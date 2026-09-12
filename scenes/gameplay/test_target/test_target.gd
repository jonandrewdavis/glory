extends StaticBody3D
class_name TestTarget

@onready var mesh: MeshInstance3D = %Mesh
@onready var collision_shape: CollisionShape3D = %CollisionShape3D
@onready var health: HealthComponent = %HealthComponent

func _ready() -> void:
	add_to_group("targetable")
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	_apply_tint()

func is_targetable() -> bool:
	return health.is_alive()

func _on_health_changed(_current: float, _max_value: float) -> void:
	_apply_tint()

func _apply_tint() -> void:
	var material := mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return
	var t := health.ratio()
	material.albedo_color = Color(1.0, t, t)

func _on_died(_source: Node) -> void:
	remove_from_group("targetable")
	collision_shape.set_deferred("disabled", true)
	mesh.visible = false

func _on_respawned() -> void:
	collision_shape.set_deferred("disabled", false)
	mesh.visible = true
	add_to_group("targetable")
