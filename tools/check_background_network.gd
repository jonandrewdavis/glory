extends Node
## Real WebSocket integration. Native clients exercise the same visibility and
## timer callback entry points; browser throttling must also be tested in Chrome.
var pumping := true
var _reply: Dictionary = {}
var _pump_at := 0
var _started := 0

func _ready() -> void:
	_started = Time.get_ticks_msec()
	if "--observer" in OS.get_cmdline_user_args():
		_observe.call_deferred()
	elif "--playflow-server" not in OS.get_cmdline_user_args():
		_run.call_deferred()

func _observe() -> void:
	MultiplayerService.set_backend(MultiplayerService.BackendType.PLAYFLOW, false)
	MultiplayerService.join_game("ws://127.0.0.1:8080")
	await wait_ready()
	print("BACKGROUND_OBSERVER_READY")

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _started > 65000:
		push_error("BACKGROUND_NETWORK_TIMEOUT")
		get_tree().quit(1)
	if not multiplayer.is_server() and MultiplayerService.presence.hidden and pumping and Time.get_ticks_msec() >= _pump_at:
		_pump_at = Time.get_ticks_msec() + 250
		MultiplayerService.presence._poll_background()

func require(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		get_tree().quit(1)
		assert(value, message)
	print("PASS: ", message)

func wait_ready() -> void:
	while not MultiplayerService.in_lobby or MultiplayerService.pending or MultiplayerService.presence.recovering or not World.level_loader.is_level_ready() or World.player_spawner.get_player(multiplayer.get_unique_id()) == null:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

func command(action: String) -> Dictionary:
	_reply.clear()
	_control.rpc_id(1, action)
	while _reply.is_empty():
		await get_tree().process_frame
	return _reply.duplicate(true)

func _run() -> void:
	MultiplayerService.set_backend(MultiplayerService.BackendType.PLAYFLOW, false)
	MultiplayerService.join_game("ws://127.0.0.1:8080")
	await wait_ready()
	var original: Dictionary = await command("prepare")
	var id := multiplayer.get_unique_id()
	var presence := MultiplayerService.presence
	require(presence.resume_token.length() == 64, "Server issued a resume credential")
	presence.set_hidden(true)
	await get_tree().create_timer(1.2).timeout
	var away: Dictionary = await command("state")
	require(away.away and not away.shield, "Server clears shields and marks hidden player away")
	await command("fire")
	var blocked: Dictionary = await command("state")
	require(blocked.arrows == 0, "Away player cannot fire")
	presence.set_hidden(false)
	await wait_ready()
	var restored: Dictionary = await command("state")
	require(multiplayer.get_unique_id() != id, "Resume creates a fresh peer and replication cache")
	require(restored.health == 37.0 and restored.protection == 0.0, "Resume grants no health or spawn protection")
	require(restored.entry == original.entry and restored.position.distance_to(original.position) < 5, "Team, score and position survive reconnect")
	require(restored.sessions == 2 and restored.players == 2 and not restored.away, "Resume replaces one session without duplicate actors")
	id = multiplayer.get_unique_id()
	presence.set_hidden(true)
	await get_tree().create_timer(0.5).timeout
	await command("kill")
	await get_tree().create_timer(0.2).timeout
	presence.set_hidden(false)
	await wait_ready()
	var dead: Dictionary = await command("state")
	require(dead.health == 0.0 and dead.entry.deaths == original.entry.deaths + 1, "Dead session restores without resurrection or a duplicate death")
	require(dead.remaining > 0, "Respawn countdown survives reconnect")
	await get_tree().create_timer(2.5).timeout
	var alive: Dictionary = await command("state")
	require(alive.health > 0, "Restored dead player completes server respawn")
	presence.set_hidden(true)
	await get_tree().create_timer(0.5).timeout
	await command("reload")
	await get_tree().create_timer(0.7).timeout
	presence.set_hidden(false)
	await wait_ready()
	var mapped: Dictionary = await command("state")
	require(mapped.revision == World.level_loader.revision and mapped.revision > original.revision, "Resume rebuilds the current map after an away map change")
	presence.set_hidden(true)
	await get_tree().create_timer(0.5).timeout
	pumping = false
	await get_tree().create_timer(9.0).timeout
	presence.set_hidden(false)
	pumping = true
	await wait_ready()
	var stalled: Dictionary = await command("state")
	require(stalled.sessions == 2 and stalled.players == 2, "Application stall disconnects transport and restores reserved session")
	require(presence.stats.polls > 0 and presence.stats.poll_errors == 0, "Background polling instrumentation records successful polls")
	presence.set_hidden(true)
	# Advance only the experiment's budget to test parking without a 30s sleep.
	presence._hidden_since = Time.get_ticks_msec() - WebPresence.PUMP_WINDOW_MS
	await get_tree().create_timer(0.5).timeout
	require(presence.recovering, "Hidden polling window parks transport to bound deferred work")
	presence.set_hidden(false)
	await wait_ready()
	require((await command("state")).sessions == 2, "Parked session resumes once")
	# Voluntary departure must release capacity, not reserve an abandoned slot.
	var token := presence.resume_token
	await MultiplayerService.leave_game()
	await get_tree().create_timer(0.5).timeout
	MultiplayerService.join_game("ws://127.0.0.1:8080")
	await wait_ready()
	var fresh: Dictionary = await command("state")
	require(presence.resume_token != token and fresh.sessions == 2, "Explicit leave releases session capacity")
	presence.set_hidden(true)
	await get_tree().create_timer(0.5).timeout
	_control.rpc_id(1, "expire")
	await get_tree().create_timer(1.0).timeout
	presence.set_hidden(false)
	while MultiplayerService.in_lobby:
		await get_tree().process_frame
	require(MultiplayerService.kick_reason == "Session expired. Please join again.", "Expired token cannot resurrect an expired session")
	MultiplayerService.join_game("ws://127.0.0.1:8080")
	await wait_ready()
	require((await command("state")).sessions == 2, "Expired reservation releases capacity")
	id = multiplayer.get_unique_id()
	_control.rpc_id(1, "replacement_timeout")
	while multiplayer.get_unique_id() == id:
		await get_tree().process_frame
	await wait_ready()
	require((await command("state")).players == 2, "Missing replacement acknowledgment disconnects safely and recovers")
	await command("finish")
	print("BACKGROUND_NETWORK_PASSED")
	await MultiplayerService.leave_game()
	get_tree().quit()

@rpc("any_peer", "call_remote", "reliable")
func _control(action: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var player: ArrowPlayer = World.player_spawner.get_player(id)
	match action:
		"prepare":
			World.creep_spawner.set_physics_process(false)
			World.creep_spawner.clear_creeps()
			player.health.regen_enabled = false
			player.health.current = 37
			player.spawn_protection_left = 0
			player.shield_container.show()
			World.scoreboard.entries[id].kills = 7
		"fire":
			player.server_fire(Vector2.RIGHT, 0, 2.0)
		"kill":
			player.spawn_protection_left = 0
			var attacker := ArrowPlayer.new()
			attacker.team = Teams.Team.ORANGE if player.team == Teams.Team.BLUE else Teams.Team.BLUE
			attacker.peer_id = 99
			player.health.take_damage(100, attacker)
			attacker.free()
			World.respawn_manager.pending[id].remaining = 2.0
		"reload":
			await World.level_loader.spawn_level("Fortress2")
			player = World.player_spawner.get_player(id)
		"finish":
			_audit.rpc()
			print("BACKGROUND_SERVER_PASSED")
		"replacement_timeout":
			World.player_spawner.replace_player(id)
			World.player_spawner._replacement_requests[id].deadline = Time.get_ticks_msec() - 1
			World.player_spawner._process(0)
			return
		"expire":
			var presence := MultiplayerService.presence
			presence.server_disconnected(id)
			presence.sessions[presence.peer_tokens[id]].expires = Time.get_ticks_msec() + 250
			presence.disconnect_transport(id)
			return
	_result.rpc_id(id, {"away": MultiplayerService.presence.is_peer_away(id),
		"shield": player.shield_container.visible, "health": player.health.current,
		"protection": player.spawn_protection_left, "entry": World.scoreboard.entries[id],
		"position": player.global_position, "arrows": get_tree().get_nodes_in_group("projectiles").size(),
		"sessions": MultiplayerService.presence.sessions.size(), "players": World.player_spawner.get_child_count(),
		"revision": World.level_loader.revision, "remaining": World.respawn_manager.seconds_left(id)})

@rpc("authority", "call_remote", "reliable")
func _result(value: Dictionary) -> void:
	_reply = value

@rpc("authority", "call_remote", "reliable")
func _audit() -> void:
	require(multiplayer.get_peers().size() == 2, "Relay roster has no stale reconnect peer IDs")
	require(World.player_spawner.get_child_count() == 2 and World.scoreboard.entries.size() == 2, "Observer world and scoreboard have no duplicate actors")
	print("BACKGROUND_AUDIT_PASSED")
