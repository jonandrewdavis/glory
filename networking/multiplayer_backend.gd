@abstract
class_name MultiplayerBackend
extends Node

signal lobby_found(address: Variant, lobby_name: String, cur_players: int, max_players: int)
signal lobby_joined
signal join_lobby_failed(reason: String)
signal status_changed(text: String)
## Emitted once the lobby list is live; lobby_found follows. May fire synchronously from fetch_lobby_list.
signal listing_started

@abstract
func host_game(options: HostOptions) -> void
@abstract
func join_game(address: Variant) -> void
@abstract
func leave_game() -> void
@abstract
func fetch_lobby_list() -> void
@abstract
func set_joinable(joinable: bool) -> void
@abstract
func get_joinable() -> bool
@abstract
func get_uid(peer_id: int) -> Variant
@abstract
func get_username(peer_id: int) -> String
@abstract
func get_lobby_address() -> String

func _close_peer() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
