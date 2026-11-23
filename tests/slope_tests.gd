extends RefCounted
## R5-R16, R18: slopes in the simulation on the fixtures of design 23.9.4 (tests/slope_fixtures.gd).

const H := preload("res://tests/helpers.gd")
const FX := preload("res://tests/slope_fixtures.gd")
const T := MazeTuning.TILE
const RUNS := 50
const TICKS := 1200


func run(check: Callable, _node: Node) -> void:
	_gentle_walk(check)
	_gentle_stand(check)
	_gentle_ridge(check)
	_slide(check)
	_bottom_joint(check)
	_eave(check)
	_landing(check)
	_metrics(check)
	_top_joints(check)
	_wall(check)
	_fuzz(check)
	_determinism(check)
	_ring_on_gutter(check)
	_cast(check)
	_look(check)


static func put(sim: MazeSim, x_px: float, y_px: float) -> void:
	sim.px = roundi(x_px * 1000.0)
	sim.py = roundi(y_px * 1000.0)
	sim.prev_px = sim.px
	sim.prev_py = sim.py
	sim._compute_ground()


static func has(sim: MazeSim, type: String) -> bool:
	return H.has_event(sim, type)


func _gentle_walk(check: Callable) -> void:
	var sim := MazeSim.new(FX.level(FX.G_ROWS))
	var ok_grounded := true
	var mono_x := true
	var mono_y := true
	var landed := false
	var flat_to_gentle := 0
	var prev_ground := sim.ground
	var last_x := sim.px
	var last_y := sim.py
	var stopped_at := -1
	for i in 150:
		sim.step(H.inp(1))
		ok_grounded = ok_grounded and sim.grounded
		mono_x = mono_x and sim.px >= last_x
		mono_y = mono_y and sim.py <= last_y
		landed = landed or has(sim, "land")
		if prev_ground != sim.ground:
			flat_to_gentle += 1
		prev_ground = sim.ground
		if stopped_at < 0 and sim.vx == 0 and i > 20:
			stopped_at = i
		last_x = sim.px
		last_y = sim.py
	check.call(ok_grounded, "R5: grounded on every tick walking up gentle slopes")
	check.call(mono_x and mono_y, "R5: px never decreases and py never increases walking up")
	check.call(not landed, "R5: no land event walking up")
	check.call(flat_to_gentle == 1 and sim.ground == MazeSim.Ground.GENTLE, "R5: ground goes FLAT to GENTLE once")
	check.call(sim.px + 15000 == 10 * T, "R5: the box's right edge stops at the wall (%d)" % (sim.px + 15000))
	var px := sim.px
	var py := sim.py
	H.steps(sim, 60, H.inp(1))
	check.call(sim.px == px and sim.py == py, "R5/R14: pressing into the wall keeps the position for 60 ticks")


func _gentle_stand(check: Callable) -> void:
	var sim := MazeSim.new(FX.level(FX.G_ROWS))
	put(sim, 6 * 40 + 10, 5 * 40 + 40 - 5)
	check.call(sim.ground == MazeSim.Ground.GENTLE, "R6: placed on a gentle slope")
	var px := sim.px
	var py := sim.py
	var steady := true
	for i in 120:
		sim.step(H.inp())
		steady = steady and sim.px == px and sim.py == py and sim.vx == 0 and sim.vy == 0
		steady = steady and sim.ground == MazeSim.Ground.GENTLE
	check.call(steady, "R6: standing on a gentle slope for 120 ticks changes nothing")


func _gentle_ridge(check: Callable) -> void:
	var sim := MazeSim.new(FX.level(FX.G_ROWS))
	put(sim, 16 * 40 + 6, 4 * 40 + 40 - 3)
	var ok := true
	var no_land := true
	var max_step := 0
	var last := sim.py
	for dir in [1, -1]:
		for i in 140:
			sim.step(H.inp(dir))
			ok = ok and sim.grounded
			no_land = no_land and not has(sim, "land")
			max_step = maxi(max_step, absi(sim.py - last))
			last = sim.py
			if (dir == 1 and sim.px > 20 * T) or (dir == -1 and sim.px < 16 * T + 8000):
				break
		check.call(
			(dir == 1 and sim.px > 20 * T) or (dir == -1 and sim.px < 16 * T + 8000),
			"R7: the gentle ridge is crossed (direction %d, px %.1f)" % [dir, sim.px / 1000.0]
		)
	check.call(ok and no_land, "R7: grounded on every tick and no land event over the gentle ridge")
	check.call(max_step <= MazeTuning.RUN_SPEED / 2 + 1000, "R7: no step in py above abs(vx)/2 + 1 px (%d)" % max_step)


