extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena := ArenaBounds.new()
	add_child(arena)
	assert(arena.clearance(Vector3.ZERO) == 300.0)
	assert(arena.clearance(Vector3(1201, 0, 0)) < 0.0)
	assert(arena.clearance(Vector3(0, -301, 0)) < 0.0)
	assert(arena.clearance(Vector3(0, 1201, 0)) < 0.0)
	assert(arena.clearance(Vector3(900, 0, 900)) < 0.0)
	assert(arena.clearance(arena.return_position()) > 0.0)
	arena.position = Vector3(100, 200, 300)
	assert(arena.clearance(arena.global_position) == 300.0)
	arena.position = Vector3.ZERO
	var player := preload("res://player/mage/player_mage.tscn").instantiate() as PlayerMage
	player.name = "1"
	player.set_physics_process(false)
	add_child(player)
	var tracker := player.arena_tracker
	tracker.tick(0.0, player)
	assert(tracker.remaining == 12.0)
	assert(not tracker.near_edge)
	player.position = Vector3(1100, 0, 0)
	tracker.tick(0.0, player)
	assert(tracker.near_edge and not tracker.outside)
	assert(tracker._arrow.visible)
	player.position.x = 1201
	tracker.tick(8.0, player)
	assert(tracker.outside and tracker.remaining == 4.0)
	player.position.x = 1100
	tracker.tick(2.0, player)
	assert(not tracker.outside and tracker.remaining == 8.0)
	player.position.x = 1201
	tracker.tick(1.0, player)
	assert(tracker.remaining == 7.0)
	for point in [Vector3(0, -301, 0), Vector3(0, 1201, 0)]:
		player.position = point
		player.rotation = Vector3(0.4, 0.8, 1.6)
		tracker.tick(0.0, player)
		assert(tracker.outside)
		assert((-tracker._arrow.global_basis.z).dot((arena.return_position() - point).normalized()) > 0.999)
	tracker.tick(7.0, player)
	assert(not player.health.is_alive())
	assert(not tracker._arrow.visible)
	player.health.respawn()
	assert(player.health.is_alive() and tracker.remaining == 12.0)
	assert(player.global_position == Vector3.ZERO)
	player.position = Vector3(1201, 0, 0)
	tracker.tick(1.0, player)
	remove_child(arena)
	tracker.tick(0.0, player)
	assert(not tracker._arrow.visible)
	arena.free()
	assert(load("res://levels/LostMonuments.tscn") is PackedScene)
	assert(load("res://scenes/gameplay/ui/ui_layer.tscn") is PackedScene)
	print("Arena bounds checks passed: geometry, recovery, arrow, death, respawn, removal, scene loading.")
	get_tree().quit()
