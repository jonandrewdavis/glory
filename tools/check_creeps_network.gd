extends Node
## Run this scene in two processes with -- --server and -- --client.
## Optional --listen-host also creates a player on the server.

const PORT := 19736
var _started := 0
var _stage := 0
var _listen_host := false
var _victim_name := ""
var _old_names: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_started = Time.get_ticks_msec()
	MultiplayerService.set_backend(MultiplayerService.BackendType.ENET, false)
	_listen_host = "--listen-host" in OS.get_cmdline_user_args()
	var peer := ENetMultiplayerPeer.new()
	if "--server" in OS.get_cmdline_user_args():
		assert(peer.create_server(PORT, 4) == OK)
		multiplayer.multiplayer_peer = peer
		MultiplayerService.in_lobby = true
		MultiplayerService.backend.joinable = true
		await World.level_loader.spawn_level("Fortress1")
		await get_tree().physics_frame
		await get_tree().physics_frame
		World.creep_spawner.set_physics_process(false)
		if _listen_host:
			World.player_spawner.spawn_player(1)
		var creeps := get_tree().get_nodes_in_group("creeps")
		assert(creeps.size() == 6)
		# Prepare a live combat encounter before a client joins.
		for creep: Creep in creeps:
			creep.position = Vector2(-8 if creep.team == Teams.Team.BLUE else 8, 80)
			creep.set_physics_process(false)
			_old_names.append(str(creep.name))
		var blue: Creep = creeps[0]
		var orange: Creep = creeps[3]
		orange.health.take_damage(35, blue)
		orange.state = Creep.State.ATTACK
		orange.visual_animation = &"attack"
		orange.visual_frame = 3
		_victim_name = str(orange.name)
		print("NETWORK_SERVER_READY")
	else:
		assert(peer.create_client("127.0.0.1", PORT) == OK)
		multiplayer.multiplayer_peer = peer

func _process(_delta: float) -> void:
	if _started == 0:
		return
	if Time.get_ticks_msec() - _started > 20000:
		print("Network state: server=", multiplayer.is_server(), " peers=", multiplayer.get_peers(), " level=", World.level_loader.current_key,
			" revision=", World.level_loader.revision, " ready=", World.level_loader.is_level_ready(), " ready_peers=", World.level_loader.ready_peers,
			" creeps=", get_tree().get_nodes_in_group("creeps").size())
		for creep: Creep in get_tree().get_nodes_in_group("creeps"):
			print(creep.name, " ", creep.health.current, " ", creep.state, " ", creep.visual_animation)
		push_error("Creep network check timed out at stage %d" % _stage)
		get_tree().quit(1)
	if multiplayer.is_server():
		return
	var creeps := get_tree().get_nodes_in_group("creeps")
	if not World.level_loader.is_level_ready():
		for creep: Creep in creeps:
			if creep.visible:
				push_error("Creep visible before level readiness")
				get_tree().quit(1)
		return
	if _stage == 0 and creeps.size() == 6:
		var wounded: Creep
		for creep: Creep in creeps:
			assert(creep.collision_layer == 0)
			if creep.health.current == 165:
				wounded = creep
		if wounded == null:
			return
		assert(wounded.team == Teams.Team.ORANGE and wounded.position.is_equal_approx(Vector2(8, 80)))
		assert(wounded.state == Creep.State.ATTACK and wounded.visual_animation == &"attack" and wounded.visual_frame == 3)
		print("PASS: Late join receives current health, position, team and attack state")
		_old_names.assign(creeps.map(func(creep: Node) -> String: return str(creep.name)))
		_stage = 1
		wounded.health._request_damage.rpc_id(1, 100.0, NodePath(""))
		_confirm_snapshot.rpc_id(1)
	elif _stage == 1 and creeps.size() == 5:
		print("PASS: Server death despawns the creep on the client")
		_stage = 2
		_confirm_death.rpc_id(1)
	elif _stage == 2 and World.level_loader.current_key == "Fortress2" and creeps.size() == 6:
		for creep: Creep in creeps:
			assert(str(creep.name) not in _old_names)
		print("PASS: Level replacement clears old creeps and replicates a fresh wave")
		_stage = 3
		_confirm_reload.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _confirm_snapshot() -> void:
	if not multiplayer.is_server():
		return
	await get_tree().create_timer(0.1).timeout
	var victim: Creep = World.get_node("Creeps/" + _victim_name)
	assert(victim.health.current == 165, "Client damage RPC must be ignored")
	print("PASS: Server rejects client-requested creep damage")
	var enemy: Creep
	for creep: Creep in get_tree().get_nodes_in_group("creeps"):
		if creep.team != victim.team:
			enemy = creep
			break
	victim.health.take_damage(200, enemy)
	victim.set_physics_process(true)

@rpc("any_peer", "call_remote", "reliable")
func _confirm_death() -> void:
	if not multiplayer.is_server():
		return
	World.creep_spawner.set_physics_process(true)
	await World.level_loader.spawn_level("Fortress2")

@rpc("any_peer", "call_remote", "reliable")
func _confirm_reload() -> void:
	if not multiplayer.is_server():
		return
	print("NETWORK_CHECK_PASSED: ", "listen host" if _listen_host else "dedicated authority")
	_finish.rpc()
	await get_tree().create_timer(0.2).timeout
	World.clear()
	get_tree().quit()

@rpc("authority", "call_remote", "reliable")
func _finish() -> void:
	get_tree().quit()
