extends Node2D
const Trajectory := preload("res://player/arrow_player/trajectory_preview.gd")
var failures := 0

class Target extends CharacterBody2D:
	var peer_id := 123
	var team := 0
	var is_dead := false

func _ready() -> void:
	call_deferred("check")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func check() -> void:
	await get_tree().physics_frame
	var space := get_world_2d().direct_space_state
	var start := Vector2(-10000, -10000)
	var excluded: Array[RID] = []
	var step := 1.0 / Engine.physics_ticks_per_second
	var began := Time.get_ticks_usec()
	for speed in [300.0, 420.0, 560.0, 720.0]:
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, -1).normalized()]:
			var velocity: Vector2 = direction * speed
			var full := Trajectory.predict(space, start, velocity, excluded, step)
			var half := Trajectory.first_half(full)
			expect(full[-1].is_equal_approx(start + velocity * Arrow.LIFETIME + Vector2(0, 392) * Arrow.LIFETIME * Arrow.LIFETIME), "Unobstructed prediction reaches lifetime at speed %d" % speed)
			expect(absf(Trajectory.length_of(half) * 2.0 - Trajectory.length_of(full)) < 0.02, "Preview trims half the path distance")
			var arrow = load("res://player/arrow_player/arrow.tscn").instantiate()
			arrow.setup({"position": start, "velocity": velocity})
			add_child(arrow)
			arrow.set_physics_process(false)
			arrow._physics_process(step * 10)
			expect(arrow.global_position.is_equal_approx(full[10]), "Actual projectile follows predicted samples")
			arrow.free()
	print("Mean full-flight prediction + verification: ", (Time.get_ticks_usec() - began) / 20.0, " us")
	var wall := StaticBody2D.new()
	wall.position = Vector2(100, 0)
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 1000)
	shape.shape = rectangle
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit_path := Trajectory.predict(space, Vector2.ZERO, Vector2(300, 0), excluded, step)
	expect(is_equal_approx(hit_path[-1].x, 95.0), "Terrain stops prediction at first impact")
	var clipped := Trajectory.first_half(hit_path)
	expect(absf(Trajectory.length_of(clipped) * 2.0 - Trajectory.length_of(hit_path)) < 0.001, "Collision path clips exactly halfway")
	var ignored: Array[RID] = [wall.get_rid()]
	var pass_through := Trajectory.predict(space, Vector2.ZERO, Vector2(300, 0), ignored, step)
	expect(pass_through[-1].x > 100.0, "Excluded colliders do not truncate prediction")
	var target := Target.new()
	target.position = Vector2(50, 0)
	target.collision_layer = 2
	var target_shape := CollisionShape2D.new()
	target_shape.shape = rectangle
	target.add_child(target_shape)
	add_child(target)
	target.add_to_group("players")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var friendly := Trajectory.predict(space, Vector2.ZERO, Vector2(300, 0), Arrow.ignored_rids(get_tree(), 1, 0), step)
	expect(is_equal_approx(friendly[-1].x, 95.0), "Friendly player is transparent")
	target.team = 1
	var enemy := Trajectory.predict(space, Vector2.ZERO, Vector2(300, 0), Arrow.ignored_rids(get_tree(), 1, 0), step)
	expect(is_equal_approx(enemy[-1].x, 45.0), "Enemy player stops trajectory")
	target.is_dead = true
	expect(target.get_rid() in Arrow.ignored_rids(get_tree(), 1, 0), "Dead player is excluded")
	target.is_dead = false
	target.peer_id = 1
	expect(target.get_rid() in Arrow.ignored_rids(get_tree(), 1, 0), "Shooter is excluded")
	target.peer_id = 123
	var shield := Area2D.new()
	shield.collision_layer = 8
	shield.position = Vector2(-20, 0)
	var shield_shape := CollisionShape2D.new()
	shield_shape.shape = rectangle
	shield.add_child(shield_shape)
	target.add_child(shield)
	shield.owner = target
	shield.add_to_group("shields")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var blocked := Trajectory.predict(space, Vector2.ZERO, Vector2(300, 0), Arrow.ignored_rids(get_tree(), 1, 0), step)
	expect(is_equal_approx(blocked[-1].x, 25.0), "Enemy shield ends preview before reflection")
	target.team = 0
	expect(shield.get_rid() in Arrow.ignored_rids(get_tree(), 1, 0), "Friendly shield is excluded")
	target.free()
	var dots := Trajectory.dots(clipped)
	expect(dots[-1].is_equal_approx(clipped[-1]), "Final dot reaches exact halfway cutoff")
	var short_path := PackedVector2Array([Vector2.ZERO, Vector2(2, 0)])
	expect(Trajectory.dots(Trajectory.first_half(short_path)) == PackedVector2Array([Vector2(1, 0)]), "Close impacts retain a short preview")
	var node := Node2D.new()
	node.position = Vector2(40, -25)
	node.scale = Vector2(1.2, 1.2)
	add_child(node)
	expect(node.to_global(node.to_local(dots[-1])).is_equal_approx(dots[-1]), "World samples survive player scale and offset")
	node.free()
	wall.free()
	get_tree().quit(1 if failures else 0)
