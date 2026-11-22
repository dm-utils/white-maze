extends RefCounted
## Look and feel (design 18.12): Lilith's bounds (A2), pose table (A7), simulation untouched (A1), name; palettes (A3),
## lip faces (A4), static layers (A6), worlds (A8), readability backings.

const PROFILE := "user://white_maze_test_art.json"
const SOLUTIONS := "res://tests/solutions.json"
const B := MazeLilith.Body
const A := MazeLilith.Arm
const BODIES := [B.IDLE, B.RUN, B.JUMP, B.LAUNCH, B.FALL]
const ARMS := [A.REST, A.AIM, A.THROW, A.UP]
const VELS := [0.0, 300.0, -300.0, 1080.0, -1080.0]
const HITBOX := Rect2(-15.0, -32.0, 30.0, 32.0)
const H := preload("res://tests/helpers.gd")
const HASH_PINS := [0, 2476996174, 1019855091, 3867735071]

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
	_palettes()
	_lips()
	_worlds()
	await _static_layers()
	await _backings()
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
		# squash only on the ground (the view sets it only when grounded), so never in the air poses
		var squashes := [0.0, 0.5, 1.0] if body in [B.IDLE, B.RUN] else [0.0]
		# every pose x arm x squash x aim direction x throw progress x phase
		for arm: int in ARMS:
			for sq: float in squashes:
				for d in MazeAim.STEPS:
					var v := Vector2(MazeAim.dir(d))
					for k in [0.0, 0.5, 1.0]:
						for ph in [0.0, 0.25, 0.5, 0.75]:
							var p := _pose(
								body,
								arm,
								{
									"aim_angle": atan2(v.y, v.x),
									"throw_k": k,
									"squash_k": sq,
									"phase": ph,
									"tick": int(ph * 100.0) + d,
								}
							)
							bad = bad if bad != "" else _violation(p)
		# velocity and tick
		for arm: int in ARMS:
			for vx: float in VELS:
				for vy: float in VELS:
					for t in range(0, 120, 7):
						bad = bad if bad != "" else _violation(_pose(body, arm, {"vel": Vector2(vx, vy), "tick": t}))
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
	_check.call(band.to_html(false) == "e0306e", "the headband is rose-crimson")
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
		await _node.get_tree().process_frame
		frames += 1
		if g.sim.finished():
			break
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


static func _hue_gap(a: Color, b: Color) -> float:
	var d := absf(a.h - b.h) * 360.0
	return minf(d, 360.0 - d)


func _near_white(c: Color) -> bool:
	return c.s < 0.2 and c.v > 0.8


## A3 for each world
func _palettes() -> void:
	var hz := MazeWorlds.HAZARD
	for w in MazeWorlds.COUNT:
		var p := MazeWorlds.palette(w)
		var name: String = MazeWorlds.NAMES[w]
		var top: Color = p["back_top"]
		var bottom: Color = p["back_bottom"]
		_check.call(MazeArt.contrast(p["lip"], p["block"]) >= 1.8, "A3 %s: lip against block" % name)
		_check.call(
			MazeArt.contrast(p["noring"], top) >= 1.5 and MazeArt.contrast(p["noring"], bottom) >= 1.5,
			"A3 %s: X against the back wall" % name
		)
		_check.call(
			MazeArt.contrast(hz, top) >= 3.0 and MazeArt.contrast(hz, bottom) >= 3.0,
			"A3 %s: hazard against the back wall" % name
		)
		var lj := MazeArt.luminance(p["joint"])
		var lb := MazeArt.luminance(p["block"])
		var ll := MazeArt.luminance(p["lip"])
		_check.call(lj < lb and lb < ll, "A3 %s: joint darker than block darker than lip" % name)
		_check.call(
			MazeArt.luminance(p["noring_edge"]) < MazeArt.luminance(p["noring"]), "A3 %s: X border is darker" % name
		)
		var calm := true
		for key in ["back_decor", "back_line"]:
			calm = calm and MazeArt.contrast(p[key], top) <= 1.6 and MazeArt.contrast(p[key], bottom) <= 1.6
		_check.call(calm, "A3 %s: back decor and lines stay calm" % name)
		var white_free := true
		var hazard_free := true
		for key in p:
			var c: Color = p[key]
			white_free = white_free and not _near_white(c)
			hazard_free = hazard_free and not (_hue_gap(c, hz) < 15.0 and c.s > 0.4 and c.v > 0.45)
		_check.call(white_free, "A3 %s: nothing but the ring colour is near white" % name)
		_check.call(hazard_free, "A3 %s: no palette colour near the hazard hue" % name)
	_check.call(_near_white(MazeWorlds.RING), "A3 the ring colour is the near-white one")
	_check.call(
		_hue_gap(MazeLilith.HEADBAND, hz) >= 25.0, "A3 the headband hue is at least 25 degrees from the hazard (B3)"
	)


