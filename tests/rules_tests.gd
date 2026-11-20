extends RefCounted
## S15-S17: death and respawn, clock, determinism.

const H := preload("res://tests/helpers.gd")
const T := MazeTuning.TILE


func run(check: Callable, _node: Node) -> void:
	_spike_death(check)
	_fall_death(check)
	_clock(check)
	_determinism(check)


func _spike_death(check: Callable) -> void:
	var lv := H.level(H.rows(30, 12, {Vector2i(8, 8): "#", Vector2i(12, 10): "^"}))
	var sim := MazeSim.new(lv)
	sim.px = 12 * T + 20000
	sim.py = 9 * T - 1000
	sim.grounded = false
	# first a bead so that beads and rings differ from the start state
	sim.step(H.inp(0, false, false, 72))
	var beads := sim.beads_left
	var flights := sim.flights.size()
	var death_tick := -1
	var guard := 0
	while death_tick < 0 and guard < 100:
		sim.step(H.inp())
		guard += 1
		if H.has_event(sim, "death"):
			death_tick = sim.tick
	check.call(death_tick > 0 and sim.deaths == 1 and not sim.alive(), "touching a spike kills")
	var clock := sim.clock_start
	var alive_early := false
	for i in 29:
		sim.step(H.inp())
		alive_early = alive_early or sim.alive()
	check.call(not alive_early and sim.tick == death_tick + 29, "dead for 29 ticks after the death tick")
	sim.step(H.inp())
	check.call(sim.alive() and H.has_event(sim, "respawn") and sim.tick == death_tick + 30, "respawn exactly 30 ticks after death")
	check.call(sim.px == 2 * T + T / 2 and sim.py == 11 * T and sim.vx == 0 and sim.vy == 0 and sim.facing == 1,
			"respawn at the spawn with zero velocity")
	check.call(sim.beads_left == beads and sim.clock_start == clock and sim.deaths == 1,
			"beads, clock and death count survive a death")
	check.call(sim.rings.size() + flights >= 1, "rings and flights survive a death")


func _fall_death(check: Callable) -> void:
	var edits := {}
	for x in range(6, 30):
		edits[Vector2i(x, 11)] = "."
	var sim := MazeSim.new(H.level(H.rows(30, 12, edits)))
	var death_tick := -1
	for i in 200:
		sim.step(H.inp(1))
		if H.has_event(sim, "death"):
			death_tick = sim.tick
			break
	check.call(death_tick > 0 and sim.py - 32000 >= 12 * T, "falling out of the grid kills once the head is below it")
	var guard := 0
	while not H.has_event(sim, "respawn") and guard < 100:
		sim.step(H.inp(1))
		guard += 1
	check.call(sim.tick == death_tick + 30 and sim.px == 2 * T + T / 2, "respawn after a fall takes 30 ticks")


func _clock(check: Callable) -> void:
	var sim := MazeSim.new(H.level(H.rows(30, 12, {"F": Vector2i(), Vector2i(6, 10): "F"})))
	check.call(sim.time_ticks() == 0, "clock is 0 before any input")
	H.steps(sim, 20, H.inp())
	check.call(sim.time_ticks() == 0 and sim.clock_start < 0, "idle ticks do not start the clock")
	sim.step(H.inp(1))
	check.call(sim.clock_start == sim.tick and sim.time_ticks() == 1, "the first move starts the clock")
	var guard := 0
	while not sim.finished() and guard < 200:
		sim.step(H.inp(1))
		guard += 1
	check.call(sim.finished() and H.has_event(sim, "finish"), "touching F finishes")
	var ticks := sim.time_ticks()
	check.call(ticks == sim.finish_tick - sim.clock_start + 1, "time counts first active tick to finish tick inclusive")
	var frozen := H.snap_no_tick(sim)
	H.steps(sim, 30, H.inp(1, true, true))
	check.call(sim.time_ticks() == ticks and H.snap_no_tick(sim) == frozen, "after the finish only the tick counter changes")
	var jump_clock := MazeSim.new(H.level(H.rows(30, 12)))
	jump_clock.step(H.inp(0, true, true))
	check.call(jump_clock.time_ticks() == 1, "a jump press starts the clock")
	var throw_clock := MazeSim.new(H.level(H.rows(30, 12, {Vector2i(8, 10): "#"})))
	throw_clock.step(H.inp(0, false, false, 0))
	check.call(throw_clock.time_ticks() == 1, "a valid throw starts the clock")
	var bad_throw := MazeSim.new(H.level(H.rows(30, 12)))
	bad_throw.step(H.inp(0, false, false, 36))
	check.call(bad_throw.time_ticks() == 0, "an invalid throw does not start the clock")


func _script(i: int) -> MazeInput:
	var phase := i % 90
	var throw_dir := 108 if i == 200 else (18 if i == 330 else -1)
	return H.inp(1 if (i / 90) % 2 == 0 else -1, phase < 20, phase == 0, throw_dir, i == 410)


func _determinism(check: Callable) -> void:
	var lv := H.level(H.rows(30, 14, {Vector2i(10, 12): "#", Vector2i(11, 12): "#", Vector2i(15, 13): "^"}))
	var a := MazeSim.new(lv)
	var b := MazeSim.new(lv)
	var same := true
	for i in 600:
		a.step(_script(i))
		same = same and a.snapshot() == _replay_to(lv, i + 1).snapshot()
	b = _replay_to(lv, 600)
	check.call(same and a.snapshot() == b.snapshot(), "the same level and inputs give equal snapshots after every tick")


func _replay_to(lv: MazeLevel, ticks: int) -> MazeSim:
	var s := MazeSim.new(lv)
	for i in ticks:
		s.step(_script(i))
	return s
