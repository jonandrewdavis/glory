extends Node
## Godot --headless --path . tools/check_respawns.tscn

var failures := 0
var manager: RespawnManager
var ram: BatteringRam

func _ready() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func ticks(count: int = 2) -> void:
	for i in count:
		await get_tree().physics_frame

func reset_ownership() -> void:
	for band in manager.bands:
		manager.owners[band.band_id] = band.initial_owner
	manager._refresh_bands()
	ram.distance = ram.route_length() * 0.5

func push_to(distance: float) -> void:
	var previous := ram.distance
	ram.distance = distance
	ram.global_position = ram.route_position_at(distance)
	ram.route_advanced.emit(previous, distance, signf(distance - previous))

func at_x(x: float, y: float = -32.0) -> float:
	return ram.route_distance_at(Vector2(x, y))

func _run() -> void:
	manager = World.respawn_manager
	await World.level_loader.spawn_level("Fortress2")
	await ticks()
	World.creep_spawner.set_physics_process(false)
	World.creep_spawner.clear_creeps()
	ram = get_tree().get_first_node_in_group("fortress_rams") as BatteringRam
	ram.set_physics_process(false)
	manager.set_physics_process(false)
	if "--preview" in OS.get_cmdline_user_args():
		await preview()
		World.clear()
		get_tree().quit()
		return
	check_curve()
	check_captures()
	await check_points()
	await check_death()
	await check_lifecycle()
	World.clear()
	await ticks()
	expect(manager.bands.is_empty() and manager.pending.is_empty(), "Session exit clears bands and waits")
	print("Respawn checks completed; failures=", failures)
	get_tree().quit(1 if failures else 0)

func check_curve() -> void:
	for pair in [[0, 2.0], [1, 2.0], [2, 2.0], [15, 5.25], [30, 9.0], [100, 26.5], [1000, 251.5]]:
		expect(is_equal_approx(manager.settings.delay_for_population(pair[0]), pair[1]), "Uncapped population %d => %ss" % [pair[0], pair[1]])

func check_captures() -> void:
	expect(manager.bands.size() == 6, "Six authored bands are loaded")
	expect(manager.active_band(Teams.Team.BLUE).order == 2 and manager.active_band(Teams.Team.ORANGE).order == 5, "Outposts start active")
	push_to(at_x(-608) + 0.1)
	expect(manager.active_band(Teams.Team.ORANGE).order == 5, "Orange cannot capture before the Blue tower threshold")
	push_to(at_x(-608))
	expect(manager.active_band(Teams.Team.ORANGE).order == 4, "Orange captures center-right at the Blue outer tower center")
	push_to(at_x(-500, 0))
	expect(manager.active_band(Teams.Team.ORANGE).order == 5 and manager.owners[&"center_right"] == SpawnBand.NEUTRAL, "Pushing the ram back over a milestone releases that band")
	push_to(at_x(-800))
	expect(manager.active_band(Teams.Team.ORANGE).order == 3, "Orange advances to center-left at its second milestone")
	expect(manager.active_band(Teams.Team.BLUE).order == 1, "Blue falls back to its fortress once the ram is past its outpost")
	push_to(at_x(-700))
	expect(manager.active_band(Teams.Team.ORANGE).order == 4, "Orange loses only center-left when pushed back over its second milestone")
	push_to(0)
	expect(manager.active_band(Teams.Team.ORANGE).order == 2 and manager.active_band(Teams.Team.BLUE).order == 1, "Orange captures the outpost but not Blue's fortress")
	push_to(at_x(-608))
	expect(manager.active_band(Teams.Team.BLUE).order == 2 and manager.active_band(Teams.Team.ORANGE).order == 4, "Blue reclaims its outpost at its own tower")
	push_to(at_x(0))
	expect(manager.active_band(Teams.Team.BLUE).order == 2 and manager.active_band(Teams.Team.ORANGE).order == 5, "A centered ram restores the starting territory")
	push_to(at_x(608))
	expect(manager.active_band(Teams.Team.BLUE).order == 3 and manager.active_band(Teams.Team.ORANGE).order == 5, "Blue captures center-left at Orange's tower")
	push_to(at_x(800))
	expect(manager.active_band(Teams.Team.BLUE).order == 4, "Blue captures center-right at its second milestone")
	push_to(at_x(700))
	expect(manager.active_band(Teams.Team.BLUE).order == 3 and manager.active_band(Teams.Team.ORANGE).order == 6, "Blue loses center-right when pushed back over its second milestone")
	push_to(ram.route_length())
	expect(manager.active_band(Teams.Team.BLUE).order == 5 and manager.active_band(Teams.Team.ORANGE).order == 6, "Blue captures the outpost but not Orange's fortress")
	push_to(at_x(608))
	expect(manager.active_band(Teams.Team.BLUE).order == 3 and manager.active_band(Teams.Team.ORANGE).order == 5, "Orange reclaims its outpost at its own tower")
	check_contiguous()
	reset_ownership()
	push_to(ram.route_length())
	expect(manager.active_band(Teams.Team.BLUE).order == 5, "One large movement processes all crossed milestones")
	var owners := manager.owners.duplicate()
	ram.route_advanced.emit(ram.distance, ram.distance, -1)
	expect(owners == manager.owners, "A stationary ram cannot capture")
	World.round_manager.phase = RoundManager.Phase.ENDED
	push_to(0)
	expect(owners == manager.owners, "Round-end freezes capture decisions")
	World.round_manager.phase = RoundManager.Phase.PLAYING
	reset_ownership()

