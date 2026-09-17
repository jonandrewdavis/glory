class_name StuckArrow
extends Node2D
## Purely local, non-networked visual of an arrow that has landed. Position,
## rotation and parent are decided by whoever spawns it (ProjectileSpawner).

## Arrows read clearly on impact, then settle to a faint ghost so a busy
## battlefield doesn't clutter.
const SETTLE_DELAY := 0.25
const SETTLE_DURATION := 0.35
const SETTLED_ALPHA := 0.55

var _fading := false
var _settle: Tween

@onready var polygon: Polygon2D = %Polygon2D

## Call after the node is in the tree. scale matches Arrow.visual_scale;
## lifetime <= 0 means "until cleared".
func setup(team: int, scale := 1.0, lifetime := 0.0) -> void:
	polygon.color = Teams.color(team)
	if scale != 1.0:
		polygon.scale *= scale
		polygon.position *= scale
	_settle = create_tween()
	_settle.tween_interval(SETTLE_DELAY)
	_settle.tween_property(self, "modulate:a", SETTLED_ALPHA, SETTLE_DURATION)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_timeout)

## Parents this arrow under `container` at the impact point, tip sunk slightly
## into the body along the flight direction.
func attach_to(container: Node2D, impact_pos: Vector2, impact_rot: float) -> void:
	container.add_child(self)
	global_position = impact_pos + Vector2.RIGHT.rotated(impact_rot) * ProjectileSpawner.SINK
	global_rotation = impact_rot
	reset_physics_interpolation()

func is_fading() -> bool:
	return _fading

func fade_out(duration := 0.4) -> void:
	if _fading:
		return
	_fading = true
	if _settle != null and _settle.is_valid():
		_settle.kill()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_callback(queue_free)

func _on_lifetime_timeout() -> void:
	if is_inside_tree():
		fade_out()
