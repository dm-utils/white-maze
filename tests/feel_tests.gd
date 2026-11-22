extends RefCounted
## F1-F2: level speed (design 20.6); F4-F6: render time, smoothness and pose blending (20.3). F7-F8 are in art_tests.

const H := preload("res://tests/helpers.gd")
const C := preload("res://tests/controls_tests.gd")
const PROFILE := "user://white_maze_test_feel.json"
const DT := 1.0 / 60.0
const SOLUTIONS := "res://tests/solutions.json"
const JOINTS := ["near_foot", "far_foot", "hand_near", "hand_far"]
const MAX_JOINT_PX := 3.5
const MAX_TILT_DEG := 2.0

var _check: Callable
var _node: Node


func run(check: Callable, node: Node) -> void:
	_check = check
	_node = node
	_level_speed()
	_args()
	_game_speed()
	_render_time()
	_smooth()
	_blend()
	_clean()


func _clean() -> void:
	for p in [PROFILE, PROFILE + ".tmp"]:
		DirAccess.remove_absolute(p)


func _main(extra: Array = []) -> MazeMain:
	WhiteText.lang = "nl"
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	m.args = PackedStringArray(["--profile=" + PROFILE, "--level=l001"]) + PackedStringArray(extra)
	_node.add_child(m)
	m.game.set_process(false)
	m.game.rig.skip_intro()
	return m


func _close(m: MazeMain) -> void:
	_node.remove_child(m)
	m.free()


func _level_speed() -> void:
	var want := [0.80, 0.82, 0.84, 0.86, 0.88, 0.90, 0.92, 0.94, 0.96]
	var ok := true
	for i in want.size():
		ok = ok and is_equal_approx(MazeGame.level_speed(i + 1), want[i])
	_check.call(ok, "F1 level_speed gives 0.80 to 0.96 for the levels 1 to 9")
	_check.call(
		is_equal_approx(MazeGame.level_speed(10), 0.96) and is_equal_approx(MazeGame.level_speed(12), 0.96),
		"F1 level_speed stays at 0.96 from level 10"
	)
	_check.call(
		is_equal_approx(MazeGame.level_speed(0), 0.80) and is_equal_approx(MazeGame.level_speed(-3), 0.80),
		"F1 level_speed never goes below the first level"
	)


func _args() -> void:
	_check.call(MazeMain.parse_args(PackedStringArray(["--speed=110"]))["speed"] == 110, "F1 --speed=110 is taken")
	_check.call(MazeMain.parse_args(PackedStringArray(["--speed=20"]))["speed"] == 0, "F1 --speed=20 is ignored")
	_check.call(MazeMain.parse_args(PackedStringArray(["--speed=abc"]))["speed"] == 0, "F1 --speed=abc is ignored")
	_check.call(MazeMain.parse_args(PackedStringArray([]))["speed"] == 0, "F1 no --speed uses the table")
	_check.call(
		MazeMain.query_args("?speed=90") == PackedStringArray(["--speed=90"]), "F1 the web query key speed is passed on"
	)
	var m := _main(["--speed=110"])
	_check.call(is_equal_approx(m.game.speed, 1.1), "F1 --speed=110 gives 1.1 on l001")
	_close(m)
	m = _main()
	_check.call(is_equal_approx(m.game.speed, 0.8), "F1 l001 runs at the table speed 0.80")
	_close(m)


func _walk(g: MazeGame, frames: int) -> void:
	g.controls.handle_event(C.key(KEY_D))
	for i in frames:
		g.advance(DT)


func _game_speed() -> void:
	var m := _main()
	var g := m.game
	_walk(g, 300)
	_check.call(absi(g.sim.tick - 240) <= 1, "F2 300 frames at the table speed give 240 ticks (%d)" % g.sim.tick)
	var plain := MazeSim.new(g.level)
	for i in g.sim.tick:
		plain.step(H.inp(1))
	_check.call(plain.snapshot() == g.sim.snapshot(), "F2 the game at 0.80 plays the same simulation as a plain run")
	_check.call(g.world.modulate == Color.WHITE, "F2 a level at 0.80 is not drawn dimmed")
	_close(m)
	m = _main(["--speed=100"])
	_walk(m.game, 300)
	_check.call(m.game.sim.tick == 300, "F2 speed 100 gives 300 ticks (%d)" % m.game.sim.tick)
	_close(m)
	m = _main()
	g = m.game
	g.controls.handle_event(C.key(KEY_J))
	for i in 6:
		g.advance(DT)
	_check.call(g.controls.aiming() and g.world.modulate != Color.WHITE, "F2 aiming dims the world")
	var t0 := g.sim.tick
	for i in 60:
		g.advance(DT)
	_check.call(absi(g.sim.tick - t0 - 12) <= 1, "F2 aiming on l001 gives 12 ticks per second (%d)" % (g.sim.tick - t0))
	_close(m)


## game on l001 at speed 100: one tick per frame of 1/60 s
func _game100() -> MazeMain:
	return _main(["--speed=100"])


func _run_until(g: MazeGame, cond: Callable, frames: int) -> bool:
	for i in frames:
		g.advance(DT)
		if cond.call():
			return true
	return false


