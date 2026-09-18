extends Node
## Two processes: -- --server [--listen-host] and -- --client.
const PORT := 19738
var started := 0
var stage := 0
var failures := 0
var old_serial := -1
var old_revision := -1
var finished := false

func _ready() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func _run() -> void:
	started = Time.get_ticks_msec()
	MultiplayerService.set_backend(MultiplayerService.BackendType.ENET, false)
	var peer := ENetMultiplayerPeer.new()
	if "--server" in OS.get_cmdline_user_args():
		assert(peer.create_server(PORT, 4) == OK)
		multiplayer.multiplayer_peer = peer
		MultiplayerService.in_lobby = true
		MultiplayerService.backend.joinable = true
		await World.level_loader.spawn_level("Fortress2")
		World.creep_spawner.set_physics_process(false)
		World.creep_spawner.clear_creeps()
		if "--listen-host" in OS.get_cmdline_user_args():
			World.player_spawner.spawn_player(1)
			World.player_spawner.get_player(1).set_physics_process(false)
		else:
			# A roster-only Blue teammate makes the joining player Orange.
			World.scoreboard.entries[99] = {"team": Teams.Team.BLUE, "kills": 0, "deaths": 0, "assists": 0}
		push_ram_to(-608)
		print("RESPAWN_SERVER_READY")
	else:
		assert(peer.create_client("127.0.0.1", PORT) == OK)
		multiplayer.multiplayer_peer = peer

func push_ram_to(x: float) -> void:
	var ram := get_tree().get_first_node_in_group("fortress_rams") as BatteringRam
	ram.set_physics_process(false)
	var previous := ram.distance
	ram.distance = ram.route_distance_at(Vector2(x, -32))
	ram.route_advanced.emit(previous, ram.distance, -1)

func _process(_delta: float) -> void:
	if started == 0 or finished:
		return
	if Time.get_ticks_msec() - started > 20000:
		push_error("Respawn network check timed out at stage %d" % stage)
		get_tree().quit(1)
	if multiplayer.is_server() or not World.level_loader.is_level_ready():
		return
	var manager := World.respawn_manager
	var player := World.player_spawner.get_player(multiplayer.get_unique_id())
	var band := manager.active_band(Teams.Team.ORANGE)
	if player == null or band == null:
		return
	player.set_physics_process(false)
	if stage == 0 and band.order == 4:
		expect(player.team == Teams.Team.ORANGE, "Joining player is Orange")
		expect(band.bounds.has_point(band.to_local(player.global_position)), "Late join spawns in captured central band")
		expect(player.global_position.distance_to(player.authoritative_spawn) < 12, "Client applies the server-selected spawn position")
		expect(player.is_spawn_protected(), "Spawn protection reaches joining client")
		old_serial = player.spawn_serial
		stage = 1
		_ack_join.rpc_id(1)
	elif stage == 1 and not player.health.is_alive() and manager.seconds_left(player.peer_id) > 0:
		expect(manager.seconds_left(player.peer_id) <= 2.0, "Client receives server countdown for its dead incarnation")
		stage = 2
		_ack_death.rpc_id(1)
	elif stage == 2 and player.spawn_serial != old_serial and player.health.is_alive() and band.order == 3:
		expect(band.bounds.has_point(band.to_local(player.global_position)), "Remote Orange respawns in band captured during its countdown")
		expect(manager.seconds_left(player.peer_id) == 0, "Old countdown does not attach to replacement player")
		expect(World.scoreboard.entries[player.peer_id].deaths == 1, "Death count survives network replacement")
		expect(player.is_spawn_protected(), "Replacement protection is replicated")
		old_revision = World.level_loader.revision
		old_serial = player.spawn_serial
		stage = 3
		_ack_respawn.rpc_id(1, player.global_position)
	elif stage == 3 and World.level_loader.revision > old_revision and player.spawn_serial != old_serial and band.order == 5:
		expect(band.bounds.has_point(band.to_local(player.global_position)), "Map reload places client at reset outpost")
		expect(manager.seconds_left(player.peer_id) == 0, "Map reload cancels old death timer")
		var owners := manager.owners.duplicate()
		manager._sync_state(old_revision, {}, {})
		expect(manager.owners == owners, "Client ignores stale level snapshots")
		stage = 4
		old_serial = player.spawn_serial
		_ack_reload.rpc_id(1)
	elif stage == 4 and player.team == Teams.Team.BLUE and player.spawn_serial != old_serial:
		var blue_band := manager.active_band(Teams.Team.BLUE)
		expect(blue_band.bounds.has_point(blue_band.to_local(player.global_position)), "Living team switch uses the new team's active band")
		old_revision = World.level_loader.revision
		old_serial = player.spawn_serial
		stage = 5
		_ack_switch.rpc_id(1)
	elif stage == 5 and World.level_loader.revision > old_revision and player.spawn_serial != old_serial:
		var blue_band := manager.active_band(Teams.Team.BLUE)
		expect(blue_band.order == 2 and blue_band.bounds.has_point(blue_band.to_local(player.global_position)), "Round restart resets and relocates living remote players")
		expect(World.round_manager.wins_for(Teams.Team.BLUE) == 1, "Round score survives respawn reset")
		stage = 6
		_finish_request.rpc_id(1, failures)

