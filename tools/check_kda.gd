extends Node
## Godot --headless --path . tools/check_kda.tscn
var failures := 0
var events: Array[Dictionary] = []
var players: Array[ArrowPlayer] = []
var panel: Control
var feed: Control
var hud: RoundHud
var health_hud: PlayerHealthBar

func _ready() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	print("PASS: " if condition else "FAIL: ", message)
	if not condition:
		failures += 1
		push_error(message)

func fresh_victim() -> ArrowPlayer:
	var victim := players[4]
	World.respawn_manager.cancel(victim.peer_id)
	victim.health.respawn()
	return victim

func _run() -> void:
	await World.level_loader.spawn_level("Fortress2")
	World.creep_spawner.set_physics_process(false)
	World.creep_spawner.clear_creeps()
	World.respawn_manager.set_physics_process(false)
	var ram := get_tree().get_first_node_in_group("fortress_rams")
	ram.set_physics_process(false)
	for id in range(1, 6):
		World.scoreboard.entries[id] = {"team": Teams.Team.ORANGE if id == 5 else Teams.Team.BLUE, "kills": 0, "deaths": 0, "assists": 0}
		World.player_spawner.spawn_player(id)
		var player := World.player_spawner.get_player(id)
		player.set_physics_process(false)
		players.append(player)
	World.scoreboard.player_killed.connect(func(event: Dictionary) -> void: events.append(event))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(screen)
	panel = load("res://scenes/gameplay/ui/score_panel.tscn").instantiate()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -344
	panel.offset_right = -24
	panel.offset_top = 24
	screen.add_child(panel)
	feed = load("res://scenes/gameplay/ui/kill_feed.tscn").instantiate()
	screen.add_child(feed)
	feed.set_process(false)
	hud = load("res://scenes/gameplay/ui/round_hud.tscn").instantiate()
	screen.add_child(hud)
	health_hud = load("res://scenes/gameplay/ui/player_health_bar.tscn").instantiate()
	health_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(health_hud)
	var victim := players[4]
	victim.health.take_damage(10, players[0])
	victim.health.take_damage(10, players[1])
	victim.health.take_damage(10, players[0])
	expect(victim.recent_attackers == [1, 2], "Repeated attacker moves to front without duplicates")
	victim.health.heal(100)
	expect(victim.recent_attackers == [1, 2], "Healing retains whole-life history")
	victim.health.take_damage(200, players[2])
	var board := World.scoreboard
	expect(board.entries[3].kills == 1 and board.entries[1].assists == 1 and board.entries[2].assists == 1 and board.entries[5].deaths == 1, "Lethal attacker gets kill; two recent attackers get assists")
	expect(board.entries[3].assists == 0 and victim.recent_attackers.is_empty(), "Killer receives no assist and victim history clears")
	expect(events.size() == 1 and events[0].killer_id == 3 and events[0].victim_id == 5, "One player kill event has lethal source")
	victim.health.take_damage(200, players[0])
	expect(events.size() == 1 and board.entries[5].deaths == 1, "Damage after death cannot award duplicate stats or events")
	victim = fresh_victim()
	for source in players.slice(0, 4):
		victim.health.take_damage(1, source)
	expect(victim.recent_attackers == [4, 3, 2], "Fourth distinct attacker evicts oldest")
	victim.health.take_damage(200, players[3])
	expect(board.entries[4].kills == 1 and board.entries[3].assists == 1 and board.entries[2].assists == 2 and board.entries[1].assists == 1, "Evicted attacker receives no assist")
	victim = fresh_victim()
	victim.health.take_damage(10, players[0])
	players[0].health.take_damage(200, victim)
	var before_assists: int = board.entries[1].assists
	victim.health.take_damage(200, players[1])
	expect(board.entries[1].assists == before_assists + 1, "Dead but connected attacker still receives assist")
	players[0].health.respawn()
	World.respawn_manager.cancel(1)
	victim = fresh_victim()
	expect(not victim.health.take_damage(0, players[0]) and not victim.health.take_damage(-1, players[0]) and victim.recent_attackers.is_empty(), "Zero/negative damage cannot enter history")
	expect(not players[0].health.take_damage(10, players[1]) and players[0].recent_attackers.is_empty(), "Friendly damage rejects attribution")
	victim.health.take_damage(10, players[0])
	board.remove_player(1)
	expect(victim.recent_attackers.is_empty(), "Disconnect removes attacker from outstanding histories")
	board.entries[1] = {"team": Teams.Team.BLUE, "kills": 0, "deaths": 0, "assists": 0}
	victim.health.take_damage(10, players[0])
	board._server_switch(1, Teams.Team.ORANGE)
	expect(board.get_team(1) == Teams.Team.ORANGE and victim.recent_attackers.is_empty(), "Team switch removes attacker from outstanding histories")
	await get_tree().process_frame
	health_hud._process(0)
	expect(health_hud._health == World.player_spawner.get_player(1).health, "Local health HUD follows player replacement")
	var before := board.entries.duplicate(true)
	board.record_kill(2, 0)
	expect(board.entries == before, "Non-player victim grants no stats")
	board.record_kill(2, 5, [2, 2, 5, 1, 3, 3, 4])
	expect(board.entries[3].assists == int(before[3].assists) + 1 and board.entries[4].assists == int(before[4].assists) + 1 and board.entries[1].assists == before[1].assists, "Assist validation excludes killer, victim, duplicates and teammates")
	var event_count := events.size()
	board._sync_combat({}, events.back())
	expect(events.size() == event_count, "Duplicate kill event is ignored")
	for i in 7:
		board.record_kill(2, 5)
	await get_tree().process_frame
	expect(feed._feed.size() == 5, "Kill feed retains only five newest entries")
	var line: Label = feed._feed[0].line
	expect(line.text == "%s killed %s" % [MultiplayerService.get_username(2), MultiplayerService.get_username(5)] and line.modulate == Teams.color(Teams.Team.BLUE), "Feed contains plain killer/victim text colored by killer team")
	feed._process(7.5)
	expect(is_equal_approx(line.modulate.a, 0.5), "Feed fades during its final second")
	feed._process(0.6)
	expect(feed._feed.is_empty(), "Feed expires after eight seconds")
	expect(not hud.score_label.visible and not hud.get_node("RespawnHud").visible, "Round score and converted respawn UI remain hidden")
	var respawns := hud.get_node("RespawnHud")
	expect(respawns.get_node("Zones").get_child_count() == 6, "Hidden respawn UI contains six working node-based zones")
	for band in World.respawn_manager.bands:
		expect(not band.visible and band.get_node("SpawnFlag").position == band.flag_position, "Converted world spawn flags stay hidden and positioned")
	victim = fresh_victim()
	victim.health.take_damage(10, players[1])
	victim.health.respawn()
	expect(victim.recent_attackers.is_empty(), "Explicit respawn clears history even while alive")
	var replication: SceneReplicationConfig = players[1].get_node("MultiplayerSynchronizer").replication_config
	expect(not replication.has_property(NodePath("ReadinessIndicator:display_state")), "Charge indicator is local and never replicated")
	var indicator := players[1].readiness_indicator
	indicator.display_state = Vector4(2, 1, 0.5, 1)
	indicator._process(0)
	expect(indicator.get_node("Progress") is TextureProgressBar and is_equal_approx(indicator.get_node("Progress").value, 0.5), "Charge snapshot drives radial progress node")
	board.record_kill(5, 2)
	expect(feed._feed[0].line.modulate == Teams.color(Teams.Team.ORANGE), "Orange kills use Orange team color")
	MultiplayerService.in_lobby = true
	var actual_ui: UILayer = load("res://scenes/gameplay/ui/ui_layer.tscn").instantiate()
	add_child(actual_ui)
	await get_tree().process_frame
	expect(actual_ui.get_node("PauseLayer/PauseRoot/PlayersPanel/ScorePanel").get_node("%Rows").get_child_count() == board.entries.size() + 2, "Pause layer scoreboard shows all player rows")
	expect(not actual_ui.get_node("PlayerUI/HudRoot/RoundHud/RespawnHud").visible, "Integrated gameplay UI keeps respawns hidden")
	actual_ui.hide()
	if "--preview" in OS.get_cmdline_user_args():
		await preview()
	actual_ui.queue_free()
	World.ui_layer = null
	MultiplayerService.in_lobby = false
	World.clear()
	await get_tree().process_frame
	expect(feed._feed.is_empty(), "Session clear removes feed")
	expect(not respawns.visible and not hud.score_label.visible, "Reset does not reveal hidden UI")
	canvas.queue_free()
	await get_tree().process_frame
	print("KDA checks completed; failures=", failures)
	get_tree().quit(1 if failures else 0)

func preview() -> void:
	get_window().size = Vector2i(1280, 720)
	var screen: Control = panel.get_parent()
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var ui_scale := 2.0 if "--large-ui" in OS.get_cmdline_user_args() else 1.25
	screen.scale = Vector2.ONE * ui_scale
	screen.size = get_viewport().get_visible_rect().size / ui_scale
	World.camera_rig.set_local_player(World.player_spawner.get_player(1))
	for id in range(6, 30):
		World.scoreboard.entries[id] = {"team": id % 2, "kills": id, "deaths": id / 2, "assists": 2}
	MultiplayerService.usernames[28] = "A very long player name to check truncation"
	panel._update_rows()
	for i in 3:
		World.scoreboard.record_kill(2, 5)
	for frame in 4:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/glory-ui-large-preview.png" if "--large-ui" in OS.get_cmdline_user_args() else "/tmp/glory-ui-preview.png")
