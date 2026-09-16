extends SceneTree
## Physics smoke check using the archer's capsule, speed, jump and world mask.
## Godot --headless --path . --script tools/check_fortress.gd
## Omit --headless and add -- --preview to save /tmp/fortress-overview.png.

var level: Node2D
var pawn: CharacterBody2D
var failures := 0
const DT := 1.0 / 60.0

func _initialize() -> void:
	level = load("res://levels/Fortress1.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	call_deferred("_check")

func expect(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("%s (pawn at %s)" % [description, pawn.position])
	else:
		print("PASS: ", description)

func tick(direction: float = 0.0, jump: bool = false) -> void:
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

func _check() -> void:
	if "--preview" in OS.get_cmdline_user_args():
		await preview()
		quit()
		return
	pawn = CharacterBody2D.new()
	pawn.collision_layer = 2
	var archer := preload("res://player/arrow_player/arrow_player.tscn").instantiate()
	pawn.collision_mask = archer.collision_mask
	archer.free()
	var collider := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 6.0
	capsule.height = 16.0
	collider.shape = capsule
	pawn.add_child(collider)
	root.add_child(pawn)
	# Run fixed simulation frames quickly, without changing delta or game resources.
	Engine.physics_ticks_per_second = 6000
	Engine.time_scale = 100.0
	Engine.max_physics_steps_per_frame = 1000
	for marker in level.get_node("SpawnPoints").get_children():
		await teleport(marker.position)
		expect(pawn.is_on_floor() and absf(pawn.position.x - marker.position.x) < 1.0 and pawn.position.y < marker.position.y + 24,
			"%s settles on a safe floor" % marker.name)
	for side in [-1, 1]:
		# No jumps are necessary on either of the two main ramps.
		await teleport(Vector2(side * 544, 80))
		for frame in range(270):
			await tick(side)
		expect(absf(pawn.position.x) > 836 and pawn.position.y < -38, "Side %d center-to-middle ramp" % side)
		await teleport(Vector2(side * 1552, -48))
		for frame in range(270):
			await tick(side)
			if absf(pawn.position.x) >= 1864:
				break
		expect(absf(pawn.position.x) > 1848 and pawn.position.y < -166, "Side %d middle-to-base ramp" % side)
		await ascent(side, 912, -32, 4, "outpost")
		await ascent(side, 2256, -160, 8, "gatehouse")
		await ascent(side, 2432, -160, 12, "great tower")
		# Two balconies and the curtain walk intersect the internal climbing routes.
		for route in [Vector2(2256, -288), Vector2(2432, -448), Vector2(2344, -352)]:
			await teleport(Vector2(side * route.x, route.y - 18))
			expect(pawn.is_on_floor() and absf(pawn.position.y - (route.y - 8)) < 1.0,
				"Side %d balcony/wall walk at y=%d" % [side, route.y])
		# Defenders can leave through the balcony opening above the gate facade.
		await teleport(Vector2(side * 2256, -306))
		for frame in range(86):
			await tick(-side)
		expect(absf(pawn.position.x) < 2140 and pawn.is_on_floor() and pawn.position.y < -294,
			"Side %d gate balcony doorway" % side)
		for frame in range(120):
			await tick(-side, true)
		for frame in range(60):
			await tick()
		expect(pawn.is_on_floor() and pawn.position.y > -200, "Side %d keep exit returns to approach" % side)
		var perch_x := 1424 if side < 0 else 1408
		await ascent(side, perch_x - 40, -32, 3, "crooked perch")
		for direction in [-1, 1]:
			await teleport(Vector2(side * 1112, 0))
			for frame in range(150):
				await tick(side * direction)
			expect(pawn.is_on_floor() and pawn.position.y < -38,
				"Side %d trench exit direction %d" % [side, direction])
			await teleport(Vector2(side * 1992, -128))
			for frame in range(150):
				await tick(side * direction)
				if (direction < 0 and absf(pawn.position.x) <= 1888) or (direction > 0 and absf(pawn.position.x) >= 2096):
					break
			expect(pawn.is_on_floor() and pawn.position.y < -166,
				"Side %d dry moat exit direction %d" % [side, direction])
		await teleport(Vector2(side * 2112, -176))
		for frame in range(180):
			await tick(side)
		expect(absf(pawn.position.x) > 2240, "Side %d open gate route allows entry" % side)
	await teleport(Vector2(0, 80))
	expect(pawn.is_on_floor() and absf(pawn.position.y - 88) < 1.0, "Center ground is y=96")
	expect(get_nodes_in_group("spawn_blue").size() == 4 and get_nodes_in_group("spawn_orange").size() == 4, "Four spawn markers per team")
	expect(level.get_node("StaticBodyLimits/Right").position.x - level.get_node("StaticBodyLimits/Left").position.x == 5120,
		"Map width doubled to 5120")
	expect(get_nodes_in_group("fortress_rams").size() == 1, "One shared ram")
	for group in ["fortress_keeps", "fortress_outposts", "fortress_gates"]:
		expect(get_nodes_in_group(group).size() == 2, "One per side: %s" % group)
	# Solid lips stop projectiles from either direction (world query).
	var query := PhysicsRayQueryParameters2D.create(Vector2(-96, 56), Vector2(-180, 56), 1)
	expect(not level.get_world_2d().direct_space_state.intersect_ray(query).is_empty(), "Forward cover blocks a horizontal world ray")
	await preload("res://tools/check_fortress_platforms.gd").run(self, level)
	print("Fortress checks completed; failures=", failures)
	quit(1 if failures else 0)

func ascent(side: int, x: int, floor_y: int, steps: int, description: String) -> void:
	await teleport(Vector2(side * x, floor_y - 16))
	for step in range(steps):
		await tick(0, true)
		for frame in range(38):
			await tick()
		expect(pawn.is_on_floor() and absf(pawn.position.y - (floor_y - 8 - (step + 1) * 32)) < 1.0,
			"Side %d %s jump %d" % [side, description, step + 1])

func preview() -> void:
	root.size = Vector2i(1600, 620)
	root.content_scale_size = Vector2i(1600, 620)
	var camera := Camera2D.new()
	camera.position = Vector2(0, -100)
	camera.zoom = Vector2(0.30, 0.30)
	if "--keep-preview" in OS.get_cmdline_user_args():
		root.size = Vector2i(1600, 800)
		root.content_scale_size = Vector2i(1600, 800)
		camera.position = Vector2(2272, -300)
		camera.zoom = Vector2(1.2, 1.2)
	level.add_child(camera)
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "/tmp/fortress-keep.png" if "--keep-preview" in OS.get_cmdline_user_args() else "/tmp/fortress-overview.png"
	var error := root.get_texture().get_image().save_png(path)
	print("Preview: ", error_string(error), " ", path)
