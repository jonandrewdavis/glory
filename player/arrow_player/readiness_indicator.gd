extends Node2D
## Atomic replicated snapshot: zero-based level, preparing, fill, ready.
@export var display_state := Vector4.ZERO

const RADIUS := 20.0
const COLORS := [Color("63dfff"), Color("ffd166"), Color("ff914d")]

func _process(_delta: float) -> void:
	visible = not get_parent().is_dead
	queue_redraw()

func _draw() -> void:
	var level := clampi(int(display_state.x), 0, COLORS.size() - 1)
	var preparing := display_state.y > 0.5
	var fill := clampf(display_state.z, 0.0, 1.0)
	var color: Color = COLORS[level]
	var center := Vector2(0.0, -12.0)
	if preparing:
		var arc_color := color if display_state.w > 0.5 else Color(0.45, 0.52, 0.58)
		draw_arc(center, RADIUS, PI, TAU, 48, Color(0.03, 0.05, 0.09, 0.9), 4.0, true)
		draw_arc(center, RADIUS, PI, TAU, 48, Color(0.2, 0.25, 0.3, 0.9), 2.0, true)
		if fill > 0.001:
			draw_arc(center, RADIUS, PI, PI + PI * fill, 48, arc_color, 2.0, true)
			draw_circle(center + Vector2.from_angle(PI + PI * fill) * RADIUS, 1.5, arc_color, true, -1.0, true)
	var font := ThemeDB.fallback_font
	var label := str(level + 1)
	var label_pos := Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x * 0.5, -19.0)
	draw_string_outline(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 2, Color(0.03, 0.05, 0.09))
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
