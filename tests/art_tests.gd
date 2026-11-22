extends RefCounted
## Look and feel step 1 (design 18.12): Lilith's bounds (A2), pose table (A7), simulation untouched (A1), name.

const PROFILE := "user://white_maze_test_art.json"
const SOLUTIONS := "res://tests/solutions.json"
const B := MazeLilith.Body
const A := MazeLilith.Arm
const BODIES := [B.IDLE, B.RUN, B.JUMP, B.LAUNCH, B.FALL]
const ARMS := [A.REST, A.AIM, A.THROW, A.UP]
const VELS := [0.0, 300.0, -300.0, 1080.0, -1080.0]
const HITBOX := Rect2(-15.0, -32.0, 30.0, 32.0)

var _check: Callable
var _node: Node


func run(check: Callable, node: Node) -> void:
	_check = check
	_node = node
	_bounds()
	_poses()
	_figure()
	await _game()
	_names()
	DirAccess.remove_absolute(PROFILE)
	DirAccess.remove_absolute(PROFILE + ".tmp")


## first violation of the bounds of 18.6.1, or ""
func _violation(p: Dictionary) -> String:
	for s in MazeLilith.shapes(p):
		if s["part"] == "outline":
			continue
		var box := HITBOX
		if s["part"] == "tail":
			box = MazeLilith.TAIL_BOUNDS
		var pts: PackedVector2Array = s["pts"]
		var extent := Vector2.ZERO
		var points := PackedVector2Array()
		match s["type"]:
			"circle":
				points.append(s["c"])
				extent = Vector2.ONE * float(s["r"])
			"line":
				points = pts
				extent = Vector2.ONE * float(s["w"]) / 2.0
			_:
				points = pts
		for v in points:
			var lo: Vector2 = v - extent
			var hi: Vector2 = v + extent
			if lo.x < box.position.x - 0.001 or hi.x > box.end.x + 0.001:
				return "%s %s x %s" % [s["part"], p, v]
			if lo.y < box.position.y - 0.001 or hi.y > box.end.y + 0.001:
				return "%s %s y %s" % [s["part"], p, v]
	return ""


func _pose(body: int, arm: int, extra: Dictionary) -> Dictionary:
	var p := {"body": body, "arm": arm, "slots": 4, "filled": 4}
	p.merge(extra, true)
	return p


func _bounds() -> void:
	for body: int in BODIES:
		var bad := ""
		# phase, squash, arm
		for arm: int in ARMS:
			for i in 21:
				for sq in [0.0, 1.0]:
					var p := _pose(body, arm, {"phase": i * 0.05, "tick": i * 6, "squash_k": sq, "aim_angle": i * 0.3})
					bad = bad if bad != "" else _violation(p)
		# velocity and tick
		for arm: int in ARMS:
			for vx: float in VELS:
				for vy: float in VELS:
					for t in range(0, 120, 7):
						bad = bad if bad != "" else _violation(_pose(body, arm, {"vel": Vector2(vx, vy), "tick": t}))
		# all 144 aim directions, both arm poses that use them
		for arm: int in [A.AIM, A.THROW]:
			for k in [0.0, 0.5, 1.0]:
				for d in MazeAim.STEPS:
					var v := Vector2(MazeAim.dir(d))
					var p := _pose(body, arm, {"aim_angle": atan2(v.y, v.x), "throw_k": k, "squash_k": float(d % 2)})
					bad = bad if bad != "" else _violation(p)
		_check.call(bad == "", "A2: Lilith stays inside the hitbox in pose %d %s" % [body, bad])
	var slots_ok := true
	for n in 5:
		for f in n + 1:
			slots_ok = slots_ok and _violation(_pose(B.IDLE, A.REST, {"slots": n, "filled": f})) == ""
	_check.call(slots_ok, "A2: every number of bandolier slots stays inside the hitbox")


