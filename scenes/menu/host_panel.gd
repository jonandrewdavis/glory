class_name HostPanel
extends PanelContainer

signal closed

func _ready() -> void:
	%HostButton.pressed.connect(_host)
	%CloseButton.pressed.connect(_close)
	%NameEdit.text_submitted.connect(func(_text: String) -> void: _host())

func open() -> void:
	show()
	%NameEdit.grab_focus()

func _host() -> void:
	var options := HostOptions.new()
	options.max_players = int(%MaxPlayersSpin.value)
	options.lobby_name = %NameEdit.text.strip_edges().replace(",", "")
	if options.lobby_name.is_empty():
		options.lobby_name = %NameEdit.placeholder_text
	_close()
	MultiplayerService.host_game(options)

func _close() -> void:
	hide()
	closed.emit()
