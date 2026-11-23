extends RefCounted
## CAM1-CAM14: the camera rig on its own (driven by MazeSim with explicit time steps) and in the game screen.

const H := preload("res://tests/helpers.gd")
const SOLUTIONS := "res://tests/solutions.json"
const C := preload("res://tests/controls_tests.gd")
const PROFILE := "user://white_maze_test_camera.json"
const DT := 1.0 / 60.0
const BAND := 110.0
const DESKTOP := Vector2(1280, 720)
const PHONE := Vector2(1600, 720)
const TABLET := Vector2(1280, 960)

var _check: Callable
var _node: Node


func run(check: Callable, node: Node) -> void:
	_check = check
	_node = node
	_zoom()
	_level_clamp_and_player_in_view()
	_calm_jumps()
	_launch()
	_look_ahead()
	_falling()
	_sliding()
	_aim_framing()
	_snap()
	_intro()
	_overview()
	_game_snap()
	_game_intro()
	_game_overview()
	_game_same_frame()
	_game_mouse()
	_game_fixed_layers()
	_clean()


## floor from row floor_y down, spawn on it at (2, floor_y - 1); edits {Vector2i: char}
func _fixture(w: int, h: int, floor_y: int, edits: Dictionary = {}, extra: Dictionary = {}) -> MazeLevel:
	var grid: Array = []
	for y in h:
		grid.append(("#" if y >= floor_y else ".").repeat(w))
	var all := edits.duplicate()
	if not all.values().has("S"):
		all[Vector2i(2, floor_y - 1)] = "S"
	if not all.values().has("F"):
		all[Vector2i(w - 2, 1)] = "F"
	for key in all:
		if key is Vector2i:
			var line: String = grid[key.y]
			grid[key.y] = line.substr(0, key.x) + all[key] + line.substr(key.x + 1)
	return H.level(grid, extra)


func _rig(lv: MazeLevel, canvas: Vector2 = DESKTOP) -> MazeCameraRig:
	var r := MazeCameraRig.new()
	_setup(r, lv, canvas)
	return r


func _setup(r: MazeCameraRig, lv: MazeLevel, canvas: Vector2) -> void:
	var door := (Vector2(lv.finish) + Vector2(0.5, 0.5)) * 40.0
	r.setup(Vector2(lv.width, lv.height) * 40.0, canvas, BAND, door)


func _frame(sim: MazeSim, aim_frame: bool = false, hit: Vector2 = Vector2.ZERO) -> Dictionary:
	return {
		"player": Vector2(sim.px / 1000.0, sim.py / 1000.0 - 16.0),
		"vel": Vector2(sim.vx, sim.vy) * 60.0 / 1000.0,
		"grounded": sim.grounded, "alive": sim.alive(), "facing": sim.facing,
		"aim_frame": aim_frame, "aim_hit": hit, "flights": not sim.flights.is_empty(),
	}


## follow centre (world px) of the rig, whatever the view is
func _centre(r: MazeCameraRig) -> Vector2:
	return r.play_rect().get_center()


## one tick of the sim and one frame of the rig; snaps on a respawn like MazeGame
func _tick(
	sim: MazeSim, r: MazeCameraRig, inp: MazeInput, aim_frame: bool = false, hit: Vector2 = Vector2.ZERO
) -> void:
	sim.step(inp)
	if H.has_event(sim, "respawn"):
		r.snap(_frame(sim, aim_frame, hit))
	else:
		r.update(DT, _frame(sim, aim_frame, hit))


