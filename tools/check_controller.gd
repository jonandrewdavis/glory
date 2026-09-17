extends Node
## Run: Godot --headless --path . tools/check_controller.tscn
var failures := 0

class PlayerProbe extends ArrowPlayer:
	func _enter_tree() -> void: pass
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

class RigProbe extends CameraRig:
	func _ready() -> void: pass

func expect(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)
	else:
		print("PASS: ", description)

func _ready() -> void:
	call_deferred("check")

func check() -> void:
	var player := PlayerProbe.new()
	player._update_facing(Vector2.LEFT)
	player._update_facing(Vector2(0.1, -0.995))
	expect(player.get_facing_direction() == -1, "Vertical aim retains facing")
	player._update_facing(Vector2.RIGHT)
	expect(player.get_facing_direction() == 1, "Committed aim reverses facing")
	player._update_horizontal(1.0, 1.0, 1.0)
	expect(player.velocity.x == 100.0, "Acceleration cannot overshoot speed")
	player._update_horizontal(0.05, 0.0, 1.0)
	expect(player.velocity.x == 0.0, "Braking stops without overshoot")
	player.velocity.x = 100.0
	player._update_horizontal(0.05, -1.0, 1.0)
	expect(player.velocity.x < 0.0, "Reversal responds within 50ms")
	player._update_jump(0.0, true, false, false, true)
	player._update_jump(0.09, true, true, true, false)
	expect(player.velocity.y == -290.0, "Coyote jump within grace window")
	player._update_jump(0.01, true, false, false, false)
	expect(player.velocity.y == -145.0, "Release cuts jump once")
	player._update_jump(0.01, true, true, true, false)
	expect(player.velocity.y == -145.0, "Coyote time cannot grant a second jump")
	player._reset_jump()
	player.velocity.y = 0.0
	player._update_jump(0.0, true, false, false, true)
	player._update_jump(0.11, true, true, true, false)
	expect(player.velocity.y == 0.0, "Expired coyote time does not jump")
	player._reset_jump()
	player._update_jump(0.0, true, true, false, false)
	player._update_jump(0.10, true, false, false, true)
	expect(player.velocity.y == -145.0, "Released buffered jump becomes short hop on landing")
	player._reset_jump()
	player.velocity.y = 0.0
	player._update_jump(0.0, true, true, true, false)
	player._update_jump(0.13, true, false, true, true)
	expect(player.velocity.y == 0.0, "Expired buffer does not jump")
	player._update_jump(0.0, true, true, true, false)
	player._update_jump(0.0, false, false, false, false)
	expect(player._jump_buffer_left == 0.0 and player._coyote_left == 0.0, "Input loss clears jump timers")
	player.is_blocking = true
	player._update_jump(0.0, true, true, true, true)
	expect(is_equal_approx(player.velocity.y, -159.5), "Blocking retains reduced jump")
	player.free()
	await check_drop_through()
	await check_camera()
	get_tree().quit(1 if failures else 0)

func check_drop_through() -> void:
	var platform := TileMapLayer.new()
	platform.tile_set = load("res://assets/sprites/oak_tileset.tres")
	platform.add_to_group("fortress_one_way_platforms")
	for x in 4:
		platform.set_cell(Vector2i(x, 0), 0, Vector2i(8, 0), 1)
	add_child(platform)
	var player: ArrowPlayer = load("res://player/arrow_player/arrow_player.tscn").instantiate()
	player.set_script(PlayerProbe)
	player.position = Vector2(32, -40)
	add_child(player)
	for tick in 60:
		await get_tree().physics_frame
		player.velocity += player.get_gravity() / 60.0
		player.move_and_slide()
	expect(player.is_on_floor(), "Player lands on a one-way platform")
	var rest_y := player.position.y
	player.velocity = Vector2.ZERO
	expect(player._drop_through_floor(), "Down press on a one-way floor releases it")
	for tick in 30:
		await get_tree().physics_frame
		player.velocity += player.get_gravity() / 60.0
		player.move_and_slide()
		player._update_drop_through(1.0 / 60.0)
	expect(player.position.y > rest_y + 16.0, "Player falls through the released platform")
	expect(player._drop_exceptions.is_empty(), "Drop exception clears after its window")
	var solid := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(64, 16)
	solid.add_child(shape)
	solid.position = Vector2(32, 200)
	add_child(solid)
	for tick in 120:
		await get_tree().physics_frame
		player.velocity += player.get_gravity() / 60.0
		player.move_and_slide()
	expect(player.is_on_floor(), "Player lands on solid ground below")
	expect(not player._drop_through_floor(), "Down press on solid ground does nothing")
	player.queue_free()
	platform.queue_free()
	solid.queue_free()

