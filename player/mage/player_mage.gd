extends CharacterBody3D
class_name PlayerMage

@export var MAX_SPEED := 80.0 #meters per second
@export var MIN_SPEED := 20.0
@export var acceleration := 15.5
@export var decceleration := 10.5
@export var current_speed := 50.0
@onready var trail_3d: Trail3D = %Trail3D

@export var yaw_speed := 45.0 #degrees per second
@export var pitch_speed := 45.0
@export var roll_speed := 45.0

#@onready var prop = $Plane2/Plane/propellor
@onready var player_mage_mesh: Node3D = %Rat

var turn_input =  Vector2()

func _enter_tree() -> void:
	set_multiplayer_authority(int(name))

func _ready() -> void:
	pitch_speed = deg_to_rad(pitch_speed)
	yaw_speed = deg_to_rad(yaw_speed)
	roll_speed = deg_to_rad(roll_speed)
	if is_multiplayer_authority():
		World.fly_cam.target = self
		trail_3d.transparency = 0.8

func _physics_process(delta: float) -> void:
	var input = Input.get_vector("left","right","down","up")
	var roll = Input.get_axis("roll_left","roll_right")
	turn_input = input

	var speed_input = Vector2(0.0, Input.get_axis("throttle_down","throttle_up"))
	if speed_input.y > 0 and current_speed < MAX_SPEED:
		current_speed += acceleration * delta
	elif speed_input.y < 0 and current_speed > MIN_SPEED:
		current_speed -= decceleration * delta
	velocity = -basis.z * current_speed
	move_and_slide()
	var turn_dir = Vector3(-turn_input.y,-turn_input.x,-roll)
	apply_rotation(turn_dir,delta)
	turn_input = Vector2()

	# TODO: Effects for speed up, speed down... mesh
	#spin_propellor(delta)

	render_ui_layer_elements()

	
func apply_rotation(vector,delta):
	rotate(basis.z,vector.z * roll_speed * delta)
	rotate(basis.x,vector.x * pitch_speed * delta)
	rotate(basis.y,vector.y * yaw_speed * delta)
	#lean mesh
	if vector.y < 0:
		player_mage_mesh.rotation.z = lerp_angle(player_mage_mesh.rotation.z, deg_to_rad(-45)*-vector.y,delta)
	elif vector.y > 0:
		player_mage_mesh.rotation.z = lerp_angle(player_mage_mesh.rotation.z, deg_to_rad(45)*vector.y,delta)
	else:
		player_mage_mesh.rotation.z = lerp_angle(player_mage_mesh.rotation.z, 0,delta)

func render_ui_layer_elements():
	if World.ui_layer:
		World.ui_layer.throttle_progress_bar.max_value = MAX_SPEED
		World.ui_layer.throttle_progress_bar.value = current_speed

#func spin_propellor(delta):
	#var m = current_speed/MAX_SPEED
	#prop.rotate_z(150*delta*m)
	#if prop.rotation.z > TAU:
		#prop.rotation.z = 0

#func _on_mouse_analog_input_analog_input(analog: Vector2) -> void:
	#if not use_wasd:
		#turn_input = analog
