class_name RoundHud
extends Control
## Top-centre siege readout: gate health bars, round score, ram track, winner banner.

const BAR_SIZE := Vector2(220, 12)
## Half-width of the centre gap that holds the round score.
const GAP := 40.0
const TOP := 16.0
const TRACK_HEIGHT := 5.0
const FONT_SIZE := 11
const BACKING := Color(0.05, 0.06, 0.08, 0.85)
const OUTLINE := Color(0.03, 0.05, 0.09)

@onready var score_label: Label = %RoundScoreLabel
@onready var banner_label: Label = %WinnerLabel

func _ready() -> void:
	World.round_manager.changed.connect(update_labels)
	# The viewer's team decides friendly versus enemy display names.
	World.scoreboard.changed.connect(update_labels)
	update_labels()

func _process(_delta: float) -> void:
	queue_redraw()

func gate(team: int) -> FortressGate:
	for node in get_tree().get_nodes_in_group("fortress_gates"):
		if node is FortressGate and node.team == team:
			return node
	return null

func ram() -> BatteringRam:
	var rams := get_tree().get_nodes_in_group("fortress_rams")
	return rams[0] as BatteringRam if not rams.is_empty() else null

func update_labels() -> void:
	var rounds: RoundManager = World.round_manager
	var viewer: int = World.scoreboard.get_team(multiplayer.get_unique_id())
	score_label.text = "%s %d - %d %s" % [
		Teams.display_name(Teams.Team.BLUE, viewer), rounds.wins_for(Teams.Team.BLUE),
		rounds.wins_for(Teams.Team.ORANGE), Teams.display_name(Teams.Team.ORANGE, viewer)]
	banner_label.visible = rounds.phase == RoundManager.Phase.ENDED and rounds.winner >= 0
	if banner_label.visible:
		banner_label.text = "%s wins the round!" % Teams.display_name(rounds.winner, viewer)
		banner_label.modulate = Teams.color(rounds.winner)

func _draw() -> void:
	var cx := size.x * 0.5
	var font := ThemeDB.fallback_font
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var x := cx - GAP - BAR_SIZE.x if team == Teams.Team.BLUE else cx + GAP
		var rect := Rect2(Vector2(x, TOP), BAR_SIZE)
		var g := gate(team)
		var ratio := g.health.ratio() if g else 0.0
		draw_rect(rect, BACKING)
		if ratio > 0.0:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), Teams.color(team))
		draw_rect(rect, Color(0.85, 0.9, 0.95, 0.6), false, 1.0)
		var text := "%d / %d" % [ceili(g.health.current), int(g.health.max_value)] if g else "-"
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var pos := rect.position + Vector2((rect.size.x - width) * 0.5, rect.size.y - 2)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 2, OUTLINE)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)
	# Ram track: blue gate at the left end, orange gate at the right end.
	var track := Rect2(Vector2(cx - GAP - BAR_SIZE.x, TOP + BAR_SIZE.y + 6), Vector2(2.0 * (GAP + BAR_SIZE.x), TRACK_HEIGHT))
	draw_rect(track, BACKING)
	var r := ram()
	if r == null:
		return
	var p := r.progress()
	var mid := track.position.x + track.size.x * 0.5
	var x := track.position.x + track.size.x * p
	var pushed_by: int = Teams.Team.BLUE if p >= 0.5 else Teams.Team.ORANGE
	draw_rect(Rect2(Vector2(minf(mid, x), track.position.y), Vector2(absf(x - mid), track.size.y)), Teams.color(pushed_by))
	var pusher := Color.GRAY
	if r.direction != 0:
		pusher = Teams.color(Teams.Team.BLUE if r.direction > 0 else Teams.Team.ORANGE)
	draw_rect(Rect2(Vector2(x - 2, track.position.y - 2), Vector2(4, track.size.y + 4)), pusher)
