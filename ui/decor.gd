class_name MazeDecor
extends RefCounted
## Pure decor: which details sit where (plan) and which primitives draw them (shapes). Derived from the cells and the
## world only, via MazeArt hashes, so two calls give equal results (design 18.8, rules D1 to D8).

const T := 40.0
const BACK_LIMIT_PER_100 := 8
const MIN_PILLAR_RUN := 4
const SALT_PILLAR := 21
const SALT_RELIEF := 22
const SALT_TORCH := 23
const SALT_SAND := 24
const SALT_ARCH := 25
const SALT_VINE := 26
const SALT_VINE_LEN := 27
const SALT_VINE_X := 28
const SALT_GLOW := 29
const SALT_SPOT := 30
const SALT_CRACK := 31
const SALT_CRACK_PT := 32
const SALT_VARIANT := 33
const SALT_TRIM := 34
const SALT_SPECK := 35
const SALT_SPECK_N := 36
const SALT_TUFT := 37
const SALT_TUFT_N := 38
const SALT_TUFT_H := 39
const SAND_STEPS := 16 # many small steps keep the foot of the mound blunt
const RELIEF_GAP := 12
const ARCH_GAP := 12
const TORCH_GAP := 6
const GLOW_GAP := 4
const SPAWN_CLEAR := 2 # cells around the start kept plain, Lilith reads first
const DOOR_CLEAR := 5 # cells between a light source and the door
const SPACED := {"relief": RELIEF_GAP, "arch": ARCH_GAP, "torch": TORCH_GAP, "glow": GLOW_GAP}
const GLOW_ALPHAS := [[60.0, 0.05], [40.0, 0.06], [24.0, 0.08]]
const CAVE_GLOW := [[40.0, 0.03], [28.0, 0.03], [16.0, 0.03]] # stacked, so the rim stays soft
const CRACK_PERCENT := {MazeWorlds.World.TEMPLE: 25, MazeWorlds.World.JUNGLE: 12}
const KINDS_BACK := ["pillar", "relief", "arch", "torch", "glow", "vine", "sand", "spot"]