func _slide(check: Callable) -> void:
	for mode in [0, -1, 1]:
		var sim := MazeSim.new(FX.level(FX.S_ROWS))
		put(sim, 8 * 40 + 10, 100)
		var slide_events := 0
		var land_tick := -1
		var reached := -1
		var increasing := true
		var grounded_all := true
		var on_slope_ticks := 0
		var last_y := 0
		var prev_steep := false
		var held_ok := true
		var goal := -MazeTuning.SLIDE_SPEED
		if mode == -1:
			goal = -MazeTuning.SLIDE_FAST
		elif mode == 1:
			goal = -MazeTuning.SLIDE_SLOW
		for i in 40:
			sim.step(H.inp(mode))
			slide_events += 1 if has(sim, "slide") else 0
			if land_tick < 0 and has(sim, "land"):
				land_tick = i
				check.call(sim.facing == -1 or mode == 1, "R8: facing points downhill after the landing (mode %d)" % mode)
			if land_tick >= 0 and sim.ground == MazeSim.Ground.STEEP:
				on_slope_ticks += 1
				grounded_all = grounded_all and sim.grounded
				increasing = increasing and (prev_steep == false or sim.py > last_y)
				if reached < 0 and sim.vx == goal:
					reached = i - land_tick
				if reached >= 0:
					held_ok = held_ok and sim.vx == goal
			elif land_tick >= 0:
				grounded_all = grounded_all and sim.grounded
			last_y = sim.py
			prev_steep = sim.ground == MazeSim.Ground.STEEP
		check.call(slide_events >= 1 and land_tick >= 0, "R8: a landing on a steep roof starts a slide (mode %d)" % mode)
		check.call(reached >= 0 and reached <= 14, "R8: the goal speed %d is reached within 14 ticks (%d, mode %d)" % [goal, reached, mode])
		check.call(held_ok, "R8: the speed stays at the goal while on the slope (mode %d)" % mode)
		check.call(increasing and on_slope_ticks > 5, "R8: py strictly increases on the slope (mode %d)" % mode)
		check.call(grounded_all, "R8: grounded on every tick of the slide (mode %d)" % mode)
	# exactly one slide event on a long slide, none while the slide goes on
	var sim := MazeSim.new(FX.level(FX.S_ROWS))
	put(sim, 8 * 40 + 10, 100)
	var n := 0
	for i in 45:
		sim.step(H.inp())
		n += 1 if has(sim, "slide") else 0
	check.call(n == 1, "R8: one slide event for the whole staircase (%d)" % n)


func _bottom_joint(check: Callable) -> void:
	var sim := MazeSim.new(FX.level(FX.S_ROWS))
	put(sim, 6 * 40 + 20, 6 * 40 + 20)
	check.call(sim.ground == MazeSim.Ground.STEEP, "R9: placed on the steep slope")
	var none_ticks := 0
	var lands := 0
	var ticks_on_floor := []
	for i in 40:
		sim.step(H.inp())
		none_ticks += 1 if sim.ground == MazeSim.Ground.NONE else 0
		lands += 1 if has(sim, "land") else 0
		if sim.ground == MazeSim.Ground.FLAT:
			ticks_on_floor.append(sim.vx)
	check.call(none_ticks == 0 and lands == 0, "R9: no airborne tick and no land event at the bottom joint")
	var decel_ok := ticks_on_floor.size() > 3
	for i in range(1, ticks_on_floor.size()):
		var step: int = ticks_on_floor[i] - ticks_on_floor[i - 1]
		if ticks_on_floor[i] != 0 and ticks_on_floor[i - 1] != 0:
			decel_ok = decel_ok and step == MazeTuning.GROUND_DECEL
	check.call(decel_ok, "R9: on the floor vx changes by GROUND_DECEL per tick")


