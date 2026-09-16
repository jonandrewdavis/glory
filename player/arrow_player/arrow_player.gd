class_name ArrowPlayer
extends CharacterBody2D
## Owner-driven archer. The owning peer runs input/physics and replicates
## state through the MultiplayerSynchronizer; the host judges arrow hits.

const SPEED_MAX := 100.0
const JUMP_VELOCITY := -290.0
const ACCELERATION := 17.5
const FRICTION := 8.0
const FIRE_COOLDOWN := 0.5

@export_group("Charge")
@export_range(0.0, 2.0, 0.05) var minimum_charge_time := 0.5
@export var charge_level_durations: Array[float] = [2.0, 2.0, 2.0]
@export var charge_perfect_window := 0.8 ## last N seconds of each level
## Maps progress within a level (0..1) to strength (0..1) for that level.
@export var charge_curves: Array[Curve] = [
	preload("res://player/arrow_player/charge_curves/level_1_linear.tres"),
	preload("res://player/arrow_player/charge_curves/level_2_linear.tres"),
	preload("res://player/arrow_player/charge_curves/level_3_linear.tres"),
]
## Static speed steps. Level N fires at steps[N] (normal) or steps[N + 1]
## (perfect), so each level's normal shot equals the previous level's perfect.
@export var charge_speed_steps: Array[float] = [300.0, 420.0, 560.0, 720.0]
@export var charge_damage: Array[float] = [25.0, 35.0, 50.0]
## x = length factor, y = thickness factor of the arrow per level.
@export var charge_arrow_scales: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(1.1, 1.6), Vector2(1.2, 2.2)]

@export_group("Shield")
@export var shield_duration := 0.7
@export var shield_cooldown := 2.0
@export var shield_reflect_speed_mult := 1.1

var peer_id := 0
var team: int = Teams.Team.BLUE
var spawn_index := 0

var is_blocking := false
var block_time_left := 0.0
var shield_cooldown_left := 0.0

var charge_time := 0.0
var is_charging := false
var _shot_queued := false ## released early; fires at the live reticle aim once the minimum is reached
var _charge_level_shown := -1
var is_dead := false
var fire_cooldown_left := 0.0

# Host-only bookkeeping.
var _server_last_fire_msec := -100000
var _server_last_hit_by := 0

@onready var sprite: AnimatedSprite2D = %AnimatedSprite2D
@onready var health: HealthComponent = %HealthComponent
@onready var arrow_container: Node2D = %ArrowContainer
@onready var aim_reticle: Node2D = %AimReticle
@onready var charge_arc: Node2D = %ChargeArc
@onready var shield_container: Node2D = %ShieldContainer
@onready var shield_polygon: Polygon2D = %ShieldPolygon2D
@onready var shield_boss: Polygon2D = %ShieldBoss
@onready var shield_area: Area2D = %ShieldArea
@onready var shield_collision: CollisionPolygon2D = %ShieldCollision
@onready var name_label: Label = %NameLabel
@onready var stuck_arrows: Node2D = %StuckArrows

func _enter_tree() -> void:
	peer_id = name.to_int()
	set_multiplayer_authority(peer_id)
	get_node("HealthComponent").set_multiplayer_authority(1)
	get_node("HealthSynchronizer").set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("players")
	_apply_team_colors()
	name_label.text = MultiplayerService.get_username(peer_id)
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

	if can_act and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY * (0.55 if (is_charging or is_blocking) else 1.0)

	_update_charge_input(delta, mouse, can_act, Input.is_action_pressed("primary"), Input.is_action_just_released("primary"))

	if can_act and Input.is_action_just_pressed("secondary") and not is_charging and not is_blocking and shield_cooldown_left <= 0.0:
		_start_block(mouse)

	var direction := Input.get_axis("left", "right") if can_act else 0.0
	var speed_mult := 1.0
	if not is_on_floor():
		speed_mult = 0.97
	elif is_charging or is_blocking:
		speed_mult = 0.5
	var weight := delta * (ACCELERATION if direction != 0.0 else FRICTION)
	velocity.x = lerpf(velocity.x, direction * SPEED_MAX * speed_mult, weight)
	move_and_slide()

	if not is_dead:
		sprite.flip_h = aim_reticle.direction.x < 0.0
		if not is_charging:
			sprite.play("walk" if absf(velocity.x) > 5.0 else "idle")

func _is_paused() -> bool:
	return World.ui_layer != null and World.ui_layer.is_paused()

func capture_mouse() -> void:
	if is_multiplayer_authority() and not _is_paused():
		if World.ui_layer == null or not World.ui_layer.exiting:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- Charge / fire ---------------------------------------------------------

func _update_charge_input(delta: float, mouse: Vector2, can_act: bool, held: bool, released: bool) -> void:
	if not can_act:
		if is_charging or _shot_queued:
			_cancel_charge()
		return
	if _shot_queued:
		_charge(minf(delta, maxf(minimum_charge_time - charge_time, 0.0)), mouse)
		if charge_time >= minimum_charge_time:
			_fire(mouse)
		return
	if held and not is_blocking and fire_cooldown_left <= 0.0:
		_charge(delta, mouse)
	elif released and not is_blocking and fire_cooldown_left <= 0.0:
		# Also catch a press/release shorter than one physics tick.
		if not is_charging:
			_charge(0.0, mouse)
		if charge_time < minimum_charge_time:
			_shot_queued = true
		else:
			_fire(mouse)
	elif is_charging:
		_cancel_charge()