## Sweeps the whole route both ways: Blue must hold a prefix and Orange a suffix.
func check_contiguous() -> void:
	var valid := true
	var steps := 400
	for i in range(0, steps * 2 + 1):
		var t := float(i if i <= steps else steps * 2 - i) / steps
		push_to(t * ram.route_length())
		valid = valid and is_contiguous(manager.owners) and manager.owners == manager.owners_at(ram.distance)
	expect(valid, "Blue and Orange bands never interleave anywhere on the route, in either direction")
	var saved: Dictionary = manager._thresholds.duplicate(true)
	manager._thresholds[&"center_left"] = {Teams.Team.BLUE: 0.0, Teams.Team.ORANGE: -1.0}
	manager._thresholds[&"blue_outpost"] = {Teams.Team.BLUE: -1.0, Teams.Team.ORANGE: ram.route_length()}
	expect(is_contiguous(manager.owners_at(ram.route_length() * 0.5)), "Misauthored milestones still cannot interleave teams")
	manager._thresholds = saved

func is_contiguous(owners: Dictionary) -> bool:
	var sequence: Array = manager.bands.map(func(band: SpawnBand) -> int: return owners[band.band_id])
	var last_blue := sequence.rfind(Teams.Team.BLUE)
	var first_orange := sequence.find(Teams.Team.ORANGE)
	for i in sequence.size():
		if sequence[i] != Teams.Team.BLUE and i < last_blue:
			return false
		if sequence[i] != Teams.Team.ORANGE and first_orange != -1 and i > first_orange:
			return false
	return true

func check_points() -> void:
	var pawn := CharacterBody2D.new()
	pawn.collision_mask = 33
	var collider := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 7.2
	shape.height = 19.2
	collider.shape = shape
	pawn.add_child(collider)
	add_child(pawn)
	for band in manager.bands:
		for marker in band.spawn_markers():
			var point := marker.global_position
			expect(manager._point_clear(point), "%s/%s clears terrain" % [band.band_id, marker.name])
			pawn.position = point
			pawn.velocity = Vector2.ZERO
			for i in 40:
				await get_tree().physics_frame
				pawn.velocity.y += 980.0 / 60
				pawn.move_and_slide()
			expect(pawn.is_on_floor() and pawn.position.distance_to(point) < 20, "%s/%s lands on nearby walkable ground" % [band.band_id, marker.name])
	pawn.free()
	var burst_valid := true
	for i in 120:
		var point := manager.spawn_position(Teams.Team.ORANGE)
		burst_valid = burst_valid and manager.active_band(Teams.Team.ORANGE).bounds.has_point(manager.active_band(Teams.Team.ORANGE).to_local(point))
	expect(burst_valid, "120 respawns reuse safe points inside the active band without queuing")
	var active := manager.active_band(Teams.Team.ORANGE)
	var container := active.get_node("Points")
	active.remove_child(container)
	var fallback := manager.spawn_position(Teams.Team.ORANGE)
	expect(manager.bands[5].bounds.has_point(manager.bands[5].to_local(fallback)), "Missing points fall back to permanent fortress")
	active.add_child(container)

