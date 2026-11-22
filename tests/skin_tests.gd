extends RefCounted
## Skins (design 21): data packs and engine rules (S2, S3, S8), geometry, shapes, bake. Grows with the card steps.

const H := preload("res://tests/helpers.gd")
const PALETTE_USED := [
	"void", "back_top", "back_bottom", "back_line", "back_decor", "block", "joint", "speck", "lip", "noring",
	"noring_edge", "sheen", "detail", "light", "door_frame",
]

var _check: Callable
var _node: Node


func run(check: Callable, node: Node) -> void:
	_check = check
	_node = node
	_data()
	_guard()
	_palette_rules()
	_rim_faces()
	_never_larger()
	_polygons_valid()
	_continuity()
	_precision()
	_groups()
	_keys_argument()
	_spikes_rings()
	_lip_at_a_glance()
	_bake_times()


func _packs() -> Array:
	return [MazeSkins.TEMPLE, MazeSkins.JUNGLE, MazeSkins.CAVE]


## S2
func _data() -> void:
	for w in MazeWorlds.COUNT:
		var pack := MazeSkins.pack(w)
		var name: String = MazeWorlds.NAMES[w]
		_check.call(MazeSkin.validate(pack).is_empty(), "S2 %s pack is valid (%s)" % [name, MazeSkin.validate(pack)])
		var skin := MazeSkins.skin(w)
		_check.call(MazeWorlds.palette(w) == skin["pal"], "S2 %s palette comes from the skin" % name)
		var all := true
		for key in PALETTE_USED:
			all = all and skin["pal"].has(key) and skin["pal"][key] is Color
		_check.call(all, "S2 %s palette holds every key the layers read" % name)
		var round_trip: Dictionary = JSON.parse_string(JSON.stringify(pack))
		_check.call(MazeSkin.resolve(round_trip) == skin, "S2 %s pack survives a JSON round trip" % name)
	_check.call(MazeWorlds.palette(99) == MazeWorlds.palette(MazeWorlds.World.TEMPLE), "S2 palette(99) is the temple")
	_check.call(MazeSkins.skin(-1) == MazeSkins.skin(0), "S2 an unknown world gives the temple skin")


func _with(path: Array, value: Variant) -> Dictionary:
	var pack: Dictionary = MazeSkins.TEMPLE.duplicate(true)
	var node: Variant = pack
	for i in path.size() - 1:
		node = node[path[i]]
	node[path[-1]] = value
	return pack


## S3
func _guard() -> void:
	for key in ["contour", "lip_hi", "door_frame", "hazard", "ring"]:
		var pack := _with(["palette", key], "#112233")
		_check.call(_has(MazeSkin.validate(pack), "engine-owned"), "S3 palette.%s is engine-owned" % key)
		var top := _with([key], "#112233")
		_check.call(_has(MazeSkin.validate(top), "engine-owned"), "S3 top-level %s is engine-owned" % key)
	_check.call(_has(MazeSkin.validate(_with(["palette", "lip"], "#FFFFFF")), "engine-owned"), "S3 palette.lip is engine-owned")
	var bad := {
		"rim.wall 9": _with(["rim", "wall"], 9),
		"stones.chamfer 20": _with(["stones", "chamfer"], 20.0),
		"3 motifs": _with(["motifs"], [{"kind": "moss", "chance": 1}, {"kind": "moss", "chance": 1}, {"kind": "moss", "chance": 1}]),
		"unknown tint": _with(["lip"], "neon"),
		"unknown motif": _with(["motifs"], [{"kind": "snake", "chance": 5}]),
		"unknown key": _with(["extra"], 1),
		"bad colour": _with(["palette", "block"], "red"),
	}
	var temple := MazeSkins.skin(MazeWorlds.World.TEMPLE)
	for label: String in bad:
		var pack: Dictionary = bad[label]
		_check.call(not MazeSkin.validate(pack).is_empty(), "S3 %s gives an error" % label)
		_check.call(MazeSkin.from_pack(pack) == temple, "S3 %s: from_pack returns the temple skin" % label)
	var wide := _with(["rim", "wall"], 9)
	_check.call(MazeSkin.resolve(wide)["rim"]["wall"] == 3, "S3 resolve clamps rim.wall 9 to 3")
	var skin := MazeSkins.skin(MazeWorlds.World.JUNGLE)
	var pal: Dictionary = skin["pal"]
	var tint: Array = MazeSkin.LIP_TINTS["moss"]
	_check.call(
		pal["lip_hi"] == Color(tint[1]) and pal["lip_lo"] == Color(tint[2]) and pal["lip"] == Color(tint[0])
		and pal["contour"] == (pal["block"] as Color).darkened(MazeSkin.CONTOUR_DARKEN)
		and pal["door_frame"] == (pal["block"] as Color).lightened(MazeSkin.DOOR_FRAME_LIGHTEN),
		"S3 lip shades, contour and door frame come from the engine"
	)
	var ints := _with(["rim", "wall"], 2.0)
	_check.call(MazeSkin.validate(ints).is_empty(), "S3 a whole float is accepted")


