class_name ENetBackend
extends MultiplayerBackend

const GAME_PORT := 3005
const SEARCH_PORT := 3006
const BROADCAST_ADDRESS := "255.255.255.255"
const GREETING_MESSAGE := "Anyone there?"

var search_server := UDPServer.new()
var search_peer := PacketPeerUDP.new()
var max_players := 0
var lobby_name := ""
var joining := false
var joinable := false

func _ready() -> void:
	(multiplayer as SceneMultiplayer).peer_authenticating.connect(_authenticating)
	search_peer.set_broadcast_enabled(true)
	search_peer.set_dest_address(BROADCAST_ADDRESS, SEARCH_PORT)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	status_changed.emit("LAN ready")

func _process(_delta: float) -> void:
	if search_server.is_listening():
		search_server.poll()
		while search_server.is_connection_available():
			var remote := search_server.take_connection()
			remote.get_packet()
			remote.put_packet(("%s,%d,%d" % [lobby_name, multiplayer.get_peers().size() + 1, max_players]).to_utf8_buffer())
	while search_peer.get_available_packet_count() > 0:
		var packet := search_peer.get_packet().get_string_from_utf8().split(",")
		var address := search_peer.get_packet_ip()
		if packet.size() in [3, 4] and packet[1].is_valid_int() and packet[2].is_valid_int():
			lobby_found.emit(address, packet[0], int(packet[1]), int(packet[2]))

func host_game(options: HostOptions) -> void:
	_configure_auth()
	max_players = options.max_players
	lobby_name = options.lobby_name.replace(",", "")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, max_players - 1)
	if err != OK:
		join_lobby_failed.emit(error_string(err))
		return
	peer.refuse_new_connections = true
	multiplayer.multiplayer_peer = peer
	lobby_joined.emit()

func join_game(address: Variant) -> void:
	_configure_auth()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(str(address), GAME_PORT)
	if err != OK:
		join_lobby_failed.emit(error_string(err))
		return
	joining = true
	multiplayer.multiplayer_peer = peer

func _on_connected() -> void:
	if joining:
		joining = false
		lobby_joined.emit()

func _configure_auth() -> void:
	var api := multiplayer as SceneMultiplayer
	api.auth_callback = _authenticate
	api.auth_timeout = 5.0

func _authenticating(id: int) -> void:
	(multiplayer as SceneMultiplayer).send_auth(id, CombatNetwork.PROTOCOL.to_utf8_buffer())

func _authenticate(id: int, data: PackedByteArray) -> void:
	if data == CombatNetwork.PROTOCOL.to_utf8_buffer():
		(multiplayer as SceneMultiplayer).complete_auth(id)
	else:
		multiplayer.multiplayer_peer.disconnect_peer(id)

func _on_connection_failed() -> void:
	if joining:
		joining = false
		join_lobby_failed.emit("Could not reach host.")

func leave_game() -> void:
	joining = false
	joinable = false
	search_server.stop()
	_close_peer()

func fetch_lobby_list() -> void:
	search_peer.put_packet(GREETING_MESSAGE.to_utf8_buffer())
	listing_started.emit()

func set_joinable(value: bool) -> void:
	joinable = value
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.refuse_new_connections = not value
	if value and not search_server.is_listening():
		var err := search_server.listen(SEARCH_PORT)
		if err != OK:
			status_changed.emit("LAN discovery unavailable; join by IP address.")
	elif not value:
		search_server.stop()

func get_joinable() -> bool:
	return joinable

func get_uid(peer_id: int) -> String:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and peer_id != multiplayer.get_unique_id():
		var remote := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(peer_id)
		if remote:
			return remote.get_remote_address()
	return str(peer_id)

func get_username(peer_id: int) -> String:
	return str(peer_id)

func get_lobby_address() -> String:
	for address in IP.get_local_addresses():
		var parts := address.split(".")
		if parts.size() == 4 and (address.begins_with("10.") or address.begins_with("192.168.") or (parts[0] == "172" and int(parts[1]) >= 16 and int(parts[1]) <= 31)):
			return address
	return "127.0.0.1"
