extends RefCounted
## S2-S7: walking, jumping, coyote, buffer, corner correction, collisions on small hand-made maps.

const H := preload("res://tests/helpers.gd")
const T := MazeTuning.TILE


func run(check: Callable, _node: Node) -> void:
	_walk(check)
	_jump_height(check)
	_coyote(check)
	_buffer(check)
	_corner(check)
	_collisions(check)


func _walk(check: Callable) -> void:
	var sim := MazeSim.new(H.level(H.rows(30, 8)))
	check.call(sim.grounded and sim.px == 2 * T + T / 2 and sim.py == 7 * T, "spawn stands on the floor below S")
	var reached := -1
	var over := false
	for i in 20:
		sim.step(H.inp(1))
		if sim.vx > MazeTuning.RUN_SPEED:
			over = true
		if reached < 0 and sim.vx == MazeTuning.RUN_SPEED:
			reached = i + 1
	check.call(reached > 0 and reached <= 8, "full speed within 8 ticks (took %d)" % reached)
	check.call(not over, "walking never exceeds RUN_SPEED")
	var stop := 0
	while sim.vx != 0 and stop < 50:
		sim.step(H.inp(0))
		stop += 1
	check.call(stop <= 7, "stops within 7 ticks after release (took %d)" % stop)
	sim = MazeSim.new(H.level(H.rows(30, 8)))
	H.steps(sim, 3, H.inp(1))
	sim.step(H.inp(-1))
	check.call(sim.vx < 3 * MazeTuning.GROUND_ACCEL, "turning around on the ground brakes harder than speeding up")
	check.call(sim.facing == -1, "facing follows the input")


func _jump_run(sim: MazeSim, held_ticks: int) -> int:
	var floor_y := sim.py
	var top := sim.py
	var n := 0
	sim.step(H.inp(0, true, true))
	while not sim.grounded and n < 200:
		n += 1
		top = mini(top, sim.py)
		sim.step(H.inp(0, n < held_ticks, false))
	return floor_y - top


func _jump_height(check: Callable) -> void:
	var tall := H.level(H.rows(20, 16))
	var full := _jump_run(MazeSim.new(tall), 1000) / float(T)
	check.call(full >= 3.1 and full <= 3.6, "full jump lifts the feet 3.1 to 3.6 tiles (%.2f)" % full)
	var tap := _jump_run(MazeSim.new(tall), 0) / float(T)
	check.call(tap >= 1.8 and tap <= 2.6, "tap jump lifts the feet 1.8 to 2.6 tiles (%.2f)" % tap)
	var sim := MazeSim.new(tall)
	H.steps(sim, 1, H.inp(0, true, true))
	check.call(H.has_event(sim, "jump") and sim.vy < 0, "a press on the ground jumps at once")
	sim = MazeSim.new(tall)
	var max_vy := 0
	sim.py -= 10 * T
	sim.grounded = false
	for i in 100:
		sim.step(H.inp())
		max_vy = maxi(max_vy, sim.vy)
	check.call(max_vy == MazeTuning.MAX_FALL, "falling speed is capped at MAX_FALL (%d)" % max_vy)


## ledge at x = 8: floor only left of it; walk off, then press n ticks after the walk-off tick
func _ledge_sim() -> MazeSim:
	var edits := {}
	for x in range(8, 30):
		edits[Vector2i(x, 11)] = "."
	return MazeSim.new(H.level(H.rows(30, 12, edits)))


func _coyote(check: Callable) -> void:
	for n in [6, 7]:
		var sim := _ledge_sim()
		var guard := 0
		while sim.grounded and guard < 200:
			sim.step(H.inp(1))
			guard += 1
		var jumped := false
		for i in n:
			sim.step(H.inp(1, false, i == n - 1))
			jumped = jumped or H.has_event(sim, "jump")
		check.call(
			jumped == (n == 6),
			"jump pressed %d ticks after leaving the ledge %s" % [n, "jumps" if n == 6 else "does not jump"]
		)


func _buffer(check: Callable) -> void:
	var tall := H.level(H.rows(20, 16))
	# tap jump, find the first tick that starts on the ground again
	var probe := MazeSim.new(tall)
	probe.step(H.inp(0, true, true))
	var landed_tick := -1
	for i in 200:
		probe.step(H.inp())
		if probe.grounded:
			landed_tick = probe.tick + 1
			break
	for n in [8, 9]:
		var sim := MazeSim.new(tall)
		sim.step(H.inp(0, true, true))
		var second_jump := -1
		while sim.tick < landed_tick + 3:
			var press: bool = sim.tick + 1 == landed_tick - n
			sim.step(H.inp(0, false, press))
			if second_jump < 0 and H.has_event(sim, "jump"):
				second_jump = sim.tick
		check.call(
			(second_jump == landed_tick) == (n == 8),
			"jump pressed %d ticks before the landing tick %s" % [n, "jumps on landing" if n == 8 else "is forgotten"]
		)


