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
