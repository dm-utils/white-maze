extends RefCounted
## L5: every level of the index and of the lab has a solution within par; replays are deterministic.

const SOLUTIONS := "res://tests/solutions.json"


func run(check: Callable, _node: Node) -> void:
	var solutions := WhitePuzzleStore.load_json(SOLUTIONS)
	for dir in [MazeLevels.DIR, MazeLevels.LAB_DIR]:
		for id in MazeLevels.ids(dir):
			_solution(check, solutions, id, MazeLevels.load_level(id, dir))


func _solution(check: Callable, solutions: Dictionary, id: String, lv: MazeLevel) -> void:
	check.call(solutions.has(id) and solutions[id] is String, "%s has a solution in solutions.json" % id)
	if not solutions.has(id):
		return
	var sim := MazeRunScript.run(lv, solutions[id])
	check.call(sim != null and sim.finished(), "%s: the solution finishes" % id)
	if sim == null or not sim.finished():
		return
	print(
		(
			"solution %s: %d ticks, %d rings, par %d, %d deaths"
			% [id, sim.time_ticks(), sim.rings_used, lv.par, sim.deaths]
		)
	)
	check.call(
		sim.rings_used <= lv.par, "%s: the solution uses %d rings, par is %d" % [id, sim.rings_used, lv.par]
	)
	check.call(sim.rings_used >= 1 or lv.par == 0, "%s: the solution launches off a thrown ring" % id)
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
		again.finished() and again.finish_tick == sim.finish_tick and again.rings_used == sim.rings_used,
		"%s: the encoded recording replays to the same finish" % id
	)
