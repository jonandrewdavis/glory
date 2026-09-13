extends CharacterBody3D
class_name PlayerMage

## Speed / turning / feel levers. Presets in res://player/mage/profiles/.
@export var profile: MageFlightProfile:
	set(value):
		profile = value
		if profile == null or not is_node_ready():
			return
		current_speed = clampf(current_speed, profile.min_speed, profile.max_speed)
		_turn_velocity = Vector3.ZERO
## Debug only: F1..F9 hot-swap to these profiles at runtime (authority, debug builds).
@export var debug_profiles: Array[MageFlightProfile] = []
@export_group("Network Smoothing")
## How fast remote peers converge on the last received state (higher = tighter, lower = smoother).
@export_range(1.0, 60.0, 0.5) var smoothing_speed := 12.0
## Remote peers snap instead of lerping when the error exceeds this distance (respawn, teleport, long hitch).
@export_range(1.0, 500.0, 1.0) var snap_distance := 25.0
@export_group("")
@onready var trail_3d: Trail3D = %Trail3D

#@onready var prop = $Plane2/Plane/propellor
@onready var player_mage_mesh: Node3D = %Rat
@onready var collision_shape: CollisionShape3D = %CollisionShape3D
@onready var targeting: TargetingSystem = %TargetingSystem
@onready var weapon: Weapon = %BeamWeapon
@onready var health: HealthComponent = %HealthComponent
@onready var mana: ManaComponent = %ManaComponent
@onready var arena_tracker: ArenaTracker = %ArenaTracker
@onready var aim_look: AimLook = %AimLook
@onready var muzzle: Marker3D = %Muzzle

var current_speed := 0.0
var turn_input =  Vector2()
var _turn_velocity := Vector3.ZERO # rad/s per axis (pitch, yaw, roll), smoothed toward stick target
var _velocity_dir := Vector3.FORWARD # travel direction, lags facing when profile.drift > 0
var _spawn_transform := Transform3D.IDENTITY
## Replicated by MultiplayerSynchronizer. Authority writes these; remote peers interpolate toward them.
var net_position := Vector3.ZERO
var net_quaternion := Quaternion.IDENTITY

func _enter_tree() -> void:
	set_multiplayer_authority(int(name))

func _ready() -> void:
	# First debug slot wins so the F1 profile is what you spawn with.
	if not debug_profiles.is_empty() and debug_profiles[0] != null:
		profile = debug_profiles[0]
	if profile == null:
		profile = MageFlightProfile.new()
	current_speed = profile.base_speed
	_reset_motion_state()
	_spawn_transform = global_transform
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	targeting.enabled = is_multiplayer_authority()
	aim_look.enabled = is_multiplayer_authority()
	weapon.set_owner_body(self)
	if is_multiplayer_authority():
		_publish_net_state()
	else:
		# Remote peers are driven from _process; engine physics interpolation would only add lag.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_snap_to_net_state()
		var sync := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
		if sync != null:
			sync.synchronized.connect(_on_first_sync, CONNECT_ONE_SHOT)
	if is_multiplayer_authority():
		World.fly_cam.target = self
		World.fly_cam.look_provider = aim_look
		trail_3d.color = Color.from_string("d03cff", Color.MAGENTA)
		trail_3d.color.a = 0.3
		#trail_3d.billboard_mode = Trail3D.BillboardMode.NONE

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var span := maxf(profile.max_speed - profile.min_speed, 0.001)
	aim_look.set_speed_ratio((current_speed - profile.min_speed) / span)
	var aim := aim_look.offset_basis()
	targeting.basis = aim
	muzzle.basis = aim
	targeting.tick(delta)
	if not health.is_alive():
		velocity = Vector3.ZERO
		_publish_net_state()
		weapon.update_weapon(delta, false, null)
		render_ui_layer_elements()
		return
	var input = Input.get_vector("left","right","down","up")
	var roll = clampf(Input.get_axis("roll_left","roll_right"), -1.0, 1.0)
	turn_input = input

	_update_speed(delta)
	velocity = _travel_direction(delta) * current_speed
	move_and_slide()
	var turn_dir = Vector3(-turn_input.y,-turn_input.x,-roll)
	apply_rotation(turn_dir,delta)
	turn_input = Vector2()
	_publish_net_state()
	arena_tracker.tick(delta, self)
	if not health.is_alive():
		weapon.update_weapon(delta, false, null)
		render_ui_layer_elements()
		return
	var firing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("primary")
	firing = firing and mana.drain(weapon.mana_per_second, delta)
	weapon.update_weapon(delta, firing, targeting.locked_target)

	# TODO: Effects for speed up, speed down... mesh
	#spin_propellor(delta)

	render_ui_layer_elements()

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		return
	_smooth_to_net_state(delta)

