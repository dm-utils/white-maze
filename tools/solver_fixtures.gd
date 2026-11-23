extends RefCounted
## Extra levels for the solver equivalence test (design 23.10.4): the slope fixtures of the tests, a room with huts, a
## tall pillar between two steep roofs and gentle tiers, and a room with a raised floor, flush roofs and toes, so a
## random walk meets every slope branch of the simulation.

const FX := preload("res://tests/slope_fixtures.gd")

const ROOMS := {
	"fx-s": FX.S_ROWS,
	"fx-g": FX.G_ROWS,
	"fx-e": FX.E_ROWS,
	"fx-t": FX.T_ROWS,
	"fx-roofs": [
		"................................",
		"................................",
		"................................",
		"................................",
		"................................",
		"................................",
		"................................",
		"................................",
		"...................#............",
		"....../\\...........#....rRLl....",
		".S.../##\\...rRLl../#\\./.####.^F.",
		"################################",
	],
	"fx-tiers": [
		"................................",
		"................................",
		"................................",
		"................................",
		"................................",
		"................................",
		"................................",
		"................................",
		"..S.............................",
		"##########\\.Ll../#####\\..rRLl.F.",
		"################################",
		"################################",
	],
}


static func levels() -> Array[MazeLevel]:
	var out: Array[MazeLevel] = []
	for id in ROOMS:
		var rows: Array = ROOMS[id]
		out.append(MazeLevel.from_dict({
			"format": 2, "id": id, "name": {"nl": id, "en": id}, "difficulty": "easy", "beads": 3, "par": 0,
			"sky": true, "rows": rows,
		}))
	return out

