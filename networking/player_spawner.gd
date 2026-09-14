class_name PlayerSpawner
extends MultiplayerSpawner

const ARROW_PLAYER = preload("uid://bd7kaorjlt0go")

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	if MultiplayerService.is_host() and MultiplayerService.backend.get_joinable() and not MultiplayerService.banlist.has(MultiplayerService.backend.get_uid(peer_id)):
		spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if MultiplayerService.is_host():
		remove_player(peer_id)

func spawn_player(id: int) -> void:
	if has_node(str(id)):
		return
	var player: CharacterBody3D = ARROW_PLAYER.instantiate()
	player.name = str(id)
	add_child(player)

func remove_player(id: int) -> void:
	var player := get_node_or_null(str(id))
	if player:
		remove_child(player)
		player.queue_free()

func clear_players() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
