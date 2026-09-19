extends Node
const PORT := 19749
var failures := 0
var running := false
var reported := false
var started := 0.0
var pawn: ArrowPlayer
var confirmations := 0
var report: Dictionary = {}

func _ready() -> void:
	start.call_deferred()

func expect(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func start() -> void:
	started = CombatNetwork.now()
	MultiplayerService.set_backend(MultiplayerService.BackendType.ENET, false)
	var host := "--server" in OS.get_cmdline_user_args()
	var socket := "--transport=ws" in OS.get_cmdline_user_args()
	var peer: MultiplayerPeer
	if socket:
		var ws := WebSocketMultiplayerPeer.new()
		assert((ws.create_server(PORT) if host else ws.create_client("ws://127.0.0.1:%d" % PORT)) == OK)
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		assert((enet.create_server(PORT, 4) if host else enet.create_client("127.0.0.1", PORT)) == OK)
		peer = enet
	multiplayer.multiplayer_peer = peer
	World.projectile_spawner.arrow_spawned.connect(func(_arrow: Arrow) -> void: confirmations += 1)
	if host:
		MultiplayerService.in_lobby = true
		MultiplayerService.backend.joinable = true
		await World.level_loader.spawn_level("Fortress1")
		World.player_spawner.spawn_player(1)
		pawn = World.player_spawner.get_player(1)
		pawn.set_physics_process(false)
		pawn.global_position = Vector2(-10000, -10000)

func _process(_delta: float) -> void:
	if CombatNetwork.now() - started > 18.0:
		push_error("Pipeline timed out")
		get_tree().quit(1)
	if multiplayer.is_server():
		if is_instance_valid(pawn):
			pawn.global_position.x = -10000.0 + sin(CombatNetwork.now()) * 30.0
		return
	if not running and World.combat_network.epoch != 0 and World.player_spawner.get_player(1) != null:
		running = true
		check_client()

func check_client() -> void:
	pawn = World.player_spawner.get_player(multiplayer.get_unique_id())
	pawn.set_physics_process(false)
	pawn.aim_reticle.set_physics_process(false)
	pawn.global_position = Vector2(-11000, -10000)
	pawn.aim_reticle.set_direction(Vector2.UP)
	await get_tree().create_timer(0.4).timeout
	var remote := World.player_spawner.get_player(1)
	expect(remote.presentation.samples.size() >= 2, "Remote player receives interpolation history")
	expect(remote.visual_root.global_position.distance_to(remote.global_position) < 10.0, "Remote presentation has bounded view age")
	var own_position := pawn.global_position
	pawn._prepare(0.0, own_position + Vector2.UP)
	await get_tree().create_timer(pawn.minimum_preparation_time(0) + 0.1).timeout
	pawn.preparation_time = pawn.minimum_preparation_time(0)
	pawn._fire(own_position + Vector2.UP)
	expect(World.projectile_spawner._ghosts.size() == 1, "Local launch creates a ghost immediately")
	var ghost: Arrow = World.projectile_spawner._ghosts.values()[0]
	var handle := ghost.get_instance_id()
	await get_tree().create_timer(0.5).timeout
	expect(confirmations == 1 and World.projectile_spawner._ghosts.is_empty(), "One authoritative confirmation replaces prediction")
	expect(World.projectile_spawner._visuals.size() == 1 and World.projectile_spawner._visuals.values()[0].get_instance_id() == handle, "Network handoff keeps the camera handle")
	expect(pawn.global_position == own_position, "Server snapshots never overwrite owner movement")
	pawn._start_block(own_position + Vector2.UP)
	await get_tree().create_timer(0.15).timeout
	_request_report.rpc_id(1)
	await get_tree().create_timer(0.15).timeout
	expect(report.get("blocking", false), "Shield command activates server collision")
	expect(report.get("position", Vector2.ZERO) == own_position, "Server uses submitted owner position")
	await get_tree().create_timer(0.75).timeout
	_request_report.rpc_id(1)
	await get_tree().create_timer(0.15).timeout
	expect(not report.get("blocking", true), "Server expires shield with owner physics stopped")
	expect(int(report.get("samples", 0)) >= 30, "Upstream movement remains independently sampled")
	var count: int = report.get("snapshots", 0)
	expect(count >= 30 and count <= 100, "Server emits scheduled aggregate snapshots")
	World.combat_network.request_baseline()
	await get_tree().create_timer(0.25).timeout
	expect(confirmations == 1, "Recovery baseline cannot duplicate a live projectile")
	_finish.rpc_id(1, failures)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(1 if failures else 0)

@rpc("any_peer", "call_remote", "reliable")
func _request_report() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var player := World.player_spawner.get_player(id)
	_report.rpc_id(id, {"blocking": player.server_blocking, "position": player.global_position,
		"samples": World.combat_network.metrics.owner_samples, "snapshots": World.combat_network.metrics.snapshots})

@rpc("authority", "call_remote", "reliable")
func _report(value: Dictionary) -> void:
	report = value

@rpc("any_peer", "call_remote", "reliable")
func _finish(client_failures: int) -> void:
	if multiplayer.is_server():
		await get_tree().create_timer(0.4).timeout
		get_tree().quit(1 if client_failures else 0)
