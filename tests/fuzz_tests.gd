extends RefCounted
## Independent property tests: seeded random input on the shipped levels and on small rooms, invariants checked
## after every tick (no overlap with solids, speed limits, bead book-keeping, ring set, determinism, frozen finish).

const H := preload("res://tests/helpers.gd")
const T := MazeTuning.TILE
const RUNS := 24
const TICKS := 500


func run(check: Callable, _node: Node) -> void:
	var levels: Array[MazeLevel] = []
	for id in MazeLevels.ids():
		levels.append(MazeLevels.load_level(id))
	levels.append(_room())
	var bad := {}
	var launches := 0
	var throws := 0
	var deaths := 0
	for lv in levels:
		for n in RUNS:
			var rng := WhiteRng.new(1000 + n)
			var a := MazeSim.new(lv)
			var b := MazeSim.new(lv)
			var held := false
			for i in TICKS:
				var inp := _random_input(rng, held, a)
				held = inp.jump_held
				var before_cast := a.snapshot()
				a.cast((i * 7) % MazeAim.STEPS)
				if a.snapshot() != before_cast:
					bad["cast mutates the state"] = true
				var was_finished := a.finished()
				var frozen := H.snap_no_tick(a)
				a.step(inp)
				b.step(inp)
				if a.snapshot() != b.snapshot():
					bad["two sims diverge"] = true
				if was_finished and H.snap_no_tick(a) != frozen:
					bad["state changes after the finish"] = true
				for e in a.events:
					launches += 1 if e["type"] == "launch" else 0
					throws += 1 if e["type"] == "throw" else 0
					deaths += 1 if e["type"] == "death" else 0
				_invariants(a, lv, bad)
	check.call(bad.is_empty(), "random play keeps every invariant (%s)" % str(bad.keys()))
	check.call(
		throws > 50 and launches > 20 and deaths > 5,
		"random play exercises throws (%d), launches (%d), deaths (%d)" % [throws, launches, deaths]
	)


func _room() -> MazeLevel:
	var edits := {}
	for x in range(6, 10):
		edits[Vector2i(x, 8)] = "#"
	for y in range(5, 12):
		edits[Vector2i(14, y)] = "#"
	edits[Vector2i(4, 12)] = "^"
	edits[Vector2i(5, 12)] = "^"
	edits[Vector2i(10, 11)] = "X"
	return H.level(H.rows(20, 14, edits))


func _random_input(rng: WhiteRng, held: bool, sim: MazeSim) -> MazeInput:
	var inp := MazeInput.new()
	if _n(rng, 100) < 20:
		inp.move = _n(rng, 3) - 1
	else:
		inp.move = sim.facing if _n(rng, 100) < 70 else 0
	var want_held := held
	if _n(rng, 100) < 12:
		want_held = not held
	inp.jump_held = want_held
	inp.jump_pressed = want_held and not held
	if _n(rng, 100) < 6:
		inp.throw_dir = _n(rng, MazeAim.STEPS)
	inp.undo = _n(rng, 100) < 2
	return inp


func _invariants(s: MazeSim, lv: MazeLevel, bad: Dictionary) -> void:
	if s.alive() and H.overlaps_solid(s):
		bad["player overlaps a solid cell"] = true
	if s.vy > MazeTuning.MAX_FALL:
		bad["vy above MAX_FALL"] = true
	if absi(s.vx) > MazeTuning.WALL_LAUNCH_X:
		bad["vx above the largest launch speed"] = true
	if s.vy < -MazeTuning.FLOOR_LAUNCH:
		bad["vy above the floor launch speed"] = true
	if s.beads_left < 0 or s.beads_left > lv.beads:
		bad["beads_left outside 0..beads"] = true
	var thrown := 0
	var seen := {}
	for r in s.rings:
		if not r["preset"]:
			thrown += 1
		var key := "%s/%d" % [r["cell"], r["face"]]
		if seen.has(key):
			bad["a face holds two rings"] = true
		seen[key] = true
		if lv.cell(r["cell"].x, r["cell"].y) != MazeLevel.Cell.SOLID:
			bad["ring not on a # block"] = true
		var front: Vector2i = r["cell"] + MazeLevel.FACE_STEP[r["face"]]
		if lv.solid(front.x, front.y):
			bad["ring on an unexposed face"] = true
		if r["cooldown"] < 0 or r["cooldown"] > MazeTuning.RING_COOLDOWN_TICKS:
			bad["cooldown out of range"] = true
	for f in s.flights:
		thrown += 1
		var key := "%s/%d" % [f["cell"], f["face"]]
		if seen.has(key):
			bad["a flight targets a taken face"] = true
		seen[key] = true
		if f["arrive_tick"] <= s.tick - 1:
			bad["a flight outlived its arrival"] = true
	if s.beads_left + thrown != lv.beads:
		bad["beads are not conserved"] = true
	var last := -2
	for r in s.rings:
		if not r["preset"]:
			if r["order"] <= last:
				bad["thrown rings are not in order"] = true
			last = r["order"]
	if s.dead_ticks < 0 or s.dead_ticks > MazeTuning.DEATH_TICKS:
		bad["dead_ticks out of range"] = true
	if s.lock_ticks < 0 or s.lock_ticks > MazeTuning.WALL_LOCK_TICKS:
		bad["lock_ticks out of range"] = true
	if s.clock_start > s.tick:
		bad["clock starts in the future"] = true
	if s.finished() and (s.clock_start < 0 or s.time_ticks() < 1):
		bad["finished without a clock"] = true


func _n(rng: WhiteRng, k: int) -> int:
	return rng.range_int(0, k - 1)