func check_camera() -> void:
	var rig := RigProbe.new()
	rig._update_camera_facing(Vector2.LEFT.rotated(deg_to_rad(34.0)), 0.5, true)
	expect(rig._camera_facing == 1, "Aim 34 degrees off horizontal cannot reverse camera")
	rig._update_camera_facing(Vector2.LEFT.rotated(deg_to_rad(32.0)), 0.5, true)
	expect(rig._camera_facing == -1, "Aim 32 degrees off horizontal commits after 500ms")
	rig._update_camera_facing(Vector2.RIGHT, 0.5, true)
	rig._update_camera_facing(Vector2(-0.6, -0.8), 1.0, true)
	expect(rig._camera_facing == 1, "Wide diagonal grace area prevents camera reversal")
	rig._update_camera_facing(Vector2.LEFT, 0.49, true)
	expect(rig._camera_facing == 1, "Brief opposite glance does not turn camera")
	rig._update_camera_facing(Vector2.UP, 0.01, true)
	rig._update_camera_facing(Vector2.LEFT, 0.49, true)
	expect(rig._camera_facing == 1, "Neutral aim resets commitment instead of accumulating glances")
	rig._update_camera_facing(Vector2.LEFT, 0.01, true)
	expect(rig._camera_facing == -1, "Continuous 500ms commitment reverses camera")
	rig._update_camera_facing(Vector2.RIGHT, 0.49, true)
	rig._update_camera_facing(Vector2.RIGHT, 0.01, false)
	rig._update_camera_facing(Vector2.RIGHT, 0.49, true)
	expect(rig._camera_facing == -1, "Input loss cancels pending reversal")
	rig._update_camera_facing(Vector2.RIGHT, 0.01, true)
	expect(rig._camera_facing == 1, "Commitment rules are symmetric")
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	rig.add_child(camera)
	var host := PhantomCameraHost.new()
	host.host_layers = 2
	camera.add_child(host)
	for node_name in ["PlayerPCam", "ArrowPCam", "LandingMarker"]:
		var node: Node2D = Node2D.new() if node_name == "LandingMarker" else PhantomCamera2D.new()
		if node is PhantomCamera2D:
			node.host_layers = 2
		node.name = node_name
		rig.add_child(node)
		node.owner = rig
		node.unique_name_in_owner = true
	add_child(rig)
	var player: ArrowPlayer = load("res://player/arrow_player/arrow_player.tscn").instantiate()
	player.set_script(PlayerProbe)
	add_child(player)
	rig.player_pcam.follow_mode = PhantomCamera2D.FollowMode.FRAMED
	rig.arrow_pcam.follow_mode = PhantomCamera2D.FollowMode.GROUP
	rig.player_pcam.zoom = Vector2(3, 3)
	rig.player_pcam.priority = 10
	rig.player_pcam.follow_damping = true
	rig.player_pcam.follow_damping_value = Vector2(0.2, 0.15)
	rig.player_pcam.dead_zone_width = 0.06
	rig.player_pcam.dead_zone_height = 0.28
	rig.set_local_player(player)
	await get_tree().process_frame
	await get_tree().physics_frame
	host.set_physics_process(false)
	host.set_process(false)
	expect(rig.player_pcam.is_active(), "Test exercises active framed follow")
	var width := get_viewport().get_visible_rect().size.x / 3.0
	for fps in [30, 60, 144]:
		for side in [-1, 1]:
			player._update_facing(Vector2(side, 0))
			rig._update_camera_facing(Vector2(side, 0), rig.reversal_hold_time, true)
			rig._update_player_offset()
			for tick in ceili(fps * 0.6):
				rig.player_pcam.process_logic(1.0 / fps)
			var center := rig.player_pcam.get_transform_output().origin
			var ahead: float = 0.5 + side * (center.x - player.position.x) / width
			expect(ahead >= 0.61 and ahead <= 0.69, "Forward view is within 1 percent of target by 0.6s at %s FPS" % fps)
			for tick in ceili(fps * 0.4):
				rig.player_pcam.process_logic(1.0 / fps)
			center = rig.player_pcam.get_transform_output().origin
			ahead = 0.5 + side * (center.x - player.position.x) / width
			expect(ahead >= 0.619 and ahead <= 0.681, "Settled forward view is 62–68 percent")
	var center_before := rig.player_pcam.get_transform_output().origin
	player.position.y -= 40.0
	for tick in 60:
		rig.player_pcam.process_logic(1.0 / 60.0)
	expect(is_equal_approx(rig.player_pcam.get_transform_output().origin.y, center_before.y), "Normal jump fits inside vertical deadzone")
	player.position.y += 400.0
	for tick in 60:
		rig.player_pcam.process_logic(1.0 / 60.0)
	var fall_gap := player.position.y - rig.player_pcam.get_transform_output().origin.y
	expect(fall_gap < get_viewport().get_visible_rect().size.y / 3.0 * 0.2, "Sustained fall remains in view")
	var before := rig.player_pcam.follow_offset
	camera.zoom = Vector2.ONE
	rig._update_player_offset()
	expect(rig.player_pcam.follow_offset == before, "Arrow zoom cannot change player framing offset")
	player.position = Vector2(2000, -800)
	rig.reset_for_relocation(player)
	expect(rig.player_pcam.get_transform_output().origin.is_equal_approx(player.position + before), "Relocation discards old deadzone history")
	rig.landing_marker.position = player.position + Vector2(600, 0)
	rig._set_group(rig.landing_marker)
	rig._following_arrow = true
	rig.arrow_pcam.priority = 20
	expect(rig.arrow_pcam.follow_targets.size() == 2, "Arrow follow frames player and watched target")
	rig._stop_following()
	expect(rig.arrow_pcam.priority == 0 and not rig._following_arrow, "Release restores player camera priority")
	rig.reset_for_relocation(player)
	expect(rig._watch == null and rig.arrow_pcam.follow_targets.is_empty(), "Respawn clears watched arrow state")
	player.queue_free()
	rig.queue_free()
