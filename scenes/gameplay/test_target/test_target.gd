extends StaticBody3D
class_name TestTarget

signal died
signal respawned
signal health_changed(current: float, max: float)

@export var max_health := 100.0
@export var respawn_delay := 5.0

var health: float

@onready var mesh: MeshInstance3D = %Mesh
@onready var collision_shape: CollisionShape3D = %CollisionShape3D

func _ready() -> void:
	health = max_health
	add_to_group("targetable")

func is_targetable() -> bool:
	return health > 0.0

func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_apply_tint()
	if health <= 0.0:
		_die()

func _apply_tint() -> void:
	var material := mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return
	var t := health / max_health
	material.albedo_color = Color(1.0, t, t)

func _die() -> void:
	remove_from_group("targetable")
	collision_shape.set_deferred("disabled", true)
	mesh.visible = false
	died.emit()
	await get_tree().create_timer(respawn_delay).timeout
	if is_inside_tree():
		_respawn()

func _respawn() -> void:
	health = max_health
	collision_shape.set_deferred("disabled", false)
	mesh.visible = true
	_apply_tint()
	add_to_group("targetable")
	health_changed.emit(health, max_health)
	respawned.emit()
