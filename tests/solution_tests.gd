extends RefCounted
## L5: every level of the index has a solution within par; replays are deterministic.

const SOLUTIONS := "res://tests/solutions.json"


func run(check: Callable, _node: Node) -> void:
	var solutions := WhitePuzzleStore.load_json(SOLUTIONS)
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		check.call(solutions.has(id) and solutions[id] is String, "%s has a solution in solutions.json" % id)
		if not solutions.has(id):
			continue
		var sim := MazeRunScript.run(lv, solutions[id])
		check.call(sim != null and sim.finished(), "%s: the solution finishes" % id)
		if sim == null or not sim.finished():
			continue
		print(
			(
				"solution %s: %d ticks, %d beads, par %d, %d deaths"
				% [id, sim.time_ticks(), sim.beads_used(), lv.par, sim.deaths]
			)
		)
		check.call(
			sim.beads_used() <= lv.par, "%s: the solution uses %d beads, par is %d" % [id, sim.beads_used(), lv.par]
		)
		check.call(sim.beads_used() >= 1, "%s: the solution needs at least one bead" % id)
		check.call(sim.time_ticks() > 0, "%s: the solution takes time" % id)
		# replay twice: equal snapshots tick by tick
		var inputs: Array = MazeRunScript.parse(solutions[id])["inputs"]
		var a := MazeSim.new(lv)
		var b := MazeSim.new(lv)
		var same := true
		var recorded: Array = []
		for input in inputs:
			recorded.append(input)
			a.step(input)
			b.step(input)
			same = same and a.snapshot() == b.snapshot()
			if a.finished():
				break
		check.call(same and a.finish_tick == sim.finish_tick, "%s: replaying twice gives equal snapshots" % id)
		var again := MazeRunScript.run(lv, MazeRunScript.encode(recorded))
		check.call(
			again.finished() and again.finish_tick == sim.finish_tick and again.beads_used() == sim.beads_used(),
			"%s: the encoded recording replays to the same finish" % id
		)
