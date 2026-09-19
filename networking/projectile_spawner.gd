class_name ProjectileSpawner
extends Node
## Server simulation and client presentation have independent lifetimes.
signal arrow_spawned(arrow: Arrow)
signal visual_spawned(arrow: Arrow)
signal hit_sound_played(headshot: bool)
const ARROW_SCENE := preload("res://player/arrow_player/arrow.tscn")
const STUCK_ARROW_SCENE := preload("res://player/arrow_player/stuck_arrow.tscn")
const GROUND_ARROW_CAP := 64
const SINK := 3.0
@export_range(0.1, 5.0, 0.05, "or_greater") var arrow_travel_time_multiplier := 1.5
var _serial := 0
var _ground_arrows: Node2D
var _simulation: Dictionary = {}
var _visuals: Dictionary = {}
var _ghosts: Dictionary = {}
var _terminated: Dictionary = {}
var _reflections: Dictionary = {}
@onready var hit_sound: AudioStreamPlayer = $HitSound
@onready var headshot_sound: AudioStreamPlayer = $HeadshotSound

func _ready() -> void:
	get_node("../LevelLoader").level_clearing.connect(clear_projectiles)

func _key(peer: int, serial: int, shot: int) -> String:
	return "%d:%d:%d" % [peer, serial, shot]

func _instantiate(data: Dictionary, visual: bool) -> Arrow:
	var arrow: Arrow = ARROW_SCENE.instantiate()
	arrow.cosmetic = visual
	arrow.name = ("Visual" if visual else "Arrow") + str(data.get("serial", 0))
	arrow.setup(data)
	get_node("../Projectiles").add_child(arrow, true)
	if visual:
		visual_spawned.emit(arrow)
	else:
		arrow_spawned.emit(arrow)
	return arrow

func spawn_arrow(data: Dictionary) -> Arrow:
	if not multiplayer.is_server():
		return null
	_serial += 1
	data = data.duplicate()
	data.serial = _serial
	data.launch_time = World.combat_network.server_time()
	data.travel_time_multiplier = Arrow.valid_travel_time_multiplier(data.get("travel_time_multiplier", arrow_travel_time_multiplier))
	var arrow := _instantiate(data, false)
	_simulation[_serial] = arrow
	World.combat_network.queue_event({"kind": "launch", "data": data})
	return arrow

func predict(player: ArrowPlayer, shot: int, aim: Vector2, level: int) -> Arrow:
	var data := {"position": player.global_position, "velocity": aim * player.compute_arrow_speed(level),
		"owner_id": player.peer_id, "shooter_serial": player.spawn_serial, "shot": shot,
		"team": player.team, "damage": 0.0, "scale": player._level_vec(player.level_arrow_scales, level, Vector2.ONE),
		"travel_time_multiplier": arrow_travel_time_multiplier, "launch_time": World.combat_network.server_time()}
	var key := _key(player.peer_id, player.spawn_serial, shot)
	if _ghosts.has(key):
		return _ghosts[key]
	var arrow := _instantiate(data, true)
	arrow.predicted = true
	arrow.created_at = CombatNetwork.now()
	_ghosts[key] = arrow
	return arrow

func _process(_delta: float) -> void:
	for key: String in _ghosts.keys():
		var arrow: Arrow = _ghosts[key]
		if not is_instance_valid(arrow):
			_ghosts.erase(key)
		elif CombatNetwork.now() - arrow.created_at >= 1.0:
			_ghosts.erase(key)
			_fade_ghost(arrow)
			World.combat_network.request_baseline()
	for id: int in _terminated.keys():
		if CombatNetwork.now() - float(_terminated[id]) > 10.0:
			_terminated.erase(id)

func _fade_ghost(arrow: Arrow) -> void:
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "modulate:a", 0.0, 0.05)
	tween.tween_callback(arrow.queue_free)

## Handoff is immediate. Terminal effects wait for presentation time.
func receive_event(event: Dictionary) -> void:
	if event.kind == "launch":
		if event.data.has("reflected_from"):
			_reflections[int(event.data.reflected_from)] = event.data
		else:
			_confirm(event.data)
	elif event.kind == "result" and event.peer == multiplayer.get_unique_id():
		if event.result == "rejected":
			var key := _key(event.peer, event.serial, event.shot)
			if _ghosts.has(key):
				_fade_ghost(_ghosts[key])
				_ghosts.erase(key)
			if int(event.action) == CombatNetwork.SHIELD:
				var p: ArrowPlayer = World.player_spawner.get_player(event.peer)
				if p and p.spawn_serial == event.serial:
					p._end_block()

func _confirm(data: Dictionary) -> void:
	var id: int = data.serial
	if _visuals.has(id) or _terminated.has(id):
		return
	var key := _key(data.owner_id, data.get("shooter_serial", 0), data.get("shot", 0))
	var arrow: Arrow = _ghosts.get(key)
	if is_instance_valid(arrow):
		_ghosts.erase(key)
		var previous := arrow.global_position
		arrow.setup(data)
		arrow.predicted = false
		arrow.evaluate_visual(World.combat_network.render_time)
		arrow.correction = previous - arrow.global_position
		arrow.correction_left = 0.08
		if arrow.correction.length() > 96.0:
			arrow.correction = Vector2.ZERO
			arrow.trail.clear_points()
		arrow.global_position += arrow.correction
	else:
		arrow = _instantiate(data, true)
	_visuals[id] = arrow
	if not multiplayer.is_server():
		arrow_spawned.emit(arrow)

