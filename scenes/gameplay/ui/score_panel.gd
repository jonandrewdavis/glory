extends VBoxContainer
## Player-only K/D/A and an ephemeral, server-authored kill feed.
const ROW := preload("res://scenes/gameplay/ui/score_row.tscn")
const FEED_LIMIT := 5
const FEED_SECONDS := 8.0

var _feed: Array[Dictionary] = []

func _ready() -> void:
	var header := $Scoreboard/Margin/Table/HeaderMargin/Header
	header.get_node("Name").text = "Player"
	header.get_node("Kills").text = "K"
	header.get_node("Deaths").text = "D"
	header.get_node("Assists").text = "A"
	World.scoreboard.changed.connect(_update_rows)
	World.scoreboard.player_killed.connect(_on_player_killed)
	MultiplayerService.username_changed.connect(func(_id: int) -> void: _update_rows())
	World.level_loader.level_clearing.connect(_clear_feed)
	MultiplayerService.game_exited.connect(_clear_feed)
	%Rows.resized.connect(_align_header)
	%Scroll.resized.connect(_align_header)
	_update_rows()

func _align_header() -> void:
	$Scoreboard/Margin/Table/HeaderMargin.add_theme_constant_override("margin_right", maxi(0, roundi(%Scroll.size.x - %Rows.size.x)))

func _update_rows() -> void:
	for child in %Rows.get_children():
		%Rows.remove_child(child)
		child.queue_free()
	var board := World.scoreboard
	var ids := board.entries.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var first: Dictionary = board.entries[a]
		var second: Dictionary = board.entries[b]
		for key in ["kills", "assists", "deaths"]:
			var x := int(first.get(key, 0))
			var y := int(second.get(key, 0))
			if x != y:
				return x < y if key == "deaths" else x > y
		return a < b)
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var heading := Label.new()
		heading.text = Teams.team_name(team)
		heading.modulate = Teams.color(team)
		%Rows.add_child(heading)
		for id: int in ids:
			var entry: Dictionary = board.entries[id]
			if entry.team != team:
				continue
			var row := ROW.instantiate()
			%Rows.add_child(row)
			var username := MultiplayerService.get_username(id)
			row.get_node("Name").text = ("• " if id == multiplayer.get_unique_id() else "") + username
			row.get_node("Name").tooltip_text = username
			row.get_node("Name").modulate = Teams.color(team)
			row.get_node("Kills").text = str(entry.kills)
			row.get_node("Deaths").text = str(entry.deaths)
			row.get_node("Assists").text = str(entry.get("assists", 0))
	%Scroll.custom_minimum_size.y = minf(260, 52 + ids.size() * 25)
	if board.entries.is_empty():
		_clear_feed()

func _on_player_killed(event: Dictionary) -> void:
	var line := Label.new()
	line.text = "%s killed %s" % [event.killer_name, event.victim_name]
	line.modulate = Teams.color(int(event.team))
	line.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.06))
	line.add_theme_constant_override("outline_size", 3)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%KillFeed.add_child(line)
	%KillFeed.move_child(line, 0)
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
