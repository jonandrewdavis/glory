class_name PlayerListItem
extends HBoxContainer

var peer_id: int

func _ready() -> void:
	World.scoreboard.changed.connect(_update_team)
	MultiplayerService.username_changed.connect(func(_id: int) -> void: _update_team())
	_update_team()
	var team: int = World.scoreboard.get_team(peer_id)
	if team >= 0:
		%UsernameLabel.modulate = Teams.color(team)
	var can_moderate := MultiplayerService.is_host() and peer_id != multiplayer.get_unique_id()
	%KickButton.visible = can_moderate
	%BanButton.visible = can_moderate
	%KickButton.pressed.connect(func() -> void: MultiplayerService.kick_player(peer_id))
	%BanButton.pressed.connect(func() -> void: MultiplayerService.ban_player(peer_id))

func _update_team() -> void:
	var team := World.scoreboard.get_team(peer_id)
	%UsernameLabel.modulate = Teams.color(team)
	if multiplayer:
		%UsernameLabel.text = "%s — %s" % [MultiplayerService.get_username(peer_id), Teams.display_name(team, World.scoreboard.get_team(multiplayer.get_unique_id()))]
	
