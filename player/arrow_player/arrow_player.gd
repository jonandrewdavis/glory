class_name ArrowPlayer
extends CharacterBody2D
## Owner-driven archer. The owning peer runs input/physics and replicates
## state through the MultiplayerSynchronizer; the host judges arrow hits.

const SPEED_MAX := 100.0
const JUMP_VELOCITY := -290.0
const FIRE_COOLDOWN := 0.5

@export_group("Movement Feel")
@export var acceleration := 1700.0
@export var braking := 2200.0
@export var reversal_acceleration := 2400.0
@export var coyote_time := 0.10
@export var jump_buffer_time := 0.12
@export_range(0.0, 1.0) var jump_cut_factor := 0.5
@export_range(0.01, 1.0) var facing_threshold := 0.15
## How long the dropped platform stays passable after pressing down.
@export var drop_through_time := 0.25

var _facing := 1
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _jump_consumed := false
var _jump_cut := false
var _drop_through_left := 0.0
var _drop_exceptions: Array[RID] = []

const LEVEL_COUNT := 3
const LEVEL_ACTIONS := [&"select_arrow_level_1", &"select_arrow_level_2", &"select_arrow_level_3"]

@export_group("Arrow Levels")
@export var level_minimum_times: Array[float] = [0.8, 1.6, 2.4]
@export var level_speeds: Array[float] = [756.0, 1008.0, 1296.0]
@export var level_damage: Array[float] = [25.0, 35.0, 50.0]
## x = length factor, y = thickness factor of the arrow per level.
@export var level_arrow_scales: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(1.1, 1.6), Vector2(1.2, 2.2)]

@export_group("Shield")
@export var shield_duration := 0.7
@export var shield_cooldown := 2.0

@export_group("Damage")
## Host-side multiplier for this player's arrows that land in an enemy's HeadHitbox.
@export var headshot_damage_multiplier := 1.5

var peer_id := 0
var team: int = Teams.Team.BLUE
var spawn_index := 0

var is_blocking := false
var block_time_left := 0.0
var shield_cooldown_left := 0.0

var preparation_time := 0.0
var is_preparing := false
var _shot_queued := false ## released early; fires at the live reticle aim once the minimum is reached
var _wait_for_primary_release := false
var selected_level := 0
var is_dead := false
var fire_cooldown_left := 0.0

# Host-only bookkeeping.
var _server_last_fire_msec := -100000
var _server_last_hit_by := 0

@onready var sprite: AnimatedSprite2D = %AnimatedSprite2D
@onready var health: HealthComponent = %HealthComponent
@onready var arrow_container: Node2D = %ArrowContainer
@onready var aim_reticle: Node2D = %AimReticle
@onready var readiness_indicator: Node2D = %ReadinessIndicator
@onready var shield_container: Node2D = %ShieldContainer
@onready var shield_polygon: Polygon2D = %ShieldPolygon2D
@onready var shield_boss: Polygon2D = %ShieldBoss
@onready var shield_area: Area2D = %ShieldArea
@onready var shield_collision: CollisionPolygon2D = %ShieldCollision
@onready var name_label: Label = %NameLabel
@onready var stuck_arrows: Node2D = %StuckArrows
## Editor-visible headshot band; no physics layers, tested by Arrow.is_head_point().
@onready var head_shape: CollisionShape2D = %HeadShape

func _enter_tree() -> void:
	peer_id = name.to_int()
	set_multiplayer_authority(peer_id)
	get_node("HealthComponent").set_multiplayer_authority(1)
	get_node("HealthSynchronizer").set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("players")
	_apply_team_colors()
	if is_multiplayer_authority():
		_update_readiness_indicator()
	name_label.text = MultiplayerService.get_username(peer_id)
	MultiplayerService.username_changed.connect(func(id: int) -> void:
		if id == peer_id:
			name_label.text = MultiplayerService.get_username(peer_id))
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	if multiplayer.is_server():
		health.died.connect(_on_died_server)

	var is_owner := is_multiplayer_authority()
	z_index = 2 if is_owner else 1
	refresh_team_fade()
	if is_owner:
		for other in get_tree().get_nodes_in_group("players"):
			if other != self and other.has_method("refresh_team_fade"):
				other.refresh_team_fade()
	if is_owner:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		_teleport_to_spawn()
		World.camera_rig.set_local_player(self)
		capture_mouse()
		if not World.level_loader.is_level_ready():
			await World.level_loader.level_loaded
			if not is_inside_tree():
				return
			_teleport_to_spawn()
	else:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _apply_team_colors() -> void:
	var color := Teams.color(team)
	sprite.modulate = color
	name_label.modulate = color
	($ArrowContainer/ArrowPolygon2D as Polygon2D).color = color
	shield_polygon.color = Color(color, 0.9)
	shield_boss.color = color.darkened(0.4)

