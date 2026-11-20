extends RefCounted
## S8-S14 and S19: ring launches, cooldown, throws and invalid throws, undo, rings used.

const H := preload("res://tests/helpers.gd")
const T := MazeTuning.TILE
const UP := MazeLevel.Face.UP
const DOWN := MazeLevel.Face.DOWN
const LEFT := MazeLevel.Face.LEFT
const RIGHT := MazeLevel.Face.RIGHT


func run(check: Callable, _node: Node) -> void:
	_floor_ring(check)
	_wall_ring(check)
	_ceiling_ring(check)
	_cooldown_and_order(check)
	_throw_and_invalid(check)
	_throw_down(check)
	_undo(check)
	_rings_used(check)


func _ring(x: int, y: int, face: String) -> Dictionary:
	return {"rings": [{"x": x, "y": y, "face": face}]}


func _apex(sim: MazeSim, input: MazeInput, ticks: int) -> int:
	var low := sim.py
	for i in ticks:
		sim.step(input)
		low = mini(low, sim.py)
	return low


func _floor_ring(check: Callable) -> void:
	var grid := H.rows(20, 16)
	var lv := H.level(grid, _ring(2, 15, "up"))
	check.call(lv.valid(), "floor ring test level is valid (%s)" % str(lv.errors))
	for held in [false, true]:
		var sim := MazeSim.new(lv)
		var low := _apex(sim, H.inp(0, held), 120)
		var lift := (15 * T - low) / float(T)
		check.call(
			lift >= 5.5 and lift <= 6.3,
			"floor ring lifts the feet 5.5 to 6.3 tiles, jump held %s (%.2f)" % [held, lift]
		)
	for incoming in [-8000, 0, 6000, MazeTuning.MAX_FALL]:
		var sim := MazeSim.new(lv)
		sim.py = 15 * T - 3 * T
		sim.vy = incoming
		sim.grounded = false
		var low := _apex(sim, H.inp(), 120)
		var lift := (15 * T - low) / float(T)
		check.call(
			lift >= 5.5 and lift <= 6.8,
			"floor ring gives the same bounce after incoming speed %d (lift %.2f)" % [incoming, lift]
		)
	var sim := MazeSim.new(lv)
	sim.step(H.inp())
	check.call(
		H.has_event(sim, "launch") and sim.vy == -MazeTuning.FLOOR_LAUNCH and not sim.grounded,
		"standing on a floor ring launches at once with vy = -FLOOR_LAUNCH (vy %d)" % sim.vy
	)


func _wall_ring(check: Callable) -> void:
	# ring on the right face of a block at x = 4; the player walks left into it
	var edits := {}
	for y in range(8, 15):
		edits[Vector2i(4, y)] = "#"
	var lv := H.level(H.rows(24, 16, edits), _ring(4, 14, "right"))
	check.call(lv.valid(), "wall ring level is valid (%s)" % str(lv.errors))
	var sim := MazeSim.new(lv)
	sim.px = 8 * T
	var guard := 0
	while not H.has_event(sim, "launch") and guard < 100:
		sim.step(H.inp(-1))
		guard += 1
	check.call(
		H.has_event(sim, "launch") and sim.vx == MazeTuning.WALL_LAUNCH_X and sim.vy <= -MazeTuning.WALL_LAUNCH_LIFT,
		"wall ring on a RIGHT face: vx = WALL_LAUNCH_X, vy <= -WALL_LAUNCH_LIFT (vx %d vy %d)" % [sim.vx, sim.vy]
	)
	var held_ok := true
	for i in 12:
		sim.step(H.inp(-1))
		held_ok = held_ok and sim.vx == MazeTuning.WALL_LAUNCH_X
	check.call(held_ok, "holding left for 12 ticks after a wall launch changes nothing")
	sim.step(H.inp(-1))
	check.call(sim.vx < MazeTuning.WALL_LAUNCH_X, "at tick 13 the input works again")
	# mirror: block at x = 19, ring on its left face, player walks right
	edits = {}
	for y in range(8, 15):
		edits[Vector2i(19, y)] = "#"
	lv = H.level(H.rows(24, 16, edits), _ring(19, 14, "left"))
	sim = MazeSim.new(lv)
	sim.px = 15 * T
	guard = 0
	while not H.has_event(sim, "launch") and guard < 100:
		sim.step(H.inp(1))
		guard += 1
	check.call(
		(
			H.has_event(sim, "launch")
			and sim.vx == -MazeTuning.WALL_LAUNCH_X
			and sim.vy <= -MazeTuning.WALL_LAUNCH_LIFT
			and sim.facing == -1
		),
		"wall ring on a LEFT face mirrors it (vx %d vy %d)" % [sim.vx, sim.vy]
	)
	held_ok = true
	for i in 12:
		sim.step(H.inp(1))
		held_ok = held_ok and sim.vx == -MazeTuning.WALL_LAUNCH_X
	sim.step(H.inp(1))
	check.call(held_ok and sim.vx > -MazeTuning.WALL_LAUNCH_X, "mirror lock lasts 12 ticks")
	# an already faster upward speed is kept
	sim = MazeSim.new(H.level(H.rows(24, 16, {Vector2i(4, 10): "#"}), _ring(4, 10, "right")))
	sim.px = 5 * T + 15000
	sim.py = 10 * T + 30000
	sim.vy = -16000
	sim.grounded = false
	sim.step(H.inp())
	check.call(
		H.has_event(sim, "launch") and sim.vy < -MazeTuning.WALL_LAUNCH_LIFT, "a faster rise is kept by a wall launch"
	)


