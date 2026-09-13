extends Node
class_name AimLook

@export var sensitivity := 0.05
@export var invert_y := false
@export var yaw_limit_deg := 180.0
@export var pitch_limit_deg := 80.0
@export var return_speed := 8.0
@export var look_action := "secondary"
@export_range(0.0, 1.0) var high_speed_penalty := 0.5

var yaw := 0.0
var speed_ratio := 0.0
var pitch := 0.0
var enabled := false:
	set(value):
		enabled = value
		set_process(enabled)
		set_process_input(enabled)

func _ready() -> void:
	set_process(enabled)
	set_process_input(enabled)
	var config := get_node_or_null("/root/GGT_GameConfig")
	if config:
		sensitivity = config.get_aim_sensitivity()
		config.aim_sensitivity_changed.connect(func(value: float) -> void: sensitivity = value)

func _input(event: InputEvent) -> void:
	if not enabled or not is_looking():
		return
	if event is InputEventMouseMotion:
		apply_motion(event.screen_relative)

func set_speed_ratio(value: float) -> void:
	speed_ratio = clampf(value, 0.0, 1.0)

func speed_scale() -> float:
	return lerpf(1.0, 1.0 - high_speed_penalty, speed_ratio)

func apply_motion(rel: Vector2) -> void:
	var s := deg_to_rad(sensitivity) * speed_scale()
	yaw -= rel.x * s
	pitch -= rel.y * s * (-1.0 if invert_y else 1.0)
	yaw = clampf(yaw, -deg_to_rad(yaw_limit_deg), deg_to_rad(yaw_limit_deg))
	pitch = clampf(pitch, -deg_to_rad(pitch_limit_deg), deg_to_rad(pitch_limit_deg))

func _process(delta: float) -> void:
	if is_looking():
		return
	var weight := 1.0 - exp(-return_speed * delta)
	yaw = lerpf(yaw, 0.0, weight)
	pitch = lerpf(pitch, 0.0, weight)
	if absf(yaw) < 1e-4:
		yaw = 0.0
	if absf(pitch) < 1e-4:
		pitch = 0.0

func is_looking() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed(look_action)

func offset_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))

func reset() -> void:
	yaw = 0.0
	pitch = 0.0