## Same-team peers are drawn slightly translucent so the local player stands
## out; enemies and the local player are fully opaque. Sprite only.
func refresh_team_fade() -> void:
	var local: ArrowPlayer = World.player_spawner.get_player(multiplayer.get_unique_id())
	var faded := local != null and local != self and local.team == team
	sprite.modulate.a = 0.7 if faded else 1.0

# --- Stuck arrows ----------------------------------------------------------

## Parents a landed-arrow visual to this body so it follows the player.
func attach_stuck_arrow(node: StuckArrow, impact_pos: Vector2, impact_rot: float) -> void:
	node.attach_to(stuck_arrows, impact_pos, impact_rot)

func _clear_stuck_arrows() -> void:
	for child in stuck_arrows.get_children():
		child.queue_free()

# --- Physics --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		# Follows replicated state, so it works for remote copies too.
		if shield_area.monitoring != shield_container.visible:
			shield_area.monitoring = shield_container.visible
		if shield_area.monitoring:
			_server_check_shield()
	if is_multiplayer_authority():
		_owner_physics(delta)

func _owner_physics(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	fire_cooldown_left = maxf(fire_cooldown_left - delta, 0.0)
	shield_cooldown_left = maxf(shield_cooldown_left - delta, 0.0)

	var can_act := not is_dead and not _is_paused() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var mouse: Vector2 = global_position + aim_reticle.direction * aim_reticle.radius

	if is_blocking:
		block_time_left -= delta
		shield_container.look_at(mouse)
		if block_time_left <= 0.0:
			_end_block()

	var jump_requested := can_act and Input.is_action_just_pressed("jump")

	if can_act:
		for level in LEVEL_COUNT:
			if Input.is_action_just_pressed(LEVEL_ACTIONS[level]):
				select_level(level)
	_update_shot_input(delta, mouse, can_act, Input.is_action_pressed("primary"), Input.is_action_just_released("primary"), jump_requested)
	_update_jump(delta, can_act, jump_requested, Input.is_action_pressed("jump"), is_on_floor())
	if can_act and Input.is_action_just_pressed("down") and is_on_floor():
		_drop_through_floor()
	_update_drop_through(delta)
	if can_act:
		_update_facing(aim_reticle.direction)

	if can_act and Input.is_action_just_pressed("secondary") and not is_preparing and not is_blocking and shield_cooldown_left <= 0.0:
		_start_block(mouse)

	var direction := Input.get_axis("left", "right") if can_act else 0.0
	var speed_mult := 1.0
	if not is_on_floor():
		speed_mult = 0.97
	elif is_preparing or is_blocking:
		speed_mult = 0.5
	_update_horizontal(delta, direction, speed_mult)
	move_and_slide()
	if is_on_floor():
		_jump_consumed = false

	if not is_dead:
		sprite.flip_h = _facing < 0
		if not is_preparing:
			sprite.play("walk" if absf(velocity.x) > 5.0 else "idle")

func get_facing_direction() -> int:
	return _facing

func _update_facing(aim: Vector2) -> void:
	if aim.x > facing_threshold:
		_facing = 1
	elif aim.x < -facing_threshold:
		_facing = -1

func _update_horizontal(delta: float, direction: float, speed_mult: float) -> void:
	var rate := acceleration
	if direction == 0.0:
		rate = braking
	elif velocity.x * direction < 0.0:
		rate = reversal_acceleration
	velocity.x = move_toward(velocity.x, direction * SPEED_MAX * speed_mult, rate * delta)

func _reset_jump() -> void:
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_jump_consumed = false
	_jump_cut = false

func _update_jump(delta: float, can_act: bool, requested: bool, held: bool, grounded: bool) -> void:
	if not can_act:
		_reset_jump()
		return
	_coyote_left = maxf(_coyote_left - delta, 0.0)
	_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)
	if grounded and not _jump_consumed:
		_coyote_left = coyote_time
	if requested:
		_jump_buffer_left = jump_buffer_time
	if _jump_buffer_left > 0.0 and not _jump_consumed and (grounded or _coyote_left > 0.0):
		velocity.y = JUMP_VELOCITY * (0.55 if is_blocking else 1.0)
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_jump_consumed = true
		_jump_cut = false
	if not held and velocity.y < 0.0 and _jump_consumed and not _jump_cut:
		velocity.y *= jump_cut_factor
		_jump_cut = true

