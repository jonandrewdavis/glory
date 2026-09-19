extends SceneTree

const SCENE := "res://levels/Fortress2.tscn"
const OUT := "/Users/andrewdavis/godot/glory/fortress2_level.png"
const WIDTH := 10000
const REMOVE := ["BatteringRam", "SpawnPoints", "SpawnBands",
	"Blue/Keep/FortressGate", "Orange/Keep/FortressGate"]

func _init() -> void:
	await process_frame
	var level: Node2D = load(SCENE).instantiate()
	for p in REMOVE:
		var n := level.get_node_or_null(p)
		if n: n.get_parent().remove_child(n); n.free()
		else: push_warning("missing " + p)
	var vp := SubViewport.new()
	vp.add_child(level)
	root.add_child(vp)
	var rect := Rect2()
	var first := true
	for c in _all(level):
		if c.name == "Sky": continue
		var r := _bounds(c)
		if r == Rect2(): continue
		rect = r if first else rect.merge(r); first = false
	rect = rect.grow(32)
	print("bounds ", rect, " items=", _all(level).size())
	var scale := float(WIDTH) / rect.size.x
	vp.size = Vector2i(WIDTH, int(ceil(rect.size.y * scale)))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	cam.position = rect.position
	cam.zoom = Vector2(scale, scale)
	vp.add_child(cam)
	cam.make_current()
	await process_frame
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	print("saved ", img.get_size(), " err=", img.save_png(OUT))
	quit()

func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children(): out += _all(c)
	return out

func _bounds(c: Node) -> Rect2:
	if not (c is CanvasItem) or not (c as CanvasItem).is_visible_in_tree(): return Rect2()
	var xf: Transform2D = (c as Node2D).get_global_transform() if c is Node2D else Transform2D()
	var pts := PackedVector2Array()
	if c is Polygon2D: pts = c.polygon
	elif c is Line2D: pts = c.points
	elif c is TileMapLayer:
		var ur: Rect2i = c.get_used_rect()
		if ur.size == Vector2i(): return Rect2()
		var ts: Vector2 = Vector2(c.tile_set.tile_size)
		var a := Vector2(ur.position) * ts; var b := Vector2(ur.end) * ts
		pts = PackedVector2Array([a, b])
	else: return Rect2()
	if pts.is_empty(): return Rect2()
	var r := Rect2(xf * pts[0], Vector2())
	for p in pts: r = r.expand(xf * p)
	return r