func _has(err: PackedStringArray, text: String) -> bool:
	for line in err:
		if text in line:
			return true
	return false


## S8
func _palette_rules() -> void:
	for w in MazeWorlds.COUNT:
		var err := MazeSkin.check_palette(MazeWorlds.palette(w))
		_check.call(err.is_empty(), "S8 %s palette passes the checks (%s)" % [MazeWorlds.NAMES[w], err])
	var base := MazeWorlds.palette(MazeWorlds.World.TEMPLE)
	var white := Color("#F0F0F0")
	var grey := Color("#808080")
	var hz := MazeWorlds.HAZARD
	var cases := {
		"C1": {"lip": base["block"]},
		"C2": {"block_hi": base["lip"]},
		"C3": {"joint": base["lip"]},
		"C4": {"block_lo": base["block_hi"]},
		"C5": {"contour": base["block"]},
		"C6": {"mortar": (base["block"] as Color).darkened(0.1)},
		"C7": {"noring": base["back_top"]},
		"C8": {"noring_hi": base["lip"]},
		"C9": {"back_top": hz},
		"C10": {"back_line": grey},
		"C11": {"speck": white},
		"C12": {"light": hz},
		"C13": {"back_top": MazeLilith.HAIR},
		"C14": {"door_frame": base["back_top"]},
	}
	for id: String in cases:
		var pal := base.duplicate()
		pal.merge(cases[id], true)
		_check.call(_has(MazeSkin.check_palette(pal), id + ":"), "S8 %s fires on a broken palette" % id)
	var bad_tints := {"snow": ["#FFFFFF", "#FFFFFF", "#FFFFFF"]}
	_check.call(_has(MazeSkin.check_palette(base, bad_tints), "C15:"), "S8 C15 fires on a near white lip tint")
	_check.call(
		_has(MazeSkin.check_palette(base, MazeSkin.LIP_TINTS, MazeWorlds.HAZARD), "C15:"),
		"S8 C15 fires on a pin outline lighter than the dark pin"
	)


## S13 (time part): primitive build per level and world; the budget of 21.12.3 is 150 ms, the test only fails above 1 s
func _bake_times() -> void:
	var slow := 0.0
	var worst := 0
	var empty_ok := true
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		for w in MazeWorlds.COUNT:
			var best := 1 << 60
			var layer := MazeStaticLayer.new()
			for i in 3:
				layer.build(lv, w, MazeStaticLayer.Kind.TILES)
				best = mini(best, layer.build_usec)
			var points := 0
			for list: Array in layer._chunks.values():
				for s: Dictionary in list:
					points += (s["pts"] as PackedVector2Array).size() if s.has("pts") else 1
				worst = maxi(worst, list.size())
			print(
				"bake %s %s: %.1f ms, %d primitives, %d points"
				% [id, MazeWorlds.NAMES[w], best / 1000.0, layer.command_count, points]
			)
			slow = maxf(slow, best / 1000.0)
	_check.call(slow <= 1000.0, "S13 the primitive build of every level in every world stays under 1000 ms (%.1f)" % slow)
	_check.call(worst <= 8000, "S13 at most 8000 primitives per chunk (%d)" % worst)


## S2: a crumbly or trimmed face is exactly a ring face
func _rim_faces() -> void:
	var same := true
	var faces := 0
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		for y in lv.height:
			for x in lv.width:
				for f in 4:
					var c := Vector2i(x, y)
					var a := MazeSkin.rim_face(lv, c, f)
					same = same and a == MazeStaticLayer.lip_drawn(lv, c, f)
					faces += 1 if a else 0
	_check.call(same and faces > 0, "S2 rim_face equals lip_drawn on every cell and face of every level (%d)" % faces)


## primitives of one chunk list that may touch a rect, bounds included
func _near(list: Array, rect: Rect2) -> Array:
	var out: Array = []
	for s: Dictionary in list:
		var one: Array[Dictionary] = [s]
		if MazeDecor.bounds(one).grow(0.5).intersects(rect):
			out.append(s)
	return out


