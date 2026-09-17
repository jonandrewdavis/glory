class_name Creep
extends CharacterBody2D
## Server-simulated lane soldier. Replicas only display snapshots.

enum State { MARCH, ATTACK, HOLD, DEAD }

const LAYER := 16
const BODY_SIZE := Vector2(12, 16)
const ATTACK_FPS := 10.0
const STRIKE_TIME := 3.0 / ATTACK_FPS
const ATTACK_DURATION := 6.0 / ATTACK_FPS
const DEATH_DURATION := 3.0 ## corpse linger so stuck arrows stay visible
const SHEETS := {
	&"idle": preload("res://assets/sprites/Soldier/Soldier_Idle.png"),
	&"walk": preload("res://assets/sprites/Soldier/Soldier_Walk.png"),
	&"attack": preload("res://assets/sprites/Soldier/Soldier_Attack01.png"),
	&"death": preload("res://assets/sprites/Soldier/Soldier_Death.png"),
}
static var _frames: SpriteFrames

@export var walk_speed := 60.0
@export var melee_reach := 48.0
@export var swing_interval_min := 0.8
@export var swing_interval_max := 1.4
@export var damage_low := 20.0
@export var damage_high := 25.0
@export var jump_velocity := -290.0

var serial := 0
var team := Teams.Team.BLUE
var goal_x := 0.0
var march_direction := 1
var facing := 1
var state: State = State.MARCH
var visual_animation: StringName = &"idle"
var visual_frame := 0
var hit_serial := 0

## Enemy Creep, or the enemy FortressGate when no soldier is in reach.
var _target: Node
var _rng := RandomNumberGenerator.new()
var _cooldown := 0.0
var _swing_elapsed := -1.0
var _struck := false
var _animation_time := 0.0
var _death_time := 0.0
var _display_position := Vector2.ZERO
var _last_hit_serial := 0
var _flash_left := 0.0

@onready var health: HealthComponent = $HealthComponent
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
## Editor-visible headshot band; no physics layers, tested by Arrow.is_head_point().
@onready var head_shape: CollisionShape2D = $HeadHitbox/HeadShape
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
## Under the sprite, not the body, so arrows follow the locally smoothed position.
@onready var stuck_arrows: Node2D = $AnimatedSprite2D/StuckArrows

func setup(data: Dictionary) -> void:
	serial = data.serial
	team = data.team
	position = data.position
	goal_x = data.goal_x
	march_direction = 1 if team == Teams.Team.BLUE else -1
	facing = march_direction

func _ready() -> void:
	sprite.sprite_frames = animation_frames()
	_display_position = global_position
	_rng.randomize()
	_cooldown = next_swing_interval()
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	if not multiplayer.is_server():
		collision_layer = 0
		collision_mask = 0
	reset_physics_interpolation()

static func animation_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	_frames = SpriteFrames.new()
	_frames.remove_animation(&"default")
	for animation: StringName in SHEETS:
		var sheet: Texture2D = SHEETS[animation]
		_frames.add_animation(animation)
		_frames.set_animation_speed(animation, ATTACK_FPS)
		_frames.set_animation_loop(animation, animation in [&"idle", &"walk"])
		for frame in range(sheet.get_width() / 100):
			var texture := AtlasTexture.new()
			texture.atlas = sheet
			texture.region = Rect2(frame * 100, 0, 100, 100)
			_frames.add_frame(animation, texture)
	return _frames

## Parents a landed-arrow visual to this soldier; freed with the body.
func attach_stuck_arrow(node: StuckArrow, impact_pos: Vector2, impact_rot: float) -> void:
	node.attach_to(stuck_arrows, impact_pos, impact_rot)

func is_alive() -> bool:
	return state != State.DEAD and health.is_alive()

func next_swing_interval() -> float:
	return _rng.randf_range(maxf(swing_interval_min, ATTACK_DURATION), maxf(swing_interval_max, swing_interval_min))

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if state == State.DEAD:
		_death_time += delta
		_set_animation(&"death", delta)
		if _death_time >= DEATH_DURATION:
			queue_free()
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	# A soldier hitting the gate keeps looking for enemy soldiers.
	if not _can_hit(_target) or _target is FortressGate:
		_target = _find_target()
	if _target != null:
		# Striking the gate is part of holding at the marker.
		state = State.HOLD if _target is FortressGate else State.ATTACK
		facing = 1 if _target.global_position.x >= global_position.x else -1
		if _swing_elapsed < 0.0 and _cooldown <= 0.0:
			_swing_elapsed = 0.0
			_struck = false
			_animation_time = 0.0
			_cooldown = next_swing_interval()
	else:
		state = State.HOLD if _at_goal() else State.MARCH
		facing = march_direction
	if _swing_elapsed >= 0.0:
		_swing_elapsed += delta
		if not _struck and _swing_elapsed >= STRIKE_TIME:
			_struck = true
			if _can_hit(_target):
				_target.health.take_damage(damage_low if _rng.randi_range(0, 1) == 0 else damage_high, self)
		if _swing_elapsed >= ATTACK_DURATION:
			_swing_elapsed = -1.0
	_move(delta)
	_set_animation(&"attack" if _swing_elapsed >= 0.0 else (&"walk" if absf(velocity.x) > 1.0 else &"idle"), delta)

