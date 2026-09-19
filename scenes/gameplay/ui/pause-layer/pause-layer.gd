extends CanvasLayer

var players: Dictionary = {}
var team_buttons: Array[Button] = []
var team_status: Label

func _ready() -> void:
	hide()
	var box := %ResumeButton.get_parent()
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var button := Button.new()
		box.add_child(button)
		button.pressed.connect(func() -> void: World.scoreboard.request_team(team))
		team_buttons.append(button)
	team_status = Label.new()
	team_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(team_status)
	_update_teams()
	%ResumeButton.pressed.connect(resume)
	%SettingsButton.pressed.connect(func() -> void: %SettingsMenu.show())
	%LeaveButton.pressed.connect(MultiplayerService.leave_game)
	%LoadLevelButton.pressed.connect(_load_level)
	%SettingsMenu.visibility_changed.connect(func() -> void:
		%PauseRoot.visible = not %SettingsMenu.visible
		if not %SettingsMenu.visible:
			%ResumeButton.grab_focus())
	%SettingsMenu.confirm_button_clicked.connect(func() -> void: %SettingsMenu.hide())
	%HostPanel.visible = MultiplayerService.is_host()
	if MultiplayerService.is_host():
		for key in LevelLoader.LEVEL_DICT:
			%LevelOption.add_item(key)
		%LobbyAddressLabel.text = "Address: " + MultiplayerService.get_lobby_address()

	#multiplayer.peer_connected.connect(_add_player)
	#multiplayer.peer_disconnected.connect(_remove_player)
	#_add_player(multiplayer.get_unique_id())
	#for peer_id in multiplayer.get_peers():
		#_add_player(peer_id)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_toggle()

func _process(_delta: float) -> void:
	if visible:
		_update_teams()

func _update_teams() -> void:
	var board := World.scoreboard
	var peer_id := multiplayer.get_unique_id()
	var viewer := board.get_team(peer_id)
	var remaining := board.switch_seconds_left()
	for team in [Teams.Team.BLUE, Teams.Team.ORANGE]:
		var button := team_buttons[team]
		button.text = "%s %s (%d)" % ["On" if viewer == team else "Join", Teams.display_name(team, viewer), board.team_size(team)]
		button.modulate = Teams.color(team)
		button.disabled = remaining > 0 or not board.can_join(peer_id, team)
	team_status.text = "Switch available in %ds" % remaining if remaining > 0 else board.switch_message

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_toggle()

func _toggle() -> void:
	if GGT.is_changing_scene() or not MultiplayerService.in_lobby:
		return
	if %SettingsMenu.visible:
		%SettingsMenu.hide()
	elif visible:
		resume()
	else:
		show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		%ResumeButton.grab_focus()

func resume() -> void:
	%SettingsMenu.hide()
	hide()
	World.ui_layer.capture_player_mouse()

#func _add_player(peer_id: int) -> void:
	#if players.has(peer_id):
		#return
	#var item := PLAYER_ITEM.instantiate()
	#item.peer_id = peer_id
	#%PlayerList.add_child(item)
	#players[peer_id] = item

#func _remove_player(peer_id: int) -> void:
	#if players.has(peer_id):
		#var item: Node = players[peer_id]
		#%PlayerList.remove_child(item)
		#item.queue_free()
		#players.erase(peer_id)

func _load_level() -> void:
	World.change_level(%LevelOption.get_item_text(%LevelOption.selected))