func _zoom() -> void:
	var z1 := MazeCameraRig.target_zoom(DESKTOP)
	var z2 := MazeCameraRig.target_zoom(PHONE)
	var z3 := MazeCameraRig.target_zoom(TABLET)
	_check.call(
		is_equal_approx(z1, 2.0) and is_equal_approx(z2, 2.0),
		"CAM1 zoom is 2.0 on 16:9 and 20:9 (%f, %f)" % [z1, z2]
	)
	_check.call(is_equal_approx(z3, 2.0), "CAM1 zoom is 2.0 on 4:3 (%f)" % z3)
	_check.call(
		32.0 * z1 / DESKTOP.y >= 0.085 and 32.0 * z2 / PHONE.y >= 0.085,
		"CAM1 Lilith is at least 8.5 % of the height"
	)
	_check.call(32.0 * z3 / TABLET.y >= 0.065, "CAM1 Lilith is at least 6.5 % of the height on 4:3")
	var l001 := Vector2(48, 14) * 40.0
	var l006 := Vector2(32, 24) * 40.0
	_check.call(
		absf(MazeCameraRig.fit_zoom(l001, DESKTOP, BAND) - 0.646) < 0.001,
		"CAM1 fit zoom of l001 on desktop is 0.646"
	)
	_check.call(
		absf(MazeCameraRig.fit_zoom(l006, DESKTOP, BAND) - 0.594) < 0.001,
		"CAM1 fit zoom of l006 on desktop is 0.594"
	)
	_check.call(
		absf(MazeCameraRig.fit_zoom(l001, PHONE, BAND) - 0.813) < 0.001,
		"CAM1 fit zoom of l001 on the phone canvas is 0.813"
	)
	var never_above := true
	for c: Vector2 in [DESKTOP, PHONE, TABLET]:
		for s: Vector2 in [Vector2(10, 5) * 40.0, l001, l006, Vector2(64, 30) * 40.0]:
			never_above = never_above and MazeCameraRig.fit_zoom(s, c, BAND) <= MazeCameraRig.target_zoom(c) + 1e-9
	_check.call(never_above, "CAM1 fit zoom is never above the target zoom")


func _level_ids() -> PackedStringArray:
	return MazeLevels.ids()


func _level_clamp_and_player_in_view() -> void:
	var solutions := WhitePuzzleStore.load_json(SOLUTIONS)
	for id in _level_ids():
		var lv := MazeLevels.load_level(id)
		var inputs: Array = MazeRunScript.parse(solutions[id])["inputs"]
		var lvl_rect := Rect2(Vector2.ZERO, Vector2(lv.width, lv.height) * 40.0)
		for canvas: Vector2 in [DESKTOP, PHONE, TABLET]:
			var sim := MazeSim.new(lv)
			var r := _rig(lv, canvas)
			r.snap(_frame(sim))
			var clamp_ok := true
			var view_ok := true
			var frames := 0
			for inp: MazeInput in inputs:
				sim.step(inp)
				var f := _frame(sim)
				if H.has_event(sim, "respawn"):
					r.snap(f)
				else:
					r.update(DT, f)
				var pr := r.play_rect()
				if pr.size.x <= lvl_rect.size.x:
					clamp_ok = clamp_ok and pr.position.x >= -0.01 and pr.end.x <= lvl_rect.end.x + 0.01
				if pr.size.y <= lvl_rect.size.y:
					clamp_ok = clamp_ok and pr.position.y >= -0.01 and pr.end.y <= lvl_rect.end.y + 0.01
				if sim.alive():
					var p: Vector2 = f["player"]
					var lo := pr.position + Vector2(
						0.0 if pr.position.x <= 0.01 else 40.0, 0.0 if pr.position.y <= 0.01 else 40.0
					)
					var hi := pr.end - Vector2(
						0.0 if pr.end.x >= lvl_rect.end.x - 0.01 else 40.0,
						0.0 if pr.end.y >= lvl_rect.end.y - 0.01 else 40.0
					)
					view_ok = view_ok and Rect2(lo, hi - lo).grow(0.01).has_point(p)
				frames += 1
			_check.call(
				clamp_ok, "CAM2 %s at %s: the play rect stays inside the level (%d frames)" % [id, str(canvas), frames]
			)
			_check.call(view_ok, "CAM3 %s at %s: the player stays inside the play rect" % [id, str(canvas)])


