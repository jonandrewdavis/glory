extends Control
## Intentionally hidden at the scene root. Child state must never reveal this root.
const ZONE := preload("res://scenes/gameplay/ui/respawn_zone.tscn")

func _ready() -> void:
	World.respawn_manager.changed.connect(_update_zones)
	_update_zones()

func _update_zones() -> void:
	var bands := World.respawn_manager.bands
	while $Zones.get_child_count() > bands.size():
		var child := $Zones.get_child($Zones.get_child_count() - 1)
		$Zones.remove_child(child)
		child.queue_free()
	while $Zones.get_child_count() < bands.size():
		$Zones.add_child(ZONE.instantiate())
	for i in bands.size():
		var band: SpawnBand = bands[i]
		var zone := $Zones.get_child(i)
		zone.get_node("Marker").color = Color.GRAY if band.controlling_team == SpawnBand.NEUTRAL else Teams.color(band.controlling_team)
		zone.get_node("Marker/Active").visible = band.active
		zone.get_node("Number").text = str(i + 1) + (" ACTIVE" if band.active else "")

func _process(_delta: float) -> void:
	var player := World.player_spawner.get_player(multiplayer.get_unique_id())
	$Countdown.visible = player != null and not player.health.is_alive() and World.round_manager.phase == RoundManager.Phase.PLAYING
	if not $Countdown.visible:
		return
	var manager := World.respawn_manager
	var band := manager.active_band(player.team)
	var destination := "Zone %d" % (manager.bands.find(band) + 1) if band else "team spawn"
	$Countdown/Text.text = "Respawn in %.1fs  ·  %s" % [manager.seconds_left(player.peer_id), destination]
