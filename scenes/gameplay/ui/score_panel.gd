extends VBoxContainer
## Player-only K/D/A table, shown in the pause layer. Hosts also get kick/ban per row.
const ROW := preload("res://scenes/gameplay/ui/score_row.tscn")

func _ready() -> void:
	var header := $Scoreboard/Margin/Table/HeaderMargin/Header
	header.get_node("Name").text = "Player"
	header.get_node("Kills").text = "K"
	header.get_node("Deaths").text = "D"
	header.get_node("Assists").text = "A"
	_add_moderation(header, 0)
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
	var viewer := board.get_team(multiplayer.get_unique_id())
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
		heading.text = Teams.display_name(team, viewer)
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
			_add_moderation(row, id)

## Hosts get KICK/BAN on other players' rows; invisible copies elsewhere keep the columns aligned.
func _add_moderation(row: Control, id: int) -> void:
	if not MultiplayerService.is_host():
		return
	var active := id != 0 and id != multiplayer.get_unique_id()
	for action in [["KICK", MultiplayerService.kick_player], ["BAN", MultiplayerService.ban_player]]:
		var button := Button.new()
		button.text = action[0]
		if active:
			button.pressed.connect(action[1].bind(id))
		else:
			button.disabled = true
			button.modulate.a = 0.0
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(button)
