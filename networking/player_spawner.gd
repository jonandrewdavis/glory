class_name PlayerSpawner
extends MultiplayerSpawner

const ARROW_PLAYER := preload("uid://bd7kaorjlt0go")
const SPAWN_SLOTS := 8

func _ready() -> void:
	spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	if MultiplayerService.is_host() and MultiplayerService.backend.get_joinable() and not MultiplayerService.banlist.has(MultiplayerService.backend.get_uid(peer_id)):
		spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if MultiplayerService.is_host():
		remove_player(peer_id)

## Host only.
func spawn_player(id: int) -> void:
	if has_node(str(id)) or not multiplayer.is_server():
		return
	var team: int = World.scoreboard.assign_team(id)
	spawn({"peer_id": id, "team": team, "spawn_index": randi() % SPAWN_SLOTS})

func _spawn_player(data: Variant) -> Node:
	var player: ArrowPlayer = ARROW_PLAYER.instantiate()
	player.name = str(data.peer_id)
	player.team = data.get("team", Teams.Team.BLUE)
	player.spawn_index = data.get("spawn_index", 0)
	return player

func get_player(id: int) -> ArrowPlayer:
	return get_node_or_null(str(id)) as ArrowPlayer

func replace_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	var player := get_player(id)
	if player:
		remove_child(player)
		player.queue_free()
	spawn_player(id)

func remove_player(id: int) -> void:
	var player := get_node_or_null(str(id))
	if player:
		remove_child(player)
		player.queue_free()
	World.scoreboard.remove_player(id)

func clear_players() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
