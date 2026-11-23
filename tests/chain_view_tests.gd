extends RefCounted
## K6-K8: chain layout, timeline and look rules; the view replays what the shapes give.

const Style := MazeChainShapes.Style
const SOLUTIONS := "res://tests/solutions.json"
const CARD_BOX := Rect2(0, 0, 712, 400)
const EXPORT_BOX := MazeChainView.EXPORT_BOX
const MINI_BOX := Rect2(0, 0, 104, 58)
const EPS := 0.01
const PROFILE := "user://white_maze_test_chain_view.json"
const ZERO_RUN := "R96,RJ4,R32,RJ4,R16,RJ4,R12,RJ8,R24,L4,R28,RJ4,R16,-4,L4,R8,RJ24,R48"
const OVER_RUN := "R2,T142,R70,U,L64,-8,T142,R70,U,R20,-24,T142,R6,RJ14,R80,R12,U,-3,T142,R300"

var _node: Node


func run(check: Callable, node: Node) -> void:
	_node = node
	_clean()
	_layout(check)
	_stacking(check)
	_animation(check)
	_look(check)
	_variants(check)
	_view(check)
	_args(check)
	await _skip(check)
	await _skip_real_input(check)
	await _result_layout(check)
	await _export_and_share(check)
	await _level_select(check)
	_clean()
	WhiteText.lang = "nl"


func _clean() -> void:
	for p in [PROFILE, PROFILE + ".tmp"]:
		DirAccess.remove_absolute(p)


func _main(extra: Array) -> MazeMain:
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	m.args = PackedStringArray(["--profile=" + PROFILE, "--speed=100"] + extra)
	_node.add_child(m)
	return m


func _close(m: MazeMain) -> void:
	_node.remove_child(m)
	m.free()


func _chain_of(id: String) -> Array:
	var sol: String = WhitePuzzleStore.load_json(SOLUTIONS)[id]
	return MazeChain.from_run(MazeLevels.load_level(id), sol)["links"]


func _inside(r: Rect2, outer: Rect2) -> bool:
	return r.position.x >= outer.position.x - EPS and r.position.y >= outer.position.y - EPS \
			and r.end.x <= outer.end.x + EPS and r.end.y <= outer.end.y + EPS


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) <= EPS


func _layout(check: Callable) -> void:
	var boxes := {Style.CARD: CARD_BOX, Style.EXPORT: EXPORT_BOX, Style.MINI: MINI_BOX}
	var pads := {Style.CARD: 18.0, Style.EXPORT: 0.0, Style.MINI: 4.0}
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		var links := _chain_of(id)
		for style: int in boxes:
			var box: Rect2 = boxes[style]
			var lay := MazeChainShapes.layout(lv, links, box, style)
			var inner: Rect2 = lay["inner"]
			var ok := inner == box.grow(-pads[style])
			for p: Vector2 in lay["points"]:
				ok = ok and inner.grow(EPS).has_point(p)
			for r: Rect2 in lay["ghost"]:
				ok = ok and _inside(r, inner)
			if style != Style.MINI:
				ok = ok and _inside(lay["door"], inner)
			check.call(ok, "K6: %s style %d: points, ghost rectangles and door lie inside the inner box" % [id, style])
			var frame := Rect2(-20, -20, lv.width * 40 + 40, lv.height * 40 + 40)
			var k := minf(inner.size.x / frame.size.x, inner.size.y / frame.size.y)
			check.call(
				is_equal_approx(lay["scale"], k) and _inside(lay["map"], inner)
					and _near(lay["map"].get_center(), inner.get_center()),
				"K6: %s style %d: scale follows the formula and the map is centred" % [id, style]
			)
			var mini := style == Style.MINI
			var r: float = lay["bead_r"]
			var bead_ok := r >= (3.2 if mini else 8.0) and r <= (4.5 if mini else 14.0)
			var w: float = lay["thread_w"]
			bead_ok = bead_ok and (is_equal_approx(w, 2.0) if mini else (w >= 2.5 and w <= 4.0))
			check.call(bead_ok, "K6: %s style %d: bead and thread sizes are within their clamps" % [id, style])
			check.call(
				lay["points"].size() == links.size() + 2 and lay["kinds"].size() == lay["points"].size()
					and lay["more"] == 0 and (lay["ghost"].is_empty() == mini),
				"K6: %s style %d: one point per link plus start and end, no ghost map in MINI" % [id, style]
			)
			check.call(
				MazeChainShapes.layout(lv, links, box, style) == lay, "K6: %s style %d: layout is repeatable" % [id, style]
			)
	# pinned values of l004 on the card
	var l4 := MazeLevels.load_level("l004")
	var lay4 := MazeChainShapes.layout(l4, _chain_of("l004"), CARD_BOX, Style.CARD)
	var want := PackedVector2Array([Vector2(59.38776, 248.2857), Vector2(128.3673, 253.4592),
			Vector2(293.9184, 253.4592), Vector2(459.4694, 253.4592), Vector2(625.0204, 179.3061)])
	var same: bool = lay4["points"].size() == want.size()
	for i in mini(want.size(), lay4["points"].size()):
		same = same and _near(lay4["points"][i], want[i])
	check.call(same, "K6: l004 on the card: start, three beads and end are at their pinned places")
	check.call(
		is_equal_approx(lay4["scale"], 676.0 / 1960.0) and is_equal_approx(lay4["bead_r"], 8.0),
		"K6: l004 on the card: scale 676/1960 and bead radius 8"
	)
	var kinds: PackedInt32Array = lay4["kinds"]
	check.call(
		kinds == PackedInt32Array([MazeChainShapes.START, 0, 0, 0, MazeChainShapes.END]),
		"K6: kinds read start, three beads, end"
	)
	# more than MAX_LINKS: drawn up to the limit, the rest is counted
	var many: Array = []
	for i in MazeChain.MAX_LINKS + 5:
		many.append({"kind": MazeChain.Kind.BEAD, "cell": Vector2i(5 + i % 20, 11), "face": 0})
	var lm := MazeChainShapes.layout(l4, many, CARD_BOX, Style.CARD)
	check.call(
		lm["n"] == MazeChain.MAX_LINKS and lm["more"] == 5 and lm["points"].size() == MazeChain.MAX_LINKS + 2,
		"K6: 69 links draw 64 and report 5 more"
	)


