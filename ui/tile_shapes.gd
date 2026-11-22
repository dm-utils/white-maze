class_name MazeTileShapes
extends RefCounted
## Primitives of the tiles layer, per chunk, in world px (design 21.12). Pure: no nodes, no state; the layer replays
## the lists. Types: poly, vpoly (vertex colours), line, polyline, circle.

const T := 40.0
const LIP := 5.0
const JOINT_W := 2.0
const EDGE_W := 2.0
const SHEEN_W := 3.0
const SHEEN_ALPHA := 0.5
const SHEEN_STEPS := [0, 2, 1] # distinct slots out of four
const DOOR_POST := 5.0
const DOOR_LINTEL := 6.0
const DOOR_ALPHA_BOTTOM := 0.9
const DOOR_ALPHA_TOP := 0.15
const SALT_JOINT := 1
const SALT_JOINT_H := 2
const SALT_CRACK := 3
const SALT_CRACK_PT := 4
const SALT_SHEEN := 5
const SALT_SHEEN_N := 6


## primitives of chunk (cx, cy); cracks: Vector2i -> decor shapes of the crack items
static func chunk(level: MazeLevel, skin: Dictionary, cracks: Dictionary, cx: int, cy: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := MazeStaticLayer.CHUNK
	var pal: Dictionary = skin["pal"]
	for y in range(cy * n, mini((cy + 1) * n, level.height)):
		for x in range(cx * n, mini((cx + 1) * n, level.width)):
			var o := Vector2(x, y) * T
			match level.cell(x, y):
				MazeLevel.Cell.SOLID:
					_block(out, level, skin, cracks, x, y, o)
				MazeLevel.Cell.NO_RING:
					_no_ring(out, pal, x, y, o)
				MazeLevel.Cell.SPIKE:
					_spikes(out, skin, o)
				MazeLevel.Cell.EMPTY:
					_tuft(out, level, skin, x, y)
			if Vector2i(x, y) == level.finish:
				_door(out, pal, o)
	return out


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


static func _block(
	out: Array[Dictionary], level: MazeLevel, skin: Dictionary, cracks: Dictionary, x: int, y: int, o: Vector2
) -> void:
	var pal: Dictionary = skin["pal"]
	out.append(rect(Rect2(o, Vector2(T, T)), pal["block"]))
	_joints(out, skin, x, y, o)
	out.append_array(MazeDecor.speck_shapes(x, y, pal))
	if cracks.has(Vector2i(x, y)):
		out.append_array(cracks[Vector2i(x, y)])
	var lip: Color = pal["lip"]
	var cell := Vector2i(x, y)
	if MazeStaticLayer.lip_drawn(level, cell, MazeLevel.Face.UP):
		out.append(rect(Rect2(o, Vector2(T, LIP)), lip))
	if MazeStaticLayer.lip_drawn(level, cell, MazeLevel.Face.DOWN):
		out.append(rect(Rect2(o + Vector2(0, T - LIP), Vector2(T, LIP)), lip))
	if MazeStaticLayer.lip_drawn(level, cell, MazeLevel.Face.LEFT):
		out.append(rect(Rect2(o, Vector2(LIP, T)), lip))
	if MazeStaticLayer.lip_drawn(level, cell, MazeLevel.Face.RIGHT):
		out.append(rect(Rect2(o + Vector2(T - LIP, 0), Vector2(LIP, T)), lip))


static func _tuft(out: Array[Dictionary], level: MazeLevel, skin: Dictionary, x: int, y: int) -> void:
	var here := Vector2i(x, y)
	if not skin["tufts"] or here == level.spawn or here == level.finish:
		return
	if MazeStaticLayer.lip_drawn(level, Vector2i(x, y + 1), MazeLevel.Face.UP):
		out.append_array(MazeDecor.tuft_shapes(x, y, skin["pal"]))


static func _joints(out: Array[Dictionary], skin: Dictionary, x: int, y: int, o: Vector2) -> void:
	var col: Color = skin["pal"]["joint"]
	match skin["id"]:
		"jungle":
			var vx := MazeArt.pick(x, y, SALT_JOINT, 3) * 8 + 8
			var hy := 12.0 + MazeArt.pick(x, y, SALT_JOINT_H, 3) * 8.0
			out.append(rect(Rect2(o + Vector2(0, hy), Vector2(T, JOINT_W)), col))
			if MazeArt.pick(x, y, SALT_JOINT_H + 100, 2) == 0:
				out.append(rect(Rect2(o + Vector2(vx, 0), Vector2(JOINT_W, hy)), col))
			else:
				out.append(rect(Rect2(o + Vector2(vx, hy + JOINT_W), Vector2(JOINT_W, T - hy - JOINT_W)), col))
		"cave":
			if MazeArt.chance(x, y, SALT_CRACK, 30):
				var ax := 10.0 + MazeArt.pick(x, y, SALT_CRACK_PT, 8) * 2.0
				var bx := ax + MazeArt.pick(x, y, SALT_CRACK_PT + 1, 5) * 3.0 - 6.0
				var cx := bx + MazeArt.pick(x, y, SALT_CRACK_PT + 2, 5) * 3.0 - 6.0
				var pts := PackedVector2Array([o + Vector2(ax, 8), o + Vector2(bx, 20), o + Vector2(cx, 32)])
				out.append(polyline(pts, col, JOINT_W))
		_:
			out.append(rect(Rect2(o + Vector2(0, 19), Vector2(T, JOINT_W)), col))
			out.append(rect(Rect2(o + Vector2(0, T - JOINT_W), Vector2(T, JOINT_W)), col))
			var top_x := 0.0 if (x + y) % 2 == 0 else 20.0
			var low_x := 20.0 - top_x
			out.append(rect(Rect2(o + Vector2(top_x, 0), Vector2(JOINT_W, 19)), col))
			out.append(rect(Rect2(o + Vector2(low_x, 21), Vector2(JOINT_W, 17)), col))


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
