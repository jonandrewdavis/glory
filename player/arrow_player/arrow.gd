class_name Arrow
extends Area2D
## Host-spawned projectile. Flies a deterministic ballistic path on every peer
## from the spawn data alone; only the host runs collision and decides hits.

signal hit(victim: Node, shooter_id: int)
signal blocked(arrow: Arrow, blocker: Node)

const GRAVITY := Vector2(0, 784) # 980 * legacy gravity_scale 0.8
const LIFETIME := 5.0
const TRAIL_LENGTH := 8
const FLIGHT_COLLISION_MASK := 27

static func flight_position(start: Vector2, launch_velocity: Vector2, time: float) -> Vector2:
	return start + launch_velocity * time + 0.5 * GRAVITY * time * time

func _init() -> void:
	collision_mask = FLIGHT_COLLISION_MASK

enum HitOutcome { NONE, HIT, KILLED }

var origin := Vector2.ZERO
var initial_velocity := Vector2.ZERO
var owner_id := 0
var team := 0
var damage := 35.0
var visual_scale := Vector2.ONE ## x = length, y = thickness
var velocity := Vector2.ZERO
var elapsed := 0.0

var _finished := false
var _prev_position := Vector2.ZERO

@onready var polygon: Polygon2D = %Polygon2D
@onready var trail: Line2D = $Trail

func setup(data: Dictionary) -> void:
	origin = data.get("position", Vector2.ZERO)
	initial_velocity = data.get("velocity", Vector2.ZERO)
	owner_id = data.get("owner_id", 0)
	team = data.get("team", 0)
	damage = data.get("damage", 35.0)
	var raw_scale: Variant = data.get("scale", Vector2.ONE)
	visual_scale = raw_scale if raw_scale is Vector2 else Vector2(float(raw_scale), float(raw_scale))
	velocity = initial_velocity
	global_position = origin
	rotation = velocity.angle()

func _ready() -> void:
	add_to_group("projectiles")
	polygon.color = Teams.color(team)
	trail.default_color = Teams.color(team)
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
	elapsed += delta
	_prev_position = global_position
	global_position = flight_position(origin, initial_velocity, elapsed)
	velocity = initial_velocity + GRAVITY * elapsed
	rotation = velocity.angle()
	_update_trail()
	if multiplayer.is_server():
		_sweep(_prev_position, global_position)
	if elapsed >= LIFETIME:
		if multiplayer.is_server():
			_finish()
		else:
			hide()

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
	if collider is Creep or (collider is Node and collider.is_in_group("players")):
		var outcome := _hit_creep(collider) if collider is Creep else _hit_player(collider)
		if outcome != HitOutcome.NONE:
			World.projectile_spawner.server_report_impact(
				result.position, rotation, team, visual_scale.y, collider, outcome == HitOutcome.KILLED)
	else:
		World.projectile_spawner.server_report_impact(result.position, rotation, team, visual_scale.y, null, false)
	_finish()

## Host only. Called from the ray sweep or from the blocking player's area
## overlap. Enemy shields reflect the arrow back, re-owned by the blocker.
func server_touched_shield(blocker: Node, at: Vector2) -> void:
	if _finished or blocker == null or not Teams.are_enemies(team, blocker.get("team")):
		return
	World.projectile_spawner.reflect_arrow(self, blocker, at)
	blocked.emit(self, blocker)
	_finish()

## Own body, teammates, dead players and friendly shields are transparent.
func _ignored_rids() -> Array[RID]:
	return ignored_rids(get_tree(), owner_id, team)

static func ignored_rids(tree: SceneTree, shooter_id: int, shooter_team: int) -> Array[RID]:
	var rids: Array[RID] = []
	for body in tree.get_nodes_in_group("players"):
		if body.get("peer_id") == shooter_id or body.get("team") == shooter_team or body.get("is_dead"):
			rids.append(body.get_rid())
	for body in tree.get_nodes_in_group("creeps"):
		if body is Creep and (body.team == shooter_team or not body.is_alive()):
			rids.append(body.get_rid())
	for area in tree.get_nodes_in_group("shields"):
		var blocker: Node = area.owner
		if blocker == null or blocker.get("peer_id") == shooter_id or blocker.get("team") == shooter_team:
			rids.append(area.get_rid())
	return rids

func _hit_creep(body: Creep) -> HitOutcome:
	var shooter: ArrowPlayer = World.player_spawner.get_player(owner_id)
	if shooter == null or shooter.team != team or not Teams.are_enemies(team, body.team):
		return HitOutcome.NONE
	if body.health.take_damage(damage, shooter):
		hit.emit(body, owner_id)
		return HitOutcome.KILLED if not body.is_alive() else HitOutcome.HIT
	return HitOutcome.NONE

func _hit_player(body: Node) -> HitOutcome:
	var shooter: ArrowPlayer = World.player_spawner.get_player(owner_id)
	if shooter == null or shooter.team != team or not Teams.are_enemies(team, body.team):
		return HitOutcome.NONE
	var health := HealthComponent.find_in(body)
	if health and health.take_damage(damage, shooter):
		hit.emit(body, owner_id)
		return HitOutcome.KILLED if not health.is_alive() else HitOutcome.HIT
	return HitOutcome.NONE

func _finish() -> void:
	if _finished:
		return
	_finished = true
	queue_free()
