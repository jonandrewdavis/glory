class_name FortressGate
extends Area2D
## Server-authoritative keep gate. Lives on physics layer 7 (gates) with no
## mask, so bodies walk straight through it; only the arrow ray sweep sees it.
## The optional Barrier body is what actually stops players.

const LAYER := 64
## arrow_transparent_platforms: solid to players, ignored by creeps and arrows.
const BARRIER_LAYER := 32
## The root sits at the ram impact point, this far outside the timber, halfway up.
const IMPACT_GAP := 2.0
const BAR_SIZE := Vector2(48, 3)

@export var team: int = Teams.Team.BLUE
## Size of the timber facade: the arrow/creep hitbox and the player barrier.
@export var hitbox_size := Vector2(48, 96)
## Adds a Barrier body so players cannot walk through the timber.
@export var blocks_players := false

@onready var health: HealthComponent = $HealthComponent
@onready var stuck_arrows: Node2D = $StuckArrows

func side() -> int:
	return -1 if team == Teams.Team.BLUE else 1

func _ready() -> void:
	var timber := RectangleShape2D.new()
	timber.size = hitbox_size
	$CollisionShape2D.shape = timber
	$CollisionShape2D.position = Vector2(side() * hitbox_inset(), 0)
	if blocks_players:
		_add_barrier(timber)
	if multiplayer.is_server():
		World.level_loader.peer_level_ready.connect(_on_peer_level_ready)
		for id: int in World.level_loader.ready_peers:
			_on_peer_level_ready(id)

## Areas never stop bodies, so a static twin of the timber does.
func _add_barrier(timber: RectangleShape2D) -> void:
	var barrier := StaticBody2D.new()
	barrier.name = "Barrier"
	barrier.collision_layer = BARRIER_LAYER
	barrier.collision_mask = 0
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = timber
	collider.position = $CollisionShape2D.position
	barrier.add_child(collider)
	add_child(barrier)

func _on_peer_level_ready(id: int) -> void:
	$MultiplayerSynchronizer.set_visibility_for(id, true)

## Distance from the root to the centre of the timber.
func hitbox_inset() -> float:
	return IMPACT_GAP + hitbox_size.x * 0.5

func is_alive() -> bool:
	return health.is_alive()

## World-space rect of the timber facade.
func hitbox() -> Rect2:
	return Rect2(global_position + Vector2(side() * hitbox_inset(), 0) - hitbox_size * 0.5, hitbox_size)

## Nearest point of the timber to `point`; soldiers measure melee reach to it.
func closest_point(point: Vector2) -> Vector2:
	var rect := hitbox()
	return point.clamp(rect.position, rect.end)

## Same contract as ArrowPlayer and Creep so ProjectileSpawner can stick arrows.
func attach_stuck_arrow(node: StuckArrow, impact_pos: Vector2, impact_rot: float) -> void:
	node.attach_to(stuck_arrows, impact_pos, impact_rot)
