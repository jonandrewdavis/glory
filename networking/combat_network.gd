class_name CombatNetwork
extends Node
## Server publication, owner submissions and combat commands share a stable RPC path.
const PROTOCOL := "glory-batches-1"
const UPSTREAM_HZ := 30.0
const SNAPSHOT_HZ := 20.0
const CHARGE := 0
const CANCEL := 1
const FIRE := 2
const SHIELD := 3
const MAX_COMMANDS := 64
var epoch := 0
var tick := 0
var sequence := 0
var event_sequence := 0
var delay := 0.1
var render_time := 0.0
var clock_offset := 0.0
var _target_offset := 0.0
var _clock_samples: Array[Vector2] = []
var _pings: Dictionary = {}
var _clock_count := 0
var _ping_at := 0.0
var _hello_at := 0.0
var _last_snapshot := 0.0
var _last_delay_sample := -1
var _ages: Array[float] = []
var _upstream_left := 0.0
var _publish_left := 0.0
var _local_sequence := 0
var _command_sequence := 0
var _peer: MultiplayerPeer
var _admitted: Dictionary = {}
var _pending: Dictionary = {}
var _commands: Array[Dictionary] = []
var _states: Dictionary = {}
var _rates: Dictionary = {}
var _congested: Dictionary = {}
var _events: Array[Dictionary] = []
var _presentation_events: Array[Dictionary] = []
var _received_event := 0
var _suspended := false
var _metrics_at := 0.0
var metrics := {"snapshots": 0, "snapshot_bytes": 0, "owner_samples": 0, "rejected": 0,
	"events": 0, "coalesced": 0, "underruns": 0, "resyncs": 0}

func _ready() -> void:
	process_physics_priority = -100
	process_priority = -100
	get_node("../LevelLoader").level_clearing.connect(reset_level)
	multiplayer.peer_disconnected.connect(_forget_peer)

static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func server_time() -> float:
	return now() if multiplayer.is_server() else now() + clock_offset

func reset_level() -> void:
	_pending.clear()
	_commands.clear()
	_states.clear()
	_admitted.clear()
	_events.clear()
	_presentation_events.clear()
	_received_event = 0
	_last_snapshot = 0.0
	_hello_at = 0.0
	_suspended = false
	if not multiplayer.is_server():
		epoch = 0

func _forget_peer(id: int) -> void:
	_pending.erase(id)
	_states.erase(id)
	_admitted.erase(id)
	_rates.erase(id)
	_congested.erase(id)

func suspend() -> void:
	_suspended = true

func resume() -> void:
	_suspended = false
	request_baseline()

func request_baseline() -> void:
	if multiplayer.is_server() or not _connected() or not World.level_loader.is_level_ready():
		return
	if now() < _hello_at:
		return
	_hello_at = now() + 1.0
	metrics.resyncs += 1
	_hello.rpc_id(1, PROTOCOL, World.level_loader.revision)

func _connected() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and (multiplayer.is_server() or multiplayer.get_peers().has(1))

func _physics_process(delta: float) -> void:
	if not _connected():
		return
	if _peer != multiplayer.multiplayer_peer:
		_peer = multiplayer.multiplayer_peer
		reset_level()
		epoch = (randi() & 0x7fffffff) + 1 if multiplayer.is_server() else 0
		_clock_samples.clear()
		_pings.clear()
		_clock_count = 0
		render_time = 0.0
		_local_sequence = 0
		_command_sequence = 0
	if not World.level_loader.is_level_ready():
		return
	if multiplayer.is_server():
		tick += 1
		# Commands carry their own pose. Process these before newer coalesced state.
		for command in _commands:
			_apply_command(command)
		_commands.clear()
		for id: int in _pending:
			_accept_pose(id, _pending[id])
		_pending.clear()
		for p: ArrowPlayer in get_tree().get_nodes_in_group("players"):
			_advance_combat(p)
		_publish_left -= delta
		var publish := _publish_left <= 0.0
		if publish:
			_publish_left += (floorf(-_publish_left * SNAPSHOT_HZ) + 1.0) / SNAPSHOT_HZ
		_flush.call_deferred(publish)
	else:
		if epoch == 0 or (_last_snapshot > 0.0 and now() - _last_snapshot > 0.5):
			request_baseline()
		_upstream_left -= delta
		if epoch != 0 and _upstream_left <= 0.0 and not _suspended:
			_upstream_left += (floorf(-_upstream_left * UPSTREAM_HZ) + 1.0) / UPSTREAM_HZ
			var p: ArrowPlayer = World.player_spawner.get_player(multiplayer.get_unique_id())
			if p and not p.network_suspended and not p.is_dead and not p.network_away and not MultiplayerService.presence.blocks_input() and _can_send(1):
				_submit_pose.rpc_id(1, epoch, World.level_loader.revision, owner_pose(p))

