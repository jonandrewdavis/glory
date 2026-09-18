extends RefCounted
## Shared bake-time geometry update; never runs during gameplay.

static func apply(level: Node2D) -> void:
	level.get_node("StaticBodyLimits/Top").position.y = -16384
	var cover_tiles: TileSet = preload("res://assets/sprites/oak_tileset.tres").duplicate()
	cover_tiles.set_physics_layer_collision_layer(0, 32)
	for node in level.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer.is_in_group("fortress_one_way_platforms"):
			layer.add_to_group("fortress_arrow_transparent_platforms", true)
			for cell in layer.get_used_cells():
				layer.set_cell(cell, 0, layer.get_cell_atlas_coords(cell), 2)
		elif "/ForwardOutpost/" in str(level.get_path_to(layer)):
			layer.tile_set = cover_tiles
	for side in [-1, 1]:
		var keep := level.get_node("Blue/Keep" if side < 0 else "Orange/Keep")
		var floor_layer := keep.get_node("LowerBalcony") as TileMapLayer
		floor_layer.position = Vector2(side * 1048 - 128, -288)
		floor_layer.clear()
		for x in range(16):
			floor_layer.set_cell(Vector2i(x, 0), 0, Vector2i(8 + x % 3, 0), 2)
		floor_layer.self_modulate.a = 1.0
		var old_grate := keep.get_node_or_null("MurderHoleGrating")
		if old_grate:
			old_grate.free()
		var lip := keep.get_node("BalconyLip") as TileMapLayer
		lip.position = Vector2(side * 928 - 8, -320)
		lip.clear()
		lip.set_cell(Vector2i.ZERO, 0, Vector2i(9, 0))
		lip.set_cell(Vector2i(0, 1), 0, Vector2i(9, 0))
		var left := 1008 if side > 0 else -1024
		var wall := PackedVector2Array([Vector2(left, -384), Vector2(left + 16, -384), Vector2(left + 16, -320), Vector2(left, -320)])
		keep.get_node("GateWall/Collision").polygon = wall
		keep.get_node("GateStone").polygon = wall
		_gate_access(level, keep, side)

static func _gate_access(level: Node2D, keep: Node, side: int) -> void:
	# Replace only generated access geometry, making repeated upgrades safe.
	var previous := keep.get_node_or_null("GateAccess")
	if previous:
		previous.free()
	var access := Node2D.new()
	access.name = "GateAccess"
	keep.add_child(access)
	access.owner = level
	var barrier := StaticBody2D.new()
	barrier.name = "TimberBarrier"
	barrier.collision_layer = 32
	barrier.collision_mask = 0
	barrier.position = Vector2(side * 1032, -208)
	access.add_child(barrier)
	barrier.owner = level
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(48, 96)
	collider.shape = shape
	barrier.add_child(collider)
	collider.owner = level
	for i in range(3):
		keep.get_node("Climb%d" % (i + 1)).position = Vector2(side * (1136 - 24 * i) - 48, -192 - 32 * i)
