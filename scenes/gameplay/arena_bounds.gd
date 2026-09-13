@tool
extends Node3D
class_name ArenaBounds

## World-aligned cylinder. Heights are relative to this node's global position.
@export_range(1.0, 10000.0) var radius := 1200.0
@export var floor_height := -300.0
@export var ceiling_height := 1200.0
@export var return_height := 300.0
@export_range(0.0, 2000.0) var warning_distance := 200.0
@export_range(0.0, 100.0) var warning_hysteresis := 5.0
@export_range(0.1, 120.0) var countdown_seconds := 12.0
@export_range(0.1, 10.0) var recovery_rate := 2.0

var _preview: MeshInstance3D
var _preview_settings: Array = []

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("arena_bounds")

func clearance(world_position: Vector3) -> float:
	var offset := world_position - global_position
	return minf(radius - Vector2(offset.x, offset.z).length(),
		minf(offset.y - floor_height, ceiling_height - offset.y))

func return_position() -> Vector3:
	return global_position + Vector3(0, clampf(return_height, floor_height + 0.01, ceiling_height - 0.01), 0)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if ceiling_height <= floor_height + 0.02:
		warnings.append("Ceiling height must be above floor height.")
	if return_height <= floor_height or return_height >= ceiling_height:
		warnings.append("Choose a return height safely between the floor and ceiling.")
	if warning_distance >= minf(radius, (ceiling_height - floor_height) * 0.5):
		warnings.append("The warning band fills the arena; reduce it to leave a safe interior.")
	if not global_basis.is_equal_approx(Basis.IDENTITY):
		warnings.append("Bounds are world-aligned. Use radius and heights instead of rotation or scale.")
	return warnings

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var settings := [radius, floor_height, ceiling_height, return_height, warning_distance, global_transform]
	if settings == _preview_settings:
		return
	_preview_settings = settings
	update_configuration_warnings()
	if not is_instance_valid(_preview):
		_preview = MeshInstance3D.new()
		add_child(_preview)
		_preview.top_level = true
	_preview.global_transform = Transform3D(Basis.IDENTITY, global_position)
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	_draw_cylinder(mesh, radius, floor_height, ceiling_height, Color.CYAN)
	var band := minf(warning_distance, minf(radius, (ceiling_height - floor_height) * 0.5))
	_draw_cylinder(mesh, maxf(0.01, radius - band), floor_height + band, ceiling_height - band, Color.ORANGE)
	mesh.surface_end()
	_preview.mesh = mesh

func _draw_cylinder(mesh: ImmediateMesh, r: float, low: float, high: float, color: Color) -> void:
	mesh.surface_set_color(color)
	for i in range(64):
		var a := TAU * i / 64.0
		var b := TAU * (i + 1) / 64.0
		for height in [low, high]:
			mesh.surface_add_vertex(Vector3(cos(a) * r, height, sin(a) * r))
			mesh.surface_add_vertex(Vector3(cos(b) * r, height, sin(b) * r))
		if i % 8 == 0:
			mesh.surface_add_vertex(Vector3(cos(a) * r, low, sin(a) * r))
			mesh.surface_add_vertex(Vector3(cos(a) * r, high, sin(a) * r))