func _process(delta: float) -> void:
	if not _connected():
		return
	if multiplayer.is_server() and "--network-metrics" in OS.get_cmdline_user_args() and now() >= _metrics_at:
		_metrics_at = now() + 1.0
		var output := metrics.duplicate()
		output.physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		output.process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		output.tick = tick
		output.players = _states.size()
		output.arrows = World.projectile_spawner._simulation.size()
		print("NETWORK_METRICS ", JSON.stringify(output))
	if not multiplayer.is_server():
		clock_offset = move_toward(clock_offset, _target_offset, delta * 0.02)
		if epoch != 0 and now() >= _ping_at:
			_ping_at = now() + (0.1 if _clock_count < 8 else 1.0)
			var stamp := now()
			_pings[stamp] = true
			for old: float in _pings.keys():
				if stamp - old > 5.0:
					_pings.erase(old)
			_ping.rpc_id(1, stamp)
	var target := server_time() - delay
	render_time = maxf(render_time, target)
	while not _presentation_events.is_empty() and float(_presentation_events[0].time) <= render_time:
		World.projectile_spawner.present_event(_presentation_events.pop_front())

func owner_pose(p: ArrowPlayer) -> Dictionary:
	_local_sequence += 1
	return {"serial": p.spawn_serial, "sequence": _local_sequence, "time": server_time(),
		"position": p.global_position, "velocity": p.velocity, "aim": p.aim_reticle.direction.angle(),
		"level": p.selected_level, "facing": p.sprite.flip_h}

func command(p: ArrowPlayer, kind: int, shot: int = 0) -> void:
	if not is_instance_valid(p) or not p.is_inside_tree() or p.network_suspended or _suspended:
		return
	_command_sequence += 1
	var message := {"id": _command_sequence, "kind": kind, "shot": shot, "pose": owner_pose(p), "peer": p.peer_id}
	if multiplayer.is_server():
		_apply_command(message)
	elif epoch != 0:
		_submit_command.rpc_id(1, epoch, World.level_loader.revision, message)

func _allowed(id: int, session: int, revision: int) -> bool:
	return multiplayer.is_server() and session == epoch and revision == World.level_loader.revision and _admitted.has(id) and World.level_loader.ready_peers.has(id)