## drives a sim with one input for n ticks and returns the view y range seen
func _view_y_span(sim: MazeSim, r: MazeCameraRig, inputs: Array) -> float:
	var lo := INF
	var hi := -INF
	for inp: MazeInput in inputs:
		_tick(sim, r, inp)
		var y := r.view_centre().y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return hi - lo


func _calm_jumps() -> void:
	var lv := _fixture(64, 30, 18)
	var sim := MazeSim.new(lv)
	var r := _rig(lv)
	r.snap(_frame(sim))
	var inputs: Array = []
	for i in 80:
		inputs.append(H.inp(0, i < 70, i == 0))
	var span := _view_y_span(sim, r, inputs)
	_check.call(span <= 1.0 and sim.grounded, "CAM4 a full jump moves the view by at most 1 px (%.3f)" % span)
	sim = MazeSim.new(lv)
	r = _rig(lv)
	r.snap(_frame(sim))
	inputs = []
	for j in 5:
		for i in 40:
			inputs.append(H.inp(0, i < 30, i == 0))
	span = _view_y_span(sim, r, inputs)
	_check.call(span <= 1.0, "CAM4 five jumps in a row move the view by at most 1 px (%.3f)" % span)


func _launch() -> void:
	var edits := {}
	for x in range(4, 64):
		for y in range(13, 18):
			edits[Vector2i(x, y)] = "#"
	var lv := _fixture(64, 30, 18, edits, {"rings": [{"x": 2, "y": 18, "face": "up"}]})
	_check.call(lv.valid(), "CAM5 launch fixture is valid (%s)" % str(lv.errors))
	var sim := MazeSim.new(lv)
	var r := _rig(lv)
	r.snap(_frame(sim))
	var worst := INF
	for i in 120:
		_tick(sim, r, H.inp(1))
		if sim.alive():
			worst = minf(worst, _frame(sim)["player"].y - r.play_rect().position.y)
	_check.call(
		worst >= MazeCameraRig.GUARD_TOP - 0.5,
		"CAM5 the player stays %.1f px below the top during the launch" % worst
	)
	_check.call(sim.grounded and sim.py == 13 * 40000, "CAM5 the player landed on the ledge")
	for i in 120:
		_tick(sim, r, H.inp())
	var z := MazeCameraRig.target_zoom(DESKTOP)
	var ph := (DESKTOP.y - BAND) / z
	var target := 13.0 * 40.0 - (MazeCameraRig.FEET_Y - 0.5) * ph - BAND / (2.0 * z)
	_check.call(
		absf(r.view_centre().y - target) <= 2.0,
		"CAM5 the view settles on the ledge within 2 s (%.2f)" % (r.view_centre().y - target)
	)


func _look_ahead() -> void:
	var lv := _fixture(64, 30, 18)
	var sim := MazeSim.new(lv)
	var r := _rig(lv)
	r.snap(_frame(sim))
	for i in 120:
		_tick(sim, r, H.inp(1))
	var lead := r.view_centre().x - sim.px / 1000.0
	_check.call(lead >= 60.0 and lead <= 120.0, "CAM6 walking right the view leads by 60 to 120 px (%.1f)" % lead)
	# reversal with a synthetic velocity so the timing does not depend on the deceleration
	var f := _frame(sim)
	f["vel"] = Vector2(-300.0, 0.0)
	var twin := _rig(lv)
	twin.snap(_frame(sim))
	for i in 9:
		twin.update(DT, f)
	_check.call(twin.look_dir() == 1, "CAM6 the look direction has not turned at 0.15 s")
	for i in 6:
		twin.update(DT, f)
	_check.call(twin.look_dir() == -1, "CAM6 the look direction has turned at 0.25 s")
	sim = MazeSim.new(_fixture(64, 30, 18, {Vector2i(40, 17): "S"}))
	r = _rig(sim.level)
	r.snap(_frame(sim))
	for i in 60:
		_tick(sim, r, H.inp(1))
	for i in 180:
		_tick(sim, r, H.inp(-1))
	_check.call(r.view_centre().x < sim.px / 1000.0, "CAM6 after 3 s of walking left the view is left of the player")
	# a short tap the other way does not swing the view
	sim = MazeSim.new(lv)
	r = _rig(lv)
	r.snap(_frame(sim))
	for i in 60:
		_tick(sim, r, H.inp(1))
	var x0 := r.view_centre().x - sim.px / 1000.0
	for i in 6:
		_tick(sim, r, H.inp(-1))
	var x1 := r.view_centre().x - sim.px / 1000.0
	_check.call(absf(x1 - x0) < 25.0, "CAM6 a short tap the other way does not swing the view (%.1f)" % absf(x1 - x0))