## independent text-based version of the ring-face rule: # next to a cell that is not # X ^ (below the grid is empty)
func _text_lip(rows: PackedStringArray, x: int, y: int, face: int) -> bool:
	if rows[y][x] != "#":
		return false
	var n: Vector2i = Vector2i(x, y) + MazeLevel.FACE_STEP[face]
	if n.x < 0 or n.x >= rows[0].length() or n.y < 0:
		return false
	if n.y >= rows.size():
		return true
	return not rows[n.y][n.x] in ["#", "X", "^"]


## A4
func _lips() -> void:
	var fixture := H.level(
		["......F.", ".#.X....", ".#^#....", "........", "........", "........", ".....S..", "########"], {"beads": 1}
	)
	_check.call(fixture.valid(), "A4 fixture is a valid level: %s" % fixture.errors)
	var U := MazeLevel.Face.UP
	var D := MazeLevel.Face.DOWN
	var L := MazeLevel.Face.LEFT
	var R := MazeLevel.Face.RIGHT
	_check.call(
		MazeArt.lip_face(fixture, Vector2i(1, 1), U) and MazeArt.lip_face(fixture, Vector2i(1, 1), L)
		and MazeArt.lip_face(fixture, Vector2i(1, 1), R) and not MazeArt.lip_face(fixture, Vector2i(1, 1), D),
		"A4 a block next to empty cells gets lips, not towards a block"
	)
	_check.call(
		MazeArt.lip_face(fixture, Vector2i(1, 2), L) and not MazeArt.lip_face(fixture, Vector2i(1, 2), R),
		"A4 no lip towards a spike"
	)
	_check.call(
		not MazeArt.lip_face(fixture, Vector2i(3, 2), U) and not MazeArt.lip_face(fixture, Vector2i(3, 2), L)
		and MazeArt.lip_face(fixture, Vector2i(3, 2), R),
		"A4 no lip towards X or a spike, lip towards empty"
	)
	var x_any := false
	for f in 4:
		x_any = x_any or MazeArt.lip_face(fixture, Vector2i(3, 1), f)
	_check.call(not x_any, "A4 X never gets a lip")
	_check.call(not MazeArt.lip_face(fixture, Vector2i(0, 7), L), "A4 no lip towards the out-of-bounds side")
	_check.call(MazeArt.lip_face(fixture, Vector2i(0, 7), U), "A4 the floor next to the empty cell above has a lip")
	var same := true
	var rings_on_lips := true
	var lips := 0
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		var rows := lv.render()
		for y in lv.height:
			for x in lv.width:
				for f in 4:
					var got := MazeArt.lip_face(lv, Vector2i(x, y), f)
					lips += 1 if got else 0
					same = same and got == _text_lip(rows, x, y, f)
		for r in lv.preset_rings:
			rings_on_lips = rings_on_lips and MazeArt.lip_face(lv, r["cell"], r["face"])
	_check.call(same and lips > 0, "A4 on every shipped level the lip faces follow the ring rule")
	_check.call(rings_on_lips, "A4 every preset ring sits on a lip face")