func _rate_ok(id: int) -> bool:
	var rate: Vector2 = _rates.get(id, Vector2(now(), 0))
	if now() - rate.x >= 1.0:
		rate = Vector2(now(), 0)
	rate.y += 1
	_rates[id] = rate
	return rate.y <= 120

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_pose(session: int, revision: int, pose: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _allowed(id, session, revision) or not _rate_ok(id):
		return
	if _pending.has(id):
		metrics.coalesced += 1
	_pending[id] = pose

@rpc("any_peer", "call_remote", "reliable")
func _submit_command(session: int, revision: int, message: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _allowed(id, session, revision) or not _rate_ok(id) or _commands.size() >= MAX_COMMANDS:
		return
	message.peer = id
	_commands.append(message)

func _valid_pose(p: ArrowPlayer, pose: Dictionary) -> bool:
	return p != null and not p.is_dead and not p.network_away and p.spawn_revision == World.level_loader.revision \
		and pose.get("serial") is int and pose.serial == p.spawn_serial and pose.get("sequence") is int \
		and pose.sequence >= 0 and pose.get("position") is Vector2 and pose.position.is_finite() \
		and pose.get("velocity") is Vector2 and pose.velocity.is_finite() and pose.get("aim") is float \
		and is_finite(pose.aim) and pose.get("time") is float and is_finite(pose.time) \
		and absf(pose.time - now()) < 5.0 and pose.get("level") is int and pose.level in range(3) \
		and pose.get("facing") is bool

func _state(p: ArrowPlayer) -> Dictionary:
	if not _states.has(p.peer_id) or _states[p.peer_id].serial != p.spawn_serial:
		_states[p.peer_id] = {"serial": p.spawn_serial, "sequence": -1, "command": -1, "charge": -1.0,
			"cooldown": maxf(p._server_last_fire_msec / 1000.0 + p.FIRE_COOLDOWN, now() + p.fire_cooldown_left), "shield": 0.0,
			"shield_ready": now() + p.shield_cooldown_left, "pending": 0, "aim": 0.0,
			"level": 0, "facing": false, "source_time": now(), "last_shot": 0}
	return _states[p.peer_id]

func _accept_pose(id: int, pose: Dictionary) -> bool:
	var p: ArrowPlayer = World.player_spawner.get_player(id)
	if not _valid_pose(p, pose):
		metrics.rejected += 1
		return false
	var s := _state(p)
	if pose.sequence <= s.sequence:
		return false
	s.sequence = pose.sequence
	s.aim = pose.aim
	s.level = pose.level
	s.facing = pose.facing
	s.source_time = pose.time
	if not p.is_multiplayer_authority():
		p.global_position = pose.position
		p.velocity = pose.velocity
	metrics.owner_samples += 1
	return true

func _apply_command(message: Dictionary) -> void:
	if not message.get("peer") is int or not message.get("id") is int or not message.get("kind") is int or not message.get("shot") is int or not message.get("pose") is Dictionary:
		return
	var p: ArrowPlayer = World.player_spawner.get_player(message.peer)
	if not _valid_pose(p, message.pose):
		return
	if World.round_manager.phase != RoundManager.Phase.PLAYING:
		_result(p, message.shot, "rejected", message.kind)
		return
	var s := _state(p)
	if message.id <= s.command:
		return
	s.command = message.id
	# Reliable actions must not be invalidated by a newer unreliable sample.
	# Their attached pose is used atomically; the next sample restores latest movement.
	var saved_position := p.global_position
	var pose: Dictionary = message.pose
	_accept_pose(p.peer_id, pose)
	if not p.is_multiplayer_authority():
		p.global_position = pose.position
	s.aim = pose.aim
	s.level = pose.level
	var accepted := true
	match message.kind:
		CHARGE:
			if s.shield > now():
				accepted = false
			elif s.charge < 0.0:
				s.charge = maxf(now(), s.cooldown)
		CANCEL:
			s.charge = -1.0
			if s.pending != 0:
				_result(p, s.pending, "rejected")
			s.pending = 0
		FIRE:
			if message.shot <= s.last_shot or s.charge < 0.0 or s.shield > now() or s.pending != 0:
				accepted = false
			else:
				s.last_shot = message.shot
				s.pending = message.shot
				_result(p, message.shot, "pending")
				_advance_combat(p)
		SHIELD:
			if now() < s.shield_ready or s.charge >= 0.0 or s.shield > now():
				accepted = false
			else:
				s.shield = now() + p.shield_duration
				s.shield_ready = s.shield + p.shield_cooldown
				s.cooldown = maxf(s.cooldown, s.shield + p.FIRE_COOLDOWN)
				p.set_server_shield(true, s.aim)
				queue_event({"kind": "shield", "peer": p.peer_id, "serial": p.spawn_serial, "active": true, "aim": s.aim})
		_:
			accepted = false
	if not accepted:
		_result(p, message.shot, "rejected", message.kind)
	if not p.is_multiplayer_authority() and pose.sequence < s.sequence:
		p.global_position = saved_position

func _advance_combat(p: ArrowPlayer) -> void:
	var s := _state(p)
	if p.is_dead or p.network_away or World.round_manager.phase != RoundManager.Phase.PLAYING:
		if s.pending != 0:
			_result(p, s.pending, "rejected")
		s.pending = 0
		s.charge = -1.0
		s.shield = 0.0
	if p.is_multiplayer_authority():
		s.aim = p.aim_reticle.direction.angle()
		s.level = p.selected_level
		s.facing = p.sprite.flip_h
	if s.shield > 0.0 and now() >= s.shield:
		s.shield = 0.0
		queue_event({"kind": "shield", "peer": p.peer_id, "serial": p.spawn_serial, "active": false, "aim": s.aim})
	p.set_server_shield(s.shield > now(), s.aim)
	if not p.is_multiplayer_authority():
		p.shield_cooldown_left = maxf(0.0, s.shield_ready - now())
		p.fire_cooldown_left = maxf(0.0, s.cooldown - now())
	if s.pending != 0 and now() >= s.cooldown and now() - s.charge >= p.minimum_preparation_time(s.level):
		var shot: int = s.pending
		s.pending = 0
		s.charge = -1.0
		s.cooldown = now() + p.FIRE_COOLDOWN
		p.server_fire(Vector2.from_angle(s.aim), s.level, p.minimum_preparation_time(s.level), shot)
		_result(p, shot, "accepted")

func _result(p: ArrowPlayer, shot: int, result: String, action: int = FIRE) -> void:
	queue_event({"kind": "result", "peer": p.peer_id, "serial": p.spawn_serial, "shot": shot, "result": result, "action": action})

func records() -> Array:
	var result: Array = []
	for p: ArrowPlayer in get_tree().get_nodes_in_group("players"):
		var s := _state(p)
		var flags := int(s.facing) | (int(s.charge >= 0.0) << 1) | (int(s.shield > now()) << 2) | (int(p.is_dead) << 3) | (int(p.network_away) << 4)
		result.append({"peer": p.peer_id, "serial": p.spawn_serial, "sequence": maxi(0, s.sequence),
			"position": p.global_position, "velocity": p.velocity, "aim": s.aim, "flags": flags,
			"level": s.level, "age": maxf(0.0, now() - s.source_time), "time": now()})
	return result

func queue_event(event: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	event_sequence += 1
	event.id = event_sequence
	event.time = now()
	event.tick = tick
	_events.append(event)

func _flush(publish: bool) -> void:
	if not _connected() or not multiplayer.is_server() or not World.level_loader.is_level_ready():
		return
	if not _events.is_empty():
		# Bound each reliable RPC; never retain an unbounded outgoing application queue.
		while not _events.is_empty():
			var batch: Array[Dictionary] = []
			for i in mini(16, _events.size()):
				batch.append(_events.pop_front())
			for id: int in _admitted:
				if multiplayer.get_peers().has(id) and _can_send(id, true):
					_receive_events.rpc_id(id, epoch, World.level_loader.revision, batch)
			_install_events(batch)
			metrics.events += batch.size()
	if not publish:
		return
	sequence += 1
	var state := records()
	var chunks := PlayerSnapshot.encode(epoch, World.level_loader.revision, sequence, tick, now(), state)
	for id: int in _admitted:
		if not multiplayer.get_peers().has(id) or not _can_send(id):
			continue
		for chunk in chunks:
			_receive_snapshot.rpc_id(id, chunk)
			metrics.snapshots += 1
			metrics.snapshot_bytes += chunk.size()
	for record: Dictionary in state:
		_present_record(record, sequence)

func _can_send(id: int, reliable_event := false) -> bool:
	var socket := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if socket == null:
		return true
	var amount := socket.get_peer(id).get_current_outbound_buffered_amount()
	if amount > 16384 and not _congested.has(id):
		_congested[id] = now()
	if amount < 4096:
		_congested.erase(id)
	if _congested.has(id) and now() - float(_congested[id]) > 5.0:
		if multiplayer.is_server():
			multiplayer.multiplayer_peer.disconnect_peer(id)
		else:
			multiplayer.multiplayer_peer.close()
		return false
	if reliable_event and amount >= 49152:
		# Never silently drop a reliable lifecycle event: force a fresh baseline on recovery.
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return false
	return reliable_event or not _congested.has(id)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_snapshot(bytes: PackedByteArray) -> void:
	var packet := PlayerSnapshot.decode(bytes)
	if packet.is_empty() or packet.epoch != epoch or packet.revision != World.level_loader.revision:
		return
	_last_snapshot = now()
	if packet.sequence > _last_delay_sample:
		_last_delay_sample = packet.sequence
		_ages.append(maxf(0.0, server_time() - packet.time))
		if _ages.size() > 64:
			_ages.pop_front()
		var sorted := _ages.duplicate()
		sorted.sort()
		var desired := clampf(sorted[int((sorted.size() - 1) * 0.95)] + 0.05, 0.075, 0.15)
		delay = desired if desired > delay else move_toward(delay, desired, 0.0005)
	for record: Dictionary in packet.records:
		_present_record(record, packet.sequence)

func _present_record(record: Dictionary, seq: int) -> void:
	var p: ArrowPlayer = World.player_spawner.get_player(record.peer)
	if p and p.spawn_serial == record.serial:
		p.receive_snapshot(record, seq)

@rpc("authority", "call_remote", "reliable")
func _receive_events(session: int, revision: int, events: Array) -> void:
	if session == epoch and revision == World.level_loader.revision:
		_install_events(events)

func _install_events(events: Array) -> void:
	for event: Dictionary in events:
		if int(event.id) <= _received_event:
			continue
		_received_event = event.id
		if MultiplayerService.is_dedicated_server():
			continue
		World.projectile_spawner.receive_event(event)
		_presentation_events.append(event)
	# One tick's events can be received in separate chunks, but reliable order is preserved.

@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: String, revision: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _rate_ok(id):
		return
	if protocol != PROTOCOL:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if revision != World.level_loader.revision or not World.level_loader.ready_peers.has(id):
		return
	_admitted[id] = true
	send_baseline(id)

func send_baseline(id: int) -> void:
	if not multiplayer.is_server() or not multiplayer.get_peers().has(id):
		return
	_admitted[id] = true
	_baseline.rpc_id(id, epoch, World.level_loader.revision, now(), sequence, event_sequence, records(), World.projectile_spawner.baseline(), World.projectile_spawner.arrow_travel_time_multiplier)

@rpc("authority", "call_remote", "reliable")
func _baseline(session: int, revision: int, stamp: float, seq: int, watermark: int, players: Array, arrows: Array, multiplier: float) -> void:
	if revision != World.level_loader.revision:
		return
	var first := epoch != session
	epoch = session
	if first:
		clock_offset = stamp - now()
		_target_offset = clock_offset
		render_time = stamp - delay
	_received_event = watermark
	_presentation_events.clear()
	_last_snapshot = now()
	World.projectile_spawner.arrow_travel_time_multiplier = multiplier
	World.projectile_spawner.install_baseline(arrows)
	for p: ArrowPlayer in get_tree().get_nodes_in_group("players"):
		p.presentation.clear()
	for record: Dictionary in players:
		_present_record(record, seq)

@rpc("any_peer", "call_remote", "unreliable", 2)
func _ping(stamp: float) -> void:
	if multiplayer.is_server() and _admitted.has(multiplayer.get_remote_sender_id()) and is_finite(stamp) and _rate_ok(multiplayer.get_remote_sender_id()):
		_pong.rpc_id(multiplayer.get_remote_sender_id(), stamp, now())

@rpc("authority", "call_remote", "unreliable", 2)
func _pong(sent: float, stamp: float) -> void:
	if not _pings.has(sent):
		return
	_pings.erase(sent)
	var rtt := now() - sent
	_clock_samples.append(Vector2(rtt, stamp - (now() + sent) * 0.5))
	if _clock_samples.size() > 32:
		_clock_samples.pop_front()
	var best := _clock_samples[0]
	for sample in _clock_samples:
		if sample.x < best.x:
			best = sample
	_target_offset = best.y
	_clock_count += 1
	if _clock_count == 1 or absf(_target_offset - clock_offset) > 0.5:
		clock_offset = _target_offset
		render_time = server_time() - delay
		request_baseline()