func _ceiling_ring(check: Callable) -> void:
	var lv := H.level(H.rows(20, 16, {Vector2i(2, 10): "#"}), _ring(2, 10, "down"))
	check.call(lv.valid(), "ceiling ring level is valid (%s)" % str(lv.errors))
	var sim := MazeSim.new(lv)
	var launched := false
	for i in 80:
		sim.step(H.inp(0, true, i == 0))
		if H.has_event(sim, "launch"):
			launched = true
			break
	check.call(
		launched and sim.vy == MazeTuning.CEILING_LAUNCH, "ceiling ring sets vy = CEILING_LAUNCH (vy %d)" % sim.vy
	)
	check.call(not sim.launched, "a ceiling launch does not count as rising")


func _cooldown_and_order(check: Callable) -> void:
	# corridor: floor ring below, ceiling ring above; bounces between them
	var rings := [{"x": 2, "y": 15, "face": "up"}, {"x": 2, "y": 12, "face": "down"}]
	var lv := H.level(H.rows(12, 16, {Vector2i(2, 12): "#"}), {"rings": rings})
	check.call(lv.valid(), "corridor level is valid (%s)" % str(lv.errors))
	var sim := MazeSim.new(lv)
	var floor_launches: Array[int] = []
	for i in 80:
		sim.step(H.inp())
		for e in sim.events:
			if e["type"] == "launch" and e["face"] == UP:
				floor_launches.append(sim.tick)
	check.call(
		floor_launches.size() >= 2,
		"the corridor bounces the player repeatedly (%d floor launches)" % floor_launches.size()
	)
	var gap_ok := true
	for i in range(1, floor_launches.size()):
		gap_ok = gap_ok and floor_launches[i] - floor_launches[i - 1] >= MazeTuning.RING_COOLDOWN_TICKS
	check.call(gap_ok, "one ring never launches twice within 10 ticks")
	# two rings overlapping the player: one launch per tick, first in order
	var edits := {}
	for y in range(13, 15):
		edits[Vector2i(4, y)] = "#"
	lv = H.level(
		H.rows(12, 16, edits), {"rings": [{"x": 5, "y": 15, "face": "up"}, {"x": 4, "y": 14, "face": "right"}]}
	)
	check.call(lv.valid(), "overlapping rings level is valid (%s)" % str(lv.errors))
	sim = MazeSim.new(lv)
	sim.px = 5 * T + 15000
	sim.step(H.inp())
	var first: Array = sim.events.filter(func(e: Dictionary) -> bool: return e["type"] == "launch")
	check.call(first.size() == 1 and first[0]["face"] == UP, "two overlapping rings: only the first in order launches")
	sim.step(H.inp())
	var second: Array = sim.events.filter(func(e: Dictionary) -> bool: return e["type"] == "launch")
	check.call(second.size() == 1 and second[0]["face"] == RIGHT, "the second ring launches on the next tick")


func _throw_sim(edits: Dictionary = {}, extra: Dictionary = {}) -> MazeSim:
	return MazeSim.new(H.level(H.rows(40, 14, edits), extra))