func _eave(check: Callable) -> void:
	var sim := MazeSim.new(FX.level(FX.E_ROWS))
	put(sim, 13 * 40 + 8, 3 * 40 + 8)
	check.call(sim.ground == MazeSim.Ground.STEEP, "R10: placed on the right side of the roof")
	var t0 := -1
	var was_steep := false
	for i in 80:
		sim.step(H.inp())
		was_steep = was_steep or sim.ground == MazeSim.Ground.STEEP
		if was_steep and sim.ground == MazeSim.Ground.NONE:
			t0 = i
			break
	check.call(t0 >= 0, "R10: the slide ends at the eave (tick %d)" % t0)
	check.call(sim.vy == MazeTuning.GRAVITY_DOWN, "R10: first tick without support has vy == GRAVITY_DOWN (%d)" % sim.vy)
	check.call(sim.px > 16 * T, "R10: the player leaves past the eave (%d)" % sim.px)
	var out := false
	var s2 := MazeSim.new(FX.level(FX.E_ROWS))
	put(s2, 13 * 40 + 8, 3 * 40 + 8)
	for i in 400:
		s2.step(H.inp())
		if s2.py - MazeTuning.PLAYER_H >= s2.level.height * T or s2.dead_ticks > 0:
			out = true
			break
	check.call(out, "R10: the player falls out of the grid if nothing is done")
	for k in range(1, 7):
		var s3 := MazeSim.new(FX.level(FX.E_ROWS))
		put(s3, 13 * 40 + 8, 3 * 40 + 8)
		var airborne := -1
		var was := false
		for i in 80:
			s3.step(H.inp())
			was = was or s3.ground == MazeSim.Ground.STEEP
			if was and s3.ground == MazeSim.Ground.NONE:
				airborne = i
				break
		for i in k - 1:
			s3.step(H.inp())
		s3.step(H.inp(0, true, true))
		check.call(has(s3, "jump") and airborne >= 0, "R10: a jump %d ticks after the eave still jumps (coyote)" % k)
	var s4 := MazeSim.new(FX.level(FX.E_ROWS))
	put(s4, 13 * 40 + 8, 3 * 40 + 8)
	var was4 := false
	for i in 80:
		s4.step(H.inp())
		was4 = was4 or s4.ground == MazeSim.Ground.STEEP
		if was4 and s4.ground == MazeSim.Ground.NONE:
			break
	H.steps(s4, 6, H.inp())
	s4.step(H.inp(0, true, true))
	check.call(not has(s4, "jump"), "R10: a jump 7 ticks after the eave is too late")


func _landing(check: Callable) -> void:
	var sim := MazeSim.new(FX.level(FX.S_ROWS))
	put(sim, 8 * 40 + 10, 100)
	var vy_before := 0
	var lands := 0
	var landing_vx := 0
	for i in 40:
		var vy_prev := sim.vy
		sim.step(H.inp())
		if has(sim, "land"):
			lands += 1
			vy_before = vy_prev + MazeTuning.GRAVITY_DOWN
			landing_vx = sim.vx
			break
	check.call(lands == 1 and landing_vx == (0 - vy_before) / 2, "R11: landing on a steep roof gives vx %d == (0 - %d) / 2" % [landing_vx, vy_before])
	var g := MazeSim.new(FX.level(FX.G_ROWS))
	put(g, 6 * 40 + 10, 100)
	var gl := 0
	var gvx := 0
	for i in 40:
		g.step(H.inp())
		if has(g, "land"):
			gl += 1
			gvx = g.vx
			break
	check.call(gl == 1 and gvx == 0, "R11: landing on a gentle slope leaves vx unchanged (%d)" % gvx)
	var s2 := MazeSim.new(FX.level(FX.G_ROWS))
	put(s2, 6 * 40 + 10, 100)
	s2.vx = 3000
	var expect := MazeSim._approach(3000, 0, MazeTuning.AIR_DRAG)
	for i in 40:
		s2.step(H.inp())
		if has(s2, "land"):
			break
	check.call(s2.vx <= 3000 and s2.vx >= 0, "R11: landing on a gentle slope with speed keeps it (vx %d, expected near %d)" % [s2.vx, expect])
	var fall := MazeSim.new(FX.level(FX.S_ROWS))
	put(fall, 8 * 40 + 10, 20)
	var steps := 0
	while not fall.grounded and steps < 100:
		fall.step(H.inp())
		steps += 1
	check.call(fall.vx == -MazeTuning.MAX_FALL / 2 or fall.vx < -5000, "R11: a fall at MAX_FALL turns into a 450 px/s slide (%d)" % fall.vx)


