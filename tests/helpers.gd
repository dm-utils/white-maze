extends RefCounted
## Shared helpers for the suites: small maps, input builders, audited stepping.

const T := MazeTuning.TILE


## width x height map: empty, solid floor row at the bottom, S at (2, h - 2), F at (w - 2, 1); edits {Vector2i: char}
static func rows(width: int, height: int, edits: Dictionary = {}) -> Array:
	var grid: Array = []
	for y in height:
		grid.append(("#" if y == height - 1 else ".").repeat(width))
	var all := edits.duplicate()
	if not all.has("S"):
		all[Vector2i(2, height - 2)] = "S"
	if not all.has("F"):
		all[Vector2i(width - 2, 1)] = "F"
	for key in all:
		if key is Vector2i:
			var line: String = grid[key.y]
			grid[key.y] = line.substr(0, key.x) + all[key] + line.substr(key.x + 1)
	return grid


static func level(grid: Array, extra: Dictionary = {}) -> MazeLevel:
	var d := {
		"format": 1, "id": "t001", "name": {"nl": "T", "en": "T"}, "difficulty": "easy", "beads": 3, "par": 1,
		"rows": grid,
	}
	d.merge(extra, true)
	return MazeLevel.from_dict(d)


static func inp(move: int = 0, held: bool = false, pressed: bool = false, throw_dir: int = -1,
		undo: bool = false) -> MazeInput:
	var i := MazeInput.new()
	i.move = move
	i.jump_held = held
	i.jump_pressed = pressed
	i.throw_dir = throw_dir
	i.undo = undo
	return i


static func overlaps_solid(sim: MazeSim) -> bool:
	return not sim._box_free(sim.px - 15000, sim.py - 32000, sim.px + 15000, sim.py)


## steps n ticks with the same input; false when the player ever overlapped a solid cell
static func steps(sim: MazeSim, n: int, input: MazeInput) -> bool:
	var ok := true
	for i in n:
		sim.step(input)
		if overlaps_solid(sim):
			ok = false
	return ok


static func has_event(sim: MazeSim, type: String) -> bool:
	for e in sim.events:
		if e["type"] == type:
			return true
	return false


static func event(sim: MazeSim, type: String) -> Dictionary:
	for e in sim.events:
		if e["type"] == type:
			return e
	return {}


static func snap_no_tick(sim: MazeSim) -> String:
	var s := sim.snapshot()
	return s.substr(s.find("|"))
