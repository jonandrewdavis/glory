class_name JoinListItem
extends HBoxContainer

var address: Variant

func _ready() -> void:
	%JoinButton.pressed.connect(func() -> void: MultiplayerService.join_game(address))

func update_lobby(lobby_name: String, cur: int, maximum: int) -> void:
	%NameLabel.text = lobby_name
	%PlayerCountLabel.text = "(%d/%d)" % [cur, maximum]
	%JoinButton.disabled = cur >= maximum
