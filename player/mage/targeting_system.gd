extends Node3D
class_name TargetingSystem

signal target_locked(target: Node3D)
signal target_lost(previous: Node3D)
signal candidates_changed(candidates: Array[Node3D])

@export var search_half_angle_deg := 25.0:
	set(value):
		search_half_angle_deg = value
		if is_node_ready():
			_apply_ranges()
@export var max_distance := 120.0:
	set(value):
		max_distance = value
		if is_node_ready():
			_apply_ranges()
@export var release_cone_multiplier := 1.3
@export var release_distance_multiplier := 1.3
@export var lock_grace := 0.4
@export var acquire_dwell := 0.2
@export var require_line_of_sight := true
@export_flags_3d_physics var los_collision_mask := 5
@export var switch_strength := 250.0
@export var flick_decay := 600.0
@export var switch_angle_tolerance_deg := 60.0
@export var switch_cooldown := 0.15
@export var debug_draw := false:
	set(value):
		debug_draw = value
		if is_node_ready():
			debug.visible = value

var locked_target: Node3D
var candidates: Array[Node3D] = []
var acquire_candidate: Node3D
var acquire_time := 0.0
var grace_time := 0.0
var flick_accum := Vector2.ZERO
var switch_cooldown_left := 0.0
var enabled := false:
	set(value):
		enabled = value
		set_process_input(enabled)

@onready var sensor: Area3D = %TargetSensor
@onready var sensor_shape: CollisionShape3D = %SensorShape
@onready var debug: TargetingDebug = %TargetingDebug
@onready var body: PhysicsBody3D = get_parent()

func _ready() -> void:
	sensor_shape.shape = SphereShape3D.new()
	_apply_ranges()
	debug.visible = debug_draw
	set_process_input(enabled)

func _apply_ranges() -> void:
	var release_dist := max_distance * release_distance_multiplier
	(sensor_shape.shape as SphereShape3D).radius = release_dist
	debug.configure(search_half_angle_deg, search_half_angle_deg * release_cone_multiplier, max_distance, release_dist)

func acquire_progress() -> float:
	if acquire_candidate == null or acquire_dwell <= 0.0:
		return 0.0
	return clampf(acquire_time / acquire_dwell, 0.0, 1.0)

func get_camera() -> Camera3D:
	return get_viewport().get_camera_3d()

func tick(delta: float) -> void:
	_prune_stale()
	if not enabled:
		return
	switch_cooldown_left = maxf(0.0, switch_cooldown_left - delta)
	flick_accum = flick_accum.move_toward(Vector2.ZERO, flick_decay * delta)
	_gather_candidates()
	_maintain_lock(delta)
	if locked_target == null:
		_update_acquire(delta)
	elif flick_accum.length() >= switch_strength and switch_cooldown_left == 0.0:
		_try_switch(flick_accum.normalized())
		flick_accum = Vector2.ZERO
	if candidates.size():
		debug.update_debug(candidates, locked_target, global_position)

func _input(event: InputEvent) -> void:
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if Input.is_action_pressed("secondary"):
		return
	if event is InputEventMouseMotion:
		flick_accum += event.screen_relative

func _forward() -> Vector3:
	return -global_basis.z

func _gather_candidates() -> void:
	var forward := _forward()
	var origin := body.global_position
	var cos_limit := cos(deg_to_rad(search_half_angle_deg))
	var found: Array[Node3D] = []
	for overlap in sensor.get_overlapping_bodies():
		if overlap == body or not overlap.is_in_group("targetable"):
			continue
		if HealthComponent.find_in(overlap) == null:
			continue
		var to: Vector3 = overlap.global_position - origin
		var d := to.length()
		if d > max_distance or d <= 0.0:
			continue
		if to.dot(forward) / d < cos_limit:
			continue
		if require_line_of_sight and not _has_los(origin, overlap):
			continue
		found.append(overlap)
	if found != candidates:
		candidates = found
		candidates_changed.emit(candidates)

func _has_los(origin: Vector3, target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, target.global_position, los_collision_mask, [body.get_rid()])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.collider == target

func _update_acquire(delta: float) -> void:
	var forward := _forward()
	var origin := body.global_position
	var best: Node3D = null
	var best_dot := -2.0
	var best_dist := INF
	for candidate in candidates:
		var to: Vector3 = candidate.global_position - origin
		var d := to.length()
		var dot := to.dot(forward) / d
		if dot > best_dot or (is_equal_approx(dot, best_dot) and d < best_dist):
			best = candidate
			best_dot = dot
			best_dist = d
	if best != acquire_candidate:
		acquire_candidate = best
		acquire_time = 0.0
		return
	if best == null:
		return
	acquire_time += delta
	if acquire_time >= acquire_dwell:
		_set_lock(best)

## A node can leave the game (player disconnect, despawn) between ticks. Freed
## objects compare equal to null in GDScript, so check validity before any
## null comparison and clear every reference we might hand out.
func _prune_stale() -> void:
	if not _is_live(locked_target):
		_drop_lock()
	if not _is_live(acquire_candidate):
		acquire_candidate = null
		acquire_time = 0.0
	if candidates.any(func(c) -> bool: return not _is_live(c)):
		candidates = candidates.filter(_is_live)
		candidates_changed.emit(candidates)

## Untyped on purpose: passing a freed instance to a Node3D parameter is itself an error.
func _is_live(node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree()

func _maintain_lock(delta: float) -> void:
	if locked_target == null:
		return
	if not locked_target.is_in_group("targetable"):
		_drop_lock()
		return
	var origin := body.global_position
	var to: Vector3 = locked_target.global_position - origin
	var d := to.length()
	var release_dist := max_distance * release_distance_multiplier
	var cos_limit := cos(deg_to_rad(search_half_angle_deg * release_cone_multiplier))
	var inside := d <= release_dist and d > 0.0 and to.dot(_forward()) / d >= cos_limit
	if inside and require_line_of_sight:
		inside = _has_los(origin, locked_target)
	if inside:
		grace_time = 0.0
		return
	grace_time += delta
	if grace_time >= lock_grace:
		_drop_lock()

func _set_lock(target: Node3D) -> void:
	if target == locked_target:
		return
	var previous := locked_target
	locked_target = target
	grace_time = 0.0
	acquire_candidate = null
	acquire_time = 0.0
	if previous:
		target_lost.emit(previous)
	target_locked.emit(target)

func _drop_lock() -> void:
	var previous := locked_target
	locked_target = null
	grace_time = 0.0
	if is_instance_valid(previous):
		target_lost.emit(previous)

func _try_switch(dir: Vector2) -> void:
	var camera := get_camera()
	if camera == null or camera.is_position_behind(locked_target.global_position):
		return
	var origin2d := camera.unproject_position(locked_target.global_position)
	var cos_limit := cos(deg_to_rad(switch_angle_tolerance_deg))
	var best: Node3D = null
	var best_score := -INF
	for candidate in candidates:
		if candidate == locked_target or camera.is_position_behind(candidate.global_position):
			continue
		var off := camera.unproject_position(candidate.global_position) - origin2d
		if off.is_zero_approx():
			continue
		var a := off.normalized().dot(dir)
		if a < cos_limit:
			continue
		var score := a - off.length() / 4000.0
		if score > best_score:
			best_score = score
			best = candidate
	if best:
		_set_lock(best)
		switch_cooldown_left = switch_cooldown