func _move(delta: float) -> void:
	velocity.y += 980.0 * delta
	velocity.x = 0.0
	if state == State.MARCH and _swing_elapsed < 0.0 and not _creep_ahead():
		velocity.x = march_direction * minf(walk_speed, absf(goal_x - position.x) / delta)
		# Only terrain can trigger a hop. A separate creep check keeps queues flat.
		if is_on_floor() and _world_obstacle_ahead():
			velocity.y = jump_velocity
	move_and_slide()

func _creep_ahead() -> bool:
	# Horizontal reservations also prevent airborne soldiers landing on another
	# soldier or overtaking a queue while traversing a step.
	for other: Node in get_tree().get_nodes_in_group("creeps"):
		if other == self or not other is Creep or not other.is_alive():
			continue
		if absf(other.global_position.y - global_position.y) > melee_reach:
			continue
		var ahead: float = (other.global_position.x - global_position.x) * march_direction
		if ahead > 0.0 and ahead < BODY_SIZE.x + 3.0:
			return true
	return false

func _world_obstacle_ahead() -> bool:
	var from := global_position + Vector2(0, 2)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(march_direction * 10, 0), 1)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _can_hit(other: Node) -> bool:
	if not is_instance_valid(other) or not (other is Creep or other is FortressGate):
		return false
	if not other.is_alive() or not Teams.are_enemies(team, other.team):
		return false
	var point: Vector2 = other.closest_point(global_position) if other is FortressGate else other.global_position
	var offset := point - global_position
	# Forgiving radial melee deliberately reaches across ramp edges and cover.
	return offset.length_squared() <= melee_reach * melee_reach

func _at_goal() -> bool:
	return (goal_x - position.x) * march_direction <= 1.0

## Nearest enemy soldier; otherwise, once holding at the marker, the enemy gate
## when it is within reach.
func _find_target() -> Node:
	var nearest: Creep
	var best := INF
	for other: Node in get_tree().get_nodes_in_group("creeps"):
		if not other is Creep or not _can_hit(other):
			continue
		var distance := global_position.distance_squared_to(other.global_position)
		if distance < best or (is_equal_approx(distance, best) and (nearest == null or other.serial < nearest.serial)):
			nearest = other
			best = distance
	if nearest != null or not _at_goal():
		return nearest
	for gate: Node in get_tree().get_nodes_in_group("fortress_gates"):
		if gate is FortressGate and _can_hit(gate):
			return gate
	return null

func _set_animation(animation: StringName, delta: float) -> void:
	if visual_animation != animation:
		visual_animation = animation
		_animation_time = 0.0
	else:
		_animation_time += delta
	if animation == &"attack":
		_animation_time = maxf(_swing_elapsed, 0.0)
	var count := sprite.sprite_frames.get_frame_count(animation)
	var frame := int(_animation_time * ATTACK_FPS)
	visual_frame = mini(frame, count - 1) if animation in [&"attack", &"death"] else frame % count

func _on_damaged(_amount: float, _source: Node) -> void:
	if multiplayer.is_server():
		hit_serial += 1

func _on_died(source: Node) -> void:
	if not multiplayer.is_server() or state == State.DEAD:
		return
	state = State.DEAD
	if source is ArrowPlayer:
		# Zero denotes a non-player victim, so only the killer's score changes.
		World.scoreboard.record_kill(source.peer_id, 0)
	_target = null
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	$CollisionShape2D.set_deferred("disabled", true)
	_set_animation(&"death", 0.0)

func _process(delta: float) -> void:
	_display_position = _display_position.lerp(global_position, 1.0 - exp(-20.0 * delta))
	sprite.position = _display_position - global_position
	sprite.flip_h = facing < 0
	sprite.animation = visual_animation
	sprite.frame = visual_frame
	if hit_serial != _last_hit_serial:
		_last_hit_serial = hit_serial
		_flash_left = 0.15
	_flash_left = maxf(0.0, _flash_left - delta)
	sprite.self_modulate = Color(1.6, 0.5, 0.5) if _flash_left > 0.0 else Teams.color(team)
	queue_redraw()

func _draw() -> void:
	if not is_node_ready() or state == State.DEAD:
		return
	var offset := _display_position - global_position
	draw_line(offset + Vector2(-5, 9), offset + Vector2(5, 9), Teams.color(team), 2.0)
	if health.current < health.max_value:
		draw_rect(Rect2(offset + Vector2(-7, -13), Vector2(14, 2)), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(offset + Vector2(-7, -13), Vector2(14 * health.ratio(), 2)), Teams.color(team))