func _throw_case(check: Callable, name: String, sim: MazeSim, dir: int, reason: String) -> void:
	var beads := sim.beads_left
	var ring_count := sim.rings.size()
	sim.step(H.inp(0, false, false, dir))
	var ev := H.event(sim, "throw_invalid")
	check.call(
		(
			ev.get("reason", "") == reason
			and sim.beads_left == beads
			and sim.flights.is_empty()
			and sim.rings.size() == ring_count
		),
		"invalid throw (%s) reports '%s' and changes nothing" % [name, reason]
	)


func _throw_and_invalid(check: Callable) -> void:
	# valid throw to the right at a block: ring on its left face
	var sim := _throw_sim({Vector2i(8, 12): "#"})
	var cast := sim.cast(0)
	check.call(
		cast["valid"] and cast["cell"] == Vector2i(8, 12) and cast["face"] == LEFT and cast["reason"] == "ok",
		"cast to the right hits the left face of the block"
	)
	check.call(
		cast["dist"] > 0 and cast["origin"] == Vector2i(sim.px, sim.py - 16000), "cast reports origin and distance"
	)
	sim.step(H.inp(0, false, false, 0))
	check.call(
		sim.beads_left == 2 and sim.flights.size() == 1 and H.has_event(sim, "throw") and sim.rings_used == 0,
		"a valid throw spends a bead, starts a flight and leaves rings used unchanged"
	)
	var arrive: int = sim.flights[0]["arrive_tick"]
	check.call(arrive > sim.tick and sim.rings.is_empty(), "the ring does not exist before the bead arrives")
	while sim.tick < arrive - 1:
		sim.step(H.inp())
	check.call(sim.rings.is_empty(), "no ring one tick before arrival")
	sim.step(H.inp())
	check.call(
		(
			sim.rings.size() == 1
			and H.has_event(sim, "ring")
			and sim.rings[0]["cell"] == Vector2i(8, 12)
			and sim.rings[0]["face"] == LEFT
			and not sim.rings[0]["preset"]
		),
		"the ring appears at the arrival tick"
	)
	check.call(sim.time_ticks() > 0, "a valid throw starts the clock")

	_throw_case(check, "no-ring block", _throw_sim({Vector2i(8, 12): "X"}), 0, "no_ring")
	_throw_case(check, "out of bounds left", _throw_sim(), 72, "no_ring")
	_throw_case(check, "out of bounds above", _throw_sim(), 36, "no_ring")
	_throw_case(check, "out of range", _throw_sim(), 0, "none")
	# corner approach: diagonal from a cell centre into the floor block under a solid block
	sim = _throw_sim({Vector2i(3, 12): "#"})
	sim.px = 2 * T + 20000
	sim.py = 12 * T + 36000
	_throw_case(check, "face not exposed", sim, 126, "no_ring")
	sim = _throw_sim()
	sim.px = 2 * T + 20000
	sim.py = 12 * T + 36000
	cast = sim.cast(126)
	check.call(
		cast["valid"] and cast["cell"] == Vector2i(3, 13) and cast["face"] == UP,
		"a diagonal corner hit picks the vertical face when |dy| >= |dx|"
	)
	sim = _throw_sim({Vector2i(6, 12): "^"})
	sim.px = 6 * T + 20000
	_throw_case(check, "spike in front", sim, 108, "hazard")
	# taken: during flight and after arrival
	sim = _throw_sim({Vector2i(8, 12): "#"})
	sim.step(H.inp(0, false, false, 0))
	_throw_case_keep(check, "face taken during flight", sim, 0, "taken")
	while sim.flights.size() > 0:
		sim.step(H.inp())
	_throw_case_keep(check, "face taken after arrival", sim, 0, "taken")
	# no beads left
	sim = _throw_sim({Vector2i(8, 12): "#"}, {"beads": 1})
	sim.step(H.inp(0, false, false, 0))
	sim.px = 20 * T
	sim.py = 13 * T
	_throw_case_keep(check, "no beads left", sim, 108, "no_beads")
	# dead
	sim = _throw_sim({Vector2i(8, 12): "#", Vector2i(3, 12): "^"})
	var guard := 0
	while sim.alive() and guard < 100:
		sim.step(H.inp(1))
		guard += 1
	check.call(not sim.alive(), "the player died on the spike")
	_throw_case(check, "while dead", sim, 0, "dead")
	check.call(not sim.cast(0)["valid"] and sim.cast(0)["reason"] == "dead", "cast reports dead")


