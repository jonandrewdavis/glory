class_name PlayerSpawner
extends MultiplayerSpawner

const ARROW_PLAYER := preload("uid://bd7kaorjlt0go")
const SPAWN_SLOTS := 8
var _serial := 0
var _players: Dictionary = {}
var _replacement_requests: Dictionary = {}

func _ready() -> void:
	spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	get_node("../RoundManager").round_ended.connect(func(_winner: int) -> void: _replacement_requests.clear())

func _on_peer_connected(peer_id: int) -> void:
	if MultiplayerService.is_host() and MultiplayerService.backend.get_joinable() and not MultiplayerService.banlist.has(MultiplayerService.backend.get_uid(peer_id)):
		spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if MultiplayerService.is_host() and not MultiplayerService.presence.keep_peer(peer_id):
		remove_player(peer_id)

## Host only.
func spawn_player(id: int) -> void:
	if get_player(id) != null or not multiplayer.is_server():
		return
	var team: int = World.scoreboard.assign_team(id)
	var index := randi() % SPAWN_SLOTS
	_serial += 1
	spawn({"peer_id": id, "team": team, "spawn_index": index,
		"position": World.respawn_manager.spawn_position(team, index),
		"revision": World.level_loader.revision, "serial": _serial,
		"protection": World.respawn_manager.settings.protection_seconds})

func _spawn_player(data: Variant) -> Node:
	var player: ArrowPlayer = ARROW_PLAYER.instantiate()
	# Unique paths prevent packets for a dead incarnation from moving its replacement.
	player.name = "%d_%d" % [data.peer_id, data.get("serial", 0)]
	player.peer_id = data.peer_id
	player.team = data.get("team", Teams.Team.BLUE)
	player.spawn_index = data.get("spawn_index", 0)
	player.authoritative_spawn = data.get("position", Vector2.ZERO)
	player.has_authoritative_spawn = data.has("position")
	player.spawn_revision = data.get("revision", 0)
	player.spawn_serial = data.get("serial", 0)
	player.spawn_protection_left = maxf(0, data.get("protection", 0.0))
	player.network_away = data.get("away", false)
	player.initial_health = data.get("health", -1.0)
	player.position = player.authoritative_spawn
	var id: int = data.peer_id
	_players[id] = player
	player.tree_exiting.connect(func() -> void:
		if _players.get(id) == player:
			_players.erase(id))
	return player

func get_player(id: int) -> ArrowPlayer:
	var player: ArrowPlayer = _players.get(id)
	return player if is_instance_valid(player) else null

func replace_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	World.respawn_manager.cancel(id)
	var player := get_player(id)
	if player and multiplayer.get_peers().has(id) and not MultiplayerService.presence.is_peer_away(id):
		# Stop the owner's old synchronizer before destroying its network path.
		_replacement_requests[id] = {"serial": player.spawn_serial, "revision": World.level_loader.revision,
			"deadline": Time.get_ticks_msec() + 5000}
		_prepare_replacement.rpc_id(id, player.spawn_serial, World.level_loader.revision)
		return
	_replace_now(id)

func _replace_now(id: int) -> void:
	_replacement_requests.erase(id)
	World.respawn_manager.cancel(id)
	var player := get_player(id)
	if player:
		remove_child(player)
		player.queue_free()
	spawn_player(id)
	var replacement := get_player(id)
	if replacement:
		replacement.set_network_away(MultiplayerService.presence.is_peer_away(id))

func _process(_delta: float) -> void:
	if not multiplayer.is_server() or not MultiplayerService.presence.enabled():
		return
	for id in _replacement_requests.keys():
		if Time.get_ticks_msec() >= int(_replacement_requests[id].deadline):
			# A silent owner must reconnect before it can send on a replaced path.
			if MultiplayerService.presence.keep_peer(id):
				MultiplayerService.presence.server_disconnected(id)
				MultiplayerService.presence.disconnect_transport(id)
				_replace_now(id)
			else:
				_replacement_requests.erase(id)
				multiplayer.multiplayer_peer.disconnect_peer(id)

## Runs before the normal peer-connected spawn handler. Preserve the living or
## dead incarnation's state, without granting health, protection, or a new team.
func restore_session(old_id: int, new_id: int) -> void:
	if _replacement_requests.has(old_id):
		_replace_now(old_id)
	var player := get_player(old_id)
	World.scoreboard.reassign_player(old_id, new_id)
	if player == null:
		return
	var remaining: float = World.respawn_manager.seconds_left(old_id)
	var data := {"peer_id": new_id, "team": player.team, "spawn_index": player.spawn_index,
		"position": player.global_position, "revision": World.level_loader.revision,
		"health": player.health.current, "protection": player.spawn_protection_left, "away": true}
	var attackers := player.recent_attackers.duplicate()
	var last_fire := player._server_last_fire_msec
	World.respawn_manager.cancel(old_id)
	_replacement_requests.erase(old_id)
	remove_child(player)
	player.queue_free()
	_serial += 1
	data.serial = _serial
	var restored := spawn(data) as ArrowPlayer
	restored.recent_attackers.assign(attackers)
	restored._server_last_fire_msec = last_fire
	if not restored.health.is_alive() and World.round_manager.phase == RoundManager.Phase.PLAYING:
		World.respawn_manager.pending[new_id] = {"player": restored, "remaining": remaining}
	for arrow in get_tree().get_nodes_in_group("projectiles"):
		if arrow.owner_id == old_id:
			arrow.owner_id = new_id

@rpc("authority", "call_remote", "reliable")
func _prepare_replacement(serial: int, revision: int) -> void:
	var player := get_player(multiplayer.get_unique_id())
	if player == null or player.spawn_serial != serial:
		return
	player.get_node("MultiplayerSynchronizer").replication_config = SceneReplicationConfig.new()
	player.set_physics_process(false)
	player.hide()
	_replacement_ready.rpc_id(1, serial, revision)

@rpc("any_peer", "call_remote", "reliable")
func _replacement_ready(serial: int, revision: int) -> void:
	if not multiplayer.is_server() or revision != World.level_loader.revision:
		return
	var id := multiplayer.get_remote_sender_id()
	var request: Dictionary = _replacement_requests.get(id, {})
	var player := get_player(id)
	if player and player.spawn_serial == serial and request.get("serial", -1) == serial and request.get("revision", -1) == revision:
		_replace_now(id)

func remove_player(id: int) -> void:
	_replacement_requests.erase(id)
	World.respawn_manager.cancel(id)
	var player := get_player(id)
	if player:
		remove_child(player)
		player.queue_free()
	World.scoreboard.remove_player(id)

func clear_players() -> void:
	_replacement_requests.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
