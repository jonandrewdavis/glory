class_name PlayFlowBackend
extends MultiplayerBackend
## PlayFlow discovery + Godot WebSocket transport. Never needs a server API key.

const API_URL := "https://api.computeflow.cloud/api/v3/servers"
const PORT := 8080
const CAPACITY := 30
const PROTOCOL := "glory-playflow-1"
const CONFIG = preload("res://networking/playflow_config.tres")
const JOIN_TIMEOUT_MSEC := 90000
const POLL_SECONDS := 2.0
enum RequestKind {LIST, START, DETAILS}

var joining := false
var joinable := false
var address := ""
var request: HTTPRequest
var reservations: Dictionary = {}
var api: SceneMultiplayer
var attempt := 0
var deadline := 0
var client_key := ""
var selected_id := ""
var start_requested := false

func _ready() -> void:
	api = multiplayer as SceneMultiplayer
	api.peer_authenticating.connect(_on_authenticating)
	api.peer_authentication_failed.connect(_on_auth_failed)
	api.peer_connected.connect(func(id: int) -> void: reservations.erase(id))
	api.connected_to_server.connect(_on_connected)
	api.connection_failed.connect(_on_connection_failed)
	status_changed.emit("PlayFlow ready")

func _process(_delta: float) -> void:
	if joining and Time.get_ticks_msec() >= deadline:
		_fail("Server startup or connection timed out after 90 seconds. Try Play again shortly.")

func _configure_auth() -> void:
	api.auth_callback = _on_auth
	api.auth_timeout = 5.0

func host_game(_options: HostOptions) -> void:
	if not MultiplayerService.is_dedicated_server():
		join_lobby_failed.emit("Start the dedicated build in PlayFlow to host.")
		return
	_configure_auth()
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(PORT, "0.0.0.0")
	if error != OK:
		join_lobby_failed.emit("Cannot listen on port %d: %s" % [PORT, error_string(error)])
		return
	api.multiplayer_peer = peer
	address = "ws://127.0.0.1:%d" % PORT
	lobby_joined.emit()

func join_game(target: Variant) -> void:
	if joining:
		return
	attempt += 1
	joining = true
	deadline = Time.get_ticks_msec() + JOIN_TIMEOUT_MSEC
	selected_id = ""
	start_requested = false
	address = str(target)
	if address.begins_with("ws://") or address.begins_with("wss://"):
		_connect_url(address)
		return
	client_key = OS.get_environment("PLAYFLOW_CLIENT_KEY")
	if client_key.is_empty():
		client_key = CONFIG.client_key
	if not client_key.begins_with("pfclient_"):
		_fail("Configure PLAYFLOW_CLIENT_KEY before exporting the client.")
		return
	if address != "auto":
		selected_id = address
	status_changed.emit("Finding a server...")
	_poll_server()

func _poll_server() -> void:
	if selected_id.is_empty():
		_send_request("?include_launching=true", HTTPClient.METHOD_GET, "", RequestKind.LIST)
	else:
		_send_request("/" + selected_id.uri_encode(), HTTPClient.METHOD_GET, "", RequestKind.DETAILS)

func _send_request(path: String, method: int, body: String, kind: RequestKind) -> void:
	# Separate request objects and captured attempt IDs isolate cancelled responses.
	var pending_request := HTTPRequest.new()
	pending_request.timeout = 8.0
	add_child(pending_request)
	request = pending_request
	var token := attempt
	pending_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, response: PackedByteArray) -> void:
		if request == pending_request:
			request = null
		pending_request.queue_free()
		_on_response(result, code, response, kind, token))
	var error := pending_request.request(API_URL + path, PackedStringArray([
		"api-key: " + client_key, "Content-Type: application/json"
	]), method, body)
	if error != OK:
		request = null
		pending_request.queue_free()
		_on_response.call_deferred(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray(), kind, token)

func _poll_later() -> void:
	var token := attempt
	await get_tree().create_timer(POLL_SECONDS).timeout
	if joining and token == attempt:
		_poll_server()

func _on_response(result: int, code: int, body: PackedByteArray, kind: RequestKind, token: int) -> void:
	if not joining or token != attempt:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 429:
		# A POST timeout does not mean startup failed. Rediscover; never POST twice.
		status_changed.emit("Waiting for PlayFlow... Checking server status.")
		_poll_later()
		return
	if code < 200 or code >= 300:
		var detail := str(data.get("error", "")).to_lower() if data is Dictionary else ""
		if kind == RequestKind.START and (code == 409 or "limit" in detail or "active server" in detail):
			status_changed.emit("Another player may be starting the server. Waiting...")
			_poll_later()
		elif code in [401, 403]:
			_fail("PlayFlow rejected the client key or startup permission. Check the project's client key.")
		elif kind == RequestKind.START:
			_fail("PlayFlow could not start the server (HTTP %d). Check that a ready 'default' build and TCP 8080/TLS port are configured." % code)
		else:
			_fail("PlayFlow server is unavailable (HTTP %d). Try Play again." % code)
		return
	if kind == RequestKind.START:
		if data is Dictionary:
			selected_id = str(data.get("instance_id", ""))
		status_changed.emit("Server starting... This usually takes 10–30 seconds.")
		_poll_later()
	elif kind == RequestKind.DETAILS:
		if not data is Dictionary:
			_fail("PlayFlow returned invalid server details.")
		else:
			_handle_server(data)
	else:
		_handle_list(data)