## Authority: copy the simulated transform into the replicated fields.
func _publish_net_state() -> void:
	net_position = global_position
	net_quaternion = global_basis.get_rotation_quaternion()

## Remote peer: move toward the last received state, snapping on large errors.
func _smooth_to_net_state(delta: float) -> void:
	if global_position.distance_to(net_position) > snap_distance:
		_snap_to_net_state()
		return
	var weight := minf(smoothing_speed * delta, 1.0)
	global_position = global_position.lerp(net_position, weight)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(net_quaternion, weight))

func _snap_to_net_state() -> void:
	global_position = net_position
	global_basis = Basis(net_quaternion)

func _on_first_sync() -> void:
	# The first delta sync after spawn can carry a stale spawn transform; lock to it rather than lerp.
	_snap_to_net_state()

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not is_multiplayer_authority() or debug_profiles.is_empty():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index := key.keycode - KEY_F1
	if index < 0 or index >= debug_profiles.size() or debug_profiles[index] == null:
		return
	set_profile(debug_profiles[index])
	print("Flight profile: ", profile.display_name)
	get_viewport().set_input_as_handled()

func set_profile(value: MageFlightProfile) -> void:
	profile = value

func _reset_motion_state() -> void:
	_turn_velocity = Vector3.ZERO
	_velocity_dir = -basis.z

func _update_speed(delta: float) -> void:
	var boosting := Input.is_action_pressed("throttle_up") and mana.drain(profile.boost_mana_per_second, delta)
	if boosting:
		current_speed = move_toward(current_speed, profile.max_speed, profile.acceleration * delta)
		trail_3d.width = move_toward(current_speed / 100, profile.max_speed / 100, (profile.acceleration  / 2) * delta)
	elif Input.is_action_pressed("throttle_down"):
		current_speed = move_toward(current_speed, profile.min_speed, profile.deceleration * delta)
		trail_3d.width = move_toward(current_speed / 100, profile.min_speed / 100, (profile.deceleration / 2) * delta)
	else:
		var rate := profile.deceleration if current_speed > profile.base_speed else profile.acceleration
		current_speed = move_toward(current_speed, profile.base_speed, rate * delta)

	var trail_rate := profile.deceleration if current_speed > profile.base_speed else profile.acceleration
	trail_3d.width = move_toward(trail_3d.width, current_speed / 100, (trail_rate / 2) * delta)

## Direction of travel for this frame. On rails unless the profile has drift.
func _travel_direction(delta: float) -> Vector3:
	var facing := -basis.z
	if profile.drift <= 0.0:
		_velocity_dir = facing
		return facing
	var weight := 1.0 - exp(-profile.drift_follow_rate() * delta)
	_velocity_dir = _velocity_dir.slerp(facing, weight).normalized()
	return _velocity_dir

## Signed bank angle relative to the horizon, radians. 0 = wings level, positive = rolled right.
func bank_angle() -> float:
	return atan2(basis.x.dot(Vector3.UP), basis.y.dot(Vector3.UP))

