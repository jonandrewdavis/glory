extends Node
class_name StatComponent

signal changed(current: float, max_value: float)
signal max_changed(max_value: float)
signal depleted
signal refilled

@export var max_value := 100.0:
	set(value):
		max_value = maxf(value, 0.0)
		max_changed.emit(max_value)
		if _initialized:
			current = minf(current, max_value)
		else:
			current = max_value

@export_group("Regeneration")
@export var regen_enabled := true
@export var regen_rate := 5.0
@export var regen_delay := 3.0

var current := 0.0:
	set(value):
		var previous := current
		current = clampf(value, 0.0, max_value)
		if previous == current:
			return
		changed.emit(current, max_value)
		if current <= 0.0:
			depleted.emit()
		elif current >= max_value:
			refilled.emit()
		if _initialized:
			_on_value_changed(previous, current)

var _regen_delay_left := 0.0
var _initialized := false

func _init() -> void:
	current = max_value

func _ready() -> void:
	_initialized = true

func _physics_process(delta: float) -> void:
	_process_regen(delta)

func ratio() -> float:
	if max_value <= 0.0:
		return 0.0
	return current / max_value

func is_empty() -> bool:
	return current <= 0.0

func is_full() -> bool:
	return current >= max_value

func refill() -> void:
	_regen_delay_left = 0.0
	current = max_value

func _can_regen() -> bool:
	return true

func _on_value_changed(_previous: float, _value: float) -> void:
	pass

func _process_regen(delta: float) -> void:
	if not regen_enabled or current >= max_value or not _can_regen():
		return
	if _regen_delay_left > 0.0:
		_regen_delay_left = maxf(_regen_delay_left - delta, 0.0)
		return
	_gain(regen_rate * delta)

func _lose(amount: float) -> float:
	var previous := current
	current = previous - absf(amount)
	_regen_delay_left = regen_delay
	return previous - current

func _gain(amount: float) -> float:
	var previous := current
	current = previous + absf(amount)
	return current - previous
