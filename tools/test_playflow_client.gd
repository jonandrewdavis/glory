extends Node
## Integration probe: native headless client with the real autoloads/gameplay.
## Run against a local dedicated process; exits on --expect-full or stays connected.
var service: Node
var started := 0
var reported := false
var balanced := false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	service = get_node("/root/MultiplayerService")
	service.set_backend(service.BackendType.PLAYFLOW, false)
	service.join_lobby_failed.connect(func(reason: String) -> void:
		print("PROBE_REJECTED: " + reason)
		get_tree().quit(0 if "--expect-full" in OS.get_cmdline_user_args() and reason == "Server is full (30/30 players)." else 1))
	service.game_exited.connect(func() -> void: get_tree().quit(1))
	started = Time.get_ticks_msec()
	service.join_game("ws://127.0.0.1:8080")

func _process(_delta: float) -> void:
	if service == null:
		return
	var world := get_node("/root/World")
	if not reported and service.in_lobby:
		var id: int = multiplayer.get_unique_id()
		if world.player_spawner.get_player(id) != null and world.level_loader.is_level_ready():
			reported = true
			print("PROBE_READY: ", id)
			if "--expect-full" in OS.get_cmdline_user_args():
				get_tree().quit(1)
	if reported and not balanced and world.scoreboard.entries.size() == 30:
		assert(not world.scoreboard.entries.has(1), "Dedicated host must not be a player")
		assert(world.scoreboard.team_size(Teams.Team.BLUE) == 15)
		assert(world.scoreboard.team_size(Teams.Team.ORANGE) == 15)
		balanced = true
		print("PROBE_BALANCED: 15 vs 15")
	if not reported and Time.get_ticks_msec() - started > 15000:
		push_error("Probe timed out")
		get_tree().quit(1)
