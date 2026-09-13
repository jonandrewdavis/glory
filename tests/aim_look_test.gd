extends SceneTree
## Headless smoke test: Godot --headless --path . -s tests/aim_look_test.gd

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true

func _run() -> void:
	var aim := AimLook.new()
	aim.enabled = true
	root.add_child(aim)

	aim.apply_motion(Vector2(100, 0))
	assert(aim.yaw < 0.0, "mouse right yaws negative")
	assert((aim.offset_basis() * Vector3.FORWARD).x > 0.0, "mouse right looks right")
	aim.reset()
	aim.apply_motion(Vector2(0, -100))
	assert(aim.pitch > 0.0, "mouse up pitches positive")
	assert((aim.offset_basis() * Vector3.FORWARD).y > 0.0, "mouse up looks up")

	aim.reset()
	aim.apply_motion(Vector2(100000, 100000))
	assert(is_equal_approx(aim.yaw, -deg_to_rad(aim.yaw_limit_deg)), "yaw clamps")
	assert(is_equal_approx(aim.pitch, -deg_to_rad(aim.pitch_limit_deg)), "pitch clamps")

	aim.invert_y = true
	aim.reset()
	aim.apply_motion(Vector2(0, -100))
	assert(aim.pitch < 0.0, "invert_y flips pitch")
	aim.invert_y = false

	aim.reset()
	aim.apply_motion(Vector2(200, -200))
	assert(not aim.is_looking(), "headless mouse is never captured")
	for i in 240:
		aim._process(1.0 / 60.0)
	assert(aim.yaw == 0.0 and aim.pitch == 0.0, "eases back to zero when released")

	aim.reset()
	aim.set_speed_ratio(0.0)
	aim.apply_motion(Vector2(100, 0))
	var slow_yaw := aim.yaw
	aim.reset()
	aim.set_speed_ratio(1.0)
	aim.apply_motion(Vector2(100, 0))
	assert(absf(aim.yaw) < absf(slow_yaw), "faster flight lowers sensitivity")
	assert(is_equal_approx(aim.yaw, slow_yaw * (1.0 - aim.high_speed_penalty)), "penalty scales linearly")
	aim.set_speed_ratio(0.0)

	var player = load("res://player/mage/player_mage.tscn").instantiate()
	player.name = "1"
	player.set_physics_process(false)
	root.add_child(player)
	assert(player.aim_look != null, "player has AimLook")
	player.targeting.basis = Basis.from_euler(Vector3(0, PI / 2, 0))
	var fwd: Vector3 = player.targeting._forward()
	assert(fwd.is_equal_approx(Vector3(-1, 0, 0)), "targeting forward follows its own basis: " + str(fwd))

	print("aim_look_test OK")
	quit()
