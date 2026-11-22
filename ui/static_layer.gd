class_name MazeStaticLayer
extends RefCounted
## One static layer of the world (back wall or tiles) in chunks of 16 x 16 cells. Makes the chunk nodes; MazeStaticBake
## draws them once into a texture per chunk (design 18.7, 18.10, ADR 0010).

enum Kind { BACK, TILES }

const CHUNK := 16
const T := 40.0
const VOID_PAD := 2000.0
const LIP := 5.0
const JOINT_W := 2.0
const EDGE_W := 2.0
const LINE_W := 2.0
const SHEEN_W := 3.0
const SHEEN_ALPHA := 0.5
const SHEEN_STEPS := [0, 2, 1] # distinct slots out of four
const DOOR_POST := 5.0
const DOOR_LINTEL := 6.0
const DOOR_ALPHA_BOTTOM := 0.9
const DOOR_ALPHA_TOP := 0.15
const DOOR_GLOWS := [[34.0, 0.06], [22.0, 0.08]]
const SALT_JOINT := 1
const SALT_JOINT_H := 2
const SALT_CRACK := 3
const SALT_CRACK_PT := 4
const SALT_SHEEN := 5
const SALT_SHEEN_N := 6
const SALT_BACK_V := 7
const SALT_BACK_H := 8
const SALT_STRATA := 9

var kind := Kind.TILES
var level: MazeLevel
var world := MazeWorlds.World.TEMPLE
var draws := 0 # chunk draws so far; tests expect one per chunk

var _pal: Dictionary


func build(lv: MazeLevel, world_id: int, layer_kind: int) -> void:
	level = lv
	world = world_id
	kind = layer_kind
	draws = 0
	_pal = MazeWorlds.palette(world_id)


## node that draws chunk (cx, cy) in world coordinates; the caller parents it
func make_chunk(cx: int, cy: int) -> Node2D:
	var chunk := Node2D.new()
	chunk.draw.connect(_draw_chunk.bind(chunk, cx, cy))
	return chunk


## screen colour far beyond the level, so the camera never shows the page behind the world
func make_void() -> Node2D:
	var v := Node2D.new()
	v.draw.connect(_draw_void.bind(v))
	return v


## number of chunks per axis
func chunks() -> Vector2i:
	return Vector2i(ceili(float(level.width) / CHUNK), ceili(float(level.height) / CHUNK))


func chunk_count() -> int:
	var n := chunks()
	return n.x * n.y


func _draw_void(ci: Node2D) -> void:
	var size := Vector2(level.width, level.height) * T
	ci.draw_rect(Rect2(Vector2.ONE * -VOID_PAD, size + Vector2.ONE * 2.0 * VOID_PAD), _pal["void"])


func _draw_chunk(ci: Node2D, cx: int, cy: int) -> void:
	draws += 1
	var x0 := cx * CHUNK
	var y0 := cy * CHUNK
	var x1 := mini(x0 + CHUNK, level.width)
	var y1 := mini(y0 + CHUNK, level.height)
	if kind == Kind.BACK:
		_draw_back_gradient(ci, x0, y0, x1, y1)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if kind == Kind.BACK:
				_draw_back_cell(ci, x, y)
			else:
				_draw_tile(ci, x, y)
	if kind == Kind.BACK:
		_draw_door_glow(ci, Rect2(Vector2(x0, y0) * T, Vector2(x1 - x0, y1 - y0) * T))


func _draw_back_gradient(ci: Node2D, x0: int, y0: int, x1: int, y1: int) -> void:
	var total := float(level.height) * T
	var top: Color = _pal["back_top"]
	var bottom: Color = _pal["back_bottom"]
	var c0 := top.lerp(bottom, y0 * T / total)
	var c1 := top.lerp(bottom, y1 * T / total)
	var pts := PackedVector2Array(
		[Vector2(x0, y0) * T, Vector2(x1, y0) * T, Vector2(x1, y1) * T, Vector2(x0, y1) * T]
	)
	ci.draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))


