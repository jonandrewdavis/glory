extends Node
## Run two processes: -- --server and -- --client.
const PORT := 19739
var failures := 0
var started := 0
var requested := false
var received := 0
var finished := false

func _ready() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	print("PASS: " if condition else "FAIL: ", message)
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	started = Time.get_ticks_msec()
	MultiplayerService.set_backend(MultiplayerService.BackendType.ENET, false)
	# This fixture exercises scoreboard networking without spawning gameplay actors.
	multiplayer.peer_connected.disconnect(World.player_spawner._on_peer_connected)
	World.scoreboard.player_killed.connect(_on_kill)
	var peer := ENetMultiplayerPeer.new()
	if "--server" in OS.get_cmdline_user_args():
		assert(peer.create_server(PORT, 4) == OK)
		multiplayer.multiplayer_peer = peer
		MultiplayerService.in_lobby = true
		MultiplayerService.backend.joinable = true
		for id in [10, 20, 30, 40]:
			World.scoreboard.entries[id] = {"team": Teams.Team.ORANGE if id == 40 else Teams.Team.BLUE, "kills": 0, "deaths": 0, "assists": 0}
		World.scoreboard.record_kill(10, 40, [20, 30])
		print("KDA_SERVER_READY")
	else:
		assert(peer.create_client("127.0.0.1", PORT) == OK)
		multiplayer.multiplayer_peer = peer

func _process(_delta: float) -> void:
	if finished or started == 0:
		return
	if Time.get_ticks_msec() - started > 15000:
		push_error("KDA network check timed out")
		get_tree().quit(1)
	if multiplayer.is_server() or requested or not World.scoreboard.entries.has(40):
		return
	requested = true
	var board := World.scoreboard
	expect(board.entries[10].kills == 1 and board.entries[20].assists == 1 and board.entries[30].assists == 1 and board.entries[40].deaths == 1, "Late join receives complete K/D/A snapshot")
	expect(received == 0, "Late join does not replay historical kill events")
	var before := board.entries.duplicate(true)
	board.record_kill(10, 40, [20, 30])
	expect(board.entries == before and received == 0, "Client cannot author kills or assists")
	_request_combat.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_combat() -> void:
	if multiplayer.is_server():
		World.scoreboard.record_kill(10, 40, [20, 30])

func _on_kill(event: Dictionary) -> void:
	received += 1
	if multiplayer.is_server():
		return
	var board := World.scoreboard
	expect(received == 1 and event.killer_id == 10 and event.victim_id == 40, "Client receives exactly one live player-kill event")
	expect(board.entries[10].kills == 2 and board.entries[20].assists == 2 and board.entries[30].assists == 2 and board.entries[40].deaths == 2, "All K/D/A updates arrive before the kill event")
	expect(event.team == Teams.Team.BLUE and event.has("killer_name") and event.has("victim_name"), "Kill event snapshots names and killer team")
	_finish.rpc_id(1, failures)
	finished = true
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(1 if failures else 0)

@rpc("any_peer", "call_remote", "reliable")
func _finish(client_failures: int) -> void:
	if not multiplayer.is_server():
		return
	finished = true
	expect(received == 2 and World.scoreboard.entries[20].assists == 2, "Host and client agree on live combat totals")
	print("KDA network checks completed; failures=", failures + client_failures)
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(1 if failures + client_failures else 0)
