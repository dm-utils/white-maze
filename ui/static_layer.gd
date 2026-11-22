class_name MazeStaticLayer
extends RefCounted
## One static layer of the world (back wall or tiles) in chunks of 16 x 16 cells. Makes the chunk nodes; MazeStaticBake
## draws them once into a texture per chunk (design 18.7, 18.10, ADR 0010).

enum Kind { BACK, TILES }

const CHUNK := 16
const T := 40.0
const VOID_PAD := 2000.0
const LINE_W := 2.0
const DOOR_GLOWS := [[34.0, 0.06], [22.0, 0.08]]
const SALT_BACK_V := 7
const SALT_BACK_H := 8
const SALT_STRATA := 9

var kind := Kind.TILES
var level: MazeLevel
var world := MazeWorlds.World.TEMPLE
var draws := 0 # chunk draws so far; tests expect one per chunk

var _pal: Dictionary
var _skin: Dictionary
var _back_items: Array[Dictionary] = [] # {"bounds": Rect2, "shapes": Array[Dictionary]}
var _cracks := {} # Vector2i -> shapes
var _chunks := {} # Vector2i -> primitives of a tiles chunk, until its first draw
var build_usec := 0 # tiles: time of the primitive build
var command_count := 0 # tiles: primitives of all chunks


func build(lv: MazeLevel, world_id: int, layer_kind: int) -> void:
	level = lv
	world = world_id
	kind = layer_kind
	draws = 0
	_skin = MazeSkins.skin(world_id)
	_pal = _skin["pal"]
	_back_items.clear()
	_cracks.clear()
	for item in MazeDecor.plan(lv, world_id):
		var list := MazeDecor.shapes(item, _pal)
		if item["layer"] == "back" and kind == Kind.BACK:
			_back_items.append({"bounds": MazeDecor.bounds(list), "shapes": list})
		elif item["layer"] == "tiles" and kind == Kind.TILES:
			_cracks[item["cell"]] = list
	_chunks.clear()
	command_count = 0
	var t0 := Time.get_ticks_usec()
	if kind == Kind.TILES:
		var n := chunks()
		MazeSkin.begin(lv, _skin)
		for cy in n.y:
			for cx in n.x:
				var list := MazeTileShapes.chunk(lv, _skin, _cracks, cx, cy)
				command_count += list.size()
				_chunks[Vector2i(cx, cy)] = list
		MazeSkin.end()
	build_usec = Time.get_ticks_usec() - t0


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
	if kind == Kind.TILES:
		var key := Vector2i(cx, cy)
		if not _chunks.has(key):
			_chunks[key] = MazeTileShapes.chunk(level, _skin, _cracks, cx, cy)
		_draw_shapes(ci, _chunks[key])
		_chunks.erase(key)
		return
	for y in range(y0, y1):
		for x in range(x0, x1):
			_draw_back_cell(ci, x, y)
	if kind == Kind.BACK:
		var rect := Rect2(Vector2(x0, y0) * T, Vector2(x1 - x0, y1 - y0) * T)
		_draw_back_items(ci, rect)
		_draw_door_glow(ci, rect)


## items that reach into the chunk; light glows cross chunk edges, so each chunk draws what touches it
func _draw_back_items(ci: Node2D, rect: Rect2) -> void:
	for it in _back_items:
		if rect.intersects(it["bounds"]):
			_draw_shapes(ci, it["shapes"])


func _draw_shapes(ci: Node2D, list: Array[Dictionary]) -> void:
	for s in list:
		match s["t"]:
			"poly":
				ci.draw_colored_polygon(s["pts"], s["col"])
			"line":
				ci.draw_line(s["pts"][0], s["pts"][1], s["col"], s["w"])
			"polyline":
				ci.draw_polyline(s["pts"], s["col"], s["w"])
			"circle":
				ci.draw_circle(s["c"], s["r"], s["col"])
			"vpoly":
				ci.draw_polygon(s["pts"], s["cols"])


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
	match _skin["back"]:
		"courses":
			if MazeArt.chance(x, y, SALT_BACK_H, 70):
				ci.draw_line(o + Vector2(0, 1), o + Vector2(T, 1), col, LINE_W)
			if MazeArt.chance(x, y, SALT_BACK_V, 40):
				var vx := 8.0 + MazeArt.pick(x, y, SALT_BACK_V + 100, 3) * 12.0
				ci.draw_line(o + Vector2(vx, 1), o + Vector2(vx, T), col, LINE_W)
		"strata":
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


## lip_face, but no lip on the bottom of the last row: the other level edges have none either
static func lip_drawn(lv: MazeLevel, cell: Vector2i, face: int) -> bool:
	if face == MazeLevel.Face.DOWN and cell.y == lv.height - 1:
		return false
	return MazeArt.lip_face(lv, cell, face)