## every item of the level in this world, sorted by (y, x, kind); no state, no randomness
static func plan(level: MazeLevel, world: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var taken := {}
	var last := {}
	var is_temple := world == MazeWorlds.World.TEMPLE
	var is_jungle := world == MazeWorlds.World.JUNGLE
	var is_cave := world == MazeWorlds.World.CAVE
	if is_temple:
		_pillars(level, items, taken)
		_scatter(level, items, taken, last, "relief", 3)
	if is_jungle:
		_scatter(level, items, taken, last, "arch", 4)
	if not is_cave:
		_scatter(level, items, taken, last, "torch", 1)
	if is_cave:
		_scatter(level, items, taken, last, "glow", 1)
	if is_jungle:
		_scatter(level, items, taken, last, "vine", 1)
	if is_temple:
		_scatter(level, items, taken, last, "sand", 1)
	if is_cave:
		_scatter(level, items, taken, last, "spot", 1)
	_trim(level, items)
	_cracks(level, world, items)
	items.sort_custom(_before)
	return items


## cells an item covers
static func footprint(item: Dictionary) -> Rect2i:
	var c: Vector2i = item["cell"]
	match item["kind"]:
		"pillar", "vine":
			return Rect2i(c.x, c.y, 1, item["size"])
		"relief":
			return Rect2i(c.x - 1, c.y - 1, 3, 3)
		"arch":
			return Rect2i(c.x, c.y, 4, 3)
	return Rect2i(c.x, c.y, 1, 1)


## primitives of an item in world px; glow circles come first and are marked "glow" (they may leave the footprint)
static func shapes(item: Dictionary, pal: Dictionary) -> Array[Dictionary]:
	var c: Vector2i = item["cell"]
	var o := Vector2(c) * T
	var out: Array[Dictionary] = []
	var deco: Color = pal["back_decor"]
	match item["kind"]:
		"pillar":
			var h: float = item["size"] * T
			out.append(_rect(Rect2(o + Vector2(8, 0), Vector2(24, h)), deco))
			out.append(_rect(Rect2(o + Vector2(4, 0), Vector2(32, 6)), deco))
			out.append(_rect(Rect2(o + Vector2(4, h - 6), Vector2(32, 6)), deco))
		"relief":
			var m := o + Vector2(T, T) / 2.0
			out.append(_polyline(_ring(m, 12.0), deco, 3.0))
			out.append(_polyline(_ring(m, 20.0), deco, 3.0))
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0 + 0.2)
				out.append(_line(m + d * 27.0, m + d * 38.0, deco, 3.0))
		"torch":
			var m := o + Vector2(T, T) / 2.0
			var light: Color = pal["light"]
			var flame := m + Vector2(0, -6)
			for g: Array in GLOW_ALPHAS:
				out.append(_glow(flame, g[0], Color(light, g[1])))
			out.append(_rect(Rect2(m + Vector2(-3, 2), Vector2(6, 12)), deco))
			out.append(_rect(Rect2(m + Vector2(-6, 1), Vector2(12, 3)), deco))
			out.append(_poly(_ellipse(flame, 4.0, 7.0), light))
		"arch":
			var base := o + Vector2(0, 3.0 * T)
			var mid := o + Vector2(2.0 * T, 60)
			var arc := PackedVector2Array()
			for i in 9:
				arc.append(mid + Vector2.from_angle(PI + PI * i / 11.0) * 54.0)
			out.append(_polyline(PackedVector2Array([base + Vector2(26, -4), mid + Vector2(-54, 0)]), deco, 4.0))
			out.append(_polyline(arc, deco, 4.0))
		"vine":
			var vx := o.x + 12.0 + MazeArt.pick(c.x, c.y, SALT_VINE_X, 4) * 5.0
			var bottom: float = o.y + item["size"] * T - 8.0
			out.append(_line(Vector2(vx, o.y), Vector2(vx, bottom), deco, 3.0))
			var side := 1.0
			var y := o.y + 12.0
			while y < bottom:
				out.append(_poly(_ellipse(Vector2(vx + side * 5.0, y), 6.0, 3.5), deco))
				side = -side
				y += 14.0
			out.append(_poly(_ellipse(Vector2(vx, bottom), 4.0, 4.0), deco))
		"glow":
			var m := o + Vector2(T, T) / 2.0
			for g: Array in CAVE_GLOW:
				out.append(_glow(m, g[0], Color(pal["light"], g[1])))
			out.append(_poly(_prism(m + Vector2(-9, 4), 6.0, 9.0), deco))
			out.append(_poly(_prism(m + Vector2(0, -2), 6.0, 12.0), deco))
			out.append(_poly(_prism(m + Vector2(9, 5), 5.0, 8.0), deco))
		"sand":
			var left: bool = item["variant"] == 0
			var corner := o + Vector2(0.0 if left else T, T)
			var dir := 1.0 if left else -1.0
			var pts := PackedVector2Array([corner])
			for i in SAND_STEPS + 1:
				var a := PI / 2.0 * i / SAND_STEPS
				pts.append(corner + Vector2(dir * 14.0 * cos(a), -6.0 * sin(a)))
			out.append(_poly(pts, Color(pal["detail"], 0.3)))
		"spot":
			out.append(_circle(o + Vector2(T, T) / 2.0, 16.0, Color(pal["detail"], 0.15)))
		"crack":
			var pts := PackedVector2Array()
			var x := 12.0 + MazeArt.pick(c.x, c.y, SALT_CRACK_PT, 12)
			var y := 8.0
			for i in 4:
				pts.append(o + Vector2(x, y))
				x = clampf(x + MazeArt.pick(c.x, c.y, SALT_CRACK_PT + 1 + i, 9) - 4.0, 8.0, 32.0)
				y += 8.0
			out.append(_polyline(pts, pal["joint"], 2.0))
	return out


