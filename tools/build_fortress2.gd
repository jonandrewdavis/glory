extends SceneTree
## Bake the compact Fortress2 scene as editable native nodes.
## Godot --headless --path . --script tools/build_fortress2.gd

const LEVEL_PATH := "res://levels/Fortress2.tscn"
const OAK := preload("res://assets/sprites/oak_tileset.tres")
const BLUE := Color(0.72, 0.87, 1.0)
const ORANGE := Color(1.0, 0.82, 0.66)
var level: Node2D

func _initialize() -> void:
	if "--upgrade-defenses" in OS.get_cmdline_user_args():
		level = load(LEVEL_PATH).instantiate()
		root.add_child(level)
		current_scene = level
		call_deferred("_upgrade_defenses")
		return
	level = Node2D.new()
	level.name = "Fortress2"
	root.add_child(level)
	current_scene = level
	call_deferred("_build")

func _upgrade_defenses() -> void:
	preload("res://tools/fortress2_defenses.gd").apply(level)
	var packed := PackedScene.new()
	var error := packed.pack(level)
	if error == OK:
		error = ResourceSaver.save(packed, LEVEL_PATH)
	print("Fortress2 defense upgrade: ", error_string(error))
	quit(error)

func _build() -> void:
	var sky := polygon(level, "Sky", rect_points(Rect2(-8192, -8192, 16384, 16384)), Color(0.12, 0.15, 0.19))
	sky.z_index = -10
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://assets/shaders/Fortress2.gdshader")
	sky.material = sky_material
	sky.set_script(load("res://scenes/gameplay/sky_parallax.gd"))
	build_limits()
	for side in [-1, 1]:
		build_side(side)
	build_center()
	build_ram()
	build_spawns()
	preload("res://tools/fortress2_defenses.gd").apply(level)
	var packed := PackedScene.new()
	var error := packed.pack(level)
	if error == OK:
		error = ResourceSaver.save(packed, LEVEL_PATH)
	print("Fortress2 bake: ", error_string(error))
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

func mirrored_rect(side: int, x: float, y: float, width: float, height: float) -> Rect2:
	return Rect2(x if side > 0 else -x - width, y, width, height)

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

func build_limits() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	attach(level, body, "StaticBodyLimits")
	for data in [
		["Bottom", Vector2(0, 320), Vector2.UP],
		["Left", Vector2(-1280, 0), Vector2.RIGHT],
		["Right", Vector2(1280, 0), Vector2.LEFT],
		["Top", Vector2(0, -640), Vector2.DOWN],
	]:
		var collision := CollisionShape2D.new()
		collision.position = data[1]
		var boundary := WorldBoundaryShape2D.new()
		boundary.normal = data[2]
		collision.shape = boundary
		attach(body, collision, data[0])

func build_side(side: int) -> void:
	var tint := BLUE if side < 0 else ORANGE
	var team := branch(level, "Blue" if side < 0 else "Orange")
	var bend := Vector2(432, 32) if side < 0 else Vector2(440, 36)
	var profile := PackedVector2Array([
		Vector2(0, 96), Vector2(208, 96), Vector2(256, 72), Vector2(320, 72), Vector2(352, 96),
		bend, Vector2(512, -32), Vector2(656, -32), Vector2(704, 0), Vector2(752, 0),
		Vector2(800, -32), Vector2(864, -32), Vector2(1008, -160), Vector2(1280, -160),
	])
	for i in range(profile.size()):
		profile[i].x *= side
	var earth := profile.duplicate()
	earth.append(Vector2(side * 1280, 320))
	earth.append(Vector2(0, 320))
	polygon(team, "Earth", earth, Color(0.20, 0.16, 0.13) * tint)
	solid(team, "TerrainWorld", earth)
	var fill := tiles(team, "OakGround", tint, false)
	for x in range(80):
		var left_y := surface_y(profile, x * 16, side)
		var right_y := surface_y(profile, (x + 1) * 16, side)
		var surface := maxf(left_y, right_y)
		for y in range(int(ceil(surface / 16.0)), 20):
			var cell_x := x if side > 0 else -x - 1
			var top := is_equal_approx(left_y, right_y) and is_equal_approx(y * 16.0, surface)
			fill.set_cell(Vector2i(cell_x, y), 0, Vector2i(8 + x % 3, 0) if top else Vector2i(1, 1))
	line(team, "RampSurface", profile, Color(0.52, 0.53, 0.51) * tint, 3)
	var band_points := profile.duplicate()
	for i in range(profile.size() - 1, -1, -1):
		band_points.append(profile[i] + Vector2(0, 9))
	var band := polygon(team, "TeamEdge", band_points, Color.WHITE)
	var colors := PackedColorArray()
	for point in band_points:
		var color := tint
		color.a = 0.55 * clampf(absf(point.x) / 208.0, 0.0, 1.0)
		colors.append(color)
	band.vertex_colors = colors
	build_keep(team, side, tint)
	build_outpost(team, side, tint)
	build_field(team, side, tint)