func _falling() -> void:
	var grid_edits := {}
	for x in range(0, 12):
		for y in range(8, 20):
			grid_edits[Vector2i(x, y)] = "#"
	grid_edits[Vector2i(2, 7)] = "S"
	var lv := _fixture(64, 30, 20, grid_edits)
	_check.call(lv.valid(), "CAM7 fall fixture is valid (%s)" % str(lv.errors))
	var sim := MazeSim.new(lv)
	var r := _rig(lv)
	r.snap(_frame(sim))
	var anchor_y := 8 * 40.0
	var t_fall := -1.0
	var t := 0.0
	var worst := INF
	var window := 0
	for i in 300:
		_tick(sim, r, H.inp(1))
		t += DT
		var feet := sim.py / 1000.0
		if t_fall < 0.0 and feet > anchor_y + MazeCameraRig.FALL_MIN:
			t_fall = t
		if t_fall >= 0.0 and t - t_fall >= 0.25 and not sim.grounded:
			worst = minf(worst, r.play_rect().end.y - feet)
			window += 1
		if sim.grounded and t_fall >= 0.0:
			break
	_check.call(window > 5, "CAM7 the fall lasts long enough to measure (%d frames)" % window)
	_check.call(worst >= 140.0, "CAM7 at least 140 px below the feet while falling (%.1f)" % worst)


## R19: sliding shows at least 3.6 tiles below the feet from 0.3 s on
func _sliding() -> void:
	var edits := {}
	for k in 10:
		edits[Vector2i(20 + k, 18 - k)] = "/"
		for y in range(19 - k, 23):
			edits[Vector2i(20 + k, y)] = "#"
	for y in range(9, 23):
		edits[Vector2i(30, y)] = "#"
	var lv := _fixture(48, 24, 23, edits, {"format": 2})
	_check.call(lv.valid(), "R19 slide fixture is valid (%s)" % str(lv.errors))
	var sim := MazeSim.new(lv)
	sim.px = 29 * 40000 + 30000
	sim.py = 9 * 40000 + 10000
	sim._compute_ground()
	var r := _rig(lv)
	r.snap(_frame(sim))
	var t := 0.0
	var slide_t := -1.0
	var worst := INF
	var reached := -1.0
	var frames := 0
	for i in 100:
		var f_in := H.inp()
		sim.step(f_in)
		var f := _frame(sim)
		f["slide"] = sim.sliding()
		r.update(DT, f)
		t += DT
		if sim.sliding() and slide_t < 0.0:
			slide_t = t
		if slide_t >= 0.0 and reached < 0.0 and r._guard_b >= MazeCameraRig.GUARD_BOTTOM_FALL - 0.01:
			reached = t - slide_t
		if slide_t >= 0.0 and t - slide_t >= 0.3 and sim.sliding():
			worst = minf(worst, r.play_rect().end.y - sim.py / 1000.0)
			frames += 1
	_check.call(
		slide_t >= 0.0 and reached >= 0.0 and reached <= 0.3,
		"R19 the bottom guard grows within 0.3 s (%.2f)" % reached
	)
	_check.call(
		frames > 10 and worst >= 144.0,
		"R19 at least 3.6 tiles below the feet while sliding (%.1f over %d frames)" % [worst, frames]
	)


