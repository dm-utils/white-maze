class_name MazeTileShapes
extends RefCounted
## Primitives of the tiles layer, per chunk, in world px (design 21.12). Pure: no nodes, no state; the layer replays
## the lists. Types: poly, vpoly (vertex colours), line, polyline, circle.

const T := 40.0
const EDGE_W := 2.0
const SHEEN_W := 3.0
const SHEEN_ALPHA := 0.5
const SHEEN_STEPS := [0, 2, 1] # distinct slots out of four
const DOOR_POST := 5.0
const DOOR_LINTEL := 6.0
const DOOR_ALPHA_BOTTOM := 0.9
const DOOR_ALPHA_TOP := 0.15
const SALT_SHEEN := 5
const SALT_SHEEN_N := 6


## primitives of chunk (cx, cy); cracks: Vector2i -> decor shapes of the crack items
static func chunk(level: MazeLevel, skin: Dictionary, cracks: Dictionary, cx: int, cy: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := MazeStaticLayer.CHUNK
	var pal: Dictionary = skin["pal"]
	var cells: Array[Vector2i] = []
	for y in range(cy * n, mini((cy + 1) * n, level.height)):
		for x in range(cx * n, mini((cx + 1) * n, level.width)):
			cells.append(Vector2i(x, y))
	for c in cells:
		if level.cell(c.x, c.y) == MazeLevel.Cell.SOLID:
			out.append(poly(MazeSkin.outline(level, skin, c, false), pal["contour"]))
			out.append(poly(MazeSkin.outline(level, skin, c, true), pal["mortar"]))
	var seen := {}
	for c in cells:
		if level.cell(c.x, c.y) != MazeLevel.Cell.SOLID:
			continue
		var rect := MazeSkin.stone_of(level, skin, c)
		if not seen.has(rect.position):
			seen[rect.position] = true
			_stone(out, level, skin, rect)
	for c in cells:
		if level.cell(c.x, c.y) == MazeLevel.Cell.SOLID:
			_block_detail(out, skin, cracks, c)
	for c in cells:
		if level.cell(c.x, c.y) == MazeLevel.Cell.SOLID:
			_trims(out, level, skin, c)
	for c in cells:
		var o := Vector2(c) * T
		match level.cell(c.x, c.y):
			MazeLevel.Cell.NO_RING:
				_no_ring(out, pal, c.x, c.y, o)
			MazeLevel.Cell.SPIKE:
				_spikes(out, skin, o)
			MazeLevel.Cell.EMPTY:
				_tuft(out, level, skin, c.x, c.y)
		if c == level.finish:
			_door(out, pal, o)
	return out


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


static func _no_ring(out: Array[Dictionary], pal: Dictionary, x: int, y: int, o: Vector2) -> void:
	out.append(rect(Rect2(o, Vector2(T, T)), pal["noring"]))
	var edge: Color = pal["noring_edge"]
	out.append(rect(Rect2(o, Vector2(T, EDGE_W)), edge))
	out.append(rect(Rect2(o + Vector2(0, T - EDGE_W), Vector2(T, EDGE_W)), edge))
	out.append(rect(Rect2(o, Vector2(EDGE_W, T)), edge))
	out.append(rect(Rect2(o + Vector2(T - EDGE_W, 0), Vector2(EDGE_W, T)), edge))
	var sheen := Color(pal["sheen"], SHEEN_ALPHA)
	var base := MazeArt.pick(x, y, SALT_SHEEN, 4)
	var n := 2 + MazeArt.pick(x, y, SALT_SHEEN_N, 2)
	for i in n:
		var sx: float = 4.0 + 8.0 * ((base + int(SHEEN_STEPS[i])) % 4)
		out.append(line(o + Vector2(sx, 35), o + Vector2(sx + 8, 6), sheen, SHEEN_W))


## same colours in every world; only the outline of a spike changes (design 18.5)
static func _spikes(out: Array[Dictionary], skin: Dictionary, o: Vector2) -> void:
	for i in 2:
		var x := o.x + i * T / 2.0
		var b := o.y + T
		var pts := PackedVector2Array()
		match skin["spikes"]:
			"thorn":
				pts = PackedVector2Array(
					[
						Vector2(x + 1, b), Vector2(x + 6, o.y + 30), Vector2(x + 11, o.y + 20),
						Vector2(x + 14, o.y + 30), Vector2(x + 19, b),
					]
				)
			"crystal":
				pts = PackedVector2Array(
					[
						Vector2(x + 1, b), Vector2(x + 4, o.y + 27), Vector2(x + 8, o.y + 20),
						Vector2(x + 12, o.y + 20), Vector2(x + 16, o.y + 27), Vector2(x + 19, b),
					]
				)
			_:
				pts = PackedVector2Array([Vector2(x + 1, b), Vector2(x + T / 4.0, o.y + T / 2.0), Vector2(x + 19, b)])
		out.append(poly(pts, MazeWorlds.HAZARD))
		out.append(polyline(pts.slice(0, pts.size() / 2 + 1), MazeWorlds.HAZARD_HI, 2.0))
		out.append(rect(Rect2(Vector2(x + 1, b - 3), Vector2(18, 3)), MazeWorlds.HAZARD_DARK))


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


static func _trim_w(face: int) -> float:
	return MazeSkin.TRIM_UP if face == MazeLevel.Face.UP else MazeSkin.TRIM_SIDE


## the four bands of every ring face of a cell, then the inner corner joints (21.8); shadows first, then lip and
## stripes, so two trims meeting at a corner join like a moulding
static func _trims(out: Array[Dictionary], level: MazeLevel, skin: Dictionary, cell: Vector2i) -> void:
	var pal: Dictionary = skin["pal"]
	var faces: Array[int] = []
	for face in 4:
		if MazeSkin.rim_face(level, cell, face):
			faces.append(face)
	var joints := joint_corners(level, cell)
	if faces.is_empty() and joints.is_empty():
		return
	var inner := MazeSkin.outline(level, skin, cell, true)
	var c := MazeSkin.CONTOUR_W
	var shadow := Color(pal["contour"], MazeSkin.TRIM_SHADOW_ALPHA)
	for ci in joints:
		_joint(out, level, skin, cell, ci, true)
	for f in faces:
		var w := _trim_w(f)
		_band(out, level, skin, cell, f, inner, c + w, c + w + MazeSkin.TRIM_SHADOW_W, shadow)
	for ci in joints:
		_joint(out, level, skin, cell, ci, false)
	for f in faces:
		_band(out, level, skin, cell, f, inner, c - 0.5, c + _trim_w(f), pal["lip"])
	for f in faces:
		_band(out, level, skin, cell, f, inner, c, c + MazeSkin.TRIM_HI_W, pal["lip_hi"])
	for f in faces:
		var w := _trim_w(f)
		_band(out, level, skin, cell, f, inner, c + w - MazeSkin.TRIM_LO_W, c + w, pal["lip_lo"])


## band between depths d0 and d1 along a face, following the edge offsets, cut to the cell's inner polygon
static func _band(
	out: Array[Dictionary], level: MazeLevel, skin: Dictionary, cell: Vector2i, face: int,
	inner: PackedVector2Array, d0: float, d1: float, col: Color
) -> void:
	var inward := Vector2(MazeSkin.INWARD[face])
	var along := Vector2(MazeSkin.ALONG[face])
	var near := PackedVector2Array()
	var far := PackedVector2Array()
	for i in 6:
		var v := Vector2(MazeSkin.vertex(cell, face, i))
		var d := MazeSkin.rim_d(level, skin, cell, face, i)
		if i == 0:
			v -= along
		elif i == 5:
			v += along
		near.append(v + inward * (d + d0))
		far.append(v + inward * (d + d1))
	far.reverse()
	near.append_array(far)
	for pg in Geometry2D.intersect_polygons(near, inner):
		_add_poly(out, pg, col)


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


static func _joint(
	out: Array[Dictionary], level: MazeLevel, skin: Dictionary, cell: Vector2i, ci: int, shadows: bool
) -> void:
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
