class_name MazeChainShapes
extends RefCounted
## Layout, colours, timeline and draw primitives of the chain (design 22.5 to 22.7). Pure: primitives are in the
## format of MazeDecor.shapes (poly, vpoly, line, polyline, circle) plus text, so tests read what is drawn.

enum Style { CARD, EXPORT, MINI }

const START := 2 # point kinds next to MazeChain.Kind
const END := 3
const TILE := 40.0
const MARGIN_TILES := 0.5
const PAD := [18.0, 0.0, 4.0] # per style: card, export, mini
const BEAD_K := 0.30 # bead radius in tile fractions
const STACK_STEP := 1.7 # in bead radii
const T_IN := 0.25
const BEAD_S_MAX := 0.18
const STRING_S_MAX := 1.2
const TAUT_S := 0.35
const END_S := 0.25
const SAG_K := 0.18
const SAG_MAX_K := 0.12 # of the inner height
const SAG_POINTS := 12
const DROP_K := 2.5 # in bead radii
const FINAL_T := 99.0
const CARD_RADIUS := 14.0
const CARD_CORNER_POINTS := 6
const BORDER_W := 2.0
const DOOR_ALPHA := 0.25
const MIN_CONTRAST := 3.0
const TAIL_DEG := 120.0
const ARC_STEPS := 4
const CLASP_LEN := 2.6 # in bead radii
const CLASP_WID := 2.0
const CLASP_RADIUS := 0.5
const LABEL_SIZE := 20


## world rectangle of a level with half a tile of margin
static func level_rect(level: MazeLevel) -> Rect2:
	var m := MARGIN_TILES * TILE
	return Rect2(-m, -m, level.width * TILE + 2.0 * m, level.height * TILE + 2.0 * m)


## {"box", "style", "scale", "map", "inner", "points", "kinds", "n", "bead_r", "thread_w", "knot_r", "ghost", "door",
## "more"}; points are start, up to MAX_LINKS links, end
static func layout(level: MazeLevel, links: Array, box: Rect2, style: int) -> Dictionary:
	var frame := level_rect(level)
	var inner := box.grow(-float(PAD[style]))
	var k := minf(inner.size.x / frame.size.x, inner.size.y / frame.size.y)
	var map_size := frame.size * k
	var map := Rect2(inner.position + (inner.size - map_size) / 2.0, map_size)
	var mini := style == Style.MINI
	var bead_r := clampf(BEAD_K * TILE * k, 2.5 if mini else 8.0, 4.0 if mini else 14.0)
	var thread_w := 1.25 if mini else clampf(0.35 * bead_r, 2.5, 4.0)
	var knot_r := (0.6 if mini else 0.45) * bead_r
	var pts := PackedVector2Array()
	var kinds := PackedInt32Array()
	pts.append(_to_map(_centre(level.spawn), map, frame, k))
	kinds.append(START)
	var drawn := drawn_count(links)
	var seen := {}
	for i in drawn:
		var l: Dictionary = links[i]
		var p := _to_map(MazeWorldView.face_point(l["cell"], l["face"], MazeWorldView.RING_LIFT), map, frame, k)
		var key := MazeChain.key(l["cell"], l["face"])
		var again: int = seen.get(key, 0)
		if again > 0:
			p += Vector2(MazeLevel.FACE_STEP[l["face"]]) * again * STACK_STEP * bead_r
		seen[key] = again + 1
		pts.append(p)
		kinds.append(l["kind"])
	pts.append(_to_map(_centre(level.finish), map, frame, k))
	kinds.append(END)
	var door := Rect2()
	if not mini:
		door = Rect2(_to_map(Vector2(level.finish) * TILE, map, frame, k), Vector2(TILE, TILE) * k)
	return {
		"box": box, "style": style, "scale": k, "map": map, "inner": inner, "points": pts, "kinds": kinds,
		"n": drawn, "bead_r": bead_r, "thread_w": thread_w, "knot_r": knot_r,
		"ghost": [] if mini else _ghost(level, map, frame, k), "door": door, "more": links.size() - drawn,
	}


## number of links that are drawn
static func drawn_count(links: Array) -> int:
	return mini(links.size(), MazeChain.MAX_LINKS)


