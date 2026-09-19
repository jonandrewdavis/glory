extends SceneTree
## Compact-map traversal and integration smoke check.
## Add -- --preview to write /tmp/fortress2-overview.png.

const DT := 1.0 / 60.0
var level: Node2D
var pawn: CharacterBody2D
var failures := 0
var player_scale := Vector2.ONE
var player_half_height := 8.0

func _initialize() -> void:
	# Autoload scene history expects a current scene before its _ready runs.
	var placeholder := Node.new()
	root.add_child(placeholder)
	current_scene = placeholder
	call_deferred("_load_level")

func _load_level() -> void:
	current_scene.free()
	level = load("res://levels/Fortress2.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	call_deferred("_check")

func expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("%s (pawn at %s)" % [description, pawn.position if pawn else Vector2.ZERO])

func tick(direction := 0.0, jump := false) -> void:
	await physics_frame
	pawn.velocity.y += 980.0 * DT
	if jump and pawn.is_on_floor():
		pawn.velocity.y = -290.0
	pawn.velocity.x = lerpf(pawn.velocity.x, direction * (100.0 if pawn.is_on_floor() else 97.0), 17.5 * DT)
	pawn.move_and_slide()

func teleport(point: Vector2) -> void:
	pawn.position = point
	pawn.velocity = Vector2.ZERO
	for frame in range(30):
		await tick()

func ascent(side: int, x: int, floor_y: int, steps: int, description: String) -> void:
	await teleport(Vector2(side * x, floor_y - 16))
	for step in range(steps):
		await tick(0, true)
		for frame in range(38):
			await tick()
		expect(pawn.is_on_floor() and absf(pawn.position.y - (floor_y - 8 - (step + 1) * 32)) < 1,
			"Side %d %s jump %d" % [side, description, step + 1])

func hop(x: float, from_y: float, to_y: float, description: String) -> void:
	await teleport(Vector2(x, from_y - 8))
	expect(pawn.is_on_floor(), "%s start" % description)
	await tick(0, true)
	for frame in range(38):
		await tick()
	expect(pawn.is_on_floor() and absf(pawn.position.y - (to_y - 8)) < 1, description)

func check_center() -> void:
	expect(get_nodes_in_group("fortress_center_towers").size() == 1, "One neutral center tower")
	for side in [-1, 1]:
		# Shelf (y=72) -> Step1 (40) -> Step2 (8) -> deck (-24), using the overlaps between steps.
		await hop(side * 264, 72, 40, "Side %d center step 1" % side)
		await hop(side * 220, 40, 8, "Side %d center step 2" % side)
		await hop(side * 172, 8, -24, "Side %d center deck" % side)
	await teleport(Vector2(-160, -32))
	for frame in range(240):
		await tick(1)
		if pawn.position.x > 150:
			break
	expect(pawn.is_on_floor() and pawn.position.x > 150 and absf(pawn.position.y + 32) < 1, "Deck walk passes through the tower")
	await ascent(1, 0, -24, 1, "tower perch")
	var arrow: Node = load("res://player/arrow_player/arrow.tscn").instantiate()
	var arrow_mask: int = arrow.collision_mask
	arrow.free()
	var space := level.get_world_2d().direct_space_state
	for x in [0, -60, 60]:
		var through := space.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(x, -200), Vector2(x, 90), arrow_mask, [pawn.get_rid()]))
		expect(through.is_empty(), "Bridge column x=%d is transparent to arrows" % x)
	expect(level.get_node_or_null("Blue/CenterShelter") == null and level.get_node_or_null("Orange/CenterLip") == null, "Central shelters removed")

func _check() -> void:
	if "--preview" in OS.get_cmdline_user_args():
		await preview()
		quit()
		return
	pawn = CharacterBody2D.new()
	pawn.collision_layer = 2
	var archer: Node = load("res://player/arrow_player/arrow_player.tscn").instantiate()
	pawn.collision_mask = archer.collision_mask
	player_scale = archer.scale
	var collider := CollisionShape2D.new()
	collider.shape = archer.get_node("CollisionShape2D").shape.duplicate()
	player_half_height = collider.shape.height * player_scale.y * 0.5
	archer.free()
	pawn.add_child(collider)
	root.add_child(pawn)
	Engine.physics_ticks_per_second = 6000
	Engine.time_scale = 100
	Engine.max_physics_steps_per_frame = 1000
	for marker in level.get_node("SpawnPoints").get_children():
		# Creep markers intentionally lie in timber: only players are blocked.
		pawn.collision_mask = 17 if str(marker.name).begins_with("Creep") else 33
		await teleport(marker.position)
		expect(pawn.is_on_floor() and absf(pawn.position.x - marker.position.x) < 1, "%s safe spawn" % marker.name)
	pawn.collision_mask = 33
	for side in [-1, 1]:
		await teleport(Vector2(side * 352, 80))
		for frame in range(260):
			await tick(side)
		expect(absf(pawn.position.x) > 500 and pawn.position.y < -38, "Side %d lower ramp" % side)
		await teleport(Vector2(side * 864, -48))
		for frame in range(260):
			await tick(side)
			if absf(pawn.position.x) > 1000:
				break
		expect(absf(pawn.position.x) > 992 and pawn.position.y < -162, "Side %d upper ramp" % side)
		await ascent(side, 608, -32, 4, "outpost")
		await ascent(side, 1188, -160, 10, "keep")
		await check_gate_access(side)
		for direction in [-1, 1]:
			await teleport(Vector2(side * 728, -8))
			for frame in range(110):
				await tick(side * direction)
			expect(pawn.is_on_floor() and pawn.position.y < -38, "Side %d trench exit %d" % [side, direction])
	expect(level.get_node("StaticBodyLimits/Right").position.x - level.get_node("StaticBodyLimits/Left").position.x == 2560, "Compact 2560 width")
	expect(get_nodes_in_group("spawn_blue").size() == 4 and get_nodes_in_group("spawn_orange").size() == 4, "Four spawns per team")
	expect(get_nodes_in_group("fortress_keeps").size() == 2, "Two keeps")
	expect(get_nodes_in_group("fortress_outposts").size() == 2, "Two outposts")
	expect(get_nodes_in_group("fortress_gates").size() == 2, "Two damageable gate objectives")
	expect(get_nodes_in_group("fortress_rams").size() == 1, "One shared ram")
	await check_center()
	await check_defenses()
	await load("res://tools/check_fortress_platforms.gd").run(self, level)
	print("Fortress2 checks completed; failures=", failures)
	quit(1 if failures else 0)

