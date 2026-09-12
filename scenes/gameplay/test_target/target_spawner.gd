extends Node3D
class_name TargetSpawner

@export var target_scene: PackedScene
@export var max_targets := 35
@export var spawn_interval := 3.0
@export var max_distance := 2000.0
@export var min_distance := 30.0

var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = spawn_interval
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)
	_timer.start()

func _on_timeout() -> void:
	if get_child_count() - 1 >= max_targets or target_scene == null:
		return
	var target: Node3D = target_scene.instantiate()
	target.position = _random_hemisphere_point()
	add_child(target)

func _random_hemisphere_point() -> Vector3:
	var dir := Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)).normalized()
	dir.y = absf(dir.y)
	var r := lerpf(min_distance, max_distance, pow(randf(), 1.0 / 3.0))
	return dir * r