func _stacking(check: Callable) -> void:
	var lv := MazeLevels.load_level("l004")
	var twin: Array = [
		{"kind": MazeChain.Kind.BEAD, "cell": Vector2i(7, 11), "face": 0},
		{"kind": MazeChain.Kind.BEAD, "cell": Vector2i(7, 11), "face": 0},
		{"kind": MazeChain.Kind.BEAD, "cell": Vector2i(7, 11), "face": 0},
	]
	var lay := MazeChainShapes.layout(lv, twin, CARD_BOX, Style.CARD)
	var r: float = lay["bead_r"]
	var p: PackedVector2Array = lay["points"]
	check.call(
		_near(p[2], p[1] + Vector2(0, -1.7 * r)) and _near(p[3], p[1] + Vector2(0, -3.4 * r)),
		"K6: equal links stack along the face normal, 1.7 and 3.4 radii"
	)
	var other: Array = [twin[0], {"kind": MazeChain.Kind.BEAD, "cell": Vector2i(7, 11), "face": 2}]
	var lay2 := MazeChainShapes.layout(lv, other, CARD_BOX, Style.CARD)
	var near_face: Vector2 = lay2["points"][2]
	var base: Vector2 = MazeChainShapes.layout(lv, [other[1]], CARD_BOX, Style.CARD)["points"][1]
	check.call(_near(near_face, base), "K6: links on different faces of one cell are not moved")


func _animation(check: Callable) -> void:
	var S := MazeChainShapes
	check.call(absf(S.duration(0) - 0.85) < 0.001, "K7: duration(0) is 0.85")
	check.call(absf(S.duration(3) - 1.39) < 0.001, "K7: duration(3) is 1.39")
	check.call(absf(S.duration(4) - 1.57) < 0.001, "K7: duration(4) is 1.57")
	check.call(absf(S.duration(7) - 2.05) < 0.001, "K7: duration(7) is 2.05")
	var longest := 0.0
	for n in MazeChain.MAX_LINKS + 1:
		longest = maxf(longest, S.duration(n))
	check.call(longest <= 2.05 + 0.001, "K7: no chain takes longer than 2.05 s (%.3f)" % longest)
	var s0 := S.anim_state(0.0, 3)
	var none := true
	for k in s0["link_k"]:
		none = none and k < 0.0
	check.call(s0["card_a"] == 0.0 and none and not s0["last_seg"] and s0["slack"] == 1.0, "K7: at t = 0 nothing is shown")
	var step := S.bead_step(3)
	var mid := S.anim_state(S.T_IN + 0.5 * step, 3)
	check.call(
		absf(mid["link_k"][0] - 0.5) < 0.001 and mid["link_k"][1] < 0.0 and mid["card_a"] == 1.0,
		"K7: halfway into the first bead its k is 0.5"
	)
	var t_taut := S.T_IN + 3 * step
	check.call(
		S.anim_state(t_taut - 0.01, 3)["slack"] == 1.0 and not S.anim_state(t_taut - 0.01, 3)["last_seg"],
		"K7: the thread is slack before the taut phase"
	)
	check.call(
		S.anim_state(t_taut + S.TAUT_S, 3)["slack"] == 0.0 and S.anim_state(t_taut, 3)["last_seg"],
		"K7: the thread is taut after the taut phase"
	)
	for n in [0, 1, 3, 4, 7, 20, 64]:
		var end := S.anim_state(S.duration(n), n)
		var final := true
		for k in end["link_k"]:
			final = final and k == 1.0
		check.call(
			final and end["card_a"] == 1.0 and end["last_seg"] and end["slack"] == 0.0 and end["end_k"] == 1.0
				and end["done"] and not S.anim_state(S.duration(n) - 0.05, n)["done"],
			"K7: the state at duration(%d) is the final state" % n
		)
	var lv := MazeLevels.load_level("l004")
	var lay := S.layout(lv, _chain_of("l004"), CARD_BOX, Style.CARD)
	var cols := S.colours(0)
	var at_end := S.shapes(lay, S.anim_state(S.duration(3), 3), cols, true, Style.CARD)
	var way_after := S.shapes(lay, S.anim_state(99.0, 3), cols, true, Style.CARD)
	check.call(at_end == way_after, "K7: shapes at duration(n) equal shapes at t = 99")
	var early := S.shapes(lay, S.anim_state(S.T_IN + 0.5 * step, 3), cols, true, Style.CARD)
	check.call(early.size() < at_end.size(), "K7: the beads that did not appear yet are not drawn")
	check.call(absf(S.ease_out_back(0.0)) < 1e-9 and absf(S.ease_out_back(1.0) - 1.0) < 1e-9, "K7: ease_out_back runs 0 to 1")


func _thread_polylines(prims: Array, cols: Dictionary, w: float) -> int:
	var n := 0
	for s: Dictionary in prims:
		if s["t"] == "polyline" and s["col"] == cols["thread"] and is_equal_approx(s["w"], w):
			n += 1
	return n


func _has_clasp(prims: Array, cols: Dictionary) -> bool:
	for s: Dictionary in prims:
		if s["t"] == "polyline" and s["col"] == cols["clasp"] and is_equal_approx(s["w"], 3.5):
			return true
	return false


func _has_end_knot(prims: Array, lay: Dictionary, cols: Dictionary) -> bool:
	var end: Vector2 = lay["points"][lay["points"].size() - 1]
	for s: Dictionary in prims:
		if s["t"] == "circle" and s["col"] == cols["thread"] and _near(s["c"], end):
			return true
	return false


