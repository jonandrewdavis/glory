extends Node
## Godot --headless --path . tools/check_creeps.tscn

var world: Node
var failures := 0
var _serial := 100000

func _ready() -> void:
	call_deferred("_check")

func get_nodes_in_group(group: StringName) -> Array[Node]:
	return get_tree().get_nodes_in_group(group)

func expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)

func ticks(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame

func soldier(team: int, at: Vector2, goal: float = 0.0) -> Creep:
	_serial += 1
	return world.creep_spawner.spawn({"serial": _serial, "team": team, "position": at, "goal_x": goal}) as Creep

func reset_creeps() -> void:
	world.creep_spawner.clear_creeps()
	await ticks(2)

func _check() -> void:
	world = get_tree().root.get_node("World")
	if "--preview" in OS.get_cmdline_user_args():
		await preview()
		return
	Engine.physics_ticks_per_second = 6000
	Engine.time_scale = 100.0
	Engine.max_physics_steps_per_frame = 1000
	await world.level_loader.spawn_level("Fortress1")
	await ticks(4)
	expect(get_nodes_in_group("creeps").size() == 6, "Initial wave: three creeps at each fortress")
	for creep: Creep in get_nodes_in_group("creeps"):
		creep.set_physics_process(false)
	world.creep_spawner.queue_wave()
	await ticks(4)
	expect(get_nodes_in_group("creeps").size() == 6 and world.creep_spawner.pending.size() == 6, "Occupied spawn slots retain every pending soldier")
	for creep: Creep in get_nodes_in_group("creeps"):
		creep.position.y -= 100
	await ticks(4)
	expect(get_nodes_in_group("creeps").size() == 6, "Airborne soldiers reserve their spawn column to prevent stacking")
	await ticks(1800)
	expect(world.creep_spawner.pending.size() == 12, "Thirty-second timer queues another set of three per fortress")
	for creep: Creep in get_nodes_in_group("creeps"):
		creep.position.x += 200
	await ticks(4)
	expect(get_nodes_in_group("creeps").size() == 12 and world.creep_spawner.pending.size() == 6, "Vacated slots spawn without overlapping pending waves")
	await reset_creeps()
	for level_name in ["Fortress1", "Fortress2"]:
		await world.level_loader.spawn_level(level_name)
		await ticks(4)
		await reset_creeps()
		for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
			var own := get_nodes_in_group("creep_spawn_blue" if team == Teams.Team.BLUE else "creep_spawn_orange")
			var enemy := get_nodes_in_group("creep_spawn_orange" if team == Teams.Team.BLUE else "creep_spawn_blue")
			var squad: Array[Creep] = []
			for marker: Node2D in own:
				squad.append(soldier(team, marker.global_position, enemy[0].global_position.x))
			var creep := squad[0]
			var separated := true
			for i in range(6500):
				await get_tree().physics_frame
				for j in range(1, squad.size()):
					separated = separated and absf(squad[j].position.x - squad[j - 1].position.x) >= Creep.BODY_SIZE.x
				if creep.state == Creep.State.HOLD:
					break
			expect(creep.state == Creep.State.HOLD and absf(creep.position.x - creep.goal_x) <= 1.0,
				"%s team %d traverses terrain through center and holds at enemy gate (at %s)" % [level_name, team, creep.position])
			expect(separated, "%s team %d keeps its whole squad separated across terrain" % [level_name, team])
			await reset_creeps()
	await check_ramp_combat()
	await world.level_loader.spawn_level("Fortress1")
	await ticks(4)
	await reset_creeps()
	await check_queue()
	await check_combat()
	await check_arrows_and_ram()
	world.clear()
	await ticks(2)
	expect(get_nodes_in_group("creeps").is_empty() and world.creep_spawner.pending.is_empty(), "Session cleanup removes creeps and pending waves")
	print("Creep checks completed; failures=", failures)
	get_tree().quit(1 if failures else 0)

func check_ramp_combat() -> void:
	# Fortress2 is still loaded after traversal. These positions reproduce the
	# 15-pixel reservation deadlock without depending on random hop timing.
	for side in [-1, 1]:
		for center in [936.0, 864.0, 1008.0]:
			var points: Array[Vector2] = []
			for x in [center - 7.25, center + 7.25]:
				var ground := -32.0 - clampf((x - 864.0) / 144.0, 0.0, 1.0) * 128.0
				points.append(Vector2(side * x, ground - 24))
			await ramp_duel(points[0], points[1], "Fortress2 side %d ramp at x=%d" % [side, center])
	# An isolated ramp just below the soldiers' 0.9-radian walkable limit.
	for side in [-1, 1]:
		var slope: float = tan(0.89) * side
		var ramp := StaticBody2D.new()
		var collision := CollisionPolygon2D.new()
		collision.polygon = PackedVector2Array([Vector2(-100, 100 * slope), Vector2(100, -100 * slope), Vector2(100, 150), Vector2(-100, 150)])
		ramp.position = Vector2(0, -400)
		ramp.add_child(collision)
		add_child(ramp)
		await ramp_duel(Vector2(-7.25, -424 + 7.25 * slope), Vector2(7.25, -424 - 7.25 * slope), "Near-maximum slope side %d" % side)
		ramp.free()
	var blue := soldier(Teams.Team.BLUE, Vector2(0, -400), 0)
	var orange := soldier(Teams.Team.ORANGE, Vector2(14, -440), 14)
	blue.set_physics_process(false)
	orange.set_physics_process(false)
	await ticks(2)
	expect(not blue._can_hit(orange) and not orange._can_hit(blue), "Vertically distant soldiers remain out of melee reach")
	await reset_creeps()

func ramp_duel(first: Vector2, second: Vector2, description: String) -> void:
	var blue := soldier(Teams.Team.BLUE, first, first.x)
	var orange := soldier(Teams.Team.ORANGE, second, second.x)
	blue._cooldown = 10.0
	orange._cooldown = 10.0
	await ticks(60)
	expect(blue.is_on_floor() and orange.is_on_floor(), description + " settles on terrain")
	blue._cooldown = 0.1
	orange._cooldown = 0.1
	await ticks(180)
	expect(blue.health.current < 200 and orange.health.current < 200, description + " allows both soldiers to deal melee damage")
	expect(absf(blue.position.x - orange.position.x) >= Creep.BODY_SIZE.x, description + " preserves body separation")
	await reset_creeps()

func check_queue() -> void:
	var leader := soldier(Teams.Team.BLUE, Vector2(40, 80), 40)
	var follower := soldier(Teams.Team.BLUE, Vector2(0, 80), 100)
	await ticks(240)
	expect(leader.position.x - follower.position.x >= Creep.BODY_SIZE.x and absf(leader.position.y - follower.position.y) < 1.0,
		"Friendly creeps queue without overlapping or climbing")
	var player := CharacterBody2D.new()
	player.collision_layer = 2
	player.collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 16)
	collision.shape = shape
	player.add_child(collision)
	get_tree().root.add_child(player)
	player.position = Vector2(0, 88)
	for i in range(60):
		await get_tree().physics_frame
		player.velocity = Vector2(100, 0)
		player.move_and_slide()
	expect(player.position.x > 90, "Player bodies pass through creeps")
	player.free()
	await reset_creeps()

