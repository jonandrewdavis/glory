class_name RoundManager
extends Node
## Host-authoritative round table. A round ends when either keep gate falls;
## the winner shows for BANNER_SECONDS, then the level reloads and every player
## is re-spawned. Scoreboard kills, deaths and assists are untouched.

signal changed
signal round_ended(winner: int)

enum Phase { PLAYING, ENDED }
const BANNER_SECONDS := 5.0

var wins: Dictionary = {Teams.Team.BLUE: 0, Teams.Team.ORANGE: 0}
var phase: Phase = Phase.PLAYING
var winner := -1
var round_number := 0
## Bumped on level clearing and clear(); cancels a pending restart.
var _generation := 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	# Sibling lookup: World's @onready vars are not assigned yet.
	var loader: LevelLoader = get_node("../LevelLoader")
	loader.level_loaded.connect(_on_level_loaded)
	loader.level_clearing.connect(_on_level_clearing)

func _on_peer_connected(peer_id: int) -> void:
	if MultiplayerService.is_host():
		_sync_round.rpc_id(peer_id, wins, phase, winner, round_number)

func _on_level_clearing() -> void:
	_generation += 1

## Host only. Every fresh level is a fresh round. Gates live inside the level
## scene, so they are wired here.
func _on_level_loaded() -> void:
	if not multiplayer.is_server():
		return
	for gate in get_tree().get_nodes_in_group("fortress_gates"):
		if gate is FortressGate:
			gate.health.died.connect(_on_gate_died.bind(gate))
	_sync_round.rpc(wins, Phase.PLAYING, -1, round_number + 1)
	# Also relocate existing players on a manually selected map change.
	respawn_all()

func _on_gate_died(_source: Node, gate: FortressGate) -> void:
	if not multiplayer.is_server() or phase != Phase.PLAYING:
		return
	var victor: int = Teams.Team.ORANGE if gate.team == Teams.Team.BLUE else Teams.Team.BLUE
	var next := wins.duplicate()
	next[victor] += 1
	_sync_round.rpc(next, Phase.ENDED, victor, round_number)
	_restart_after_banner()

func _restart_after_banner() -> void:
	var token := _generation
	var session: int = World.session
	await get_tree().create_timer(BANNER_SECONDS).timeout
	if token != _generation or session != World.session or not multiplayer.is_server() or phase != Phase.ENDED:
		return
	# The fresh level respawns everyone, which picks up the new teams.
	World.scoreboard.shuffle_teams()
	World.level_loader.spawn_level(World.level_loader.current_key)

## Host only. Full re-instance at the team spawn, as team switching does.
func respawn_all() -> void:
	var ids: Array[int] = []
	for player in World.player_spawner.get_children():
		if player is ArrowPlayer:
			ids.append(player.peer_id)
	for id in ids:
		World.player_spawner.replace_player(id)

func wins_for(team: int) -> int:
	return int(wins.get(team, 0))

func clear() -> void:
	_generation += 1
	wins = {Teams.Team.BLUE: 0, Teams.Team.ORANGE: 0}
	phase = Phase.PLAYING
	winner = -1
	round_number = 0
	changed.emit()

@rpc("authority", "call_local", "reliable")
func _sync_round(new_wins: Dictionary, new_phase: int, new_winner: int, number: int) -> void:
	wins = new_wins.duplicate()
	phase = new_phase as Phase
	winner = new_winner
	round_number = number
	changed.emit()
	if phase == Phase.ENDED:
		round_ended.emit(winner)