## colour at a point: every primitive that contains it composited in draw order over base
func _colour_at(list: Array, p: Vector2, base: Color) -> Color:
	var col := base
	for s: Dictionary in list:
		var c := Color(0, 0, 0, 0)
		match s["t"]:
			"poly":
				if Geometry2D.is_point_in_polygon(p, s["pts"]):
					c = s["col"]
			"vpoly":
				if Geometry2D.is_point_in_polygon(p, s["pts"]):
					c = s["cols"][0]
					for v: Color in s["cols"]:
						c = v if MazeArt.luminance(v) > MazeArt.luminance(c) else c
			"line", "polyline":
				var pts: PackedVector2Array = s["pts"]
				for i in pts.size() - 1:
					var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
					if q.distance_to(p) <= float(s["w"]) / 2.0:
						c = s["col"]
			"circle":
				if p.distance_to(s["c"]) <= float(s["r"]):
					c = s["col"]
		if c.a > 0.0:
			col = col.lerp(Color(c, 1.0), c.a)
	return col


func _same_colour(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.003 and absf(a.g - b.g) < 0.003 and absf(a.b - b.b) < 0.003


## S7: the lip at a glance, sampled on the primitives
func _lip_at_a_glance() -> void:
	var runs := 0
	var bad_lip := []
	var bad_plain := []
	var base := Color(1, 0, 1)
	var jobs: Array = []
	for id in ["l001", "l003", "l005", "l009"]:
		jobs.append([id, MazeWorlds.for_number(MazeLevels.ids().find(id) + 1)])
	for w in [MazeWorlds.World.JUNGLE, MazeWorlds.World.CAVE]:
		jobs.append(["l001", w])
	for job: Array in jobs:
		var lv := MazeLevels.load_level(job[0])
		var skin := MazeSkins.skin(job[1])
		var pal: Dictionary = skin["pal"]
		var plain: Dictionary = skin.duplicate()
		plain["tufts"] = false # moss blades are lip coloured on purpose and may touch the contour
		var chunks := {}
		var lip: Color = pal["lip"]
		var lipish: Array[Color] = [pal["lip"], pal["lip_hi"], pal["lip_lo"]]
		for y in lv.height:
			for x in lv.width:
				var cell := Vector2i(x, y)
				var kind := lv.cell(x, y)
				if kind != MazeLevel.Cell.SOLID and kind != MazeLevel.Cell.NO_RING:
					continue
				var n := MazeStaticLayer.CHUNK
				var key := Vector2i(x / n, y / n)
				if not chunks.has(key):
					chunks[key] = MazeTileShapes.chunk(lv, plain, {}, key.x, key.y)
				var list: Array = chunks[key]
				var near := _near(list, Rect2(Vector2(cell) * 40.0, Vector2(40, 40)).grow(2.0))
				var any_air := false
				var joints := MazeTileShapes.joint_corners(lv, cell)
				for f in 4:
					any_air = any_air or MazeSkin.side(lv, cell, f) == MazeSkin.Side.AIR
					var origin := Vector2((cell + MazeSkin.START[f]) * 40)
					var along := Vector2(MazeSkin.ALONG[f])
					var inward := Vector2(MazeSkin.INWARD[f])
					if MazeStaticLayer.lip_drawn(lv, cell, f):
						for t in [0.25, 0.5, 0.75]:
							if _corner_trim_near(lv, cell, f, t, joints):
								continue
							runs += 1
							var line: Array[Color] = []
							for i in 40:
								line.append(_colour_at(near, origin + along * 40.0 * t + inward * (0.25 + 0.5 * i), base))
							if not _lip_profile_ok(line, pal, lipish, base):
								bad_lip.append("%s %s %s f%d t%.2f" % [job[0], job[1], cell, f, t])
					elif kind == MazeLevel.Cell.NO_RING or MazeSkin.side(lv, cell, f) != MazeSkin.Side.AIR:
						var side_kind := MazeSkin.side(lv, cell, f)
						if kind == MazeLevel.Cell.SOLID and side_kind == MazeSkin.Side.SAME:
							continue
						for i in 32:
							var c := _colour_at(near, origin + along * 20.0 + inward * (0.25 + 0.5 * i), base)
							if not _same_colour(c, base) and MazeArt.contrast(lip, c) < 1.3:
								bad_plain.append("%s %s %s f%d" % [job[0], job[1], cell, f])
								break
				if kind == MazeLevel.Cell.SOLID and not any_air:
					for gy in 4:
						for gx in 4:
							var q := Vector2(5 + gx * 10, 5 + gy * 10)
							if _in_joint(q, joints):
								continue
							var c := _colour_at(near, Vector2(cell) * 40.0 + q, base)
							if not _same_colour(c, base) and MazeArt.contrast(lip, c) < 1.3:
								bad_plain.append("%s %s %s inside %s" % [job[0], job[1], cell, q])
	_check.call(runs > 100 and bad_lip.is_empty(), "S7 every ring face shows contour, lip and a dark edge (%d samples, bad %s)" % [runs, bad_lip.slice(0, 4)])
	_check.call(bad_plain.is_empty(), "S7 nothing lip-like where no ring can go (bad %s)" % [bad_plain.slice(0, 4)])


## true when the sample lies within the trim of a perpendicular ring face (a convex corner) or a corner joint
func _corner_trim_near(lv: MazeLevel, cell: Vector2i, face: int, t: float, joints: Array[int]) -> bool:
	if t == 0.5:
		return false
	for ci in 4:
		var near: int = MazeSkin.CORNER_P[ci] if t > 0.5 else MazeSkin.CORNER_Q[ci]
		if near != face:
			continue
		var other: int = MazeSkin.CORNER_Q[ci] if t > 0.5 else MazeSkin.CORNER_P[ci]
		return MazeSkin.rim_face(lv, cell, other) or joints.has(ci)
	return false


## contour at least 2 px, then lip colours at least 5 px within 2 px, then a dark enough colour within 4 px
func _lip_profile_ok(line: Array[Color], pal: Dictionary, lipish: Array[Color], base: Color) -> bool:
	var i := 0
	while i < line.size() and _same_colour(line[i], base):
		i += 1
	var start := i
	while i < line.size() and _same_colour(line[i], pal["contour"]):
		i += 1
	if (i - start) * 0.5 < 2.0:
		return false
	var gap_end := mini(i + 4, line.size())
	while i < gap_end and not _is_any(line[i], lipish):
		i += 1
	var run_start := i
	while i < line.size() and _is_any(line[i], lipish):
		i += 1
	if (i - run_start) * 0.5 < 5.0:
		return false
	for j in range(i, mini(i + 8, line.size())):
		if MazeArt.contrast(pal["lip"], line[j]) >= 1.8:
			return true
	return false


func _is_any(c: Color, list: Array[Color]) -> bool:
	for v in list:
		if _same_colour(c, v):
			return true
	return false


func _in_joint(q: Vector2, corners: Array[int]) -> bool:
	for ci in corners:
		var pos := Vector2(MazeSkin.CORNER_POS[ci]) * 40.0
		if absf(q.x - pos.x) <= 14.0 and absf(q.y - pos.y) <= 14.0:
			return true
	return false


func _random_level() -> MazeLevel:
	var rng := WhiteRng.from_text("decor-fixture")
	var edits := {}
	for y in 64:
		for x in 64:
			var r := rng.range_int(0, 99)
			edits[Vector2i(x, y)] = "." if r < 62 else ("#" if r < 90 else ("X" if r < 95 else "^"))
	var lv := H.level(H.rows(64, 64, edits))
	lv.id = "random"
	return lv


## every level in every world, and the random map in every world
func _maps() -> Array:
	var out: Array = []
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		for w in MazeWorlds.COUNT:
			out.append([id, w, lv])
	var random := _random_level()
	for w in MazeWorlds.COUNT:
		out.append(["random", w, random])
	return out


func _inside_rect(list: Array, rect: Rect2) -> bool:
	for s: Dictionary in list:
		var one: Array[Dictionary] = [s]
		if not rect.grow(0.01).encloses(MazeDecor.bounds(one)):
			return false
	return true


func _pts_inside(pts: PackedVector2Array, rect: Rect2) -> bool:
	for p in pts:
		if not rect.grow(0.01).has_point(p):
			return false
	return not pts.is_empty()


## S4
func _never_larger() -> void:
	var bad := []
	for job: Array in _maps():
		var lv: MazeLevel = job[2]
		var skin := MazeSkins.skin(job[1])
		var stones := {}
		var slabs := {}
		for y in lv.height:
			for x in lv.width:
				var c := Vector2i(x, y)
				var rect := Rect2(Vector2(c) * 40.0, Vector2(40, 40))
				var kind := lv.cell(x, y)
				if kind == MazeLevel.Cell.SOLID or kind == MazeLevel.Cell.NO_RING:
					for inner in [false, true]:
						if not _pts_inside(MazeSkin.outline(lv, skin, c, inner), rect):
							bad.append("outline %s %s %s" % [job[0], job[1], c])
					for f in 4:
						for i in 6:
							if MazeSkin.rim_d(lv, skin, c, f, i) < 0:
								bad.append("rim_d %s" % c)
				if kind == MazeLevel.Cell.SOLID:
					var out: Array[Dictionary] = []
					MazeTileShapes._trims(out, lv, skin, c)
					if not _inside_rect(out, rect):
						bad.append("trims %s %s %s" % [job[0], job[1], c])
					var st := MazeSkin.stone_of(lv, skin, c)
					if not stones.has(st.position):
						stones[st.position] = true
						var parts: Array[Dictionary] = []
						MazeTileShapes._stone(parts, lv, skin, st)
						if not _inside_rect(parts, Rect2(Vector2(st.position) * 40.0, Vector2(st.size) * 40.0)):
							bad.append("stone %s %s %s" % [job[0], job[1], st])
				elif kind == MazeLevel.Cell.NO_RING:
					var sl := MazeSkin.slab_of(lv, c)
					if not slabs.has(sl.position):
						slabs[sl.position] = true
						var parts: Array[Dictionary] = []
						MazeTileShapes._slab(parts, lv, skin, sl)
						if not _inside_rect(parts, Rect2(Vector2(sl.position) * 40.0, Vector2(sl.size) * 40.0)):
							bad.append("slab %s %s %s" % [job[0], job[1], sl])
		var door := Rect2(Vector2(lv.finish) * 40.0, Vector2(40, 40))
		var parts: Array[Dictionary] = []
		MazeTileShapes._door(parts, skin["pal"], door.position)
		if not _inside_rect(parts, door):
			bad.append("door %s %s" % [job[0], job[1]])
	for shape in MazeSkin.SPIKE_SHAPES:
		var skin: Dictionary = MazeSkins.skin(MazeSkin.SPIKE_SHAPES.find(shape)).duplicate()
		var parts: Array[Dictionary] = []
		MazeTileShapes._spikes(parts, skin, Vector2.ZERO)
		if not _inside_rect(parts, Rect2(0, 0, 40, 40)):
			bad.append("spike %s" % shape)
	_check.call(bad.is_empty(), "S4 nothing is drawn outside its cell, stone or slab (%s)" % [bad.slice(0, 4)])


## S5
func _continuity() -> void:
	var steps := 0
	var bad := []
	for job: Array in _maps():
		var lv: MazeLevel = job[2]
		var skin := MazeSkins.skin(job[1])
		for y in lv.height:
			for x in lv.width:
				var c := Vector2i(x, y)
				for f in 4:
					var m: Vector2i = c + MazeSkin.ALONG[f]
					if MazeSkin.rim_face(lv, c, f) and MazeSkin.rim_face(lv, m, f):
						steps += 1
						if MazeSkin.rim_d(lv, skin, c, f, 5) != MazeSkin.rim_d(lv, skin, m, f, 0):
							bad.append("%s %s f%d" % [job[0], c, f])
	_check.call(steps > 100 and bad.is_empty(), "S5 shared vertices get one offset (%d pairs, %s)" % [steps, bad.slice(0, 3)])
	var crossing := 0
	var same := true
	for id in ["l003", "l006", "l009"]:
		var lv := MazeLevels.load_level(id)
		var skin := MazeSkins.skin(MazeWorlds.for_number(MazeLevels.ids().find(id) + 1))
		var first := MazeTileShapes.chunk(lv, skin, {}, 0, 0)
		same = same and var_to_str(first) == var_to_str(MazeTileShapes.chunk(lv, skin, {}, 0, 0))
		var n := MazeStaticLayer.CHUNK
		var lists := {}
		for y in lv.height:
			for x in lv.width:
				var c := Vector2i(x, y)
				if lv.cell(x, y) != MazeLevel.Cell.SOLID:
					continue
				var st := MazeSkin.stone_of(lv, skin, c)
				var last := st.end - Vector2i.ONE
				if st.position.x / n == last.x / n and st.position.y / n == last.y / n:
					continue
				crossing += 1
				var parts: Array[Dictionary] = []
				MazeTileShapes._stone(parts, lv, skin, st)
				for corner in [st.position, last]:
					var key := Vector2i(corner.x / n, corner.y / n)
					if not lists.has(key):
						lists[key] = MazeTileShapes.chunk(lv, skin, {}, key.x, key.y)
					same = same and _has_run(lists[key], parts) and MazeSkin.stone_of(lv, skin, corner) == st
	_check.call(crossing > 0 and same, "S5 stones over a chunk border are the same primitives in both chunks (%d)" % crossing)
	var slab_ok := true
	var lv9 := MazeLevels.load_level("l009")
	var skin9 := MazeSkins.skin(MazeWorlds.World.CAVE)
	for cx in 2:
		for cy in 2:
			slab_ok = slab_ok and var_to_str(MazeTileShapes.chunk(lv9, skin9, {}, cx, cy)) == var_to_str(MazeTileShapes.chunk(lv9, skin9, {}, cx, cy))
	_check.call(same and slab_ok, "S5 two builds give equal primitive lists")


## the primitives of part appear in list as one run
func _has_run(list: Array, part: Array[Dictionary]) -> bool:
	if part.is_empty():
		return true
	for i in list.size() - part.size() + 1:
		if _same_prim(list[i], part[0]):
			var ok := true
			for j in part.size():
				ok = ok and _same_prim(list[i + j], part[j])
			if ok:
				return true
	return false


func _same_prim(a: Dictionary, b: Dictionary) -> bool:
	return var_to_str(a) == var_to_str(b)


## S6
func _precision() -> void:
	var bad := []
	for job: Array in _maps():
		if job[0] == "random":
			continue
		var lv: MazeLevel = job[2]
		var skin := MazeSkins.skin(job[1])
		for y in lv.height:
			for x in lv.width:
				var c := Vector2i(x, y)
				if lv.cell(x, y) != MazeLevel.Cell.SOLID:
					continue
				var top := y * 40.0
				for p in MazeSkin.outline(lv, skin, c, false):
					if MazeSkin.rim_face(lv, c, MazeLevel.Face.UP) and p.y > top + 0.001 and p.y <= top + 3.001:
						if p.x - x * 40.0 > 3.001 and (x + 1) * 40.0 - p.x > 3.001:
							bad.append("floor %s %s %s" % [job[0], c, p])
				for f in 4:
					for i in 6:
						var d := MazeSkin.rim_d(lv, skin, c, f, i)
						var cap := MazeSkin.THIN_RIM_MAX if MazeSkin.side(lv, c, MazeSkin.OPPOSITE[f]) == MazeSkin.Side.AIR else MazeSkin.RIM_MAX
						if d > cap or (f == MazeLevel.Face.UP and d != 0):
							bad.append("rim_d %s %s f%d" % [job[0], c, f])
				for corner in 4:
					var k := MazeSkin.chip(lv, skin, c, corner)
					var p: int = MazeSkin.CORNER_P[corner]
					var q: int = MazeSkin.CORNER_Q[corner]
					if k > 3 and (p == MazeLevel.Face.UP or q == MazeLevel.Face.UP):
						bad.append("chip %s %s" % [job[0], c])
	_check.call(bad.is_empty(), "S6 floors straight, offsets and chips within bounds (%s)" % [bad.slice(0, 4)])
	_precision_l003()
	_precision_l006()


func _precision_l003() -> void:
	var lv := MazeLevels.load_level("l003")
	var skin := MazeSkins.skin(MazeWorlds.World.TEMPLE)
	var pillar := MazeSkin.outline(lv, skin, Vector2i(24, 11), false)
	var flat := true
	for p in pillar:
		flat = flat and (p.y <= 440.001 or p.y > 443.0 or false)
		flat = flat and not (p.y > 440.001 and p.y <= 443.0)
	_check.call(
		flat and pillar.has(Vector2(960, 440)) and pillar.has(Vector2(1000, 440)),
		"S6 the pillar top is exactly y = 440 from x = 960 to 1000 without chips"
	)
	var out: Array[Dictionary] = []
	MazeTileShapes._trims(out, lv, skin, Vector2i(24, 11))
	var lip_box := Rect2()
	var first := true
	for s: Dictionary in out:
		if s["t"] == "poly" and s["col"] == skin["pal"]["lip"]:
			var one: Array[Dictionary] = [s]
			var b := MazeDecor.bounds(one, true)
			lip_box = b if first else lip_box.merge(b)
			first = false
	_check.call(
		absf(lip_box.position.x - 963.0) < 0.01 and absf(lip_box.end.x - 997.0) < 0.01,
		"S6 the pillar trim runs from x = 963 to 997 (%s)" % lip_box
	)
	var ledge := Vector2i(10, 11)
	var chip := MazeSkin.chip(lv, skin, ledge, MazeSkin.Corner.TL)
	var straight := true
	for p in MazeSkin.outline(lv, skin, ledge, false):
		straight = straight and (p.y <= 440.001 or p.y > 443.0 or p.x < 400.0 + 3.001)
	_check.call((chip == 2 or chip == 3) and straight, "S6 the ledge at (10, 11) has a chip of 2 or 3 px and a straight floor")
	_check.call(MazeSkin.chip(lv, skin, Vector2i(19, 11), MazeSkin.Corner.TR) == 0, "S6 the ledge at (19, 11) next to spikes stays square")
	_check.call(
		MazeSkin.chip(lv, skin, Vector2i(2, 11), MazeSkin.Corner.TR) > 0
		and not MazeSkin.rim_face(lv, Vector2i(0, 11), MazeLevel.Face.UP),
		"S6 the spawn floor has a chip at its end and no trim under the X column"
	)
	var slab := MazeSkin.slab_of(lv, Vector2i(0, 5))
	var o := MazeSkin.slab_outline(lv, skin, slab)
	var left_flush := o.has(Vector2(0, 5 * 40 + 1.5)) and o.has(Vector2(0, 11 * 40 - 1.5))
	_check.call(slab == Rect2i(0, 5, 1, 6) and left_flush and not o.has(Vector2(37, 5 * 40 + 1.5)), "S6 the X column is one slab, flush left, rounded right")
	var wall_ok := MazeSkin.rim_d(lv, skin, Vector2i(28, 10), MazeLevel.Face.LEFT, 0) == 0
	var wall_max := 0
	for y in range(6, 11):
		for i in 6:
			wall_max = maxi(wall_max, MazeSkin.rim_d(lv, skin, Vector2i(28, y), MazeLevel.Face.LEFT, i))
	_check.call(wall_ok and wall_max <= 2 and MazeSkin.chip(lv, skin, Vector2i(28, 6), MazeSkin.Corner.TL) > 0, "S6 the wall before the door is crumbly up to 2 px, 0 at the spikes, chipped on top")
	var ceiling := 0
	var flush := true
	for x in range(1, 47):
		for i in 6:
			ceiling = maxi(ceiling, MazeSkin.rim_d(lv, skin, Vector2i(x, 0), MazeLevel.Face.DOWN, i))
		for p in MazeSkin.outline(lv, skin, Vector2i(x, 0), false):
			flush = flush and p.y >= 0.0
	_check.call(ceiling > 0 and ceiling <= 2 and flush, "S6 the ceiling of l003 is crumbly up to 2 px")


func _precision_l006() -> void:
	var lv := MazeLevels.load_level("l006")
	var skin := MazeSkins.skin(MazeWorlds.World.JUNGLE)
	var ok := true
	for x in [9, 13, 17]:
		var top := 0
		while not lv.solid(x, top):
			top += 1
		var o := MazeSkin.outline(lv, skin, Vector2i(x, top), false)
		for p in o:
			ok = ok and (p.y <= top * 40.0 + 0.001 or p.y > top * 40.0 + 3.001 or p.x - x * 40.0 <= 3.001 or (x + 1) * 40.0 - p.x <= 3.001)
		var y := top
		while lv.cell(x, y) == MazeLevel.Cell.SOLID and lv.cell(x, y + 1) == MazeLevel.Cell.SOLID:
			for f in [MazeLevel.Face.LEFT, MazeLevel.Face.RIGHT]:
				for i in 6:
					ok = ok and MazeSkin.rim_d(lv, skin, Vector2i(x, y), f, i) <= 2
			y += 1
		for f in [MazeLevel.Face.LEFT, MazeLevel.Face.RIGHT]:
			ok = ok and MazeSkin.rim_d(lv, skin, Vector2i(x, y), f, 0) == 0
	_check.call(ok, "S6 the l006 towers have straight tops, walls of at most 2 px and no offset at the spikes")


## S10
func _groups() -> void:
	var bad := []
	var big_cave := 0
	var big_temple := 0
	var running := true
	for job: Array in _maps():
		var lv: MazeLevel = job[2]
		var skin := MazeSkins.skin(job[1])
		for y in lv.height:
			for x in lv.width:
				var c := Vector2i(x, y)
				var kind := lv.cell(x, y)
				if kind == MazeLevel.Cell.SOLID:
					var st := MazeSkin.stone_of(lv, skin, c)
					var ok := st.has_point(c) and st.size.x <= 2 and st.size.y <= 2 and (st.size.x == st.size.y or st.size.y == 1)
					for yy in range(st.position.y, st.end.y):
						for xx in range(st.position.x, st.end.x):
							ok = ok and lv.cell(xx, yy) == MazeLevel.Cell.SOLID and MazeSkin.stone_of(lv, skin, Vector2i(xx, yy)) == st
					if not ok:
						bad.append("stone %s %s %s" % [job[0], job[1], c])
					if job[0] == "random" and st.size == Vector2i(2, 2):
						big_cave += 1 if job[1] == MazeWorlds.World.CAVE else 0
						big_temple += 1 if job[1] == MazeWorlds.World.TEMPLE else 0
					if job[0] == "random" and job[1] == MazeWorlds.World.TEMPLE and st.size == Vector2i(2, 1):
						running = running and st.position.x % 2 == st.position.y % 2
				elif kind == MazeLevel.Cell.NO_RING:
					var sl := MazeSkin.slab_of(lv, c)
					var ok := sl.has_point(c) and (sl.size.x == 1 or sl.size.y == 1)
					for yy in range(sl.position.y, sl.end.y):
						for xx in range(sl.position.x, sl.end.x):
							ok = ok and _x_at(lv, xx, yy) and MazeSkin.slab_of(lv, Vector2i(xx, yy)) == sl
					var row0 := x
					while _x_at(lv, row0 - 1, y):
						row0 -= 1
					var row1 := x
					while _x_at(lv, row1 + 1, y):
						row1 += 1
					if row1 > row0:
						ok = ok and sl == Rect2i(row0, y, row1 - row0 + 1, 1)
					if not ok:
						bad.append("slab %s %s %s" % [job[0], job[1], c])
	_check.call(bad.is_empty(), "S10 stones and slabs are consistent groups (%s)" % [bad.slice(0, 4)])
	_check.call(big_cave > 0 and big_temple == 0 and running, "S10 cave has 2 x 2 stones (%d), temple none, 2 x 1 follows the running bond" % big_cave)


func _x_at(lv: MazeLevel, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < lv.width and y < lv.height and lv.cell(x, y) == MazeLevel.Cell.NO_RING


func _keys_argument() -> void:
	var o := MazeMain.parse_args(PackedStringArray(["--keys=R10,T139,R51"]))
	_check.call(o["keys"] == "R10 T139 R51", "--keys accepts commas for spaces")


## every polygon the layer draws can be triangulated, on the shipped levels and the random map
func _polygons_valid() -> void:
	var bad := []
	var count := 0
	for job: Array in _maps():
		var lv: MazeLevel = job[2]
		var skin := MazeSkins.skin(job[1])
		var n := MazeStaticLayer.CHUNK
		for cy in ceili(float(lv.height) / n):
			for cx in ceili(float(lv.width) / n):
				for s: Dictionary in MazeTileShapes.chunk(lv, skin, {}, cx, cy):
					if s["t"] == "poly" or s["t"] == "vpoly":
						count += 1
						if Geometry2D.triangulate_polygon(s["pts"]).is_empty():
							bad.append("%s %s chunk %d,%d" % [job[0], job[1], cx, cy])
	_check.call(count > 1000 and bad.is_empty(), "S4 every polygon triangulates (%d, bad %s)" % [count, bad.slice(0, 3)])


## S11, S12, S9
func _spikes_rings() -> void:
	var hz: Array[Color] = [MazeWorlds.HAZARD, MazeWorlds.HAZARD_HI, MazeWorlds.HAZARD_DARK, MazeWorlds.HAZARD_LINE]
	var today := {
		"spear": PackedVector2Array([Vector2(1, 40), Vector2(10, 20), Vector2(19, 40)]),
		"thorn": PackedVector2Array([Vector2(1, 40), Vector2(6, 30), Vector2(11, 20), Vector2(14, 30), Vector2(19, 40)]),
		"crystal": PackedVector2Array(
			[Vector2(1, 40), Vector2(4, 27), Vector2(8, 20), Vector2(12, 20), Vector2(16, 27), Vector2(19, 40)]
		),
	}
	for w in MazeWorlds.COUNT:
		var skin := MazeSkins.skin(w)
		var parts: Array[Dictionary] = []
		MazeTileShapes._spikes(parts, skin, Vector2.ZERO)
		var colours := true
		for s: Dictionary in parts:
			var c: Color = s["col"]
			colours = colours and hz.has(Color(c, 1.0))
		var outline_ok: bool = parts[0]["pts"] == today[skin["spikes"]]
		_check.call(colours and parts.size() > 8 and outline_ok, "S11 %s pins: shared colours, today's outline" % MazeWorlds.NAMES[w])
	for flash in [false, true]:
		var st := MazeWorldView.ring_strokes(flash)
		var white: Color = WhiteTheme.ACCENT if flash else MazeWorlds.RING
		_check.call(
			st.size() == 4 and st[2] == [MazeWorldView.RING_OUTLINE_W, MazeWorldView.RING_OUTLINE]
			and st[3] == [MazeWorldView.RING_STROKE, white] and st[0][0] > st[1][0] and st[1][0] > st[2][0],
			"S12 ring strokes (flash %s): glows, outline, white last" % flash
		)
	_check.call(
		MazeSkin.CONTOUR_W >= 2.0 * (MazeLilith.OUTLINE_LINE / 2.0) and MazeLilith.OUTLINE_LINE == 3.0
		and MazeLilith.OUTLINE_CIRCLE == 1.5 and MazeLilith.OUTLINE == Color("#120E10", 0.85)
		and MazeWorldView.RING_OUTLINE_W > MazeWorldView.RING_STROKE,
		"S9 the block contour is at least twice Lilith's outline per side, her outline is unchanged"
	)