func _handle_list(data: Variant) -> void:
	if not data is Dictionary or not data.get("servers") is Array:
		_fail("PlayFlow returned an invalid server list.")
		return
	# Prefer running over launching; never provision because an existing one is full.
	for state in ["running", "launching"]:
		for server in data.servers:
			if server is Dictionary and server.get("status") == state:
				selected_id = str(server.get("instance_id", ""))
				_handle_server(server)
				return
	if start_requested:
		_poll_later()
		return
	start_requested = true
	status_changed.emit("Starting a server...")
	_send_request("/start", HTTPClient.METHOD_POST, JSON.stringify({
		"name": "glory", "region": "us-east", "compute_size": "small",
		"ttl": 3600, "version_tag": "default",
		# Explicit port so the project needs no dashboard port setup; the web client requires TLS.
		"port_configs": [{"name": "godot_websocket", "internal_port": PORT, "protocol": "tcp", "tls_enabled": true}]
	}), RequestKind.START)

func _handle_server(server: Dictionary) -> void:
	match str(server.get("status", "")):
		"running":
			var url := server_url(server)
			if url.is_empty():
				_fail("Server has no secure WebSocket endpoint. Configure TCP 8080 with TLS in PlayFlow and restart it.")
			else:
				_connect_url(url)
		"launching":
			status_changed.emit("Server starting... This usually takes 10–30 seconds.")
			_poll_later()
		_:
			_fail("Server stopped or failed during startup. Check the PlayFlow server logs, then try Play again.")

static func server_url(server: Dictionary) -> String:
	var ports: Variant = server.get("network_ports", [])
	if not ports is Array:
		return ""
	for port in ports:
		if not port is Dictionary:
			continue
		if str(port.get("protocol", "")).to_lower() != "tcp" or not port.get("tls_enabled", false):
			continue
		if int(port.get("internal_port", 0)) != PORT:
			continue
		var host := str(port.get("host", ""))
		var external := int(port.get("external_port", 0))
		if not host.is_empty() and external > 0 and external <= 65535:
			return "wss://%s:%d" % [host, external]
	return ""

func _connect_url(url: String) -> void:
	if OS.has_feature("web") and not url.begins_with("wss://"):
		_fail("The web client requires a secure wss:// address.")
		return
	_configure_auth()
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(url)
	if error != OK:
		_fail("Could not connect: " + error_string(error))
		return
	address = url
	api.multiplayer_peer = peer
	status_changed.emit("Connecting to PlayFlow...")

func _on_authenticating(id: int) -> void:
	if not api.is_server():
		api.send_auth(id, PROTOCOL.to_utf8_buffer())

func _on_auth(id: int, data: PackedByteArray) -> void:
	if api.is_server():
		if reservations.has(id):
			return
		var reason := ""
		if data.get_string_from_utf8() != PROTOCOL:
			reason = "Client/server version mismatch. Refresh the game."
		elif not joinable:
			reason = "Server is loading. Try again shortly."
		elif api.get_peers().size() + reservations.size() >= CAPACITY:
			reason = "Server is full (30/30 players)."
		if not reason.is_empty():
			api.send_auth(id, reason.to_utf8_buffer())
			# Leave time to deliver the reason; auth_timeout disconnects non-cooperative clients.
			return
		reservations[id] = true
		api.send_auth(id, "OK".to_utf8_buffer())
		api.complete_auth(id)
	elif id == 1 and joining:
		if data.get_string_from_utf8() == "OK":
			api.complete_auth(id)
		else:
			_fail_for_attempt.call_deferred(data.get_string_from_utf8(), attempt)

func _on_auth_failed(id: int) -> void:
	reservations.erase(id)
	if joining:
		_fail_for_attempt.call_deferred("PlayFlow admission timed out or the server disconnected.", attempt)

func _fail_for_attempt(reason: String, token: int) -> void:
	if token == attempt:
		_fail(reason)

func _on_connected() -> void:
	if joining:
		joining = false
		attempt += 1
		lobby_joined.emit()

func _on_connection_failed() -> void:
	if joining:
		_fail("Could not connect to PlayFlow. The free instance may have expired.")

func _fail(reason: String) -> void:
	if not joining:
		return
	joining = false
	attempt += 1
	_cancel_request()
	join_lobby_failed.emit(reason)

func _cancel_request() -> void:
	if is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	request = null

func leave_game() -> void:
	joining = false
	attempt += 1
	joinable = false
	_cancel_request()
	_close_peer()
	if api:
		api.auth_callback = Callable()
		api.auth_timeout = 3.0
	reservations.clear()

func fetch_lobby_list() -> void:
	listing_started.emit()
	status_changed.emit("Use Play to start or join the dedicated server.")

func set_joinable(value: bool) -> void:
	joinable = value
	if value:
		print("PlayFlow ready: TCP %d, %d player slots (15 vs 15)" % [PORT, CAPACITY])

func get_joinable() -> bool:
	return joinable

func get_uid(id: int) -> String:
	return str(id)

func get_username(id: int) -> String:
	return str(id)

func get_lobby_address() -> String:
	return address
