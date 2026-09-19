class_name WebPresence
extends Node
## PlayFlow experiment: JS owns hidden-tab polling; SceneTree owns visible polling.
## Resume always uses a fresh transport/replication cache and a server-issued token.
const HEARTBEAT_MS := 1000
const STALE_MS := 8000
const GRACE_MS := 120000
const RECOVERY_MS := 30000
# RPCs may enqueue deferred SceneTree work that polling alone cannot flush.
# Bound the experiment's hidden lifetime, then park the transport until return.
const PUMP_WINDOW_MS := 30000
const JS := """
(() => {
  let callback, timer;
  const disabled = new URLSearchParams(location.search).get('background_poll') === '0';
  const dispatch = kind => { if (callback) callback(kind, document.hidden); };
  const visibility = () => dispatch('visibility');
  const freeze = () => dispatch('freeze');
  // Closing or navigating away: release the session instead of reserving it.
  const pagehide = event => { if (!event.persisted) dispatch('pagehide'); };
  window.gloryBackground = {
    start(cb) {
      callback = cb;
	  document.addEventListener('visibilitychange', visibility);
	  document.addEventListener('freeze', freeze);
	  window.addEventListener('pagehide', pagehide);
	  timer = setInterval(() => { if (document.hidden && !disabled) dispatch('tick'); }, 250);
      visibility();
    },
    stop() {
      clearInterval(timer);
	  document.removeEventListener('visibilitychange', visibility);
	  document.removeEventListener('freeze', freeze);
	  window.removeEventListener('pagehide', pagehide);
      callback = undefined;
    },
    report(json) { window.gloryNetworkDiagnostics = JSON.parse(json); }
  };
})();
"""

