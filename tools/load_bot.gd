extends Node
## Headless load bot: joins a local PlayFlow server, wanders and fires so the
## server's CPU can be measured under N clients. See tools/load_test.sh.
var _player: ArrowPlayer
var _time := 0.0
var _fire_left := 1.0
var _origin := Vector2.ZERO

func _ready() -> void:
	MultiplayerService.set_backend(MultiplayerService.BackendType.PLAYFLOW, false)
	MultiplayerService.join_game("ws://127.0.0.1:8080")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = World.player_spawner.get_player(multiplayer.get_unique_id()) if multiplayer.has_multiplayer_peer() else null
		if _player != null:
			_origin = _player.position
			print("LOAD_BOT_READY")
		return
	if _player.is_dead:
		_origin = _player.position
		return
	# Headless clients cannot capture the mouse, so drive the body directly;
	# the replication and fire traffic is the same as a real player's.
	_time += delta
	_player.position.x = _origin.x + sin(_time * 1.3 + float(multiplayer.get_unique_id() % 7)) * 60.0
	_fire_left -= delta
	if _fire_left <= 0.0:
		_fire_left = randf_range(0.9, 1.6)
		var aim := Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.1)).normalized()
		_player.request_fire.rpc_id(1, aim, 0, 1.0)