func check_death() -> void:
	reset_ownership()
	World.player_spawner.spawn_player(1)
	World.player_spawner.spawn_player(2)
	await ticks()
	var blue := World.player_spawner.get_player(1)
	var orange := World.player_spawner.get_player(2)
	blue.set_physics_process(false)
	orange.set_physics_process(false)
	blue.position = Vector2(-1200, -176)
	ram.distance = at_x(-608) + 0.5
	ram.position = Vector2(-607, -32)
	orange.position = ram.position
	ram._physics_process(0.1)
	expect(manager.active_band(Teams.Team.ORANGE).order == 4, "Real ram physics advances Orange's active band")
	reset_ownership()
	orange.health.take_damage(orange.health.current, blue)
	expect(manager.pending.has(2) and manager.seconds_left(2) == 2.0, "Death schedules a two-second wait for a small team")
	var old_serial := orange.spawn_serial
	for id in range(10, 24):
		World.scoreboard.entries[id] = {"team": Teams.Team.ORANGE, "kills": 0, "deaths": 0, "assists": 0}
	expect(manager.seconds_left(2) == 2.0 and manager.settings.delay_for_population(World.scoreboard.team_size(Teams.Team.ORANGE)) == 5.25, "Joining players do not change an existing death deadline")
	manager.schedule(orange)
	expect(manager.pending.size() == 1, "Duplicate death scheduling does not reset the wait")
	push_to(at_x(-608))
	manager._physics_process(1.99)
	expect(World.player_spawner.get_player(2) == orange, "No early respawn")
	manager._physics_process(0.02)
	var replacement := World.player_spawner.get_player(2)
	replacement.set_physics_process(false)
	expect(replacement != orange and replacement.spawn_serial != old_serial and replacement.health.is_alive(), "Server replaces the dead incarnation at expiry")
	expect(manager.bands[3].bounds.has_point(manager.bands[3].to_local(replacement.global_position)), "Orange respawns in newly captured center-right, not its old tower")
	expect(World.scoreboard.entries[2].deaths == 1 and World.scoreboard.entries[1].kills == 1, "Replacement preserves kills and deaths")
	replacement.server_fire(Vector2.LEFT, 0, replacement.minimum_preparation_time(0))
	var arrow := Arrow.new()
	arrow.setup({"position": Vector2.ZERO, "velocity": Vector2.RIGHT * 100, "team": Teams.Team.BLUE})
	World.projectile_spawner.reflect_arrow(arrow, replacement, Vector2.ZERO)
	arrow.free()
	blue.health.take_damage(blue.health.current, replacement)
	var before := blue.team
	# Allow switching by removing the synthetic population first.
	for id in range(10, 24):
		World.scoreboard.entries.erase(id)
	World.scoreboard._server_switch(1, Teams.Team.ORANGE)
	expect(World.player_spawner.get_player(1) == blue and blue.team == before and "after respawning" in World.scoreboard.switch_message, "Dead players cannot bypass their wait by switching teams")
	World.player_spawner.remove_player(1)
	expect(not manager.pending.has(1), "Disconnect cancels a pending respawn")
	World.player_spawner.clear_players()
	World.scoreboard.clear()
	World.projectile_spawner.clear_projectiles()
	await ticks()

func check_lifecycle() -> void:
	push_to(ram.route_length())
	await World.level_loader.spawn_level("Fortress2")
	await ticks()
	expect(manager.active_band(Teams.Team.BLUE).order == 2 and manager.active_band(Teams.Team.ORANGE).order == 5, "Level reload resets ownership before respawning")
	var before := manager.owners.duplicate()
	manager._sync_state(World.level_loader.revision - 1, {}, {})
	expect(manager.owners == before, "Stale ownership snapshots cannot affect a new map")
	await World.level_loader.spawn_level("Fortress1")
	await ticks()
	expect(manager.bands.is_empty(), "Legacy maps work without band definitions")
	expect(manager.spawn_position(Teams.Team.BLUE, 0) == Teams.spawn_position(get_tree(), Teams.Team.BLUE, 0), "Legacy map uses its original spawn markers")

func preview() -> void:
	get_window().size = Vector2i(1536, 864)
	var camera := Camera2D.new()
	camera.position = Vector2(0, -140)
	camera.zoom = Vector2(0.55, 0.55)
	add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := preload("res://scenes/gameplay/ui/round_hud.tscn").instantiate()
	layer.add_child(hud)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/respawn-bands-initial.png")
	World.scoreboard.entries[99] = {"team": Teams.Team.BLUE, "kills": 0, "deaths": 0, "assists": 0}
	World.player_spawner.spawn_player(1)
	var player := World.player_spawner.get_player(1)
	player.set_physics_process(false)
	var source := ArrowPlayer.new()
	source.peer_id = 99
	source.team = Teams.Team.BLUE
	player.health.take_damage(player.health.current, source)
	source.free()
	push_to(at_x(-608))
	World.camera_rig.clear()
	camera.make_current()
	for i in 16:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/respawn-bands-captured.png")
	print("Saved /tmp/respawn-bands-initial.png and /tmp/respawn-bands-captured.png")