func check_combat() -> void:
	var blue := soldier(Teams.Team.BLUE, Vector2(-8, 80), 100)
	var orange := soldier(Teams.Team.ORANGE, Vector2(8, 80), -100)
	orange.set_physics_process(false)
	var losses: Array[float] = []
	orange.health.damaged.connect(func(amount: float, _source: Node) -> void: losses.append(amount))
	expect(blue.health.current == 200 and not blue.health.regen_enabled and not blue.health.auto_respawn, "Creeps start with 200 health, no regen or respawn")
	var intervals_ok := true
	for i in range(100):
		var interval := blue.next_swing_interval()
		intervals_ok = intervals_ok and interval >= 0.8 and interval <= 1.4
	expect(intervals_ok, "Swing delays stay within 0.8–1.4 seconds")
	await ticks(40)
	expect(losses.is_empty(), "First swing waits its random delay and strike frame")
	await ticks(600)
	expect(losses.size() >= 6 and losses.size() <= 10, "Each attack applies one hit at the strike frame")
	var damage_ok := true
	for index in range(losses.size()):
		var loss := losses[index]
		damage_ok = damage_ok and (loss == 20.0 or loss == 25.0 or (index == losses.size() - 1 and orange.health.current == 0 and loss <= 25))
	expect(damage_ok, "Melee damage uses 20 or 25 (final hit clamped to remaining health)")
	if orange.is_alive():
		orange.health.take_damage(200, blue)
	expect(not orange.is_alive() and orange.collision_layer == 0, "Death immediately removes collision and combat eligibility")
	orange.set_physics_process(true)
	await ticks(ceili(Creep.DEATH_DURATION * 60.0) + 2)
	expect(not is_instance_valid(orange) and blue.position.x > -8 and blue.state in [Creep.State.MARCH, Creep.State.HOLD], "Death animation removes soldier permanently and attacker resumes marching")
	await reset_creeps()
	blue = soldier(Teams.Team.BLUE, Vector2(-8, 80), 100)
	orange = soldier(Teams.Team.ORANGE, Vector2(8, 80), -100)
	orange.set_physics_process(false)
	blue._cooldown = 0.0
	await ticks(5)
	orange.position.x = 100
	await ticks(50)
	expect(orange.health.current == 200, "Target leaving reach before the strike takes no damage")
	await reset_creeps()
	var wall := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2, 32)
	collision.shape = shape
	wall.add_child(collision)
	wall.position = Vector2(0, 80)
	add_child(wall)
	blue = soldier(Teams.Team.BLUE, Vector2(-8, 80), -8)
	orange = soldier(Teams.Team.ORANGE, Vector2(8, 80), 8)
	await ticks(180)
	expect(blue.health.current == 200 and orange.health.current == 200, "Terrain between opposing soldiers blocks melee damage")
	wall.free()
	await ticks(180)
	expect(blue.health.current < 200 and orange.health.current < 200, "Both opposing soldiers attack when the obstruction clears")
	await reset_creeps()

