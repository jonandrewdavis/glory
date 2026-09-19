class_name Arrow
extends Area2D
## Host-spawned projectile. Flies a deterministic ballistic path on every peer
## from the spawn data alone; only the host runs collision and decides hits.

signal hit(victim: Node, shooter_id: int, headshot: bool)
signal blocked(arrow: Arrow, blocker: Node)

const GRAVITY := Vector2(0, 784) # 980 * legacy gravity_scale 0.8
const LIFETIME := 5.0 ## Bounds of the baseline trajectory clock, not real seconds.
const TRAIL_LENGTH := 8
## world | players | shields | creeps | gates
const FLIGHT_COLLISION_MASK := 27 | FortressGate.LAYER

static func flight_position(start: Vector2, launch_velocity: Vector2, time: float) -> Vector2:
	return start + launch_velocity * time + 0.5 * GRAVITY * time * time

static func valid_travel_time_multiplier(value: float) -> float:
	return value if is_finite(value) and value > 0.0 else 1.0

func _init() -> void:
	collision_mask = FLIGHT_COLLISION_MASK

enum HitOutcome { NONE, HIT, KILLED }

var origin := Vector2.ZERO
var initial_velocity := Vector2.ZERO
var owner_id := 0
var team := 0
var damage := 35.0
var visual_scale := Vector2.ONE ## x = length, y = thickness
var velocity := Vector2.ZERO ## Actual world velocity, including slowdown and direction.
var elapsed := 0.0 ## Baseline trajectory time; decreases on the return trip.
var travel_time_multiplier := 1.0
var flight_direction := 1
var reflected := false ## Bounced off a shield at least once; drawn white.
var cosmetic := false
var predicted := false
var projectile_id := 0
var launch_data: Dictionary = {}
var launch_time := 0.0
var initial_time := 0.0
var created_at := 0.0
var correction := Vector2.ZERO
var correction_left := 0.0

var _finished := false
var _prev_position := Vector2.ZERO
var _prev_elapsed := 0.0

@onready var polygon: Polygon2D = %Polygon2D
@onready var trail: Line2D = $Trail

func setup(data: Dictionary) -> void:
	launch_data = data.duplicate()
	projectile_id = data.get("serial", 0)
	launch_time = data.get("launch_time", 0.0)
	initial_time = data.get("trajectory_time", 0.0)
	origin = data.get("position", Vector2.ZERO)
	initial_velocity = data.get("velocity", Vector2.ZERO)
	travel_time_multiplier = valid_travel_time_multiplier(data.get("travel_time_multiplier", 1.0))
	elapsed = clampf(data.get("trajectory_time", 0.0), 0.0, LIFETIME)
	flight_direction = -1 if data.get("flight_direction", 1) == -1 else 1
	_prev_elapsed = elapsed
	owner_id = data.get("owner_id", 0)
	team = data.get("team", 0)
	damage = data.get("damage", 35.0)
	reflected = data.get("reflected", false)
	var raw_scale: Variant = data.get("scale", Vector2.ONE)
	visual_scale = raw_scale if raw_scale is Vector2 else Vector2(float(raw_scale), float(raw_scale))
	_update_flight_state()
	_prev_position = global_position

func _update_flight_state() -> void:
	global_position = flight_position(origin, initial_velocity, elapsed)
	velocity = (initial_velocity + GRAVITY * elapsed) * flight_direction / travel_time_multiplier
	rotation = velocity.angle()

func restore_flight(time: float) -> void:
	elapsed = clampf(time, 0.0, LIFETIME)
	_prev_elapsed = elapsed
	_update_flight_state()
	_prev_position = global_position
	trail.clear_points()

func _ready() -> void:
	if not cosmetic:
		add_to_group("projectiles")
	else:
		collision_layer = 0
		collision_mask = 0
		monitorable = false
		set_physics_process(false)
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(cosmetic)
	visible = cosmetic
	refresh_colors()
	trail.clear_points()
	if visual_scale != Vector2.ONE:
		polygon.scale *= visual_scale
		polygon.position.x *= visual_scale.x
		var shape_node: CollisionShape2D = $CollisionShape2D
		var shape: RectangleShape2D = shape_node.shape.duplicate()
		shape.size *= visual_scale
		shape_node.shape = shape
		trail.width *= visual_scale.y
	reset_physics_interpolation()
	_prev_position = global_position

func _physics_process(delta: float) -> void:
	if _finished:
		return
	_prev_elapsed = elapsed
	elapsed = clampf(elapsed + delta * flight_direction / travel_time_multiplier, 0.0, LIFETIME)
	_prev_position = global_position
	_update_flight_state()
	if multiplayer.is_server():
		_sweep(_prev_position, global_position)
	if (flight_direction > 0 and elapsed >= LIFETIME) or (flight_direction < 0 and elapsed <= 0.0):
		if multiplayer.is_server():
			_finish()
		else:
			hide()
			set_physics_process(false)

