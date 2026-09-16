class_name Teams
extends RefCounted

enum Team {BLUE, ORANGE}
const SETTINGS = preload("res://scenes/gameplay/team_settings.tres")

static func display_name(team: int, viewer: int) -> String:
	if viewer not in [Team.BLUE, Team.ORANGE]:
		return team_name(team)
	if team == Team.BLUE:
		return SETTINGS.blue_friendly if viewer == team else SETTINGS.blue_enemy
	if team == Team.ORANGE:
		return SETTINGS.orange_friendly if viewer == team else SETTINGS.orange_enemy
	return "None"

static func are_enemies(first: int, second: int) -> bool:
	return first in [Team.BLUE, Team.ORANGE] and second in [Team.BLUE, Team.ORANGE] and first != second

const COLORS := {
	Team.BLUE: Color("87cefa"),
	Team.ORANGE: Color("ff8c1a"),
}
const NAMES := {
	Team.BLUE: "Blue",
	Team.ORANGE: "Orange",
}
const SPAWN_GROUPS := {
	Team.BLUE: "spawn_blue",
	Team.ORANGE: "spawn_orange",
}
const FALLBACK_SPAWN := {
	Team.BLUE: Vector2(-1500, -140),
	Team.ORANGE: Vector2(1500, -140),
}

static func color(team: int) -> Color:
	return COLORS.get(team, Color.WHITE)

static func team_name(team: int) -> String:
	return NAMES.get(team, "None")

static func spawn_position(tree: SceneTree, team: int, index: int) -> Vector2:
	var group: String = SPAWN_GROUPS.get(team, "")
	var points := tree.get_nodes_in_group(group) if not group.is_empty() else []
	if points.is_empty():
		return FALLBACK_SPAWN.get(team, Vector2.ZERO)
	var marker: Node2D = points[posmod(index, points.size())]
	return marker.global_position
