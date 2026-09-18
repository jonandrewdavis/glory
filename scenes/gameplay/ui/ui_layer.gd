extends CanvasLayer
class_name UILayer

const MENU_SCENE := "res://scenes/menu/menu.tscn"
var exiting := false
var _resume_label: Label

func _ready() -> void:
	# World is our Global link.
	World.ui_layer = self
	_resume_label = Label.new()
	_resume_label.text = "Resuming session..."
	_resume_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_resume_label.position = Vector2(24, 100)
	_resume_label.add_theme_font_size_override("font_size", 24)
	_resume_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_resume_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$PlayerUI.add_child(_resume_label)
	_resume_label.hide()
	# Player will use this.

	GGT_GameConfig.ui_scale_changed.connect(_apply_ui_scale)
	$PlayerUI.resized.connect(_apply_ui_scale)
	_apply_ui_scale()

	MultiplayerService.game_exited.connect(_on_game_exited)
	if DebugMenu != null:
		DebugMenu.update_settings_label()
	if GGT.is_changing_scene():
		await GGT.scene_transition_finished
		await get_tree().process_frame
	if not MultiplayerService.in_lobby:
		_on_game_exited()
	elif not exiting:
		capture_player_mouse()

## Scales the HUD (everything but Controls) while keeping it anchored to the screen edges.
func _apply_ui_scale(_value: float = 0.0) -> void:
	var ui_scale := GGT_GameConfig.get_ui_scale()
	%HudRoot.scale = Vector2(ui_scale, ui_scale)
	%HudRoot.size = $PlayerUI.size / ui_scale

func _on_game_exited() -> void:
	if exiting:
		return
	exiting = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if GGT.is_changing_scene():
		await GGT.scene_transition_finished
		await get_tree().process_frame
	GGT.change_scene(MENU_SCENE, {"show_progress_bar": false})

func is_paused() -> bool:
	return $PauseLayer.visible

func _process(_delta: float) -> void:
	_resume_label.visible = MultiplayerService.presence.recovering

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not is_paused() and not MultiplayerService.presence.blocks_input():
		capture_player_mouse()
		get_viewport().set_input_as_handled()

func capture_player_mouse() -> void:
	var player: ArrowPlayer = World.player_spawner.get_player(multiplayer.get_unique_id())
	if is_instance_valid(player):
		player.capture_mouse()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
