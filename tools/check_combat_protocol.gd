extends Node
var failures := 0

func _ready() -> void:
	run.call_deferred()

func expect(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
	else:
		print("PASS: ", label)

func record(pos := Vector2.ZERO, time := 1.0) -> Dictionary:
	return {"peer": 11, "serial": 7, "sequence": 1, "position": pos,
		"velocity": Vector2(100, 0), "aim": 0.0, "flags": 0, "level": 1, "age": 0.02, "time": time}

func run() -> void:
	World.combat_network.set_physics_process(false)
	World.combat_network.set_process(false)
	check_codec()
	check_buffer()
	check_commands()
	check_presentation()
	await check_ghosts()
	World.clear()
	print("COMBAT_PROTOCOL_PASSED" if failures == 0 else "COMBAT_PROTOCOL_FAILED")
	get_tree().quit(1 if failures else 0)

func check_codec() -> void:
	var records: Array = []
	for i in 30:
		var state := record(Vector2(-4000.125 + i, 1234.5))
		state.peer = i + 1
		records.append(state)
	var chunks := PlayerSnapshot.encode(12, 3, 99, 100, 23.5, records)
	var count := 0
	for bytes in chunks:
		expect(bytes.size() <= 1200, "Snapshot respects payload budget")
		var decoded := PlayerSnapshot.decode(bytes)
		expect(decoded.epoch == 12 and decoded.revision == 3 and decoded.sequence == 99 and decoded.time == 23.5, "Chunk carries complete timeline identity")
		for state: Dictionary in decoded.records:
			expect(state.position.distance_to(records[state.peer - 1].position) < 0.001, "Float position round trip")
			count += 1
	expect(count == 30, "Thirty players survive chunking")
	var invalid := chunks[0].duplicate()
	invalid.resize(invalid.size() - 1)
	expect(PlayerSnapshot.decode(invalid).is_empty(), "Truncated snapshot rejected")
	invalid = chunks[0].duplicate()
	invalid.encode_float(PlayerSnapshot.HEADER + 12, NAN)
	expect(PlayerSnapshot.decode(invalid).is_empty(), "Nonfinite position rejected")

func check_buffer() -> void:
	var buffer := PresentationBuffer.new()
	var a := record(Vector2.ZERO, 1.0)
	a.aim = deg_to_rad(179)
	var b := record(Vector2(10, 0), 1.1)
	b.aim = deg_to_rad(-179)
	buffer.push(a, 1)
	buffer.push(b, 2)
	buffer.push(record(Vector2(999, 0), 0.5), 1)
	expect(buffer.samples.size() == 2, "Out-of-order snapshot cannot overwrite state")
	expect(buffer.sample_at(0.5).position == Vector2.ZERO, "Startup holds seed")
	var middle := buffer.sample_at(1.05)
	expect(middle.position.distance_to(Vector2(5, 0)) < 0.001, "Timestamp interpolation follows expected path")
	expect(absf(absf(middle.aim) - PI) < 0.001, "Angles interpolate across wrap by shortest path")
	expect(buffer.sample_at(10.0).position == Vector2(10, 0), "Underrun holds instead of extrapolating")
	for i in 100:
		buffer.push(record(Vector2(i, 0), 2.0 + i), i + 3)
	expect(buffer.samples.size() == 32, "History stays bounded")

func pawn(id: int) -> ArrowPlayer:
	var p := World.player_spawner.spawn({"peer_id": id, "serial": id,
		"position": Vector2(-10000, -10000), "revision": World.level_loader.revision}) as ArrowPlayer
	p.set_physics_process(false)
	p.aim_reticle.set_physics_process(false)
	return p

func check_commands() -> void:
	var p := pawn(11)
	var net: CombatNetwork = World.combat_network
	var pose := net.owner_pose(p)
	pose.position += Vector2(10, 0)
	expect(net._accept_pose(11, pose), "Server accepts valid owner pose")
	expect(not net._accept_pose(11, pose), "Duplicate owner sequence rejected")
	pose.serial = 999
	expect(not net._accept_pose(11, pose), "Old incarnation cannot move replacement")
	pose = net.owner_pose(p)
	pose.position = Vector2(INF, 0)
	expect(not net._accept_pose(11, pose), "Nonfinite owner pose rejected")
	net.command(p, CombatNetwork.CHARGE)
	var state := net._state(p)
	expect(state.charge >= 0.0, "Server starts charge clock")
	net.command(p, CombatNetwork.FIRE, 1)
	expect(state.pending == 1 and World.projectile_spawner._simulation.is_empty(), "Early release waits for server eligibility")
	state.charge = CombatNetwork.now() - p.minimum_preparation_time(0) - 0.1
	net._advance_combat(p)
	expect(World.projectile_spawner._simulation.size() == 1 and state.pending == 0, "Eligible shot launches once")
	net.command(p, CombatNetwork.CHARGE)
	net.command(p, CombatNetwork.FIRE, 1)
	expect(World.projectile_spawner._simulation.size() == 1 and state.pending == 0, "Shot ID replay cannot launch again")
	net.command(p, CombatNetwork.CANCEL)
	net.command(p, CombatNetwork.SHIELD)
	expect(p.server_blocking, "Server activates shield")
	var deadline: float = state.shield
	net.command(p, CombatNetwork.SHIELD)
	expect(state.shield == deadline, "Repeated shield cannot extend duration")
	state.shield = CombatNetwork.now() - 0.01
	net._advance_combat(p)
	expect(not p.server_blocking, "Server expires shield without owner update")
	net.command(p, CombatNetwork.SHIELD)
	expect(not p.server_blocking, "Server enforces shield cooldown")
	p.set_network_away(true)
	expect(not net._accept_pose(11, net.owner_pose(p)), "Away player cannot submit movement")
	World.projectile_spawner.clear_projectiles()

func check_presentation() -> void:
	var p := pawn(22)
	var raw := p.global_position
	var a := record(raw, 10.0)
	var b := record(raw + Vector2(10, 0), 10.1)
	p.receive_snapshot(a, 1)
	p.receive_snapshot(b, 2)
	World.combat_network.render_time = 10.05
	p._process(0.0)
	expect(p.global_position == raw, "Listen-host smoothing never moves collision body")
	expect(p.visual_root.global_position.distance_to(raw + Vector2(5, 0)) < 0.001, "Listen host sees interpolated artwork")
	p.present_death(raw + Vector2(5, 0))
	p.receive_snapshot(record(raw + Vector2(100, 0), 11.0), 3)
	p._process(0.0)
	expect(p.sprite.animation == &"death" and p.presentation.samples.is_empty(), "Late movement cannot resurrect death presentation")

func check_ghosts() -> void:
	var p := pawn(1)
	var manager: ProjectileSpawner = World.projectile_spawner
	var ghost := manager.predict(p, 55, Vector2.RIGHT, 0)
	expect(ghost.collision_layer == 0 and not ghost.monitorable and not ghost.is_in_group("projectiles"), "Ghost has no gameplay collision or projectile membership")
	var handle := ghost.get_instance_id()
	ghost.position += Vector2(20, 0)
	var data := ghost.launch_data.duplicate()
	data.serial = 123
	data.launch_time = World.combat_network.server_time()
	World.combat_network.render_time = data.launch_time
	manager._confirm(data)
	expect(manager._visuals[123].get_instance_id() == handle and manager._ghosts.is_empty(), "Confirmation adopts ghost handle without a second visual")
	ghost._process(0.08)
	expect(ghost.correction_left == 0.0 and ghost.position.distance_to(data.position) < 0.001, "Correction converges in 80 milliseconds")
	manager._confirm(data)
	expect(manager._visuals.size() == 1, "Duplicate confirmation is idempotent")
	manager.present_event({"kind": "terminal", "projectile": 123, "position": data.position + Vector2(10, 0)})
	manager._confirm(data)
	expect(manager._visuals.is_empty(), "Late confirmation cannot resurrect a terminated arrow")
	var rejected := manager.predict(p, 56, Vector2.RIGHT, 0)
	manager.receive_event({"kind": "result", "peer": 1, "serial": p.spawn_serial, "shot": 56, "result": "rejected", "action": CombatNetwork.FIRE})
	await get_tree().create_timer(0.2).timeout
	expect(not is_instance_valid(rejected), "Rejected ghost fades and is freed")
	var expired := manager.predict(p, 57, Vector2.RIGHT, 0)
	expired.created_at -= 2.0
	manager._process(0.0)
	expect(manager._ghosts.is_empty(), "Unanswered ghost has bounded lifetime")
