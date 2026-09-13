extends CharacterBody3D
class_name PlayerMage

@export var MAX_SPEED := 80.0 #meters per second
@export var MIN_SPEED := 20.0
@export var base_speed := 50.0
@export var acceleration := 15.5
@export var decceleration := 10.5
@export var boost_mana_per_second := 20.0
@onready var trail_3d: Trail3D = %Trail3D

@export var yaw_speed := 45.0 #degrees per second
@export var pitch_speed := 45.0
@export var roll_speed := 45.0

#@onready var prop = $Plane2/Plane/propellor
@onready var player_mage_mesh: Node3D = %Rat
@onready var collision_shape: CollisionShape3D = %CollisionShape3D
@onready var targeting: TargetingSystem = %TargetingSystem
@onready var weapon: Weapon = %BeamWeapon
@onready var health: HealthComponent = %HealthComponent
@onready var mana: ManaComponent = %ManaComponent

var current_speed := 0.0
var turn_input =  Vector2()
var _spawn_transform := Transform3D.IDENTITY

func _enter_tree() -> void:
	set_multiplayer_authority(int(name))

func _ready() -> void:
	pitch_speed = deg_to_rad(pitch_speed)
	yaw_speed = deg_to_rad(yaw_speed)
	roll_speed = deg_to_rad(roll_speed)
	current_speed = base_speed
	_spawn_transform = global_transform
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	targeting.enabled = is_multiplayer_authority()
	weapon.set_owner_body(self)
	if is_multiplayer_authority():
		World.fly_cam.target = self
		trail_3d.color = Color.from_string("d03cff", Color.MAGENTA)
		trail_3d.color.a = 0.3
		trail_3d.billboard_mode = Trail3D.BillboardMode.NONE

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	targeting.tick(delta)
	if not health.is_alive():
		velocity = Vector3.ZERO
		weapon.update_weapon(delta, false, null)
		render_ui_layer_elements()
		return
	var input = Input.get_vector("left","right","down","up")
	var roll = clampf(Input.get_axis("roll_left","roll_right"), -1.0, 1.0)
	turn_input = input

	_update_speed(delta)
	velocity = -basis.z * current_speed
	move_and_slide()
	var turn_dir = Vector3(-turn_input.y,-turn_input.x,-roll)
	apply_rotation(turn_dir,delta)
	turn_input = Vector2()
	var firing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("primary")
	firing = firing and mana.drain(weapon.mana_per_second, delta)
	weapon.update_weapon(delta, firing, targeting.locked_target)

	# TODO: Effects for speed up, speed down... mesh
	#spin_propellor(delta)

	render_ui_layer_elements()

func _update_speed(delta: float) -> void:
	var boosting := Input.is_action_pressed("throttle_up") and mana.drain(boost_mana_per_second, delta)
	if boosting:
		current_speed = move_toward(current_speed, MAX_SPEED, acceleration * delta)
	elif Input.is_action_pressed("throttle_down"):
		current_speed = move_toward(current_speed, MIN_SPEED, decceleration * delta)
	else:
		var rate := decceleration if current_speed > base_speed else acceleration
		current_speed = move_toward(current_speed, base_speed, rate * delta)

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
		World.ui_layer.health_progress_bar.max_value = health.max_value
		World.ui_layer.health_progress_bar.value = health.current
		World.ui_layer.mana_progress_bar.max_value = mana.max_value
		World.ui_layer.mana_progress_bar.value = mana.current
		World.ui_layer.target_hud.update_targets(targeting.locked_target, targeting.candidates, targeting.acquire_candidate, targeting.acquire_progress())

func _on_died(_source: Node) -> void:
	player_mage_mesh.visible = false
	trail_3d.visible = false
	collision_shape.set_deferred("disabled", true)
	remove_from_group("targetable")
	if is_multiplayer_authority():
		targeting.enabled = false

func _on_respawned() -> void:
	if is_multiplayer_authority():
		global_transform = _spawn_transform
		current_speed = base_speed
		mana.refill()
		targeting.enabled = true
	trail_3d.clear()
	player_mage_mesh.visible = true
	trail_3d.visible = true
	collision_shape.set_deferred("disabled", false)
	add_to_group("targetable")

#func spin_propellor(delta):
	#var m = current_speed/MAX_SPEED
	#prop.rotate_z(150*delta*m)
	#if prop.rotation.z > TAU:
		#prop.rotation.z = 0

#func _on_mouse_analog_input_analog_input(analog: Vector2) -> void:
	#if not use_wasd:
		#turn_input = analog
