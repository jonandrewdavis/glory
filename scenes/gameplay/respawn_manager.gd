class_name RespawnManager
extends Node
## All deadlines, ownership decisions and spawn choices are server-owned.

signal changed
@export var settings: RespawnSettings = preload("res://scenes/gameplay/respawn_settings.tres")
var bands: Array[SpawnBand] = []
var owners: Dictionary = {}
var pending: Dictionary = {}
var _client_waits: Dictionary = {}
var _rotations: Dictionary = {}
var _ram: BatteringRam
var _broadcast_left := 0.0
var _warned_empty: Dictionary = {}
var _thresholds: Dictionary = {}

func _ready() -> void:
	var loader: LevelLoader = get_node("../LevelLoader")
	loader.level_loaded.connect(_on_level_loaded)
	loader.level_clearing.connect(clear)
	loader.peer_level_ready.connect(_send_snapshot)
	get_node("../RoundManager").round_ended.connect(_on_round_ended)

func clear() -> void:
	if is_instance_valid(_ram) and _ram.route_advanced.is_connected(_on_route_advanced):
		_ram.route_advanced.disconnect(_on_route_advanced)
	_ram = null
	bands.clear()
	owners.clear()
	pending.clear()
	_client_waits.clear()
	_rotations.clear()
	_warned_empty.clear()
	_thresholds.clear()
	changed.emit()

func _on_level_loaded() -> void:
	for node in get_tree().get_nodes_in_group("spawn_bands"):
		if node is SpawnBand and World.level_loader.is_ancestor_of(node):
			bands.append(node)
	bands.sort_custom(func(a: SpawnBand, b: SpawnBand) -> bool: return a.order < b.order)
	for band in bands:
		owners[band.band_id] = band.initial_owner
		for warning in band._get_configuration_warnings():
			push_warning("Spawn band %s: %s" % [band.band_id, warning])
	for node in get_tree().get_nodes_in_group("fortress_rams"):
		if World.level_loader.is_ancestor_of(node):
			_ram = node as BatteringRam
			break
	if multiplayer.is_server():
		if _ram:
			_ram.route_advanced.connect(_on_route_advanced)
			for band in bands:
				_thresholds[band.band_id] = {
					Teams.Team.BLUE: band.capture_distance(_ram, Teams.Team.BLUE),
					Teams.Team.ORANGE: band.capture_distance(_ram, Teams.Team.ORANGE),
				}
			_validate_milestones()
	_refresh_bands()

func _validate_milestones() -> void:
	for band in bands:
		var marks: Dictionary = _thresholds[band.band_id]
		if not band.permanent and marks[Teams.Team.ORANGE] >= marks[Teams.Team.BLUE]:
			push_warning("Spawn band %s: the Orange milestone must come before the Blue milestone on the ram route." % band.band_id)
	if owners_at(_ram.distance) != owners:
		push_warning("Spawn band initial owners disagree with the ram's starting position; they change on its first move.")
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var fortresses := bands.filter(func(band: SpawnBand) -> bool: return band.permanent and band.initial_owner == team)
		if not bands.is_empty() and fortresses.is_empty():
			push_warning("Every team needs a permanent fortress spawn band: %s has none." % Teams.team_name(team))
		var previous := -INF if team == Teams.Team.BLUE else INF
		var ordered := bands.duplicate()
		if team == Teams.Team.ORANGE:
			ordered.reverse()
		for band: SpawnBand in ordered:
			if band.permanent:
				continue
			var distance: float = _thresholds[band.band_id][team]
			var marker := band.get_node_or_null("BlueCapture" if team == Teams.Team.BLUE else "OrangeCapture") as Marker2D
			if marker and marker.global_position.distance_to(_ram.route_position_at(maxf(0, distance))) > 16:
				push_warning("Spawn band %s capture marker is more than 16 pixels from the ram route." % band.band_id)
			if distance < 0 or (team == Teams.Team.BLUE and distance <= previous) or (team == Teams.Team.ORANGE and distance >= previous):
				push_warning("Spawn band %s has missing or unordered capture milestones for %s." % [band.band_id, Teams.team_name(team)])
			previous = distance

func active_band(team: int) -> SpawnBand:
	var result: SpawnBand
	for band in bands:
		if int(owners.get(band.band_id, SpawnBand.NEUTRAL)) == team:
			if result == null or team == Teams.Team.BLUE:
				result = band
	return result

func _refresh_bands() -> void:
	var blue := active_band(Teams.Team.BLUE)
	var orange := active_band(Teams.Team.ORANGE)
	for band in bands:
		band.set_control(int(owners.get(band.band_id, SpawnBand.NEUTRAL)), band == blue or band == orange)
	changed.emit()

func _on_route_advanced(previous: float, current: float, _direction: int) -> void:
	if not multiplayer.is_server() or World.round_manager.phase != RoundManager.Phase.PLAYING or previous == current:
		return
	var next := owners_at(current)
	if next != owners:
		owners = next
		_refresh_bands()
		_broadcast()

