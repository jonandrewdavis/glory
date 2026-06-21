class_name JoinPanel
extends PanelContainer

signal closed
const ITEM_SCENE := preload("res://scenes/menu/join_list_item.tscn")
var addresses: Dictionary = {}
var search_token := 0

func _ready() -> void:
	%CloseButton.pressed.connect(_close)
	%RefreshButton.pressed.connect(_refresh)
	%JoinAddressButton.pressed.connect(_join_address)
	%AddressEdit.text_submitted.connect(func(_text: String) -> void: _join_address())
	MultiplayerService.lobby_found.connect(_add_lobby)
	MultiplayerService.backend_changed.connect(_refresh_hint)
	MultiplayerService.joining_lobby.connect(_close)

func open() -> void:
	_refresh_hint(MultiplayerService.backend_type)
	show()
	_refresh()
	%AddressEdit.grab_focus()

func _refresh_hint(_type: int) -> void:
	%AddressEdit.placeholder_text = MultiplayerService.backend.get_address_hint()
	%AddressEdit.clear()

func _refresh() -> void:
	search_token += 1
	var token := search_token
	addresses.clear()
	for child in %LobbyList.get_children():
		%LobbyList.remove_child(child)
		child.queue_free()
	%SearchLabel.text = "Searching..."
	MultiplayerService.fetch_lobby_list()
	await get_tree().create_timer(3.0).timeout
	if token == search_token:
		%SearchLabel.text = "No rooms found. Try an address or refresh." if addresses.is_empty() else "%d room(s)" % addresses.size()

func _add_lobby(address: Variant, lobby_name: String, cur: int, maximum: int) -> void:
	if not visible:
		return
	if addresses.has(address):
		addresses[address].update_lobby(lobby_name, cur, maximum)
		return
	var item := ITEM_SCENE.instantiate()
	item.address = address
	%LobbyList.add_child(item)
	item.update_lobby(lobby_name, cur, maximum)
	addresses[address] = item
	%SearchLabel.text = "%d room(s)" % addresses.size()

func _join_address() -> void:
	MultiplayerService.join_game(%AddressEdit.text.strip_edges())

func _close() -> void:
	hide()
	closed.emit()
