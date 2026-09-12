@tool
extends EditorPlugin


func _enter_tree() -> void:

	add_custom_type("Line3D", "MeshInstance3D", preload("uid://c8rainoecpyie"), preload("uid://d2k4q6d7tyw2f"))
	add_custom_type("Trail3D", "Line3D", preload("uid://bqflf4vw8mem1"), preload("uid://d2k4q6d7tyw2f"))
	add_custom_type("Wireframe3D", "Line3D", preload("uid://bi5vqx05j5uiq"), null)


func _exit_tree() -> void:

	remove_custom_type("Trail3D")
	remove_custom_type("Line3D")
	remove_custom_type("Wireframe3D")
