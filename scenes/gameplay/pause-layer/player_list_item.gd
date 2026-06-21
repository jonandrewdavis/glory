class_name PlayerListItem
extends HBoxContainer

var peer_id: int

func _ready() -> void:
	%UsernameLabel.text = MultiplayerService.get_username(peer_id)
	var can_moderate := MultiplayerService.is_host() and peer_id != multiplayer.get_unique_id()
	%KickButton.visible = can_moderate
	%BanButton.visible = can_moderate
	%KickButton.pressed.connect(func() -> void: MultiplayerService.kick_player(peer_id))
	%BanButton.pressed.connect(func() -> void: MultiplayerService.ban_player(peer_id))
