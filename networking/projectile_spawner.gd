class_name ProjectileSpawner
extends MultiplayerSpawner
## Host spawns arrows through spawn(); every peer instantiates them via the
## custom spawn function from the same data, so flight is deterministic.

signal arrow_spawned(arrow: Arrow)

const ARROW_SCENE := preload("res://player/arrow_player/arrow.tscn")
const STUCK_ARROW_SCENE := preload("res://player/arrow_player/stuck_arrow.tscn")
const GROUND_ARROW_CAP := 64
const PLAYER_ARROW_LIFETIME := 8.0
const SINK := 3.0 ## px the tip is pushed into a body so it reads as embedded

var _serial := 0
var _ground_arrows: Node2D

func _ready() -> void:
	spawn_function = _spawn_arrow

## Host only. data: {position, velocity, owner_id, team, damage}
func spawn_arrow(data: Dictionary) -> Arrow:
	if not multiplayer.is_server():
		return null
	_serial += 1
	data.serial = _serial
	return spawn(data) as Arrow

func _spawn_arrow(data: Variant) -> Node:
	var arrow: Arrow = ARROW_SCENE.instantiate()
	arrow.name = "Arrow%d" % data.get("serial", 0)
	arrow.setup(data)
	if multiplayer.is_server():
		arrow.blocked.connect(_on_arrow_blocked)
	arrow_spawned.emit(arrow)
	return arrow

func clear_projectiles() -> void:
	var container := get_node_or_null(spawn_path)
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	_ground_arrows = null

func remove_owned_projectiles(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for arrow in get_tree().get_nodes_in_group("projectiles"):
		if arrow.owner_id == peer_id:
			arrow.queue_free()

## Host only. Re-spawns an arrow flying back, owned by the blocker.
func reflect_arrow(arrow: Arrow, blocker: ArrowPlayer, at: Vector2) -> Arrow:
	return spawn_arrow({
		"position": at,
		"velocity": -arrow.velocity * blocker.shield_reflect_speed_mult,
		"owner_id": blocker.peer_id,
		"team": blocker.team,
		"damage": arrow.damage,
		"scale": arrow.visual_scale,
	})

func _on_arrow_blocked(_arrow: Arrow, _blocker: Node) -> void:
	pass

# --- Stuck arrows (local visuals, host-announced) ---------------------------

## Host only. victim null means the arrow hit the world; otherwise it is any
## node with attach_stuck_arrow() (players, creeps) that MultiplayerSpawner
## names identically on every peer, so its World-relative path resolves everywhere.
func server_report_impact(pos: Vector2, rot: float, team: int, scale: float, victim: Node, lethal: bool) -> void:
	if multiplayer.is_server():
		var path := World.get_path_to(victim) if victim != null else NodePath()
		_spawn_stuck_arrow.rpc(pos, rot, team, scale, path, lethal)

@rpc("authority", "call_local", "reliable")
func _spawn_stuck_arrow(pos: Vector2, rot: float, team: int, scale: float, victim_path: NodePath, lethal: bool) -> void:
	var stuck: StuckArrow = STUCK_ARROW_SCENE.instantiate()
	if victim_path.is_empty():
		var container := _ensure_ground_container()
		if container == null:
			stuck.free()
			return
		container.add_child(stuck)
		stuck.global_position = pos
		stuck.global_rotation = rot
		stuck.reset_physics_interpolation()
		stuck.setup(team, scale)
		_enforce_ground_cap(container)
		return
	var victim := World.get_node_or_null(victim_path)
	if victim == null or not victim.is_inside_tree() or not victim.has_method("attach_stuck_arrow"):
		stuck.free()
		return
	victim.attach_stuck_arrow(stuck, pos, rot)
	stuck.setup(team, scale, 0.0 if lethal else PLAYER_ARROW_LIFETIME)

func _ensure_ground_container() -> Node2D:
	if is_instance_valid(_ground_arrows):
		return _ground_arrows
	var parent := get_node_or_null(spawn_path)
	if parent == null:
		return null
	_ground_arrows = Node2D.new()
	_ground_arrows.name = "StuckArrows"
	_ground_arrows.z_index = -1
	parent.add_child(_ground_arrows)
	return _ground_arrows

func _enforce_ground_cap(container: Node2D) -> void:
	var live: Array[StuckArrow] = []
	for child in container.get_children():
		if child is StuckArrow and not child.is_fading():
			live.append(child)
	var excess := live.size() - GROUND_ARROW_CAP
	for i in range(maxi(excess, 0)):
		live[i].fade_out()