## 1 or 2 dots of 1.5 px, kept 8 px from the cell edge so they never touch a lip
static func speck_shapes(x: int, y: int, pal: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var o := Vector2(x, y) * T
	for i in 1 + MazeArt.pick(x, y, SALT_SPECK_N, 2):
		var p := Vector2(8 + MazeArt.pick(x, y, SALT_SPECK + i * 2, 25), 8 + MazeArt.pick(x, y, SALT_SPECK + i * 2 + 1, 25))
		out.append(_circle(o + p, 1.5, pal["speck"]))
	return out


## moss blades on an up lip face; (x, y) is the empty cell above the block, blades stand on its bottom edge
static func tuft_shapes(x: int, y: int, pal: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not MazeArt.chance(x, y, SALT_TUFT, 50):
		return out
	var o := Vector2(x, y) * T
	var n := 3 + MazeArt.pick(x, y, SALT_TUFT_N, 3)
	for i in n:
		var bx := 6.0 + i * 28.0 / (n - 1) + MazeArt.pick(x, y, SALT_TUFT_H + 10 + i, 3) - 1.0
		var h := 2.0 + MazeArt.pick(x, y, SALT_TUFT_H + i, 3)
		var lean := MazeArt.pick(x, y, SALT_TUFT_H + 20 + i, 3) - 1.0
		out.append(_line(o + Vector2(bx, T), o + Vector2(bx + lean, T - h), pal["lip"], 2.0))
	return out


## bounding rect of the primitives; widths included unless thin is set
static func bounds(list: Array[Dictionary], thin := false) -> Rect2:
	var r := Rect2()
	var first := true
	for s in list:
		var b := Rect2()
		var pad := 0.0 if thin else float(s.get("w", 0.0)) / 2.0
		match s["t"]:
			"circle":
				b = Rect2(s["c"] - Vector2.ONE * s["r"], Vector2.ONE * 2.0 * s["r"])
			_:
				var pts: PackedVector2Array = s["pts"]
				b = Rect2(pts[0], Vector2.ZERO)
				for p in pts:
					b = b.expand(p)
		b = b.grow(pad)
		r = b if first else r.merge(b)
		first = false
	return r


static func _pillars(level: MazeLevel, items: Array[Dictionary], taken: Dictionary) -> void:
	for x in level.width:
		if MazeArt.pick(x, 0, SALT_PILLAR, 7) != 0:
			continue
		var y := 0
		while y < level.height:
			var top := y
			while y < level.height and _free(level, x, y) and not taken.has(Vector2i(x, y)):
				y += 1
			var run := y - top
			if run >= MIN_PILLAR_RUN and level.solid(x, top - 1) and level.solid(x, y):
				_add(items, taken, "pillar", Vector2i(x, top), run)
			y += 1


static func _scatter(
	level: MazeLevel, items: Array[Dictionary], taken: Dictionary, last: Dictionary, kind: String, size: int
) -> void:
	for x in level.width:
		for y in level.height:
			if not _wants(level, kind, x, y):
				continue
			var item_size := size
			var c := Vector2i(x, y)
			if kind == "vine":
				item_size = _vine_len(level, x, y, taken)
			var item := {"kind": kind, "cell": c, "size": item_size}
			if kind == "arch" or kind == "relief":
				var fp := footprint(item)
				if not _area_free(level, fp, taken):
					continue
			elif taken.has(c):
				continue
			if kind in SPACED and last.has(kind):
				var gap: int = SPACED[kind]
				if x - int(last[kind]) < gap:
					continue
			if kind in SPACED:
				last[kind] = x
			_add(items, taken, kind, c, item_size, _sand_variant(level, x, y) if kind == "sand" else -1)


## chance and neighbour conditions of one kind at one cell (the cell itself must be free)
static func _wants(level: MazeLevel, kind: String, x: int, y: int) -> bool:
	match kind:
		"relief":
			return MazeArt.chance(x, y, SALT_RELIEF, 9)
		"arch":
			return MazeArt.chance(x, y, SALT_ARCH, 8)
		"torch":
			return (
				MazeArt.chance(x, y, SALT_TORCH, 12)
				and _free(level, x, y)
				and _far_from_door(level, x, y)
				and not _solid_next_to(level, x, y)
				and level.cell(x, y + 1) == MazeLevel.Cell.EMPTY
				and level.solid(x, y + 2)
			)
		"glow":
			return (
				MazeArt.chance(x, y, SALT_GLOW, 4)
				and _free(level, x, y)
				and _far_from_door(level, x, y)
				and not _solid_next_to(level, x, y)
				and _free(level, x, y + 1)
				and _free(level, x, y + 2)
				and level.cell(x, y - 1) == MazeLevel.Cell.EMPTY
			)
		"vine":
			return MazeArt.chance(x, y, SALT_VINE, 25) and _free(level, x, y) and level.solid(x, y - 1)
		"sand":
			return (
				MazeArt.chance(x, y, SALT_SAND, 60)
				and _free(level, x, y)
				and level.solid(x, y + 1)
				and (level.solid(x - 1, y) or level.solid(x + 1, y))
			)
		"spot":
			return MazeArt.chance(x, y, SALT_SPOT, 3) and _free(level, x, y)
	return false


static func _vine_len(level: MazeLevel, x: int, y: int, taken: Dictionary) -> int:
	var want := 1 + MazeArt.pick(x, y, SALT_VINE_LEN, 3)
	var n := 1
	while n < want and _free(level, x, y + n) and not taken.has(Vector2i(x, y + n)):
		n += 1
	return n


static func _area_free(level: MazeLevel, area: Rect2i, taken: Dictionary) -> bool:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if not _free(level, x, y) or taken.has(Vector2i(x, y)):
				return false
	return true


static func _add(
	items: Array[Dictionary], taken: Dictionary, kind: String, c: Vector2i, size: int, variant := -1
) -> void:
	var item := {
		"kind": kind,
		"cell": c,
		"size": size,
		"variant": variant if variant >= 0 else MazeArt.pick(c.x, c.y, SALT_VARIANT, 4),
		"layer": "back",
	}
	var fp := footprint(item)
	for y in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			taken[Vector2i(x, y)] = true
	items.append(item)


## calm (D7): drop the items with the highest trim hash until the limit holds
@warning_ignore("integer_division")
static func _trim(level: MazeLevel, items: Array[Dictionary]) -> void:
	var empty := 0
	for v in level.cells:
		if v == MazeLevel.Cell.EMPTY:
			empty += 1
	var limit := empty * BACK_LIMIT_PER_100 / 100
	if items.size() <= limit:
		return
	items.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _trim_key(a) < _trim_key(b)
	)
	items.resize(limit)


static func _trim_key(item: Dictionary) -> int:
	var c: Vector2i = item["cell"]
	return MazeArt.hash3(c.x, c.y, SALT_TRIM + KINDS_BACK.find(item["kind"]))


## a block with four solid neighbours; the cave has none, its joint pattern already is a crack
static func _cracks(level: MazeLevel, world: int, items: Array[Dictionary]) -> void:
	if not CRACK_PERCENT.has(world):
		return
	for y in level.height:
		for x in level.width:
			if level.cell(x, y) != MazeLevel.Cell.SOLID or not MazeArt.chance(x, y, SALT_CRACK, CRACK_PERCENT[world]):
				continue
			if (
				level.solid(x - 1, y)
				and level.solid(x + 1, y)
				and level.solid(x, y - 1)
				and level.solid(x, y + 1)
			):
				items.append(
					{
						"kind": "crack",
						"cell": Vector2i(x, y),
						"size": 1,
						"variant": MazeArt.pick(x, y, SALT_VARIANT, 4),
						"layer": "tiles",
					}
				)


## empty, not within two cells of the start, not the door or its eight neighbours, not directly above a spike (D1, D2)
static func _free(level: MazeLevel, x: int, y: int) -> bool:
	if x < 0 or x >= level.width or y < 0 or y >= level.height:
		return false
	if level.cell(x, y) != MazeLevel.Cell.EMPTY:
		return false
	if maxi(absi(x - level.spawn.x), absi(y - level.spawn.y)) <= SPAWN_CLEAR:
		return false
	if absi(x - level.finish.x) <= 1 and absi(y - level.finish.y) <= 1:
		return false
	return level.cell(x, y + 1) != MazeLevel.Cell.SPIKE


## light stays clear of the door so the door glow is the one that reads
static func _far_from_door(level: MazeLevel, x: int, y: int) -> bool:
	return maxi(absi(x - level.finish.x), absi(y - level.finish.y)) >= DOOR_CLEAR


static func _solid_next_to(level: MazeLevel, x: int, y: int) -> bool:
	return level.solid(x - 1, y) or level.solid(x + 1, y) or level.solid(x, y - 1) or level.solid(x, y + 1)


## 0 when the sand leans on the left wall, 1 on the right; hash decides when both are solid
static func _sand_variant(level: MazeLevel, x: int, y: int) -> int:
	var left := level.solid(x - 1, y)
	var right := level.solid(x + 1, y)
	if left and right:
		return MazeArt.pick(x, y, SALT_SAND + 100, 2)
	return 0 if left else 1


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ca: Vector2i = a["cell"]
	var cb: Vector2i = b["cell"]
	if ca.y != cb.y:
		return ca.y < cb.y
	if ca.x != cb.x:
		return ca.x < cb.x
	return str(a["kind"]) < str(b["kind"])


static func _rect(r: Rect2, col: Color) -> Dictionary:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	return _poly(pts, col)


static func _poly(pts: PackedVector2Array, col: Color) -> Dictionary:
	return {"t": "poly", "pts": pts, "col": col}


static func _line(a: Vector2, b: Vector2, col: Color, w: float) -> Dictionary:
	return {"t": "line", "pts": PackedVector2Array([a, b]), "col": col, "w": w}


static func _polyline(pts: PackedVector2Array, col: Color, w: float) -> Dictionary:
	return {"t": "polyline", "pts": pts, "col": col, "w": w}


static func _circle(c: Vector2, r: float, col: Color) -> Dictionary:
	return {"t": "circle", "c": c, "r": r, "col": col}


static func _glow(c: Vector2, r: float, col: Color) -> Dictionary:
	var s := _circle(c, r, col)
	s["glow"] = true
	return s


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _ring(c: Vector2, r: float) -> PackedVector2Array:
	var pts := _ellipse(c, r, r)
	pts.append(pts[0])
	return pts


## blunt crystal: octagon with flat top and bottom, half width w, half height h
static func _prism(c: Vector2, w: float, h: float) -> PackedVector2Array:
	var k := 3.0
	return PackedVector2Array(
		[
			c + Vector2(-w + k, -h), c + Vector2(w - k, -h), c + Vector2(w, -h + k), c + Vector2(w, h - k),
			c + Vector2(w - k, h), c + Vector2(-w + k, h), c + Vector2(-w, h - k), c + Vector2(-w, -h + k),
		]
	)
