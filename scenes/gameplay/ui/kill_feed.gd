extends VBoxContainer
## Ephemeral, server-authored kill feed.
const FEED_LIMIT := 5
const FEED_SECONDS := 8.0

var _feed: Array[Dictionary] = []

func _ready() -> void:
	World.scoreboard.player_killed.connect(_on_player_killed)
	World.scoreboard.changed.connect(func() -> void:
		if World.scoreboard.entries.is_empty():
			_clear_feed())
	World.level_loader.level_clearing.connect(_clear_feed)
	MultiplayerService.game_exited.connect(_clear_feed)

func _on_player_killed(event: Dictionary) -> void:
	var line := Label.new()
	line.text = "%s killed %s" % [event.killer_name, event.victim_name]
	if event.get("reflected", false):
		line.text += " (reflected)"
	line.modulate = Teams.color(int(event.team))
	line.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.06))
	line.add_theme_constant_override("outline_size", 3)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	move_child(line, 0)
	_feed.push_front({"line": line, "remaining": FEED_SECONDS})
	if _feed.size() > FEED_LIMIT:
		var oldest: Dictionary = _feed.pop_back()
		oldest.line.queue_free()

func _process(delta: float) -> void:
	for i in range(_feed.size() - 1, -1, -1):
		_feed[i].remaining -= delta
		var line: Label = _feed[i].line
		line.modulate.a = clampf(_feed[i].remaining, 0.0, 1.0)
		if _feed[i].remaining <= 0:
			line.queue_free()
			_feed.remove_at(i)

func _clear_feed() -> void:
	for entry in _feed:
		entry.line.queue_free()
	_feed.clear()