func _param_at(w: MazeWorldView, a: float) -> Dictionary:
	w.alpha = a
	return w.player_params()


## F4: pose values follow the render time, not the tick
func _render_time() -> void:
	var m := _game100()
	var g := m.game
	var w := g.world
	for i in 10:
		g.advance(DT)
	var lo := _param_at(w, 0.25)
	var hi := _param_at(w, 0.75)
	_check.call(not is_equal_approx(lo["rig"]["drop"], hi["rig"]["drop"]), "F4 the idle bob differs per alpha")
	var whole := _param_at(w, 1.0)
	_check.call(is_equal_approx(whole["tick"], float(g.sim.tick)), "F4 with alpha 1 the render time is the tick")
	# jump, land: squash rises over one tick after the landing tick
	g.controls.touch_jump(true)
	g.advance(DT)
	g.controls.touch_jump(false)
	var landed := _run_until(g, func() -> bool: return w._land_tick == g.sim.tick, 120)
	_check.call(landed, "F4 the jump ends in a landing")
	g.advance(DT)
	var s_lo := float(_param_at(w, 0.25)["squash_k"])
	var s_hi := float(_param_at(w, 0.75)["squash_k"])
	_check.call(s_lo > 0.0 and s_hi > s_lo, "F4 the landing squash rises within a tick (%.2f, %.2f)" % [s_lo, s_hi])
	g.advance(DT)
	s_lo = float(_param_at(w, 0.25)["squash_k"])
	s_hi = float(_param_at(w, 0.75)["squash_k"])
	_check.call(s_lo > s_hi, "F4 the landing squash fades between ticks (%.3f, %.3f)" % [s_lo, s_hi])
	# throw swing
	for i in 20:
		g.advance(DT)
	g.controls.touch_throw(36)
	g.advance(DT)
	g.advance(DT)
	g.advance(DT)
	_check.call(w._throw_tick > -1000 and g.sim.tick - w._throw_tick < 10, "F4 the throw is in its swing")
	var t_lo := float(_param_at(w, 0.25)["throw_k"])
	var t_hi := float(_param_at(w, 0.75)["throw_k"])
	_check.call(
		t_hi > t_lo and t_lo > 0.0 and t_hi < 1.0, "F4 the throw swing differs per alpha (%.3f, %.3f)" % [t_lo, t_hi]
	)
	_close(m)
	# death and respawn fades
	m = _game100()
	g = m.game
	w = g.world
	g.controls.touch_move(1)
	var died := _run_until(g, func() -> bool: return not g.sim.alive(), 600)
	_check.call(died, "F4 walking right ends in a death")
	for i in 5:
		g.advance(DT)
	var d_lo := float(_param_at(w, 0.25)["fade"])
	var d_hi := float(_param_at(w, 0.75)["fade"])
	_check.call(d_lo > d_hi and d_hi > 0.0, "F4 the death fade differs per alpha (%.3f, %.3f)" % [d_lo, d_hi])
	g.controls.touch_move(0)
	var back := _run_until(g, func() -> bool: return g.sim.alive(), 60)
	_check.call(back, "F4 the player respawns")
	for i in 3:
		g.advance(DT)
	var r_lo := float(_param_at(w, 0.25)["fade"])
	var r_hi := float(_param_at(w, 0.75)["fade"])
	_check.call(r_hi > r_lo and r_hi < 1.0, "F4 the respawn fade differs per alpha (%.3f, %.3f)" % [r_lo, r_hi])
	_close(m)


## frames of 1/120 s on the world; true when the joints stayed within the limits
class Watch:
	var worst_px := 0.0
	var worst_deg := 0.0
	var frames := 0
	var where := ""
	var _prev := {}
	var _prev_face := 0
	var _prev_body := -1

	func feed(w: MazeWorldView, label: String) -> void:
		var p := w.player_params()
		if p.is_empty():
			_prev = {}
			return
		var rig: Dictionary = w.last_rig
		var skip: bool = _prev.is_empty() or w._face != _prev_face or p["body"] == MazeLilith.Body.DEAD
		skip = skip or _prev_body == MazeLilith.Body.DEAD
		if not skip:
			frames += 1
			for j: String in JOINTS:
				var d := (rig[j] as Vector2).distance_to(_prev[j])
				if d > worst_px:
					worst_px = d
					where = "%s %s" % [label, j]
			var dt := absf(rad_to_deg(rig["tilt"] - _prev["tilt"]))
			worst_deg = maxf(worst_deg, dt)
		_prev = rig
		_prev_face = w._face
		_prev_body = p["body"]


func _frame120(g: MazeGame, watch: Watch, label: String) -> void:
	g.advance(1.0 / 120.0)
	watch.feed(g.world, label)


func _hold120(g: MazeGame, watch: Watch, label: String, frames: int) -> void:
	for i in frames:
		_frame120(g, watch, label)