func _look(check: Callable) -> void:
	var S := MazeChainShapes
	var button: Color = WhiteTheme.BUTTON["normal"]
	for w in MazeSkins.PACKS.size():
		var pal := MazeWorlds.palette(w)
		var cols := S.colours(w)
		var name := str(MazeSkins.PACKS[w]["id"])
		check.call(
			MazeArt.contrast(cols["thread"], pal["back_top"]) >= 3.0
				and MazeArt.contrast(cols["thread"], pal["back_bottom"]) >= 3.0,
			"K8: %s: the thread has contrast 3.0 against both background colours" % name
		)
		check.call(
			MazeArt.contrast(cols["clasp"], pal["back_top"]) >= 3.0
				and MazeArt.contrast(cols["clasp"], pal["back_bottom"]) >= 3.0,
			"K8: %s: the clasp has contrast 3.0 against both background colours" % name
		)
		check.call(
			MazeArt.contrast(S.colours(w, button)["thread"], button) >= 3.0,
			"K8: %s: the MINI thread has contrast 3.0 against the card button" % name
		)
		check.call(
			cols["bead"] == MazeWorlds.RING and cols["outline"] == MazeWorldView.RING_OUTLINE
				and cols["bead_shade"] == MazeWorlds.RING.darkened(0.10),
			"K8: %s: beads use only the ring white, its shade and the ring outline" % name
		)
	# bead circles in the primitives use only those three colours
	var lv := MazeLevels.load_level("l004")
	var lay := S.layout(lv, _chain_of("l004"), CARD_BOX, Style.CARD)
	var cols := S.colours(0)
	var prims := S.shapes(lay, S.anim_state(99.0, 3), cols, true, Style.CARD)
	var r: float = lay["bead_r"]
	var allowed := [cols["bead"], cols["bead_shade"], cols["outline"]]
	var bead_circles := 0
	var colours_ok := true
	for s: Dictionary in prims:
		if s["t"] == "circle" and (is_equal_approx(s["r"], r + 1.5) or is_equal_approx(s["r"], r) \
				or is_equal_approx(s["r"], 0.82 * r)):
			bead_circles += 1
			colours_ok = colours_ok and allowed.has(s["col"])
	check.call(bead_circles == 9 and colours_ok, "K8: three beads are three circles each, in the allowed colours (%d)" % bead_circles)
	# clasp or end knot, never both
	var par_prims := prims
	check.call(_has_clasp(par_prims, cols) and not _has_end_knot(par_prims, lay, cols), "K8: at par: clasp and no end knot")
	var over := S.shapes(lay, S.anim_state(99.0, 3), cols, false, Style.CARD)
	check.call(not _has_clasp(over, cols) and _has_end_knot(over, lay, cols), "K8: over par: end knot and no clasp")
	var mini_lay := S.layout(lv, _chain_of("l004"), MINI_BOX, Style.MINI)
	var mini_cols := S.colours(0, WhiteTheme.BUTTON["normal"])
	var mini := S.shapes(mini_lay, S.anim_state(99.0, 3), mini_cols, true, Style.MINI)
	var hollow := true
	for s: Dictionary in mini:
		hollow = hollow and s["t"] != "vpoly" and not (s["t"] == "polyline" and s["col"] == mini_cols["thread_under"])
	check.call(hollow, "K8: MINI has no background and no under-stroke")
	# fade-in: card alpha scales the background
	var faded := S.shapes(lay, S.anim_state(0.0, 3), cols, true, Style.CARD)
	check.call(faded[0]["cols"][0].a == 0.0 and prims[0]["cols"][0].a == 1.0, "K8: the card fades in from alpha 0")


func _variants(check: Callable) -> void:
	var S := MazeChainShapes
	var lv := MazeLevels.load_level("l004")
	var cols := S.colours(0)
	var lay := S.layout(lv, [], CARD_BOX, Style.CARD)
	var prims := S.shapes(lay, S.anim_state(99.0, 0), cols, true, Style.CARD)
	check.call(
		_thread_polylines(prims, cols, lay["thread_w"]) == 1,
		"K8: with no links the thread is one segment from start to end"
	)
	check.call(_has_clasp(prims, cols), "K8: no links is at most par: the clasp shows")
	var knot := [{"kind": MazeChain.Kind.KNOT, "cell": Vector2i(7, 11), "face": 0}]
	var lay_k := S.layout(lv, knot, CARD_BOX, Style.CARD)
	var with_knot := S.shapes(lay_k, S.anim_state(99.0, 1), cols, true, Style.CARD)
	var circles := 0
	for s: Dictionary in with_knot:
		if s["t"] == "circle" and is_equal_approx(s["r"], lay_k["knot_r"]) and s["col"] == cols["thread"]:
			circles += 1
	check.call(circles == 2, "K8: a knot is a small knot in the thread colour, not a bead (start knot and one)")
	var many: Array = []
	for i in MazeChain.MAX_LINKS + 3:
		many.append({"kind": MazeChain.Kind.BEAD, "cell": Vector2i(5 + i % 20, 11), "face": 0})
	var lay_m := S.layout(lv, many, CARD_BOX, Style.CARD)
	var text := ""
	for s: Dictionary in S.shapes(lay_m, S.anim_state(99.0, lay_m["n"]), cols, false, Style.CARD):
		if s["t"] == "text":
			text = s["text"]
	check.call(text == "+3", "K8: more than 64 links show a +N label")


