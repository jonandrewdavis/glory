extends Node2D
## One replicated snapshot keeps activation, fill, tier and perfect state together.
## Effects are local presentation only; no transforms or timers are replicated.
@export var display_state := Vector4.ZERO # active, fill, zero-based tier, perfect
## x: level-1 minimum-charge fill, y: ready flag, z: perfect-window start fill for the current tier.
@export var readiness := Vector3(0.15, 0.0, 1.0)

const RADIUS := 20.0
const COLORS := [Color("63dfff"), Color("ffd166"), Color("ff914d")]
const PERFECT := Color(0.4, 1.0, 0.4)
const EFFECT_DURATION := 0.2

var _active := false
var _tier := 0
var _effect_left := 0.0
var _burst := false
var _clock := 0.0

func _ready() -> void:
	visible = false

func reset() -> void:
	display_state = Vector4.ZERO
	readiness.y = 0.0
	_active = false
	_effect_left = 0.0
	_burst = false
	position = Vector2.ZERO
	scale = Vector2.ONE
	hide()
	queue_redraw()

func _process(delta: float) -> void:
	var active := display_state.x > 0.5
	var tier := maxi(int(display_state.z), 0)
	if not active:
		if _active:
			reset()
		return
	if not _active:
		# Also handles late joins: appearing at a high tier is not a level-up.
		_effect_left = EFFECT_DURATION
		_burst = false
	elif tier > _tier:
		_effect_left = EFFECT_DURATION
		_burst = true
	_active = true
	_tier = tier
	show()
	_clock += delta
	_effect_left = maxf(_effect_left - delta, 0.0)
	var remaining := _effect_left / EFFECT_DURATION
	var intensity := minf(float(_tier), 2.0)
	var punch := (0.12 + intensity * 0.05) if _burst else 0.08
	scale = Vector2.ONE * (1.0 + punch * sin(remaining * PI))
	var shake := minf(1.0 + intensity * 0.5, 2.0) * remaining if _burst else 0.0
	position = Vector2(sin(_clock * 113.0), cos(_clock * 97.0)).limit_length() * shake
	queue_redraw()

## Radial tick across the arc at a 0..1 fill position.
func _draw_threshold(center: Vector2, fill: float, color: Color) -> void:
	var direction := Vector2.from_angle(PI + PI * clampf(fill, 0.0, 1.0))
	draw_line(center + direction * (RADIUS - 3.0), center + direction * (RADIUS + 3.0), color, 1.0, true)

func _draw() -> void:
	if not _active:
		return
	var center := Vector2(0.0, -12.0)
	var fill := clampf(display_state.y, 0.0, 1.0)
	var color: Color = PERFECT if display_state.w > 0.5 else COLORS[mini(_tier, COLORS.size() - 1)]
	if _tier == 0 and readiness.y < 0.5:
		color = Color(0.45, 0.52, 0.58)
	var remaining := _effect_left / EFFECT_DURATION
	if display_state.w > 0.5:
		color = color.lerp(Color.WHITE, 0.12 + 0.08 * sin(_clock * 8.0))
	if _burst:
		color = color.lerp(Color.WHITE, remaining)
	draw_arc(center, RADIUS, PI, TAU, 48, Color(0.03, 0.05, 0.09, 0.9), 4.0, true)
	draw_arc(center, RADIUS, PI, TAU, 48, Color(0.2, 0.25, 0.3, 0.9), 2.0, true)
	if fill > 0.001:
		draw_arc(center, RADIUS, PI, PI + PI * fill, 48, color, 2.0, true)
		draw_circle(center + Vector2.from_angle(PI + PI * fill) * RADIUS, 1.5, color, true, -1.0, true)
	if _tier == 0:
		_draw_threshold(center, readiness.x, Color.WHITE)
	_draw_threshold(center, readiness.z, PERFECT)
	var font := ThemeDB.fallback_font
	var label := str(_tier + 1)
	var label_pos := Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x * 0.5, -19.0)
	draw_string_outline(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 2, Color(0.03, 0.05, 0.09))
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
	if _burst and remaining > 0.0:
		for i in 7:
			var direction := Vector2.from_angle(PI + (float(i) + 0.5) / 7.0 * PI)
			var start := center + direction * (RADIUS + 2.0 + (1.0 - remaining) * 7.0)
			draw_line(start, start + direction * (2.0 + float(mini(_tier, 2))), Color(color, remaining), 1.0, true)
