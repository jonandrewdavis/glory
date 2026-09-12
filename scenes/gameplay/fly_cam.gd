extends Node3D

signal signal_target_changed(new_target)

@export var target:Node3D : set = set_target

func _ready():
	signal_target_changed.connect(func(_target: Node3D): get_node("Camera3D").current = true)

func set_target(new_node: Node3D):
	target = new_node
	signal_target_changed.emit(new_node)

func _process(delta: float) -> void:
	if target: 
		position = lerp(position,target.position,20*delta)
		rotation.x = lerp_angle(rotation.x,target.rotation.x,1*delta)
		rotation.y = lerp_angle(rotation.y,target.rotation.y,2*delta)
		rotation.z = lerp_angle(rotation.z,target.rotation.z,2*delta)
