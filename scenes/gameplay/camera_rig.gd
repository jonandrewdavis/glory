class_name CameraRig
extends Node2D
## Single local camera driven by Phantom Camera. Follows the local player by
## default. While "follow_arrow" (Shift) is held, a GROUP camera frames the
## player together with a watched target:
##
## 1. On a fresh press the newest arrow the local peer owns is watched. If it
##    already landed, its landing spot is watched instead.
## 2. When the watched arrow lands, a client-side marker parked at the impact
##    point takes its place and the camera stays locked there.
## 3. Releasing Shift returns to the player.
## 4. While held, a newer arrow only takes over once it is farther from the
##    player than the watched target by TAKEOVER_SCREEN_FRACTION of the visible
##    screen width.

const PLAYER_PRIORITY := 10
const ARROW_PRIORITY := 20
const TAKEOVER_SCREEN_FRACTION := 0.1

@export_range(0.0, 0.3) var forward_view_fraction := 0.15
## Opposite aim must be within 33 degrees of horizontal before counting.
@export_range(0.1, 1.0) var reversal_threshold := 0.838670568 # cos(33 degrees)
@export_range(0.0, 1.5) var reversal_hold_time := 0.50

var _camera_facing := 1
var _reversal_elapsed := 0.0

@onready var player_pcam: PhantomCamera2D = %PlayerPCam
@onready var arrow_pcam: PhantomCamera2D = %ArrowPCam
@onready var landing_marker: Node2D = %LandingMarker
@onready var camera: Camera2D = $Camera2D

var _player: ArrowPlayer
var _watch: Node2D ## What the group frames besides the player (arrow or marker).
var _newest: Arrow ## Newest arrow owned by the local peer; may already be freed.
var _newest_landed := false
var _newest_landing := Vector2.ZERO
var _following_arrow := false

func _ready() -> void:
	process_physics_priority = 100 # After player movement, before the host (300).
	# Sibling lookup: this runs before World's @onready vars are assigned.
	(%ProjectileSpawner as ProjectileSpawner).visual_spawned.connect(_on_arrow_spawned)

## Called by the owning ArrowPlayer once it is in the tree (also on respawn).
func set_local_player(player: ArrowPlayer) -> void:
	_player = player
	camera.enabled = true
	player_pcam.set_follow_target(player)
	reset_for_relocation(player)

func _physics_process(delta: float) -> void:
	if is_instance_valid(_player):
		var can_aim := not _player.is_dead and not _is_paused() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		_update_camera_facing(_player.aim_reticle.direction, delta, can_aim)
		_update_player_offset()

func _update_camera_facing(aim: Vector2, delta: float, can_aim: bool) -> void:
	# Neutral aim or a brief glance cancels the pending turn, never accumulates it.
	if not can_aim or aim.x * _camera_facing > -reversal_threshold:
		_reversal_elapsed = 0.0
		return
	_reversal_elapsed += delta
	if _reversal_elapsed + 0.000001 >= reversal_hold_time:
		_camera_facing = -_camera_facing
		_reversal_elapsed = 0.0

func _update_player_offset() -> void:
	var width := get_viewport().get_visible_rect().size.x / player_pcam.zoom.x
	player_pcam.set_follow_offset(Vector2(_camera_facing * forward_view_fraction * width, 0.0))

## Explicit relocations must discard the framed camera's previous deadzone.
func reset_for_relocation(player: ArrowPlayer) -> void:
	if player != _player:
		return
	_camera_facing = player.get_facing_direction()
	_reversal_elapsed = 0.0
	_watch = null
	_newest = null
	_newest_landed = false
	_stop_following()
	arrow_pcam.set_follow_targets([] as Array[Node2D])
	_update_player_offset()
	player_pcam.follow_mode = PhantomCamera2D.FollowMode.SIMPLE
	player_pcam.teleport_position()
	player_pcam.follow_mode = PhantomCamera2D.FollowMode.FRAMED
	camera.reset_physics_interpolation()

func clear() -> void:
	_reversal_elapsed = 0.0
	camera.enabled = false
	_player = null
	_watch = null
	_newest = null
	_newest_landed = false
	_stop_following()
	arrow_pcam.set_follow_targets([] as Array[Node2D])
	player_pcam.set_follow_target(null)

func _on_arrow_spawned(arrow: Arrow) -> void:
	if arrow.owner_id != multiplayer.get_unique_id():
		return
	_newest = arrow
	_newest_landed = false
	arrow.tree_exiting.connect(_on_arrow_exiting.bind(arrow))

## Runs while the arrow is still in the tree, so its position is valid.
func _on_arrow_exiting(arrow: Arrow) -> void:
	if arrow == _newest:
		_newest_landed = true
		_newest_landing = arrow.global_position
	if arrow != _watch:
		return
	landing_marker.global_position = arrow.global_position
	if _following_arrow:
		_set_group(landing_marker)

func _process(_delta: float) -> void:
	var held := Input.is_action_pressed("follow_arrow") and not _is_paused()
	if held and not _following_arrow:
		if is_instance_valid(_player) and _newest_position() != null:
			_watch_newest()
			arrow_pcam.teleport_position()
			arrow_pcam.set_priority(ARROW_PRIORITY)
			_following_arrow = true
	elif not held and _following_arrow:
		_stop_following()
	elif _following_arrow:
		_check_takeover()

## Rule 4: a newer arrow (live or landed) replaces the watched target only once
## it is farther from the player by a fraction of a screen at the current zoom.
func _check_takeover() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_watch):
		return
	if is_instance_valid(_newest) and _newest == _watch:
		return
	var newest_pos: Variant = _newest_position()
	if newest_pos == null:
		return
	if _watch == landing_marker and _newest_landed and landing_marker.global_position == _newest_landing:
		return # Already watching the newest arrow's landing spot.
	var d_new: float = _player.global_position.distance_to(newest_pos)
	var d_watch := _player.global_position.distance_to(_watch.global_position)
	if d_new >= d_watch + _takeover_distance():
		_watch_newest()

## Position of the newest own arrow: live position, landing spot, or null.
func _newest_position() -> Variant:
	if is_instance_valid(_newest):
		return _newest.global_position
	if _newest_landed:
		return _newest_landing
	return null

func _watch_newest() -> void:
	if is_instance_valid(_newest):
		_set_group(_newest)
	elif _newest_landed:
		landing_marker.global_position = _newest_landing
		_set_group(landing_marker)

func _takeover_distance() -> float:
	return get_viewport().get_visible_rect().size.x / camera.zoom.x * TAKEOVER_SCREEN_FRACTION

## The group is always exactly two nodes: the player and what we're watching.
func _set_group(watch: Node2D) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(watch):
		return
	_watch = watch
	arrow_pcam.set_follow_targets([_player, watch] as Array[Node2D])

func _stop_following() -> void:
	arrow_pcam.set_priority(0)
	_following_arrow = false

func _is_paused() -> bool:
	return World.ui_layer != null and World.ui_layer.is_paused()
