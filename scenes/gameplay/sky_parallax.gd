extends Polygon2D
## Feeds the active Camera2D position to the starfield shader so star layers parallax with movement.

func _ready() -> void:
	set_process(not MultiplayerService.is_dedicated_server())

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or not material is ShaderMaterial:
		return
	material.set_shader_parameter("camera_offset", camera.get_screen_center_position())