func _aim_framing() -> void:
	var edits := {}
	for y in range(10, 18):
		edits[Vector2i(22, y)] = "#"
	edits[Vector2i(10, 17)] = "S"
	var lv := _fixture(64, 30, 18, edits)
	_check.call(lv.valid(), "CAM8 aim fixture is valid (%s)" % str(lv.errors))
	var sim := MazeSim.new(lv)
	var r := _rig(lv)
	r.snap(_frame(sim))
	var hit := Vector2(sim.cast(0)["hit"]) / 1000.0
	var base_x := r.view_centre().x
	_check.call(
		not r.play_rect().grow(-(MazeCameraRig.AIM_MARGIN - 1.0)).has_point(hit),
		"CAM8 the target is out of the framed area without framing"
	)
	for i in 60:
		_tick(sim, r, H.inp(), true, hit)
	var area := r.play_rect().grow(-(MazeCameraRig.AIM_MARGIN - 1.0))
	var p := _frame(sim)["player"] as Vector2
	_check.call(area.has_point(hit), "CAM8 the target is inside the play rect within 1 s")
	_check.call(r.play_rect().grow(-40.0).has_point(p), "CAM8 the player stays inside the play rect while framing")
	_check.call(r.view_centre().x > base_x + 20.0, "CAM8 the view moved towards the target")
	# throw: the offset stays while the bead flies, then returns
	var offset_held := true
	var flew := 0
	_tick(sim, r, H.inp(0, false, false, 0), false, hit)
	while not sim.flights.is_empty() and flew < 120:
		offset_held = offset_held and r.view_centre().x > base_x + 20.0
		flew += 1
		_tick(sim, r, H.inp(), false, hit)
	_check.call(flew > 3 and offset_held, "CAM8 the offset stays while the bead is in flight (%d frames)" % flew)
	for i in 90:
		_tick(sim, r, H.inp())
	_check.call(
		absf(r.view_centre().x - base_x) < 2.0,
		"CAM8 the view returns within 1.5 s after the bead became a ring (%.2f)" % (r.view_centre().x - base_x)
	)
	# mouse: no framing, standing player, the view does not move
	sim = MazeSim.new(lv)
	r = _rig(lv)
	r.snap(_frame(sim))
	var c0 := r.view_centre()
	for i in 60:
		_tick(sim, r, H.inp())
	_check.call(
		r.view_centre().distance_to(c0) < 0.5,
		"CAM8 without aim framing a standing player does not move the view"
	)
	# a cancelled aim returns at once
	for i in 30:
		_tick(sim, r, H.inp(), true, hit)
	for i in 90:
		_tick(sim, r, H.inp())
	_check.call(r.view_centre().distance_to(c0) < 2.0, "CAM8 a cancelled aim returns the view")


func _snap() -> void:
	var lv := _fixture(64, 30, 18, {Vector2i(10, 17): "S"})
	var sim := MazeSim.new(lv)
	var r := _rig(lv)
	r.snap(_frame(sim))
	var z := MazeCameraRig.target_zoom(DESKTOP)
	var ph := (DESKTOP.y - BAND) / z
	var want := Vector2(
		10.0 * 40.0 + 20.0 + MazeCameraRig.LOOK_X,
		18.0 * 40.0 - (MazeCameraRig.FEET_Y - 0.5) * ph - BAND / (2.0 * z)
	)
	_check.call(
		r.view_centre().distance_to(want) < 0.01,
		"CAM9 snap gives the base target without smoothing (%s)" % str(r.view_centre() - want)
	)
	for i in 30:
		_tick(sim, r, H.inp(1))
	var f := _frame(sim)
	r.snap(f)
	var after := r.view_centre()
	r.update(0.0, f)
	_check.call(r.view_centre().distance_to(after) < 0.01, "CAM9 after a snap the follow state is at its target")


