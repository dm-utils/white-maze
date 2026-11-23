extends RefCounted
## R1: the ruins play bit for bit as before slopes. Hash of the per-tick state of every stored solution of l001-l009.

const SOLUTIONS := "res://tests/solutions.json"
const EXPECTED := "ed5d3873a5d602b74d300a169a765cd70e4e092e280ac6f84bef3cdfa5db17ad"


func run(check: Callable, _node: Node) -> void:
	var solutions := WhitePuzzleStore.load_json(SOLUTIONS)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var ticks := 0
	for n in range(1, 10):
		var id := "l%03d" % n
		var lv := MazeLevels.load_level(id)
		var sim := MazeSim.new(lv)
		for input in MazeRunScript.parse(solutions[id])["inputs"]:
			sim.step(input)
			ctx.update(_tuple(sim).to_utf8_buffer())
			ticks += 1
			if sim.finished():
				break
		check.call(sim.finished(), "%s: the solution finishes (R1 trace)" % id)
	var got := ctx.finish().hex_encode()
	print("inert trace: %d ticks, sha256 %s" % [ticks, got])
	check.call(got == EXPECTED, "R1: the trace of l001-l009 is unchanged (sha256 %s)" % got)


func _tuple(sim: MazeSim) -> String:
	return "%d,%d,%d,%d,%s,%d,%d,%s,%s,%d,%d,%d;" % [sim.px, sim.py, sim.vx, sim.vy, sim.grounded, sim.coyote,
			sim.buffer, sim.jumping, sim.launched, sim.lock_ticks, sim.dead_ticks, sim.rings_used]
