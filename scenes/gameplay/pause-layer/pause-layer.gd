extends CanvasLayer

const PLAYER_ITEM := preload("res://scenes/gameplay/pause-layer/player_list_item.tscn")
var players: Dictionary = {}

func _ready() -> void:
	hide()
	%ResumeButton.pressed.connect(resume)
	%SettingsButton.pressed.connect(func() -> void: %SettingsMenu.show())
	%LeaveButton.pressed.connect(MultiplayerService.leave_game)
	%LoadLevelButton.pressed.connect(_load_level)
	%SettingsMenu.visibility_changed.connect(func() -> void:
		%PauseRoot.visible = not %SettingsMenu.visible
		if not %SettingsMenu.visible:
			%ResumeButton.grab_focus())
	%SettingsMenu.confirm_button_clicked.connect(func() -> void: %SettingsMenu.hide())
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	_add_player(multiplayer.get_unique_id())
	for peer_id in multiplayer.get_peers():
		_add_player(peer_id)
	%HostPanel.visible = MultiplayerService.is_host()
	if MultiplayerService.is_host():
		for key in LevelLoader.LEVEL_DICT:
			%LevelOption.add_item(key)
		%LobbyAddressLabel.text = "Address: " + MultiplayerService.get_lobby_address()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _add_player(peer_id: int) -> void:
	if players.has(peer_id):
		return
	var item := PLAYER_ITEM.instantiate()
	item.peer_id = peer_id
	%PlayerList.add_child(item)
	players[peer_id] = item

func _remove_player(peer_id: int) -> void:
	if players.has(peer_id):
		var item: Node = players[peer_id]
		%PlayerList.remove_child(item)
		item.queue_free()
		players.erase(peer_id)

func _load_level() -> void:
	World.change_level(%LevelOption.get_item_text(%LevelOption.selected))
