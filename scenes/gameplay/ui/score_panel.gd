extends VBoxContainer
## Player-only K/D/A table, shown in the pause layer.
const ROW := preload("res://scenes/gameplay/ui/score_row.tscn")

func _ready() -> void:
	var header := $Scoreboard/Margin/Table/HeaderMargin/Header
	header.get_node("Name").text = "Player"
	header.get_node("Kills").text = "K"
	header.get_node("Deaths").text = "D"
	header.get_node("Assists").text = "A"
	World.scoreboard.changed.connect(_update_rows)
	MultiplayerService.username_changed.connect(func(_id: int) -> void: _update_rows())
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