## colours of a world; under is the colour the chain sits on (the level card button for MINI), transparent for the
## card and export, which sit on the world's own background (design 22.6.1)
static func colours(world: int, under: Color = Color(0, 0, 0, 0)) -> Dictionary:
	var pal := MazeWorlds.palette(world)
	var unders: Array[Color] = []
	if under.a > 0.0:
		unders.append(under)
	else:
		unders.append(pal["back_top"])
		unders.append(pal["back_bottom"])
	var thread: Color = WhiteTheme.DIM
	for c: Color in [pal["door_frame"], pal["lip_lo"], WhiteTheme.DIM]:
		thread = c
		if _contrast_all(c, unders) >= MIN_CONTRAST:
			break
	return {
		"bg_top": pal["back_top"], "bg_bottom": pal["back_bottom"], "border": pal["back_line"],
		"ghost": pal["back_decor"], "thread": thread, "thread_under": MazeWorldView.RING_OUTLINE,
		"bead": MazeWorlds.RING, "bead_shade": MazeWorlds.RING.darkened(0.10), "outline": MazeWorldView.RING_OUTLINE,
		"clasp": pal["lip"], "clasp_hi": pal["lip_hi"], "clasp_lo": pal["lip_lo"],
	}


static func bead_step(n: int) -> float:
	return minf(BEAD_S_MAX, STRING_S_MAX / maxi(n, 1))


## seconds of the whole finish moment for n drawn links
static func duration(n: int) -> float:
	return T_IN + n * bead_step(n) + TAUT_S + END_S


## {"card_a", "link_k" (-1 before a link appears, else 0..1), "last_seg", "slack", "end_k", "done"}
static func anim_state(t: float, n: int) -> Dictionary:
	var step := bead_step(n)
	var t_taut := T_IN + n * step
	var t_end := t_taut + TAUT_S
	var ks := PackedFloat32Array()
	for i in n:
		var t0 := T_IN + i * step
		ks.append(-1.0 if t < t0 else clampf((t - t0) / step, 0.0, 1.0))
	return {
		"card_a": clampf(t / T_IN, 0.0, 1.0), "link_k": ks, "last_seg": t >= t_taut,
		"slack": 1.0 - smoothstep(t_taut, t_end, t), "end_k": clampf((t - t_end) / END_S, 0.0, 1.0),
		"done": t >= t_end + END_S,
	}


static func ease_out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func ease_out_back(x: float) -> float:
	var u := x - 1.0
	return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u


