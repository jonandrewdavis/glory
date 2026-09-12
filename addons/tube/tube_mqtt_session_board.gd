class_name TubeMqttSessionBoard extends RefCounted

const MqttClient := preload("./mqtt/mqtt.gd")
const MAX_PACKET_SIZE := TubeMqttTracker.MAX_PACKET_SIZE
const PING_TIMEOUT := TubeMqttTracker.PING_TIMEOUT

signal connected
signal failed
signal disconnected
signal sessions_changed

var error_message := ""
var state := WebSocketPeer.STATE_CLOSED
var connect_timeout: float = TubeTracker.CONNECT_TIMEOUT
var sessions: Dictionary[String, Dictionary] = {}

var _mqtt := MqttClient.new()
var _app_id: String
var _session_id: String
var _socket := WebSocketPeer.new()
var _subscription_id := 0
var _published := false
var _changed := false
var _connecting_time := 0.0
var _close_elapsed := 0.0
var _ping_pending := false
var _ping_elapsed := 0.0
var _send_error: Error = OK


func _init(p_app_id: String, p_session_id := "") -> void:
	_app_id = p_app_id
	_session_id = p_session_id
	_mqtt.verbose_level = 0
	_mqtt.binarymessages = true
	_mqtt.max_packet_size = MAX_PACKET_SIZE
	_mqtt.client_id = "tube" + Crypto.new().generate_random_bytes(8).hex_encode()
	_mqtt._ready()
	if is_publishing():
		_mqtt.set_last_will(session_topic(_session_id), PackedByteArray(), true, 0)
	_mqtt.broker_connected.connect(_on_broker_connected)
	_mqtt.subscription_acknowledged.connect(_on_subscribed)
	_mqtt.broker_connection_failed.connect(_on_failed.bind("MQTT broker connection failed"))
	_mqtt.broker_disconnected.connect(_on_failed.bind("MQTT broker connection closed"))
	_mqtt.received_message_details.connect(_on_message)
	_mqtt.ping_sent.connect(_on_ping_sent)
	_mqtt.ping_received.connect(_on_ping_received)
	_mqtt.send_failed.connect(_on_send_failed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_mqtt):
		_mqtt.free()


func is_publishing() -> bool:
	return not _session_id.is_empty()


func board_topic() -> String:
	return "tube/v1/sessions/%s" % _app_id.to_utf8_buffer().hex_encode()


func session_topic(p_session_id: String) -> String:
	return board_topic() + "/" + p_session_id.to_utf8_buffer().hex_encode()


## Sets the MQTT username and password sent with CONNECT. Must be called before [method connect_to_url].
func set_credentials(p_username: String, p_password: String) -> void:
	if p_username.is_empty():
		_mqtt.set_user_pass(null, null)
	else:
		_mqtt.set_user_pass(p_username, p_password)


func connect_to_url(p_url: String) -> Error:
	state = WebSocketPeer.STATE_CONNECTING
	if not (p_url.begins_with("ws://") or p_url.begins_with("wss://")):
		_on_failed("MQTT requires a ws:// or wss:// broker URL")
		return ERR_INVALID_PARAMETER
	if not _mqtt.connect_to_broker(p_url):
		_on_failed("MQTT connection failed")
		return ERR_CANT_CONNECT
	_socket = _mqtt.websocket
	return OK


func is_open() -> bool:
	return state == WebSocketPeer.STATE_OPEN


func is_close() -> bool:
	return state == WebSocketPeer.STATE_CLOSED


func close() -> void:
	if state >= WebSocketPeer.STATE_CLOSING:
		return
	if _published and is_open():
		_publish(session_topic(_session_id), PackedByteArray())
	state = WebSocketPeer.STATE_CLOSING
	_close_elapsed = 0.0


func publish_session_metadata(p_metadata: Dictionary) -> Error:
	if not is_publishing():
		return ERR_UNAVAILABLE
	if not is_open():
		return ERR_UNCONFIGURED
	var error := _publish(session_topic(_session_id), JSON.stringify(p_metadata).to_utf8_buffer())
	if error == OK:
		_published = true
	return error


func _publish(p_topic: String, p_payload: PackedByteArray) -> Error:
	if 2 + p_topic.to_utf8_buffer().size() + p_payload.size() > MAX_PACKET_SIZE:
		return ERR_OUT_OF_MEMORY
	_send_error = OK
	_mqtt.publish(p_topic, p_payload, true, 0)
	return _send_error


func _on_broker_connected() -> void:
	if state != WebSocketPeer.STATE_CONNECTING:
		return
	if _socket.get_selected_protocol() != "mqtt":
		_on_failed("Broker did not select the mqtt WebSocket protocol")
		return
	if is_publishing():
		_open()
		return
	_subscription_id = _mqtt.subscribe(board_topic() + "/+", 0)


func _on_subscribed(id: int, result: int) -> void:
	if state != WebSocketPeer.STATE_CONNECTING:
		return
	if id != _subscription_id or result != 0:
		_on_failed("MQTT broker rejected subscription")
		return
	_open()


func _open() -> void:
	state = WebSocketPeer.STATE_OPEN
	connected.emit()


func _on_failed(message: String) -> void:
	if state >= WebSocketPeer.STATE_CLOSING:
		return
	error_message = message
	close()
	failed.emit()


func _on_send_failed(error: int) -> void:
	_send_error = error


func _on_ping_sent() -> void:
	if not _ping_pending:
		_ping_pending = true
		_ping_elapsed = 0.0


func _on_ping_received() -> void:
	_ping_pending = false
	_ping_elapsed = 0.0


func _on_message(topic: String, payload: PackedByteArray, _retained: bool) -> void:
	if state >= WebSocketPeer.STATE_CLOSING or is_publishing():
		return
	var prefix := board_topic() + "/"
	if not topic.begins_with(prefix):
		return
	var hex := topic.trim_prefix(prefix)
	if hex.is_empty() or hex.length() % 2 != 0 or not hex.is_valid_hex_number(false):
		return
	var session_id := hex.hex_decode().get_string_from_utf8()
	if session_id.is_empty():
		return
	if payload.is_empty():
		_changed = sessions.erase(session_id) or _changed
		return
	var data = JSON.parse_string(payload.get_string_from_utf8())
	if not data is Dictionary:
		return
	sessions[session_id] = data
	_changed = true


func _process(delta: float) -> void:
	if is_close():
		return
	if state == WebSocketPeer.STATE_CLOSING:
		if _mqtt.brokerconnectmode != MqttClient.BCM_NOCONNECTION:
			_mqtt.disconnect_from_server()
		_socket.poll()
		_close_elapsed += delta
		if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED or _close_elapsed >= TubeTracker.CLOSE_TIMEOUT:
			state = WebSocketPeer.STATE_CLOSED
			disconnected.emit()
		return
	_mqtt._process(delta)
	if state == WebSocketPeer.STATE_CONNECTING:
		_connecting_time += delta
		if _connecting_time >= connect_timeout:
			_on_failed("MQTT connection or subscription timed out")
	if _ping_pending and state < WebSocketPeer.STATE_CLOSING:
		_ping_elapsed += delta
		if _ping_elapsed >= PING_TIMEOUT:
			_on_failed("MQTT broker did not answer ping")
	if _changed:
		_changed = false
		sessions_changed.emit()