## Ownership is a pure function of where the ram stands: each team holds the
## unbroken run of bands outward from its fortress whose milestones the ram is
## at or past. Runs stop at the first band not held, so teams never interleave.
func owners_at(distance: float) -> Dictionary:
	var result := {}
	for band in bands:
		result[band.band_id] = SpawnBand.NEUTRAL
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var ordered := bands.duplicate()
		if team == Teams.Team.ORANGE:
			ordered.reverse()
		for band: SpawnBand in ordered:
			if not _holds(band, team, distance):
				break
			result[band.band_id] = team
	return result

func _holds(band: SpawnBand, team: int, distance: float) -> bool:
	if band.permanent:
		return band.initial_owner == team
	var mark: float = _thresholds[band.band_id][team]
	return mark >= 0.0 and (distance >= mark if team == Teams.Team.BLUE else distance <= mark)

func schedule(player: ArrowPlayer) -> void:
	if not multiplayer.is_server() or player.health.is_alive() or World.round_manager.phase != RoundManager.Phase.PLAYING or pending.has(player.peer_id):
		return
	pending[player.peer_id] = {"player": player, "remaining": settings.delay_for_population(World.scoreboard.team_size(player.team))}
	_broadcast()

func cancel(peer_id: int) -> void:
	pending.erase(peer_id)
	_client_waits.erase(peer_id)

func seconds_left(peer_id: int) -> float:
	if multiplayer.is_server():
		return float(pending[peer_id].remaining) if pending.has(peer_id) else 0.0
	var state: Dictionary = _client_waits.get(peer_id, {})
	var player: ArrowPlayer = World.player_spawner.get_player(peer_id)
	if player == null or state.get("life", -1) != player.spawn_serial:
		return 0.0
	return maxf(0.0, float(state.get("remaining", 0.0)))

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		for state: Dictionary in _client_waits.values():
			state.remaining = maxf(0, float(state.remaining) - delta)
		return
	if not World.level_loader.is_level_ready() or World.round_manager.phase != RoundManager.Phase.PLAYING:
		return
	for id in pending.keys():
		var entry: Dictionary = pending[id]
		var player = entry.player
		if not is_instance_valid(player) or World.player_spawner.get_player(id) != player or player.health.is_alive():
			pending.erase(id)
			continue
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			pending.erase(id)
			World.player_spawner.replace_player(id)
	_broadcast_left -= delta
	if _broadcast_left <= 0:
		_broadcast_left = 0.25
		_broadcast()

func _on_round_ended(_winner: int) -> void:
	pending.clear()
	_client_waits.clear()
	if multiplayer.is_server():
		_broadcast()

func spawn_position(team: int, index: int = 0) -> Vector2:
	if bands.is_empty():
		return Teams.spawn_position(get_tree(), team, index)
	var ordered := bands.duplicate()
	if team == Teams.Team.BLUE:
		ordered.reverse()
	for band: SpawnBand in ordered:
		if owners.get(band.band_id) != team:
			continue
		var candidates: Array[Vector2] = []
		var best_distance := -1.0
		for marker in band.spawn_markers():
			var point := marker.global_position
			if not _point_clear(point):
				continue
			var enemy_distance := INF
			for enemy in get_tree().get_nodes_in_group("players"):
				if enemy is ArrowPlayer and enemy.health.is_alive() and Teams.are_enemies(team, enemy.team):
					enemy_distance = minf(enemy_distance, point.distance_squared_to(enemy.global_position))
			if enemy_distance > best_distance:
				best_distance = enemy_distance
				candidates.clear()
			if enemy_distance == best_distance:
				candidates.append(point)
		if not candidates.is_empty():
			var next := int(_rotations.get(band.band_id, 0))
			_rotations[band.band_id] = next + 1
			return candidates[next % candidates.size()]
		if not _warned_empty.has(band.band_id):
			push_warning("Spawn band %s has no clear points; falling back toward the fortress." % band.band_id)
			_warned_empty[band.band_id] = true
	# Invalid map configuration: use its legacy points instead of an infinite queue.
	return Teams.spawn_position(get_tree(), team, index)

func _point_clear(point: Vector2) -> bool:
	var shape := CapsuleShape2D.new()
	shape.radius = 7.2
	shape.height = 19.2
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 33 # Same terrain and platform layers as the archer.
	return get_viewport().world_2d.direct_space_state.intersect_shape(query, 1).is_empty()

func _wait_snapshot() -> Dictionary:
	var waits := {}
	for id in pending:
		var player = pending[id].player
		if is_instance_valid(player):
			waits[id] = {"life": player.spawn_serial, "remaining": maxf(0, pending[id].remaining)}
	return waits

func _broadcast() -> void:
	changed.emit()
	if not multiplayer.is_server():
		return
	for id in World.level_loader.ready_peers:
		_send_snapshot(id)

func _send_snapshot(id: int) -> void:
	if multiplayer.is_server() and World.level_loader.is_level_ready():
		_sync_state.rpc_id(id, World.level_loader.revision, owners, _wait_snapshot())

@rpc("authority", "call_remote", "reliable")
func _sync_state(revision: int, new_owners: Dictionary, waits: Dictionary) -> void:
	if revision != World.level_loader.revision or not World.level_loader.is_level_ready():
		return
	owners = new_owners.duplicate()
	_client_waits = waits.duplicate(true)
	_refresh_bands()