# --- Drop-through -----------------------------------------------------------

## Lets the body fall through whichever one-way platform it is standing on.
## Solid floors are unaffected. Returns true when a platform was released.
func _drop_through_floor() -> bool:
	var dropped := false
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y >= 0.0:
			continue
		var collider := collision.get_collider()
		if collider == null or not collider.is_in_group("fortress_one_way_platforms"):
			continue
		var rid := collision.get_collider_rid()
		if rid in _drop_exceptions:
			dropped = true
			continue
		PhysicsServer2D.body_add_collision_exception(get_rid(), rid)
		_drop_exceptions.append(rid)
		dropped = true
	if dropped:
		_drop_through_left = drop_through_time
		if velocity.y < 0.0:
			velocity.y = 0.0
	return dropped

func _update_drop_through(delta: float) -> void:
	if _drop_exceptions.is_empty():
		return
	_drop_through_left -= delta
	if _drop_through_left <= 0.0:
		_clear_drop_through()

func _clear_drop_through() -> void:
	for rid in _drop_exceptions:
		PhysicsServer2D.body_remove_collision_exception(get_rid(), rid)
	_drop_exceptions.clear()
	_drop_through_left = 0.0

func _is_paused() -> bool:
	return World.ui_layer != null and World.ui_layer.is_paused()

func capture_mouse() -> void:
	if is_multiplayer_authority() and not _is_paused():
		if World.ui_layer == null or not World.ui_layer.exiting:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- Preparation / fire ---------------------------------------------------

func select_level(level: int) -> void:
	if level < 0 or level >= LEVEL_COUNT:
		return
	selected_level = level
	if is_preparing:
		arrow_container.scale = _level_vec(level_arrow_scales, level, Vector2.ONE)
	_update_readiness_indicator()

func minimum_preparation_time(level: int) -> float:
	return maxf(_level_value(level_minimum_times, level, 0.8), 0.0)

func _update_readiness_indicator() -> void:
	var minimum := minimum_preparation_time(selected_level)
	var ready := is_preparing and preparation_time >= minimum
	var fill := clampf(preparation_time / minimum, 0.0, 1.0) if minimum > 0.0 else (1.0 if is_preparing else 0.0)
	readiness_indicator.display_state = Vector4(float(selected_level), 1.0 if is_preparing else 0.0, fill, 1.0 if ready else 0.0)

func _update_shot_input(delta: float, mouse: Vector2, can_act: bool, held: bool, released: bool, cancel_requested := false) -> void:
	if _wait_for_primary_release:
		# Consume the canceled hold's release as well as the hold itself.
		if not held:
			_wait_for_primary_release = false
		return
	if not can_act:
		if is_preparing or _shot_queued:
			_cancel_preparation()
		return
	if cancel_requested and (is_preparing or _shot_queued):
		_cancel_preparation()
		_wait_for_primary_release = held
		return
	if cancel_requested:
		_wait_for_primary_release = held
		return
	if fire_cooldown_left > 0.0 and not is_blocking:
		# Buffer one shot without counting recovery time as preparation.
		if (held or released) and not is_preparing:
			_prepare(0.0, mouse)
		if released and is_preparing:
			_shot_queued = true
		return
	if _shot_queued:
		_prepare(delta, mouse)
		if preparation_time >= minimum_preparation_time(selected_level):
			_fire(mouse)
		return
	if held and not is_blocking and fire_cooldown_left <= 0.0:
		_prepare(delta, mouse)
	elif released and not is_blocking and fire_cooldown_left <= 0.0:
		# Also catch a press/release shorter than one physics tick.
		if not is_preparing:
			_prepare(0.0, mouse)
		if preparation_time < minimum_preparation_time(selected_level):
			_shot_queued = true
		else:
			_fire(mouse)
	elif is_preparing:
		_cancel_preparation()

func _prepare(delta: float, mouse: Vector2) -> void:
	is_preparing = true
	# Do not cap at the current minimum: a later level change keeps all elapsed time.
	preparation_time += delta
	arrow_container.scale = _level_vec(level_arrow_scales, selected_level, Vector2.ONE)
	arrow_container.show()
	arrow_container.look_at(mouse)
	_update_readiness_indicator()
	sprite.play("attack")