## A8, and the hash pins and spread
func _worlds() -> void:
	var ok := true
	for n in [1, 2, 3]:
		ok = ok and MazeWorlds.for_number(n) == MazeWorlds.World.TEMPLE
	for n in [4, 5, 6]:
		ok = ok and MazeWorlds.for_number(n) == MazeWorlds.World.JUNGLE
	for n in [7, 8, 9, 10, 40]:
		ok = ok and MazeWorlds.for_number(n) == MazeWorlds.World.CAVE
	_check.call(ok, "A8 worlds per series position")
	_check.call(MazeWorlds.for_number(0) == MazeWorlds.World.TEMPLE, "A8 position 0 stays in the temple")
	_check.call(
		MazeWorlds.from_name("jungle") == MazeWorlds.World.JUNGLE and MazeWorlds.from_name("cave") == 2
		and MazeWorlds.from_name("temple") == 0 and MazeWorlds.from_name("moon") == -1,
		"A8 world names"
	)
	_check.call(MazeWorlds.palette(99) == MazeWorlds.TEMPLE, "A8 an unknown world gives the temple palette")
	var o := MazeMain.parse_args(PackedStringArray(["--world=cave", "--fps"]))
	var bad := MazeMain.parse_args(PackedStringArray(["--world=moon"]))
	_check.call(o["world"] == "cave" and o["fps"] and bad["world"] == "" and not bad["fps"], "A8 --world and --fps")
	var q := MazeMain.query_args("?fps&world=cave&level=l001&profile=/etc/x&shot=a.png&lang=n%6C")
	_check.call(
		q == PackedStringArray(["--fps", "--world=cave", "--level=l001", "--lang=nl"]),
		"web query: known keys become arguments, profile and shot are dropped (%s)" % [q]
	)
	var qo := MazeMain.parse_args(MazeMain.query_args("fps=0&world=../x&camera=overview&touch=1"))
	_check.call(
		not qo["fps"] and qo["world"] == "" and qo["camera"] == "overview" and qo["touch"],
		"web query: flag off with =0, odd values dropped"
	)
	_check.call(MazeMain.query_args("").is_empty() and MazeMain.query_args("?").is_empty(), "web query: empty is empty")
	var h := [MazeArt.hash3(0, 0, 0), MazeArt.hash3(1, 2, 3), MazeArt.hash3(39, 17, 5), MazeArt.hash3(-4, 9, 1)]
	_check.call(h == HASH_PINS, "hash3 gives the pinned values: %s" % [h])
	var counts := [0, 0, 0, 0]
	for y in 24:
		for x in 28:
			counts[MazeArt.pick(x, y, 7, 4)] += 1
	var even := true
	for c in counts:
		even = even and c >= 0.15 * 672 and c <= 0.35 * 672
	_check.call(even, "pick spreads over four values: %s" % [counts])
	_check.call(MazeArt.pick(3, 4, 5, 9) == MazeArt.pick(3, 4, 5, 9), "pick is deterministic")


func _game_with(extra: PackedStringArray) -> MazeMain:
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	m.args = PackedStringArray(["--profile=" + PROFILE]) + extra
	_node.add_child(m)
	return m


## A6, A8 with the real game screen
func _static_layers() -> void:
	var m := _game_with(PackedStringArray(["--level=l001"]))
	var g := m.game
	g.set_process(false)
	_check.call(g.world.world_id == MazeWorlds.World.TEMPLE, "A8 level 1 is a temple level")
	for i in 120:
		var inp := H.inp(1 if i % 2 == 0 else 0, false, i % 40 == 5)
		_feed(g, inp)
		await _node.get_tree().process_frame
	var chunks: int = g.world.chunk_count()
	_check.call(chunks > 0 and g.world.static_draws() == chunks, "A6 every chunk is drawn once (%d)" % chunks)
	g.restart()
	await _node.get_tree().process_frame
	_check.call(
		g.world.build_count == 1 and g.world.static_draws() == chunks, "A6 a restart does not rebuild the layers"
	)
	_node.remove_child(m)
	m.free()
	_baked_memory()
	_bottom_lip()
	var j := _game_with(PackedStringArray(["--level=l001", "--world=jungle"]))
	_check.call(j.game.world.world_id == MazeWorlds.World.JUNGLE, "A8 --world=jungle gives the jungle world")
	_node.remove_child(j)
	j.free()
	var u := _game_with(PackedStringArray(["--level=l005", "--world=moon"]))
	_check.call(u.game.world.world_id == MazeWorlds.World.JUNGLE, "A8 an unknown --world is ignored")
	_node.remove_child(u)
	u.free()


