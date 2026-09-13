extends Node3D
class_name ArenaTracker

@export_range(0.0, 1.0, 0.05) var arrow_opacity := 0.5

var remaining := 12.0
var outside := false
var near_edge := false
var arena: ArenaBounds
var _arrow: Node3D
var _material: StandardMaterial3D

func _ready() -> void:
	_arrow = Node3D.new()
	add_child(_arrow)
	_arrow.top_level = true
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Material alpha blending also works in the Web Compatibility renderer.
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	for is_tip in [false, true]:
		var part := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0 if is_tip else 0.12
		mesh.bottom_radius = 0.4 if is_tip else 0.12
		mesh.height = 0.7 if is_tip else 0.9
		part.mesh = mesh
		part.material_override = _material
		part.rotation.x = -PI / 2.0
		part.position.z = -0.7 if is_tip else 0.0
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arrow.add_child(part)
	_arrow.hide()

func reset() -> void:
	remaining = arena.countdown_seconds if is_instance_valid(arena) else 12.0
	clear_feedback()

func clear_feedback() -> void:
	outside = false
	near_edge = false
	if is_instance_valid(_arrow):
		_arrow.hide()
	if is_instance_valid(World.ui_layer):
		World.ui_layer.update_arena_warning("", 0.0)

func tick(delta: float, player: PlayerMage) -> void:
	var active := get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if active != arena:
		arena = active
		reset()
	if not is_instance_valid(arena):
		clear_feedback()
		return
	var distance := arena.clearance(player.global_position)
	outside = distance < 0.0
	var threshold := arena.warning_distance + (arena.warning_hysteresis if near_edge else 0.0)
	near_edge = distance <= threshold
	remaining = clampf(remaining + (-delta if outside else delta * arena.recovery_rate), 0.0, arena.countdown_seconds)
	if remaining <= 0.0:
		player.explode_out_of_bounds.rpc()
		player.health.kill(arena)
		return
	_arrow.visible = near_edge
	if near_edge:
		var direction := arena.return_position() - player.global_position
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()
			_arrow.global_position = player.global_position + direction * 3.0
			var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
			_arrow.look_at(_arrow.global_position + direction, up)
		_material.albedo_color = Color(Color.TOMATO if outside else Color.ORANGE, arrow_opacity)
	var message := ""
	if outside:
		message = "RETURN TO ARENA — %.1fs" % remaining
	elif remaining < arena.countdown_seconds:
		message = "ARENA EDGE · " if near_edge else ""
		message += "RECOVERING — %.1f / %.1fs" % [remaining, arena.countdown_seconds]
	elif near_edge:
		message = "ARENA EDGE"
	if is_instance_valid(World.ui_layer):
		World.ui_layer.update_arena_warning(message, remaining / arena.countdown_seconds, outside)

func _exit_tree() -> void:
	if is_multiplayer_authority():
		clear_feedback()
