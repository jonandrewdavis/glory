extends Node
## Headless load bot: joins a local PlayFlow server, wanders and fires so the
## server's CPU can be measured under N clients. See tools/load_test.sh.
var _player: ArrowPlayer
var _time := 0.0
var _action_left := 0.5
var _mode := "combat"

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--workload="):
			_mode = argument.trim_prefix("--workload=")
	MultiplayerService.set_backend(MultiplayerService.BackendType.PLAYFLOW, false)
	MultiplayerService.join_game("ws://127.0.0.1:8080")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = World.player_spawner.get_player(multiplayer.get_unique_id()) if multiplayer.has_multiplayer_peer() else null
		if _player != null and World.combat_network.epoch != 0:
			_player.set_physics_process(false)
			_player.aim_reticle.set_physics_process(false)
			print("LOAD_BOT_READY")
		else:
			_player = null
		return
	if _player.is_dead:
		return
	if _mode == "idle":
		return
	# Exercise the actual controller, collision, charge and shield paths with
	# deterministic input. Headless windows cannot capture a hardware mouse.
	_time += delta
	if not _player.is_on_floor():
		_player.velocity += _player.get_gravity() * delta
	var direction := 1.0 if int(_time / 2.0) % 2 == 0 else -1.0
	_player._update_horizontal(delta, direction, 0.5 if _player.is_preparing or _player.is_blocking else 1.0)
	_player._update_jump(delta, true, fmod(_time, 3.0) < delta, true, _player.is_on_floor())
	_player.move_and_slide()
	if _player.is_on_floor():
		_player._jump_consumed = false
	_player.aim_reticle.set_direction(Vector2(direction, -0.4).normalized())
	_player.sprite.flip_h = direction < 0.0
	if _mode == "move":
		return
	_player.fire_cooldown_left = maxf(0, _player.fire_cooldown_left - delta)
	_player.shield_cooldown_left = maxf(0, _player.shield_cooldown_left - delta)
	var mouse = _player.global_position + _player.aim_reticle.direction * 96.0
	if _player.is_blocking:
		_player.block_time_left -= delta
		if _player.block_time_left <= 0:
			_player._end_block()
		return
	_action_left -= delta
	if _action_left <= 0 and not _player.is_preparing and _player.shield_cooldown_left <= 0:
		_player._start_block(mouse)
		_action_left = 5.0
	elif _player.fire_cooldown_left <= 0:
		_player._prepare(delta, mouse)
		if _player.preparation_time >= _player.minimum_preparation_time(0):
			_player._fire(mouse)
