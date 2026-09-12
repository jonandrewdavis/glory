extends Weapon
class_name BeamWeapon

@export var beam_width := 0.35
@export var beam_color := Color(0.4, 0.9, 1.0, 1.0)

@onready var hitscan_ray: RayCast3D = %HitscanRay
@onready var beam: Line3D = %Beam

func _ready() -> void:
	beam.use_global_space = true
	beam.billboard_mode = Line3D.BillboardMode.VIEW
	beam.material_type = Line3D.MaterialType.ADD
	beam.width = beam_width
	beam.color = beam_color
	beam.visible = false
	hitscan_ray.target_position = Vector3(0, 0, -weapon_range)
	hitscan_ray.collision_mask = 5
	hitscan_ray.enabled = true

func set_owner_body(body: PhysicsBody3D) -> void:
	super(body)
	hitscan_ray.add_exception(body)

func update_weapon(delta: float, firing: bool, target: Node3D) -> void:
	if not firing:
		beam.visible = false
		return
	var from := global_position
	var to: Vector3
	if target:
		to = target.global_position
		apply_damage(target, damage_per_second * delta)
	else:
		hitscan_ray.force_raycast_update()
		if hitscan_ray.is_colliding():
			to = hitscan_ray.get_collision_point()
			var col := hitscan_ray.get_collider()
			if col and col.is_in_group("targetable"):
				apply_damage(col, damage_per_second * delta)
		else:
			to = from - global_basis.z * weapon_range
	beam.points = PackedVector3Array([from, to])
	beam.rebuild()
	beam.visible = true
