class_name ProjectileSpawner
extends MultiplayerSpawner
## Host spawns arrows through spawn(); every peer instantiates them via the
## custom spawn function from the same data, so flight is deterministic.

signal arrow_spawned(arrow: Arrow)
## Local hit feedback fired on the shooting peer; also a test hook.
signal hit_sound_played(headshot: bool)

const ARROW_SCENE := preload("res://player/arrow_player/arrow.tscn")
const STUCK_ARROW_SCENE := preload("res://player/arrow_player/stuck_arrow.tscn")
const GROUND_ARROW_CAP := 64
const SINK := 3.0 ## px the tip is pushed into a body so it reads as embedded

## Real travel time divided by baseline time. Changes timing, never the arc.
## Captured by the host at launch; reflections retain the launch value.
@export_range(0.1, 5.0, 0.05, "or_greater") var arrow_travel_time_multiplier := 1.5

var _serial := 0
var _ground_arrows: Node2D

@onready var hit_sound: AudioStreamPlayer = $HitSound
@onready var headshot_sound: AudioStreamPlayer = $HeadshotSound

func _ready() -> void:
	spawn_function = _spawn_arrow
	get_node("../LevelLoader").level_clearing.connect(_on_level_clearing)

## Ground-stuck arrows and in-flight arrows belong to the old level's terrain.
func _on_level_clearing() -> void:
	if is_instance_valid(_ground_arrows):
		_ground_arrows.queue_free()
	_ground_arrows = null
	if multiplayer.is_server():
		for arrow in get_tree().get_nodes_in_group("projectiles"):
			arrow.queue_free()

# --- Hit feedback (shooter only, host-announced) ----------------------------

## Host only. Tells the shooting peer a damaging arrow landed so it can play
## the click (body) or the ping (headshot). Nobody else hears it.
func server_notify_hit(shooter_id: int, headshot: bool) -> void:
	if not multiplayer.is_server():
		return
	if shooter_id == multiplayer.get_unique_id():
		_play_hit_sound(headshot)
	elif multiplayer.get_peers().has(shooter_id):
		_play_hit_sound.rpc_id(shooter_id, headshot)

@rpc("authority", "call_remote", "reliable")
func _play_hit_sound(headshot: bool) -> void:
	(headshot_sound if headshot else hit_sound).play()
	hit_sound_played.emit(headshot)

## Host only. position/velocity describe the original baseline trajectory.
## Optional trajectory_time/flight_direction resume that curve after a block.
func spawn_arrow(data: Dictionary) -> Arrow:
	if not multiplayer.is_server():
		return null
	_serial += 1
	data.serial = _serial
	data.travel_time_multiplier = Arrow.valid_travel_time_multiplier(
		data.get("travel_time_multiplier", arrow_travel_time_multiplier))
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

## Host only. Reverse the same trajectory without resetting its bounds or speed.
func reflect_arrow(arrow: Arrow, blocker: ArrowPlayer, at: Vector2) -> Arrow:
	return spawn_arrow({
		"position": arrow.origin,
		"velocity": arrow.initial_velocity,
		"trajectory_time": arrow.trajectory_time_at(at),
		"flight_direction": -arrow.flight_direction,
		"travel_time_multiplier": arrow.travel_time_multiplier,
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
## Body arrows persist until the victim dies (players clear on respawn, creeps
## are freed with the corpse); ground arrows are capped and cleared on reset.
func server_report_impact(pos: Vector2, rot: float, team: int, scale: float, victim: Node) -> void:
	if multiplayer.is_server():
		var path := World.get_path_to(victim) if victim != null else NodePath()
		_spawn_stuck_arrow.rpc(pos, rot, team, scale, path)

@rpc("authority", "call_local", "reliable")
func _spawn_stuck_arrow(pos: Vector2, rot: float, team: int, scale: float, victim_path: NodePath) -> void:
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
	stuck.setup(team, scale)

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