func surface_y(profile: PackedVector2Array, x: float, side: int) -> float:
	for i in range(profile.size() - 1):
		var a := profile[i] * Vector2(side, 1)
		var b := profile[i + 1] * Vector2(side, 1)
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return -160.0

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
	facade(keep, "KeepFacade", side, 1160, -384, -160, 224, tint)
	climb(keep, side, 1160, -160, 6, tint)
	battlements(keep, "CrownParapet", side, 1160, -384, 240, tint)
	platform(keep, "LowerBalcony", side, 1088, -288, 176, tint, true)
	cover(keep, "BalconyLip", side, 1008, -304, tint)
	platform(keep, "UpperBalcony", side, 1192, -352, 160, tint, true)
	for x in [1120, 1264]:
		cover(keep, "UpperLip%d" % x, side, x, -368, tint)
	# Solid front wall above the open gate; the wooden gate itself is visual only.
	var wall := rect_points(mirrored_rect(side, 1008, -384, 16, 128))
	solid(keep, "GateWall", wall)
	polygon(keep, "GateStone", wall, Color(0.48, 0.50, 0.51) * tint)
	build_gate(keep, side, tint)
	flag(keep, side, 1160, -384, tint)

func build_gate(parent: Node, side: int, tint: Color) -> void:
	var gate := branch(parent, "MainGate")
	var shape := rect_points(mirrored_rect(side, 1008, -256, 48, 96))
	polygon(gate, "GateTimber", shape, Color(0.39, 0.27, 0.17))
	for x in range(1016, 1056, 12):
		line(gate, "Plank%d" % x, PackedVector2Array([Vector2(side * x, -252), Vector2(side * x, -164)]), Color(0.18, 0.14, 0.12), 2)
	for y in [-240, -184]:
		polygon(gate, "IronBand%d" % -y, rect_points(mirrored_rect(side, 1008, y, 48, 6)), Color(0.55, 0.57, 0.59) * tint)
	# The damageable objective is its own scene; MainGate is art only.
	var objective: Node2D = load("res://entities/fortress_gate.tscn").instantiate()
	objective.team = Teams.Team.BLUE if side < 0 else Teams.Team.ORANGE
	objective.position = Vector2(side * 1006, -208)
	attach(parent, objective, "FortressGate")

func build_outpost(parent: Node, side: int, tint: Color) -> void:
	var outpost := branch(parent, "ForwardOutpost")
	outpost.add_to_group("fortress_outposts", true)
	facade(outpost, "Watchtower", side, 608, -160, -32, 112, tint)
	climb(outpost, side, 608, -32, 3, tint)
	battlements(outpost, "Lookout", side, 608, -160, 144, tint)
	platform(outpost, "FiringShelf", side, 560, -96, 112, tint, true)
	cover(outpost, "LowBarricade", side, 544, -48, tint)

