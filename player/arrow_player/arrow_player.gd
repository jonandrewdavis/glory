class_name ArrowPlayer
extends CharacterBody2D
## Owner-driven movement; CombatNetwork publishes accepted server state.

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
## Local-only: the owner's last aim, carried into its next incarnation.
static var _carried_aim := Vector2.ZERO
static var _carried_facing := 1
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
var authoritative_spawn := Vector2.ZERO
var has_authoritative_spawn := false
var spawn_revision := 0
var spawn_serial := 0
var network_away := false:
	set(value):
		if value == network_away:
			return
		if value:
			_away_position = position
		network_away = value
		if is_node_ready():
			if value:
				clear_away_actions()
			_refresh_name()
			refresh_team_fade()
var _away_fade: Tween
var initial_health := -1.0
var _away_position := Vector2.ZERO

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
var network_suspended := false
var server_blocking := false
var presentation := PresentationBuffer.new()
var visual_root: Node2D
var visual_shield: Node2D
var preview_body: Area2D
var preview_shield: Area2D
var _shot_serial := 0
var _visual_dead := false
var _shield_event: Dictionary = {}
const PREVIEW_LAYER := 1 << 20
var recent_attackers: Array[int] = []
var last_hit_reflected := false ## Host only. Whether the latest arrow to hit had bounced off a shield.

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
	if peer_id <= 0:
		peer_id = name.to_int()
	set_multiplayer_authority(peer_id)
	get_node("HealthComponent").set_multiplayer_authority(1)
	get_node("HealthSynchronizer").set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("players")
	_setup_presentation()
	if MultiplayerService.is_dedicated_server():
		sprite.process_mode = Node.PROCESS_MODE_DISABLED
	_apply_team_colors()
	if is_multiplayer_authority():
		_update_readiness_indicator()
	_refresh_name()
	MultiplayerService.username_changed.connect(func(id: int) -> void:
		if id == peer_id:
			_refresh_name())
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	if multiplayer.is_server():
		health.died.connect(_on_died_server)
	if initial_health >= 0.0:
		# Restore without emitting a second kill or scheduling a second death.
		health._initialized = false
		health.current = initial_health
		health._initialized = true
	if not health.is_alive():
		_on_died(null)
	if network_away:
		_away_position = position
		clear_away_actions()

	var is_owner := is_multiplayer_authority()
	z_index = 2 if is_owner else 1
	refresh_team_fade()
	if is_owner:
		for other in get_tree().get_nodes_in_group("players"):
			if other != self and other.has_method("refresh_team_fade"):
				other.refresh_team_fade()
	if is_owner:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		if _carried_aim != Vector2.ZERO:
			aim_reticle.set_direction(_carried_aim)
			_facing = _carried_facing
			sprite.flip_h = _facing < 0
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
	if is_owner and MultiplayerService.presence.blocks_input():
		network_suspended = true
		clear_away_actions()

func _apply_team_colors() -> void:
	var color := Teams.color(team)
	sprite.modulate = color
	name_label.modulate = color
	(arrow_container.get_node("ArrowPolygon2D") as Polygon2D).color = color
	shield_polygon.color = Color(color, 0.9)
	shield_boss.color = color.darkened(0.4)

## Same-team peers are drawn slightly translucent so the local player stands
## out; enemies and the local player are fully opaque. Sprite only.
func refresh_team_fade() -> void:
	if MultiplayerService.is_dedicated_server():
		return
	var local: ArrowPlayer = World.player_spawner.get_player(multiplayer.get_unique_id())
	var faded := local != null and local != self and local.team == team
	var target_alpha := 0.2 if network_away else (0.7 if faded else 1.0)
	if _away_fade:
		_away_fade.kill()
	_away_fade = create_tween()
	_away_fade.tween_property(sprite, "modulate:a", target_alpha, 0.3)

func _refresh_name() -> void:
	name_label.text = MultiplayerService.get_username(peer_id) + (" (AFK)" if network_away else "")

# --- Stuck arrows ----------------------------------------------------------

## Parents a landed-arrow visual to this body so it follows the player.
func attach_stuck_arrow(node: StuckArrow, impact_pos: Vector2, impact_rot: float) -> void:
	node.attach_to(stuck_arrows, impact_pos, impact_rot)

func _clear_stuck_arrows() -> void:
	for child in stuck_arrows.get_children():
		child.queue_free()

# --- Physics --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# An owner can receive the replacement while its new map is still loading.
	if has_authoritative_spawn and (not World.level_loader.is_level_ready() or spawn_revision != World.level_loader.revision):
		hide()
		return
	show()
	if multiplayer.is_server() and MultiplayerService.presence.is_peer_away(peer_id):
		set_network_away(true)
		position = _away_position
		clear_away_actions()
	if multiplayer.is_server():
		if server_blocking and shield_area.monitoring and health.is_alive():
			_server_check_shield()
	if is_multiplayer_authority() and not network_suspended and not network_away and not MultiplayerService.presence.blocks_input():
		_owner_physics(delta)

