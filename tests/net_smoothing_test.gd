extends SceneTree
## Headless smoke test: Godot --headless --path . -s tests/net_smoothing_test.gd
## Remote peers lerp/slerp toward replicated net_position / net_quaternion and snap on big errors.

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true

func _run() -> void:
	var dt := 1.0 / 60.0

	# Peer id 1 is the local (offline) peer, so name "2" makes this a remote-controlled instance.
	var remote = load("res://player/mage/player_mage.tscn").instantiate()
	remote.name = "2"
	remote.set_physics_process(false)
	remote.net_position = Vector3(10, 20, 30)
	remote.net_quaternion = Quaternion(Vector3.UP, PI * 0.5)
	root.add_child(remote)
	assert(not remote.is_multiplayer_authority(), "name 2 is remote")
	assert(remote.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "remote disables engine interpolation")
	assert(remote.global_position.is_equal_approx(Vector3(10, 20, 30)), "remote snaps to spawn state in _ready")
	assert(remote.global_basis.get_rotation_quaternion().is_equal_approx(remote.net_quaternion), "remote snaps rotation in _ready")

	# Small error: converge smoothly, never overshoot.
	remote.net_position = Vector3(12, 20, 30)
	remote.net_quaternion = Quaternion(Vector3.UP, PI * 0.5 + 0.2)
	remote._process(dt)
	var after_one: Vector3 = remote.global_position
	assert(after_one.x > 10.0 and after_one.x < 12.0, "first frame moves part way")
	var expected_weight: float = minf(remote.smoothing_speed * dt, 1.0)
	assert(is_equal_approx(after_one.x, lerpf(10.0, 12.0, expected_weight)), "lerp uses smoothing_speed * delta")
	var prev_dist: float = after_one.distance_to(remote.net_position)
	for i in 120:
		remote._process(dt)
		var d: float = remote.global_position.distance_to(remote.net_position)
		assert(d <= prev_dist + 0.0001, "distance never grows")
		prev_dist = d
	assert(remote.global_position.distance_to(remote.net_position) < 0.01, "converges on net_position")
	assert(remote.global_basis.get_rotation_quaternion().angle_to(remote.net_quaternion) < 0.01, "converges on net_quaternion")

	# Large error: snap in one frame.
	remote.net_position = Vector3(500, 0, 0)
	remote._process(dt)
	assert(remote.global_position.is_equal_approx(Vector3(500, 0, 0)), "snaps past snap_distance")

	# Huge delta clamps the weight to 1 instead of overshooting.
	remote.net_position = Vector3(505, 0, 0)
	remote._process(10.0)
	assert(remote.global_position.is_equal_approx(Vector3(505, 0, 0)), "weight clamps to 1")

	# Authority publishes its transform into the replicated fields and never smooths.
	var local = load("res://player/mage/player_mage.tscn").instantiate()
	local.name = "1"
	local.set_physics_process(false)
	root.add_child(local)
	assert(local.is_multiplayer_authority(), "name 1 is authority")
	local.global_position = Vector3(1, 2, 3)
	local.global_basis = Basis(Vector3.UP, 1.0)
	local._publish_net_state()
	assert(local.net_position.is_equal_approx(Vector3(1, 2, 3)), "authority publishes position")
	assert(local.net_quaternion.is_equal_approx(Quaternion(Vector3.UP, 1.0)), "authority publishes rotation")
	local.net_position = Vector3(900, 0, 0)
	local._process(dt)
	assert(local.global_position.is_equal_approx(Vector3(1, 2, 3)), "authority ignores net state")

	print("net_smoothing_test: OK")
