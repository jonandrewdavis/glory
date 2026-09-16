class_name CreepSpawner
extends MultiplayerSpawner
## Persistent spawn path; replication is gated by each peer's level readiness.

const CREEP_SCENE := preload("res://entities/creep.tscn")
@export var wave_size := 3
@export var wave_interval := 30.0

var pending: Array[Dictionary] = []
var _serial := 0
var _wave_left := 0.0
var _active := false

func _ready() -> void:
	spawn_function = _spawn_creep
	var loader: LevelLoader = get_node("../LevelLoader")
	loader.level_loaded.connect(_on_level_loaded)
	loader.level_clearing.connect(clear_creeps)
	loader.peer_level_ready.connect(_on_peer_level_ready)

func _on_level_loaded() -> void:
	if not multiplayer.is_server():
		return
	_active = true
	_wave_left = maxf(wave_interval, 0.1)
	queue_wave()

func _on_peer_level_ready(id: int) -> void:
	for creep in get_node(spawn_path).get_children():
		creep.synchronizer.set_visibility_for(id, true)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not _active:
		return
	_wave_left -= delta
	while _wave_left <= 0.0:
		_wave_left += maxf(wave_interval, 0.1)
		queue_wave()
	_flush_pending()

func queue_wave() -> void:
	if not multiplayer.is_server():
		return
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var group := "creep_spawn_blue" if team == Teams.Team.BLUE else "creep_spawn_orange"
		var markers := get_tree().get_nodes_in_group(group)
		var goals := get_tree().get_nodes_in_group("creep_spawn_orange" if team == Teams.Team.BLUE else "creep_spawn_blue")
		if markers.is_empty() or goals.is_empty():
			continue
		for index in range(wave_size):
			var marker: Node2D = markers[index % markers.size()]
			pending.append({"team": team, "position": marker.global_position, "goal_x": goals[0].global_position.x})

func _flush_pending() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Creep.BODY_SIZE + Vector2(4, 4)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1 | Creep.LAYER
	var reserved: Array[Vector2] = []
	var waiting: Array[Dictionary] = []
	for data in pending:
		var at: Vector2 = data.position
		query.transform = Transform2D(0.0, at)
		if not get_viewport().world_2d.direct_space_state.intersect_shape(query, 1).is_empty():
			waiting.append(data)
			continue
		var occupied := false
		# Keep a slot reserved even while its previous soldier is airborne.
		for creep: Creep in get_tree().get_nodes_in_group("creeps"):
			if creep.is_alive() and absf(creep.global_position.x - at.x) < shape.size.x:
				occupied = true
				break
		for point in reserved:
			if absf(point.x - at.x) < shape.size.x and absf(point.y - at.y) < shape.size.y:
				occupied = true
				break
		if occupied:
			waiting.append(data)
			continue
		_serial += 1
		data.serial = _serial
		if spawn(data) != null:
			reserved.append(at)
		else:
			waiting.append(data)
	pending = waiting

func _spawn_creep(data: Variant) -> Node:
	var creep: Creep = CREEP_SCENE.instantiate()
	creep.name = "Creep%d" % data.serial
	creep.setup(data)
	if multiplayer.is_server():
		for id: int in World.level_loader.ready_peers:
			creep.get_node("MultiplayerSynchronizer").set_visibility_for(id, true)
	return creep

func clear_creeps() -> void:
	_active = false
	_wave_left = 0.0
	pending.clear()
	# Clients let MultiplayerSpawner process authoritative despawns. Hide any
	# old replicas immediately while their next level loads.
	for creep in get_node(spawn_path).get_children():
		if multiplayer.is_server():
			creep.free()
		else:
			creep.hide()