## draw primitives in painting order; clasp when rings used are at most par
static func shapes(lay: Dictionary, state: Dictionary, cols: Dictionary, clasp: bool, style: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mini := style == Style.MINI
	var pts: PackedVector2Array = lay["points"]
	var kinds: PackedInt32Array = lay["kinds"]
	var n: int = lay["n"]
	var bead_r: float = lay["bead_r"]
	var thread_w: float = lay["thread_w"]
	var knot_r: float = lay["knot_r"]
	var card_a: float = state["card_a"]
	var ks: PackedFloat32Array = state["link_k"]
	var thread: Color = cols["thread"]
	var under: Color = cols["thread_under"]
	if not mini:
		_background(out, lay, cols, style, card_a)
		for r: Rect2 in lay["ghost"]:
			out.append(MazeTileShapes.rect(r, _fade(cols["ghost"], card_a)))
		out.append(MazeTileShapes.rect(lay["door"], _fade(MazeWorlds.DOOR_LIGHT, DOOR_ALPHA * card_a)))
	# current points: links drop in from above
	var cur := pts.duplicate()
	for i in n:
		var k := ks[i]
		if k >= 0.0 and k < 1.0:
			cur[i + 1] -= Vector2(0, (1.0 - ease_out_cubic(k)) * DROP_K * bead_r)
	var end := pts[n + 1]
	var last_dir := _dir(cur[n], end)
	var shorten := bead_r * CLASP_LEN / 2.0 if (clasp and not mini) else 0.0
	var segments: Array[PackedVector2Array] = []
	for j in n + 1:
		var shown: bool = state["last_seg"] if j == n else ks[j] >= 0.0
		if not shown:
			continue
		var a := cur[j]
		var b := cur[j + 1]
		if j == n and shorten > 0.0:
			b -= last_dir * minf(shorten, a.distance_to(b) * 0.5)
		segments.append(_segment(a, b, float(state["slack"]), float(lay["inner"].size.y)))
	if not mini:
		for seg in segments:
			out.append(MazeTileShapes.polyline(seg, under, thread_w + 2.0))
	for seg in segments:
		out.append(MazeTileShapes.polyline(seg, thread, thread_w))
	# knots, beads, start
	for i in n:
		var k := ks[i]
		if k < 0.0 or kinds[i + 1] != MazeChain.Kind.KNOT:
			continue
		var a := minf(1.0, 2.0 * k)
		if mini:
			out.append(MazeTileShapes.circle(cur[i + 1], knot_r, _fade(thread, a)))
		else:
			_knot(out, cur[i + 1], knot_r, thread, under, a)
	for i in n:
		var k := ks[i]
		if k < 0.0 or kinds[i + 1] != MazeChain.Kind.BEAD:
			continue
		_bead(out, cur[i + 1], bead_r, cols, minf(1.0, 2.0 * k), mini)
	if not mini:
		_knot(out, pts[0], knot_r, thread, under, card_a)
		var tail := pts[0] + Vector2.from_angle(deg_to_rad(TAIL_DEG)) * 1.2 * bead_r
		out.append(MazeTileShapes.line(pts[0], tail, _fade(under, card_a), thread_w + 2.0))
		out.append(MazeTileShapes.line(pts[0], tail, _fade(thread, card_a), thread_w))
	# end
	var ek: float = state["end_k"]
	if mini:
		if clasp:
			out.append(MazeTileShapes.circle(end, 1.4 * bead_r + 1.0, cols["outline"]))
			out.append(MazeTileShapes.circle(end, 1.4 * bead_r, cols["clasp"]))
	elif ek > 0.0:
		if clasp:
			_clasp(out, end, last_dir, bead_r, cols, ek)
		else:
			_knot(out, end, 1.3 * knot_r, thread, under, ek)
	if int(lay["more"]) > 0 and state["last_seg"] and n > 0:
		out.append({
			"t": "text", "text": "+%d" % int(lay["more"]), "pos": cur[n] + Vector2(bead_r + 6.0, 6.0),
			"size": LABEL_SIZE, "col": thread,
		})
	return out


static func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


static func _to_map(p: Vector2, map: Rect2, frame: Rect2, k: float) -> Vector2:
	return map.position + (p - frame.position) * k


static func _contrast_all(c: Color, unders: Array[Color]) -> float:
	var lowest := INF
	for u in unders:
		lowest = minf(lowest, MazeArt.contrast(c, u))
	return lowest


static func _fade(c: Color, a: float) -> Color:
	return Color(c, c.a * a)


static func _dir(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


## one rectangle per horizontal run of solid cells (# and X) of a row
static func _ghost(level: MazeLevel, map: Rect2, frame: Rect2, k: float) -> Array:
	var out := []
	for y in level.height:
		var x := 0
		while x < level.width:
			if not level.solid(x, y):
				x += 1
				continue
			var x0 := x
			while x < level.width and level.solid(x, y):
				x += 1
			out.append(Rect2(_to_map(Vector2(x0, y) * TILE, map, frame, k), Vector2(x - x0, 1) * TILE * k))
	return out


## straight when taut, else a quadratic bezier that hangs down
static func _segment(a: Vector2, b: Vector2, slack: float, inner_h: float) -> PackedVector2Array:
	var sag := slack * minf(SAG_K * a.distance_to(b), SAG_MAX_K * inner_h)
	if sag <= 0.0:
		return PackedVector2Array([a, b])
	var ctrl := (a + b) / 2.0 + Vector2(0, 2.0 * sag)
	var out := PackedVector2Array()
	for i in SAG_POINTS:
		var t := float(i) / (SAG_POINTS - 1)
		out.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return out


static func _background(out: Array[Dictionary], lay: Dictionary, cols: Dictionary, style: int, card_a: float) -> void:
	var box: Rect2 = lay.get("canvas", lay["box"]) # export: the whole image, the chain sits in a smaller box
	var top: Color = _fade(cols["bg_top"], card_a)
	var bottom: Color = _fade(cols["bg_bottom"], card_a)
	var pts := PackedVector2Array()
	if style == Style.CARD:
		pts = _round_rect(box.get_center(), box.size.x, box.size.y, CARD_RADIUS, 0.0, 1.0, CARD_CORNER_POINTS - 1)
		pts.remove_at(pts.size() - 1)
	else:
		pts = PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end,
				Vector2(box.position.x, box.end.y)])
	var colors := PackedColorArray()
	for p in pts:
		colors.append(top.lerp(bottom, clampf((p.y - box.position.y) / box.size.y, 0.0, 1.0)))
	out.append(MazeTileShapes.vpoly(pts, colors))
	if style == Style.CARD:
		var ring := _round_rect(box.get_center(), box.size.x, box.size.y, CARD_RADIUS, 0.0, 1.0, CARD_CORNER_POINTS - 1)
		out.append(MazeTileShapes.polyline(ring, _fade(cols["border"], card_a), BORDER_W))


