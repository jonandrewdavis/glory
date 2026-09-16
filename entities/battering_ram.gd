class_name BatteringRam
extends Node2D
## Collision-free objective. Only the server advances route distance.

@export var speed := 24.0
@export var detection_radius := 160.0
@export var route := PackedVector2Array([Vector2(-2108, -160), Vector2(0, 96), Vector2(2108, -160)])
var distance := -1.0
var direction := 0
var blue_count := 0
var orange_count := 0
var _curve := Curve2D.new()
var _display_position := Vector2.ZERO

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

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		blue_count = 0
		orange_count = 0
		for player in get_tree().get_nodes_in_group("players"):
			if not player is ArrowPlayer or not player.health.is_alive():
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
		distance = clampf(distance + direction * speed * delta, 0, _curve.get_baked_length())
	position = _curve.sample_baked(maxf(distance, 0))
	queue_redraw()

func _process(delta: float) -> void:
	_display_position = _display_position.lerp(position, 1.0 - exp(-18.0 * delta))
	queue_redraw()

func _draw() -> void:
	var offset := _display_position - position
	var tint := Teams.color(Teams.Team.BLUE if direction > 0 else Teams.Team.ORANGE) if direction != 0 else Color.GRAY
	draw_arc(offset + Vector2(0, -24), detection_radius, 0, TAU, 64, Color(tint, 0.18), 1.0)
	for x in [-25, 25]:
		draw_circle(offset + Vector2(x, -9), 9, Color("343b44"))
		draw_line(offset + Vector2(x, -10), offset + Vector2(x, -44), Color("795638"), 5)
	draw_rect(Rect2(offset + Vector2(-45, -36), Vector2(90, 12)), Color("946639"))
	draw_rect(Rect2(offset + Vector2(-50, -52), Vector2(100, 8)), tint)
	draw_rect(Rect2(offset + Vector2(40 if direction >= 0 else -50, -39), Vector2(10, 18)), Color("abb6c0"))
