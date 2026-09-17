extends Node
## Run two processes with -- --server and -- --client.
const PORT := 19737
var failures := 0
var stage := 0
var local_player: ArrowPlayer
var received := 0
var observed_ready := false
var started := 0
var reflection_source: Arrow

func _ready() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func _run() -> void:
	started = Time.get_ticks_msec()
	MultiplayerService.set_backend(MultiplayerService.BackendType.ENET, false)
	var peer := ENetMultiplayerPeer.new()
	World.projectile_spawner.arrow_spawned.connect(_on_arrow)
	if "--server" in OS.get_cmdline_user_args():
		World.projectile_spawner.arrow_travel_time_multiplier = 1.75
		assert(peer.create_server(PORT, 4) == OK)
		multiplayer.multiplayer_peer = peer
		MultiplayerService.in_lobby = true
		MultiplayerService.backend.joinable = true
		await World.level_loader.spawn_level("Fortress1")
		print("ARROW_SERVER_READY")
	else:
		# Deliberately disagree: clients must use the host's spawn value.
		World.projectile_spawner.arrow_travel_time_multiplier = 3.0
		assert(peer.create_client("127.0.0.1", PORT) == OK)
		multiplayer.multiplayer_peer = peer

func _process(_delta: float) -> void:
	if started == 0:
		return
	if Time.get_ticks_msec() - started > 20000:
		push_error("Arrow network check timed out")
		get_tree().quit(1)
	if multiplayer.is_server():
		for player: ArrowPlayer in World.player_spawner.get_children():
			if player.readiness_indicator.display_state == Vector4(stage, 1, 1, 1):
				observed_ready = true
		return
	if stage == 0 and local_player == null and World.level_loader.is_level_ready():
		local_player = World.player_spawner.get_player(multiplayer.get_unique_id())
		if local_player != null:
			local_player.set_physics_process(false)
			local_player.position = Vector2(0, -10000)
			_prepare_next()

func _prepare_next() -> void:
	local_player.fire_cooldown_left = 0.0
	local_player.select_level(stage)
	local_player._prepare(local_player.minimum_preparation_time(stage), local_player.position + Vector2.RIGHT)
	await get_tree().create_timer(0.25).timeout
	local_player._fire(local_player.position + Vector2.RIGHT)

func _on_arrow(arrow: Arrow) -> void:
	var shot_stage := received
	expect(arrow.travel_time_multiplier == 1.75, "Network arrow retains host launch multiplier")
	if shot_stage < 3:
		var shooter := World.player_spawner.get_player(arrow.owner_id)
		expect(arrow.initial_velocity.is_equal_approx(Vector2(shooter.compute_arrow_speed(shot_stage), 0)), "Network shot has configured level speed")
		expect(arrow.damage == [25.0, 35.0, 50.0][shot_stage], "Network shot has selected damage")
		expect(arrow.visual_scale == [Vector2(1, 1), Vector2(1.1, 1.6), Vector2(1.2, 2.2)][shot_stage], "Network shot has selected scale")
	else:
		arrow.set_physics_process(false)
		# The spawn callback runs before entering the tree, which enables processing.
		arrow.set_physics_process.call_deferred(false)
		reflection_source = arrow
		expect(arrow.origin == Vector2(-10000, -10000) and arrow.initial_velocity == Vector2(1008, -200), "Network reflection preserves baseline curve")
		expect(is_equal_approx(arrow.elapsed, 0.4), "Network reflection preserves impact clock")
		expect(arrow.flight_direction == (-1 if shot_stage == 3 else 1), "Network repeated reflection preserves direction")
		expect(arrow.owner_id == (22 if shot_stage == 3 else 11), "Network reflection transfers ownership")
		expect(arrow.team == (Teams.Team.ORANGE if shot_stage == 3 else Teams.Team.BLUE), "Network reflection transfers team")
		expect(arrow.damage == 35.0 and arrow.visual_scale == Vector2(1.1, 1.6), "Network reflection preserves damage and scale")
		expect(arrow.global_position.is_equal_approx(Arrow.flight_position(arrow.origin, arrow.initial_velocity, 0.4)), "Network reflection starts at matching position")
		expect(arrow.velocity.is_equal_approx((arrow.initial_velocity + Arrow.GRAVITY * 0.4) * arrow.flight_direction / 1.75), "Network reflection starts at matching velocity")
	received += 1
	if multiplayer.is_server():
		if shot_stage < 3:
			expect(observed_ready, "Remote readiness snapshot arrives before release")
	else:
		_ack.rpc_id(1, failures)

@rpc("any_peer", "call_remote", "reliable")
func _ack(client_failures: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	failures += client_failures
	await get_tree().create_timer(0.6).timeout
	var player := World.player_spawner.get_player(sender)
	if player != null and stage < 3:
		expect(player.readiness_indicator.display_state == Vector4(stage, 0, 0, 0), "Release replicates idle selected-level indicator")
	observed_ready = false
	stage += 1
	if stage < 3:
		_next.rpc(stage)
	elif stage < 5:
		_spawn_reflection()
	else:
		expect(received == 5, "Host spawned three shots and two reflections")
		print("ARROW_NETWORK_PASSED" if failures == 0 else "ARROW_NETWORK_FAILED")
		_finish.rpc(failures)
		await get_tree().create_timer(0.2).timeout
		World.clear()
		get_tree().quit(1 if failures else 0)

func _spawn_reflection() -> void:
	var source := reflection_source
	if stage == 3:
		source = Arrow.new()
		source.setup({"position": Vector2(-10000, -10000), "velocity": Vector2(1008, -200),
			"trajectory_time": 0.4, "travel_time_multiplier": 1.75, "damage": 35.0, "scale": Vector2(1.1, 1.6)})
		World.projectile_spawner.arrow_travel_time_multiplier = 2.5
	var blocker := ArrowPlayer.new()
	blocker.peer_id = 22 if stage == 3 else 11
	blocker.team = Teams.Team.ORANGE if stage == 3 else Teams.Team.BLUE
	World.projectile_spawner.reflect_arrow(source, blocker, source.global_position)
	blocker.free()
	if stage == 3:
		source.free()

@rpc("authority", "call_remote", "reliable")
func _next(level: int) -> void:
	stage = level
	_prepare_next()

@rpc("authority", "call_remote", "reliable")
func _finish(server_failures: int) -> void:
	expect(received == 5, "Client received three shots and two reflections")
	get_tree().quit(1 if failures + server_failures else 0)