func _intro() -> void:
	var lv := MazeLevels.load_level("l001")
	var door := (Vector2(lv.finish) + Vector2(0.5, 0.5)) * 40.0
	var sim := MazeSim.new(lv)
	var r := _rig(lv)
	r.snap(_frame(sim))
	var twin := _rig(lv)
	twin.snap(_frame(sim))
	r.start_intro()
	_check.call(r.intro_active() and r.play_rect().has_point(door), "CAM10 the intro starts on the door")
	var f := _frame(sim)
	var t := 0.0
	var hold_ok := true
	while t < MazeCameraRig.INTRO_HOLD_S - 0.05:
		r.update(DT, f)
		twin.update(DT, f)
		t += DT
		hold_ok = hold_ok and r.play_rect().has_point(door)
	_check.call(hold_ok, "CAM10 the door stays in view during the hold")
	while r.intro_active() and t < 6.0:
		r.update(DT, f)
		twin.update(DT, f)
		t += DT
	_check.call(not r.intro_active() and t < 3.0, "CAM10 the intro ends by itself (%.2f s)" % t)
	_check.call(r.view_centre().distance_to(twin.view_centre()) < 0.5, "CAM10 the intro ends on the follow view")
	# skip at 0.5 s
	r = _rig(lv)
	r.snap(_frame(sim))
	twin = _rig(lv)
	twin.snap(_frame(sim))
	r.start_intro()
	for i in 30:
		r.update(DT, f)
		twin.update(DT, f)
	r.skip_intro()
	_check.call(not r.intro_active(), "CAM10 a skip ends the intro")
	for i in 19:
		r.update(DT, f)
		twin.update(DT, f)
	_check.call(
		r.view_centre().distance_to(twin.view_centre()) < 0.5,
		"CAM10 a skip reaches the follow view within the blend time"
	)


func _overview() -> void:
	for id in _level_ids():
		var lv := MazeLevels.load_level(id)
		var lvl_rect := Rect2(Vector2.ZERO, Vector2(lv.width, lv.height) * 40.0)
		for canvas: Vector2 in [DESKTOP, PHONE]:
			var sim := MazeSim.new(lv)
			var r := _rig(lv, canvas)
			r.snap(_frame(sim))
			var f := _frame(sim)
			r.set_overview(true)
			for i in 16:
				r.update(DT, f)
			var fit := MazeCameraRig.fit_zoom(Vector2(lv.width, lv.height) * 40.0, canvas, BAND)
			_check.call(
				absf(r.view_zoom() - fit) < 0.0001 and r.play_rect().grow(0.5).encloses(lvl_rect),
				"CAM11 %s at %s: the overview shows the whole level" % [id, str(canvas)]
			)
			r.set_overview(false)
			for i in 16:
				r.update(DT, f)
			_check.call(
				absf(r.view_zoom() - MazeCameraRig.target_zoom(canvas)) < 0.0001 and r.overview_k() == 0.0,
				"CAM11 %s at %s: the zoom is back after release" % [id, str(canvas)]
			)


func _clean() -> void:
	for p in [PROFILE, PROFILE + ".tmp"]:
		DirAccess.remove_absolute(p)


func _main(extra: Array = []) -> MazeMain:
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	m.args = PackedStringArray(["--profile=" + PROFILE, "--speed=100"]) + PackedStringArray(extra)
	_node.add_child(m)
	return m


func _close(m: MazeMain) -> void:
	_node.remove_child(m)
	m.free()


## a game on l001 driven by advance() only
func _game(extra: Array = []) -> MazeMain:
	WhiteText.lang = "nl"
	var m := _main(["--level=l001"] + extra)
	m.game.set_process(false)
	return m


