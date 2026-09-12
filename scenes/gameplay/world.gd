extends Node
# Global class: World

# TODO: Organize this file since it'll be very central to everything.
# This is very much like our "Global" class, since it's an autoload and never
# ever disappears. Players and Levels are loaded in and out, but it is always 
# at the top level.


# UI
var ui_layer: UILayer


const DEFAULT_LEVEL := "LostMonuments"

var session := 0
@onready var level_loader: LevelLoader = %LevelLoader
@onready var player_spawner: PlayerSpawner = %PlayerSpawner
@onready var fly_cam: Node3D = %FlyCam

func _ready() -> void:
	if OS.is_debug_build() and get_tree().current_scene == self:
		host_debug_world()
		
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

func host_debug_world():
	var opt = HostOptions.new()
	opt.max_players = 1
	opt.lobby_name = 'test'
	MultiplayerService.backend_changed.connect(func(_new): MultiplayerService.host_game(opt)) 
	MultiplayerService.set_backend(MultiplayerService.BackendType.ENET)
