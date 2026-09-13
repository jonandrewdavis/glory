extends Node3D

signal signal_target_changed(new_target)

@export var target:Node3D : set = set_target
@export var position_follow := 20.0
@export var pitch_follow := 1.0
@export var yaw_follow := 2.0
@export var roll_follow := 2.0

var look_provider: AimLook
var _follow_euler := Vector3.ZERO

func _ready():
	# This rig is driven every render frame in _process. With project-wide physics
	# interpolation on, Godot would also interpolate it between physics ticks, which
	# fights the per-frame update and causes stutter. Opt the rig (and its Camera3D) out.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	signal_target_changed.connect(func(_target: Node3D): get_node("Camera3D").current = true)

func set_target(new_node: Node3D):
	target = new_node
	signal_target_changed.emit(new_node)
	if is_inside_tree() and is_instance_valid(target):
		global_transform = target.global_transform
		_follow_euler = target.global_basis.get_euler()
		reset_physics_interpolation()

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	# Follow the render-interpolated transform, not the raw 60 Hz physics one, so the
	# camera and the player advance together every frame.
	var tf := target.get_global_transform_interpolated()
	var e := tf.basis.get_euler()
	global_position = global_position.lerp(tf.origin, 1.0 - exp(-position_follow * delta))
	_follow_euler.x = lerp_angle(_follow_euler.x, e.x, 1.0 - exp(-pitch_follow * delta))
	_follow_euler.y = lerp_angle(_follow_euler.y, e.y, 1.0 - exp(-yaw_follow * delta))
	_follow_euler.z = lerp_angle(_follow_euler.z, e.z, 1.0 - exp(-roll_follow * delta))
	var offset := look_provider.offset_basis() if is_instance_valid(look_provider) else Basis.IDENTITY
	global_basis = Basis.from_euler(_follow_euler) * offset
