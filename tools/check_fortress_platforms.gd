extends RefCounted
## Shared collision regression checks, called by both Fortress checkers.

static func run(check: SceneTree, level: Node2D) -> void:
	var arrow := preload("res://player/arrow_player/arrow.tscn").instantiate()
	var arrow_mask: int = arrow.collision_mask
	arrow.free()
	var converted := 0
	for platform in check.get_nodes_in_group("fortress_one_way_platforms"):
		var path := str(level.get_path_to(platform))
		var tower := "/Keep/" in path or "/ForwardOutpost/" in path
		var valid: bool = platform.is_in_group("fortress_arrow_transparent_platforms") == tower
		for cell in platform.get_used_cells():
			valid = valid and platform.get_cell_alternative_tile(cell) == (2 if tower else 1)
		check.expect(valid, "%s platform classification" % path)
		if tower:
			converted += 1
	check.expect(converted == (56 if level.name == "Fortress1" else 28), "All tower platforms converted")
	# Isolate the same baked tiles so nearby tower walls cannot mask the result.
	var limits := level.get_node("StaticBodyLimits") as StaticBody2D
	var limits_layer := limits.collision_layer
	limits.collision_layer = 0
	var fixture := TileMapLayer.new()
	fixture.tile_set = preload("res://assets/sprites/oak_tileset.tres")
	fixture.position = Vector2(10000, 0)
	check.root.add_child(fixture)
	var target := StaticBody2D.new()
	target.collision_layer = 2
	target.collision_mask = 0
	target.position = Vector2(10008, 24)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 8)
	collider.shape = shape
	target.add_child(collider)
	check.root.add_child(target)
	var space := level.get_world_2d().direct_space_state
	for atlas_x in [8, 9, 10]:
		fixture.set_cell(Vector2i.ZERO, 0, Vector2i(atlas_x, 0), 2)
		await check.physics_frame
		await check.physics_frame
		for segment in [Vector4(8, -8, 8, 12), Vector4(8, 12, 8, -8), Vector4(-8, 3, 24, 3), Vector4(24, 3, -8, 3), Vector4(-8, -8, 24, 12)]:
			var start := fixture.position + Vector2(segment.x, segment.y)
			var end := fixture.position + Vector2(segment.z, segment.w)
			var query := PhysicsRayQueryParameters2D.create(start, end, arrow_mask)
			check.expect(space.intersect_ray(query).is_empty(), "Tile %d arrow passes %s" % [atlas_x, segment])
		var through := PhysicsRayQueryParameters2D.create(Vector2(10008, -8), Vector2(10008, 32), arrow_mask)
		check.expect(space.intersect_ray(through).get("collider") == target, "Arrow detects target beyond tile %d" % atlas_x)
	# Exercise the real archer's scaled capsule against the platform.
	var archer := preload("res://player/arrow_player/arrow_player.tscn").instantiate()
	check.pawn.scale = archer.scale
	archer.free()
	for x in range(-3, 4):
		fixture.set_cell(Vector2i(x, 0), 0, Vector2i(8, 0), 2)
	await check.teleport(Vector2(10008, -20))
	check.expect(check.pawn.is_on_floor(), "Scaled archer lands on platform")
	check.pawn.position = Vector2(10008, 16)
	check.pawn.velocity = Vector2(0, -290)
	var rose_above := false
	for frame in range(60):
		await check.tick()
		rose_above = rose_above or check.pawn.position.y < -10
	check.expect(rose_above and check.pawn.is_on_floor() and check.pawn.position.y < 0, "Scaled archer jumps through and lands on top")
	check.pawn.scale = Vector2.ONE
	# Original solid stone still stops arrow sweeps.
	fixture.set_cell(Vector2i.ZERO, 0, Vector2i(9, 0), 0)
	await check.physics_frame
	await check.physics_frame
	var cover := PhysicsRayQueryParameters2D.create(Vector2(9992, 3), Vector2(10024, 3), arrow_mask)
	check.expect(not space.intersect_ray(cover).is_empty(), "Solid cover still blocks arrows")
	fixture.free()
	target.free()
	limits.collision_layer = limits_layer
