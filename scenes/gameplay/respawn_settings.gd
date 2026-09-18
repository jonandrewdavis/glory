class_name RespawnSettings
extends Resource

@export var minimum_delay := 2.0
@export var baseline_players := 2
@export var seconds_per_extra_player := 0.25
@export var protection_seconds := 2.0

func delay_for_population(players: int) -> float:
	return maxf(0.0, minimum_delay) + maxf(0.0, seconds_per_extra_player) * maxi(0, players - baseline_players)
