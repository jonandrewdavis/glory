extends SceneTree
## Headless test: Godot --headless --path . -s tests/matchmaker_rank_test.gd

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true

func _run() -> void:
	var M = load("res://networking/matchmaker.gd")
	assert(M != null, "matchmaker script missing")

	var empty: Array[String] = M.rank_candidates({})
	assert(empty.is_empty(), "empty in -> empty out")

	var lobbies := {
		"FULL1": {"name": "a", "cur": 4, "max": 4},
		"LOW01": {"name": "b", "cur": 1, "max": 25},
		"HIGH2": {"name": "c", "cur": 3, "max": 25},
		"HIGH1": {"name": "d", "cur": 3, "max": 25},
		"OVER1": {"name": "e", "cur": 5, "max": 4},
		"NEAR1": {"name": "f", "cur": 24, "max": 25},
	}
	var ranked: Array[String] = M.rank_candidates(lobbies)
	assert(ranked == ["NEAR1", "HIGH1", "HIGH2", "LOW01"], "ranking got %s" % [ranked])

	var floats := {"K": {"name": "x", "cur": 2.0, "max": 25.0}}
	var f: Array[String] = M.rank_candidates(floats)
	assert(f == ["K"], "float counts accepted")

	print("Matchmaker rank checks passed: empty, full excluded, most populated first, ties by address, 24/25 included.")