## the snapped view a fresh rig gives for the current state of the game
func _snapped_view(g: MazeGame) -> Vector2:
	var vs := g.get_viewport().get_visible_rect().size
	var r := MazeCameraRig.new()
	r.setup(Vector2(g.level.width, g.level.height) * 40.0, vs, MazeGame.HUD_BAND, g._door_centre())
	r.snap(_frame(g.sim))
	return r.view_centre()


func _game_snap() -> void:
	var m := _game()
	var g := m.game
	g.controls.handle_event(C.key(KEY_D))
	for i in 200:
		g.advance(DT)
	var walked := g.rig.view_centre()
	g.restart()
	_check.call(g.rig.view_centre().distance_to(_snapped_view(g)) < 0.01, "CAM9 a restart snaps to the spawn framing")
	_check.call(g.rig.view_centre().distance_to(walked) > 100.0, "CAM9 the restart moved the view")
	# walk into the first pit: the camera holds while dead, then cuts at the respawn
	var held_ok := true
	var dead_view := Vector2.ZERO
	var cut := false
	for i in 600:
		var before := g.rig.view_centre()
		g.advance(DT)
		if not g.sim.alive():
			held_ok = held_ok and (dead_view == Vector2.ZERO or g.rig.view_centre().distance_to(dead_view) < 0.01)
			if dead_view == Vector2.ZERO:
				dead_view = g.rig.view_centre()
		if H.has_event(g.sim, "respawn"):
			var now := g.rig.view_centre()
			cut = now.distance_to(_snapped_view(g)) < 0.01 and before.distance_to(now) > 50.0
			break
	_check.call(dead_view != Vector2.ZERO and held_ok, "CAM9 the view holds still while the player is dead")
	_check.call(cut, "CAM9 the first frame after the respawn shows the spawn framing")
	_close(m)


func _game_intro() -> void:
	var a := _game()
	var b := _game()
	_check.call(a.game.rig.intro_active() and b.game.rig.intro_active(), "CAM10 a level opens with the intro")
	var door_in_view := a.game.world.view_rect.has_point(a.game._door_centre())
	_check.call(door_in_view, "CAM10 the intro starts on the door")
	b.game.rig.skip_intro()
	a.game.controls.handle_event(C.key(KEY_D))
	b.game.controls.handle_event(C.key(KEY_D))
	for i in 60:
		a.game.advance(DT)
		b.game.advance(DT)
	_check.call(not a.game.rig.intro_active(), "CAM10 a key press skips the intro")
	_check.call(
		a.game.sim.snapshot() == b.game.sim.snapshot() and a.game.sim.tick > 0,
		"CAM10 the intro does not delay the input"
	)
	_close(a)
	_close(b)
	var shot := _main(["--level=l001", "--shot=/tmp/none.png"])
	_check.call(not shot.game.rig.intro_active(), "CAM10 a screenshot run has no intro")
	_close(shot)
	var cam := _main(["--level=l001", "--camera=door"])
	_check.call(not cam.game.rig.intro_active() and cam.game.rig.debug_view == "door", "CAM10 --camera has no intro")
	_close(cam)


