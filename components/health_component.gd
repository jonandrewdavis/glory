extends StatComponent
class_name HealthComponent

signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died(source: Node)
signal respawned

@export_group("Respawn")
@export var auto_respawn := true
@export var respawn_delay := 5.0

@export_group("Networking")
@export var networked := false
@export var network_send_interval := 0.1

var _last_source: Node
var _pending_damage := 0.0
var _pending_source: Node
var _send_cooldown := 0.0
var _respawn_timer: Timer

static func find_in(node: Node) -> HealthComponent:
	if node == null:
		return null
	for child in node.get_children():
		if child is HealthComponent:
			return child
	return null

func _ready() -> void:
	_respawn_timer = Timer.new()
	_respawn_timer.one_shot = true
	_respawn_timer.timeout.connect(respawn)
	add_child(_respawn_timer)
	super()

func _physics_process(delta: float) -> void:
	super(delta)
	_flush_pending_damage(delta)

func is_alive() -> bool:
	return current > 0.0

func take_damage(amount: float, source: Node = null) -> bool:
	if get_parent() is Creep:
		if not multiplayer.is_server() or not is_instance_valid(source):
			return false
		if not (source is Creep or source is ArrowPlayer) or not Teams.are_enemies(source.team, get_parent().team):
			return false
	if get_parent() is ArrowPlayer:
		if not multiplayer.is_server() or not is_instance_valid(source) or not source is ArrowPlayer:
			return false
		if not Teams.are_enemies(source.team, get_parent().team):
			return false
		if get_parent().is_spawn_protected():
			return false
		get_parent().server_register_hit(source.peer_id)
	if get_parent() is FortressGate:
		if not multiplayer.is_server() or not is_instance_valid(source):
			return false
		# The ram is neutral and only strikes the gate it is touching.
		if not source is BatteringRam:
			if not (source is Creep or source is ArrowPlayer) or not Teams.are_enemies(source.team, get_parent().team):
				return false
	if amount <= 0.0 or not is_alive():
		return false
	if not _is_local_authority():
		_pending_damage += amount
		_pending_source = source
		return true
	_apply_damage(amount, source)
	return true

func heal(amount: float) -> float:
	if not is_alive():
		return 0.0
	var gained := _gain(amount)
	if gained > 0.0:
		healed.emit(gained)
	return gained

func kill(source: Node = null) -> void:
	take_damage(current, source)

func respawn() -> void:
	_respawn_timer.stop()
	_last_source = null
	refill()

func _can_regen() -> bool:
	return is_alive() and _is_local_authority()

func _on_value_changed(previous: float, value: float) -> void:
	if previous > 0.0 and value <= 0.0:
		died.emit(_last_source)
		if auto_respawn and _is_local_authority():
			_respawn_timer.start(respawn_delay)
	elif previous <= 0.0 and value > 0.0:
		respawned.emit()

func _is_local_authority() -> bool:
	return not networked or is_multiplayer_authority()

func _apply_damage(amount: float, source: Node) -> void:
	_last_source = source
	var lost := _lose(amount)
	if lost > 0.0:
		damaged.emit(lost, source)

func _flush_pending_damage(delta: float) -> void:
	_send_cooldown = maxf(_send_cooldown - delta, 0.0)
	if _pending_damage <= 0.0 or _send_cooldown > 0.0:
		return
	var source_path := NodePath()
	if is_instance_valid(_pending_source) and _pending_source.is_inside_tree():
		source_path = _pending_source.get_path()
	_request_damage.rpc_id(get_multiplayer_authority(), _pending_damage, source_path)
	_pending_damage = 0.0
	_pending_source = null
	_send_cooldown = network_send_interval

@rpc("any_peer", "call_remote", "reliable")
func _request_damage(amount: float, source_path: NodePath) -> void:
	# Combat damage is decided locally by the server, never a client RPC.
	if get_parent() is ArrowPlayer or get_parent() is Creep or get_parent() is FortressGate:
		return
	if not networked or not is_multiplayer_authority():
		return
	var source: Node = null
	if not source_path.is_empty():
		source = get_node_or_null(source_path)
	take_damage(amount, source)
