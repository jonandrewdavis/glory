extends Node
## Godot --headless --path . tools/check_rounds.tscn

var world: Node
var failures := 0
var _serial := 200000

func _ready() -> void:
	call_deferred("_check")

func get_nodes_in_group(group: StringName) -> Array[Node]:
	return get_tree().get_nodes_in_group(group)

func expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)

func ticks(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame

func soldier(team: int, at: Vector2, goal: float = 0.0) -> Creep:
	_serial += 1
	return world.creep_spawner.spawn({"serial": _serial, "team": team, "position": at, "goal_x": goal}) as Creep

func gate(team: int) -> FortressGate:
	for node in get_nodes_in_group("fortress_gates"):
		if node is FortressGate and node.team == team:
			return node
	return null

func ram() -> BatteringRam:
	return get_nodes_in_group("fortress_rams")[0] as BatteringRam

func reset_creeps() -> void:
	world.creep_spawner.clear_creeps()
	await ticks(2)

func _check() -> void:
	world = get_tree().root.get_node("World")
	Engine.physics_ticks_per_second = 6000
	Engine.time_scale = 100.0
	Engine.max_physics_steps_per_frame = 1000
	world.creep_spawner.set_physics_process(false)
	await world.level_loader.spawn_level("Fortress2")
	await ticks(4)
	await reset_creeps()
	await check_gates()
	await check_arrows()
	await check_validation()
	await check_creeps_vs_gate()
	await check_ram()
	await check_round_end()
	await check_hud()
	world.clear()
	await ticks(2)
	var rounds: RoundManager = world.round_manager
	expect(rounds.wins_for(Teams.Team.BLUE) == 0 and rounds.phase == RoundManager.Phase.PLAYING and rounds.round_number == 0, "Session clear resets round state")
	expect(get_nodes_in_group("fortress_gates").is_empty() and get_nodes_in_group("fortress_rams").is_empty(), "Session clear removes gates and ram")
	print("Round checks completed; failures=", failures)
	get_tree().quit(1 if failures else 0)

func check_gates() -> void:
	var blue := gate(Teams.Team.BLUE)
	var orange := gate(Teams.Team.ORANGE)
	expect(blue != null and orange != null and get_nodes_in_group("fortress_gates").size() == 2, "Two fortress gates, one per team")
	expect(blue.health.current == 5000.0 and orange.health.current == 5000.0 and blue.health.max_value == 5000.0, "Gates start at 5000 HP")
	expect(blue.collision_layer == FortressGate.LAYER and blue.collision_mask == 0, "Gates sit on the gates layer with no mask")
	expect(blue.hitbox().has_point(Vector2(-1030, -200)) and not blue.hitbox().has_point(Vector2(-1000, -200)), "Gate hitbox covers the timber facade only")
	var rounds: RoundManager = world.round_manager
	expect(rounds.phase == RoundManager.Phase.PLAYING and rounds.round_number == 1 and rounds.wins_for(Teams.Team.BLUE) == 0 and rounds.wins_for(Teams.Team.ORANGE) == 0, "Level load starts round one")
	# The gate stays walkable: a body that even masks the gates layer passes.
	var pawn := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(12, 16)
	pawn.add_child(shape)
	pawn.collision_layer = 0
	pawn.collision_mask = 1 | FortressGate.LAYER
	add_child(pawn)
	pawn.global_position = Vector2(990, -176)
	for i in range(30):
		pawn.velocity = Vector2(300, 0)
		pawn.move_and_slide()
		await get_tree().physics_frame
	expect(pawn.global_position.x > 1060, "Bodies walk through the gate facade")
	pawn.free()

func check_arrows() -> void:
	world.player_spawner.spawn_player(1)
	var player: ArrowPlayer = world.player_spawner.get_player(1)
	player.set_physics_process(false)
	player.team = Teams.Team.BLUE
	# Parked far from the ram so the archer never pushes it.
	player.position = Vector2(-1200, -176)
	var orange := gate(Teams.Team.ORANGE)
	var blue := gate(Teams.Team.BLUE)
	var sounds: Array[bool] = []
	var listener := func(headshot: bool) -> void: sounds.append(headshot)
	world.projectile_spawner.hit_sound_played.connect(listener)
	await ticks(2)
	var arrow: Arrow = world.projectile_spawner.spawn_arrow({"position": Vector2(960, -208), "velocity": Vector2(600, 0), "owner_id": 1, "team": Teams.Team.BLUE, "damage": 35.0})
	await ticks(10)
	expect(orange.health.current == 4965.0 and not is_instance_valid(arrow), "Enemy arrow damages the gate once")
	expect(orange.stuck_arrows.get_child_count() == 1, "Arrow sticks in the gate")
	expect(sounds == [false], "Gate hit clicks for the shooter")
	expect(world.scoreboard.entries[1].kills == 0, "Gate damage grants no kill")
	world.projectile_spawner.spawn_arrow({"position": Vector2(-960, -208), "velocity": Vector2(-600, 0), "owner_id": 1, "team": Teams.Team.BLUE, "damage": 35.0})
	await ticks(10)
	expect(blue.health.current == 5000.0 and blue.stuck_arrows.get_child_count() == 0, "Friendly arrow passes through the friendly gate")
	world.projectile_spawner.hit_sound_played.disconnect(listener)

func check_validation() -> void:
	var orange := gate(Teams.Team.ORANGE)
	var blue := gate(Teams.Team.BLUE)
	var player: ArrowPlayer = world.player_spawner.get_player(1)
	var blue_creep := soldier(Teams.Team.BLUE, Vector2(-50, 88), -50)
	var orange_creep := soldier(Teams.Team.ORANGE, Vector2(50, 88), 50)
	blue_creep.set_physics_process(false)
	orange_creep.set_physics_process(false)
	await ticks(2)
	var before := orange.health.current
	expect(not orange.health.take_damage(100.0, null) and orange.health.current == before, "Unattributed gate damage is rejected")
	expect(not orange.health.take_damage(100.0, orange_creep) and orange.health.current == before, "Friendly soldier cannot damage its own gate")
	expect(not blue.health.take_damage(100.0, player) and blue.health.current == 5000.0, "Friendly archer cannot damage their own gate")
	orange.health._request_damage(100.0, blue_creep.get_path())
	expect(orange.health.current == before, "Network damage request cannot damage a gate")
	expect(orange.health.take_damage(100.0, blue_creep) and orange.health.current == before - 100.0, "Enemy soldier damages the gate")
	expect(orange.health.take_damage(100.0, ram()) and orange.health.current == before - 200.0, "The ram damages a gate")
	await reset_creeps()

func check_creeps_vs_gate() -> void:
	var orange := gate(Teams.Team.ORANGE)
	var before := orange.health.current
	var attacker := soldier(Teams.Team.BLUE, Vector2(1006, -176), 1006)
	await ticks(300)
	expect(attacker._target == orange and orange.health.current < before, "A soldier at the enemy gate strikes it")
	var defender := soldier(Teams.Team.ORANGE, Vector2(1030, -176), 1030)
	await ticks(10)
	expect(attacker._target == defender, "Enemy soldiers take priority over the gate (target %s)" % attacker._target)
	await reset_creeps()

func check_ram() -> void:
	var r := ram()
	var orange := gate(Teams.Team.ORANGE)
	expect(is_equal_approx(r.speed, 14.0), "Ram speed lowered to 14")
	expect(is_equal_approx(r.progress(), 0.5), "Ram starts mid-route")
	r.distance = r.route_length()
	await ticks(2)
	expect(r.attack_state == BatteringRam.AttackState.WINDUP and is_equal_approx(r.progress(), 1.0), "Reaching the gate starts the wind-up")
	await ticks(238)
	expect(absf(r.attack_progress - 0.5) < 0.05 and r.distance == r.route_length(), "Wind-up fills over eight seconds while the ram holds")
	r.distance -= 10.0
	await ticks(2)
	expect(r.attack_state == BatteringRam.AttackState.IDLE and r.attack_progress == 0.0, "Leaving the gate resets the wind-up")
	r.distance = r.route_length()
	await ticks(484)
	expect(r.attack_state == BatteringRam.AttackState.STRIKE, "Eight seconds of contact begins a strike")
	world.player_spawner.spawn_player(2)
	var pusher: ArrowPlayer = world.player_spawner.get_player(2)
	pusher.set_physics_process(false)
	pusher.team = Teams.Team.ORANGE
	pusher.position = r.position
	await ticks(30)
	expect(r.direction == -1 and r.distance == r.route_length() and r.attack_state == BatteringRam.AttackState.STRIKE, "A strike locks the ram against the gate")
	var before := orange.health.current
	await ticks(212)
	expect(orange.health.current == before - 500.0, "A strike lands 500 damage after four seconds")
	expect(r.attack_state != BatteringRam.AttackState.STRIKE and r.distance < r.route_length(), "After the strike the ram moves again")
	# A peer-less remote player never teleports itself, so drop it before the reload.
	world.player_spawner.remove_player(2)
	r.distance = r.route_length() * 0.5
	await ticks(2)
	expect(r.attack_state == BatteringRam.AttackState.IDLE, "Ram mid-route is idle")

func check_round_end() -> void:
	var rounds: RoundManager = world.round_manager
	var orange := gate(Teams.Team.ORANGE)
	var blue := gate(Teams.Team.BLUE)
	var old_player: ArrowPlayer = world.player_spawner.get_player(1)
	world.scoreboard.record_kill(1, 0)
	var kills: int = world.scoreboard.entries[1].kills
	var blue_creep := soldier(Teams.Team.BLUE, Vector2(-50, 88), -50)
	blue_creep.set_physics_process(false)
	await ticks(2)
	var winners: Array[int] = []
	rounds.round_ended.connect(func(winner: int) -> void: winners.append(winner))
	orange.health.take_damage(orange.health.current, blue_creep)
	expect(rounds.phase == RoundManager.Phase.ENDED and rounds.winner == Teams.Team.BLUE, "Breaching the orange gate ends the round for blue")
	expect(rounds.wins_for(Teams.Team.BLUE) == 1 and rounds.wins_for(Teams.Team.ORANGE) == 0 and winners == [Teams.Team.BLUE], "Blue leads 1 - 0")
	var blue_creep_2 := soldier(Teams.Team.ORANGE, Vector2(50, 88), 50)
	blue_creep_2.set_physics_process(false)
	blue.health.take_damage(blue.health.current, blue_creep_2)
	expect(rounds.wins_for(Teams.Team.ORANGE) == 0, "A second breach during the banner changes nothing")
	world.creep_spawner.set_physics_process(true)
	for i in range(4000):
		await get_tree().physics_frame
		if rounds.phase == RoundManager.Phase.PLAYING and rounds.round_number == 2 and world.level_loader.is_level_ready():
			break
	await ticks(4)
	expect(rounds.phase == RoundManager.Phase.PLAYING and rounds.round_number == 2, "A new round starts after the banner")
	expect(rounds.wins_for(Teams.Team.BLUE) == 1, "Round wins persist into the next round")
	var fresh := gate(Teams.Team.ORANGE)
	expect(fresh != null and fresh != orange and fresh.health.current == 5000.0 and gate(Teams.Team.BLUE).health.current == 5000.0, "Gates are rebuilt at full health")
	var r := ram()
	expect(is_equal_approx(r.distance, r.route_length() * 0.5) and r.attack_state == BatteringRam.AttackState.IDLE, "Ram returns to the centre (distance %s of %s, state %s, direction %d)" % [r.distance, r.route_length(), r.attack_state, r.direction])
	expect(get_nodes_in_group("creeps").size() == 6, "A fresh creep wave spawns")
	var player: ArrowPlayer = world.player_spawner.get_player(1)
	expect(player != null and player != old_player and player.health.current == player.health.max_value, "Players are re-spawned with full health")
	expect(player.global_position.distance_to(Teams.spawn_position(get_tree(), player.team, player.spawn_index)) < 4.0, "Players return to their team spawn")
	expect(world.scoreboard.entries[1].kills == kills, "Kill scoreboard persists across rounds")
	world.creep_spawner.set_physics_process(false)
	await reset_creeps()

func check_hud() -> void:
	var hud: RoundHud = preload("res://scenes/gameplay/ui/round_hud.tscn").instantiate()
	add_child(hud)
	hud.update_labels()
	expect("1 - 0" in hud.score_label.text and not hud.banner_label.visible, "HUD shows the round score without a banner while playing")
	var rounds: RoundManager = world.round_manager
	rounds._sync_round(rounds.wins, RoundManager.Phase.ENDED, Teams.Team.BLUE, rounds.round_number)
	expect(hud.banner_label.visible and "wins the round" in hud.banner_label.text and hud.banner_label.modulate == Teams.color(Teams.Team.BLUE), "HUD shows the winner banner")
	rounds._sync_round(rounds.wins, RoundManager.Phase.PLAYING, -1, rounds.round_number)
	expect(not hud.banner_label.visible, "Banner hides when play resumes")
	hud.free()
