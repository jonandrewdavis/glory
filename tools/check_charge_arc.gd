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
		shots.append({"aim": (target - global_position).normalized(), "time": charge_time, "position": global_position})
		_cancel_charge()
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
	await check_queued_shots()
	var saved_config := ConfigFile.new()
	saved_config.parse(GGT_GameConfig.config.encode_to_text())
	GGT_GameConfig.set_aim_sensitivity(GGT_GameConfig.DEFAULT_AIM_SENSITIVITY)
	var player = load("res://player/arrow_player/arrow_player.tscn").instantiate()
	var reticle = player.get_node("AimReticle")
	reticle._ready()
	expect(not reticle.visible, "Reticle starts hidden for remote players")
	reticle.apply_mouse_motion(Vector2(-320.0, 0.0))
	expect(reticle.direction == Vector2.RIGHT, "Aim stays valid at virtual cursor origin")
	reticle.apply_mouse_motion(Vector2(0.0, -320.0))
	expect(reticle.direction.is_equal_approx(Vector2.UP), "Relative mouse movement aims upward")
	reticle.apply_mouse_motion(Vector2(-640.0, 320.0))
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
	expect(slider.min_value == 5.0 and slider.max_value == 45.0 and slider.step == 5.0, "Settings slider uses readable percent range and steps")
	expect(slider.value == 25.0 and settings.aim_sensitivity_value.text == "25%", "Settings default is displayed at midpoint")
	slider.value = 35.0
	expect(is_equal_approx(GGT_GameConfig.get_aim_sensitivity(), 0.35) and is_equal_approx(reticle.sensitivity, 35.0), "Settings slider changes live aiming sensitivity")
	expect(settings.aim_sensitivity_value.text == "35%", "Settings label updates as percentage")
	GGT_GameConfig.revert_to(saved_config)
	settings.initialize()
	expect(is_equal_approx(reticle.sensitivity, slider.value), "Reverting settings restores both slider and live aim")
	var legacy_config := ConfigFile.new()
	legacy_config.set_value("controls", "aim_sensitivity", 0.5)
	expect(GGT_GameConfig.get_aim_sensitivity(legacy_config) == 0.25, "Old saved default maps to new midpoint")
	settings.free()
	var arc = player.get_node("ChargeArc")
	player.remove_child(arc)
	arc.owner = null
	add_child(arc)
	arc.set_process(false)
	expect(not player.has_node("ChargeBar") and not player.has_node("HealthBar"), "Old player bars removed")
	expect(player.has_node("HealthComponent") and player.has_node("ArrowContainer"), "Health mechanics and aiming arrow retained")
	var config: SceneReplicationConfig = player.get_node("MultiplayerSynchronizer").replication_config
	for property in config.get_properties():
		var node_path := NodePath(String(property).get_slice(":", 0))
		var target: Node = arc if node_path == NodePath("ChargeArc") else player.get_node_or_null(node_path)
		expect(target != null, "Replication target resolves: " + String(property))
	var hud = load("res://scenes/gameplay/ui/ui_layer.tscn").instantiate()
	expect(hud.find_child("StrengthProgressBar", true, false) == null and hud.find_child("ChargeLevelLabel", true, false) == null, "HUD charge duplicates removed")
	for t in [0.1, 1.3, 2.1, 3.3, 4.1, 5.3, 6.0, 8.0]:
		arc.display_state = Vector4(1.0, player.charge_strength(t), player.charge_level(t), 1.0 if player.is_perfect(t) else 0.0)
		arc._process(0.016)
		expect(arc.visible and arc._tier == player.charge_level(t), "Charge state at %.1f seconds" % t)
		await get_tree().process_frame
	arc._process(0.3)
	arc._process(0.016)
	expect(is_zero_approx(arc._effect_left) and arc.position == Vector2.ZERO, "Maximum hold does not retrigger shake")
	arc.reset()
	expect(not arc.visible and arc.scale == Vector2.ONE and arc.position == Vector2.ZERO, "Cancel clears all effects")
	arc.display_state = Vector4(1.0, 0.6, 2.0, 1.0)
	arc._process(0.016)
	expect(not arc._burst, "Late join at tier three does not replay a tier-up burst")
	arc.reset()
	arc.display_state = Vector4(1.0, 0.8, 0.0, 1.0)
	arc._process(0.016)
	arc.display_state = Vector4(1.0, 0.0, 1.0, 0.0)
	arc._process(0.016)
	expect(arc._burst and arc._effect_left > 0.0, "Tier transition triggers burst")
	arc.display_state = Vector4.ZERO
	arc._process(0.016)
	expect(not arc.visible and arc._effect_left == 0.0, "Replicated release clears arc")
	arc.free()
	player.free()
	hud.free()
	get_tree().quit(1 if failures else 0)

