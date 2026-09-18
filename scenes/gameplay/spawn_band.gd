@tool
class_name SpawnBand
extends Node2D
## Bounds and capture markers are map data. Runtime ownership belongs to RespawnManager.

const NEUTRAL := -1
@export var band_id: StringName
@export var order := 0
@export_enum("Neutral:-1", "Blue:0", "Orange:1") var initial_owner := NEUTRAL
@export var permanent := false
@export var bounds := Rect2(-200, -480, 400, 576):
	set(value):
		bounds = value
		queue_redraw()
@export var flag_position := Vector2(0, -48):
	set(value):
		flag_position = value
		if is_node_ready():
			_update_flag()
@export var blue_capture_at_end := false
@export var orange_capture_at_start := false
var controlling_team := NEUTRAL
var active := false

func _ready() -> void:
	add_to_group("spawn_bands")
	controlling_team = initial_owner
	_update_flag()
	queue_redraw()
	hide()

func spawn_markers() -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	var container := get_node_or_null("Points")
	if container:
		for child in container.get_children():
			if child is Marker2D and bounds.has_point(to_local(child.global_position)):
				result.append(child)
	return result

func set_control(team: int, is_active: bool) -> void:
	controlling_team = team
	active = is_active
	_update_flag()
	queue_redraw()

func capture_distance(ram: BatteringRam, team: int) -> float:
	if team == Teams.Team.BLUE and blue_capture_at_end:
		return ram.route_length()
	if team == Teams.Team.ORANGE and orange_capture_at_start:
		return 0.0
	var marker := get_node_or_null("BlueCapture" if team == Teams.Team.BLUE else "OrangeCapture") as Marker2D
	return ram.route_distance_at(marker.global_position) if marker else -1.0

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if band_id.is_empty():
		warnings.append("Give this band a stable, unique ID.")
	if spawn_markers().is_empty():
		warnings.append("Add safe Marker2D children under Points, inside the band bounds.")
	if permanent and initial_owner == NEUTRAL:
		warnings.append("A permanent fortress must belong to a team.")
	if not permanent:
		if not blue_capture_at_end and not has_node("BlueCapture"):
			warnings.append("Add a BlueCapture marker on the ram route.")
		if not orange_capture_at_start and not has_node("OrangeCapture"):
			warnings.append("Add an OrangeCapture marker on the ram route.")
	if is_inside_tree():
		for other in get_tree().get_nodes_in_group("spawn_bands"):
			if other != self and (other.band_id == band_id or other.order == order):
				warnings.append("Band IDs and order values must be unique within the level.")
	return warnings

func _draw() -> void:
	var team := initial_owner if Engine.is_editor_hint() else controlling_team
	var tint := Color.GRAY if team == NEUTRAL else Teams.color(team)
	if Engine.is_editor_hint():
		draw_rect(bounds, Color(tint, 0.12))
		draw_rect(bounds, Color(tint, 0.6), false, 1.0)

func _update_flag() -> void:
	var flag := get_node_or_null("SpawnFlag")
	if flag == null:
		return
	flag.position = flag_position
	var team := initial_owner if Engine.is_editor_hint() else controlling_team
	flag.get_node("Flag").color = Color.GRAY if team == NEUTRAL else Teams.color(team)
	flag.get_node("Active").visible = active