func present_event(event: Dictionary) -> void:
	match event.kind:
		"launch":
			if event.data.has("reflected_from"):
				var old: int = event.data.reflected_from
				var arrow: Arrow = _visuals.get(old)
				if is_instance_valid(arrow):
					_visuals.erase(old)
					arrow.setup(event.data)
					arrow.refresh_colors()
					arrow.trail.clear_points()
					_visuals[int(event.data.serial)] = arrow
					if not multiplayer.is_server():
						arrow_spawned.emit(arrow)
				else:
					_confirm(event.data)
				_reflections.erase(old)
		"terminal":
			var id: int = event.projectile
			var arrow: Arrow = _visuals.get(id)
			if is_instance_valid(arrow):
				arrow.global_position = event.position
				if not _reflections.has(id):
					arrow.queue_free()
			if not _reflections.has(id):
				_visuals.erase(id)
			_terminated[id] = CombatNetwork.now()
		"impact":
			var pos: Vector2 = event.position
			var victim := World.get_node_or_null(NodePath(event.victim)) if not str(event.victim).is_empty() else null
			if victim is ArrowPlayer and victim.visual_root:
				pos = victim.visual_root.to_global(event.local_position)
			elif victim is Node2D:
				pos = victim.to_global(event.local_position)
			_spawn_stuck_arrow(pos, event.rotation, event.team, event.scale, NodePath(event.victim))
		"hit":
			if event.peer == multiplayer.get_unique_id():
				_play_hit_sound(event.headshot)
		"death":
			var p: ArrowPlayer = World.player_spawner.get_player(event.peer)
			if p and p.spawn_serial == event.serial:
				p.present_death(event.position)
		"shield":
			var p: ArrowPlayer = World.player_spawner.get_player(event.peer)
			if p and p.spawn_serial == event.serial:
				p.present_shield(event)

func finish(arrow: Arrow) -> void:
	_simulation.erase(arrow.projectile_id)
	World.combat_network.queue_event({"kind": "terminal", "projectile": arrow.projectile_id, "position": arrow.global_position})

func baseline() -> Array:
	var result: Array = []
	for arrow: Arrow in _simulation.values():
		if is_instance_valid(arrow) and not arrow._finished:
			var data := arrow.launch_data.duplicate()
			data.owner_id = arrow.owner_id
			data.erase("reflected_from")
			result.append(data)
	return result

func install_baseline(arrows: Array) -> void:
	var live := {}
	_reflections.clear()
	for data: Dictionary in arrows:
		live[data.serial] = true
		_confirm(data)
	for id: int in _visuals.keys():
		if not live.has(id):
			if is_instance_valid(_visuals[id]):
				_visuals[id].queue_free()
			_visuals.erase(id)

func clear_projectiles() -> void:
	for child in get_node("../Projectiles").get_children():
		child.queue_free()
	_simulation.clear()
	_visuals.clear()
	_ghosts.clear()
	_terminated.clear()
	_reflections.clear()
	_ground_arrows = null

func remove_owned_projectiles(peer_id: int) -> void:
	if multiplayer.is_server():
		for arrow: Arrow in _simulation.values():
			if is_instance_valid(arrow) and arrow.owner_id == peer_id:
				arrow._finish()

func reflect_arrow(arrow: Arrow, blocker: ArrowPlayer, at: Vector2) -> Arrow:
	var reflected_time := arrow.trajectory_time_at(at)
	arrow.global_position = at
	arrow._finish()
	return spawn_arrow({"position": arrow.origin, "velocity": arrow.initial_velocity,
		"trajectory_time": reflected_time, "flight_direction": -arrow.flight_direction,
		"travel_time_multiplier": arrow.travel_time_multiplier, "owner_id": blocker.peer_id,
		"team": blocker.team, "damage": arrow.damage, "scale": arrow.visual_scale,
		"reflected_from": arrow.projectile_id})

func server_notify_hit(shooter_id: int, headshot: bool) -> void:
	if multiplayer.is_server():
		World.combat_network.queue_event({"kind": "hit", "peer": shooter_id, "headshot": headshot})

func _play_hit_sound(headshot: bool) -> void:
	(headshot_sound if headshot else hit_sound).play()
	hit_sound_played.emit(headshot)

func server_report_impact(pos: Vector2, rot: float, team: int, scale: float, victim: Node) -> void:
	if multiplayer.is_server():
		World.combat_network.queue_event({"kind": "impact", "position": pos, "rotation": rot,
			"team": team, "scale": scale, "victim": str(World.get_path_to(victim)) if victim != null else "",
			"local_position": victim.to_local(pos) if victim is Node2D else pos})

func _spawn_stuck_arrow(pos: Vector2, rot: float, team: int, scale: float, victim_path: NodePath) -> void:
	if MultiplayerService.is_dedicated_server():
		return
	var stuck: StuckArrow = STUCK_ARROW_SCENE.instantiate()
	if victim_path.is_empty():
		_ensure_ground_container().add_child(stuck)
		stuck.global_position = pos
		stuck.global_rotation = rot
		stuck.reset_physics_interpolation()
		stuck.setup(team, scale)
		_enforce_ground_cap()
		return
	var victim := World.get_node_or_null(victim_path)
	if victim == null or not victim.has_method("attach_stuck_arrow"):
		stuck.free()
		return
	victim.attach_stuck_arrow(stuck, pos, rot)
	stuck.setup(team, scale)

func _ensure_ground_container() -> Node2D:
	if not is_instance_valid(_ground_arrows):
		_ground_arrows = Node2D.new()
		_ground_arrows.name = "StuckArrows"
		_ground_arrows.z_index = -1
		get_node("../Projectiles").add_child(_ground_arrows)
	return _ground_arrows

func _enforce_ground_cap() -> void:
	var live: Array[StuckArrow] = []
	for child in _ground_arrows.get_children():
		if child is StuckArrow and not child.is_fading():
			live.append(child)
	for i in maxi(live.size() - GROUND_ARROW_CAP, 0):
		live[i].fade_out()
