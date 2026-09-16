extends SceneTree
## Bake editable native nodes into Fortress1; no runtime generation is required.
## Run: Godot --headless --path . --script tools/build_fortress.gd

const LEVEL_PATH := "res://levels/Fortress1.tscn"
const OAK := preload("res://assets/sprites/oak_tileset.tres")
const BLUE := Color(0.72, 0.87, 1.0)
const ORANGE := Color(1.0, 0.82, 0.66)
var level: Node2D

func _initialize() -> void:
	level = load(LEVEL_PATH).instantiate()
	root.add_child(level)
	current_scene = level
	call_deferred("_build")

func _build() -> void:
	for node_name in ["Blockout", "StaticBodyLimits/Sprite2D"]:
		var old := level.get_node_or_null(node_name)
		if old != null:
			old.free()
	level.get_node("StaticBodyLimits").collision_layer = 1
	level.get_node("StaticBodyLimits").collision_mask = 1
	level.get_node("StaticBodyLimits/Bottom").position.y = 320
	level.get_node("StaticBodyLimits/Left").position.x = -2560
	level.get_node("StaticBodyLimits/Right").position.x = 2560
	level.get_node("StaticBodyLimits/Top").position.y = -800
	var blockout := branch(level, "Blockout")
	var sky := polygon(blockout, "Sky", rect_points(Rect2(-8192, -8192, 16384, 16384)), Color(0.12, 0.15, 0.19))
	sky.z_index = -10
	for side in [-1, 1]:
		build_side(blockout, side)
	# Preserve multiplayer's existing names and spawn groups.
	for team in ["Blue", "Orange"]:
		var side := -1 if team == "Blue" else 1
		var positions := [Vector2(2496, -176), Vector2(2352, -176),
			Vector2(960, -48), Vector2(880, -48)]
		for i in range(4):
			level.get_node("SpawnPoints/%s%d" % [team, i + 1]).position = positions[i] * Vector2(side, 1)
		for i in range(3):
			var marker_name := "Creep%s%d" % [team, i + 1]
			var marker := level.get_node_or_null("SpawnPoints/" + marker_name) as Marker2D
			if marker == null:
				marker = Marker2D.new()
				attach(level.get_node("SpawnPoints"), marker, marker_name)
			marker.position = Vector2(side * (2128 + i * 24), -176)
			marker.add_to_group("creep_spawn_%s" % team.to_lower(), true)
	var packed := PackedScene.new()
	var error := packed.pack(level)
	if error == OK:
		error = ResourceSaver.save(packed, LEVEL_PATH)
	if error == OK:
		error = ResourceSaver.set_uid(LEVEL_PATH, ResourceUID.text_to_id("uid://du110eaumrcto"))
	print("Fortress bake: ", error_string(error))
	await process_frame
	quit(error)

func attach(parent: Node, child: Node, node_name: String) -> void:
	child.name = node_name
	parent.add_child(child)
	child.owner = level

func branch(parent: Node, node_name: String) -> Node2D:
	var node := Node2D.new()
	attach(parent, node, node_name)
	return node

func polygon(parent: Node, node_name: String, points: PackedVector2Array, color: Color) -> Polygon2D:
	var node := Polygon2D.new()
	node.polygon = points
	node.color = color
	attach(parent, node, node_name)
	return node

func line(parent: Node, node_name: String, points: PackedVector2Array, color: Color, width: float) -> void:
	var node := Line2D.new()
	node.points = points
	node.width = width
	node.default_color = color
	attach(parent, node, node_name)

func rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func solid(parent: Node, node_name: String, points: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	attach(parent, body, node_name)
	var shape := CollisionPolygon2D.new()
	shape.polygon = points
	attach(body, shape, "Collision")

func tiles(parent: Node, node_name: String, tint: Color, collisions: bool) -> TileMapLayer:
	var node := TileMapLayer.new()
	node.tile_set = OAK
	node.modulate = tint
	node.collision_enabled = collisions
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	attach(parent, node, node_name)
	return node

func build_side(parent: Node2D, side: int) -> void:
	var team := branch(parent, "Blue" if side < 0 else "Orange")
	var tint := BLUE if side < 0 else ORANGE
	# Twice the original width; retain three main tiers but add traversable dips.
	var bend := Vector2(688, 32) if side < 0 else Vector2(704, 36)
	var outer_bend := Vector2(1696, -96) if side < 0 else Vector2(1712, -100)
	var profile := PackedVector2Array([Vector2(0, 96), Vector2(256, 96),
		Vector2(320, 64), Vector2(432, 64), Vector2(496, 96), Vector2(544, 96),
		bend, Vector2(832, -32), Vector2(1008, -32),
		Vector2(1072, 16), Vector2(1152, 16), Vector2(1216, -32),
		Vector2(1552, -32), outer_bend, Vector2(1840, -160),
		Vector2(1904, -160), Vector2(1968, -112), Vector2(2016, -112),
		Vector2(2080, -160), Vector2(2560, -160)])
	for i in range(profile.size()):
		profile[i].x *= side
	var earth := profile.duplicate()
	earth.append(Vector2(side * 2560, 320))
	earth.append(Vector2(0, 320))
	polygon(team, "Earth", earth, Color(0.20, 0.16, 0.13) * tint)
	solid(team, "TerrainWorld", earth)
	# Fill only fully buried cells: one continuous collider handles the ramps.
	var fill := tiles(team, "OakGround", tint, false)
	for x in range(160):
		var left_y := surface_y(profile, x * 16, side)
		var right_y := surface_y(profile, (x + 1) * 16, side)
		var surface := maxf(left_y, right_y)
		for y in range(int(ceil(surface / 16.0)), 20):
			var cell_x := x if side > 0 else -x - 1
			var top := is_equal_approx(left_y, right_y) and is_equal_approx(y * 16.0, surface)
			fill.set_cell(Vector2i(cell_x, y), 0, Vector2i(8 + (x % 3), 0) if top else Vector2i(1, 1))
	line(team, "RampSurface", profile, Color(0.52, 0.53, 0.51) * tint, 3.0)
	# A restrained color band follows each side and fades toward neutral at x=0.
	var band_points := profile.duplicate()
	for i in range(profile.size() - 1, -1, -1):
		band_points.append(profile[i] + Vector2(0, 9))
	var band := polygon(team, "TeamEdge", band_points, Color.WHITE)
	var colors := PackedColorArray()
	for point in band_points:
		var color := tint
		color.a = 0.55 * clampf(absf(point.x) / 240.0, 0.0, 1.0)
		colors.append(color)
	band.vertex_colors = colors
	build_keep(team, side, tint)
	build_outpost(team, side, tint)
	build_field_features(team, side, tint)
	# Low forward platforms break up the approach without dividing the center.
	platform(team, "ForwardCover", side, 176, 64, 64, tint)
	cover(team, "ForwardLip", side, 152, 48, tint)

func surface_y(profile: PackedVector2Array, x: float, side: int) -> float:
	for i in range(profile.size() - 1):
		var a := profile[i] * Vector2(side, 1)
		var b := profile[i + 1] * Vector2(side, 1)
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return -160.0

func platform(parent: Node, node_name: String, side: int, center: int, y: int, width: int, tint: Color, arrow_transparent: bool = false) -> void:
	var layer := tiles(parent, node_name, tint, true)
	layer.position = Vector2(side * center - width / 2, y)
	layer.add_to_group("fortress_one_way_platforms", true)
	if arrow_transparent:
		layer.add_to_group("fortress_arrow_transparent_platforms", true)
	for x in range(width / 16):
		layer.set_cell(Vector2i(x, 0), 0, Vector2i(8 + x % 3, 0), 2 if arrow_transparent else 1)

func cover(parent: Node, node_name: String, side: int, x: int, y: int, tint: Color) -> void:
	var layer := tiles(parent, node_name, tint, true)
	layer.position = Vector2(side * x - 8, y)
	layer.set_cell(Vector2i.ZERO, 0, Vector2i(9, 0))

func mirrored_rect(side: int, x: float, y: float, width: float, height: float) -> Rect2:
	return Rect2(x if side > 0 else -x - width, y, width, height)

func facade(parent: Node, node_name: String, side: int, center: int, top: int, bottom: int, width: int, tint: Color) -> void:
	var face := polygon(parent, node_name, rect_points(Rect2(side * center - width / 2, top, width, bottom - top)), Color(0.32, 0.35, 0.39) * tint)
	face.z_index = -2
	for y in range(top + 16, bottom, 32):
		line(face, "Course%d" % absi(y), PackedVector2Array([Vector2(side * center - width / 2, y), Vector2(side * center + width / 2, y)]), Color(0.25, 0.28, 0.30) * tint, 1)

func climb(parent: Node, side: int, center: int, bottom: int, steps: int, tint: Color) -> void:
	for step in range(steps):
		platform(parent, "Climb%d" % (step + 1), side, center + (-16 if step % 2 == 0 else 16), bottom - 32 * (step + 1), 96, tint, true)

func battlements(parent: Node, node_name: String, side: int, center: int, y: int, width: int, tint: Color) -> void:
	var deck := branch(parent, node_name)
	platform(deck, "Deck", side, center, y, width, tint, true)
	# Leave a broad central opening above the climbing route.
	for offset in [-width / 2 + 8, -width / 2 + 40, width / 2 - 40, width / 2 - 8]:
		cover(deck, "Merlon%d" % offset, side, center + offset, y - 16, tint)

func flag(parent: Node, side: int, center: int, y: int, tint: Color) -> void:
	var x := side * center
	line(parent, "FlagPole", PackedVector2Array([Vector2(x, y), Vector2(x, y - 48)]), tint, 2)
	polygon(parent, "TeamFlag", rect_points(mirrored_rect(side, center, y - 48, 32, 16)), tint)

func build_keep(parent: Node, side: int, tint: Color) -> void:
	var keep := branch(parent, "Keep")
	keep.add_to_group("fortress_keeps", true)
	keep.set_meta("team", "blue" if side < 0 else "orange")
	facade(keep, "CurtainWall", side, 2352, -352, -160, 320, tint)
	facade(keep, "Gatehouse", side, 2240, -416, -160, 160, tint)
	facade(keep, "GreatTower", side, 2432, -544, -160, 176, tint)
	var front_stairs := branch(keep, "GatehouseStairs")
	climb(front_stairs, side, 2256, -160, 7, tint)
	battlements(keep, "GatehouseParapet", side, 2240, -416, 192, tint)
	var rear_stairs := branch(keep, "GreatTowerStairs")
	climb(rear_stairs, side, 2432, -160, 11, tint)
	battlements(keep, "CrownParapet", side, 2432, -544, 208, tint)
	platform(keep, "CurtainWalk", side, 2352, -352, 288, tint, true)
	for x in [2320, 2368]:
		cover(keep, "CurtainMerlon%d" % x, side, x, -368, tint)
	# Lower balcony exits through a 32px opening above the main gate.
	platform(keep, "GateBalcony", side, 2176, -288, 208, tint, true)
	cover(keep, "GateBalconyLip", side, 2080, -304, tint)
	platform(keep, "HighBalcony", side, 2384, -448, 240, tint, true)
	for x in [2272, 2496]:
		cover(keep, "HighBalconyLip%d" % x, side, x, -464, tint)
	# Front wall is solid except for the main gate and balcony doorway.
	for span in [Vector2(-416, 96), Vector2(-288, 32)]:
		var points := rect_points(mirrored_rect(side, 2160, span.x, 16, span.y))
		solid(keep, "GateWall%d" % absi(int(span.x)), points)
		polygon(keep, "GateStone%d" % absi(int(span.x)), points, Color(0.48, 0.50, 0.51) * tint)
	build_gate(keep, side, tint)
	flag(keep, side, 2432, -544, tint)

func build_gate(parent: Node, side: int, tint: Color) -> void:
	var gate := branch(parent, "MainGate")
	gate.add_to_group("fortress_gates", true)
	gate.set_meta("placeholder", true)
	gate.set_meta("team", "blue" if side < 0 else "orange")
	gate.set_meta("objective", "Enemy battering ram breaches this gate; damage and breach logic deferred.")
	var shape := rect_points(mirrored_rect(side, 2160, -256, 48, 96))
	polygon(gate, "GateTimber", shape, Color(0.39, 0.27, 0.17))
	for x in range(2168, 2208, 12):
		line(gate, "Plank%d" % x, PackedVector2Array([Vector2(side * x, -252), Vector2(side * x, -164)]), Color(0.18, 0.14, 0.12), 2)
	for y in [-240, -184]:
		polygon(gate, "IronBand%d" % -y, rect_points(mirrored_rect(side, 2160, y, 48, 6)), Color(0.55, 0.57, 0.59) * tint)
	var target := Marker2D.new()
	target.position = Vector2(side * 2158, -208)
	attach(gate, target, "RamImpactPoint")
	label(gate, "GateLabel", "GATE", Vector2(side * 2184, -280), tint)

func label(parent: Node, node_name: String, text: String, center: Vector2, tint: Color) -> void:
	var node := Label.new()
	node.text = text
	node.position = center - Vector2(80, 0)
	node.size.x = 160
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_theme_font_size_override("font_size", 11)
	node.modulate = tint
	attach(parent, node, node_name)


func build_outpost(parent: Node, side: int, tint: Color) -> void:
	var outpost := branch(parent, "ForwardOutpost")
	outpost.add_to_group("fortress_outposts", true)
	facade(outpost, "Watchtower", side, 912, -160, -32, 112, tint)
	climb(outpost, side, 912, -32, 3, tint)
	platform(outpost, "LookoutDeck", side, 912, -160, 144, tint, true)
	for x in [848, 976]:
		cover(outpost, "RoofLip%d" % x, side, x, -176, tint)
	platform(outpost, "FiringShelf", side, 864, -96, 128, tint, true)
	cover(outpost, "ShelfLip", side, 808, -112, tint)
	cover(outpost, "LowBarricade", side, 856, -48, tint)
	flag(outpost, side, 944, -160, tint)

func build_field_features(parent: Node, side: int, tint: Color) -> void:
	var field := branch(parent, "FieldFeatures")
	# A low central berm and roof provide a second covered approach.
	platform(field, "BermShelter", side, 384, 32, 96, tint)
	cover(field, "BermLip", side, 344, 16, tint)
	# Broken bridge: walk down into the shallow trench or hop between remnants.
	platform(field, "BridgeInnerStub", side, 1040, -32, 64, tint)
	platform(field, "BridgeOuterStub", side, 1184, -32, 64, tint)
	platform(field, "SunkenBridgeStone", side, 1112 if side < 0 else 1120, -16, 32, tint)
	# An intentionally lopsided lookout on splayed legs is the oddball landmark.
	var perch_x := 1424 if side < 0 else 1408
	for offset in [-32, 32]:
		line(field, "LeaningLeg%d" % offset, PackedVector2Array([Vector2(side * (perch_x + offset), -32), Vector2(side * (perch_x + offset / 2 + 8), -128)]), Color(0.39, 0.42, 0.45) * tint, 5)
	platform(field, "PerchStep1", side, perch_x - 64, -64, 64, tint)
	platform(field, "PerchStep2", side, perch_x - 32, -96, 64, tint)
	platform(field, "CrookedPerch", side, perch_x, -128, 96, tint)
	cover(field, "PerchLip", side, perch_x + 40, -144, tint)
	# The dry moat has walkable sides and a short refuge shelf along its floor.
	platform(field, "MoatRefuge", side, 1984, -144, 48, tint)
