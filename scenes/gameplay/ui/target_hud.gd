extends Control
class_name TargetHud

@export var bracket_size := 48.0
@export var bracket_acquire_size := 120.0
@export var bracket_color := Color.CYAN
@export var candidate_dot_radius := 4.0
@export var candidate_color := Color(1, 1, 1, 0.5)
@export var reticle_radius := 6.0

var locked: Node3D
var candidates: Array[Node3D] = []
var acquire_candidate: Node3D
var acquire_progress := 0.0

var locked_screen := Vector2.ZERO
var locked_visible := false
var acquire_screen := Vector2.ZERO
var acquire_visible := false
var candidate_screens: PackedVector2Array = []

func update_targets(p_locked: Node3D, p_candidates: Array[Node3D], p_acquire: Node3D, p_progress: float) -> void:
	locked = p_locked
	candidates = p_candidates
	acquire_candidate = p_acquire
	acquire_progress = p_progress

func clear() -> void:
	locked = null
	candidates = []
	acquire_candidate = null
	acquire_progress = 0.0

func _project(camera: Camera3D, node: Node3D) -> Variant:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return null
	var pos := node.global_position
	if camera.is_position_behind(pos):
		return null
	return camera.unproject_position(pos)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	locked_visible = false
	acquire_visible = false
	candidate_screens = []
	if camera:
		var l = _project(camera, locked)
		if l != null:
			locked_screen = l
			locked_visible = true
		var a = _project(camera, acquire_candidate)
		if a != null:
			acquire_screen = a
			acquire_visible = true
		for candidate in candidates:
			var c = _project(camera, candidate)
			if c != null:
				candidate_screens.append(c)
	queue_redraw()

func _draw() -> void:
	draw_arc(size / 2.0, reticle_radius, 0.0, TAU, 24, bracket_color, 1.5)
	for p in candidate_screens:
		draw_circle(p, candidate_dot_radius, candidate_color)
	if locked_visible:
		_draw_bracket(locked_screen, bracket_size, bracket_color)
	elif acquire_visible:
		var s := lerpf(bracket_acquire_size, bracket_size, acquire_progress)
		var c := bracket_color
		c.a = 0.5
		_draw_bracket(acquire_screen, s, c)

func _draw_bracket(center: Vector2, s: float, color: Color) -> void:
	var half := s / 2.0
	var arm := s / 4.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := center + Vector2(sx * half, sy * half)
			var pts := PackedVector2Array([
				corner + Vector2(0, -sy * arm),
				corner,
				corner + Vector2(-sx * arm, 0),
			])
			draw_polyline(pts, color, 2.0)