func _corner(check: Callable) -> void:
	var edits := {}
	for x in range(5, 12):
		edits[Vector2i(x, 4)] = "#"
	var lv := H.level(H.rows(16, 12, edits))
	# right edge 6 px / 10 px into the block at x = 5 tiles
	for case in [[191000, true, 185000], [195000, false, 195000]]:
		var sim := MazeSim.new(lv)
		sim.px = case[0]
		sim.py = 234000
		sim.vy = -5000
		sim.grounded = false
		sim.step(H.inp())
		if case[1]:
			check.call(
				sim.px == case[2] and sim.vy == -4000 and sim.py == 230000,
				"corner clipped by 6 px: slid left and kept rising (px %d vy %d)" % [sim.px, sim.vy]
			)
		else:
			check.call(
				sim.px == case[2] and sim.vy == 0 and sim.py == 232000,
				"corner clipped by 10 px: rise stops (px %d vy %d)" % [sim.px, sim.vy]
			)
	# mirror: block ends at x = 12 tiles; left edge 6 px / 10 px inside it
	var mirror := MazeSim.new(lv)
	mirror.px = 12 * T + 9000
	mirror.py = 234000
	mirror.vy = -5000
	mirror.grounded = false
	mirror.step(H.inp())
	check.call(
		mirror.px == 12 * T + 15000 and mirror.vy == -4000,
		"mirror corner: slid right and kept rising (px %d)" % mirror.px
	)
	var blocked := MazeSim.new(lv)
	blocked.px = 12 * T + 5000
	blocked.py = 234000
	blocked.vy = -5000
	blocked.grounded = false
	blocked.step(H.inp())
	check.call(blocked.vy == 0 and blocked.py == 232000, "mirror corner clipped by 10 px: rise stops")
	# a head that hits the middle of a ceiling is stopped
	var mid := MazeSim.new(lv)
	mid.px = 8 * T + 20000
	mid.py = 234000
	mid.vy = -5000
	mid.grounded = false
	mid.step(H.inp())
	check.call(mid.vy == 0 and mid.py == 232000 and mid.px == 8 * T + 20000, "full ceiling hit stops the rise")


func _collisions(check: Callable) -> void:
	var lv := H.level(H.rows(20, 8, {Vector2i(10, 6): "#", Vector2i(10, 5): "#", Vector2i(10, 4): "#"}))
	var sim := MazeSim.new(lv)
	var clean := H.steps(sim, 120, H.inp(1))
	check.call(clean, "never overlaps a solid cell while walking into a wall")
	check.call(
		sim.px == 10 * T - 15000 and sim.vx == 0, "full speed into a wall stops flush at the wall (px %d)" % sim.px
	)
	sim = MazeSim.new(H.level(H.rows(20, 8, {Vector2i(5, 6): "#", Vector2i(5, 5): "#", Vector2i(5, 4): "#"})))
	sim.px = 9 * T
	sim.step(H.inp(-1))
	var left_clean := H.steps(sim, 100, H.inp(-1))
	check.call(left_clean and sim.px == 6 * T + 15000, "walking left into a wall stops flush (px %d)" % sim.px)
	# jumping around: no overlap ever
	sim = MazeSim.new(
		H.level(
			H.rows(
				30,
				12,
				{
					Vector2i(8, 10): "#",
					Vector2i(9, 10): "#",
					Vector2i(9, 9): "#",
					Vector2i(14, 6): "#",
					Vector2i(15, 6): "#",
					Vector2i(16, 6): "#"
				}
			)
		)
	)
	var ok := true
	for i in 600:
		var jump_now := i % 40 == 0
		ok = H.steps(sim, 1, H.inp(1 if (i / 100) % 2 == 0 else -1, i % 40 < 25, jump_now)) and ok
	check.call(ok, "never overlaps a solid cell while jumping around blocks")
	# landing on a ledge from above ends flush
	sim = MazeSim.new(H.level(H.rows(12, 12, {Vector2i(2, 6): "#"})))
	sim.py = 5 * T
	sim.vy = MazeTuning.MAX_FALL
	sim.grounded = false
	H.steps(sim, 10, H.inp())
	check.call(sim.py == 6 * T and sim.grounded and sim.vy == 0, "fast fall lands flush on the block (py %d)" % sim.py)
