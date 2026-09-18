extends Control

# NOTE: This is just a UI Scene. World handles adding / removing players and levels...
const GAMEPLAY_SCENE := "res://scenes/gameplay/ui/ui_layer.tscn"
const TIMEOUT_DUR := 10.0
var timeout_token := 0
var matchmaker: Matchmaker

func _ready() -> void:
	if MultiplayerService.is_dedicated_server():
		hide()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for type in MultiplayerService.BACKEND_LABELS:
		%ServiceOption.add_item(MultiplayerService.BACKEND_LABELS[type], type)
	%ServiceOption.select(%ServiceOption.get_item_index(MultiplayerService.backend_type))
	%ServiceOption.item_selected.connect(func(index: int) -> void: MultiplayerService.set_backend(%ServiceOption.get_item_id(index)))
	MultiplayerService.backend_changed.connect(func(type: int) -> void: %ServiceOption.select(%ServiceOption.get_item_index(type)))
	%StatusLabel.text = MultiplayerService.status_text
	MultiplayerService.status_changed.connect(func(text: String) -> void:
		%StatusLabel.text = text
		if MultiplayerService.pending and MultiplayerService.backend_type == MultiplayerService.BackendType.PLAYFLOW:
			%PendingLabel.text = text)
	MultiplayerService.creating_lobby.connect(_show_pending.bind("Hosting game..."))
	MultiplayerService.joining_lobby.connect(_show_pending.bind("Joining game..."))
	MultiplayerService.join_lobby_failed.connect(_on_join_lobby_failed)
	MultiplayerService.lobby_joined.connect(_on_lobby_joined)
	%UsernameEdit.max_length = GGT_GameConfig.MAX_USERNAME_LENGTH
	%UsernameEdit.text = GGT_GameConfig.get_username()
	%UsernameEdit.text_submitted.connect(_commit_username)
	%UsernameEdit.focus_exited.connect(_commit_username)
	GGT_GameConfig.username_changed.connect(func(value: String) -> void: %UsernameEdit.text = value)
	MultiplayerService.creating_lobby.connect(_commit_username)
	MultiplayerService.joining_lobby.connect(_commit_username)
	%HostButton.pressed.connect(func() -> void:
		%MainContainer.hide()
		%Help.hide()
		%HostPanel.open())
	%JoinButton.pressed.connect(func() -> void:
		%MainContainer.hide()
		%Help.hide()
		%JoinPanel.open())
	matchmaker = Matchmaker.new()
	add_child(matchmaker)
	matchmaker.progress.connect(func(text: String) -> void: %PendingLabel.text = text)
	matchmaker.finished.connect(_on_matchmake_finished)
	%MatchmakeButton.pressed.connect(_start_matchmake)
	%PlayFlowButton.pressed.connect(func() -> void:
		MultiplayerService.set_backend(MultiplayerService.BackendType.PLAYFLOW, false)
		MultiplayerService.join_game("auto"))
	%CancelButton.pressed.connect(_cancel_pending)
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
	if is_shipping_menu():
		# Shipped builds only expose the dedicated PlayFlow flow and settings.
		MultiplayerService.set_backend(MultiplayerService.BackendType.PLAYFLOW, false)
		for node in [%ServiceRow, %MatchmakeButton, %HostButton, %JoinButton]:
			node.hide()
		# Debug web exports keep Join for local ws://127.0.0.1 server testing.
		%JoinButton.visible = OS.has_feature("web") and OS.is_debug_build()
	_focus_default()
	if not MultiplayerService.kick_reason.is_empty():
		_show_failure(MultiplayerService.kick_reason)
		MultiplayerService.kick_reason = ""
	

## Web and release exports hide the developer backends (ENet, Tube, Host/Join).
static func is_shipping_menu() -> bool:
	return OS.has_feature("web") or not OS.is_debug_build()

func _commit_username(_text: String = "") -> void:
	GGT_GameConfig.set_username(%UsernameEdit.text)
	%UsernameEdit.text = GGT_GameConfig.get_username()
	GGT_GameConfig.persist()

func _focus_default() -> void:
	if %MatchmakeButton.visible:
		%MatchmakeButton.grab_focus()
	else:
		%PlayFlowButton.grab_focus()

func _restore_main() -> void:
	if matchmaker.running:
		return
	%MainContainer.show()
	%Help.show()
	_focus_default()

func _cancel_pending() -> void:
	if matchmaker.running:
		matchmaker.cancel()
		return
	timeout_token += 1
	MultiplayerService.leave_game()
	%CancelButton.hide()
	%PendingOverlay.hide()
	_restore_main()

func _start_matchmake() -> void:
	timeout_token += 1
	%MainContainer.hide()
	%Help.hide()
	%PendingLabel.text = "Searching for matches..."
	%FailedLabel.hide()
	%FailedButton.hide()
	%CancelButton.show()
	%PendingOverlay.show()
	%CancelButton.grab_focus()
	matchmaker.run()

func _on_matchmake_finished(success: bool, reason: String) -> void:
	%CancelButton.hide()
	if success:
		return
	if reason.is_empty():
		%PendingOverlay.hide()
		_restore_main()
	else:
		_show_failure(reason)

func _on_join_lobby_failed(reason: String) -> void:
	if not matchmaker.running:
		_show_failure(reason)

func _show_pending(text: String) -> void:
	if matchmaker.running:
		return
	timeout_token += 1
	var token := timeout_token
	%MainContainer.hide()
	%Help.hide()
	%PendingLabel.text = text
	%FailedLabel.hide()
	%FailedButton.hide()
	%PendingOverlay.show()
	%PendingOverlay.grab_focus()
	var playflow := MultiplayerService.backend_type == MultiplayerService.BackendType.PLAYFLOW
	%CancelButton.visible = playflow
	if playflow:
		%CancelButton.grab_focus()
		return # Backend owns the 90-second deadline, including HTTP and connection.
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
	%CancelButton.hide()
	%PendingOverlay.show()
	%FailedButton.grab_focus()

func _on_lobby_joined() -> void:
	timeout_token += 1
	%CancelButton.hide()
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
