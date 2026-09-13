class_name Matchmaker
extends Node
## One-click matchmaking on top of MultiplayerService: list public lobbies, join the most
## populated one with room (up to MAX_JOIN_ATTEMPTS candidates), else host a new public lobby.
## Owned by the menu so it lives and dies with it. Backend-agnostic: only uses the service API.

signal progress(text: String)
## reason is empty on success and on cancel.
signal finished(success: bool, reason: String)

const LIST_START_TIMEOUT := 5.0
const LIST_GRACE := 1.0
const JOIN_ATTEMPT_TIMEOUT := 10.0
const MAX_JOIN_ATTEMPTS := 3
const OVERALL_DEADLINE := 30.0
const LOBBY_NAME := "Public Match"
const TIMEOUT_REASON := "Matchmaking timed out."

var running := false
var _token := 0
var _lobbies: Dictionary = {}
var _listing_started := false
var _outcome := ""
var _fail_reason := ""
var _start_msec := 0

func _ready() -> void:
	MultiplayerService.lobby_found.connect(_on_lobby_found)
	MultiplayerService.listing_started.connect(func() -> void: _listing_started = true)
	MultiplayerService.lobby_joined.connect(func() -> void: _outcome = "joined")
	MultiplayerService.join_lobby_failed.connect(func(reason: String) -> void:
		_outcome = "failed"
		_fail_reason = reason)

## Addresses of lobbies with room, most populated first, ties broken by lowest address.
## lobbies: {address: {"name": String, "cur": int, "max": int}}
static func rank_candidates(lobbies: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for address in lobbies:
		var info: Dictionary = lobbies[address]
		if int(info.get("cur", 0)) < int(info.get("max", 0)):
			result.append(str(address))
	result.sort_custom(func(a: String, b: String) -> bool:
		var ca := int(lobbies[a].cur)
		var cb := int(lobbies[b].cur)
		return ca > cb if ca != cb else a < b)
	return result

func run() -> void:
	if running:
		return
	_token += 1
	var token := _token
	running = true
	_lobbies.clear()
	_listing_started = false
	_outcome = ""
	_fail_reason = ""
	_start_msec = Time.get_ticks_msec()

	if MultiplayerService.backend_type != MultiplayerService.BackendType.TUBE:
		MultiplayerService.set_backend(MultiplayerService.BackendType.TUBE)
		if MultiplayerService.backend_type != MultiplayerService.BackendType.TUBE:
			_finish(token, false, "Could not switch to the online backend.")
			return

	progress.emit("Searching for matches...")
	MultiplayerService.fetch_lobby_list()
	if await _wait_until(func() -> bool: return _listing_started, LIST_START_TIMEOUT, token):
		await _wait_until(func() -> bool: return false, LIST_GRACE, token)
	if token != _token:
		return

	var candidates := rank_candidates(_lobbies)
	var attempts := mini(candidates.size(), MAX_JOIN_ATTEMPTS)
	for i in attempts:
		if _remaining() <= 0.0:
			_finish_timeout(token)
			return
		progress.emit("Joining lobby %d/%d..." % [i + 1, candidates.size()])
		_outcome = ""
		MultiplayerService.join_game(candidates[i])
		await _wait_until(func() -> bool: return _outcome != "", minf(JOIN_ATTEMPT_TIMEOUT, _remaining()), token)
		if token != _token:
			return
		if _outcome == "joined":
			_finish(token, true, "")
			return
		if _outcome == "":
			MultiplayerService.leave_game()

	if _remaining() <= 0.0:
		_finish_timeout(token)
		return
	progress.emit("Creating lobby...")
	_outcome = ""
	var options := HostOptions.new()
	options.max_players = MultiplayerService.MAX_PLAYERS
	options.lobby_name = LOBBY_NAME
	MultiplayerService.host_game(options)
	await _wait_until(func() -> bool: return _outcome != "", _remaining(), token)
	if token != _token:
		return
	if _outcome == "joined":
		_finish(token, true, "")
	elif _outcome == "failed":
		_finish(token, false, _fail_reason)
	else:
		_finish_timeout(token)

func cancel() -> void:
	if not running:
		return
	_token += 1
	running = false
	MultiplayerService.leave_game()
	finished.emit(false, "")

func _on_lobby_found(address: Variant, lobby_name: String, cur: int, maximum: int) -> void:
	if running:
		_lobbies[str(address)] = {"name": lobby_name, "cur": cur, "max": maximum}

func _remaining() -> float:
	return OVERALL_DEADLINE - (Time.get_ticks_msec() - _start_msec) / 1000.0

## Polls every frame so synchronous emissions inside service calls are never missed.
## Returns true when pred is satisfied, false on timeout or cancel.
func _wait_until(pred: Callable, timeout: float, token: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while token == _token and Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return token == _token and pred.call()

func _finish(token: int, success: bool, reason: String) -> void:
	if token != _token:
		return
	running = false
	finished.emit(success, reason)

func _finish_timeout(token: int) -> void:
	MultiplayerService.leave_game()
	_finish(token, false, TIMEOUT_REASON)
