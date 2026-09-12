extends Control

# NOTE: This is just a UI Scene. World handles adding / removing players and levels...
const GAMEPLAY_SCENE := "res://scenes/gameplay/ui/ui_layer.tscn"
const TIMEOUT_DUR := 10.0
var timeout_token := 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for type in MultiplayerService.BACKEND_LABELS:
		%ServiceOption.add_item(MultiplayerService.BACKEND_LABELS[type], type)
	%ServiceOption.select(%ServiceOption.get_item_index(MultiplayerService.backend_type))
	%ServiceOption.item_selected.connect(func(index: int) -> void: MultiplayerService.set_backend(%ServiceOption.get_item_id(index)))
	%StatusLabel.text = MultiplayerService.status_text
	MultiplayerService.status_changed.connect(func(text: String) -> void: %StatusLabel.text = text)
	MultiplayerService.creating_lobby.connect(_show_pending.bind("Hosting game..."))
	MultiplayerService.joining_lobby.connect(_show_pending.bind("Joining game..."))
	MultiplayerService.join_lobby_failed.connect(_show_failure)
	MultiplayerService.lobby_joined.connect(_on_lobby_joined)
	%HostButton.pressed.connect(func() -> void:
		%MainContainer.hide()
		%Help.hide()
		%HostPanel.open())
	%JoinButton.pressed.connect(func() -> void:
		%MainContainer.hide()
		%Help.hide()
		%JoinPanel.open())
	%HostPanel.closed.connect(_restore_main)
	%JoinPanel.closed.connect(_restore_main)
	%SettingsButton.pressed.connect(func() -> void: %SettingsMenu.show())
	%SettingsMenu.visibility_changed.connect(func() -> void:
		%MainContainer.visible = not %SettingsMenu.visible
		%Help.visible = not %SettingsMenu.visible
		if not %SettingsMenu.visible:
			%SettingsButton.grab_focus())
	%SettingsMenu.confirm_button_clicked.connect(func() -> void: %SettingsMenu.hide())
	%FailedButton.pressed.connect(func() -> void:
		%PendingOverlay.hide()
		_restore_main())
	%ExitButton.pressed.connect(_exit)
	if OS.has_feature("web"):
		%ExitButton.hide()
		%ServiceOption.item_selected.emit(%ServiceOption.get_item_index(MultiplayerService.BackendType.TUBE))
	%HostButton.grab_focus()
	if not MultiplayerService.kick_reason.is_empty():
		_show_failure(MultiplayerService.kick_reason)
		MultiplayerService.kick_reason = ""
	

func _restore_main() -> void:
	%MainContainer.show()
	%Help.show()
	%HostButton.grab_focus()

func _show_pending(text: String) -> void:
	timeout_token += 1
	var token := timeout_token
	%MainContainer.hide()
	%Help.hide()
	%PendingLabel.text = text
	%FailedLabel.hide()
	%FailedButton.hide()
	%PendingOverlay.show()
	%PendingOverlay.grab_focus()
	await get_tree().create_timer(TIMEOUT_DUR).timeout
	if token == timeout_token:
		MultiplayerService.leave_game()
		_show_failure("Timed out.")

func _show_failure(reason: String) -> void:
	timeout_token += 1
	%HostPanel.hide()
	%JoinPanel.hide()
	%MainContainer.hide()
	%Help.hide()
	%PendingLabel.text = "Unable to continue"
	%FailedLabel.text = reason
	%FailedLabel.show()
	%FailedButton.show()
	%PendingOverlay.show()
	%FailedButton.grab_focus()

func _on_lobby_joined() -> void:
	timeout_token += 1
	%PendingOverlay.hide()
	var destination := GAMEPLAY_SCENE 
	GGT.change_scene(destination, {"show_progress_bar": true})

func _exit() -> void:
	var transitions := get_node_or_null("/root/GGT_Transitions")
	if transitions:
		transitions.fade_in({"show_progress_bar": true})
		await transitions.anim.animation_finished
		await get_tree().create_timer(0.3).timeout
	get_tree().quit()