## roomy level for the metrics: a staircase of steep slopes falling to the left, a gentle pair and a flat floor
func _room() -> MazeLevel:
	var edits := {}
	for k in 10:
		edits[Vector2i(20 + k, 18 - k)] = "/"
		for y in range(19 - k, 24):
			edits[Vector2i(20 + k, y)] = "#"
	for y in range(9, 24):
		edits[Vector2i(30, y)] = "#"
	edits[Vector2i(6, 22)] = "r"
	edits[Vector2i(7, 22)] = "R"
	edits[Vector2i(2, 22)] = "S"
	return FX.level(H.rows(48, 24, edits))


## feet lift above the take-off point of a full jump from here
func _lift_of(lv: MazeLevel, x: float, y: float) -> float:
	var sim := MazeSim.new(lv)
	put(sim, x, y)
	var start_y := sim.py
	var top := sim.py
	sim.step(H.inp(0, true, true))
	for n in 200:
		top = mini(top, sim.py)
		sim.step(H.inp(0, true, false))
		if sim.grounded:
			break
	return (start_y - top) / float(T)


## horizontal distance until the feet are back at the take-off height; the player slides first, then jumps
func _slide_jump(lv: MazeLevel, hold: int) -> float:
	var sim := MazeSim.new(lv)
	put(sim, 29 * 40 + 30, 9 * 40 + 40 - 30)
	for i in 14:
		sim.step(H.inp(hold))
	var start_x := sim.px
	var start_y := sim.py
	var speed := sim.vx
	sim.step(H.inp(hold, true, true))
	var top := sim.py
	for n in 120:
		sim.step(H.inp(hold, true, false))
		top = mini(top, sim.py)
		if sim.py >= start_y and sim.py > top:
			break
	return absf(sim.px - start_x) / float(T) if speed != 0 else 0.0


func _metrics(check: Callable) -> void:
	var lv := _room()
	check.call(lv.valid(), "R12: the metrics room is valid (%s)" % str(lv.errors))
	var gentle := _lift_of(lv, 6 * 40 + 10, 22 * 40 + 40 - 5)
	var steep := _lift_of(lv, 24 * 40 + 20, 14 * 40 + 20)
	check.call(gentle >= 3.1 and gentle <= 3.6, "R12: full jump from a gentle slope lifts 3.1-3.6 tiles (%.2f)" % gentle)
	check.call(steep >= 3.1 and steep <= 3.6, "R12: full jump from a steep slope lifts 3.1-3.6 tiles (%.2f)" % steep)
	var plain := _slide_jump(lv, 0)
	var fast := _slide_jump(lv, -1)
	check.call(plain >= 4.0 and plain <= 5.5, "R12: a jump from a slide without input covers 4 to 5.5 tiles (%.2f)" % plain)
	check.call(fast >= 5.5 and fast <= 7.2, "R12: a jump from a slide holding downhill covers 5.5 to 7 tiles (%.2f)" % fast)
	print("metrics: lift gentle %.2f steep %.2f tiles; slide jump %.2f, holding downhill %.2f tiles" % [gentle, steep, plain, fast])
	# running jump from a gentle slope over a gap: distance at equal height
	var sim := MazeSim.new(lv)
	put(sim, 7 * 40 + 20, 22 * 40 + 20 - 10)
	H.steps(sim, 10, H.inp(1))
	var start_x := sim.px
	var start_y := sim.py
	sim.step(H.inp(1, true, true))
	var gap := 0.0
	for n in 120:
		sim.step(H.inp(1, true, false))
		if sim.py >= start_y and n > 5:
			gap = (sim.px - start_x) / float(T)
			break
	check.call(gap >= 4.0, "R12: a running jump from a gentle slope clears 4 tiles (%.2f)" % gap)
	# an eave at 480 px/s: forward distance while falling one tile
	var fall := MazeSim.new(lv)
	put(fall, 36 * 40, 10 * 40)
	fall.vx = MazeTuning.SLIDE_FAST
	fall.grounded = false
	var x0 := fall.px
	var y0 := fall.py
	for n in 60:
		fall.step(H.inp(0))
		if fall.py - y0 >= T:
			break
	var drop := (fall.px - x0) / float(T)
	check.call(drop > 1.5 and drop < 2.1, "R12: off an eave at 480 px/s one tile of fall covers about 1.8 tiles (%.2f)" % drop)
	print("metrics: running jump gap %.2f tiles, eave at 480 px/s %.2f tiles forward per tile fallen" % [gap, drop])