func _owner_physics(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	fire_cooldown_left = maxf(fire_cooldown_left - delta, 0.0)
	shield_cooldown_left = maxf(shield_cooldown_left - delta, 0.0)

	var can_act: bool = not is_dead and not _is_paused() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (multiplayer.is_server() or World.combat_network.epoch != 0)
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

func _exit_tree() -> void:
	if is_multiplayer_authority():
		_carried_aim = aim_reticle.direction
		_carried_facing = _facing

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
	if is_multiplayer_authority() and not _is_paused() and not MultiplayerService.presence.blocks_input():
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
	if not is_preparing:
		World.combat_network.command(self, CombatNetwork.CHARGE)
	is_preparing = true
	# Do not cap at the current minimum: a later level change keeps all elapsed time.
	preparation_time += delta
	arrow_container.scale = _level_vec(level_arrow_scales, selected_level, Vector2.ONE)
	arrow_container.show()
	arrow_container.look_at(mouse)
	_update_readiness_indicator()
	sprite.play("attack")

func _cancel_preparation(notify_server := true) -> void:
	if notify_server and is_preparing and is_multiplayer_authority():
		World.combat_network.command(self, CombatNetwork.CANCEL)
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
	var level := selected_level
	_cancel_preparation(false)
	fire_cooldown_left = FIRE_COOLDOWN
	if aim.is_zero_approx():
		return
	_shot_serial += 1
	if not MultiplayerService.is_dedicated_server():
		World.projectile_spawner.predict(self, _shot_serial, aim, level)
	World.combat_network.command(self, CombatNetwork.FIRE, _shot_serial)

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

## Host only.
func server_fire(aim: Vector2, level: int, elapsed: float, shot_id: int = 0) -> void:
	if MultiplayerService.presence.is_peer_away(peer_id):
		return
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
		"shot": shot_id, "shooter_serial": spawn_serial,
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
	if not multiplayer.is_server():
		return
	recent_attackers.erase(shooter_id)
	recent_attackers.push_front(shooter_id)
	if recent_attackers.size() > 3:
		recent_attackers.resize(3)

# --- Shield ----------------------------------------------------------------

## Owner only.
func _start_block(mouse: Vector2) -> void:
	is_blocking = true
	block_time_left = shield_duration
	shield_container.look_at(mouse)
	shield_container.show()
	World.combat_network.command(self, CombatNetwork.SHIELD)

## Owner only.
func _end_block() -> void:
	is_blocking = false
	block_time_left = 0.0
	shield_container.hide()
	if not multiplayer.is_server():
		shield_collision.set_deferred("disabled", true)
	shield_cooldown_left = shield_cooldown
	fire_cooldown_left = maxf(fire_cooldown_left, FIRE_COOLDOWN)

## Host only. Enemy arrows overlapping the raised shield are reflected.
func _server_check_shield() -> void:
	if network_away:
		return
	for area in shield_area.get_overlapping_areas():
		if area is Arrow:
			area.server_touched_shield(self, area.global_position)

func set_network_away(value: bool) -> void:
	network_away = value
	if value and is_node_ready():
		clear_away_actions()

func clear_away_actions() -> void:
	velocity = Vector2.ZERO
	shield_cooldown_left = maxf(shield_cooldown_left, shield_cooldown)
	fire_cooldown_left = maxf(fire_cooldown_left, FIRE_COOLDOWN)
	_reset_jump()
	_cancel_preparation()
	is_blocking = false
	block_time_left = 0.0
	shield_container.hide()
	shield_collision.set_deferred("disabled", true)

# --- Death / respawn -------------------------------------------------------

func _on_died(_source: Node) -> void:
	is_dead = true
	_reset_jump()
	_clear_drop_through()
	aim_reticle.hide()
	readiness_indicator.hide()
	if is_multiplayer_authority():
		sprite.play("death")
		arrow_container.hide()
	if multiplayer.is_server():
		World.combat_network.queue_event({"kind": "death", "peer": peer_id, "serial": spawn_serial, "position": global_position})
	if is_multiplayer_authority():
		# Stop movement packets while dead, before this incarnation is despawned.
		network_suspended = true
		_cancel_preparation()
		if is_blocking:
			_end_block()
	shield_container.hide()
	set_server_shield(false, shield_container.rotation)

func _on_respawned() -> void:
	recent_attackers.clear()
	is_dead = false
	_clear_stuck_arrows()
	sprite.play("idle")
	if is_multiplayer_authority():
		network_suspended = false
		presentation.clear()
		_visual_dead = false
		_update_readiness_indicator()
		_teleport_to_spawn()
		capture_mouse()

## Host only.
func _on_died_server(source: Node) -> void:
	var killer_id: int = source.peer_id if source is ArrowPlayer else 0
	World.scoreboard.record_kill(killer_id, peer_id, recent_attackers.slice(1), last_hit_reflected)
	last_hit_reflected = false
	recent_attackers.clear()
	World.respawn_manager.schedule(self)

func _teleport_to_spawn() -> void:
	global_position = authoritative_spawn if has_authoritative_spawn else Teams.spawn_position(get_tree(), team, spawn_index)
	velocity = Vector2.ZERO
	_reset_jump()
	_clear_drop_through()
	reset_physics_interpolation()
	if World.camera_rig != null:
		World.camera_rig.reset_for_relocation(self)

func set_server_shield(active: bool, angle: float) -> void:
	server_blocking = active
	if multiplayer.is_server():
		shield_container.rotation = angle
		shield_collision.set_deferred("disabled", not active)
		shield_area.set_deferred("monitoring", active)

func present_shield(event: Dictionary) -> void:
	if is_multiplayer_authority() or visual_shield == null or _visual_dead:
		return
	_shield_event = event
	visual_shield.visible = event.active
	visual_shield.rotation = event.aim

func _setup_presentation() -> void:
	if MultiplayerService.is_dedicated_server():
		set_process(false)
		return
	visual_root = Node2D.new()
	visual_root.name = "Presentation"
	add_child(visual_root)
	for node: Node2D in [sprite, arrow_container, stuck_arrows]:
		node.reparent(visual_root, false)
	name_label.reparent(visual_root, false)
	visual_shield = Node2D.new()
	visual_root.add_child(visual_shield)
	shield_polygon.reparent(visual_shield, false)
	shield_boss.reparent(visual_shield, false)
	# Preview-only areas: authoritative arrow masks do not include this layer.
	preview_body = Area2D.new()
	preview_body.collision_layer = PREVIEW_LAYER
	preview_body.collision_mask = 0
	preview_body.monitoring = false
	visual_root.add_child(preview_body)
	var shape := CollisionShape2D.new()
	shape.shape = $CollisionShape2D.shape
	preview_body.add_child(shape)
	preview_shield = Area2D.new()
	preview_shield.collision_layer = PREVIEW_LAYER
	preview_shield.collision_mask = 0
	preview_shield.monitoring = false
	visual_shield.add_child(preview_shield)
	var polygon := CollisionPolygon2D.new()
	polygon.polygon = shield_collision.polygon
	preview_shield.add_child(polygon)
	visual_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF if not is_multiplayer_authority() else Node.PHYSICS_INTERPOLATION_MODE_INHERIT

func receive_snapshot(record: Dictionary, sequence: int) -> void:
	if is_multiplayer_authority() or visual_root == null:
		return
	if _visual_dead and not bool(record.flags & 8):
		return
	if not multiplayer.is_server() and sequence > presentation.last_sequence:
		global_position = record.position
		velocity = record.velocity
		shield_container.rotation = record.aim
	presentation.push(record, sequence)

func present_death(at: Vector2) -> void:
	if is_multiplayer_authority() or visual_root == null:
		return
	_visual_dead = true
	presentation.clear()
	visual_root.global_position = at
	sprite.play("death")
	arrow_container.hide()
	visual_shield.hide()

func _process(_delta: float) -> void:
	if visual_root == null:
		return
	if is_multiplayer_authority():
		visual_shield.visible = is_blocking and not is_dead and not network_away
		visual_shield.rotation = shield_container.rotation
	elif not _visual_dead:
		var state := presentation.sample_at(World.combat_network.render_time)
		if not state.is_empty():
			visual_root.global_position = state.position
			sprite.flip_h = bool(state.flags & 1)
			arrow_container.visible = bool(state.flags & 2)
			arrow_container.rotation = state.aim
			arrow_container.scale = _level_vec(level_arrow_scales, state.level, Vector2.ONE)
			visual_shield.visible = bool(state.flags & 4)
			visual_shield.rotation = state.aim
			if not _shield_event.is_empty() and _shield_event.time >= state.time:
				visual_shield.visible = _shield_event.active
				visual_shield.rotation = _shield_event.aim
			if bool(state.flags & 8):
				present_death(state.position)
			else:
				sprite.play("attack" if bool(state.flags & 2) else ("walk" if absf(state.velocity.x) > 5.0 else "idle"))
	preview_body.collision_layer = PREVIEW_LAYER if not _visual_dead and not network_away else 0
	preview_shield.collision_layer = PREVIEW_LAYER if visual_shield.visible and not network_away else 0

static func preview_exclusions(tree: SceneTree, shooter: ArrowPlayer) -> Array[RID]:
	var excluded := Arrow.ignored_rids(tree, shooter.peer_id, shooter.team)
	for p: ArrowPlayer in tree.get_nodes_in_group("players"):
		excluded.append(p.get_rid())
		excluded.append(p.shield_area.get_rid())
		if p.preview_body and (p == shooter or p.team == shooter.team or p._visual_dead or p.network_away):
			excluded.append(p.preview_body.get_rid())
			excluded.append(p.preview_shield.get_rid())
	return excluded
