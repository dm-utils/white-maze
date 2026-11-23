extends RefCounted
## K6-K8: chain layout, timeline and look rules; the view replays what the shapes give.

const Style := MazeChainShapes.Style
const SOLUTIONS := "res://tests/solutions.json"
const CARD_BOX := Rect2(0, 0, 712, 400)
const EXPORT_BOX := Rect2(40, 124, 1120, 488)
const MINI_BOX := Rect2(0, 0, 104, 58)
const EPS := 0.01

var _node: Node


func run(check: Callable, node: Node) -> void:
	_node = node
	_layout(check)
	_stacking(check)
	_animation(check)
	_look(check)
	_variants(check)
	_view(check)


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
			var bead_ok := r >= (2.5 if mini else 8.0) and r <= (4.0 if mini else 14.0)
			var w: float = lay["thread_w"]
			bead_ok = bead_ok and (is_equal_approx(w, 1.25) if mini else (w >= 2.5 and w <= 4.0))
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