## Roll toward level with the horizon. Called only when there is no stick input.
func _auto_level(delta: float) -> void:
	if profile.auto_level_speed <= 0.0:
		return
	# Near vertical the horizon is ambiguous; leave the roll alone.
	if absf(basis.z.dot(Vector3.UP)) > 0.95:
		return
	var bank := bank_angle()
	var step := minf(deg_to_rad(profile.auto_level_speed) * delta, absf(bank))
	rotate(basis.z, -signf(bank) * step)

## vector = (pitch, yaw, roll) stick input in -1..1.
func apply_rotation(vector: Vector3, delta: float) -> void:
	var target := Vector3(
		vector.x * profile.pitch_rad(),
		vector.y * profile.yaw_rad(),
		vector.z * profile.roll_rad())
	# Lose turn authority at high speed.
	if profile.high_speed_turn_penalty > 0.0:
		var span := maxf(profile.max_speed - profile.min_speed, 0.001)
		var t := clampf((current_speed - profile.min_speed) / span, 0.0, 1.0)
		target *= lerpf(1.0, 1.0 - profile.high_speed_turn_penalty, t)
	# Ramp angular velocity toward the target; frame-rate independent. 60 = no smoothing.
	var weight := 1.0
	if profile.turn_responsiveness < 60.0:
		weight = 1.0 - exp(-profile.turn_responsiveness * delta)
	_turn_velocity = _turn_velocity.lerp(target, weight)
	rotate(basis.z, _turn_velocity.z * delta)
	rotate(basis.x, _turn_velocity.x * delta)
	rotate(basis.y, _turn_velocity.y * delta)
	if vector.is_zero_approx():
		_auto_level(delta)
	#lean mesh
	var lean := deg_to_rad(profile.mesh_lean_degrees)
	var lean_delta := profile.mesh_lean_speed * delta
	if vector.y < 0:
		player_mage_mesh.rotation.z = lerp_angle(player_mage_mesh.rotation.z, -lean * -vector.y, lean_delta)
	elif vector.y > 0:
		player_mage_mesh.rotation.z = lerp_angle(player_mage_mesh.rotation.z, lean * vector.y, lean_delta)
	else:
		player_mage_mesh.rotation.z = lerp_angle(player_mage_mesh.rotation.z, 0, lean_delta)

func render_ui_layer_elements():
	if World.ui_layer:
		World.ui_layer.throttle_progress_bar.max_value = profile.max_speed
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
		arena_tracker.clear_feedback()
		targeting.enabled = false
		aim_look.enabled = false
		aim_look.reset()

func _on_respawned() -> void:
	if is_multiplayer_authority():
		arena_tracker.reset()
		global_transform = _spawn_transform
		reset_physics_interpolation()
		_publish_net_state()
		current_speed = profile.base_speed
		_reset_motion_state()
		mana.refill()
		targeting.enabled = true
		aim_look.enabled = true
	else:
		_snap_to_net_state()
	trail_3d.clear()
	player_mage_mesh.visible = true
	trail_3d.visible = true
	collision_shape.set_deferred("disabled", false)
	add_to_group("targetable")

@rpc("authority", "call_local", "reliable")
func explode_out_of_bounds() -> void:
	var burst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	burst.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.35, 0.05, 0.85)
	burst.material_override = material
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position
	var tween := burst.create_tween().set_parallel(true)
	tween.tween_property(burst, "scale", Vector3.ONE * 12.0, 0.5)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.5)
	tween.chain().tween_callback(burst.queue_free)

#func spin_propellor(delta):
	#var m = current_speed/profile.max_speed
	#prop.rotate_z(150*delta*m)
	#if prop.rotation.z > TAU:
		#prop.rotation.z = 0

#func _on_mouse_analog_input_analog_input(analog: Vector2) -> void:
	#if not use_wasd:
		#turn_input = analog
