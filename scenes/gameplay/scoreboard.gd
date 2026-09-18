class_name Scoreboard
extends Node
## Host-authoritative player K/D/A table, replicated to every peer.

signal changed
signal player_killed(event: Dictionary)

## peer_id (int) -> {team: int, kills: int, deaths: int, assists: int}
var entries: Dictionary = {}
var _event_id := 0
var _last_event_id := 0
const SWITCH_COOLDOWN := 60.0
var _switch_deadlines: Dictionary = {}
var local_switch_deadline := 0
var switch_message := ""

func switch_seconds_left() -> int:
	return maxi(0, ceili((local_switch_deadline - Time.get_ticks_msec()) / 1000.0))

func can_join(peer_id: int, target: int) -> bool:
	var current := get_team(peer_id)
	return Teams.are_enemies(current, target) and team_size(target) <= team_size(current)

func request_team(target: int) -> void:
	if multiplayer.is_server():
		_server_switch(multiplayer.get_unique_id(), target)
	else:
		_request_team.rpc_id(1, target)

@rpc("any_peer", "call_remote", "reliable")
func _request_team(target: int) -> void:
	if multiplayer.is_server():
		_server_switch(multiplayer.get_remote_sender_id(), target)

func _server_switch(peer_id: int, target: int) -> void:
	if not multiplayer.is_server() or not entries.has(peer_id):
		return
	if MultiplayerService.presence.is_peer_away(peer_id):
		return
	var remaining := maxi(0, int(_switch_deadlines.get(peer_id, 0)) - Time.get_ticks_msec())
	if remaining > 0:
		_switch_result.rpc_id(peer_id, "Please wait before changing teams.", remaining)
		return
	if not can_join(peer_id, target):
		_switch_result.rpc_id(peer_id, "You cannot join the larger team.", 0)
		return
	var player: ArrowPlayer = World.player_spawner.get_player(peer_id)
	if player == null:
		return
	if not player.health.is_alive():
		_switch_result.rpc_id(peer_id, "You can change teams after respawning.", 0)
		return
	_switch_deadlines[peer_id] = Time.get_ticks_msec() + int(SWITCH_COOLDOWN * 1000)
	var entry: Dictionary = entries[peer_id].duplicate()
	entry.team = target
	_forget_attacker(peer_id)
	_sync_entry.rpc(peer_id, entry)
	World.projectile_spawner.remove_owned_projectiles(peer_id)
	World.player_spawner.replace_player(peer_id)
	_switch_result.rpc_id(peer_id, "Team changed.", int(SWITCH_COOLDOWN * 1000))

@rpc("authority", "call_local", "reliable")
func _switch_result(message: String, remaining_msec: int) -> void:
	switch_message = message
	local_switch_deadline = Time.get_ticks_msec() + remaining_msec
	changed.emit()

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(peer_id: int) -> void:
	if MultiplayerService.is_host() and not entries.is_empty():
		_sync_all.rpc_id(peer_id, entries)

# --- Host API -------------------------------------------------------------

func assign_team(peer_id: int) -> int:
	if entries.has(peer_id):
		return entries[peer_id].team
	var team: int = Teams.Team.BLUE
	if team_size(Teams.Team.ORANGE) < team_size(Teams.Team.BLUE):
		team = Teams.Team.ORANGE
	_sync_entry.rpc(peer_id, {"team": team, "kills": 0, "deaths": 0, "assists": 0})
	return team

func record_kill(killer_id: int, victim_id: int, assist_ids: Array[int] = []) -> void:
	if not multiplayer.is_server() or not entries.has(victim_id):
		return
	var updates: Dictionary = {}
	var victim: Dictionary = entries[victim_id].duplicate()
	victim.deaths += 1
	updates[victim_id] = victim
	var event: Dictionary = {}
	if Teams.are_enemies(get_team(killer_id), get_team(victim_id)):
		var killer: Dictionary = entries[killer_id].duplicate()
		killer.kills += 1
		updates[killer_id] = killer
		var awarded := 0
		for id in assist_ids:
			if awarded == 2:
				break
			if updates.has(id) or not Teams.are_enemies(get_team(id), get_team(victim_id)):
				continue
			var assistant_entry: Dictionary = entries[id].duplicate()
			assistant_entry.assists = int(assistant_entry.get("assists", 0)) + 1
			updates[id] = assistant_entry
			awarded += 1
		_event_id += 1
		event = {"id": _event_id, "killer_id": killer_id, "victim_id": victim_id,
			"killer_name": MultiplayerService.get_username(killer_id),
			"victim_name": MultiplayerService.get_username(victim_id), "team": get_team(killer_id)}
	_sync_combat.rpc(updates, event)

func _forget_attacker(peer_id: int) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		if player is ArrowPlayer:
			player.recent_attackers.erase(peer_id)

func remove_player(peer_id: int) -> void:
	_forget_attacker(peer_id)
	_switch_deadlines.erase(peer_id)
	if entries.has(peer_id):
		_erase_entry.rpc(peer_id)

func reassign_player(old_id: int, new_id: int) -> void:
	if entries.has(old_id):
		var entry: Dictionary = entries[old_id].duplicate()
		_erase_entry.rpc(old_id)
		_sync_entry.rpc(new_id, entry)
	if _switch_deadlines.has(old_id):
		_switch_deadlines[new_id] = _switch_deadlines[old_id]
		_switch_deadlines.erase(old_id)
	for player in get_tree().get_nodes_in_group("players"):
		if player is ArrowPlayer:
			var index: int = player.recent_attackers.find(old_id)
			if index >= 0:
				player.recent_attackers[index] = new_id

# --- Read API -------------------------------------------------------------

func get_team(peer_id: int) -> int:
	return entries[peer_id].team if entries.has(peer_id) else -1

func team_size(team: int) -> int:
	var n := 0
	for entry in entries.values():
		if entry.team == team:
			n += 1
	return n

func clear() -> void:
	_event_id = 0
	_last_event_id = 0
	_switch_deadlines.clear()
	local_switch_deadline = 0
	switch_message = ""
	entries.clear()
	changed.emit()

# --- RPCs (authority = host) ---------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_combat(updates: Dictionary, event: Dictionary) -> void:
	for id in updates:
		entries[id] = updates[id]
	changed.emit()
	if not event.is_empty() and int(event.id) > _last_event_id:
		_last_event_id = int(event.id)
		player_killed.emit(event)

@rpc("authority", "call_local", "reliable")
func _sync_entry(peer_id: int, entry: Dictionary) -> void:
	entries[peer_id] = entry
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_all(all_entries: Dictionary) -> void:
	entries = all_entries.duplicate()
	changed.emit()

@rpc("authority", "call_local", "reliable")
func _erase_entry(peer_id: int) -> void:
	entries.erase(peer_id)
	changed.emit()
