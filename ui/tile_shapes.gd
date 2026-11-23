class_name MazeTileShapes
extends RefCounted
## Primitives of the tiles layer, per chunk, in world px (design 21.12). Pure: no nodes, no state; the layer replays
## the lists. Types: poly, vpoly (vertex colours), line, polyline, circle.

const T := 40.0
const DOOR_POST := 5.0
const DOOR_LINTEL := 6.0
const DOOR_ALPHA_BOTTOM := 0.9
const DOOR_ALPHA_TOP := 0.15
# half extents of a motif, line widths included
const MOTIF_HALF := {
	"glyph": Vector2(10.5, 5.5), "moss": Vector2(9.0, 7.0), "crack": Vector2(4.0, 9.0), "crystal": Vector2(3.5, 4.0),
}


## primitives of chunk (cx, cy); cracks: Vector2i -> decor shapes of the crack items
static func chunk(level: MazeLevel, skin: Dictionary, cracks: Dictionary, cx: int, cy: int) -> Array[Dictionary]:
	var scoped := MazeSkin.in_scope(level, skin)
	if not scoped:
		MazeSkin.begin(level, skin)
	var out := _chunk(level, skin, cracks, cx, cy)
	if not scoped:
		MazeSkin.end()
	return out


static func _chunk(level: MazeLevel, skin: Dictionary, cracks: Dictionary, cx: int, cy: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := MazeStaticLayer.CHUNK
	var pal: Dictionary = skin["pal"]
	var cells: Array[Vector2i] = []
	for y in range(cy * n, mini((cy + 1) * n, level.height)):
		for x in range(cx * n, mini((cx + 1) * n, level.width)):
			cells.append(Vector2i(x, y))
	var inners := {}
	for c in cells:
		match level.cell(c.x, c.y):
			MazeLevel.Cell.SOLID:
				var inner := MazeSkin.outline(level, skin, c, true)
				inners[c] = inner
				# silhouette and inner polygon are one rectangle when nothing shows the contour
				if not _same_all(level, c):
					out.append(poly(MazeSkin.outline(level, skin, c, false), pal["contour"]))
				out.append(poly(inner, pal["mortar"]))
			MazeLevel.Cell.NO_RING:
				out.append(rect(Rect2(Vector2(c) * T, Vector2(T, T)), pal["contour"]))
	var seen := {}
	for c in cells:
		if level.cell(c.x, c.y) != MazeLevel.Cell.SOLID:
			continue
		var rect := MazeSkin.stone_of(level, skin, c)
		if not seen.has(rect.position):
			seen[rect.position] = true
			_stone(out, level, skin, rect)
	seen.clear()
	for c in cells:
		if level.cell(c.x, c.y) != MazeLevel.Cell.NO_RING:
			continue
		var slab := MazeSkin.slab_of(level, c)
		if not seen.has(slab.position):
			seen[slab.position] = true
			_slab(out, level, skin, slab)
	if level.slope_count > 0:
		for c in cells:
			if level.slope(c.x, c.y):
				out.append_array(slope(level, skin, c))
	for c in cells:
		if level.cell(c.x, c.y) == MazeLevel.Cell.SOLID:
			_block_detail(out, skin, cracks, c)
	for c in cells:
		if level.cell(c.x, c.y) == MazeLevel.Cell.SOLID:
			_trims(out, level, skin, c, inners[c])
	for c in cells:
		var o := Vector2(c) * T
		match level.cell(c.x, c.y):
			MazeLevel.Cell.SPIKE:
				_spikes(out, skin, o)
			MazeLevel.Cell.EMPTY:
				_tuft(out, level, skin, c.x, c.y)
		if c == level.finish:
			_door(out, pal, o)
	return out


const COURSE_GAP := 7.0
const COURSE_W := 1.6


## primitives of a slope tile: contour, roof, courses along the surface (design 23.9.1)
static func slope(level: MazeLevel, skin: Dictionary, cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kind := level.cell(cell.x, cell.y)
	var pal: Dictionary = skin["pal"]
	var o := Vector2(cell) * T
	var shape := PackedVector2Array()
	for v in MazeSlope.polygon(kind):
		shape.append(Vector2(v))
	var contour: Color = (pal["roof"] as Color).darkened(MazeSkin.CONTOUR_DARKEN)
	out.append(poly(_shifted(shape, o), contour))
	var inner := shape
	var centre := Vector2.ZERO
	for v in shape:
		centre += v / shape.size()
	for i in shape.size():
		var a := shape[i]
		var b := shape[(i + 1) % shape.size()]
		var d := _slope_edge_inset(level, cell, kind, a, b)
		if d > 0.0:
			inner = _clip_inside(inner, a, b, centre, d)
	if inner.size() < 3:
		return out
	out.append(poly(_shifted(inner, o), pal["roof"]))
	var sy := _surface_line(kind)
	var j := 1
	while j * COURSE_GAP < 2.0 * T:
		var shift := j * COURSE_GAP
		var course := PackedVector2Array(
			[Vector2(-1.0, sy.x - sy.y + shift), Vector2(T + 1.0, sy.x + sy.y * (T + 1.0) + shift)]
		)
		for piece in Geometry2D.intersect_polyline_with_polygon(course, inner):
			if piece.size() >= 2:
				out.append(line(piece[0] + o, piece[piece.size() - 1] + o, pal["roof_lo"], COURSE_W))
		j += 1
	return out


## local surface as y = c.x + c.y * x, in px
static func _surface_line(kind: int) -> Vector2:
	var y0 := MazeSlope.surface(kind, 0, 0) / 1000.0
	var y1 := MazeSlope.surface(kind, 0, MazeTuning.TILE) / 1000.0
	return Vector2(y0, (y1 - y0) / T)


static func _shifted(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out


## inset of a polygon edge: contour towards air and along the surface, seam against blocks, none inside a roof
static func _slope_edge_inset(level: MazeLevel, cell: Vector2i, kind: int, a: Vector2, b: Vector2) -> float:
	if absf(a.x - b.x) > 0.001:
		return MazeSkin.SEAM_W if absf(a.y - b.y) < 0.001 else MazeSkin.CONTOUR_W
	var dir := 1 if a.x > 20.0 else -1
	var n := cell + Vector2i(dir, 0)
	if n.x < 0 or n.x >= level.width:
		return 0.0
	var other := level.cell(n.x, n.y)
	if other == MazeLevel.Cell.EMPTY or other == MazeLevel.Cell.SPIKE:
		return MazeSkin.CONTOUR_W
	if MazeSlope.is_slope(other):
		var pair := _roof_pair(kind, other)
		return 0.0 if pair else MazeSkin.SEAM_W
	return MazeSkin.SEAM_W


static func _roof_pair(a: int, b: int) -> bool:
	var lo := MazeLevel.Cell.GENTLE_R_LO
	var hi := MazeLevel.Cell.GENTLE_R_HI
	if (a == lo and b == hi) or (a == hi and b == lo):
		return true
	lo = MazeLevel.Cell.GENTLE_L_LO
	hi = MazeLevel.Cell.GENTLE_L_HI
	return (a == lo and b == hi) or (a == hi and b == lo)


## polygon part at least d px inside the edge a-b (centre is on the inner side)
static func _clip_inside(
	pts: PackedVector2Array, a: Vector2, b: Vector2, centre: Vector2, d: float
) -> PackedVector2Array:
	var n := (b - a).orthogonal().normalized()
	if (centre - a).dot(n) < 0.0:
		n = -n
	var out := PackedVector2Array()
	var count := pts.size()
	for i in count:
		var p := pts[i]
		var q := pts[(i + 1) % count]
		var dp := (p - a).dot(n) - d
		var dq := (q - a).dot(n) - d
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p + (q - p) * (dp / (dp - dq)))
	return out


static func _same_all(level: MazeLevel, cell: Vector2i) -> bool:
	for f in 4:
		if MazeSkin.side(level, cell, f) != MazeSkin.Side.SAME:
			return false
	return true


## stone with a bevel: dark base, light top and left, face colour inside (21.6.2)
static func _stone(out: Array[Dictionary], level: MazeLevel, skin: Dictionary, rect: Rect2i) -> void:
	var pal: Dictionary = skin["pal"]
	var o := MazeSkin.stone_outline(level, skin, rect)
	if o.size() < 3:
		return
	var b: float = skin["stones"]["bevel"]
	out.append(poly(o, pal["block_lo"]))
	var shifted := PackedVector2Array()
	for p in o:
		shifted.append(p - Vector2(b, b))
	for pg in Geometry2D.intersect_polygons(o, shifted):
		_add_poly(out, pg, pal["block_hi"])
	var v := MazeArt.pick(rect.position.x, rect.position.y, MazeSkin.SALT_SHADE, 5) - 2
	var towards: Color = pal["block_hi"] if v > 0 else pal["block_lo"]
	var face: Color = (pal["block"] as Color).lerp(towards, absf(v) * float(skin["stones"]["shade"]))
	for pg in Geometry2D.offset_polygon(o, -b):
		_add_poly(out, pg, face)
	_motif(out, level, skin, rect)


## at most one motif per stone, inside an area that keeps clear of trims, chamfers and bevels (21.6.3)
static func _motif(out: Array[Dictionary], level: MazeLevel, skin: Dictionary, rect: Rect2i) -> void:
	var anchor := rect.position
	var pick := -1
	var motifs: Array = skin["motifs"]
	for i in motifs.size():
		if MazeArt.chance(anchor.x, anchor.y, MazeSkin.SALT_MOTIF + i, motifs[i]["chance"]):
			pick = i
			break
	if pick < 0:
		return
	var st: Dictionary = skin["stones"]
	var plain := maxf(st["chamfer"], st["bevel"]) + MazeSkin.MOTIF_MARGIN
	var area := Rect2(Vector2(rect.position) * T, Vector2(rect.size) * T)
	var margins := {}
	for f in 4:
		var lip := false
		for c in MazeSkin._side_cells(rect, f):
			lip = lip or MazeSkin.rim_face(level, c, f)
		var m := plain
		if lip:
			m = MazeSkin.CONTOUR_W + _trim_w(f) + MazeSkin.TRIM_SHADOW_W + MazeSkin.MOTIF_MARGIN
		margins[f] = m
	var lo := area.position + Vector2(margins[MazeLevel.Face.LEFT], margins[MazeLevel.Face.UP])
	var hi := area.end - Vector2(margins[MazeLevel.Face.RIGHT], margins[MazeLevel.Face.DOWN])
	var kind: String = motifs[pick]["kind"]
	var half: Vector2 = MOTIF_HALF[kind]
	if hi.x - lo.x < 12.0 or hi.y - lo.y < 12.0:
		return
	var span := (hi - lo) - half * 2.0
	if span.x < 0.0 or span.y < 0.0:
		return
	var salt := MazeSkin.SALT_MOTIF_POS + pick * 3
	var jx := MazeArt.pick(anchor.x, anchor.y, salt, int(span.x) + 1)
	var jy := MazeArt.pick(anchor.x, anchor.y, salt + 1, int(span.y) + 1)
	var c := lo + half + Vector2(jx, jy)
	var pal: Dictionary = skin["pal"]
	match kind:
		"glyph":
			var ring := PackedVector2Array()
			for i in 13:
				ring.append(c + Vector2.from_angle(TAU * i / 12.0) * 4.5)
			out.append(polyline(ring, pal["joint"], 2.0))
			out.append(line(c + Vector2(-9.5, 0), c + Vector2(-6.5, 0), pal["joint"], 2.0))
			out.append(line(c + Vector2(6.5, 0), c + Vector2(9.5, 0), pal["joint"], 2.0))
		"moss":
			var col := Color(pal["motif"], 0.85)
			out.append(poly(_ellipse(c, 9.0, 4.5), col))
			out.append(poly(_ellipse(c + Vector2(5.0, -2.5), 4.0, 6.0), col))
		"crack":
			var x := c.x + MazeArt.pick(anchor.x, anchor.y, salt + 2, 3) - 1.0
			var pts := PackedVector2Array()
			for i in 4:
				pts.append(Vector2(x, c.y - 8.0 + i * 5.33))
				x = clampf(x + MazeArt.pick(anchor.x + i, anchor.y, salt + 2, 5) - 2.0, c.x - 3.0, c.x + 3.0)
			out.append(polyline(pts, pal["joint"], 2.0))
		"crystal":
			var hexa := PackedVector2Array()
			for i in 6:
				hexa.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 2.0) * 4.0)
			out.append(poly(hexa, pal["block_hi"]))


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _add_poly(out: Array[Dictionary], pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3:
		out.append(poly(pts, col))


static func rect(r: Rect2, col: Color) -> Dictionary:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	return {"t": "poly", "pts": pts, "col": col}


static func poly(pts: PackedVector2Array, col: Color) -> Dictionary:
	return {"t": "poly", "pts": pts, "col": col}


static func vpoly(pts: PackedVector2Array, cols: PackedColorArray) -> Dictionary:
	return {"t": "vpoly", "pts": pts, "cols": cols}


static func line(a: Vector2, b: Vector2, col: Color, w: float) -> Dictionary:
	return {"t": "line", "pts": PackedVector2Array([a, b]), "col": col, "w": w}


static func polyline(pts: PackedVector2Array, col: Color, w: float) -> Dictionary:
	return {"t": "polyline", "pts": pts, "col": col, "w": w}


static func circle(c: Vector2, r: float, col: Color) -> Dictionary:
	return {"t": "circle", "c": c, "r": r, "col": col}


static func _block_detail(out: Array[Dictionary], skin: Dictionary, cracks: Dictionary, cell: Vector2i) -> void:
	out.append_array(MazeDecor.speck_shapes(cell.x, cell.y, skin["pal"]))
	if cracks.has(cell):
		out.append_array(cracks[cell])


static func _tuft(out: Array[Dictionary], level: MazeLevel, skin: Dictionary, x: int, y: int) -> void:
	var here := Vector2i(x, y)
	if not skin["tufts"] or here == level.spawn or here == level.finish:
		return
	if MazeStaticLayer.lip_drawn(level, Vector2i(x, y + 1), MazeLevel.Face.UP):
		out.append_array(MazeDecor.tuft_shapes(x, y, skin["pal"]))


## X slab: gradient fill with sheen bands, edge line and a lit top line (21.7)
static func _slab(out: Array[Dictionary], level: MazeLevel, skin: Dictionary, rect: Rect2i) -> void:
	var pal: Dictionary = skin["pal"]
	var o := MazeSkin.slab_outline(level, skin, rect)
	if o.size() < 3:
		return
	var column := rect.size.x == 1 and rect.size.y > 1 # light runs left to right, else top to bottom
	var box := Rect2(o[0], Vector2.ZERO)
	for p in o:
		box = box.expand(p)
	var short := box.size.x if column else box.size.y
	var lit := box.position.x if column else box.position.y
	var length := box.size.y if column else box.size.x
	var along0 := box.position.y if column else box.position.x
	# fill in two strips so the vertex colours are exact on both sides of the bright edge
	var split := 0.18
	var cuts := [lit - 1.0, lit + split * short, lit + short + 1.0]
	for k in 2:
		var span: float = cuts[k + 1] - cuts[k]
		var strip := Rect2(box.position.x - 1.0, cuts[k], box.size.x + 2.0, span)
		if column:
			strip = Rect2(cuts[k], box.position.y - 1.0, span, box.size.y + 2.0)
		for pg in Geometry2D.intersect_polygons(o, _rect_pts(strip)):
			if pg.size() < 3:
				continue
			var cols := PackedColorArray()
			for p in pg:
				var t := ((p.x if column else p.y) - lit) / short
				cols.append(_slab_colour(pal, t, split))
			out.append(vpoly(pg, cols))
	var anchor := rect.position
	var phase := MazeArt.pick(anchor.x, anchor.y, MazeSkin.SALT_SLAB, 19)
	var lean := 0.7 * short
	var wide := Color(pal["sheen"], MazeSkin.SHEEN_ALPHAS[0])
	var thin := Color(pal["sheen"], MazeSkin.SHEEN_ALPHAS[1])
	# sheen stays below the top line, so no pixel gets more sheen than the palette check allows (C3)
	var zone := Rect2(box.position.x - 1.0, lit + 4.0, box.size.x + 2.0, short)
	if column:
		zone = Rect2(lit + 4.0, box.position.y - 1.0, short, box.size.y + 2.0)
	var clip := PackedVector2Array()
	for pg in Geometry2D.intersect_polygons(o, _rect_pts(zone)):
		clip = pg
	var p := 19.0 + phase
	while p < length + 20.0 and clip.size() >= 3:
		for band: Array in [[wide, 8.0, 0.0], [thin, 2.0, 11.0]]:
			var a: float = along0 + p + band[2]
			var w: float = band[1]
			var quad := PackedVector2Array()
			var far := lit + short
			# the band leans: its far end sits `lean` back along the long axis
			var back := a - lean
			var back_w := a + w - lean
			if column:
				quad.append_array([Vector2(lit, a), Vector2(lit, a + w), Vector2(far, back_w), Vector2(far, back)])
			else:
				quad.append_array([Vector2(a, lit), Vector2(a + w, lit), Vector2(back_w, far), Vector2(back, far)])
			for pg in Geometry2D.intersect_polygons(quad, clip):
				_add_poly(out, pg, band[0])
		p += 38.0
	var edge := PackedVector2Array()
	for pg in Geometry2D.offset_polygon(o, -1.5):
		edge = pg
		edge.append(pg[0])
		out.append(polyline(edge, pal["noring_edge"], 2.0))
	var r := MazeSkin.SLAB_RADIUS + 1.0
	if length > 2.0 * r:
		var top := Color(pal["sheen"], MazeSkin.SHEEN_ALPHAS[2])
		if column:
			out.append(line(Vector2(lit + 3.0, along0 + r), Vector2(lit + 3.0, along0 + length - r), top, 2.0))
		else:
			out.append(line(Vector2(along0 + r, lit + 3.0), Vector2(along0 + length - r, lit + 3.0), top, 2.0))


static func _slab_colour(pal: Dictionary, t: float, split: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < split:
		return (pal["noring_hi"] as Color).lerp(pal["noring"], t / split)
	return (pal["noring"] as Color).lerp(pal["noring_lo"], (t - split) / (1.0 - split))


static func _rect_pts(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## spike outline points of a shape (design 18.5), base left to base right
static func spike_points(shape: String, x: float, o_y: float) -> PackedVector2Array:
	var b := o_y + T
	match shape:
		"thorn":
			return PackedVector2Array(
				[
					Vector2(x + 1, b), Vector2(x + 6, o_y + 30), Vector2(x + 11, o_y + 20), Vector2(x + 14, o_y + 30),
					Vector2(x + 19, b),
				]
			)
		"crystal":
			return PackedVector2Array(
				[
					Vector2(x + 1, b), Vector2(x + 4, o_y + 27), Vector2(x + 8, o_y + 20), Vector2(x + 12, o_y + 20),
					Vector2(x + 16, o_y + 27), Vector2(x + 19, b),
				]
			)
	return PackedVector2Array([Vector2(x + 1, b), Vector2(x + T / 4.0, o_y + T / 2.0), Vector2(x + 19, b)])


## two pins per cell: dark outline, red fill, shaded right half, light left edge, dark base; colours are shared by all
## worlds, only the outline shape comes from the pack
static func _spikes(out: Array[Dictionary], skin: Dictionary, o: Vector2) -> void:
	for i in 2:
		var x := o.x + i * T / 2.0
		var b := o.y + T
		var pts := spike_points(skin["spikes"], x, o.y)
		out.append(poly(pts, MazeWorlds.HAZARD_LINE))
		var fill := _inset(pts, 1.5)
		out.append(poly(fill, MazeWorlds.HAZARD))
		var apex := pts[0]
		for p in pts:
			apex = p if p.y < apex.y else apex
		var tops := PackedFloat32Array()
		for p in pts:
			if is_equal_approx(p.y, apex.y):
				tops.append(p.x)
		var mid_x := (tops[0] + tops[-1]) / 2.0
		var half := Rect2(Vector2(mid_x, o.y), Vector2(x + 20.0 - mid_x, T))
		for pg in Geometry2D.intersect_polygons(fill, _rect_pts(half)):
			_add_poly(out, pg, Color(MazeWorlds.HAZARD_DARK, 0.45))
		out.append(polyline(fill.slice(0, fill.size() / 2 + 1), MazeWorlds.HAZARD_HI, 2.0))
		out.append(rect(Rect2(Vector2(x + 1, b - 3), Vector2(18, 3)), MazeWorlds.HAZARD_DARK))


## closed polygon moved inwards by d at every corner (mitre), same vertex count
static func _inset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := pts.size()
	var area := 0.0
	for i in n:
		area += pts[i].cross(pts[(i + 1) % n])
	var sign := 1.0 if area > 0.0 else -1.0 # screen coordinates: area > 0 runs clockwise on screen
	var out := PackedVector2Array()
	for i in n:
		var a := pts[(i + n - 1) % n]
		var v := pts[i]
		var c := pts[(i + 1) % n]
		var d1 := (v - a).normalized()
		var d2 := (c - v).normalized()
		var n1 := Vector2(-d1.y, d1.x) * sign
		var n2 := Vector2(-d2.y, d2.x) * sign
		out.append(v + (n1 + n2) / (1.0 + n1.dot(n2)) * d)
	return out


static func _door(out: Array[Dictionary], pal: Dictionary, o: Vector2) -> void:
	var inner := Rect2(o + Vector2(DOOR_POST, DOOR_LINTEL), Vector2(T - 2.0 * DOOR_POST, T - DOOR_LINTEL))
	var top := Color(MazeWorlds.DOOR_LIGHT, DOOR_ALPHA_TOP)
	var bottom := Color(MazeWorlds.DOOR_LIGHT, DOOR_ALPHA_BOTTOM)
	var corners := PackedVector2Array(
		[inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	)
	out.append(vpoly(corners, PackedColorArray([top, top, bottom, bottom])))
	var frame: Color = pal["door_frame"]
	out.append(rect(Rect2(o, Vector2(DOOR_POST, T)), frame))
	out.append(rect(Rect2(o + Vector2(T - DOOR_POST, 0), Vector2(DOOR_POST, T)), frame))
	out.append(rect(Rect2(o, Vector2(T, DOOR_LINTEL)), frame))
	var contour := PackedVector2Array([Vector2(5, T - 1), Vector2(5, 6), Vector2(35, 6), Vector2(35, T - 1)])
	for i in contour.size():
		contour[i] += o
	out.append(polyline(contour, pal["contour"], 2.0))


static func _trim_w(face: int) -> float:
	return MazeSkin.TRIM_UP if face == MazeLevel.Face.UP else MazeSkin.TRIM_SIDE


## the four bands of every ring face of a cell, then the inner corner joints (21.8); shadows first, then lip and
## stripes, so two trims meeting at a corner join like a moulding
static func _trims(
	out: Array[Dictionary], level: MazeLevel, skin: Dictionary, cell: Vector2i, inner := PackedVector2Array()
) -> void:
	var pal: Dictionary = skin["pal"]
	var faces: Array[int] = []
	for face in 4:
		if MazeSkin.rim_face(level, cell, face):
			faces.append(face)
	var joints := joint_corners(level, cell)
	if faces.is_empty() and joints.is_empty():
		return
	if inner.is_empty():
		inner = MazeSkin.outline(level, skin, cell, true)
	var lines := {}
	for f in faces:
		lines[f] = _face_line(level, skin, cell, f)
	var c := MazeSkin.CONTOUR_W
	var shadow := Color(pal["contour"], MazeSkin.TRIM_SHADOW_ALPHA)
	for ci in joints:
		_joint(out, cell, skin, ci, true)
	for f in faces:
		var w := _trim_w(f)
		_band(out, lines[f], f, inner, c + w, c + w + MazeSkin.TRIM_SHADOW_W, shadow)
	for ci in joints:
		_joint(out, cell, skin, ci, false)
	for f in faces:
		_band(out, lines[f], f, inner, c - 0.5, c + _trim_w(f), pal["lip"])
	for f in faces:
		_band(out, lines[f], f, inner, c, c + MazeSkin.TRIM_HI_W, pal["lip_hi"])
	for f in faces:
		var w := _trim_w(f)
		_band(out, lines[f], f, inner, c + w - MazeSkin.TRIM_LO_W, c + w, pal["lip_lo"])


## the six edge vertices of a face with their offsets, ends extended by 1 px
static func _face_line(level: MazeLevel, skin: Dictionary, cell: Vector2i, face: int) -> PackedVector2Array:
	var inward := Vector2(MazeSkin.INWARD[face])
	var along := Vector2(MazeSkin.ALONG[face])
	var line := PackedVector2Array()
	for i in 6:
		var v := Vector2(MazeSkin.vertex(cell, face, i)) + inward * MazeSkin.rim_d(level, skin, cell, face, i)
		if i == 0:
			v -= along
		elif i == 5:
			v += along
		line.append(v)
	return line


## band between depths d0 and d1 along a face line, cut to the cell's inner polygon
static func _band(
	out: Array[Dictionary], line: PackedVector2Array, face: int, inner: PackedVector2Array, d0: float, d1: float,
	col: Color
) -> void:
	var inward := Vector2(MazeSkin.INWARD[face])
	var near := PackedVector2Array()
	var far := PackedVector2Array()
	for v in line:
		near.append(v + inward * d0)
		far.append(v + inward * d1)
	far.reverse()
	near.append_array(far)
	if inner.size() == 4 and _straight(line, face):
		# straight face in a rectangular cell: the cut is a rectangle intersection
		var box := Rect2(near[0], Vector2.ZERO)
		for p in near:
			box = box.expand(p)
		var cut := box.intersection(Rect2(inner[0], inner[2] - inner[0]))
		if cut.has_area():
			out.append(poly(_rect_pts(cut), col))
		return
	for pg in Geometry2D.intersect_polygons(near, inner):
		_add_poly(out, pg, col)


## all vertices on one line (the two extended ends are on it too)
static func _straight(line: PackedVector2Array, face: int) -> bool:
	var axis := 1 if face == MazeLevel.Face.UP or face == MazeLevel.Face.DOWN else 0
	for v in line:
		if not is_equal_approx(v[axis], line[0][axis]):
			return false
	return true


## corners where a floor runs into a wall: both trims continue into the cell and meet like a moulding
static func joint_corners(level: MazeLevel, cell: Vector2i) -> Array[int]:
	var found: Array[int] = []
	if level.cell(cell.x, cell.y) != MazeLevel.Cell.SOLID:
		return found
	for ci in 4:
		var p: int = MazeSkin.CORNER_P[ci]
		var q: int = MazeSkin.CORNER_Q[ci]
		if MazeSkin.side(level, cell, p) != MazeSkin.Side.SAME or MazeSkin.side(level, cell, q) != MazeSkin.Side.SAME:
			continue
		var diag: Vector2i = cell + MazeLevel.FACE_STEP[p] + MazeLevel.FACE_STEP[q]
		if diag.x < 0 or diag.y < 0 or diag.x >= level.width or diag.y >= level.height:
			continue
		if level.cell(diag.x, diag.y) != MazeLevel.Cell.EMPTY:
			continue
		var np: Vector2i = cell + MazeLevel.FACE_STEP[p]
		var nq: Vector2i = cell + MazeLevel.FACE_STEP[q]
		if MazeSkin.rim_face(level, np, q) and MazeSkin.rim_face(level, nq, p):
			found.append(ci)
	return found


static func _joint(out: Array[Dictionary], cell: Vector2i, skin: Dictionary, ci: int, shadows: bool) -> void:
	var pal: Dictionary = skin["pal"]
	var p: int = MazeSkin.CORNER_P[ci]
	var q: int = MazeSkin.CORNER_Q[ci]
	var k := Vector2((cell + MazeSkin.CORNER_POS[ci]) * MazeSkin.T)
	var ep := Vector2(MazeSkin.INWARD[p])
	var eq := Vector2(MazeSkin.INWARD[q])
	var c := MazeSkin.CONTOUR_W
	var wp := c + _trim_w(p)
	var wq := c + _trim_w(q)
	var sh := MazeSkin.TRIM_SHADOW_W
	var shadow := Color(pal["contour"], MazeSkin.TRIM_SHADOW_ALPHA)
	if shadows:
		out.append(_frame_rect(k, ep, eq, 0.0, wp, wq, wq + sh, shadow))
		out.append(_frame_rect(k, ep, eq, wp, wp + sh, 0.0, wq + sh, shadow))
		return
	out.append(_frame_rect(k, ep, eq, 0.0, wp, c, wq, pal["lip"]))
	out.append(_frame_rect(k, ep, eq, c, wp, 0.0, wq, pal["lip"]))


## rectangle p0..p1 along ep and q0..q1 along eq from corner k
static func _frame_rect(
	k: Vector2, ep: Vector2, eq: Vector2, p0: float, p1: float, q0: float, q1: float, col: Color
) -> Dictionary:
	var pts := PackedVector2Array(
		[k + ep * p0 + eq * q0, k + ep * p1 + eq * q0, k + ep * p1 + eq * q1, k + ep * p0 + eq * q1]
	)
	return poly(pts, col)