var hidden := false
var recovering := false
var experiment_enabled := false
var resume_token := "" # Memory only; never log this bearer credential.
var sessions: Dictionary = {} # server: token -> session, including disconnected actors
var peer_tokens: Dictionary = {}
var admissions: Dictionary = {}
var _callback: JavaScriptObject
var _bridge: JavaScriptObject
var _polling := false
var _last_poll := 0
var _last_heartbeat := 0
var _last_report := 0
var _retry_at := 0
var _recovery_deadline := 0
var _snapshot_requested := false
var _snapshot: Dictionary = {}
var _snapshot_at := 0
var _snapshot_frame := 0
var _snapshot_request_at := 0
var _requested_revision := -1
var _hidden_since := 0
var _previous_auto_poll := true
var release_acknowledged := false
var stats := {"polls": 0, "max_poll_gap_ms": 0, "max_queue_packets": 0,
	"max_poll_us": 0, "recoveries": 0, "poll_errors": 0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	experiment_enabled = bool(ProjectSettings.get_setting("networking/background_resume/enabled", false)) or "--background-networking" in OS.get_cmdline_user_args()
	if OS.has_feature("web") and not experiment_enabled:
		experiment_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('background_networking') === '1'"))
	if OS.has_feature("web") and experiment_enabled:
		JavaScriptBridge.eval(JS)
		_bridge = JavaScriptBridge.get_interface("gloryBackground")
		_callback = JavaScriptBridge.create_callback(_browser_event)
		_bridge.start(_callback)

func enabled() -> bool:
	return experiment_enabled and MultiplayerService.backend_type == MultiplayerService.BackendType.PLAYFLOW

func blocks_input() -> bool:
	return enabled() and (hidden or recovering)

func _browser_event(args: Array) -> void:
	if str(args[0]) == "pagehide":
		# Best effort: the send is synchronous, but a lost release falls back to grace.
		release()
		return
	set_hidden(bool(args[1]))
	if str(args[0]) == "freeze":
		_send_heartbeat(true)
	if hidden and str(args[0]) == "tick" and enabled() and not recovering:
		_poll_background()

func set_hidden(value: bool) -> void:
	if hidden == value:
		return
	hidden = value
	if not enabled():
		return
	if hidden:
		_last_poll = Time.get_ticks_msec()
		_hidden_since = _last_poll
		_previous_auto_poll = get_tree().multiplayer_poll
		get_tree().multiplayer_poll = false
		_clear_local_input()
		_send_heartbeat(true)
	else:
		get_tree().multiplayer_poll = _previous_auto_poll
		if recovering:
			_recovery_deadline = Time.get_ticks_msec() + RECOVERY_MS
		if MultiplayerService.in_lobby and not resume_token.is_empty():
			begin_recovery("tab visible")
	_report("visibility")

func _clear_local_input() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not is_instance_valid(World.player_spawner):
		return
	var player: ArrowPlayer = World.player_spawner.get_player(multiplayer.get_unique_id())
	if player:
		player.clear_away_actions()
		player.network_suspended = true
		World.combat_network.suspend()

func _poll_background() -> void:
	if _polling or recovering or (not MultiplayerService.in_lobby and not MultiplayerService.pending) or not multiplayer.has_multiplayer_peer():
		return
	if get_tree().multiplayer_poll:
		_previous_auto_poll = true
		get_tree().multiplayer_poll = false
	if MultiplayerService.in_lobby and not resume_token.is_empty() and Time.get_ticks_msec() - _hidden_since >= PUMP_WINDOW_MS:
		begin_recovery("hidden polling window elapsed")
		multiplayer.multiplayer_peer.close()
		return
	_polling = true
	var now := Time.get_ticks_msec()
	if _last_poll:
		stats.max_poll_gap_ms = maxi(stats.max_poll_gap_ms, now - _last_poll)
	_last_poll = now
	var peer := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		stats.max_queue_packets = maxi(stats.max_queue_packets, peer.get_peer(1).get_available_packet_count())
	var start := Time.get_ticks_usec()
	var error := multiplayer.poll()
	stats.max_poll_us = maxi(stats.max_poll_us, Time.get_ticks_usec() - start)
	stats.polls += 1
	if error != OK:
		stats.poll_errors += 1
	_polling = false
	# A heartbeat proves the application drained its queue, not merely that TCP lives.
	_send_heartbeat()
	if now - _last_report >= 5000:
		_report("background poll")

func _process(_delta: float) -> void:
	if not enabled():
		return
	if MultiplayerService.is_host():
		_server_tick()
		return
	if hidden:
		return
	_send_heartbeat()
	if not recovering:
		return
	var now := Time.get_ticks_msec()
	if now >= _recovery_deadline:
		MultiplayerService._end_game(MultiplayerService.RESUME_FAILED_REASON)
		return
	if _retry_at > 0 and now >= _retry_at:
		_retry_at = 0
		_reconnect()
	if MultiplayerService.pending or not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not World.level_loader.is_level_ready() or World.player_spawner.get_player(multiplayer.get_unique_id()) == null:
		return
	if _requested_revision != World.level_loader.revision or now - _snapshot_request_at > 2000:
		_snapshot_requested = false
	if not _snapshot_requested:
		_snapshot_requested = true
		_requested_revision = World.level_loader.revision
		_snapshot_request_at = now
		_request_snapshot.rpc_id(1, World.level_loader.revision)
	elif not _snapshot.is_empty() and Engine.get_process_frames() > _snapshot_frame:
		_finish_recovery()

func _send_heartbeat(force := false) -> void:
	if not enabled() or MultiplayerService.pending or not MultiplayerService.in_lobby or multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var now := Time.get_ticks_msec()
	if force or now - _last_heartbeat >= HEARTBEAT_MS:
		_last_heartbeat = now
		_heartbeat.rpc_id(1, hidden or recovering)

@rpc("any_peer", "call_remote", "reliable")
func _heartbeat(away: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var token: String = peer_tokens.get(id, "")
	if not sessions.has(token):
		return
	var state: Dictionary = sessions[token]
	state.last_seen = Time.get_ticks_msec()
	state.away = away
	_apply_away(id, away)

func is_peer_away(id: int) -> bool:
	var state: Dictionary = sessions.get(peer_tokens.get(id, ""), {})
	return bool(state.get("away", false)) or bool(state.get("disconnected", false))

func keep_peer(id: int) -> bool:
	return enabled() and peer_tokens.has(id) and sessions.has(peer_tokens[id])

func _apply_away(id: int, value: bool) -> void:
	var player: ArrowPlayer = World.player_spawner.get_player(id)
	if player:
		player.set_network_away(value)

func can_resume(token: String) -> bool:
	return not token.is_empty() and sessions.has(token) and int(sessions[token].expires) > Time.get_ticks_msec()

func reserve(id: int, token: String) -> String:
	if token.is_empty():
		token = Crypto.new().generate_random_bytes(32).hex_encode()
		sessions[token] = {"peer_id": 0, "away": true, "disconnected": true,
			"last_seen": Time.get_ticks_msec(), "expires": Time.get_ticks_msec() + 5000}
	elif not can_resume(token) or admissions.values().has(token):
		return ""
	admissions[id] = token
	return token

func server_connected(id: int) -> void:
	if not admissions.has(id):
		return
	var token: String = admissions[id]
	admissions.erase(id)
	var state: Dictionary = sessions[token]
	var old_id: int = state.peer_id
	if old_id > 0 and old_id != id:
		# Retire the old transport before migrating its actor; stale packets cannot
		# acquire authority over the newly named incarnation.
		if multiplayer.get_peers().has(old_id):
			disconnect_transport(old_id)
		World.player_spawner.restore_session(old_id, id)
		MultiplayerService.usernames.erase(old_id)
		peer_tokens.erase(old_id)
	state.peer_id = id
	state.disconnected = false
	state.away = old_id > 0
	state.last_seen = Time.get_ticks_msec()
	state.expires = Time.get_ticks_msec() + GRACE_MS
	state.snapshot_at = -2000
	peer_tokens[id] = token
	_apply_away(id, state.away)

func server_disconnected(id: int) -> void:
	World.level_loader.ready_peers.erase(id)
	if not keep_peer(id):
		return
	var state: Dictionary = sessions[peer_tokens[id]]
	if state.disconnected:
		return
	state.disconnected = true
	state.away = true
	state.expires = Time.get_ticks_msec() + GRACE_MS
	_apply_away(id, true)

func disconnect_transport(id: int) -> void:
	if not multiplayer.get_peers().has(id):
		return
	# SceneMultiplayer removes replication/relay state but suppresses its public
	# disconnect signal. Also remove the socket immediately: WebSocket's graceful
	# close otherwise leaves a closing peer in broadcasts until a later poll.
	(multiplayer as SceneMultiplayer).disconnect_peer(id)
	multiplayer.multiplayer_peer.disconnect_peer(id, true)
	multiplayer.peer_disconnected.emit(id)

func _server_tick() -> void:
	var now := Time.get_ticks_msec()
	for token: String in sessions.keys():
		var state: Dictionary = sessions[token]
		var id: int = state.peer_id
		if state.disconnected:
			if admissions.values().has(token):
				continue # Authentication has its own five-second deadline.
			if now >= int(state.expires):
				sessions.erase(token)
				peer_tokens.erase(id)
				if id > 0:
					World.player_spawner.remove_player(id)
					MultiplayerService.usernames.erase(id)
		elif now - int(state.last_seen) > STALE_MS:
			server_disconnected(id)
			disconnect_transport(id)
			print("[background-net] application stalled; reserved player ", id)
		else:
			state.expires = now + GRACE_MS

func begin_recovery(reason: String) -> bool:
	if not enabled() or resume_token.is_empty() or not MultiplayerService.in_lobby or not MultiplayerService.kick_reason.is_empty():
		return false
	if not recovering:
		recovering = true
		_recovery_deadline = Time.get_ticks_msec() + RECOVERY_MS
		stats.recoveries += 1
		_clear_local_input()
		_report(reason)
	# The browser callback never clears scenes inside a multiplayer poll.
	if not hidden:
		_retry_at = Time.get_ticks_msec() + 1
	return true

func retry() -> void:
	_snapshot_requested = false
	_snapshot.clear()
	_retry_at = Time.get_ticks_msec() + 1000

func _reconnect() -> void:
	_snapshot_requested = false
	_snapshot.clear()
	var backend := MultiplayerService.backend as PlayFlowBackend
	var url := backend.address
	backend.leave_game()
	World.clear()
	MultiplayerService.usernames.clear()
	MultiplayerService.pending = true
	MultiplayerService._on_status_changed("Resuming session...")
	backend.join_game(url)

@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot(revision: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not keep_peer(id) or revision != World.level_loader.revision or not World.level_loader.ready_peers.has(id):
		return
	var state: Dictionary = sessions[peer_tokens[id]]
	if Time.get_ticks_msec() - int(state.get("snapshot_at", -2000)) < 1000:
		return
	state.snapshot_at = Time.get_ticks_msec()
	World.combat_network.send_baseline(id)
	_receive_snapshot.rpc_id(id, {"revision": revision, "entries": World.scoreboard.entries,
		"names": MultiplayerService.usernames, "wins": World.round_manager.wins,
		"phase": World.round_manager.phase, "winner": World.round_manager.winner,
		"round": World.round_manager.round_number, "owners": World.respawn_manager.owners,
		"waits": World.respawn_manager._wait_snapshot(),
		"switch_ms": maxi(0, int(World.scoreboard._switch_deadlines.get(id, 0)) - Time.get_ticks_msec())})

@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(value: Dictionary) -> void:
	if not recovering:
		return
	_snapshot = value
	_snapshot_at = Time.get_ticks_msec()
	_snapshot_frame = Engine.get_process_frames()

func _finish_recovery() -> void:
	if int(_snapshot.revision) != World.level_loader.revision:
		_snapshot_requested = false
		_snapshot.clear()
		return
	World.scoreboard._sync_all(_snapshot.entries)
	MultiplayerService._receive_usernames(_snapshot.names)
	World.round_manager._sync_round(_snapshot.wins, _snapshot.phase, _snapshot.winner, _snapshot.round)
	World.respawn_manager._sync_state(_snapshot.revision, _snapshot.owners, _snapshot.waits)
	World.scoreboard.local_switch_deadline = Time.get_ticks_msec() + int(_snapshot.switch_ms)
	_snapshot.clear()
	recovering = false
	var player: ArrowPlayer = World.player_spawner.get_player(multiplayer.get_unique_id())
	player.set_network_away(false)
	if player.health.is_alive():
		player.network_suspended = false
	World.combat_network.resume()
	_send_heartbeat(true)
	MultiplayerService._on_status_changed("Session restored. Click to play.")
	_report("restored")

func reset() -> void:
	resume_token = ""
	recovering = false
	_retry_at = 0
	_snapshot_requested = false
	_snapshot.clear()
	_last_poll = 0
	sessions.clear()
	peer_tokens.clear()
	admissions.clear()
	get_tree().multiplayer_poll = true

func release() -> bool:
	release_acknowledged = false
	if enabled() and not multiplayer.is_server() and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_release_session.rpc_id(1)
		return true
	return false

@rpc("any_peer", "call_remote", "reliable")
func _release_session() -> void:
	if multiplayer.is_server():
		var id := multiplayer.get_remote_sender_id()
		forget_peer(id)
		_released.rpc_id(id)

@rpc("authority", "call_remote", "reliable")
func _released() -> void:
	release_acknowledged = true

func forget_peer(id: int) -> void:
	sessions.erase(peer_tokens.get(id, ""))
	peer_tokens.erase(id)
	admissions.erase(id)

func _report(reason: String) -> void:
	_last_report = Time.get_ticks_msec()
	var report := stats.duplicate()
	report.reason = reason
	report.hidden = hidden
	report.recovering = recovering
	report.time_ms = _last_report
	print("[background-net] ", JSON.stringify(report))
	if _bridge:
		_bridge.report(JSON.stringify(report))

func _exit_tree() -> void:
	if _bridge:
		_bridge.stop()
	get_tree().multiplayer_poll = true
