@tool
extends TextureProgressBar
## Keep the ring's stroke in pixels when the Control changes size.
@export_range(0.5, 8.0) var stroke_width := 2.0:
	set(value):
		stroke_width = value
		if is_node_ready():
			_update_texture()

func _ready() -> void:
	texture_progress = texture_progress.duplicate(true)
	resized.connect(_update_texture)
	_update_texture()

func _update_texture() -> void:
	var radius := minf(size.x, size.y) * 0.5
	if radius <= 0:
		return
	var texture := texture_progress as GradientTexture2D
	texture.width = clampi(ceili(size.x * 2), 64, 1024)
	texture.height = clampi(ceili(size.y * 2), 64, 1024)
	var inner := maxf(0, 1.0 - (stroke_width + 1.0) / radius)
	texture.gradient.offsets = PackedFloat32Array([0, inner, minf(1, inner + 0.5 / radius), maxf(inner, 1 - 0.5 / radius), 1])
