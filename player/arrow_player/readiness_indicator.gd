extends Node2D
## Owner-only, never replicated: zero-based level, preparing, fill, ready.
@export var display_state := Vector4.ZERO

const COLORS := [Color("63dfff"), Color("ffd166"), Color("ff914d")]

func _ready() -> void:
	set_process(get_parent().is_multiplayer_authority())

func _process(_delta: float) -> void:
	visible = not get_parent().is_dead
	var level := clampi(int(display_state.x), 0, COLORS.size() - 1)
	$Track.visible = display_state.y > 0.5
	$Progress.visible = $Track.visible
	$Progress.value = clampf(display_state.z, 0.0, 1.0)
	$Progress.tint_progress = COLORS[level] if display_state.w > 0.5 else Color(0.45, 0.52, 0.58)
	$Level.text = str(level + 1)
	$Level.modulate = COLORS[level]
