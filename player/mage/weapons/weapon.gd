extends Node3D
class_name Weapon

signal hit(target: Node, amount: float)

@export var damage_per_second := 25.0
@export var weapon_range := 120.0

func update_weapon(_delta: float, _firing: bool, _target: Node3D) -> void:
	pass

func set_owner_body(_body: PhysicsBody3D) -> void:
	pass

func apply_damage(target: Node, amount: float) -> void:
	if target.has_method("take_damage"):
		target.take_damage(amount)
	hit.emit(target, amount)