func kill_peer(id: int) -> void:
	var player := World.player_spawner.get_player(id)
	player.end_spawn_protection()
	var attacker := ArrowPlayer.new()
	attacker.team = Teams.Team.BLUE
	attacker.peer_id = 1 if "--listen-host" in OS.get_cmdline_user_args() else 99
	player.health.take_damage(player.health.current, attacker)
	attacker.free()

@rpc("any_peer", "call_remote", "reliable")
func _ack_join() -> void:
	if multiplayer.is_server():
		kill_peer(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func _ack_death() -> void:
	if multiplayer.is_server():
		push_ram_to(-800)

@rpc("any_peer", "call_remote", "reliable")
func _ack_respawn(client_position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var player := World.player_spawner.get_player(id)
	expect(World.respawn_manager.bands[2].bounds.has_point(World.respawn_manager.bands[2].to_local(player.global_position)), "Server and client agree on respawn band (server %s, client %s, spawn %s)" % [player.global_position, client_position, player.authoritative_spawn])
	kill_peer(id)
	await World.level_loader.spawn_level("Fortress2")
	World.creep_spawner.set_physics_process(false)
	World.creep_spawner.clear_creeps()
	(get_tree().get_first_node_in_group("fortress_rams") as BatteringRam).set_physics_process(false)

@rpc("any_peer", "call_remote", "reliable")
func _ack_reload() -> void:
	if multiplayer.is_server():
		World.scoreboard._server_switch(multiplayer.get_remote_sender_id(), Teams.Team.BLUE)

@rpc("any_peer", "call_remote", "reliable")
func _ack_switch() -> void:
	if not multiplayer.is_server():
		return
	for gate in get_tree().get_nodes_in_group("fortress_gates"):
		if gate.team == Teams.Team.ORANGE:
			World.round_manager._on_gate_died(null, gate)
			break

@rpc("any_peer", "call_remote", "reliable")
func _finish_request(client_failures: int) -> void:
	if not multiplayer.is_server():
		return
	failures += client_failures
	finished = true
	_finish.rpc(failures)
	print("RESPAWN_NETWORK_PASSED" if failures == 0 else "RESPAWN_NETWORK_FAILED")
	await get_tree().create_timer(0.3).timeout
	World.clear()
	get_tree().quit(1 if failures else 0)

@rpc("authority", "call_remote", "reliable")
func _finish(server_failures: int) -> void:
	finished = true
	print("RESPAWN_CLIENT_PASSED" if server_failures == 0 else "RESPAWN_CLIENT_FAILED")
	get_tree().quit(1 if server_failures else 0)