func _poses() -> void:
	var T := MazeLilith.THROW_TICKS
	var cases := [
		[[true, true, 0, 0, false], B.IDLE, "spawn: standing"],
		[[true, true, 400, 0, false], B.IDLE, "slow on the ground: standing"],
		[[true, true, 500, 0, false], B.RUN, "running right"],
		[[true, true, -2000, 0, false], B.RUN, "running left"],
		[[true, false, 1000, -4000, false], B.JUMP, "after a jump press"],
		[[true, false, 0, -9000, true], B.LAUNCH, "after a floor ring launch"],
		[[true, false, 0, 0, true], B.FALL, "at the top of the arc"],
		[[true, false, 1000, 3000, false], B.FALL, "falling"],
		[[false, true, 0, 0, false], B.DEAD, "dead on the ground"],
		[[false, false, 0, 5000, false], B.DEAD, "dead in the air"],
		[[true, false, 0, -100, false], B.JUMP, "start of a hop"],
	]
	for c in cases:
		var a: Array = c[0]
		_check.call(MazeLilith.body_pose(a[0], a[1], a[2], a[3], a[4]) == c[1], "A7: body pose, %s" % c[2])
	_check.call(MazeLilith.arm_mode(false, 999, B.IDLE) == A.REST, "A7: arm rests when idle")
	_check.call(MazeLilith.arm_mode(true, 999, B.RUN) == A.AIM, "A7: aiming while running: AIM")
	_check.call(MazeLilith.arm_mode(false, 5, B.IDLE) == A.THROW, "A7: 5 ticks after a throw: THROW")
	_check.call(MazeLilith.arm_mode(false, T, B.IDLE) == A.REST, "A7: the throw arm lasts THROW_TICKS")
	_check.call(MazeLilith.arm_mode(false, 999, B.LAUNCH) == A.UP, "A7: launched: arms up")
	_check.call(MazeLilith.arm_mode(true, 0, B.DEAD) == A.REST, "A7: dead: arm rests")
	_check.call(MazeLilith.arm_mode(false, 3, B.LAUNCH) == A.THROW, "A7: a throw wins over the launch arms")


func _figure() -> void:
	var shapes := MazeLilith.shapes(_pose(B.IDLE, A.REST, {"slots": 3, "filled": 2}))
	var parts := {}
	var filled := 0
	var empty := 0
	for s in shapes:
		parts[s["part"]] = true
		if s["part"] == "slot":
			if s["color"] == MazeLilith.BEAD:
				filled += 1
			else:
				empty += 1
	for part in ["head", "hair", "band", "tail", "body", "arm", "leg", "outline"]:
		_check.call(parts.has(part), "Lilith has %s" % part)
	_check.call(filled == 2 and empty == 1, "the bandolier shows the beads left")
	_check.call(shapes[0]["part"] == "outline", "outlines are drawn first")
	var band: Color = MazeLilith.HEADBAND
	_check.call(band.to_html(false) == "dc3150", "the headband is crimson")
	var aim := MazeLilith.shapes(_pose(B.IDLE, A.AIM, {"aim_angle": 0.0}))
	var beads := 0
	for s in aim:
		if s["part"] == "bead":
			beads += 1
	_check.call(beads == 2, "aiming puts a bead with a halo in the hand")
	var dead := MazeLilith.shapes(_pose(B.DEAD, A.REST, {"dead_k": 0.5, "fade": 0.5}))
	_check.call(dead[dead.size() - 1]["color"].a <= 0.5, "fade lowers the alpha")
	var ticks_a := MazeLilith.shapes(_pose(B.IDLE, A.REST, {"tick": 7}))
	var ticks_b := MazeLilith.shapes(_pose(B.IDLE, A.REST, {"tick": 7}))
	_check.call(ticks_a == ticks_b, "shapes are a pure function of the pose")


func _main() -> MazeMain:
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	m.args = PackedStringArray(["--profile=" + PROFILE, "--level=l001"])
	_node.add_child(m)
	return m


func _feed(game: MazeGame, inp: MazeInput) -> void:
	var c := game.controls
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
	game.advance(1.0 / 60.0)


## A1: the game screen with the new view plays the same simulation as a plain run
func _game() -> void:
	WhiteText.lang = "nl"
	var m := _main()
	var g := m.game
	g.set_process(false)
	var script: String = WhitePuzzleStore.load_json(SOLUTIONS)["l001"]
	var frames := 0
	for inp: MazeInput in MazeRunScript.parse(script)["inputs"]:
		_feed(g, inp)
		frames += 1
		if g.sim.finished():
			break
	await _node.get_tree().process_frame
	var plain := MazeRunScript.run(MazeLevels.load_level("l001"), script)
	var same := g.sim.finished() and g.sim.snapshot() == plain.snapshot()
	_check.call(same, "A1: the game screen leaves the simulation alone")
	_check.call(g.world._throw_tick > -1000 and g.world._land_tick > -1000, "the view stores throw and land ticks")
	_node.remove_child(m)
	m.free()
	# the door of the finish and Lilith draw without a sim error on a fresh level
	var n := _main()
	n.game.set_process(false)
	await _node.get_tree().process_frame
	await _node.get_tree().process_frame
	_check.call(n.game.world.is_visible_in_tree(), "the world view with Lilith and the door is drawn")
	_node.remove_child(n)
	n.free()


func _names() -> void:
	var nl: String = MazeStrings.TEXT["nl"]["tagline"]
	var en: String = MazeStrings.TEXT["en"]["tagline"]
	_check.call("Lilith" in nl and "Lilith" in en, "the tagline names Lilith in both languages")
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	m.args = PackedStringArray(["--profile=" + PROFILE])
	_node.add_child(m)
	var sub: String = m.select.subtitle.text
	_check.call(nl in sub and "Gehaald" in sub, "the level select subtitle carries the tagline")
	_node.remove_child(m)
	m.free()