func build_field(parent: Node, side: int, tint: Color) -> void:
	# Broken bridge and a stepping stone span the shallow middle trench.
	platform(parent, "BridgeInner", side, 672, -32, 48, tint)
	platform(parent, "BridgeOuter", side, 784, -32, 48, tint)
	platform(parent, "TrenchStone", side, 728 if side < 0 else 736, -16, 32, tint)
	# A small offset perch keeps the compact field from reading as perfectly mirrored.
	var perch_x := 880 if side < 0 else 864
	platform(parent, "PerchStep", side, perch_x - 40, -64, 48, tint)
	platform(parent, "Perch", side, perch_x, -96, 80, tint)

func build_center() -> void:
	# Neutral bridge over the trench with a climbable tower in the middle.
	# Every platform here, including the roof, is an arrow-transparent one-way platform.
	var center := branch(level, "Center")
	center.add_to_group("fortress_center_towers", true)
	center.set_meta("team", "neutral")
	var tint := Color.WHITE
	var deck_y := -24
	platform(center, "BridgeDeck", 1, 0, deck_y, 352, tint, true)
	for side in [-1, 1]:
		var ramp := branch(center, "RampBlue" if side < 0 else "RampOrange")
		# Three 32-pixel hops: y=72 shelf -> 40 -> 8 -> deck.
		platform(ramp, "Step1", side, 240, 40, 64, tint, true)
		platform(ramp, "Step2", side, 200, 8, 64, tint, true)
	var tower := branch(center, "Tower")
	var roof_y := deck_y - 96
	var back := polygon(tower, "Backdrop", rect_points(Rect2(-72, roof_y, 144, 96)), Color(0.24, 0.26, 0.28))
	back.z_index = -2
	for side in [-1, 1]:
		var post := rect_points(Rect2(side * 56 - 6, roof_y, 12, 96))
		var art := polygon(tower, "PostBlue" if side < 0 else "PostOrange", post, Color(0.42, 0.44, 0.46))
		art.z_index = -1
	# Two staggered steps inside the tower lead from the deck up onto the roof.
	climb(tower, 1, 0, deck_y, 2, tint)
	platform(tower, "Roof", 1, 0, roof_y, 160, tint, true)

func build_ram() -> void:
	var ram: Node2D = load("res://entities/battering_ram.tscn").instantiate()
	ram.route = PackedVector2Array([
		Vector2(-1006, -160), Vector2(-1008, -160), Vector2(-864, -32),
		Vector2(-800, -32), Vector2(-752, 0), Vector2(-704, 0), Vector2(-656, -32),
		Vector2(-512, -32), Vector2(-432, 32), Vector2(-352, 96), Vector2(0, 96),
		Vector2(352, 96), Vector2(440, 36), Vector2(512, -32), Vector2(656, -32),
		Vector2(704, 0), Vector2(752, 0), Vector2(800, -32), Vector2(864, -32),
		Vector2(1008, -160), Vector2(1006, -160),
	])
	attach(level, ram, "BatteringRam")

func build_spawns() -> void:
	var spawns := branch(level, "SpawnPoints")
	for team in ["Blue", "Orange"]:
		var side := -1 if team == "Blue" else 1
		var positions := [Vector2(1216, -176), Vector2(1104, -176), Vector2(640, -48), Vector2(560, -48)]
		for i in range(4):
			var marker := Marker2D.new()
			marker.position = positions[i] * Vector2(side, 1)
			marker.add_to_group("spawn_%s" % team.to_lower(), true)
			attach(spawns, marker, "%s%d" % [team, i + 1])
		for i in range(3):
			var marker := Marker2D.new()
			marker.position = Vector2(side * (1006 + i * 24), -176)
			marker.add_to_group("creep_spawn_%s" % team.to_lower(), true)
			attach(spawns, marker, "Creep%s%d" % [team, i + 1])
