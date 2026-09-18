class_name FortressGate
extends Area2D
## Server-authoritative keep gate. Lives on physics layer 7 (gates) with no
## mask, so bodies walk straight through it; only the arrow ray sweep sees it.

const LAYER := 64
const HITBOX_SIZE := Vector2(48, 96)
## The root sits at the ram impact point, 2 px outside the timber, halfway up.
const HITBOX_INSET := 26.0
const BAR_SIZE := Vector2(48, 3)

@export var team: int = Teams.Team.BLUE

@onready var health: HealthComponent = $HealthComponent
@onready var stuck_arrows: Node2D = $StuckArrows

func side() -> int:
	return -1 if team == Teams.Team.BLUE else 1

func _ready() -> void:
	$CollisionShape2D.position = Vector2(side() * HITBOX_INSET, 0)
	health.changed.connect(_update_health_bar)
	_update_health_bar(health.current, health.max_value)
	if multiplayer.is_server():
		World.level_loader.peer_level_ready.connect(_on_peer_level_ready)
		for id: int in World.level_loader.ready_peers:
			_on_peer_level_ready(id)

func _on_peer_level_ready(id: int) -> void:
	$MultiplayerSynchronizer.set_visibility_for(id, true)

func is_alive() -> bool:
	return health.is_alive()

## World-space rect of the timber facade.
func hitbox() -> Rect2:
	return Rect2(global_position + Vector2(side() * HITBOX_INSET, 0) - HITBOX_SIZE * 0.5, HITBOX_SIZE)

## Nearest point of the timber to `point`; soldiers measure melee reach to it.
func closest_point(point: Vector2) -> Vector2:
	var rect := hitbox()
	return point.clamp(rect.position, rect.end)

## Same contract as ArrowPlayer and Creep so ProjectileSpawner can stick arrows.
func attach_stuck_arrow(node: StuckArrow, impact_pos: Vector2, impact_rot: float) -> void:
	node.attach_to(stuck_arrows, impact_pos, impact_rot)

func _update_health_bar(_current: float, _maximum: float) -> void:
	$HealthBar.visible = health.current < health.max_value
	$HealthBar.position = Vector2(side() * HITBOX_INSET - BAR_SIZE.x * 0.5, -HITBOX_SIZE.y * 0.5 - 8)
	$HealthBar.value = health.ratio()
	$HealthBar.modulate = Teams.color(team)