func _charge(delta: float, mouse: Vector2) -> void:
	is_charging = true
	charge_time = minf(charge_time + delta, charge_total())
	var level := charge_level(charge_time)
	if level != _charge_level_shown:
		_apply_charge_level(level)
	var perfect := is_perfect(charge_time)
	arrow_container.show()
	arrow_container.look_at(mouse)
	charge_arc.display_state = Vector4(1.0, charge_strength(charge_time), float(level), 1.0 if perfect else 0.0)
	charge_arc.readiness = Vector3(charge_strength(minimum_charge_time), 1.0 if charge_time >= minimum_charge_time else 0.0, perfect_threshold_fill(level))
	sprite.play("attack")

## Grows the aiming arrow when a new charge level is reached.
func _apply_charge_level(level: int) -> void:
	_charge_level_shown = level
	arrow_container.scale = _level_vec(charge_arrow_scales, level, Vector2.ONE)

func _cancel_charge() -> void:
	is_charging = false
	_shot_queued = false
	charge_time = 0.0
	_charge_level_shown = -1
	arrow_container.hide()
	arrow_container.scale = Vector2.ONE
	charge_arc.reset()

func _fire(mouse: Vector2) -> void:
	if charge_time < minimum_charge_time:
		return
	var aim := (mouse - global_position).normalized()
	var t := charge_time
	_cancel_charge()
	fire_cooldown_left = FIRE_COOLDOWN
	if aim.is_zero_approx():
		return
	if multiplayer.is_server():
		server_fire(aim, t)
	else:
		request_fire.rpc_id(1, aim, t)

# --- Charge levels (pure helpers over the exported tuning) -----------------

func charge_total() -> float:
	var total := 0.0
	for d in charge_level_durations:
		total += d
	return total

## 0-based level for a hold time; clamps to the last level past the end.
func charge_level(t: float) -> int:
	var elapsed := 0.0
	for i in charge_level_durations.size():
		elapsed += charge_level_durations[i]
		if t < elapsed:
			return i
	return maxi(charge_level_durations.size() - 1, 0)

## Seconds into the current level.
func _level_elapsed(t: float) -> float:
	var level := charge_level(t)
	var start := 0.0
	for i in level:
		start += charge_level_durations[i]
	return t - start

## 0..1 within the current level (1 once past the end of the last level).
func level_progress(t: float) -> float:
	if charge_level_durations.is_empty():
		return 0.0
	var duration: float = charge_level_durations[charge_level(t)]
	return clampf(_level_elapsed(t) / maxf(duration, 0.001), 0.0, 1.0)

## Inside the last charge_perfect_window seconds of a level. Once the final
## level's window is reached it stays perfect no matter how long the hold.
func is_perfect(t: float) -> bool:
	if charge_level_durations.is_empty():
		return false
	var duration: float = charge_level_durations[charge_level(t)]
	return _level_elapsed(t) >= duration - charge_perfect_window

## 0..1 bar fill within the current level, shaped by that level's curve (visual only).
func charge_strength(t: float) -> float:
	return _strength_at_progress(charge_level(t), level_progress(t))

## Bar fill at which a level's perfect window opens (visual only).
func perfect_threshold_fill(level: int) -> float:
	if charge_level_durations.is_empty():
		return 1.0
	var duration: float = charge_level_durations[clampi(level, 0, charge_level_durations.size() - 1)]
	var progress := clampf(1.0 - charge_perfect_window / maxf(duration, 0.001), 0.0, 1.0)
	return _strength_at_progress(level, progress)

func _strength_at_progress(level: int, progress: float) -> float:
	if level < charge_curves.size() and charge_curves[level] != null:
		return clampf(charge_curves[level].sample(progress), 0.0, 1.0)
	return progress

## Two static speeds per level: normal, or perfect when released in the window.
func compute_arrow_speed(t: float) -> float:
	t = maxf(t, 0.0)
	var step := charge_level(t) + (1 if is_perfect(t) else 0)
	return _level_value(charge_speed_steps, step, 300.0)

func _level_value(values: Array, level: int, fallback: float) -> float:
	if values.is_empty():
		return fallback
	return values[clampi(level, 0, values.size() - 1)]

func _level_vec(values: Array, level: int, fallback: Vector2) -> Vector2:
	if values.is_empty():
		return fallback
	return values[clampi(level, 0, values.size() - 1)]

@rpc("any_peer", "call_remote", "reliable")
func request_fire(aim: Vector2, t: float) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	server_fire(aim, t)

## Host only.
func server_fire(aim: Vector2, t: float) -> void:
	if not is_finite(t) or t < minimum_charge_time:
		return
	if not multiplayer.is_server() or not health.is_alive() or aim.is_zero_approx():
		return
	var now := Time.get_ticks_msec()
	if now - _server_last_fire_msec < int(FIRE_COOLDOWN * 1000.0 * 0.8):
		return
	_server_last_fire_msec = now
	aim = aim.normalized()
	t = clampf(t, 0.0, charge_total() + 1.0)
	var level := charge_level(t)
	World.projectile_spawner.spawn_arrow({
		"position": global_position,
		"velocity": aim * compute_arrow_speed(t),
		"owner_id": peer_id,
		"team": team,
		"damage": _level_value(charge_damage, level, 35.0),
		"scale": _level_vec(charge_arrow_scales, level, Vector2.ONE),
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
	aim_reticle.hide()
	charge_arc.reset()
	sprite.play("death")
	arrow_container.hide()
	if is_multiplayer_authority():
		_cancel_charge()
		if is_blocking:
			_end_block()
	shield_container.hide()

func _on_respawned() -> void:
	is_dead = false
	_clear_stuck_arrows()
	sprite.play("idle")
	if is_multiplayer_authority():
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
	reset_physics_interpolation()