func _top_joints(check: Callable) -> void:
	var sim := MazeSim.new(FX.level(FX.T_ROWS))
	var none_ticks := 0
	var lands := 0
	var slides := 0
	var reached := false
	for i in 120:
		sim.step(H.inp(-1))
		none_ticks += 1 if sim.ground == MazeSim.Ground.NONE else 0
		lands += 1 if has(sim, "land") else 0
		slides += 1 if has(sim, "slide") else 0
		if sim.ground == MazeSim.Ground.STEEP:
			reached = true
	check.call(reached and none_ticks == 0 and lands == 0, "R13: walking left onto the steep slope: grounded, no land (none %d)" % none_ticks)
	check.call(slides == 1, "R13: the slide starts once at the joint (%d)" % slides)
	sim = MazeSim.new(FX.level(FX.T_ROWS))
	none_ticks = 0
	lands = 0
	var gentle := false
	for i in 120:
		sim.step(H.inp(1))
		none_ticks += 1 if sim.ground == MazeSim.Ground.NONE else 0
		lands += 1 if has(sim, "land") else 0
		gentle = gentle or sim.ground == MazeSim.Ground.GENTLE
	check.call(gentle and none_ticks == 0 and lands == 0, "R13: walking right down the gentle pair: grounded, no land (none %d)" % none_ticks)


func _wall(check: Callable) -> void:
	# the slope at the foot of a wall: pressing into the wall never enters it, the slide goes away from it
	var sim := MazeSim.new(FX.level(FX.S_ROWS))
	put(sim, 7 * 40 + 25, 5 * 40 + 40 - 25)
	var ok := sim.ground == MazeSim.Ground.STEEP
	for i in 30:
		sim.step(H.inp(1))
		ok = ok and sim.px <= 8 * T - 15000
	check.call(ok and sim.px < 7 * T, "R14: pressing into the wall at the high end still slides away (px %.1f)" % (sim.px / 1000.0))
	var right := MazeSim.new(FX.level(FX.S_ROWS))
	put(right, 10 * 40 + 15, 5 * 40 + 15)
	ok = right.ground == MazeSim.Ground.STEEP
	for i in 30:
		right.step(H.inp(-1))
		ok = ok and right.px >= 10 * T + 15000
	check.call(ok and right.px > 11 * T, "R14: the right side slides away from its wall too (px %.1f)" % (right.px / 1000.0))


func _invariants(sim: MazeSim, prev_ground: int, bad: Dictionary) -> void:
	if sim.grounded != (sim.ground != MazeSim.Ground.NONE):
		bad["grounded != ground"] = true
	if sim.ground == MazeSim.Ground.FLAT and posmod(sim.py, T) != 0:
		bad["FLAT off the grid"] = true
	var cx := MazeSim._fdiv(sim.px, T)
	for cy in [MazeSim._fdiv(sim.py - 1, T), MazeSim._fdiv(sim.py, T)]:
		var kind := sim.level.cell(cx, cy)
		if MazeSlope.is_slope(kind) and sim.py > MazeSlope.surface(kind, cy, sim.px - cx * T):
			bad["centre below a slope surface"] = true
	if not sim._box_free(sim.px - 15000, sim.py - 32000, sim.px + 15000, sim.py - MazeTuning.SLOPE_STEP):
		bad["box overlaps a block above the step band"] = true
	if not sim._box_free(sim.px - 15000, sim.py - 32000, sim.px + 15000, sim.py):
		var over_slope := sim._slope_under(sim.px, sim.py).x >= 0
		var from_slope := prev_ground == MazeSim.Ground.GENTLE or prev_ground == MazeSim.Ground.STEEP
		if not (over_slope or from_slope):
			bad["box overlaps a block away from slopes"] = true