## like _throw_case, but the sim may already hold rings or flights; compares against the state before
func _throw_case_keep(check: Callable, name: String, sim: MazeSim, dir: int, reason: String) -> void:
	var beads := sim.beads_left
	var ring_count := sim.rings.size()
	var flight_count := sim.flights.size()
	sim.step(H.inp(0, false, false, dir))
	var ev := H.event(sim, "throw_invalid")
	check.call(
		(
			ev.get("reason", "") == reason
			and sim.beads_left == beads
			and sim.flights.size() == flight_count
			and sim.rings.size() == ring_count
		),
		"invalid throw (%s) reports '%s' and changes nothing" % [name, reason]
	)


func _throw_down(check: Callable) -> void:
	var sim := MazeSim.new(H.level(H.rows(20, 12)))
	sim.step(H.inp(0, false, false, 108))
	check.call(H.has_event(sim, "throw") and sim.beads_left == 2, "throwing straight down while standing is valid")
	var throw_tick := sim.tick
	sim.step(H.inp())
	check.call(
		(
			sim.tick == throw_tick + 1
			and H.has_event(sim, "ring")
			and H.has_event(sim, "launch")
			and sim.vy == -MazeTuning.FLOOR_LAUNCH
		),
		"the floor ring under the player launches it on arrival"
	)
	check.call(sim.rings_used == 1 and H.event(sim, "launch")["counted"], "that launch counts one ring used")


func _undo(check: Callable) -> void:
	var lv := H.level(H.rows(40, 14, {Vector2i(8, 12): "#", Vector2i(12, 12): "#"}), _ring(30, 13, "up"))
	var sim := MazeSim.new(lv)
	sim.px = 20 * T
	sim.step(H.inp(0, false, false, 72))
	check.call(sim.flights.size() == 1 and sim.beads_left == 2, "throw before undo")
	sim.step(H.inp(0, false, false, -1, true))
	check.call(
		sim.flights.is_empty() and sim.beads_left == 3 and H.has_event(sim, "undo") and sim.rings_used == 0,
		"undo takes back a bead in flight and leaves rings used unchanged"
	)
	sim = MazeSim.new(lv)
	sim.px = 6 * T
	sim.step(H.inp(0, false, false, 0))
	sim.px = 20 * T
	sim.step(H.inp(0, false, false, 72))
	check.call(sim.beads_left == 1, "two beads thrown")
	var guard := 0
	while not sim.flights.is_empty() and guard < 100:
		sim.step(H.inp())
		guard += 1
	var thrown: int = sim.rings.filter(func(r: Dictionary) -> bool: return not r["preset"]).size()
	check.call(thrown == 2, "both beads became rings (%d)" % thrown)
	sim.step(H.inp(0, false, false, -1, true))
	var order_ok: bool = (
		sim.rings.filter(func(r: Dictionary) -> bool: return not r["preset"]).size() == 1 and sim.beads_left == 2
	)
	check.call(order_ok, "undo removes the latest thrown ring")
	var remaining: Dictionary = sim.rings.filter(func(r: Dictionary) -> bool: return not r["preset"])[0]
	check.call(remaining["order"] == 0, "the earlier ring stays")
	sim.step(H.inp(0, false, false, -1, true))
	var presets_left: int = sim.rings.filter(func(r: Dictionary) -> bool: return r["preset"]).size()
	check.call(
		sim.rings.size() == 1 and presets_left == 1 and sim.beads_left == 3, "second undo leaves only the preset ring"
	)
	var before := H.snap_no_tick(sim)
	sim.step(H.inp(0, false, false, -1, true))
	check.call(
		not H.has_event(sim, "undo") and H.snap_no_tick(sim) == before,
		"undo with nothing thrown changes nothing (preset stays)"
	)


