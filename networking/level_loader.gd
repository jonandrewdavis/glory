class_name LevelLoader
extends Node

const WAIT_INTERVAL := 0.1
const LEVEL_DICT: Dictionary[String, String] = {
	"LostMonuments": "uid://d1xpycgi6qs7k",
}
var current_key := ""
var generation := 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(peer_id: int) -> void:
	if MultiplayerService.is_host() and not current_key.is_empty():
		spawn_level.rpc_id(peer_id, current_key)

func clear_level() -> void:
	generation += 1
	current_key = ""
	for child in get_children():
		remove_child(child)
		child.queue_free()

@rpc("authority", "call_local", "reliable")
func spawn_level(key: String) -> void:
	if not LEVEL_DICT.has(key):
		return
	clear_level()
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
