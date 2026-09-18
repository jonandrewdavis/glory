class_name RoundHud
extends Control
## Node-based siege HUD. Round score and respawn UI remain intentionally hidden.
@onready var score_label: Label = %RoundScoreLabel
@onready var banner_label: Label = %WinnerLabel
var _gates: Dictionary = {}
var _ram: BatteringRam

func _ready() -> void:
	World.round_manager.changed.connect(update_labels)
	World.scoreboard.changed.connect(update_labels)
	World.level_loader.level_loaded.connect(_bind_level)
	World.level_loader.level_clearing.connect(_unbind_level)
	resized.connect(_layout_siege)
	_layout_siege()
	_bind_level()
	update_labels()

func _layout_siege() -> void:
	# Reserve space for the right-hand scoreboard at the largest HUD scale.
	var width := clampf(size.x - 720, 220, 520)
	$Siege.offset_left = -width * 0.5
	$Siege.offset_right = width * 0.5

func gate(team: int) -> FortressGate:
	return _gates.get(team) as FortressGate

func ram() -> BatteringRam:
	return _ram if is_instance_valid(_ram) else null

func _unbind_level() -> void:
	for g: FortressGate in _gates.values():
		if is_instance_valid(g) and g.health.changed.is_connected(_update_gates):
			g.health.changed.disconnect(_update_gates)
	_gates.clear()
	_ram = null
	_update_gates()
	$Siege/Track/Fill.hide()
	$Siege/Track/Marker.hide()

func _bind_level() -> void:
	_unbind_level()
	for node in get_tree().get_nodes_in_group("fortress_gates"):
		if node is FortressGate:
			_gates[node.team] = node
			node.health.changed.connect(_update_gates)
	var rams := get_tree().get_nodes_in_group("fortress_rams")
	_ram = rams[0] as BatteringRam if not rams.is_empty() else null
	_update_gates()

func _update_gates(_current: float = 0, _maximum: float = 0) -> void:
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var bar: ProgressBar = $Siege/Gates/Blue if team == Teams.Team.BLUE else $Siege/Gates/Orange
		var g := gate(team)
		bar.value = g.health.ratio() if is_instance_valid(g) else 0.0
		bar.self_modulate = Teams.color(team)
		bar.get_node("Value").text = "%d / %d" % [ceili(g.health.current), int(g.health.max_value)] if is_instance_valid(g) else "-"

func _process(_delta: float) -> void:
	var r := ram()
	if r == null:
		return
	var track: Control = $Siege/Track
	var p := r.progress()
	var mid := track.size.x * 0.5
	var x := track.size.x * p
	$Siege/Track/Fill.show()
	$Siege/Track/Marker.show()
	$Siege/Track/Fill.position.x = minf(mid, x)
	$Siege/Track/Fill.size.x = absf(x - mid)
	$Siege/Track/Fill.color = Teams.color(Teams.Team.BLUE if p >= 0.5 else Teams.Team.ORANGE)
	$Siege/Track/Marker.position.x = x - 2
	$Siege/Track/Marker.color = Color.GRAY if r.direction == 0 else Teams.color(Teams.Team.BLUE if r.direction > 0 else Teams.Team.ORANGE)

func update_labels() -> void:
	var rounds := World.round_manager
	var viewer := World.scoreboard.get_team(multiplayer.get_unique_id())
	score_label.text = "%s %d - %d %s" % [
		Teams.display_name(Teams.Team.BLUE, viewer), rounds.wins_for(Teams.Team.BLUE),
		rounds.wins_for(Teams.Team.ORANGE), Teams.display_name(Teams.Team.ORANGE, viewer)]
	banner_label.visible = rounds.phase == RoundManager.Phase.ENDED and rounds.winner >= 0
	if banner_label.visible:
		banner_label.text = "%s wins the round!" % Teams.display_name(rounds.winner, viewer)
		banner_label.modulate = Teams.color(rounds.winner)
