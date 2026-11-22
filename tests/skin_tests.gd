extends RefCounted
## Skins (design 21): data packs and engine rules (S2, S3, S8), geometry, shapes, bake. Grows with the card steps.

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
