class_name PlayerHealthBar
extends Control
## Rebind to each local-player incarnation; health updates themselves are signal-driven.
var _health: HealthComponent

func _process(_delta: float) -> void:
	var player := World.player_spawner.get_player(multiplayer.get_unique_id())
	var next: HealthComponent = player.health if is_instance_valid(player) else null
	if next != _health:
		if is_instance_valid(_health) and _health.changed.is_connected(_update):
			_health.changed.disconnect(_update)
		_health = next
		if is_instance_valid(_health):
			_health.changed.connect(_update)
			_update(_health.current, _health.max_value)
	visible = is_instance_valid(_health)

func _update(current: float, maximum: float) -> void:
	$Bar.value = current / maximum if maximum > 0 else 0
	$Bar.self_modulate = Color(0.85, 0.25, 0.2).lerp(Color(0.35, 0.8, 0.35), $Bar.value)
	$Bar/Value.text = "%d / %d" % [ceili(current), int(maximum)]
