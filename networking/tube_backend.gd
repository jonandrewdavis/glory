class_name TubeBackend
extends MultiplayerBackend

const CONTEXT: TubeContext = preload("uid://334o3kg81fih")
const TRACKER_TIMEOUT := 5.0
const LOST_REASON := "Disconnected from host."
enum Phase {IDLE, HOSTING, JOINING, IN_SESSION}

var client: TubeClient
var phase := Phase.IDLE
var joinable := false
var max_players := 0
var lobby_name := ""
var leaving := false
var listing := false
var listing_ready := false

func _ready() -> void:
	client = TubeClient.new()
	client.context = CONTEXT
	client.tracker_connect_timeout = TRACKER_TIMEOUT
	client.multiplayer_api = get_tree().get_multiplayer()
	client.session_created.connect(_on_session_created)
	client.session_joined.connect(_on_session_joined)
	client.session_left.connect(_on_session_left)
	client.error_raised.connect(_on_error)
	client.public_sessions_changed.connect(_emit_sessions)
	client.listing_stopped.connect(_on_listing_stopped)
	client.listing_started.connect(_on_listing_started)
	add_child(client)
	multiplayer.peer_connected.connect(_on_peer_changed)
	multiplayer.peer_disconnected.connect(_on_peer_changed)
	status_changed.emit("Tube ready" if TubeClient.is_webrtc_available() else "WebRTC extension missing; install addons/webrtc_native.")

func host_game(options: HostOptions) -> void:
	lobby_name = options.lobby_name
	max_players = options.max_players
	_stop_listing()
	phase = Phase.HOSTING
	client.create_session()
	if phase != Phase.HOSTING:
		return
	client.refuse_new_connections = true
	status_changed.emit("Creating session...")

func join_game(address: Variant) -> void:
	_stop_listing()
	phase = Phase.JOINING
	client.join_session(str(address).strip_edges())
	if phase == Phase.JOINING:
		status_changed.emit("Connecting to session...")

func _on_session_created() -> void:
	if phase != Phase.HOSTING:
		return
	phase = Phase.IN_SESSION
	status_changed.emit("Session code: " + client.session_id)
	lobby_joined.emit()

func _on_session_joined() -> void:
	if phase != Phase.JOINING:
		return
	phase = Phase.IN_SESSION
	status_changed.emit("Session joined")
	lobby_joined.emit()

func _on_session_left() -> void:
	if leaving:
		return
	var was_in_session := phase == Phase.IN_SESSION
	phase = Phase.IDLE
	joinable = false
	if was_in_session:
		lobby_lost.emit(LOST_REASON)

func _on_error(code: TubeClient.SessionError, message: String) -> void:
	match code:
		TubeClient.SessionError.CREATE_SESSION_FAILED:
			if phase == Phase.HOSTING:
				_fail(message)
		TubeClient.SessionError.JOIN_SESSION_FAILED:
			if phase == Phase.JOINING:
				_fail(message)
		TubeClient.SessionError.LIST_SESSIONS_FAILED:
			listing = false
			listing_ready = false
			status_changed.emit("Session list unavailable (broker unreachable).")
		TubeClient.SessionError.ONLINE_SIGNALING_FAILED:
			status_changed.emit("Broker unreachable; session is LAN-only.")
		_:
			status_changed.emit(message)

func _fail(reason: String) -> void:
	phase = Phase.IDLE
	joinable = false
	join_lobby_failed.emit(reason)

func _on_peer_changed(peer_id: int) -> void:
	if phase != Phase.IN_SESSION or not client.is_server:
		return
	var peers := multiplayer.get_peers()
	if peer_id in peers and peers.size() + 1 > max_players:
		client.kick_peer.call_deferred(peer_id)
	_update_admission()
	if joinable:
		# Deferred so peer_count in TubeClient._publish_metadata sees the settled peer list.
		client.publish_session.call_deferred(_lobby_metadata())

func _update_admission() -> void:
	if client.is_server and client.state != TubeClient.State.IDLE:
		client.refuse_new_connections = not joinable or multiplayer.get_peers().size() + 1 >= max_players

func set_joinable(value: bool) -> void:
	joinable = value
	_update_admission()
	if phase == Phase.IN_SESSION and client.is_server:
		if value:
			client.publish_session(_lobby_metadata())
		else:
			client.unpublish_session()

func _lobby_metadata() -> Dictionary:
	return {"name": lobby_name, "max": max_players}

func get_joinable() -> bool:
	return joinable

func fetch_lobby_list() -> void:
	if phase != Phase.IDLE:
		return
	if listing:
		if listing_ready:
			listing_started.emit()
		_emit_sessions()
	else:
		listing = true
		client.list_sessions()

func _emit_sessions() -> void:
	if phase != Phase.IDLE:
		return
	var sessions := client.get_public_sessions()
	for id: String in sessions:
		var metadata: Dictionary = sessions[id]
		if metadata.get("name") is String and (metadata.get("peer_count") is float or metadata.get("peer_count") is int) and (metadata.get("max") is float or metadata.get("max") is int):
			lobby_found.emit(id, metadata.name, int(metadata.peer_count), int(metadata.max))

func _on_listing_started() -> void:
	listing_ready = true
	listing_started.emit()

func _on_listing_stopped() -> void:
	listing = false
	listing_ready = false

func _stop_listing() -> void:
	listing = false
	listing_ready = false
	client.stop_listing_sessions()

func get_uid(peer_id: int) -> String:
	return str(peer_id)

func get_username(peer_id: int) -> String:
	return str(peer_id)

func get_lobby_address() -> String:
	return client.session_id

func leave_game() -> void:
	_stop_listing()
	phase = Phase.IDLE
	joinable = false
	if client.state != TubeClient.State.IDLE:
		leaving = true
		client.leave_session()
		leaving = false
