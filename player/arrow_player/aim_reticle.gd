extends Node2D
const Trajectory := preload("res://player/arrow_player/trajectory_preview.gd")
## Local-only bounded virtual cursor; the visible reticle stays on a fixed radius.
@export_range(24.0, 160.0) var radius := 96.0
@export_range(16.0, 240.0) var mouse_radius := 80.0

var sensitivity := 5.0

var direction := Vector2.RIGHT
var _mouse_offset := Vector2.ZERO
var _trajectory_dots := PackedVector2Array()

func _ready() -> void:
	_on_sensitivity_changed(GGT_GameConfig.get_aim_sensitivity())
	GGT_GameConfig.aim_sensitivity_changed.connect(_on_sensitivity_changed)
	_mouse_offset = direction * mouse_radius
	position = direction * radius
	hide()

func _on_sensitivity_changed(value: float) -> void:
	sensitivity = value * 100.0

func set_direction(value: Vector2) -> void:
	direction = value.normalized()
	_mouse_offset = direction * mouse_radius
	position = direction * radius
	queue_redraw()

func apply_mouse_motion(motion: Vector2) -> void:
	_mouse_offset = (_mouse_offset + motion * (sensitivity / 100.0)).limit_length(mouse_radius)
	# Preserve the last valid aim when passing exactly through the origin.
	if _mouse_offset.length_squared() > 0.01:
		direction = _mouse_offset.normalized()
	position = direction * radius
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _can_aim() and event is InputEventMouseMotion:
		apply_mouse_motion(event.screen_relative)
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	visible = _can_aim()
	position = direction * radius
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if not _can_aim():
		_trajectory_dots.clear()
		return
	var player: ArrowPlayer = get_parent()
	var launch_velocity := direction * player.compute_arrow_speed(player.selected_level)
	var points := Trajectory.predict(get_world_2d().direct_space_state, player.global_position, launch_velocity,
		Arrow.ignored_rids(get_tree(), player.peer_id, player.team), 1.0 / Engine.physics_ticks_per_second)
	_trajectory_dots = Trajectory.dots(Trajectory.first_half(points))

func _can_aim() -> bool:
	var player := get_parent()
	return player.is_multiplayer_authority() and not player.is_dead and not player._is_paused() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _draw() -> void:
	# Leave room around the player for the charging arc.
	for i in range(4, _trajectory_dots.size()):
		var dot := to_local(_trajectory_dots[i])
		var progress := float(i) / maxf(_trajectory_dots.size() - 1, 1.0)
		var alpha := 0.65 * (1.0 - 0.7 * smoothstep(0.75, 1.0, progress))
		draw_circle(dot, 1.8, Color(0.04, 0.06, 0.09, alpha), true, -1.0, true)
		draw_circle(dot, 0.8, Color(1.0, 1.0, 1.0, alpha), true, -1.0, true)
	#draw_circle(Vector2.ZERO, 3.0, Color(0.04, 0.06, 0.09, 0.9), false, 3.0, true)
	#draw_circle(Vector2.ZERO, 3.0, Color.WHITE, false, 1.0, true)
	#for axis in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		#draw_line(axis * 5.0, axis * 8.0, Color(0.04, 0.06, 0.09, 0.9), 3.0, true)
		#draw_line(axis * 5.0, axis * 8.0, Color.WHITE, 1.0, true)