func _game_overview() -> void:
	var m := _game()
	var g := m.game
	g.rig.skip_intro()
	g.controls.handle_event(C.key(KEY_D))
	for i in 40:
		g.advance(DT)
	g.controls.handle_event(C.key(KEY_D, false))
	g.controls.handle_event(C.key(KEY_J))
	g.advance(DT)
	_check.call(g.controls.aiming(), "CAM11 the aim is on before the overview")
	var tick := g.sim.tick
	var time := g.sim.time_ticks()
	_check.call(time > 0, "CAM11 the clock runs before the overview")
	g.controls.handle_event(C.key(KEY_TAB))
	for i in 30:
		g.advance(DT)
	_check.call(g.sim.tick == tick and g.sim.time_ticks() == time, "CAM11 the game is held during the overview")
	_check.call(not g.controls.aiming(), "CAM11 the overview cancels an aim in progress")
	_check.call(g.rig.overview_k() > 0.99 and g.world.overview_k > 0.99, "CAM11 the overview view is shown")
	g.controls.handle_event(C.key(KEY_TAB, false))
	for i in 20:
		g.advance(DT)
	_check.call(g.sim.tick > tick and g.rig.overview_k() == 0.0, "CAM11 after the release the game continues")
	# D held through the overview walks on at once
	g.controls.handle_event(C.key(KEY_D))
	g.advance(DT)
	g.controls.handle_event(C.key(KEY_M))
	for i in 10:
		g.advance(DT)
	var x := g.sim.px
	g.controls.handle_event(C.key(KEY_M, false))
	for i in 20:
		g.advance(DT)
	_check.call(g.sim.px > x, "CAM11 a held walk key walks on after the overview")
	# no overview while paused
	g.pause()
	g.controls.handle_event(C.key(KEY_TAB))
	g.advance(DT)
	_check.call(g.rig.overview_k() == 0.0, "CAM11 no overview while paused")
	_close(m)


func _band(g: MazeGame) -> float:
	var vs := g.get_viewport().get_visible_rect().size
	return MazeGame.HUD_BAND + float(WhiteSafeArea.insets(vs, g.options.get("safe", ""))["top"])


func _game_same_frame() -> void:
	var m := _game()
	var g := m.game
	g.controls.handle_event(C.key(KEY_D))
	var deltas := [1.0 / 60.0, 1.0 / 144.0, 1.0 / 30.0]
	var worst := 0.0
	for i in 120:
		g.advance(deltas[i % 3])
		var p := g.world.get_canvas_transform() * g.rig.play_rect().position
		worst = maxf(worst, p.distance_to(Vector2(0.0, _band(g))))
	_check.call(worst < 0.01, "CAM12 the camera is applied in the frame it was computed for (%.4f)" % worst)
	var z := MazeCameraRig.target_zoom(g.get_viewport().get_visible_rect().size)
	_check.call(
		g.world.get_canvas_transform().get_scale().is_equal_approx(Vector2(z, z)),
		"CAM12 the world is drawn at the target zoom"
	)
	_close(m)


func _game_mouse() -> void:
	var m := _game()
	var g := m.game
	g.controls.handle_event(C.key(KEY_D))
	for i in 90:
		g.advance(DT)
	g.controls.handle_event(C.key(KEY_D, false))
	g.advance(DT)
	var p := g.world.get_canvas_transform() * g.world.player_centre()
	_check.call(g.controls._player_pos.is_equal_approx(p), "CAM13 the mouse aim uses the player position of this frame")
	g.controls.handle_event(C.mouse(MOUSE_BUTTON_LEFT, p + Vector2(100, 0), true))
	g.controls.handle_event(C.mouse(MOUSE_BUTTON_LEFT, p + Vector2(100, 0), false))
	_check.call(
		g.controls.take_throw() == 0,
		"CAM13 a mouse throw 100 units to the right is index 0 at the target zoom"
	)
	_close(m)


func _game_fixed_layers() -> void:
	var m := _game(["--safe=0,20,0,0"])
	var g := m.game
	g.controls.handle_event(C.key(KEY_D))
	var fixed := true
	var moved := false
	for i in 90:
		g.advance(DT)
		for n: CanvasItem in [g.hud, g.touch, g.overlays]:
			fixed = fixed and n.get_canvas_transform() == Transform2D.IDENTITY
		moved = moved or g.world.get_canvas_transform().origin != Vector2.ZERO
	_check.call(fixed and moved, "CAM14 HUD, touch controls and overlays stay screen-fixed while the camera moves")
	_check.call(
		is_equal_approx(g.hud.scrim_band(), MazeGame.HUD_BAND + 20.0),
		"CAM14 the HUD scrim covers the band plus the safe area top"
	)
	_close(m)