static func _knot(out: Array[Dictionary], p: Vector2, r: float, thread: Color, under: Color, a: float) -> void:
	out.append(MazeTileShapes.circle(p, r + 1.2, _fade(under, a)))
	out.append(MazeTileShapes.circle(p, r, _fade(thread, a)))


static func _bead(out: Array[Dictionary], p: Vector2, r: float, cols: Dictionary, a: float, mini: bool) -> void:
	if mini:
		out.append(MazeTileShapes.circle(p, r + 1.0, cols["outline"]))
		out.append(MazeTileShapes.circle(p, r, cols["bead"]))
		return
	out.append(MazeTileShapes.circle(p, r + 1.5, _fade(cols["outline"], a)))
	out.append(MazeTileShapes.circle(p, r, _fade(cols["bead_shade"], a)))
	out.append(MazeTileShapes.circle(p + Vector2(-0.15, -0.15) * r, 0.82 * r, _fade(cols["bead"], a)))


## buckle: rounded frame, lit upper long side, pin; dir is the direction of the last thread segment
static func _clasp(out: Array[Dictionary], at: Vector2, dir: Vector2, bead_r: float, cols: Dictionary, k: float) -> void:
	var s := 0.6 + 0.4 * ease_out_back(k)
	var a := minf(1.0, 3.0 * k)
	var angle := dir.angle()
	var w := CLASP_LEN * bead_r
	var h := CLASP_WID * bead_r
	var frame := _round_rect(at, w, h, CLASP_RADIUS * bead_r, angle, s)
	out.append(MazeTileShapes.polyline(frame, _fade(cols["outline"], a), 6.5))
	out.append(MazeTileShapes.polyline(frame, _fade(cols["clasp"], a), 3.5))
	# lit side: the long side that faces up on screen, 1 px outwards
	var up := Vector2(sin(angle), -cos(angle))
	var side := -1.0 if up.y <= 0.0 else 1.0
	var inset := w / 2.0 - CLASP_RADIUS * bead_r
	var lit := PackedVector2Array([_local(at, Vector2(-inset, side * h / 2.0), angle, s),
			_local(at, Vector2(inset, side * h / 2.0), angle, s)])
	var out_n := Vector2(0, side).rotated(angle)
	out.append(MazeTileShapes.line(lit[0] + out_n, lit[1] + out_n, _fade(cols["clasp_hi"], a), 1.5))
	out.append(MazeTileShapes.line(_local(at, Vector2(0, -h / 2.0), angle, s), _local(at, Vector2(0, h / 2.0), angle, s),
			_fade(cols["clasp_lo"], a), 2.0))


static func _local(at: Vector2, p: Vector2, angle: float, s: float) -> Vector2:
	return at + p.rotated(angle) * s


## closed outline of a rounded rectangle, local x along angle; steps = segments per quarter circle
static func _round_rect(
	c: Vector2, w: float, h: float, radius: float, angle: float, s: float, steps: int = ARC_STEPS
) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cx := w / 2.0 - radius
	var cy := h / 2.0 - radius
	var corners := [Vector2(-cx, -cy), Vector2(cx, -cy), Vector2(cx, cy), Vector2(-cx, cy)]
	for q in 4:
		for i in steps + 1:
			var a := PI + (q + float(i) / steps) * PI / 2.0
			out.append(_local(c, corners[q] + Vector2(cos(a), sin(a)) * radius, angle, s))
	out.append(out[0])
	return out