func _fuzz(check: Callable) -> void:
	var levels: Array[MazeLevel] = []
	for rows in [FX.S_ROWS, FX.G_ROWS, FX.E_ROWS, FX.T_ROWS]:
		levels.append(FX.level(rows))
	for id in MazeLevels.ids("res://levels/lab/"):
		levels.append(MazeLevels.load_level(id, "res://levels/lab/"))
	var bad := {}
	var slides := 0
	var gentle := 0
	for lv in levels:
		for n in RUNS:
			var rng := WhiteRng.new(5000 + n)
			var sim := MazeSim.new(lv)
			var held := false
			var move := 0
			for i in TICKS:
				var inp := MazeInput.new()
				if rng.range_int(0, 99) < 15:
					move = rng.range_int(0, 2) - 1
				inp.move = move
				var want := held
				if rng.range_int(0, 99) < 10:
					want = not held
				inp.jump_held = want
				inp.jump_pressed = want and not held
				held = want
				var prev_ground := sim.ground
				sim.step(inp)
				if sim.dead_ticks > 0 or sim.finished():
					prev_ground = MazeSim.Ground.NONE
				_invariants(sim, prev_ground, bad)
				slides += 1 if sim.ground == MazeSim.Ground.STEEP else 0
				gentle += 1 if sim.ground == MazeSim.Ground.GENTLE else 0
	check.call(bad.is_empty(), "R15: random play keeps the slope invariants (%s)" % str(bad.keys()))
	check.call(slides > 1000 and gentle > 1000, "R15: random play uses steep (%d) and gentle (%d) ground" % [slides, gentle])


func _determinism(check: Callable) -> void:
	for rows in [FX.S_ROWS, FX.G_ROWS, FX.E_ROWS, FX.T_ROWS]:
		var lv := FX.level(rows)
		var a := MazeSim.new(lv)
		var b := MazeSim.new(lv)
		var rng := WhiteRng.new(77)
		var same := true
		for i in 600:
			var inp := MazeInput.new()
			inp.move = rng.range_int(0, 2) - 1
			inp.jump_held = rng.range_int(0, 99) < 30
			inp.jump_pressed = rng.range_int(0, 99) < 5
			a.step(inp)
			b.step(inp)
			same = same and a.snapshot() == b.snapshot()
		check.call(same, "R16: two runs on the same fixture give equal snapshots")
	var snap := MazeSim.new(FX.level(FX.S_ROWS)).snapshot().split("|")
	check.call(snap[8] == "true" and snap[9] == str(MazeSim.Ground.FLAT), "R16: snapshot() has ground after grounded")


func _ring_on_gutter(check: Callable) -> void:
	var lv := FX.level(FX.E_ROWS, {"rings": [{"x": 9, "y": 6, "face": "up"}]})
	check.call(lv.valid(), "R18: the gutter ring is valid (%s)" % str(lv.errors))
	var sim := MazeSim.new(lv)
	put(sim, 12 * 40 + 20, 3 * 40 + 20)
	var launch := {}
	var vx_at := 0
	for i in 120:
		sim.step(H.inp())
		if has(sim, "launch"):
			launch = H.event(sim, "launch")
			vx_at = sim.vx
			break
	check.call(not launch.is_empty(), "R18: the slide reaches the gutter ring")
	check.call(sim.vy == -MazeTuning.FLOOR_LAUNCH, "R18: launched with vy == -FLOOR_LAUNCH (%d)" % sim.vy)
	check.call(vx_at == -MazeTuning.SLIDE_SPEED, "R18: the slide speed is kept (%d)" % vx_at)
	check.call(sim.rings_used == 0, "R18: a preset ring does not count")
	var thrown := MazeSim.new(FX.level(FX.E_ROWS))
	thrown.rings.append({"cell": Vector2i(9, 6), "face": MazeLevel.Face.UP, "preset": false, "order": 0, "cooldown": 0, "used": false})
	put(thrown, 12 * 40 + 20, 3 * 40 + 20)
	for i in 120:
		thrown.step(H.inp())
		if thrown.rings_used > 0:
			break
	check.call(thrown.rings_used == 1, "R18: a thrown ring launched from a slide counts once")