func _cancel_preparation() -> void:
	is_preparing = false
	_shot_queued = false
	preparation_time = 0.0
	arrow_container.hide()
	arrow_container.scale = Vector2.ONE
	_update_readiness_indicator()

func _fire(mouse: Vector2) -> void:
	if preparation_time < minimum_preparation_time(selected_level):
		return
	var aim := (mouse - global_position).normalized()
	var elapsed := preparation_time
	var level := selected_level
	_cancel_preparation()
	fire_cooldown_left = FIRE_COOLDOWN
	if aim.is_zero_approx():
		return
	if multiplayer.is_server():
		server_fire(aim, level, elapsed)
	else:
		request_fire.rpc_id(1, aim, level, elapsed)

## Shot strength depends only on the selected level, never on preparation time.
func compute_arrow_speed(level: int) -> float:
	return _level_value(level_speeds, level, 756.0)

func _level_value(values: Array, level: int, fallback: float) -> float:
	if values.is_empty():
		return fallback
	return values[clampi(level, 0, values.size() - 1)]

func _level_vec(values: Array, level: int, fallback: Vector2) -> Vector2:
	if values.is_empty():
		return fallback
	return values[clampi(level, 0, values.size() - 1)]

@rpc("any_peer", "call_remote", "reliable")
func request_fire(aim: Vector2, level: int, elapsed: float) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	server_fire(aim, level, elapsed)

## Host only.
func server_fire(aim: Vector2, level: int, elapsed: float) -> void:
	if level < 0 or level >= LEVEL_COUNT or not is_finite(elapsed):
		return
	if elapsed < minimum_preparation_time(level) or not aim.is_finite():
		return
	if not multiplayer.is_server() or not health.is_alive() or aim.is_zero_approx():
		return
	var now := Time.get_ticks_msec()
	if now - _server_last_fire_msec < int(FIRE_COOLDOWN * 1000.0 * 0.8):
		return
	_server_last_fire_msec = now
	aim = aim.normalized()
	World.projectile_spawner.spawn_arrow({
		"position": global_position,
		"velocity": aim * compute_arrow_speed(level),
		"owner_id": peer_id,
		"team": team,
		"damage": _level_value(level_damage, level, 35.0),
		"scale": _level_vec(level_arrow_scales, level, Vector2.ONE),
		"level": level,
	})

## Host only; called by the arrow before applying damage.
func server_register_hit(shooter_id: int) -> void:
	_server_last_hit_by = shooter_id

# --- Shield ----------------------------------------------------------------

## Owner only.
func _start_block(mouse: Vector2) -> void:
	is_blocking = true
	block_time_left = shield_duration
	shield_container.look_at(mouse)
	shield_container.show()
	shield_collision.set_deferred("disabled", false)

## Owner only.
func _end_block() -> void:
	is_blocking = false
	block_time_left = 0.0
	shield_container.hide()
	shield_collision.set_deferred("disabled", true)
	shield_cooldown_left = shield_cooldown
	fire_cooldown_left = maxf(fire_cooldown_left, FIRE_COOLDOWN)

## Host only. Enemy arrows overlapping the raised shield are reflected.
func _server_check_shield() -> void:
	for area in shield_area.get_overlapping_areas():
		if area is Arrow:
			area.server_touched_shield(self, area.global_position)

# --- Death / respawn -------------------------------------------------------

func _on_died(_source: Node) -> void:
	is_dead = true
	_reset_jump()
	_clear_drop_through()
	aim_reticle.hide()
	readiness_indicator.hide()
	sprite.play("death")
	arrow_container.hide()
	if is_multiplayer_authority():
		_cancel_preparation()
		if is_blocking:
			_end_block()
	shield_container.hide()

func _on_respawned() -> void:
	is_dead = false
	_clear_stuck_arrows()
	sprite.play("idle")
	if is_multiplayer_authority():
		_update_readiness_indicator()
		spawn_index = randi() % PlayerSpawner.SPAWN_SLOTS
		_teleport_to_spawn()
		capture_mouse()

## Host only.
func _on_died_server(_source: Node) -> void:
	World.scoreboard.record_kill(_server_last_hit_by, peer_id)
	_server_last_hit_by = 0

func _teleport_to_spawn() -> void:
	global_position = Teams.spawn_position(get_tree(), team, spawn_index)
	velocity = Vector2.ZERO
	_reset_jump()
	_clear_drop_through()
	reset_physics_interpolation()
	if World.camera_rig != null:
		World.camera_rig.reset_for_relocation(self)
