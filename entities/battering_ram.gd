class_name BatteringRam
extends Node2D
## Collision-free objective. Only the server advances route distance and runs
## the siege attack: after WINDUP_TIME seconds of contact with a gate the ram
## locks in place for a strike that lands STRIKE_DAMAGE. Leaving the gate
## resets the wind-up; every strike needs a fresh wind-up.

enum AttackState { IDLE, WINDUP, STRIKE }
signal route_advanced(previous: float, current: float, pushing_direction: int)

const BAR_SIZE := Vector2(60, 4)
const BAR_OFFSET := Vector2(-30, -74)

@export var speed := 14.0
@export var detection_radius := 160.0
@export var windup_time := 8.0
@export var strike_time := 4.0
@export var strike_damage := 500.0
@export var route := PackedVector2Array([Vector2(-2108, -160), Vector2(0, 96), Vector2(2108, -160)])
var distance := -1.0
var direction := 0
var blue_count := 0
var orange_count := 0
var attack_state: AttackState = AttackState.IDLE
## 0..1 through the current wind-up or strike.
var attack_progress := 0.0
var _attack_elapsed := 0.0
var _target_gate: FortressGate
var _curve := Curve2D.new()
var _display_position := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	for point in route:
		_curve.add_point(point)
	if distance < 0:
		distance = _curve.get_baked_length() * 0.5
	position = _curve.sample_baked(distance)
	_display_position = position
	if multiplayer.is_server():
		World.level_loader.peer_level_ready.connect(_on_peer_level_ready)
		for id: int in World.level_loader.ready_peers:
			_on_peer_level_ready(id)

func _on_peer_level_ready(id: int) -> void:
	$MultiplayerSynchronizer.set_visibility_for(id, true)

static func majority(blue: int, orange: int) -> int:
	return signi(blue - orange)

func route_length() -> float:
	return _curve.get_baked_length()

func route_distance_at(world_point: Vector2) -> float:
	# Route coordinates are relative to the ram's parent, not its moving origin.
	return _curve.get_closest_offset(get_parent().to_local(world_point))

func route_position_at(route_distance: float) -> Vector2:
	return get_parent().to_global(_curve.sample_baked(route_distance))

## 0 at the blue gate, 1 at the orange gate.
func progress() -> float:
	var length := route_length()
	return clampf(distance / length, 0.0, 1.0) if length > 0.0 else 0.5

## Living gate whose nose the ram is touching, or null. Contact means the
## route clamp bound; the route ends at each gate.
func gate_in_contact() -> FortressGate:
	var team := -1
	if distance <= 0.0:
		team = Teams.Team.BLUE
	elif distance >= route_length():
		team = Teams.Team.ORANGE
	if team < 0:
		return null
	for gate in get_tree().get_nodes_in_group("fortress_gates"):
		if gate is FortressGate and gate.team == team and gate.is_alive():
			return gate
	return null

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		var previous_distance := distance
		blue_count = 0
		orange_count = 0
		for player in get_tree().get_nodes_in_group("players"):
			if not player is ArrowPlayer or not player.health.is_alive() or player.is_spawn_protected():
				continue
			if global_position.distance_squared_to(player.global_position) > detection_radius * detection_radius:
				continue
			if player.team == Teams.Team.BLUE:
				blue_count += 1
			elif player.team == Teams.Team.ORANGE:
				orange_count += 1
		for creep in get_tree().get_nodes_in_group("creeps"):
			if not creep is Creep or not creep.is_alive():
				continue
			if global_position.distance_squared_to(creep.global_position) > detection_radius * detection_radius:
				continue
			if creep.team == Teams.Team.BLUE:
				blue_count += 1
			elif creep.team == Teams.Team.ORANGE:
				orange_count += 1
		direction = majority(blue_count, orange_count)
		# A strike locks the ram against the gate until the blow lands.
		if attack_state != AttackState.STRIKE:
			distance = clampf(distance + direction * speed * delta, 0, route_length())
		route_advanced.emit(previous_distance, distance, direction)
		_advance_attack(delta)
	position = _curve.sample_baked(maxf(distance, 0))
	queue_redraw()

func _advance_attack(delta: float) -> void:
	if attack_state == AttackState.STRIKE:
		_attack_elapsed += delta
		attack_progress = clampf(_attack_elapsed / strike_time, 0.0, 1.0)
		if _attack_elapsed >= strike_time:
			if is_instance_valid(_target_gate) and _target_gate.is_alive():
				_target_gate.health.take_damage(strike_damage, self)
			# Next tick re-enters WINDUP from zero if the ram is still touching.
			_set_attack(AttackState.IDLE)
		return
	var gate := gate_in_contact()
	if gate == null:
		if attack_state != AttackState.IDLE:
			_set_attack(AttackState.IDLE)
		return
	if attack_state == AttackState.IDLE:
		_set_attack(AttackState.WINDUP)
	_target_gate = gate
	_attack_elapsed += delta
	attack_progress = clampf(_attack_elapsed / windup_time, 0.0, 1.0)
	if _attack_elapsed >= windup_time:
		_set_attack(AttackState.STRIKE)

func _set_attack(state: AttackState) -> void:
	attack_state = state
	_attack_elapsed = 0.0
	attack_progress = 0.0

func _process(delta: float) -> void:
	_display_position = _display_position.lerp(position, 1.0 - exp(-18.0 * delta))
	var lunge := 0.0
	if attack_state == AttackState.STRIKE:
		lunge = sin(attack_progress * PI) * 10.0 * (-1.0 if distance <= route_length() * 0.5 else 1.0)
	sprite.position.x = lunge
	queue_redraw()

func _draw() -> void:
	var offset := _display_position - position
	var tint := Teams.color(Teams.Team.BLUE if direction > 0 else Teams.Team.ORANGE) if direction != 0 else Color.GRAY
	draw_arc(offset + Vector2(0, -24), detection_radius, 0, TAU, 64, Color(tint, 0.18), 1.0)
	if attack_state == AttackState.IDLE:
		return
	var origin := offset + BAR_OFFSET
	var fill := Color(1.0, 0.45, 0.2) if attack_state == AttackState.STRIKE else Color.WHITE
	draw_rect(Rect2(origin - Vector2.ONE, BAR_SIZE + Vector2.ONE * 2), Color(0.03, 0.05, 0.09, 0.9))
	draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * attack_progress, BAR_SIZE.y)), fill)
