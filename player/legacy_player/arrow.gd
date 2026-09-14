extends RigidBody2D

var source: String
var hit_location: Vector2
var is_arrow_frozen := false
var hit_node: Node2D
var hit_rotation: float
var color := Color.WHITE

var DEFAULT_GRAVITY_SCALE := 0.8

func _ready() -> void:
	add_to_group('Projectiles')
	%Polygon2D.scale = Vector2(0.1, 0.1)
	%Polygon2D.modulate = color
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	$Timer.timeout.connect(destroy)

func _process(_delta: float) -> void:
	if is_arrow_frozen:
		position = hit_node.position + hit_location
		rotation = hit_rotation
	else:
		rotation = linear_velocity.angle()
		hit_rotation = rotation

func find_node_in_group(group: String, name_to_find: String) -> Node2D:
	for node in get_tree().get_nodes_in_group(group):
		if node.name == name_to_find and node.is_inside_tree():
			return node
	return null
	
@rpc('call_local', 'any_peer', 'reliable')
func freeze_arrow(hit_location_: Vector2, node_name: String):
	if node_name == 'admin':
		hit_node = get_tree().get_first_node_in_group('PlayerAdmin')
	else:
		hit_node = find_node_in_group('Players', node_name)
		%Polygon2D.scale = Vector2(0.04, 0.04)

	hit_location = hit_location_
	is_arrow_frozen = true
	call_deferred('freeze_arrow_defer')

func freeze_arrow_defer():
	freeze = true
	%CollisionShape2D.disabled = true

func destroy():
	queue_free()

@rpc('call_local', 'any_peer', 'reliable')
func reflect_arrow(source_name: String):
	look_at(linear_velocity * -1.0)
	linear_velocity = linear_velocity * -1.1
	source = source_name
	$Timer.start(8.0)
