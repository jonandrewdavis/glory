extends Node
## Run: Godot --headless --path . tools/check_charge_arc.tscn
var failures := 0

class ShotProbe extends ArrowPlayer:
	var shots: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
	func _fire(target: Vector2) -> void:
		shots.append({"aim": (target - global_position).normalized(), "time": preparation_time, "level": selected_level, "speed": compute_arrow_speed(selected_level), "position": global_position})
		_cancel_preparation()
		fire_cooldown_left = FIRE_COOLDOWN

func _ready() -> void:
	call_deferred("check")

func expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)

func check() -> void:
	await check_shots()
	var saved_config := ConfigFile.new()
	saved_config.parse(GGT_GameConfig.config.encode_to_text())
	GGT_GameConfig.set_aim_sensitivity(GGT_GameConfig.DEFAULT_AIM_SENSITIVITY)
	var player = load("res://player/arrow_player/arrow_player.tscn").instantiate()
	var reticle = player.get_node("AimReticle")
	reticle._ready()
	expect(not reticle.visible, "Reticle starts hidden for remote players")
	# Motions are expressed as virtual cursor travel so they hold at any default sensitivity.
	var per_pixel: float = GGT_GameConfig.DEFAULT_AIM_SENSITIVITY
	reticle.apply_mouse_motion(Vector2(-80.0, 0.0) / per_pixel)
	expect(reticle.direction == Vector2.RIGHT, "Aim stays valid at virtual cursor origin")
	reticle.apply_mouse_motion(Vector2(0.0, -80.0) / per_pixel)
	expect(reticle.direction.is_equal_approx(Vector2.UP), "Relative mouse movement aims upward")
	reticle.apply_mouse_motion(Vector2(-160.0, 80.0) / per_pixel)
	expect(reticle.direction.is_equal_approx(Vector2.LEFT), "Relative mouse movement can reverse aim")
	for motion in [Vector2(10000.0, 5000.0), Vector2(-400.0, -800.0), Vector2.ZERO]:
		reticle.apply_mouse_motion(motion)
		expect(is_equal_approx(reticle.position.length(), reticle.radius), "Reticle stays at fixed radius")
		expect(is_equal_approx(reticle.direction.length(), 1.0), "Shot direction stays normalized")
	var original_direction: Vector2 = reticle.direction
	player.position += Vector2(200.0, -100.0)
	expect(reticle.direction == original_direction, "Player movement preserves aim direction")
	var settings = load("res://addons/ggt-core/settings/settings_menu.tscn").instantiate()
	add_child(settings)
	var slider: HSlider = settings.aim_sensitivity_slider
	expect(slider.min_value == 0.0 and slider.max_value == 100.0 and slider.step == 1.0, "Settings slider uses a 0-100 range in whole steps")
	expect(slider.value == 50.0 and settings.aim_sensitivity_value.text == "50", "Settings default is displayed at midpoint")
	slider.value = 75.0
	expect(is_equal_approx(GGT_GameConfig.get_aim_sensitivity(), 0.07) and is_equal_approx(reticle.sensitivity, 7.0), "Settings slider changes live aiming sensitivity")
	expect(settings.aim_sensitivity_value.text == "75", "Settings label updates as a 0-100 value")
	GGT_GameConfig.revert_to(saved_config)
	settings.initialize()
	expect(is_equal_approx(reticle.sensitivity, GGT_GameConfig.aim_level_to_sensitivity(slider.value) * 100.0), "Reverting settings restores both slider and live aim")
	var legacy_config := ConfigFile.new()
	legacy_config.set_value("controls", "aim_sensitivity", 0.5)
	expect(is_equal_approx(GGT_GameConfig.get_aim_sensitivity(legacy_config), 0.05), "Old saved default maps to new midpoint")
	legacy_config.set_value("controls", "aim_sensitivity", 0.25)
	expect(is_equal_approx(GGT_GameConfig.get_aim_sensitivity(legacy_config), 0.05), "Previous midpoint default maps to new midpoint")
	legacy_config.set_value("controls", "aim_sensitivity", 0.10)
	expect(is_equal_approx(GGT_GameConfig.get_aim_sensitivity(legacy_config), 0.05), "Values from the older, faster scale map to new midpoint")
	legacy_config.set_value("controls", "aim_sensitivity", 0.09)
	expect(is_equal_approx(GGT_GameConfig.get_aim_sensitivity(legacy_config), 0.09), "Maximum of the current range is kept")
	settings.free()
	expect(player.get_node_or_null("MultiplayerSynchronizer") == null, "Owner state cannot broadcast through a movement synchronizer")
	var config: SceneReplicationConfig = player.get_node("HealthSynchronizer").replication_config
	for property in config.get_properties():
		var node_path := NodePath(String(property).get_slice(":", 0))
		expect(player.get_node_or_null(node_path) != null, "Replication target resolves: " + String(property))
	for level in 3:
		var events := InputMap.action_get_events(ArrowPlayer.LEVEL_ACTIONS[level])
		expect(events.size() == 1 and events[0].physical_keycode == KEY_1 + level, "Level key binding %d" % (level + 1))
	player.free()
	get_tree().quit(1 if failures else 0)

