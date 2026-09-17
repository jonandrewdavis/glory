extends CanvasLayer
class_name UILayer

const MENU_SCENE := "res://scenes/menu/menu.tscn"
var exiting := false

func _ready() -> void:
	# World is our Global link.
	World.ui_layer = self
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
	World.scoreboard.changed.connect(_update_score)
	MultiplayerService.username_changed.connect(func(_id: int) -> void: _update_score())
	_update_score()

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

func capture_player_mouse() -> void:
	var player: ArrowPlayer = World.player_spawner.get_player(multiplayer.get_unique_id())
	if is_instance_valid(player):
		player.capture_mouse()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _update_score() -> void:
	var board: Scoreboard = World.scoreboard
	var lines := PackedStringArray()
	#var viewer := board.get_team(multiplayer.get_unique_id())
	lines.append("%d - %s" % [board.team_kills(Teams.Team.BLUE), board.team_kills(Teams.Team.ORANGE)])
	var ids := board.entries.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = board.entries[id]
		lines.append("%s  %d/%d" % [MultiplayerService.get_username(id), e.kills, e.deaths])
	%ScoreLabel.text = "\n".join(lines)