func _cast(check: Callable) -> void:
	var lv := FX.level(FX.S_ROWS)
	var sim := MazeSim.new(lv)
	var t := sim.cast(0)
	check.call(
		not t["valid"] and t["reason"] == "slope" and t["cell"] == Vector2i(5, 7) and t["face"] == MazeLevel.Face.UP,
		"R17: a throw that first meets a slope is invalid with reason slope (%s)" % str(t)
	)
	var thrown := MazeSim.new(lv)
	thrown.step(H.inp(0, false, false, 0))
	var idle := MazeSim.new(lv)
	idle.step(H.inp())
	check.call(
		H.event(thrown, "throw_invalid").get("reason") == "slope" and thrown.beads_left == lv.beads
		and thrown.flights.is_empty() and thrown.snapshot() == idle.snapshot(),
		"R17: the invalid throw changes nothing"
	)
	check.call(
		not MazeArt.lip_face(lv, Vector2i(5, 8), MazeLevel.Face.UP)
		and not MazeArt.lip_face(lv, Vector2i(8, 5), MazeLevel.Face.LEFT)
		and MazeArt.lip_face(lv, Vector2i(3, 8), MazeLevel.Face.UP),
		"R17: faces covered by a slope have no lip; open faces keep theirs"
	)
	# a dead player and an empty hand still report their own reason first
	var dead := MazeSim.new(lv)
	dead.dead_ticks = 5
	check.call(dead.cast(0)["reason"] == "dead", "R17: dead wins over slope")
	var sky := FX.level(H.rows(16, 10), {"sky": true})
	var open := MazeSim.new(sky)
	var up := open.cast(36)
	check.call(not up["valid"] and up["reason"] == "none", "R17: a throw into open sky gives reason none (%s)" % up["reason"])
	var closed := MazeSim.new(FX.level(H.rows(16, 10)))
	var cap := closed.cast(36)
	check.call(not cap["valid"] and cap["reason"] == "no_ring", "R17: without sky the top edge gives no_ring (%s)" % cap["reason"])
	var side := open.cast(0)
	check.call(side["reason"] == "no_ring", "R17: sky does not open the sides (%s)" % side["reason"])


static func _in_polygon(p: Vector2, poly: PackedVector2Array, tol: float) -> bool:
	if Geometry2D.is_point_in_polygon(p, poly):
		return true
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= tol:
			return true
	return false


func _look(check: Callable) -> void:
	var inside := true
	var straight := true
	var counted := 0
	var trims := true
	var lips := true
	for world in 3:
		var skin := MazeSkins.skin(world)
		for rows in [FX.S_ROWS, FX.G_ROWS, FX.E_ROWS, FX.T_ROWS]:
			var lv := FX.level(rows)
			MazeSkin.begin(lv, skin)
			for y in lv.height:
				for x in lv.width:
					var c := Vector2i(x, y)
					if lv.slope(x, y):
						var shape := PackedVector2Array()
						for v in MazeSlope.polygon(lv.cell(x, y)):
							shape.append(Vector2(v) + Vector2(c) * 40.0)
						var prims := MazeTileShapes.slope(lv, skin, c)
						counted += 1
						straight = straight and prims[0]["pts"] == shape
						for pr in prims:
							var pts: PackedVector2Array = pr["pts"]
							for p in pts:
								inside = inside and _in_polygon(p, shape, 0.01)
					if lv.cell(x, y) != MazeLevel.Cell.SOLID:
						continue
					for f in 4:
						var front := c + MazeLevel.FACE_STEP[f]
						if lv.slope(front.x, front.y):
							trims = trims and not MazeSkin.rim_face(lv, c, f) and not MazeStaticLayer.lip_drawn(lv, c, f)
							lips = lips and MazeSkin.side(lv, c, f) == MazeSkin.Side.SLOPE
			MazeSkin.end()
	check.call(counted > 40, "R21: slope primitives were checked (%d tiles)" % counted)
	check.call(inside, "R21: every slope primitive lies inside its collision polygon")
	check.call(straight, "R21: the contour of a slope is the collision polygon, a straight surface")
	check.call(trims, "R21: no covered face has a rim or a lip")
	check.call(lips, "R21: a block face towards a slope is a slope side")