func reset_probe(probe: ArrowPlayer, level: int) -> void:
	probe._cancel_preparation()
	probe.shots.clear()
	probe.fire_cooldown_left = 0.0
	probe.select_level(level)

func check_shots() -> void:
	var probe = load("res://player/arrow_player/arrow_player.tscn").instantiate()
	probe.set_script(ShotProbe)
	probe.name = "1"
	add_child(probe)
	probe.aim_reticle.set_physics_process(false)
	for level in 3:
		var minimum: float = probe.minimum_preparation_time(level)
		for early in [0.0, 0.1, minimum - 0.001]:
			reset_probe(probe, level)
			if early > 0.0:
				probe._update_shot_input(early, Vector2.RIGHT * 96.0, true, true, false)
			probe._update_shot_input(0.0, Vector2.RIGHT * 96.0, true, false, true)
			expect(probe._shot_queued and probe.shots.is_empty(), "Early release queues level %d" % level)
			probe.position += Vector2(10, 0)
			probe._update_shot_input(minimum - early + 0.000001, probe.position + Vector2.UP * 96.0, true, true, true)
			expect(probe.shots.size() == 1 and probe.shots[0].level == level, "Queue fires selected level once")
			expect(probe.shots[0].aim.is_equal_approx(Vector2.UP) and probe.shots[0].position == probe.position, "Queue uses live aim and origin")
			expect(not probe._shot_queued and probe.fire_cooldown_left == probe.FIRE_COOLDOWN, "Fire clears queue and starts cooldown")
			probe._update_shot_input(0.1, Vector2.UP, true, true, true)
			expect(probe.shots.size() == 1, "Cooldown prevents duplicate shot")
		for held_time in [minimum, 10.0]:
			reset_probe(probe, level)
			probe._update_shot_input(held_time, probe.position + Vector2.RIGHT * 96.0, true, true, false)
			expect(probe.shots.is_empty() and probe.readiness_indicator.display_state.w == 1.0, "Ready held shot never auto-fires")
			expect(probe.arrow_container.scale == probe.level_arrow_scales[level], "Aiming arrow uses selected size")
			probe._update_shot_input(0.0, probe.position + Vector2.RIGHT * 96.0, true, false, true)
			expect(probe.shots.size() == 1 and probe.shots[0].speed == probe.level_speeds[level], "Hold duration cannot change speed")
		probe._server_last_fire_msec = -100000
		probe.server_fire(Vector2.RIGHT, level, minimum - 0.001)
		expect(probe._server_last_fire_msec == -100000, "Host rejects premature level %d" % level)

	# A full tap anywhere in recovery must survive until preparation can start.
	for level in 3:
		for cooldown in [0.5, 0.25, 0.001]:
			reset_probe(probe, level)
			probe.fire_cooldown_left = cooldown
			probe._update_shot_input(0.01, Vector2.RIGHT, true, false, true)
			expect(probe._shot_queued and probe.is_preparing, "Cooldown tap buffers level %d at %.3f" % [level, cooldown])
			for click in 3:
				probe._update_shot_input(0.01, Vector2.RIGHT, true, true, false)
				probe._update_shot_input(0.01, Vector2.RIGHT, true, false, true)
			expect(probe.preparation_time == 0.0 and probe.shots.is_empty(), "Repeated cooldown clicks preserve one shot without preparing early")
			probe.fire_cooldown_left = 0.0
			var minimum: float = probe.minimum_preparation_time(level)
			probe._update_shot_input(minimum * 0.5, Vector2.UP, true, false, false)
			expect(probe.shots.is_empty() and probe._shot_queued, "Buffered shot waits for full preparation")
			probe._update_shot_input(minimum * 0.5 + 0.000001, Vector2.UP, true, false, false)
			expect(probe.shots.size() == 1 and probe.shots[0].level == level, "Buffered shot fires once after recovery and preparation")
			probe.fire_cooldown_left = 0.0
			probe._update_shot_input(10.0, Vector2.UP, true, false, false)
			expect(probe.shots.size() == 1, "Repeated clicks do not create extra buffered shots")

	reset_probe(probe, 0)
	probe.fire_cooldown_left = 0.25
	probe._update_shot_input(0.1, Vector2.RIGHT, true, true, false)
	probe.fire_cooldown_left = 0.0
	probe._update_shot_input(1.0, Vector2.RIGHT, true, true, false)
	expect(probe.shots.is_empty() and probe.is_preparing, "Hold begun during cooldown still waits for release")
	probe._update_shot_input(0.0, Vector2.RIGHT, true, false, true)
	expect(probe.shots.size() == 1, "Held buffered shot fires on release")

	for cancel in [false, true]:
		reset_probe(probe, 0)
		probe.fire_cooldown_left = 0.25
		probe._update_shot_input(0.0, Vector2.RIGHT, true, false, true)
		probe._update_shot_input(0.0, Vector2.RIGHT, cancel, false, false, cancel)
		probe.fire_cooldown_left = 0.0
		probe._update_shot_input(10.0, Vector2.RIGHT, true, false, false)
		expect(probe.shots.is_empty() and not probe._shot_queued, "Cancel or loss of control clears cooldown buffer")

	reset_probe(probe, 0)
	probe._update_shot_input(1.0, Vector2.RIGHT, true, true, false)
	probe.select_level(2)
	expect(probe.preparation_time == 1.0 and probe.readiness_indicator.display_state.w == 0.0, "Switch up preserves elapsed time and becomes unready")
	expect(probe.compute_arrow_speed(probe.selected_level) == 1296.0, "Preview speed changes immediately with selection")
	probe.select_level(0)
	probe._update_shot_input(0.0, Vector2.RIGHT, true, true, false)
	expect(probe.shots.is_empty() and probe.readiness_indicator.display_state.w == 1.0, "Switch down while held still waits for release")

	reset_probe(probe, 2)
	probe._update_shot_input(1.0, Vector2.RIGHT, true, true, false)
	probe._update_shot_input(0.0, Vector2.RIGHT, true, false, true)
	probe.select_level(0)
	probe._update_shot_input(0.0, Vector2.RIGHT, true, false, false)
	expect(probe.shots.size() == 1 and probe.shots[0].level == 0, "Switch queued shot down fires when already ready")

	reset_probe(probe, 0)
	probe._update_shot_input(0.4, Vector2.RIGHT, true, true, false)
	probe._update_shot_input(0.0, Vector2.RIGHT, true, false, true)
	probe.select_level(2)
	probe._update_shot_input(0.5, Vector2.RIGHT, true, false, false)
	expect(probe.shots.is_empty() and probe._shot_queued, "Switch queued shot up waits for longer minimum")
	probe._update_shot_input(1.5, Vector2.RIGHT, true, false, false)
	expect(probe.shots.size() == 1 and probe.shots[0].level == 2, "Switched queue fires at new minimum")

	for queued in [false, true]:
		reset_probe(probe, 2)
		probe._update_shot_input(0.1, Vector2.RIGHT, true, true, false)
		if queued:
			probe._update_shot_input(0.0, Vector2.RIGHT, true, false, true)
		probe._update_shot_input(10.0, Vector2.RIGHT, false, false, false)
		expect(not probe.is_preparing and not probe._shot_queued and probe.shots.is_empty(), "Loss of ability to act cancels held/queued shot")

	for queued in [false, true]:
		reset_probe(probe, 2)
		probe._update_shot_input(0.1, Vector2.RIGHT, true, true, false)
		if queued:
			probe._update_shot_input(0.0, Vector2.RIGHT, true, false, true)
		probe._update_shot_input(10.0, Vector2.RIGHT, true, not queued, false, true)
		expect(not probe.is_preparing and not probe._shot_queued and probe.shots.is_empty(), "Jump cancels held/queued shot before it can fire")
		expect(probe.fire_cooldown_left == 0.0 and not probe.arrow_container.visible, "Jump cancellation hides arrow without cooldown")
		probe._reset_jump()
		probe._update_jump(0.0, true, true, true, true)
		expect(probe.velocity.y == ArrowPlayer.JUMP_VELOCITY, "Canceling held or queued preparation also jumps")
		if not queued:
			probe._update_shot_input(10.0, Vector2.RIGHT, true, true, false)
			expect(not probe.is_preparing, "Canceled hold cannot restart preparation")
			probe._update_shot_input(0.0, Vector2.RIGHT, true, false, true)
			expect(not probe._shot_queued and probe.shots.is_empty(), "Canceled hold's release cannot queue a shot")
		probe._update_shot_input(0.1, Vector2.RIGHT, true, true, false)
		expect(probe.is_preparing, "Fresh press prepares normally after cancellation")
		probe._cancel_preparation()

	reset_probe(probe, 2)
	probe._update_shot_input(3.0, Vector2.RIGHT, true, true, false)
	probe._update_shot_input(0.0, Vector2.RIGHT, true, false, true, true)
	expect(probe.shots.is_empty() and not probe.is_preparing, "Jump takes priority over simultaneous ready-shot release")

	probe.readiness_indicator._process(0.0)
	expect(probe.readiness_indicator.visible and probe.readiness_indicator.display_state == Vector4(2, 0, 0, 0), "Idle indicator retains selected level")
	probe._on_died(null)
	probe.readiness_indicator._process(0.0)
	expect(not probe.readiness_indicator.visible and not probe.is_preparing, "Death hides indicator and cancels shot")
	probe._on_respawned()
	probe.readiness_indicator._process(0.0)
	expect(probe.selected_level == 2 and probe.readiness_indicator.visible, "Respawn preserves selection and restores indicator")
	probe.set_multiplayer_authority(2)
	probe.selected_level = 0 # Remote gameplay state is not the presentation snapshot.
	probe._on_died(null)
	probe._on_respawned()
	probe.readiness_indicator._process(0.0)
	expect(probe.readiness_indicator.display_state == Vector4(2, 0, 0, 0), "Remote respawn leaves the indicator state untouched")

	for invalid in [[-1, 10.0], [3, 10.0], [0, NAN], [0, INF]]:
		probe.server_fire(Vector2.RIGHT, invalid[0], invalid[1])
	probe.server_fire(Vector2(NAN, 0), 0, 10.0)
	probe.server_fire(Vector2.ZERO, 0, 10.0)
	expect(probe._server_last_fire_msec == -100000, "Host rejects invalid shot data without consuming cooldown")
	probe.free()
	await get_tree().process_frame
