class_name LevelLoader
extends Node

const WAIT_INTERVAL := 0.1
const LEVEL_DICT: Dictionary[String, String] = {
	"Fortress1": "res://levels/Fortress1.tscn",
	"Fortress2": "res://levels/Fortress2.tscn",
}
const DEFAULT_LEVEL := "Fortress2"

signal level_loaded
signal level_clearing
signal peer_level_ready(peer_id: int)

var current_key := ""
var generation := 0
var revision := 0
var ready_peers: Dictionary = {}
var _level_ready := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id: int) -> void: ready_peers.erase(id))

func _on_peer_connected(peer_id: int) -> void:
	if MultiplayerService.is_host() and not current_key.is_empty():
		spawn_level.rpc_id(peer_id, current_key, revision)

func clear_level() -> void:
	ready_peers.clear()
	level_clearing.emit()
	generation += 1
	current_key = ""
	_level_ready = false
	for child in get_children():
		remove_child(child)
		child.queue_free()

@rpc("authority", "call_local", "reliable")
func spawn_level(key: String, server_revision: int = 0) -> void:
	if not LEVEL_DICT.has(key):
		return
	clear_level()
	if multiplayer.is_server():
		revision += 1
		if not multiplayer.get_peers().is_empty():
			# Remote-only calls avoid re-entering the server's load operation.
			for id in multiplayer.get_peers():
				spawn_level.rpc_id(id, key, revision)
	else:
		revision = server_revision
	current_key = key
	var token := generation
	var path := LEVEL_DICT[key]
	var err := ResourceLoader.load_threaded_request(path, "PackedScene")
	if err != OK:
		MultiplayerService._end_game("Could not load level.")
		return
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().create_timer(WAIT_INTERVAL).timeout
		if token != generation:
			return
	if token != generation:
		return
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		MultiplayerService._end_game("Could not load level.")
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(path)
	add_child(packed.instantiate())
	_level_ready = true
	level_loaded.emit()
	if not multiplayer.is_server():
		_peer_level_ready.rpc_id(1, revision)

@rpc("any_peer", "call_remote", "reliable")
func _peer_level_ready(server_revision: int) -> void:
	if not multiplayer.is_server() or server_revision != revision or current_key.is_empty():
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1 or not multiplayer.get_peers().has(id):
		return
	ready_peers[id] = true
	peer_level_ready.emit(id)

func is_level_ready() -> bool:
	return _level_ready
