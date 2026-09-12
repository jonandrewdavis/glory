extends Node3D
class_name TargetingDebug

@export var debug_marker_count := 16

var search_cone: MeshInstance3D
var release_cone: MeshInstance3D
var markers: Array[MeshInstance3D] = []
var lock_line: Line3D

func _ready() -> void:
	search_cone = _make_cone(Color(0.2, 1.0, 0.2, 0.08))
	release_cone = _make_cone(Color(1.0, 1.0, 0.2, 0.04))
	add_child(search_cone)
	add_child(release_cone)
	for i in debug_marker_count:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		marker.mesh = sphere
		marker.material_override = _make_material(Color.RED)
		marker.top_level = true
		marker.visible = false
		add_child(marker)
		markers.append(marker)
	lock_line = Line3D.new()
	lock_line.use_global_space = true
	lock_line.width = 0.1
	lock_line.color = Color.YELLOW
	lock_line.material_type = Line3D.MaterialType.SOLID_UNLIT
	lock_line.visible = false
	add_child(lock_line)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material

func _make_cone(color: Color) -> MeshInstance3D:
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.cap_top = false
	cone.mesh = mesh
	cone.material_override = _make_material(color)
	cone.rotation_degrees.x = 90.0
	return cone

func _shape_cone(cone: MeshInstance3D, half_deg: float, dist: float) -> void:
	var mesh := cone.mesh as CylinderMesh
	mesh.bottom_radius = tan(deg_to_rad(half_deg)) * dist
	mesh.height = dist
	cone.position = Vector3(0, 0, -dist / 2.0)

func configure(search_half_deg: float, release_half_deg: float, max_dist: float, release_dist: float) -> void:
	_shape_cone(search_cone, search_half_deg, max_dist)
	_shape_cone(release_cone, release_half_deg, release_dist)

func update_debug(candidates: Array[Node3D], locked: Node3D, muzzle_pos: Vector3) -> void:
	if not visible:
		return
	for i in markers.size():
		var marker := markers[i]
		if i < candidates.size():
			var candidate := candidates[i]
			marker.global_position = candidate.global_position
			marker.material_override.albedo_color = Color.CYAN if candidate == locked else Color.RED
			marker.visible = true
		else:
			marker.visible = false
	if locked:
		lock_line.points = PackedVector3Array([muzzle_pos, locked.global_position])
		lock_line.rebuild()
		lock_line.visible = true
	else:
		lock_line.visible = false
