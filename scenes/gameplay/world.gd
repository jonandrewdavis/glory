extends Node

const DEFAULT_LEVEL := "example"
var session := 0
@onready var level_loader: LevelLoader = %LevelLoader
@onready var player_spawner: PlayerSpawner = %PlayerSpawner

func _ready() -> void:
	MultiplayerService.lobby_joined.connect(_on_lobby_joined)
	MultiplayerService.game_exited.connect(clear)

func _on_lobby_joined() -> void:
	if not MultiplayerService.is_host():
		return
	session += 1
	var token := session
	await level_loader.spawn_level(DEFAULT_LEVEL)
	if token != session or not MultiplayerService.is_host():
		return
	player_spawner.spawn_player(1)
	MultiplayerService.set_joinable(true)

func clear() -> void:
	session += 1
	player_spawner.clear_players()
	level_loader.clear_level()

func change_level(key: String) -> void:
	if MultiplayerService.is_host() and LevelLoader.LEVEL_DICT.has(key):
		level_loader.spawn_level.rpc(key)