func _view(check: Callable) -> void:
	var lv := MazeLevels.load_level("l004")
	var links := _chain_of("l004")
	var v := MazeChainView.new()
	v.size = CARD_BOX.size
	_node.add_child(v)
	v.setup(lv, links, 0, true)
	check.call(v.animating() and v.time() == 0.0, "view: a new view animates from t = 0")
	var first := v.primitives().size()
	v._process(0.3 / 6.0)
	for i in 5:
		v._process(0.05)
	check.call(absf(v.time() - 0.3) < 1e-6 and v.primitives().size() > first, "view: frames advance the time")
	v._process(5.0)
	check.call(absf(v.time() - 0.4) < 1e-6, "view: a long frame is capped at 0.1 s")
	v.finish_now()
	check.call(not v.animating(), "view: finish_now ends the animation")
	var final := MazeChainShapes.shapes(
		MazeChainShapes.layout(lv, links, Rect2(Vector2.ZERO, v.size), Style.CARD),
		MazeChainShapes.anim_state(99.0, 3), MazeChainShapes.colours(0), true, Style.CARD
	)
	check.call(v.primitives() == final, "view: the primitives are what the shapes give")
	v.setup(lv, links, 0, true, 0.3, true)
	v._process(1.0)
	check.call(v.time() == 0.3 and not v.animating(), "view: a frozen view stays at its time")
	v.setup(lv, links, 0, true, MazeChainShapes.FINAL_T, true)
	check.call(v.primitives() == final, "view: frozen at the final time shows the final state")
	_node.remove_child(v)
	v.free()


func _args(check: Callable) -> void:
	var o := MazeMain.parse_args(PackedStringArray(["--chain-t=0.55", "--reduced-motion"]))
	check.call(is_equal_approx(o["chain_t"], 0.55) and o["reduced_motion"], "args: --chain-t and --reduced-motion")
	var d := MazeMain.parse_args(PackedStringArray())
	check.call(d["chain_t"] == -1.0 and not d["reduced_motion"], "args: the chain defaults are off")
	var bad := MazeMain.parse_args(PackedStringArray(["--chain-t=-2"]))
	var junk := MazeMain.parse_args(PackedStringArray(["--chain-t=soon"]))
	check.call(bad["chain_t"] == -1.0 and junk["chain_t"] == -1.0, "args: a bad --chain-t is ignored")