## Ray hits lie on this tick's chord. Map the hit back to its trajectory time,
## then evaluate the original curve so repeated reflections cannot shift it.
## Area overlaps pass the current position and therefore use the current time.
func trajectory_time_at(at: Vector2) -> float:
	var segment := global_position - _prev_position
	if segment.is_zero_approx():
		return elapsed
	var fraction := clampf((at - _prev_position).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return lerpf(_prev_elapsed, elapsed, fraction)

func _update_trail() -> void:
	trail.add_point(global_position)
	while trail.get_point_count() > TRAIL_LENGTH:
		trail.remove_point(0)

# --- Host only -------------------------------------------------------------

## Ray-sweeps the segment travelled this tick. A ray (rather than the Area2D
## overlap) is used because it can't tunnel at high speed and because Godot's
## 2D area queries ignore WorldBoundaryShape2D, which the levels use for walls.
func _sweep(from: Vector2, to: Vector2) -> void:
	if _finished or from.is_equal_approx(to):
		return
	var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, _ignored_rids())
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider: Object = result.collider
	if collider is Area2D and collider.is_in_group("shields"):
		server_touched_shield(collider.owner, result.position)
		return
	if collider is Creep or collider is FortressGate or (collider is Node and collider.is_in_group("players")):
		var headshot := is_head_point(collider, result.position)
		var outcome := _hit_body(collider, headshot)
		if outcome != HitOutcome.NONE:
			World.projectile_spawner.server_report_impact(
				result.position, rotation, team, visual_scale.y, collider)
			World.projectile_spawner.server_notify_hit(owner_id, headshot)
		elif collider is FortressGate:
			# Friendly timber: the arrow sticks but deals no damage.
			World.projectile_spawner.server_report_impact(result.position, rotation, team, visual_scale.y, collider)
	else:
		World.projectile_spawner.server_report_impact(result.position, rotation, team, visual_scale.y, null)
	global_position = result.position
	_finish()

## Host only. Called from the ray sweep or from the blocking player's area
## overlap. Enemy shields reflect the arrow back, re-owned by the blocker.
func server_touched_shield(blocker: Node, at: Vector2) -> void:
	if _finished or blocker == null or not Teams.are_enemies(team, blocker.get("team")):
		return
	if blocker is ArrowPlayer and blocker.network_away:
		return
	World.projectile_spawner.reflect_arrow(self, blocker, at)
	blocked.emit(self, blocker)
	_finish()

## Own body, teammates, dead/AFK players, friendly shields and breached gates are
## transparent. A standing gate stops its defenders' arrows too (harmlessly), so
## nobody shoots out through closed timber.
func _ignored_rids() -> Array[RID]:
	return ignored_rids(get_tree(), owner_id, team)

static func ignored_rids(tree: SceneTree, shooter_id: int, shooter_team: int) -> Array[RID]:
	var rids: Array[RID] = []
	for body in tree.get_nodes_in_group("players"):
		if body.get("peer_id") == shooter_id or body.get("team") == shooter_team or body.get("is_dead") or (body is ArrowPlayer and body.network_away):
			rids.append(body.get_rid())
	for body in tree.get_nodes_in_group("creeps"):
		if body is Creep and (body.team == shooter_team or not body.is_alive()):
			rids.append(body.get_rid())
	for area in tree.get_nodes_in_group("shields"):
		var blocker: Node = area.owner
		if blocker == null or blocker.get("peer_id") == shooter_id or blocker.get("team") == shooter_team or (blocker is ArrowPlayer and blocker.network_away):
			rids.append(area.get_rid())
	for gate in tree.get_nodes_in_group("fortress_gates"):
		if gate is FortressGate and not gate.is_alive():
			rids.append(gate.get_rid())
	return rids

## True when a world-space impact point lies inside the victim's editor-authored
## head rect (`head_shape` on players and creeps). The shape's global transform
## absorbs any node scale, so the rect is authored in local pixels.
static func is_head_point(victim: Node, point: Vector2) -> bool:
	var shape_node: CollisionShape2D = victim.get("head_shape")
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return false
	var local: Vector2 = shape_node.global_transform.affine_inverse() * point
	var size: Vector2 = shape_node.shape.size
	return Rect2(-size * 0.5, size).has_point(local)

## Players and creeps alike; the shooter's headshot multiplier scales the damage.
func _hit_body(body: Node, headshot: bool) -> HitOutcome:
	if body is ArrowPlayer and body.network_away:
		return HitOutcome.NONE
	var shooter: ArrowPlayer = World.player_spawner.get_player(owner_id)
	if shooter == null or shooter.team != team or not Teams.are_enemies(team, body.get("team")):
		return HitOutcome.NONE
	var health := HealthComponent.find_in(body)
	# Set before damage: a lethal hit emits died synchronously.
	if body is ArrowPlayer:
		body.last_hit_reflected = reflected
	var amount := damage * (shooter.headshot_damage_multiplier if headshot else 1.0)
	if health and health.take_damage(amount, shooter):
		hit.emit(body, owner_id, headshot)
		return HitOutcome.KILLED if not health.is_alive() else HitOutcome.HIT
	return HitOutcome.NONE

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if not cosmetic and is_inside_tree():
		World.projectile_spawner.finish(self)
	queue_free()

func refresh_colors() -> void:
	polygon.color = Color.WHITE if reflected else Teams.color(team)
	trail.default_color = Teams.color(team)

func evaluate_visual(time: float) -> void:
	elapsed = clampf(initial_time + maxf(0.0, time - launch_time) * flight_direction / travel_time_multiplier, 0.0, LIFETIME)
	_update_flight_state()

func _process(delta: float) -> void:
	if not cosmetic:
		return
	var time: float = World.combat_network.server_time() if predicted else World.combat_network.render_time
	visible = predicted or time >= launch_time or correction_left > 0.0
	evaluate_visual(time)
	if correction_left > 0.0:
		correction_left = maxf(0.0, correction_left - delta)
		global_position += correction * (correction_left / 0.08)
	if visible:
		_update_trail()
