class_name NodeTunnelBackend
extends MultiplayerBackend

const RELAY_ADDRESS := "us-east.nodetunnel.io:8080"
const APP_ID := "0ahb6lkmhi5dtfi"
enum Phase {DISCONNECTED, AUTHENTICATING, READY, HOSTING, JOINING, IN_ROOM}

var peer: NodeTunnelPeer
var phase := Phase.DISCONNECTED
var pending_action: Callable
var joinable := false
var max_players := 0
var lobby_name := ""
var generation := 0
var pending_admissions: Array[int] = []

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_changed)
	multiplayer.peer_disconnected.connect(_on_peer_changed)
	_connect_to_relay()

func _connect_to_relay() -> void:
	peer = NodeTunnelPeer.new()
	peer.authenticated.connect(_on_authenticated.bind(generation), CONNECT_DEFERRED)
	peer.error.connect(_on_error.bind(generation), CONNECT_DEFERRED)
	peer.room_connected.connect(_on_room_connected.bind(generation), CONNECT_DEFERRED)
	peer.forced_disconnect.connect(_on_forced_disconnect.bind(generation), CONNECT_DEFERRED)
	peer.rooms_received.connect(_on_rooms_received.bind(generation), CONNECT_DEFERRED)
	peer.join_validation = _validate_join
	phase = Phase.AUTHENTICATING
	var err := peer.connect_to_relay(RELAY_ADDRESS, APP_ID)
	if err != OK:
		_fail(error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Connecting to relay...")
	var token := generation
	await get_tree().create_timer(10.0).timeout
	if token == generation and phase == Phase.AUTHENTICATING:
		_fail("Relay connection timed out.")

func _ensure_relay(action: Callable) -> void:
	match phase:
		Phase.READY:
			action.call()
		Phase.AUTHENTICATING:
			pending_action = action
		Phase.DISCONNECTED:
			pending_action = action
			_connect_to_relay()

func _on_authenticated(token: int) -> void:
	if token != generation:
		return
	phase = Phase.READY
	status_changed.emit("Relay ready")
	var action := pending_action
	pending_action = Callable()
	if action.is_valid():
		action.call()

func host_game(options: HostOptions) -> void:
	lobby_name = options.lobby_name
	max_players = options.max_players
	_ensure_relay(_host_room)

func _host_room() -> void:
	phase = Phase.HOSTING
	var err := peer.host_room(true, _encode_metadata())
	if err != OK:
		_fail(error_string(err))

func join_game(address: Variant) -> void:
	_ensure_relay(_join_room.bind(str(address).strip_edges()))

func _join_room(code: String) -> void:
	phase = Phase.JOINING
	var err := peer.join_room(code)
	if err != OK:
		_fail(error_string(err))

func _on_room_connected(token: int) -> void:
	if token != generation:
		return
	phase = Phase.IN_ROOM
	status_changed.emit("Room connected")
	lobby_joined.emit()

func fetch_lobby_list() -> void:
	_ensure_relay(_request_rooms)

func _request_rooms() -> void:
	var err := peer.get_rooms()
	if err != OK:
		status_changed.emit("Could not fetch rooms: " + error_string(err))

func _on_rooms_received(rooms: Array, token: int) -> void:
	if token != generation:
		return
	if phase == Phase.IN_ROOM:
		return
	for room in rooms:
		if not room is Dictionary or not room.get("metadata") is String or not room.get("id") is String:
			continue
		var metadata: Variant = JSON.parse_string(room.metadata)
		if metadata is Dictionary and metadata.get("name") is String and (metadata.get("cur") is float or metadata.get("cur") is int) and (metadata.get("max") is float or metadata.get("max") is int):
			lobby_found.emit(room.id, metadata.name, int(metadata.cur), int(metadata.max))

func _encode_metadata() -> String:
	return JSON.stringify({"name": lobby_name, "cur": multiplayer.get_peers().size() + 1, "max": max_players})

func _on_peer_changed(_id: int) -> void:
	if phase == Phase.IN_ROOM and multiplayer.is_server():
		if _id in multiplayer.get_peers() and not pending_admissions.is_empty():
			pending_admissions.pop_front()
		peer.update_room(_encode_metadata())

func _validate_join(_metadata: String) -> bool:
	var now := Time.get_ticks_msec()
	while not pending_admissions.is_empty() and now - pending_admissions[0] > 10000:
		pending_admissions.pop_front()
	if not joinable or multiplayer.get_peers().size() + pending_admissions.size() + 1 >= max_players:
		return false
	pending_admissions.append(now)
	return true

func set_joinable(value: bool) -> void:
	joinable = value

func get_joinable() -> bool:
	return joinable

func get_uid(peer_id: int) -> String:
	return str(peer_id)

func get_username(peer_id: int) -> String:
	return str(peer_id)

func get_lobby_address() -> String:
	return peer.room_id if peer != null and phase == Phase.IN_ROOM else ""

func _on_error(message: String, token: int) -> void:
	if token != generation:
		return
	if phase == Phase.IN_ROOM:
		push_warning(message)
	elif phase in [Phase.AUTHENTICATING, Phase.HOSTING, Phase.JOINING]:
		_fail(message)
	else:
		_reset_peer()

func _on_forced_disconnect(token: int) -> void:
	if token != generation:
		return
	var was_in_room := phase == Phase.IN_ROOM
	_reset_peer()
	if was_in_room:
		lobby_lost.emit("Disconnected from relay.")
	else:
		join_lobby_failed.emit("Relay connection lost.")

func _fail(reason: String) -> void:
	_reset_peer()
	join_lobby_failed.emit(reason)

func _reset_peer() -> void:
	generation += 1
	pending_action = Callable()
	pending_admissions.clear()
	joinable = false
	phase = Phase.DISCONNECTED
	if peer != null:
		peer.join_validation = Callable()
		peer.authenticated.disconnect(_on_authenticated.bind(generation - 1))
		peer.error.disconnect(_on_error.bind(generation - 1))
		peer.room_connected.disconnect(_on_room_connected.bind(generation - 1))
		peer.forced_disconnect.disconnect(_on_forced_disconnect.bind(generation - 1))
		peer.rooms_received.disconnect(_on_rooms_received.bind(generation - 1))
	_close_peer()
	peer = null
	status_changed.emit("Relay disconnected")

func leave_game() -> void:
	_reset_peer()
