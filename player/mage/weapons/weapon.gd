extends Node3D
class_name Weapon

signal hit(target: Node, amount: float)

@export var damage_per_second := 25.0
@export var weapon_range := 120.0
@export var mana_per_second := 10.0

var owner_body: PhysicsBody3D

func update_weapon(_delta: float, _firing: bool, _target: Node3D) -> void:
	pass

func set_owner_body(body: PhysicsBody3D) -> void:
	owner_body = body

func apply_damage(target: Node, amount: float) -> void:
	var health := HealthComponent.find_in(target)
	if health == null:
		return
	health.take_damage(amount, owner_body)
	hit.emit(target, amount)
