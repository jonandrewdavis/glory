extends SceneTree
## Headless smoke test: Godot --headless --path . -s tests/flight_profile_test.gd

const PROFILE_DIR := "res://player/mage/profiles/"
const NAMES := ["original", "airplane", "character", "arcade", "broom_drift"]

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true

func _run() -> void:
	var profiles := {}
	for n in NAMES:
		var p = load(PROFILE_DIR + n + ".tres")
		assert(p != null, "missing profile " + n)
		assert(p.get_script().get_global_name() == "MageFlightProfile", n + " is not a MageFlightProfile")
		assert(p.min_speed < p.base_speed and p.base_speed < p.max_speed, n + " speed ordering")
		assert(p.yaw_speed > 0.0 and p.pitch_speed > 0.0 and p.roll_speed > 0.0)
		profiles[n] = p

	var player = load("res://player/mage/player_mage.tscn").instantiate()
	player.name = "1"
	player.set_physics_process(false)
	root.add_child(player)
	assert(player.profile != null, "scene default profile")
	assert(player.debug_profiles.size() >= 5)
	assert(player.current_speed == player.profile.base_speed)
	var orig = profiles["original"]
	assert(orig.max_speed == 80.0 and orig.min_speed == 20.0 and orig.base_speed == 50.0)
	assert(orig.acceleration == 15.5 and orig.deceleration == 10.5 and orig.yaw_speed == 45.0)
	assert(orig.turn_responsiveness == 60.0 and orig.drift == 0.0 and orig.high_speed_turn_penalty == 0.0)

	var dt := 1.0 / 60.0
	var yaw_after := {}
	for n in ["airplane", "character", "arcade"]:
		player.set_profile(profiles[n])
		player.basis = Basis.IDENTITY
		player.current_speed = profiles[n].base_speed
		var first_frame_turn := 0.0
		for i in 30:
			player.apply_rotation(Vector3(0.0, 1.0, 0.0), dt)
			if i == 0:
				first_frame_turn = player._turn_velocity.y
		yaw_after[n] = player.rotation.y
		var full: float = profiles[n].yaw_rad()
		var r: float = profiles[n].turn_responsiveness
		var pr = profiles[n]
		var span: float = maxf(pr.max_speed - pr.min_speed, 0.001)
		var t: float = clampf((pr.base_speed - pr.min_speed) / span, 0.0, 1.0)
		full *= lerpf(1.0, 1.0 - pr.high_speed_turn_penalty, t)
		var expected: float = full if r >= 60.0 else full * (1.0 - exp(-r * dt))
		assert(absf(first_frame_turn - expected) < 0.0001, "%s first-tick ramp %f, expected %f" % [n, first_frame_turn, expected])
		if r < 60.0:
			assert(first_frame_turn < full, n + " should ramp rather than snap")
	assert(yaw_after["character"] > yaw_after["airplane"] * 2.0, "character should turn far tighter than airplane")

	# High-speed penalty: airplane at max speed turns slower than at min speed.
	player.set_profile(profiles["airplane"])
	var rates := []
	for speed in [profiles["airplane"].min_speed, profiles["airplane"].max_speed]:
		player.current_speed = speed
		player._turn_velocity = Vector3.ZERO
		for i in 120:
			player.apply_rotation(Vector3(0.0, 1.0, 0.0), dt)
		rates.append(player._turn_velocity.y)
	assert(rates[1] < rates[0] * 0.6, "airplane should lose turn authority at max speed")

	# Speed clamps when switching to a profile with a lower ceiling.
	player.set_profile(profiles["arcade"])
	player.current_speed = profiles["arcade"].max_speed
	player.set_profile(profiles["character"])
	assert(player.current_speed == profiles["character"].max_speed, "speed clamped on profile swap")

	# Drift: velocity direction lags facing for broom_drift, never for character.
	for n in ["character", "broom_drift"]:
		player.set_profile(profiles[n])
		player.basis = Basis.IDENTITY
		player._reset_motion_state()
		player.rotate_y(PI / 2.0)
		var dir: Vector3 = player._travel_direction(dt)
		var aligned := dir.dot(-player.basis.z) > 0.999
		if n == "character":
			assert(aligned, "character should be on rails")
		else:
			assert(not aligned, "broom_drift should lag facing")
			for i in 600:
				dir = player._travel_direction(dt)
			assert(dir.dot(-player.basis.z) > 0.99, "drift should converge on facing")

	# Auto level: rolled mage returns to horizon when coasting at base speed with no input.
	player.set_profile(profiles["character"])
	player.basis = Basis.IDENTITY
	player._reset_motion_state()
	player.rotate(player.basis.z, deg_to_rad(40.0))
	assert(absf(rad_to_deg(player.bank_angle()) - 40.0) < 0.01, "bank_angle should read the roll")
	player.current_speed = profiles["character"].max_speed
	player.apply_rotation(Vector3(0.0, 1.0, 0.0), dt)
	assert(absf(rad_to_deg(player.bank_angle()) - 40.0) < 0.01, "no auto level while steering")
	player.rotation.y = 0.0
	player.rotate(player.basis.z, deg_to_rad(40.0) - player.bank_angle())
	player.current_speed = profiles["character"].max_speed # levels at any speed
	for i in 60:
		player.apply_rotation(Vector3.ZERO, dt)
	assert(absf(player.bank_angle()) < 0.001, "character should level within a second, got %f deg" % rad_to_deg(player.bank_angle()))
	player.set_profile(profiles["original"])
	player.rotate(player.basis.z, deg_to_rad(30.0))
	player.current_speed = profiles["original"].base_speed
	for i in 60:
		player.apply_rotation(Vector3.ZERO, dt)
	assert(absf(rad_to_deg(player.bank_angle()) - 30.0) < 0.01, "original has auto level off")

	# Null profile falls back to defaults matching the original hard-coded values.
	var bare = load("res://player/mage/player_mage.tscn").instantiate()
	bare.name = "2"
	bare.profile = null
	bare.debug_profiles.clear()
	bare.set_physics_process(false)
	root.add_child(bare)
	assert(bare.profile != null and bare.profile.max_speed == 80.0 and bare.profile.yaw_speed == 45.0)

	print("Flight profile checks passed: presets, original, ramp, speed penalty, clamp, drift, auto level, fallback.")
