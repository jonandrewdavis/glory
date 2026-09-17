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
		# Retain the collision platform but draw an open metal grating over the gap.
		floor_layer.self_modulate.a = 0.0
		var old_grate := keep.get_node_or_null("MurderHoleGrating")
		if old_grate:
			old_grate.free()
		var grate := Node2D.new()
		grate.name = "MurderHoleGrating"
		keep.add_child(grate)
		grate.owner = level
		for x in range(920, 1176, 8):
			var bar := Line2D.new()
			bar.points = PackedVector2Array([Vector2(side * x, -288), Vector2(side * (x + 4), -284)])
			bar.width = 2
			bar.default_color = Color(0.65, 0.69, 0.72)
			grate.add_child(bar)
			bar.owner = level
		var lip := keep.get_node("BalconyLip") as TileMapLayer
		lip.position = Vector2(side * 928 - 8, -320)
		lip.clear()
		lip.set_cell(Vector2i.ZERO, 0, Vector2i(9, 0))
		lip.set_cell(Vector2i(0, 1), 0, Vector2i(9, 0))
		var left := 1008 if side > 0 else -1024
		var wall := PackedVector2Array([Vector2(left, -384), Vector2(left + 16, -384), Vector2(left + 16, -320), Vector2(left, -320)])
		keep.get_node("GateWall/Collision").polygon = wall
		keep.get_node("GateStone").polygon = wall
