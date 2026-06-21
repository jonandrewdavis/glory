extends Node

enum BackendType {ENET, NODETUNNEL}
const BACKEND_SCRIPTS := {BackendType.ENET: preload("res://networking/enet_backend.gd"), BackendType.NODETUNNEL: preload("res://networking/nodetunnel_backend.gd")}
const BACKEND_LABELS := {BackendType.ENET: "LAN (ENet)", BackendType.NODETUNNEL: "Online (NodeTunnel)"}
const CONFIG_SECTION := "multiplayer"
const CONFIG_KEY_BACKEND := "backend"
const DISCONNECT_REASON := "Disconnected from the host."
const KICK_REASON_KICKED := "You were kicked."
const KICK_REASON_BANNED := "You are banned from this lobby."

signal lobby_found(address: Variant, lobby_name: String, cur_players: int, max_players: int)
signal creating_lobby
signal joining_lobby
signal lobby_joined
signal join_lobby_failed(reason: String)
signal game_exited
signal backend_changed(type: BackendType)
signal status_changed(text: String)

var backend: MultiplayerBackend
var backend_type: BackendType
var banlist: Array = []
var kick_reason := ""
var status_text := ""
var in_lobby := false
var pending := false
var leaving := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var saved: Variant = GGT_GameConfig.config.get_value(CONFIG_SECTION, CONFIG_KEY_BACKEND, BackendType.ENET)
	set_backend(saved if saved is int and BACKEND_SCRIPTS.has(saved) else BackendType.ENET)

func set_backend(type: BackendType, persist_choice := true) -> void:
	if in_lobby or pending or not BACKEND_SCRIPTS.has(type):
		return
	if backend != null:
		backend.shutdown()
		backend.free()
	backend_type = type
	backend = BACKEND_SCRIPTS[type].new()
	backend.lobby_found.connect(lobby_found.emit)
	backend.lobby_joined.connect(_on_lobby_joined)
	backend.join_lobby_failed.connect(_on_join_lobby_failed)
	backend.lobby_lost.connect(_end_game)
	backend.status_changed.connect(_on_status_changed)
	add_child(backend)
	if persist_choice:
		GGT_GameConfig.config.set_value(CONFIG_SECTION, CONFIG_KEY_BACKEND, type)
		GGT_GameConfig.persist()
	backend_changed.emit(type)

func _on_status_changed(text: String) -> void:
	status_text = text
	status_changed.emit(text)

func host_game(options: HostOptions) -> void:
	if in_lobby or pending:
		return
	kick_reason = ""
	pending = true
	creating_lobby.emit()
	if options.max_players < 1 or options.max_players > 4:
		_on_join_lobby_failed("Choose between 1 and 4 players.")
	elif options.max_players == 1:
		backend.shutdown()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_on_lobby_joined()
	else:
		backend.host_game(options)

func join_game(address: Variant) -> void:
	if in_lobby or pending:
		return
	kick_reason = ""
	pending = true
	joining_lobby.emit()
	if str(address).strip_edges().is_empty() or str(address).to_utf8_buffer().size() > 256:
		_on_join_lobby_failed("Enter a valid " + backend.get_address_hint().to_lower() + ".")
		return
	backend.join_game(address)

func _on_lobby_joined() -> void:
	if not pending:
		return
	pending = false
	in_lobby = true
	lobby_joined.emit()

func _on_join_lobby_failed(reason: String) -> void:
	if not pending:
		_on_status_changed(reason)
		return
	pending = false
	backend.shutdown()
	join_lobby_failed.emit(reason)

func leave_game() -> void:
	if leaving:
		return
	leaving = true
	var was_in_lobby := in_lobby
	in_lobby = false
	pending = false
	backend.shutdown()
	banlist.clear()
	if was_in_lobby:
		game_exited.emit()
	backend.leave_game()
	leaving = false

func _end_game(reason: String) -> void:
	if not in_lobby:
		return
	if kick_reason.is_empty():
		kick_reason = reason
	leave_game()

func _on_server_disconnected() -> void:
	if pending:
		_on_join_lobby_failed(DISCONNECT_REASON)
	else:
		_end_game(DISCONNECT_REASON)

func fetch_lobby_list() -> void:
	if not in_lobby and not pending:
		backend.fetch_lobby_list()

func set_joinable(value: bool) -> void:
	if is_host() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		backend.set_joinable(value)

func is_host() -> bool:
	return in_lobby and multiplayer.is_server()

func get_lobby_address() -> String:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return "Offline"
	return backend.get_lobby_address()

func kick_player(peer_id: int) -> void:
	if is_host() and peer_id != multiplayer.get_unique_id():
		_kick_player_rpc.rpc_id(peer_id, backend.get_uid(peer_id) not in banlist)

@rpc("authority", "call_remote", "reliable")
func _kick_player_rpc(kicked: bool) -> void:
	kick_reason = KICK_REASON_KICKED if kicked else KICK_REASON_BANNED
	leave_game()

func ban_player(peer_id: int) -> void:
	if is_host() and peer_id != multiplayer.get_unique_id():
		banlist.append(backend.get_uid(peer_id))
		kick_player(peer_id)

func _on_peer_connected(peer_id: int) -> void:
	if is_host() and (not backend.get_joinable() or banlist.has(backend.get_uid(peer_id))):
		kick_player(peer_id)

func get_username(peer_id: int) -> String:
	return backend.get_username(peer_id)