func check_queued_shots() -> void:
	var probe = load("res://player/arrow_player/arrow_player.tscn").instantiate()
	probe.set_script(ShotProbe)
	probe.name = "1"
	add_child(probe)
	for early in [0.0, 0.1, probe.minimum_charge_time - 0.001]:
		probe._cancel_charge()
		probe.shots.clear()
		probe.fire_cooldown_left = 0.0
		if early > 0.0:
			probe._update_charge_input(early, probe.global_position + Vector2.RIGHT * 96.0, true, true, false)
		probe._update_charge_input(0.0, probe.global_position + Vector2.RIGHT * 96.0, true, false, true)
		expect(probe._shot_queued and probe.shots.is_empty() and probe.fire_cooldown_left == 0.0, "Early release %.3f queues without cooldown" % early)
		probe.position += Vector2(10.0, 0.0)
		# Pending shots follow live aim without creating a second shot.
		probe._update_charge_input(probe.minimum_charge_time - early, probe.global_position + Vector2.UP * 96.0, true, true, true)
		expect(probe.shots.size() == 1 and is_equal_approx(probe.shots[0].time, probe.minimum_charge_time), "Queued shot fires once at minimum")
		expect(probe.shots[0].aim.is_equal_approx(Vector2.UP) and probe.shots[0].position == probe.global_position, "Queued shot uses live aim and current origin")
		expect(not probe._shot_queued and probe.fire_cooldown_left == probe.FIRE_COOLDOWN, "Queue clears and cooldown starts on fire")
		probe._update_charge_input(0.01, Vector2.UP, true, true, true)
		expect(probe.shots.size() == 1, "Extra clicks cannot duplicate shot during cooldown")
	for held_time in [probe.minimum_charge_time, 0.8, 2.2]:
		probe.fire_cooldown_left = 0.0
		probe.shots.clear()
		probe._update_charge_input(held_time, probe.global_position + Vector2.RIGHT * 96.0, true, true, false)
		probe._update_charge_input(0.0, probe.global_position + Vector2.RIGHT * 96.0, true, false, true)
		expect(probe.shots.size() == 1 and not probe._shot_queued, "Release %.1f fires immediately" % held_time)
	probe.fire_cooldown_left = 0.0
	probe.shots.clear()
	probe._update_charge_input(0.1, probe.global_position + Vector2.RIGHT * 96.0, true, true, false)
	expect(is_equal_approx(probe.charge_arc.readiness.x, probe.charge_strength(probe.minimum_charge_time)) and probe.charge_arc.readiness.y == 0.0, "Level 1 marks configured minimum and starts unready")
	probe._update_charge_input(0.0, probe.global_position + Vector2.RIGHT * 96.0, true, false, true)
	probe._update_charge_input(0.5, Vector2.ZERO, false, false, false)
	expect(not probe.is_charging and not probe._shot_queued and probe.shots.is_empty(), "Losing ability to act cancels pending shot")
	probe._update_charge_input(probe.minimum_charge_time, probe.global_position + Vector2.RIGHT * 96.0, true, true, false)
	expect(probe.charge_arc.readiness.y == 1.0, "Minimum hold changes arc to ready")
	probe.server_fire(Vector2.RIGHT, probe.minimum_charge_time - 0.001)
	expect(probe._server_last_fire_msec == -100000, "Server rejects early shot without consuming cooldown")
	probe._cancel_charge()
	probe.free()
	await get_tree().process_frame