## S19: rings used (ADR 0009)
func _rings_used(check: Callable) -> void:
	var lv := H.level(H.rows(30, 14, {Vector2i(8, 12): "#"}), {"par": 5})
	# a) landed ring, never touched; undo returns the bead
	var sim := MazeSim.new(lv)
	sim.step(H.inp(0, false, false, 0))
	_settle(sim)
	check.call(sim.rings.size() == 1 and sim.rings_used == 0, "S19a: a landed ring nobody touched counts 0")
	sim.step(H.inp(0, false, false, -1, true))
	check.call(sim.beads_left == 3 and sim.rings_used == 0, "S19a: undo returns the bead, still 0")
	# b) taken back in flight
	sim = MazeSim.new(lv)
	sim.step(H.inp(0, false, false, 0))
	sim.step(H.inp(0, false, false, -1, true))
	_settle(sim)
	check.call(sim.rings_used == 0 and sim.beads_left == 3, "S19b: a bead taken back in flight counts 0")
	# c) bounce on an own floor ring at least three times
	var floor_lv := H.level(H.rows(20, 12), {"par": 3})
	sim = MazeSim.new(floor_lv)
	sim.step(H.inp(0, false, false, 108))
	var counted: Array[bool] = []
	for i in 200:
		sim.step(H.inp())
		for e in sim.events:
			if e["type"] == "launch":
				counted.append(e["counted"])
	check.call(
		counted.size() >= 3 and counted[0] and not counted.slice(1).has(true) and sim.rings_used == 1,
		"S19c: %d bounces on one own ring count 1, only the first launch is counted" % counted.size()
	)
	# d) undo after the launch, throw to the same face again: second ring used
	check.call(sim.beads_left == 2, "S19d: one bead is out before the undo")
	sim.step(H.inp(0, false, false, -1, true))
	check.call(
		sim.beads_left == floor_lv.beads and sim.rings_used == 1, "S19d: undo after the launch returns the bead, 1 stays"
	)
	sim.step(H.inp(0, false, false, 108))
	var guard := 0
	while sim.rings_used < 2 and guard < 300:
		sim.step(H.inp())
		guard += 1
	check.call(sim.rings_used == 2, "S19d: the same face thrown again and used counts 2")
	# e) preset ring
	var preset_lv := H.level(H.rows(20, 16), _ring(2, 15, "up"))
	sim = MazeSim.new(preset_lv)
	sim.step(H.inp())
	var launch := H.event(sim, "launch")
	check.call(
		not launch.is_empty() and launch["counted"] == false and sim.rings_used == 0,
		"S19e: a preset ring launches without counting"
	)
	# f) misuse: one bead, three cycles of throw, launch, undo
	var one := H.level(H.rows(20, 12), {"beads": 1, "par": 3})
	sim = MazeSim.new(one)
	for cycle in 3:
		sim.step(H.inp(0, false, false, 108))
		guard = 0
		var before := sim.rings_used
		while sim.rings_used == before and guard < 100:
			sim.step(H.inp())
			guard += 1
		sim.step(H.inp(0, false, false, -1, true))
	check.call(
		sim.beads_left == 1 and sim.rings_used == 3,
		"S19f: three throw, launch, undo cycles with one bead count 3 (%d)" % sim.rings_used
	)
	# g) death keeps the count; a new sim starts at 0
	var spike := H.level(H.rows(20, 12, {Vector2i(8, 10): "^", Vector2i(9, 10): "^"}), {"par": 1})
	sim = MazeSim.new(spike)
	sim.step(H.inp(0, false, false, 108))
	guard = 0
	while sim.rings_used == 0 and guard < 100:
		sim.step(H.inp())
		guard += 1
	sim.px = 8 * T + T
	sim.py = 10 * T
	sim.grounded = false
	guard = 0
	while sim.alive() and guard < 100:
		sim.step(H.inp())
		guard += 1
	check.call(not sim.alive() and sim.rings_used == 1, "S19g: a death after a counted launch keeps rings used")
	check.call(MazeSim.new(spike).rings_used == 0, "S19g: a new sim starts at 0")
	# h) finish event carries rings
	sim = MazeSim.new(H.level(H.rows(20, 12, {"F": Vector2i(), Vector2i(9, 10): "F"}), {"par": 1}))
	sim.step(H.inp(0, false, false, 108))
	guard = 0
	while not sim.finished() and guard < 300:
		sim.step(H.inp(1))
		guard += 1
	var fin := H.event(sim, "finish")
	check.call(
		sim.finished() and fin.get("rings", -1) == sim.rings_used and sim.rings_used >= 1,
		"S19h: the finish event carries rings (%s)" % str(fin)
	)


func _settle(sim: MazeSim) -> void:
	var guard := 0
	while not sim.flights.is_empty() and guard < 200:
		sim.step(H.inp())
		guard += 1