## F5: no joint jumps between frames of 1/120 s
func _smooth() -> void:
	var m := _game100()
	var g := m.game
	var watch := Watch.new()
	var c := g.controls
	_hold120(g, watch, "stand", 60)
	c.touch_move(1)
	_hold120(g, watch, "run", 240)
	c.touch_move(0)
	_hold120(g, watch, "stop", 120)
	c.touch_jump(true)
	_hold120(g, watch, "jump", 140)
	c.touch_jump(false)
	_hold120(g, watch, "fall", 200)
	c.touch_move(1)
	_hold120(g, watch, "walk", 60)
	c.touch_move(0)
	_hold120(g, watch, "halt", 60)
	c.handle_event(C.key(KEY_J))
	_hold120(g, watch, "aim", 80)
	c.handle_event(C.key(KEY_J, false))
	_hold120(g, watch, "throw", 160)
	# the solution of l001: ring launches, jumps and throws
	g.restart()
	var script: String = WhitePuzzleStore.load_json(SOLUTIONS)["l001"]
	for inp: MazeInput in MazeRunScript.parse(script)["inputs"]:
		c.touch_move(inp.move)
		if inp.jump_pressed:
			c.touch_jump(false)
			c.touch_jump(true)
			if not inp.jump_held:
				c.touch_jump(false)
		else:
			c.touch_jump(inp.jump_held)
		if inp.throw_dir >= 0:
			c.touch_throw(inp.throw_dir)
		_hold120(g, watch, "solution", 2)
		if g.sim.finished():
			break
	_check.call(watch.frames > 1000, "F5 the scripted run gives enough frames (%d)" % watch.frames)
	_check.call(
		watch.worst_px <= MAX_JOINT_PX,
		"F5 no joint moves more than %.1f px between frames (%.2f at %s)" % [MAX_JOINT_PX, watch.worst_px, watch.where]
	)
	_check.call(
		watch.worst_deg <= MAX_TILT_DEG,
		"F5 the tilt changes at most %.0f degrees per frame (%.2f)" % [MAX_TILT_DEG, watch.worst_deg]
	)
	_close(m)


func _rigs() -> Array:
	var a := MazeLilith.rig({"body": MazeLilith.Body.RUN, "arm": MazeLilith.Arm.REST, "phase": 0.3})
	var b := MazeLilith.rig({"body": MazeLilith.Body.JUMP, "arm": MazeLilith.Arm.AIM, "aim_angle": 1.0})
	var c := MazeLilith.rig({"body": MazeLilith.Body.FALL, "arm": MazeLilith.Arm.REST})
	return [a, b, c]


func _same(a: Dictionary, b: Dictionary) -> bool:
	for key: String in a:
		if a[key] is float:
			if not is_equal_approx(a[key], b[key]):
				return false
		elif not (a[key] as Vector2).is_equal_approx(b[key]):
			return false
	return true


## F6
func _blend() -> void:
	var rigs := _rigs()
	var run := Vector2i(MazeLilith.Body.RUN, MazeLilith.Arm.REST)
	var jump := Vector2i(MazeLilith.Body.JUMP, MazeLilith.Arm.AIM)
	var fall := Vector2i(MazeLilith.Body.FALL, MazeLilith.Arm.REST)
	var dead := Vector2i(MazeLilith.Body.DEAD, MazeLilith.Arm.REST)
	var b := MazePoseBlend.new()
	_check.call(_same(b.apply(run, rigs[0], 10.0), rigs[0]), "F6 the first call returns the target")
	_check.call(_same(b.apply(jump, rigs[1], 20.0), rigs[0]), "F6 a key change starts at the last returned rig")
	var mid := b.apply(jump, rigs[1], 20.0 + MazePoseBlend.BLEND_TICKS / 2.0)
	_check.call(
		_same(mid, MazeLilith.blend_rig(rigs[0], rigs[1], 0.5)), "F6 halfway the blend is halfway (smoothstep 0.5)"
	)
	_check.call(
		_same(b.apply(jump, rigs[1], 20.0 + MazePoseBlend.BLEND_TICKS), rigs[1]), "F6 after BLEND_TICKS it is the target"
	)
	# switch during a blend: starts from the rig as last returned
	b.apply(run, rigs[0], 40.0)
	b.apply(fall, rigs[2], 41.0)
	var before := b.apply(fall, rigs[2], 42.0)
	var cut := b.apply(jump, rigs[1], 43.0)
	_check.call(_same(cut, before), "F6 a switch during a blend starts at the blended rig")
	# disabled, dead, reset: at once
	b = MazePoseBlend.new()
	b.enabled = false
	b.apply(run, rigs[0], 0.0)
	_check.call(_same(b.apply(jump, rigs[1], 1.0), rigs[1]), "F6 a disabled blend switches at once")
	b = MazePoseBlend.new()
	b.apply(run, rigs[0], 0.0)
	_check.call(_same(b.apply(dead, rigs[2], 1.0), rigs[2]), "F6 a switch to DEAD is at once")
	b.apply(dead, rigs[2], 2.0)
	_check.call(_same(b.apply(run, rigs[0], 3.0), rigs[0]), "F6 a switch from DEAD is at once")
	b.apply(jump, rigs[1], 4.0)
	b.reset()
	_check.call(_same(b.apply(fall, rigs[2], 4.5), rigs[2]), "F6 after reset the next call switches at once")