## no lip along the bottom edge of the level, lips elsewhere unchanged
func _bottom_lip() -> void:
	var gone := true
	var same := true
	var bottom_had_lip := false
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		for y in lv.height:
			for x in lv.width:
				for f in 4:
					var cell := Vector2i(x, y)
					var last_row_down: bool = f == MazeLevel.Face.DOWN and y == lv.height - 1
					if last_row_down:
						bottom_had_lip = bottom_had_lip or MazeArt.lip_face(lv, cell, f)
						gone = gone and not MazeStaticLayer.lip_drawn(lv, cell, f)
					else:
						same = same and MazeStaticLayer.lip_drawn(lv, cell, f) == MazeArt.lip_face(lv, cell, f)
	_check.call(bottom_had_lip, "L2 precondition: lip_face still gives the last row a bottom lip (sim rule 3.10)")
	_check.call(gone, "L2 no lip drawn on the bottom of the last row in any level")
	_check.call(same, "L2 every other lip face is drawn as lip_face says")


## chunk textures: one sprite per chunk, memory per level within the phone budget
func _baked_memory() -> void:
	var worst := 0
	var sprites_ok := true
	var size_ok := true
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		var bake := MazeStaticBake.new()
		bake.build(lv, MazeWorlds.for_number(1))
		var sprites := 0
		for c in bake.get_children():
			if c is Sprite2D:
				sprites += 1
				var vp := c.get_child(0) as SubViewport
				size_ok = size_ok and vp.size.x <= 1280 and vp.size.y <= 1280
		sprites_ok = sprites_ok and sprites == bake.chunk_total and bake.chunk_count() == 2 * bake.chunk_total
		worst = maxi(worst, bake.baked_bytes)
		bake.free()
	_check.call(sprites_ok, "the bake makes one sprite per chunk")
	_check.call(size_ok, "a baked chunk texture is at most 1280 x 1280")
	_check.call(worst <= 24 * 1000 * 1000, "baked textures stay under 24 MB per level (worst %d bytes)" % worst)


## the readability backings and --fps
func _backings() -> void:
	var m := _game_with(PackedStringArray(["--level=l001", "--fps"]))
	var g := m.game
	g.set_process(false)
	g.advance(1.0 / 60.0)
	await _node.get_tree().process_frame
	var hint: Label = g.hud._hint
	var box := hint.get_theme_stylebox("normal") as StyleBoxFlat
	_check.call(box != null and absf(box.bg_color.a - 0.7) < 0.001, "the hint has a backing of alpha 0.7")
	_check.call(hint.size.x < g.hud.size.x, "the hint backing wraps the text, not the screen")
	_check.call(g.hud._fps.visible and g.hud._fps.text.ends_with("fps"), "--fps shows a frame rate label")
	_check.call(hint.visible, "L3 the hint shows in the follow view")
	_node.remove_child(m)
	m.free()
	var ov := _game_with(PackedStringArray(["--level=l006", "--camera=overview"]))
	ov.game.set_process(false)
	for i in 3:
		ov.game.advance(1.0 / 60.0)
		await _node.get_tree().process_frame
	_check.call(not ov.game.hud._hint.visible, "L3 the hint is hidden in the overview")
	_node.remove_child(ov)
	ov.free()
	var q := _game_with(PackedStringArray(["--level=l001"]))
	q.game.set_process(false)
	q.game.advance(1.0 / 60.0)
	_check.call(not q.game.hud._fps.visible, "no frame rate label without --fps")
	_node.remove_child(q)
	q.free()