func _key(code: int, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code as Key
	k.pressed = pressed
	k.echo = echo
	return k


func _mouse() -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	return m


func _touch() -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.pressed = true
	return t


func _advance(view: MazeChainView, seconds: float) -> void:
	for i in int(round(seconds / 0.05)):
		view._process(0.05)


func _skip(check: Callable) -> void:
	WhiteText.lang = "nl"
	var presses := {"key": _key(KEY_SPACE), "mouse": _mouse(), "touch": _touch()}
	for what: String in presses:
		_clean()
		var m := _main(["--level=l004", "--solve"])
		var g := m.game
		g.set_process(false)
		var ov := g.overlays
		var v := ov.chain_view
		v.set_process(false) # the test sets the animation time itself
		check.call(g.last_result.has("links") and ov.chain_animating() and v.time() == 0.0, "K9: %s: the chain animates after the finish" % what)
		_advance(v, 0.1)
		ov._input(presses[what])
		check.call(ov.chain_animating() and ov.result_visible(), "K9: %s: a press at 0.1 s is eaten by the grace time" % what)
		_advance(v, 0.4)
		await _node.get_tree().process_frame # a second press comes in a later frame than the first
		check.call(absf(v.time() - 0.5) < 1e-6 and ov.chain_animating(), "K9: %s: the animation runs to 0.5 s" % what)
		ov._input(presses[what])
		check.call(
			not ov.chain_animating() and ov.result_visible() and m.game == g and m.select == null
				and g.sim.finished() and g.level.id == "l004",
			"K9: %s: a press at 0.5 s ends the animation and stays on the result" % what
		)
		check.call(v.time() >= MazeChainShapes.duration(3), "K9: %s: the chain is in its final state" % what)
		g._input(_key(KEY_ENTER))
		check.call(m.game != null and m.game.level.id == "l005", "K9: %s: after the animation Enter opens the next level" % what)
		_close(m)
	# keys held from playing and releases never skip
	_clean()
	var m2 := _main(["--level=l004", "--solve"])
	m2.game.set_process(false)
	var ov2 := m2.game.overlays
	_advance(ov2.chain_view, 0.6)
	ov2._input(_key(KEY_SPACE, false))
	ov2._input(_key(KEY_SPACE, true, true))
	check.call(ov2.chain_animating(), "K9: a key release and a key echo do not skip")
	# Enter during the animation does not open the next level
	m2.game._input(_key(KEY_ENTER))
	check.call(m2.game.level.id == "l004", "K9: Enter during the animation does not open the next level")
	_close(m2)
	# reduced motion and shots start in the final state
	_clean()
	var m3 := _main(["--level=l004", "--solve", "--reduced-motion"])
	check.call(not m3.game.overlays.chain_animating() and m3.game.overlays.chain_view != null, "K9: reduced motion: not animating from the first frame")
	_close(m3)
	_clean()
	var m4 := _main(["--level=l004", "--solve", "--chain-t=0.55"])
	var v4 := m4.game.overlays.chain_view
	check.call(is_equal_approx(v4.time(), 0.55) and not m4.game.overlays.chain_animating(), "K9: --chain-t freezes the chain at that time")
	_close(m4)
	_clean()
	var m5 := _main(["--level=l004", "--solve", "--shot=/tmp/x.png"])
	check.call(not m5.game.overlays.chain_animating(), "K9: a shot shows the final state")
	_close(m5)
	# fixtures of the over-par and zero-ring scenarios
	var l4 := MazeChain.from_run(MazeLevels.load_level("l004"), OVER_RUN.replace(",", " "))
	check.call(
		l4["finished"] and l4["rings"] == 4 and MazeChain.encode(l4["links"]) == "bu7.11-bu7.11-bu19.11-bu31.11",
		"fixture: the over-par run of l004 uses 4 rings with two stacked beads"
	)
	var l1 := MazeChain.from_run(MazeLevels.load_level("l001"), ZERO_RUN.replace(",", " "))
	check.call(
		l1["finished"] and l1["rings"] == 0 and MazeChain.encode(l1["links"]) == "ku26.11",
		"fixture: the zero-ring run of l001 finishes without rings (card #010 may close this opening: then replace it)"
	)
	_clean()


func _result_data(rings: int, par: int) -> Dictionary:
	var lv := MazeLevels.load_level("l001")
	var res := MazeChain.from_run(lv, WhitePuzzleStore.load_json(SOLUTIONS)["l001"])
	var links: Array = res["links"] if rings > 0 else []
	return {
		"ticks": 391, "rings": rings, "par": par, "new_best": true, "best_ticks": 391, "has_next": true,
		"level": lv, "links": links, "world": 0, "number": 1, "name": "Eerste ring",
	}


func _result_layout(check: Callable) -> void:
	var cases := [
		[Vector2i(1280, 720), "", Vector2(712, 400)],
		[Vector2i(1600, 720), "60,0,60,24", Vector2(800, 450)],
		[Vector2i(1280, 960), "", Vector2(712, 400)],
	]
	for c: Array in cases:
		var size: Vector2i = c[0]
		var sv := SubViewport.new()
		sv.size = size
		_node.add_child(sv)
		var ov := MazeOverlays.new()
		ov.safe_override = c[1]
		sv.add_child(ov)
		ov.show_result(_result_data(1, 1))
		await _node.get_tree().process_frame
		await _node.get_tree().process_frame
		var ins := WhiteSafeArea.parse(c[1])
		var safe := Rect2(ins["left"], ins["top"], size.x - ins["left"] - ins["right"], size.y - ins["top"] - ins["bottom"])
		var card := ov.chain_view.get_global_rect()
		var col := ov.result_column.get_global_rect()
		var tag := "%dx%d %s" % [size.x, size.y, c[1]]
		check.call(safe.encloses(card) and safe.encloses(col), "K13: %s: card and column lie inside the safe rect (%s %s)" % [tag, card, col])
		check.call(not card.intersects(col), "K13: %s: card and column do not overlap" % tag)
		check.call(card.size.is_equal_approx(c[2]), "K13: %s: the card is %s (%s)" % [tag, c[2], card.size])
		check.call(card.size.x >= 480.0 and card.size.x <= 800.0 and absf(card.size.x / card.size.y - 16.0 / 9.0) < 0.01, "K13: %s: the card is 480 to 800 wide and 16:9" % tag)
		check.call(ov.chain_view.layout()["bead_r"] >= 8.0, "K13: %s: l001 beads are at least 8 px" % tag)
		sv.remove_child(ov)
		ov.free()
		_node.remove_child(sv)
		sv.free()
	# L2: the tallest column (no rings line, share feedback) stays under the HUD buttons, also in English on a phone
	WhiteText.lang = "en"
	for c: Array in [[Vector2i(1600, 720), "40,0,40,16"], [Vector2i(1600, 720), "60,0,60,24"], [Vector2i(1280, 720), ""]]:
		var sv := SubViewport.new()
		sv.size = c[0]
		_node.add_child(sv)
		var ov := MazeOverlays.new()
		ov.safe_override = c[1]
		sv.add_child(ov)
		ov.show_result(_result_data(0, 1))
		ov.share_feedback.text = "Saved: /somewhere/white-maze-l001-0-391.png"
		await _node.get_tree().process_frame
		await _node.get_tree().process_frame
		var ins := WhiteSafeArea.parse(c[1])
		var col := ov.result_column.get_global_rect()
		check.call(col.position.y >= MazeOverlays.HUD_CLEAR + ins["top"] - 0.5 and col.end.y <= c[0].y - ins["bottom"] + 0.5,
				"L2: en %s %s: the column stays under the HUD and above the bottom (%s)" % [c[0], c[1], col])
		_node.remove_child(sv)
		sv.free()
	WhiteText.lang = "nl"
	check.call(MazeOverlays.card_size(Vector2(1232, 300)) == Vector2(533, 300), "K13: a low screen shrinks the card to the free height")
	# a resized viewport is followed
	var sv2 := SubViewport.new()
	sv2.size = Vector2i(1280, 720)
	_node.add_child(sv2)
	var ov2 := MazeOverlays.new()
	sv2.add_child(ov2)
	ov2.show_result(_result_data(1, 1))
	await _node.get_tree().process_frame
	sv2.size = Vector2i(1600, 720)
	await _node.get_tree().process_frame
	await _node.get_tree().process_frame
	check.call(ov2.chain_view.get_global_rect().size.is_equal_approx(Vector2(800, 450)), "K13: the card follows a resized viewport")
	# the no_rings line
	var zero := ov2
	zero.show_result(_result_data(0, 1))
	var found := false
	for l: Node in zero.result_column.get_children():
		found = found or (l is Label and l.text == MazeStrings.s("no_rings"))
	check.call(found, "K13: a result with 0 rings adds the no_rings line")
	var plain := false
	zero.show_result(_result_data(1, 1))
	for l: Node in zero.result_column.get_children():
		plain = plain or (l is Label and l.text == MazeStrings.s("no_rings"))
	check.call(not plain, "K13: a result with rings has no no_rings line")
	_node.remove_child(sv2)
	sv2.free()


func _export_info(id: String) -> Dictionary:
	_clean()
	var m := _main(["--level=" + id, "--solve"])
	var r: Dictionary = m.game.last_result
	var info := {
		"level": r["level"], "links": r["links"], "world": r["world"], "clasp": r["rings"] <= r["par"],
		"number": r["number"], "name": r["name"], "ticks": r["ticks"], "rings": r["rings"], "par": r["par"],
		"code": r["code"],
	}
	_close(m)
	return info


func _texts_of(info: Dictionary) -> Array:
	var v := MazeChainView.new()
	v.style = Style.EXPORT
	v.export_info = info
	v.size = Vector2(MazeChainView.EXPORT_SIZE)
	v.setup(info["level"], info["links"], info["world"], info["clasp"], MazeChainShapes.FINAL_T, true)
	_node.add_child(v)
	var out := v.texts()
	_node.remove_child(v)
	v.free()
	return out


## M1: a chain of n beads on l004 for the export, any length
func _long_info(n: int) -> Dictionary:
	var lv := MazeLevels.load_level("l004")
	var links: Array = []
	for i in n:
		links.append({"kind": MazeChain.Kind.BEAD, "cell": Vector2i(2 + (i * 7) % 36, 11), "face": 0})
	var text := MazeChain.encode(links)
	return {
		"level": lv, "links": links, "world": 1, "clasp": false, "number": 4, "name": "Eén kraal", "ticks": 4321,
		"rings": n, "par": 3, "code": MazeChain.code(lv.id, n, 3, 4321, text),
	}


func _export_footer(check: Callable) -> void:
	WhiteText.lang = "nl"
	var font := ThemeDB.fallback_font
	for n in [1, 4, 11, 13, 30, 64]:
		var info := _long_info(n)
		var code_text := ""
		var address := {}
		var rings_line := {}
		for t: Dictionary in _texts_of(info):
			if t["text"] == "play.white-maze.steefbeest.nl":
				address = t
			elif t["pos"].x == 40.0 and t["pos"].y == MazeChainView.CODE_BASELINE:
				code_text = t["text"]
			elif t["size"] == 22 and t["align"] == "right":
				rings_line = t
		var cw := font.get_string_size(code_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var aw := font.get_string_size(address["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var h := font.get_height(18)
		var code_top: float = MazeChainView.CODE_BASELINE - font.get_ascent(18)
		var code_bottom: float = MazeChainView.CODE_BASELINE + font.get_descent(18)
		var addr_top: float = address["pos"].y - font.get_ascent(18)
		var tag := "%d rings (code %d characters)" % [n, str(info["code"]).length()]
		check.call(cw <= MazeChainView.FOOT_W and 40.0 + cw <= 1160.0, "M1: %s: the code line fits the image (%.0f px)" % [tag, cw])
		check.call(code_bottom <= addr_top and address["pos"].x - aw >= 40.0, "M1: %s: the code never runs into the address" % tag)
		check.call((code_text == info["code"]) == (cw < MazeChainView.FOOT_W and not code_text.ends_with("…")), "M1: %s: only a long code is cut, with an ellipsis" % tag)
		if code_text != info["code"]:
			check.call(code_text.ends_with("…") and info["code"].begins_with(code_text.trim_suffix("…")), "M1: %s: a cut code is a prefix and an ellipsis" % tag)
		check.call(MazeChainShapes.layout(info["level"], info["links"], MazeChainView.EXPORT_BOX, Style.EXPORT)["inner"].end.y <= code_top, "M1: %s: the chain box ends above the code line" % tag)
		var rw := font.get_string_size(rings_line["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		check.call(1160.0 - rw >= 40.0 and h > 0.0, "M1: %s: the rings line stays inside the image" % tag)
		check.call(MazeChainShare.share_text(info).contains(str(info["code"])), "M1: %s: the share text holds the whole code" % tag)
		var lay := MazeChainShapes.layout(info["level"], info["links"], MazeChainView.EXPORT_BOX, Style.EXPORT)
		var inside := true
		for p: Vector2 in lay["points"]:
			inside = inside and MazeChainView.EXPORT_BOX.grow(0.01).has_point(p)
		check.call(inside, "M1: %s: every chain point lies in the chain box" % tag)


func _export_and_share(check: Callable) -> void:
	_export_footer(check)
	WhiteText.lang = "nl"
	var info := _export_info("l004")
	var lines := {}
	for t: Dictionary in _texts_of(info):
		lines[t["text"]] = t
	var code: String = info["code"]
	check.call(
		lines.has("WHITE MAZE") and lines.has("4  Eén kraal") and lines.has("0:06.18")
			and lines.has("Ringen: 3 · par 3  Precies par!") and lines.has(code) and lines.has("play.white-maze.steefbeest.nl"),
		"K14: the export holds title, level, time, rings line, code and play address (%s)" % str(lines.keys())
	)
	check.call(
		lines["WHITE MAZE"]["pos"] == Vector2(40, 46) and lines["4  Eén kraal"]["pos"] == Vector2(40, 92)
			and lines["0:06.18"]["pos"] == Vector2(1160, 52) and lines["0:06.18"]["align"] == "right"
			and lines[code]["pos"] == Vector2(40, 618) and lines["play.white-maze.steefbeest.nl"]["pos"] == Vector2(1160, 654),
		"K14: the export texts sit at the places of 22.11.1"
	)
	var no_code := info.duplicate()
	no_code["code"] = ""
	var count := _texts_of(no_code).size()
	check.call(count == _texts_of(info).size() - 1, "K14: without a share code the code line is left out")
	var zero := info.duplicate()
	zero["rings"] = 0
	var has_no_rings := false
	for t: Dictionary in _texts_of(zero):
		has_no_rings = has_no_rings or t["text"] == "Ringen: 0 · par 3  Zonder ringen!"
	check.call(has_no_rings, "K14: the zero-ring export says no rings")
	var cave := _export_info("l009")
	WhiteText.lang = "en"
	var english := ""
	for t: Dictionary in _texts_of(cave):
		english += t["text"] + "|"
	check.call("Rings: 4 · par 4  Exactly par!" in english, "K14: the export follows the language (%s)" % english)
	WhiteText.lang = "nl"
	var long_name := info.duplicate()
	long_name["name"] = "x".repeat(90)
	var heading := ""
	for t: Dictionary in _texts_of(long_name):
		if t["pos"] == Vector2(40, 92):
			heading = t["text"]
	var width := ThemeDB.fallback_font.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	check.call(heading.ends_with("…") and width <= MazeChainView.NAME_MAX_W, "K14: a long name is cut with an ellipsis within 640 px (%.0f)" % width)
	# file name, share text, JS
	check.call(MazeChainShare.file_name("l004", 3, 371) == "white-maze-l004-3-371.png", "K14: the file name follows 22.11.3")
	var text := MazeChainShare.share_text(info)
	check.call(
		text == "White Maze 4 · Eén kraal · 3 ringen · par 3 · 0:06.18\n%s\nhttps://play.white-maze.steefbeest.nl" % code,
		"K14: the share text is the line, the code and the play address (%s)" % text
	)
	var rest := text.replace("https://play.white-maze.steefbeest.nl", "")
	check.call(not rest.contains("http") and not rest.contains("www."), "K14: the share text has no other address")
	var js := MazeChainShare.SHARE_JS
	var clean := true
	for bad in ["fetch", "XMLHttpRequest", "sendBeacon", "http", "import(", "WebSocket", "eval("]:
		clean = clean and not js.contains(bad)
	check.call(clean, "K14: the share script makes no network request and loads nothing")
	check.call(js.count("window.") == 2 and js.begins_with("window.whiteMazeShare = window.whiteMazeShare ||"), "K14: the script keeps to one global")
	# the result overlay: button, feedback, local save
	for is_web in [false, true]:
		var sv := SubViewport.new()
		sv.size = Vector2i(1280, 720)
		_node.add_child(sv)
		var ov := MazeOverlays.new()
		ov.web = is_web
		sv.add_child(ov)
		var data := _result_data(1, 1)
		data["code"] = "wm1/l001/1/1/391/ku26.11-bu38.11"
		ov.show_result(data)
		await _node.get_tree().process_frame
		var btn := ov.share_button
		check.call(
			btn != null and btn.text == ("Delen" if is_web else "Afbeelding bewaren") and btn.focus_mode == Control.FOCUS_ALL,
			"K14: web %s: the share button says %s and takes focus by keys" % [is_web, btn.text if btn != null else "-"]
		)
		check.call(not btn.has_focus() and ov.share_feedback.text == "", "K14: web %s: the button is not focused and the feedback is empty" % is_web)
		var ready := not ov._export.png.is_empty()
		check.call(btn.disabled == not ready, "K14: web %s: the button is disabled until the image is ready (ready %s)" % [is_web, ready])
		if not is_web:
			ov._export.png = PackedByteArray([137, 80, 78, 71])
			btn.disabled = false
			btn.pressed.emit()
			var saved := FileAccess.get_file_as_bytes("user://chains/white-maze-l001-1-391.png")
			check.call(saved.size() == 4 and ov.share_feedback.text.begins_with("Bewaard: "), "K14: saving writes the file and shows where (%s)" % ov.share_feedback.text)
			DirAccess.remove_absolute("user://chains/white-maze-l001-1-391.png")
			DirAccess.remove_absolute("user://chains")
		sv.remove_child(ov)
		ov.free()
		_node.remove_child(sv)
		sv.free()
	check.call(MazeChainShare.save_local(PackedByteArray(), "x.png") == "", "K14: an empty image is not saved")
	# --chain-export shows only the share card
	_clean()
	var m := _main(["--level=l004", "--solve", "--chain-export"])
	var ov2 := m.game.overlays
	check.call(
		ov2.result_visible() and ov2.chain_view != null and ov2.chain_view.style == Style.EXPORT and ov2.share_button == null,
		"K14: --chain-export shows only the share card"
	)
	_close(m)
	_clean()


func _all_levels() -> Array[MazeLevel]:
	var out: Array[MazeLevel] = []
	for id in MazeLevels.ids():
		out.append(MazeLevels.load_level(id))
	return out


func _minis(card: Control) -> Array:
	var out := []
	for c in card.get_children():
		if c is MazeChainView:
			out.append(c)
	return out


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var f := _find_scroll(c)
		if f != null:
			return f
	return null


func _select_in(size: Vector2i, store: MazeProfileStore, levels: Array[MazeLevel]) -> Array:
	var sv := SubViewport.new()
	sv.size = size
	_node.add_child(sv)
	var sel := MazeLevelSelect.new()
	sel.levels = levels
	sel.store = store
	sv.add_child(sel)
	await _node.get_tree().process_frame
	await _node.get_tree().process_frame
	return [sv, sel]


func _level_select(check: Callable) -> void:
	var levels := _all_levels()
	var demo := MazeProfileStore.new()
	demo.open_memory("nl", 0)
	MazeMain.fill_demo_profile(demo.data, levels)
	var ok := true
	for lv in levels:
		var chain: Dictionary = demo.data["levels"][lv.id].get("chain", {})
		var want := MazeChain.from_run(lv, WhitePuzzleStore.load_json(SOLUTIONS)[lv.id])
		ok = ok and chain.get("links", "") == MazeChain.encode(want["links"]) and chain["rings"] == want["rings"]
	check.call(ok, "K12: --demo-profile finishes every level with its replayed chain")
	for lang in ["nl", "en"]:
		WhiteText.lang = lang
		for size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720)]:
			var made := await _select_in(size, demo, levels)
			var sel: MazeLevelSelect = made[1]
			var tag := "%s %dx%d" % [lang, size.x, size.y]
			var one_each := sel.cards.size() == levels.size()
			for card in sel.cards:
				one_each = one_each and _minis(card).size() == 1
			check.call(one_each, "K12: %s: every finished card has exactly one mini chain" % tag)
			var font := ThemeDB.fallback_font
			var pad: float = sel.cards[0].get_theme_stylebox("normal").content_margin_left
			var fits := true
			var below := true
			var inside := true
			var detail := ""
			for i in sel.cards.size():
				var card: Button = sel.cards[i]
				var lines := card.text.split("\n")
				var room := card.size.x - MazeLevelSelect.MINI_SIZE.x - 2.0 * MazeLevelSelect.MINI_INSET
				for j in 2:
					var w := font.get_string_size(lines[j], HORIZONTAL_ALIGNMENT_LEFT, -1, WhiteTheme.FONT_BUTTON).x
					if w + 2.0 * pad > room:
						fits = false
						detail = "%s line %d: %.0f > %.0f" % [lines[j], j, w + 2.0 * pad, room]
				var h := font.get_height(WhiteTheme.FONT_BUTTON)
				var top3 := (card.size.y - lines.size() * h) / 2.0 + 2.0 * h
				below = below and top3 >= MazeLevelSelect.MINI_INSET + MazeLevelSelect.MINI_SIZE.y
				var mini: MazeChainView = _minis(card)[0]
				var r := Rect2(mini.global_position - card.global_position, mini.size)
				inside = inside and Rect2(Vector2.ZERO, card.size).encloses(r) \
						and absf(r.end.x - (card.size.x - MazeLevelSelect.MINI_INSET)) < 0.5 \
						and absf(r.position.y - MazeLevelSelect.MINI_INSET) < 0.5 and r.size.is_equal_approx(MazeLevelSelect.MINI_SIZE)
			check.call(fits, "K12: %s: the first two lines stay left of the mini chain (%s)" % [tag, detail])
			check.call(below, "K12: %s: lines 3 and 4 start below the mini chain" % tag)
			check.call(inside, "K12: %s: the mini chain is 104 x 58 in the top right corner, 10 px from the edges" % tag)
			if size.x == 1280:
				var scroll := _find_scroll(sel)
				var content := scroll.get_child(0) as Control
				check.call(content.get_combined_minimum_size().y <= scroll.size.y, "K12: %s: nine cards fit without scrolling (%.0f of %.0f)" % [tag, content.get_combined_minimum_size().y, scroll.size.y])
			_node.remove_child(made[0])
			made[0].free()
	WhiteText.lang = "nl"
	# unfinished, locked and chain-less cards have no mini chain
	var part := MazeProfileStore.new()
	part.open_memory("nl", 0)
	MazeProfile.record_finish(part.data, "l001", 391, 1, "R1", 1, "ku26.11-bu38.11")
	MazeProfile.record_finish(part.data, "l002", 256, 2, "R1", 1)
	var made2 := await _select_in(Vector2i(1280, 720), part, levels)
	var counts := []
	for card in made2[1].cards:
		counts.append(_minis(card).size())
	check.call(counts == [1, 0, 0, 0, 0, 0, 0, 0, 0], "K12: only a finished card with a chain has a mini chain (%s)" % str(counts))
	_node.remove_child(made2[0])
	made2[0].free()
	var empty := MazeProfileStore.new()
	empty.open_memory("nl", 0)
	var made3 := await _select_in(Vector2i(1280, 720), empty, levels)
	var none := true
	for card in made3[1].cards:
		none = none and _minis(card).is_empty()
	check.call(none, "K12: an empty profile shows no mini chains")
	_node.remove_child(made3[0])
	made3[0].free()
	# a stored chain that does not fit the level is not drawn
	var odd := MazeProfileStore.new()
	odd.open_memory("nl", 0)
	MazeProfile.record_finish(odd.data, "l001", 391, 1, "R1", 1, "bu200.50")
	var made4 := await _select_in(Vector2i(1280, 720), odd, levels)
	check.call(_minis(made4[1].cards[0]).is_empty(), "K12: a chain outside the level is not drawn")
	_node.remove_child(made4[0])
	made4[0].free()


func _button_centre(ov: MazeOverlays, text: String) -> Vector2:
	for b: Node in ov.result_column.get_children():
		if b is Button and b.text == text:
			return ov.get_viewport().get_final_transform() * b.get_global_rect().get_center() # canvas to window
	return Vector2(-1, -1)


func _tap_event(pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	return t


func _mouse_at(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = pos
	m.global_position = pos
	m.pressed = pressed
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return m


## H1: through the real input path (touch plus its emulated mouse click) a tap that skips the chain presses no button
func _skip_real_input(check: Callable) -> void:
	WhiteText.lang = "nl"
	var frames := _node.get_tree().process_frame
	for target: String in ["Volgende", "Opnieuw", "Levels"]:
		for kind: String in ["touch", "mouse"]:
			_clean()
			var m := _main(["--level=l004", "--solve"])
			var g := m.game
			var ov := g.overlays
			await frames
			await frames
			var v := ov.chain_view
			for i in 6:
				v._process(0.1)
				if v.time() > 0.6:
					break
			var tag := "%s with %s" % [target, kind]
			var at := _button_centre(ov, target)
			check.call(ov.chain_animating() and at.x > 0.0, "H1: %s: the chain still animates at %.2f s" % [tag, v.time()])
			Input.parse_input_event(_tap_event(at, true) if kind == "touch" else _mouse_at(at, true))
			await frames
			await frames
			check.call(not ov.chain_animating(), "H1: %s: the tap ends the animation" % tag)
			check.call(m.game == g and m.select == null and g.level.id == "l004" and ov.result_visible() and g.sim.finished(),
					"H1: %s: the tap that skips presses no button" % tag)
			Input.parse_input_event(_tap_event(at, false) if kind == "touch" else _mouse_at(at, false))
			await frames
			await frames
			check.call(m.game == g and m.select == null and ov.result_visible() and g.sim.finished(),
					"H1: %s: its release presses no button either" % tag)
			# a new touch after the animation works
			Input.parse_input_event(_tap_event(at, true) if kind == "touch" else _mouse_at(at, true))
			await frames
			Input.parse_input_event(_tap_event(at, false) if kind == "touch" else _mouse_at(at, false))
			await frames
			await frames
			var acted := false
			match target:
				"Volgende":
					acted = m.game != null and m.game.level.id == "l005"
				"Opnieuw":
					acted = m.game != null and not m.game.overlays.result_visible()
				"Levels":
					acted = m.select != null
			check.call(acted, "H1: %s: a new tap after the animation presses the button" % tag)
			_close(m)
	_clean()