## masonry (temple, jungle) or strata (cave) lines, kept inside their own cell so chunks stay self-contained
func _draw_back_cell(ci: Node2D, x: int, y: int) -> void:
	var col: Color = _pal["back_line"]
	var o := Vector2(x, y) * T
	if level.solid(x, y):
		return
	match world:
		MazeWorlds.World.JUNGLE:
			if MazeArt.chance(x, y, SALT_BACK_H, 70):
				ci.draw_line(o + Vector2(0, 1), o + Vector2(T, 1), col, LINE_W)
			if MazeArt.chance(x, y, SALT_BACK_V, 40):
				var vx := 8.0 + MazeArt.pick(x, y, SALT_BACK_V + 100, 3) * 12.0
				ci.draw_line(o + Vector2(vx, 1), o + Vector2(vx, T), col, LINE_W)
		MazeWorlds.World.CAVE:
			if MazeArt.chance(x, y, SALT_STRATA, 35):
				var len := 20.0 + MazeArt.pick(x, y, SALT_STRATA + 100, 3) * 6.0
				var dy := 8.0 + MazeArt.pick(x, y, SALT_STRATA + 200, 4) * 8.0
				ci.draw_line(o + Vector2(2, dy), o + Vector2(2 + len, dy), col, LINE_W)
		_:
			ci.draw_line(o + Vector2(0, 1), o + Vector2(T, 1), col, LINE_W)
			if (x + y) % 2 == 0:
				ci.draw_line(o + Vector2(1, 0), o + Vector2(1, T), col, LINE_W)


## the glow reaches past its cell, so every chunk it touches draws it (a baked chunk clips at its edge)
func _draw_door_glow(ci: Node2D, rect: Rect2) -> void:
	var c := (Vector2(level.finish) + Vector2(0.5, 0.5)) * T
	var reach: float = DOOR_GLOWS[0][0]
	if not rect.intersects(Rect2(c - Vector2.ONE * reach, Vector2.ONE * 2.0 * reach)):
		return
	for g in DOOR_GLOWS:
		ci.draw_circle(c, g[0], Color(MazeWorlds.DOOR_LIGHT, g[1]))


func _draw_tile(ci: Node2D, x: int, y: int) -> void:
	var o := Vector2(x, y) * T
	match level.cell(x, y):
		MazeLevel.Cell.SOLID:
			_draw_block(ci, x, y, o)
		MazeLevel.Cell.NO_RING:
			_draw_no_ring(ci, x, y, o)
		MazeLevel.Cell.SPIKE:
			_draw_spikes(ci, o)
	if Vector2i(x, y) == level.finish:
		_draw_door(ci, o)


func _draw_block(ci: Node2D, x: int, y: int, o: Vector2) -> void:
	ci.draw_rect(Rect2(o, Vector2(T, T)), _pal["block"])
	_draw_joints(ci, x, y, o)
	var lip: Color = _pal["lip"]
	var cell := Vector2i(x, y)
	if MazeArt.lip_face(level, cell, MazeLevel.Face.UP):
		ci.draw_rect(Rect2(o, Vector2(T, LIP)), lip)
	if MazeArt.lip_face(level, cell, MazeLevel.Face.DOWN):
		ci.draw_rect(Rect2(o + Vector2(0, T - LIP), Vector2(T, LIP)), lip)
	if MazeArt.lip_face(level, cell, MazeLevel.Face.LEFT):
		ci.draw_rect(Rect2(o, Vector2(LIP, T)), lip)
	if MazeArt.lip_face(level, cell, MazeLevel.Face.RIGHT):
		ci.draw_rect(Rect2(o + Vector2(T - LIP, 0), Vector2(LIP, T)), lip)


## joints are drawn before the lips, so a lip is never interrupted
func _draw_joints(ci: Node2D, x: int, y: int, o: Vector2) -> void:
	var col: Color = _pal["joint"]
	match world:
		MazeWorlds.World.JUNGLE:
			# two stones per tile: a horizontal joint and one vertical joint in the upper or lower stone
			var vx := MazeArt.pick(x, y, SALT_JOINT, 3) * 8 + 8
			var hy := 12.0 + MazeArt.pick(x, y, SALT_JOINT_H, 3) * 8.0
			ci.draw_rect(Rect2(o + Vector2(0, hy), Vector2(T, JOINT_W)), col)
			if MazeArt.pick(x, y, SALT_JOINT_H + 100, 2) == 0:
				ci.draw_rect(Rect2(o + Vector2(vx, 0), Vector2(JOINT_W, hy)), col)
			else:
				ci.draw_rect(Rect2(o + Vector2(vx, hy + JOINT_W), Vector2(JOINT_W, T - hy - JOINT_W)), col)
		MazeWorlds.World.CAVE:
			if MazeArt.chance(x, y, SALT_CRACK, 30):
				var ax := 10.0 + MazeArt.pick(x, y, SALT_CRACK_PT, 8) * 2.0
				var bx := ax + MazeArt.pick(x, y, SALT_CRACK_PT + 1, 5) * 3.0 - 6.0
				var cx := bx + MazeArt.pick(x, y, SALT_CRACK_PT + 2, 5) * 3.0 - 6.0
				var a := Vector2(ax, 8)
				var b := Vector2(bx, 20)
				var c := Vector2(cx, 32)
				ci.draw_polyline(PackedVector2Array([o + a, o + b, o + c]), col, JOINT_W)
		_:
			# running bond: two courses of 20 px, vertical joints alternate between 0 and 20
			ci.draw_rect(Rect2(o + Vector2(0, 19), Vector2(T, JOINT_W)), col)
			ci.draw_rect(Rect2(o + Vector2(0, T - JOINT_W), Vector2(T, JOINT_W)), col)
			var top_x := 0.0 if (x + y) % 2 == 0 else 20.0
			var low_x := 20.0 - top_x
			ci.draw_rect(Rect2(o + Vector2(top_x, 0), Vector2(JOINT_W, 19)), col)
			ci.draw_rect(Rect2(o + Vector2(low_x, 21), Vector2(JOINT_W, 17)), col)


