@tool

class_name PathLine3D
extends Line3D


@export var path: Path3D:
	get: return path
	set(value):
		if path == value:
			return
		if path and path.curve_changed.is_connected(_on_curve_changed):
			path.curve_changed.disconnect(_on_curve_changed)
		path = value
		if is_node_ready() and _auto_rebuild:
			rebuild()
		if path and not path.curve_changed.is_connected(_on_curve_changed):
			path.curve_changed.connect(_on_curve_changed)
@export var use_baked_points: bool = true:
	get: return use_baked_points
	set(value):
		if use_baked_points == value:
			return
		use_baked_points = value
		if is_node_ready() and _auto_rebuild:
			rebuild()


func _validate_property(property: Dictionary) -> void:

	match property.name:
		"points", "curve_normals", "connection_mode":
			property.usage = PROPERTY_USAGE_NONE
		_:
			super._validate_property(property)


func rebuild() -> void:

	var old_auto_rebuild := _auto_rebuild
	_auto_rebuild = false

	points.clear()
	curve_normals.clear()

	if path:
		var curve := path.curve
		if curve:
			connection_mode = ConnectionMode.LOOP if curve.closed else ConnectionMode.LINE
			if use_baked_points:
				var baked_points := curve.get_baked_points()
				points.resize(baked_points.size())
				curve_normals.resize(baked_points.size())
				for i in baked_points.size():
					var p := baked_points[i]
					points[i] = p
					curve_normals[i] = curve.sample_baked_with_rotation(curve.get_closest_offset(p), true, true).basis.x
			else:
				points.resize(curve.point_count)
				for i in curve.point_count:
					points[i] = curve.get_point_position(i)
			if use_global_space:
				var path_tf := path.global_transform
				for i in points.size():
					points[i] = path_tf * points[i]
				for i in curve_normals.size():
					curve_normals[i] = path_tf.basis * curve_normals[i]

	_auto_rebuild = old_auto_rebuild

	super.rebuild()


func _on_curve_changed() -> void:

	if _auto_rebuild:
		rebuild()
