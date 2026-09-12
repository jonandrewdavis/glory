@tool
class_name Wireframe3D
extends Line3D


@export var source_mesh: Mesh:
	get: return source_mesh
	set(value):
		if source_mesh == value:
			return
		if source_mesh and source_mesh.changed.is_connected(rebuild):
			source_mesh.changed.disconnect(rebuild)
		source_mesh = value
		if source_mesh and not source_mesh.changed.is_connected(rebuild):
			source_mesh.changed.connect(rebuild)
		rebuild()
@export var source_surface_idx: int = -1:
	get: return source_surface_idx
	set(value):
		if source_surface_idx == value:
			return
		source_surface_idx = value
		if _auto_rebuild and Engine.is_editor_hint():
			rebuild()
@export var use_source_colors: bool = false:
	get: return use_source_colors
	set(value):
		if use_source_colors == value:
			return
		use_source_colors = value
		if _auto_rebuild and Engine.is_editor_hint():
			rebuild()

var _source_colors: PackedColorArray


func _ready() -> void:

	use_global_space = false
	connection_mode = ConnectionMode.SEGMENTS

	super._ready()


func _validate_property(property: Dictionary) -> void:

	match property.name:
		"points", "curve_normals":
			property.usage = PROPERTY_USAGE_NONE
		"use_global_space":
			property.usage = PROPERTY_USAGE_NONE
		"connection_mode":
			property.usage = PROPERTY_USAGE_NONE
		_:
			super._validate_property(property)


func rebuild() -> void:

	if not is_inside_tree() or not is_node_ready():
		return

	_auto_rebuild = false

	_source_colors.clear()
	points.clear()
	curve_normals.clear()

	if source_mesh:

		for surf in source_mesh.get_surface_count():
			if source_surface_idx != -1 and source_surface_idx != surf:
				continue
			var surf_arrays := source_mesh.surface_get_arrays(surf)
			var surf_verts: PackedVector3Array = surf_arrays[Mesh.ARRAY_VERTEX]
			var surf_colors = surf_arrays[Mesh.ARRAY_COLOR]
			var surf_indices: PackedInt32Array = surf_arrays[Mesh.ARRAY_INDEX]
			var conns: Dictionary[Vector3, PackedVector3Array]
			for vert in surf_verts:
				conns[vert] = []
			for tri in surf_indices.size() / 3:
				var i0 := surf_indices[tri * 3]
				var i1 := surf_indices[tri * 3 + 1]
				var i2 := surf_indices[tri * 3 + 2]
				var p0 := surf_verts[i0]
				var p1 := surf_verts[i1]
				var p2 := surf_verts[i2]
				var conns0 = conns[p0]
				var conns1 = conns[p1]
				var conns2 = conns[p2]
				if p1 not in conns0 and p0 not in conns1:
					points.append(p0)
					points.append(p1)
					conns0.append(p1)
					conns1.append(p0)
					if use_source_colors and surf_colors:
						points.append(surf_colors[i0])
						points.append(surf_colors[i1])
				if p2 not in conns1 and p1 not in conns2:
					points.append(p1)
					points.append(p2)
					conns1.append(p2)
					conns2.append(p1)
					if use_source_colors and surf_colors:
						points.append(surf_colors[i1])
						points.append(surf_colors[i2])
				if p0 not in conns2 and p2 not in conns0:
					points.append(p2)
					points.append(p0)
					conns2.append(p0)
					conns0.append(p2)
					if use_source_colors and surf_colors:
						points.append(surf_colors[i2])
						points.append(surf_colors[i0])

	super.rebuild()

	_source_colors.clear()

	_auto_rebuild = true


func _postprocess_mesh_data() -> void:

	if use_source_colors:
		for i in _source_colors.size():
			var c := _source_colors[i]
			_colors[i * 3] *= c
			_colors[i * 3 + 1] *= c
			_colors[i * 3 + 2] *= c