func _draw_no_ring(ci: Node2D, x: int, y: int, o: Vector2) -> void:
	ci.draw_rect(Rect2(o, Vector2(T, T)), _pal["noring"])
	var edge: Color = _pal["noring_edge"]
	ci.draw_rect(Rect2(o, Vector2(T, EDGE_W)), edge)
	ci.draw_rect(Rect2(o + Vector2(0, T - EDGE_W), Vector2(T, EDGE_W)), edge)
	ci.draw_rect(Rect2(o, Vector2(EDGE_W, T)), edge)
	ci.draw_rect(Rect2(o + Vector2(T - EDGE_W, 0), Vector2(EDGE_W, T)), edge)
	var sheen := Color(_pal["sheen"], SHEEN_ALPHA)
	var base := MazeArt.pick(x, y, SALT_SHEEN, 4)
	var n := 2 + MazeArt.pick(x, y, SALT_SHEEN_N, 2)
	for i in n:
		var sx: float = 4.0 + 8.0 * ((base + int(SHEEN_STEPS[i])) % 4)
		ci.draw_line(o + Vector2(sx, 35), o + Vector2(sx + 8, 6), sheen, SHEEN_W)


## same colours in every world; only the outline of a spike changes (design 18.5)
func _draw_spikes(ci: Node2D, o: Vector2) -> void:
	for i in 2:
		var x := o.x + i * T / 2.0
		var b := o.y + T
		var pts := PackedVector2Array()
		match world:
			MazeWorlds.World.JUNGLE:
				pts = PackedVector2Array(
					[
						Vector2(x + 1, b), Vector2(x + 6, o.y + 30), Vector2(x + 11, o.y + 20),
						Vector2(x + 14, o.y + 30), Vector2(x + 19, b),
					]
				)
			MazeWorlds.World.CAVE:
				pts = PackedVector2Array(
					[
						Vector2(x + 1, b), Vector2(x + 4, o.y + 27), Vector2(x + 8, o.y + 20),
						Vector2(x + 12, o.y + 20), Vector2(x + 16, o.y + 27), Vector2(x + 19, b),
					]
				)
			_:
				pts = PackedVector2Array([Vector2(x + 1, b), Vector2(x + T / 4.0, o.y + T / 2.0), Vector2(x + 19, b)])
		ci.draw_colored_polygon(pts, MazeWorlds.HAZARD)
		ci.draw_polyline(pts.slice(0, pts.size() / 2 + 1), MazeWorlds.HAZARD_HI, 2.0)
		ci.draw_rect(Rect2(Vector2(x + 1, b - 3), Vector2(18, 3)), MazeWorlds.HAZARD_DARK)


func _draw_door(ci: Node2D, o: Vector2) -> void:
	var inner := Rect2(o + Vector2(DOOR_POST, DOOR_LINTEL), Vector2(T - 2.0 * DOOR_POST, T - DOOR_LINTEL))
	var top := Color(MazeWorlds.DOOR_LIGHT, DOOR_ALPHA_TOP)
	var bottom := Color(MazeWorlds.DOOR_LIGHT, DOOR_ALPHA_BOTTOM)
	var corners := PackedVector2Array(
		[inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	)
	ci.draw_polygon(corners, PackedColorArray([top, top, bottom, bottom]))
	var frame: Color = _pal["door_frame"]
	ci.draw_rect(Rect2(o, Vector2(DOOR_POST, T)), frame)
	ci.draw_rect(Rect2(o + Vector2(T - DOOR_POST, 0), Vector2(DOOR_POST, T)), frame)
	ci.draw_rect(Rect2(o, Vector2(T, DOOR_LINTEL)), frame)