func check_arrows_and_ram() -> void:
	var ram: BatteringRam = get_nodes_in_group("fortress_rams")[0]
	ram.distance = ram._curve.get_baked_length() * 0.5
	await ticks(2)
	world.player_spawner.spawn_player(1)
	var player: ArrowPlayer = world.player_spawner.get_player(1)
	player.set_physics_process(false)
	player.team = Teams.Team.BLUE
	player.position = Vector2(-50, 88)
	var friendly := soldier(Teams.Team.BLUE, Vector2(-20, 88), -20)
	var enemy := soldier(Teams.Team.ORANGE, Vector2(20, 88), 20)
	friendly.set_physics_process(false)
	enemy.set_physics_process(false)
	await ticks(2)
	var arrow: Arrow = world.projectile_spawner.spawn_arrow({"position": Vector2(-40, 85), "velocity": Vector2(600, 0), "owner_id": 1, "team": Teams.Team.BLUE, "damage": 35.0})
	await ticks(10)
	expect(friendly.health.current == 200 and enemy.health.current == 165 and not is_instance_valid(arrow), "Swept enemy arrow passes friendly creep and damages enemy once")
	expect(world.scoreboard.entries[1].kills == 0, "Nonlethal creep damage grants no kill")
	await ticks(2)
	expect(ram.blue_count == 2 and ram.orange_count == 1 and ram.direction == 1, "Ram counts players and creeps equally")
	player.position.x = -1000
	await ticks(2)
	expect(ram.blue_count == 1 and ram.orange_count == 1 and ram.direction == 0, "Equal creep counts stop ram")
	world.projectile_spawner.spawn_arrow({"position": Vector2(-40, 85), "velocity": Vector2(600, 0), "owner_id": 1, "team": Teams.Team.BLUE, "damage": 200.0})
	await ticks(10)
	expect(ram.orange_count == 0 and ram.direction == 1, "Dead creeps stop contributing before their animation ends")
	expect(world.scoreboard.entries[1].kills == 1 and world.scoreboard.entries[1].deaths == 0, "Lethal arrow awards one player kill without adding a player death")
	enemy.health.take_damage(200, player)
	expect(world.scoreboard.entries[1].kills == 1, "Damage after death cannot award another kill")
	var current := friendly.health.current
	friendly.health._request_damage(100, enemy.get_path())
	expect(friendly.health.current == current, "Network damage request cannot damage a creep")
	var assisted := soldier(Teams.Team.ORANGE, Vector2(50, 88), 50)
	assisted.set_physics_process(false)
	assisted.health.take_damage(35, player)
	assisted.health.take_damage(200, friendly)
	expect(world.scoreboard.entries[1].kills == 1, "A creep's killing blow does not credit a player who damaged the victim earlier")
	await reset_creeps()
	world.player_spawner.spawn_player(2)
	var opponent: ArrowPlayer = world.player_spawner.get_player(2)
	opponent.set_physics_process(false)
	opponent.position = Vector2(20, 88)
	player.position = Vector2(-50, 88)
	var before := opponent.health.current
	world.projectile_spawner.spawn_arrow({"position": Vector2(-40, 85), "velocity": Vector2(600, 0), "owner_id": 1, "team": Teams.Team.BLUE, "damage": 35.0})
	await ticks(10)
	expect(opponent.health.current == before - 35, "Existing enemy-player arrow damage still works")
	world.player_spawner.clear_players()

func preview() -> void:
	await world.level_loader.spawn_level("Fortress1")
	await ticks(4)
	await reset_creeps()
	var window := get_tree().root
	window.size = Vector2i(1200, 600)
	window.content_scale_size = Vector2i(1200, 600)
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(0, 55)
	camera.zoom = Vector2(5, 5)
	add_child(camera)
	camera.make_current()
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var side := -1 if team == Teams.Team.BLUE else 1
		for i in range(3):
			soldier(team, Vector2(side * (60 + i * 24), 80), -side * 2128)
	await ticks(180)
	for i in range(120):
		await get_tree().physics_frame
		var swinging := false
		for creep: Creep in get_nodes_in_group("creeps"):
			if creep.visual_animation == &"attack" and creep.visual_frame == 3:
				swinging = true
		if swinging:
			break
	await RenderingServer.frame_post_draw
	var result := window.get_texture().get_image().save_png("/tmp/creeps-preview.png")
	print("Creep preview: ", error_string(result), " /tmp/creeps-preview.png")
	world.clear()
	get_tree().quit(result)
