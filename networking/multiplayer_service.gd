extends Node

enum BackendType {ENET, NODETUNNEL, TUBE, PLAYFLOW}
const BACKEND_SCRIPTS := {BackendType.PLAYFLOW: preload("res://networking/playflow_backend.gd"), BackendType.TUBE: preload("res://networking/tube_backend.gd"), BackendType.ENET: preload("res://networking/enet_backend.gd")}
const BACKEND_LABELS := {BackendType.PLAYFLOW: "PlayFlow (Dedicated)", BackendType.TUBE: "Online (Tube P2P)", BackendType.ENET: "ENet (Localhost)"}
const BACKEND_ADDRESS_HINTS := {BackendType.PLAYFLOW: "auto or WebSocket URL", BackendType.TUBE: "Session code", BackendType.ENET: "IP address", BackendType.NODETUNNEL: "Room code"}
const CONFIG_SECTION := "multiplayer"
const CONFIG_KEY_BACKEND := "backend"
const DISCONNECT_REASON := "Disconnected from the host."
const KICK_REASON_KICKED := "You were kicked."
const KICK_REASON_BANNED := "You are banned from this lobby."
const MAX_PLAYERS := 30

signal lobby_found(address: Variant, lobby_name: String, cur_players: int, max_players: int)
signal creating_lobby
signal joining_lobby
signal lobby_joined
signal join_lobby_failed(reason: String)
signal game_exited
signal backend_changed(type: BackendType)
signal status_changed(text: String)
signal listing_started
signal username_changed(peer_id: int)

var backend: MultiplayerBackend
var backend_type: BackendType
var banlist: Array = []
var usernames: Dictionary[int, String] = {}
var kick_reason := ""
var status_text := ""
var in_lobby := false
var pending := false
var leaving := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(peer_id: int) -> void: usernames.erase(peer_id))
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	GGT_GameConfig.username_changed.connect(func(_value: String) -> void: _submit_local_username())
	if is_dedicated_server():
		set_backend(BackendType.PLAYFLOW, false)
		_start_dedicated.call_deferred()
		return
	var saved: Variant = GGT_GameConfig.config.get_value(CONFIG_SECTION, CONFIG_KEY_BACKEND, BackendType.ENET)
	set_backend(saved if saved is int and BACKEND_SCRIPTS.has(saved) else BackendType.ENET)

func is_dedicated_server() -> bool:
	return OS.has_feature("dedicated_server") or "--playflow-server" in OS.get_cmdline_user_args()

func _start_dedicated() -> void:
	join_lobby_failed.connect(func(reason: String) -> void:
		push_error(reason)
		get_tree().quit(1))
	var options := HostOptions.new()
	options.max_players = 30
	options.lobby_name = "PlayFlow 15 vs 15"
	host_game(options)

func set_backend(type: BackendType, persist_choice := true) -> void:
	if in_lobby or pending or not BACKEND_SCRIPTS.has(type):
		return
	if backend != null:
		backend.leave_game()
		backend.free()
	backend_type = type
	backend = BACKEND_SCRIPTS[type].new()
	backend.lobby_found.connect(lobby_found.emit)
	backend.lobby_joined.connect(_on_lobby_joined)
	backend.join_lobby_failed.connect(_on_join_lobby_failed)
	backend.lobby_lost.connect(_end_game)
	backend.status_changed.connect(_on_status_changed)
	backend.listing_started.connect(listing_started.emit)
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
	if options.max_players < 1 or options.max_players > MAX_PLAYERS:
		_on_join_lobby_failed("Choose between 1 and %d players." % MAX_PLAYERS)
	elif options.max_players == 1:
		backend.leave_game()
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
		_on_join_lobby_failed("Enter a valid " + get_address_hint().to_lower() + ".")
		return
	backend.join_game(address)

func _on_lobby_joined() -> void:
	if not pending:
		return
	pending = false
	in_lobby = true
	_submit_local_username()
	lobby_joined.emit()

func _on_join_lobby_failed(reason: String) -> void:
	if not pending:
		_on_status_changed(reason)
		return
	pending = false
	backend.leave_game()
	join_lobby_failed.emit(reason)

func leave_game() -> void:
	if leaving:
		return
	leaving = true
	var was_in_lobby := in_lobby
	in_lobby = false
	pending = false
	backend.leave_game()
	banlist.clear()
	usernames.clear()
	if was_in_lobby:
		game_exited.emit()
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

func get_address_hint() -> String:
	return BACKEND_ADDRESS_HINTS[backend_type]

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
	return usernames.get(peer_id, backend.get_username(peer_id))

func _submit_local_username() -> void:
	if not in_lobby or is_dedicated_server():
		return
	if multiplayer.is_server():
		_register_username(multiplayer.get_unique_id(), GGT_GameConfig.get_username())
	else:
		_submit_username.rpc_id(1, GGT_GameConfig.get_username())

## Server: stores a peer's name and tells everyone, the new peer also gets the full table.
@rpc("any_peer", "call_remote", "reliable")
func _submit_username(username: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var known := usernames.has(peer_id)
	_register_username(peer_id, username)
	if not known:
		_receive_usernames.rpc_id(peer_id, usernames)

func _register_username(peer_id: int, username: String) -> void:
	username = GGT_GameConfig.sanitize_username(username)
	if username.is_empty() or usernames.get(peer_id, "") == username:
		return
	_receive_usernames({peer_id: username})
	_receive_usernames.rpc({peer_id: username})

@rpc("authority", "call_remote", "reliable")
func _receive_usernames(names: Dictionary) -> void:
	for peer_id: int in names:
		usernames[peer_id] = GGT_GameConfig.sanitize_username(str(names[peer_id]))
		username_changed.emit(peer_id)