func stair_jump(target_x: float, surface_y: float, description: String) -> void:
	await tick(0, true)
	for frame in range(45):
		var direction := clampf((target_x - pawn.position.x) / 6.0, -1.0, 1.0)
		await tick(direction)
	expect(pawn.is_on_floor() and absf(pawn.position.y - (surface_y - player_half_height)) < 1, description)

func check_gate_access(side: int) -> void:
	# Same capsule and scale as the playable archer; legacy map checks use unit scale.
	pawn.scale = player_scale
	# The gate barrier is built by FortressGate at runtime; tools/check_rounds.tscn covers it.
	# Defenders climb out from inside; attackers have no exterior staircase.
	await teleport(Vector2(side * 1188, -176))
	for i in range(5):
		await stair_jump(side * 1188, -192 - 32 * i, "Side %d interior stair %d" % [side, i + 1])
	await stair_jump(side * 1188, -352, "Side %d balcony" % side)
	for frame in range(260):
		await tick(-side if absf(pawn.position.x) > 960 else 0.0)
	expect(absf(pawn.position.x) < 1088 and pawn.position.y > -180, "Side %d drops off the balcony outside the gate" % side)
	pawn.scale = Vector2.ONE

func check_defenses() -> void:
	var space := level.get_world_2d().direct_space_state
	var arrow: Node = load("res://player/arrow_player/arrow.tscn").instantiate()
	var arrow_mask: int = arrow.collision_mask
	arrow.free()
	for side in [-1, 1]:
		# The keep is all open platforms: nothing but the gate stops a level shot.
		for y in range(-472, -224, 8):
			var lane := PhysicsRayQueryParameters2D.create(Vector2(side * 1000, y), Vector2(side * 1279, y), arrow_mask)
			lane.collide_with_areas = true
			expect(space.intersect_ray(lane).is_empty(), "Side %d keep passes level arrows at %d" % [side, y])
		var drop := PhysicsRayQueryParameters2D.create(Vector2(side * 1188, -500), Vector2(side * 1188, -168), arrow_mask)
		expect(space.intersect_ray(drop).is_empty(), "Side %d keep floors pass plunging arrows" % side)
		var timber := PhysicsRayQueryParameters2D.create(Vector2(side * 1040, -192), Vector2(side * 1200, -192), arrow_mask)
		timber.collide_with_areas = true
		expect(space.intersect_ray(timber).get("collider") is Area2D, "Side %d gate stops arrows" % side)
		var ground := PhysicsRayQueryParameters2D.create(Vector2(side * 400, -20), Vector2(side * 400, 200), arrow_mask)
		expect(not space.intersect_ray(ground).is_empty(), "Side %d ground stops arrows" % side)
		for y in [-168, -40]:
			var outpost := PhysicsRayQueryParameters2D.create(Vector2(side * 500, y), Vector2(side * 700, y), arrow_mask)
			expect(space.intersect_ray(outpost).is_empty(), "Side %d outpost cover passes arrows at %d" % [side, y])
		await teleport(Vector2(side * 1200, -488))
		for frame in range(60):
			await tick(side)
		expect(pawn.is_on_floor() and pawn.position.y < -480, "Side %d crown has no blocking parapet" % side)
	var sky := PhysicsRayQueryParameters2D.create(Vector2(0, -500), Vector2(0, -3000), arrow_mask)
	expect(space.intersect_ray(sky).is_empty(), "Old ceiling and maximum normal shot apex are clear")
	var upward: Node = load("res://player/arrow_player/arrow.tscn").instantiate()
	level.add_child(upward)
	upward.set_physics_process(false)
	upward.setup({"position": Vector2(0, -500), "velocity": Vector2(0, -1296)})
	for frame in range(100):
		upward._physics_process(DT)
	expect(not upward._finished and upward.position.y < -1500, "Full-power upward arrow clears former ceiling")
	upward.free()
	var ceiling := PhysicsRayQueryParameters2D.create(Vector2(0, -16000), Vector2(0, -17000), arrow_mask)
	expect(not space.intersect_ray(ceiling).is_empty(), "Absolute high ceiling remains solid")

func preview() -> void:
	root.size = Vector2i(1600, 700)
	root.content_scale_size = Vector2i(1600, 700)
	var camera := Camera2D.new()
	camera.position = Vector2(0, -100)
	camera.zoom = Vector2(0.58, 0.58)
	level.add_child(camera)
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("/tmp/fortress2-overview.png")
	print("Preview: ", error_string(error), " /tmp/fortress2-overview.png")
	if "--gate-preview" in OS.get_cmdline_user_args():
		camera.zoom = Vector2(1.8, 1.8)
		for side in [-1, 1]:
			camera.position = Vector2(side * 1160, -320)
			for frame in range(6):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/fortress2-gate-%s.png" % ("blue" if side < 0 else "orange"))
