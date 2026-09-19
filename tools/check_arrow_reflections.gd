extends Node
## Headless combat integration: real player bodies, shields and host ray sweeps.

const START := Vector2(-10000, -10000)
const LAUNCH := Vector2(756, -200)
const STEP := 1.0 / 60.0
var failures := 0
var latest: Arrow
var spawned := 0

func _ready() -> void:
	check.call_deferred()

func expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func on_arrow(arrow: Arrow) -> void:
	latest = arrow
	spawned += 1
	arrow.set_physics_process(false)
	arrow.set_physics_process.call_deferred(false)

func pawn(id: int, team: int, at: Vector2) -> ArrowPlayer:
	var player := World.player_spawner.spawn({"peer_id": id, "team": team}) as ArrowPlayer
	player.set_physics_process(false)
	player.aim_reticle.set_physics_process(false)
	player.position = at
	return player

func shot() -> Arrow:
	return World.projectile_spawner.spawn_arrow({
		"position": START, "velocity": LAUNCH, "owner_id": 11,
		"team": Teams.Team.BLUE, "damage": 25.0,
	})

func travel_until_block() -> void:
	var before := spawned
	for i in range(300):
		if latest._finished or spawned != before:
			return
		latest._physics_process(STEP)

func check() -> void:
	World.projectile_spawner.arrow_spawned.connect(on_arrow)
	var shooter := pawn(11, Teams.Team.BLUE, START)
	var blocker := pawn(22, Teams.Team.ORANGE, Arrow.flight_position(START, LAUNCH, 0.6))
	shooter._start_block(START + LAUNCH)
	blocker._start_block(blocker.position - (LAUNCH + Arrow.GRAVITY * 0.6))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var original := shot()
	expect(original.travel_time_multiplier == 1.5, "Host applies shared 1.5x travel time")
	for bounce in range(6):
		var incoming := latest
		travel_until_block()
		expect(latest != incoming, "Stationary players can reflect bounce %d" % (bounce + 1))
		if latest == incoming:
			break
		expect(latest.origin == START and latest.initial_velocity == LAUNCH, "Reflection preserves original curve")
		expect(latest.flight_direction == -incoming.flight_direction, "Reflection reverses trajectory clock")
		expect(latest.owner_id == (22 if bounce % 2 == 0 else 11), "Reflection transfers ownership")
		expect(latest.team == (blocker.team if bounce % 2 == 0 else shooter.team), "Reflection transfers team")
		var impact_time := latest.elapsed
		expect(impact_time >= minf(incoming._prev_elapsed, incoming.elapsed) and impact_time <= maxf(incoming._prev_elapsed, incoming.elapsed), "Reflection uses within-tick impact time")
		expect(latest.global_position.is_equal_approx(Arrow.flight_position(START, LAUNCH, impact_time)), "Reflection begins on original curve")
		expect(latest.velocity.is_equal_approx((LAUNCH + Arrow.GRAVITY * impact_time) * latest.flight_direction / 1.5), "Reflection has no speed boost")
		latest._physics_process(STEP)
		expect(latest.global_position.is_equal_approx(Arrow.flight_position(START, LAUNCH, impact_time + STEP * latest.flight_direction / 1.5)), "Reflected flight retraces curve")
	expect(spawned == 7, "Six consecutive shield reflections succeed")
	expect(shooter.health.current == shooter.health.max_value and blocker.health.current == blocker.health.max_value, "Timed shields prevent body damage")
	World.projectile_spawner.clear_projectiles()
	shooter._end_block()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before_health := shooter.health.current
	shot()
	travel_until_block()
	travel_until_block()
	expect(latest._finished and shooter.health.current == before_health - 25.0, "Unshielded original shooter takes reflected damage")
	expect(shooter.recent_attackers == [blocker.peer_id], "Reflected damage credits blocker")
	World.projectile_spawner.clear_projectiles()
	before_health = shooter.health.current
	var endpoint_data := {"position": START, "velocity": LAUNCH, "trajectory_time": 0.05,
		"flight_direction": -1, "owner_id": blocker.peer_id, "team": blocker.team, "damage": 25.0}
	var returning := World.projectile_spawner.spawn_arrow(endpoint_data.duplicate())
	returning._physics_process(0.1)
	expect(returning.elapsed == 0.0 and shooter.health.current == before_health - 25.0, "Body collision is resolved before endpoint expiration")
	World.projectile_spawner.clear_projectiles()
	shooter._start_block(START + LAUNCH)
	await get_tree().physics_frame
	await get_tree().physics_frame
	returning = World.projectile_spawner.spawn_arrow(endpoint_data.duplicate())
	returning._physics_process(0.1)
	expect(returning.elapsed == 0.0 and latest != returning and latest.flight_direction == 1 and not latest._finished, "Shield can reflect on the endpoint tick before expiration")
	World.projectile_spawner.clear_projectiles()
	shooter._end_block()
	await get_tree().physics_frame
	await get_tree().physics_frame
	shot()
	travel_until_block()
	shooter.position += Vector2(0, 100)
	await get_tree().physics_frame
	await get_tree().physics_frame
	travel_until_block()
	expect(latest._finished and latest.elapsed == 0.0 and latest.global_position.is_equal_approx(START), "Missed return despawns at original launch point")
	World.projectile_spawner.clear_projectiles()
	blocker.set_network_away(true)
	await get_tree().create_timer(0.4).timeout
	expect(blocker.name_label.text.ends_with(" (AFK)") and is_equal_approx(blocker.sprite.modulate.a, 0.2), "AFK player fades and gains overhead label")
	before_health = blocker.health.current
	var afk_arrow := shot()
	var from := blocker.global_position - Vector2(30, 0)
	var to := blocker.global_position + Vector2(30, 0)
	afk_arrow._sweep(from, to)
	expect(not afk_arrow._finished and blocker.health.current == before_health, "Enemy arrow passes through AFK player without damage or consumption")
	expect(afk_arrow._hit_body(blocker, true) == Arrow.HitOutcome.NONE, "Direct arrow damage also rejects AFK player")
	blocker.network_away = false # Same setter used by server-owned replication.
	await get_tree().create_timer(0.4).timeout
	expect(not blocker.name_label.text.ends_with(" (AFK)") and is_equal_approx(blocker.sprite.modulate.a, 1.0), "Returning restores normal appearance")
	afk_arrow._sweep(from, to)
	expect(afk_arrow._finished and blocker.health.current < before_health, "Returning restores enemy arrow hits")
	World.clear()
	print("ARROW_REFLECTIONS_PASSED" if failures == 0 else "ARROW_REFLECTIONS_FAILED")
	get_tree().quit(1 if failures else 0)
