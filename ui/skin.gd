class_name MazeSkin
extends RefCounted
## Engine rules of a tile skin: constants, pack validation, resolving, palette checks (design 21.4, 21.13). Packs are
## data (MazeSkins); what keeps the game readable (lip, pins, door, outlines) lives here and never in a pack.

enum Side { SAME, AIR, SPIKE, SEAM, EDGE }
enum Corner { TL, TR, BR, BL }
enum Mode { OUTER, INNER, STONE, SLAB } # which insets an outline uses (21.5.1)

const FORMAT := 1
const T := 40
const CONTOUR_W := 3.0 # dark band inside the edge towards air, spikes and X
const SEAM_W := 1.5 # per side of a # / X seam
const SLAB_GAP := 3.0 # between two X slabs
const SLAB_RADIUS := 6.0
const TRIM_UP := 8.0 # lip trim width on floors
const TRIM_SIDE := 6.0 # on walls and ceilings
const TRIM_HI_W := 2.0
const TRIM_LO_W := 1.5
const TRIM_SHADOW_W := 2.5
const TRIM_SHADOW_ALPHA := 0.55
const RIM_STEP := 8 # px between edge vertices; 6 vertices per side
const RIM_MAX := 3 # walls and ceilings
const THIN_RIM_MAX := 2 # a side whose opposite side is also air
const FLOOR_CHIP_MAX := 3 # corners next to a floor
const CHIP_MAX := 6
const CONTOUR_DARKEN := 0.82 # contour = block.darkened(CONTOUR_DARKEN)
const DOOR_FRAME_LIGHTEN := 0.15
const SHEEN_ALPHAS := [0.18, 0.45, 0.4] # wide band, thin line, top line
const MOTIF_MARGIN := 4.0
const LIP_TINTS := {
	"sand": ["#F3E0AE", "#F8E6B2", "#CFAE70"], # lip, lip_hi, lip_lo
	"moss": ["#9BD36A", "#B8E68A", "#6A9E45"],
	"frost": ["#A9C6E4", "#B9D2EC", "#7B98BA"],
}
const SPIKE_SHAPES := ["spear", "thorn", "crystal"]
const BACK_PATTERNS := ["masonry", "courses", "strata"]
const MOTIFS := ["glyph", "moss", "crack", "crystal"]
const BONDS := ["running", "stack"]
const PALETTE_KEYS := [
	"void", "back_top", "back_bottom", "back_line", "back_decor", "block", "block_hi", "block_lo", "joint", "mortar",
	"speck", "motif", "noring", "noring_hi", "noring_lo", "noring_edge", "sheen", "detail", "light",
]
const ENGINE_KEYS := [
	"contour", "outline", "lip_hi", "lip_lo", "door_frame", "door_light", "ring", "hazard", "hazard_hi",
	"hazard_dark", "hazard_line", "trim", "floor_rim",
]
const PACK_KEYS := ["format", "id", "names", "palette", "lip", "spikes", "back", "stones", "rim", "motifs", "tufts"]
const STONE_KEYS := ["pair", "big", "bond", "chamfer", "bevel", "shade", "mortar"]
const RIM_KEYS := ["wall", "ceiling", "chip"]
const SALT_RIM := 60 # + face (60..63)
const SALT_CHIP := 64
const SALT_BIG := 65
const SALT_PAIR := 66
const SALT_SHADE := 67
const SALT_MOTIF := 68 # + motif index (68, 69)
const SALT_MOTIF_POS := 70 # .. 75
const SALT_SLAB := 76
const ARC_STEPS := 4 # points per quarter circle: 5

# memo of one level and skin between begin() and end(); filled by the geometry functions, never needed for results
static var _memo_level: MazeLevel = null
static var _memo_skin := {}
static var _memo_side := PackedByteArray() # side kind per cell and face, 255 where not solid
static var _memo_amp := {}
static var _memo_d := {}

# indexed by MazeLevel.Face (UP, DOWN, LEFT, RIGHT); screen coordinates, outline runs clockwise
const START: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, 0)]
const ALONG: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const INWARD: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
const OPPOSITE: Array[int] = [1, 0, 3, 2]
const CLOCKWISE: Array[int] = [0, 3, 1, 2] # UP, RIGHT, DOWN, LEFT
const CORNER_P: Array[int] = [2, 0, 3, 1] # side that ends at TL, TR, BR, BL
const CORNER_Q: Array[int] = [0, 3, 1, 2] # side that starts there
const CORNER_POS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]


## empty when usable; one line per problem, "<path>: <problem>"
static func validate(pack: Dictionary) -> PackedStringArray:
	var err := PackedStringArray()
	for key: Variant in pack:
		if str(key) in ENGINE_KEYS:
			err.append("%s: engine-owned" % key)
		elif str(key) not in PACK_KEYS:
			err.append("%s: unknown key" % key)
	for key in PACK_KEYS:
		if not pack.has(key):
			err.append("%s: missing" % key)
	if not err.is_empty():
		return err
	if not _is_int(pack["format"]) or int(pack["format"]) != FORMAT:
		err.append("format: must be %d" % FORMAT)
	if not (pack["id"] is String) or not _id_ok(pack["id"]):
		err.append("id: must match ^[a-z0-9-]{1,32}$")
	_validate_names(pack["names"], err)
	_validate_palette(pack["palette"], err)
	if not (pack["lip"] is String) or not LIP_TINTS.has(pack["lip"]):
		err.append("lip: unknown tint")
	if pack["spikes"] not in SPIKE_SHAPES:
		err.append("spikes: unknown shape")
	if pack["back"] not in BACK_PATTERNS:
		err.append("back: unknown pattern")
	_validate_stones(pack["stones"], err)
	_validate_rim(pack["rim"], err)
	_validate_motifs(pack["motifs"], err)
	if not (pack["tufts"] is bool):
		err.append("tufts: must be a boolean")
	if err.is_empty():
		err.append_array(check_palette(resolve(pack)["pal"]))
	return err


## numbers clamped, colours parsed, engine keys added; expects a pack that passes validate
static func resolve(pack: Dictionary) -> Dictionary:
	var pal := {}
	var src: Dictionary = pack["palette"]
	for key in PALETTE_KEYS:
		pal[key] = Color(str(src[key]))
	var tint: Array = LIP_TINTS[pack["lip"]]
	pal["lip"] = Color(tint[0])
	pal["lip_hi"] = Color(tint[1])
	pal["lip_lo"] = Color(tint[2])
	pal["contour"] = (pal["block"] as Color).darkened(CONTOUR_DARKEN)
	pal["door_frame"] = (pal["block"] as Color).lightened(DOOR_FRAME_LIGHTEN)
	var st: Dictionary = pack["stones"]
	var rim: Dictionary = pack["rim"]
	var motifs: Array = []
	for m: Dictionary in pack["motifs"]:
		motifs.append({"kind": str(m["kind"]), "chance": clampi(int(m["chance"]), 0, 50)})
	return {
		"id": str(pack["id"]),
		"lip": str(pack["lip"]),
		"spikes": str(pack["spikes"]),
		"back": str(pack["back"]),
		"tufts": bool(pack["tufts"]),
		"stones":
		{
			"pair": clampi(int(st["pair"]), 0, 100),
			"big": clampi(int(st["big"]), 0, 100),
			"bond": str(st["bond"]),
			"chamfer": clampf(float(st["chamfer"]), 2.0, 6.0),
			"bevel": clampf(float(st["bevel"]), 2.0, 4.0),
			"shade": clampf(float(st["shade"]), 0.0, 0.15),
			"mortar": clampf(float(st["mortar"]), 1.5, 4.0),
		},
		"rim":
		{
			"wall": clampi(int(rim["wall"]), 0, RIM_MAX),
			"ceiling": clampi(int(rim["ceiling"]), 0, RIM_MAX),
			"chip": clampi(int(rim["chip"]), 0, CHIP_MAX),
		},
		"motifs": motifs,
		"pal": pal,
	}


## resolve(pack) when valid, else the temple skin and a warning
static func from_pack(pack: Dictionary) -> Dictionary:
	var err := validate(pack)
	if err.is_empty():
		return resolve(pack)
	push_warning("skin pack %s rejected: %s" % [pack.get("id", "?"), "; ".join(err)])
	return resolve(MazeSkins.TEMPLE)


## the rules of 21.13.1 on a resolved palette; ids "C1".."C15"; tints and pin outline are parameters for tests
static func check_palette(
	pal: Dictionary, tints: Dictionary = LIP_TINTS, pin_line: Color = MazeWorlds.HAZARD_LINE
) -> PackedStringArray:
	var err := PackedStringArray()
	var lip: Color = pal["lip"]
	var block: Color = pal["block"]
	var top: Color = pal["back_top"]
	var bottom: Color = pal["back_bottom"]
	if MazeArt.contrast(lip, block) < 1.8:
		err.append("C1: lip against block below 1.8")
	if MazeArt.contrast(lip, pal["block_hi"]) < 1.5:
		err.append("C2: lip against block_hi below 1.5")
	# the top line sits on the lit edge of the slab, the thin lines on the body
	var top_line: Color = (pal["noring_hi"] as Color).lerp(pal["sheen"], SHEEN_ALPHAS[2])
	var thin_line: Color = (pal["noring"] as Color).lerp(pal["sheen"], SHEEN_ALPHAS[1])
	var lighter: Array[Color] = [
		pal["block_hi"], pal["joint"], pal["mortar"], pal["speck"], pal["motif"], pal["noring_hi"], top_line,
		thin_line, pal["door_frame"],
	]
	for c in lighter:
		if MazeArt.luminance(lip) <= MazeArt.luminance(c) or MazeArt.contrast(lip, c) < 1.3:
			err.append("C3: lip is not the lightest colour (%s)" % c.to_html(false))
	var lum := func(key: String) -> float: return MazeArt.luminance(pal[key])
	var order := [
		["block_lo", "block"], ["block", "block_hi"], ["joint", "block"], ["mortar", "block_lo"],
		["noring_lo", "noring"], ["noring", "noring_hi"], ["noring_edge", "noring"], ["lip_lo", "lip"],
		["lip", "lip_hi"],
	]
	for pair: Array in order:
		if lum.call(pair[0]) >= lum.call(pair[1]):
			err.append("C4: %s is not darker than %s" % pair)
	if MazeArt.contrast(pal["contour"], block) < 3.0:
		err.append("C5: contour against block below 3.0")
	if MazeArt.contrast(pal["mortar"], block) < 2.0:
		err.append("C6: mortar against block below 2.0")
	for back: Color in [top, bottom]:
		if MazeArt.contrast(pal["noring"], back) < 1.5:
			err.append("C7: X against the back wall below 1.5")
		if MazeArt.contrast(MazeWorlds.HAZARD, back) < 3.0:
			err.append("C9: hazard against the back wall below 3")
		for key in ["back_decor", "back_line"]:
			if MazeArt.contrast(pal[key], back) > 1.6:
				err.append("C10: %s above 1.6 against the back wall" % key)
		if MazeArt.contrast(MazeLilith.HAIR, back) < 3.0:
			err.append("C13: hair against the back wall below 3.0")
	if MazeArt.contrast(lip, pal["noring_hi"]) < 2.0:
		err.append("C8: lip against noring_hi below 2.0")
	for key: String in pal:
		var c: Color = pal[key]
		if _near_white(c):
			err.append("C11: %s is near white" % key)
		if _near_hazard(c):
			err.append("C12: %s is near the hazard hue" % key)
	if MazeArt.contrast(pal["door_frame"], top) < 2.0:
		err.append("C14: door frame against the back wall below 2.0")
	for tint_name: String in tints:
		for hex: String in tints[tint_name]:
			var c := Color(hex)
			if _near_white(c) or _near_hazard(c):
				err.append("C15: lip tint %s is near white or the hazard" % tint_name)
	if MazeArt.luminance(pin_line) >= MazeArt.luminance(MazeWorlds.HAZARD_DARK):
		err.append("C15: the pin outline is not darker than the dark pin")
	return err


static func _near_white(c: Color) -> bool:
	return c.s < 0.2 and c.v > 0.8


static func _near_hazard(c: Color) -> bool:
	var d := absf(c.h - MazeWorlds.HAZARD.h) * 360.0
	return minf(d, 360.0 - d) < 15.0 and c.s > 0.4 and c.v > 0.45


static func _is_int(v: Variant) -> bool:
	return v is int or (v is float and v == floorf(v))


static func _id_ok(s: String) -> bool:
	if s.length() < 1 or s.length() > 32:
		return false
	for i in s.length():
		var ch := s.unicode_at(i)
		if not ((ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57) or ch == 45):
			return false
	return true


static func _hex_ok(v: Variant) -> bool:
	if not (v is String) or v.length() != 7 or not v.begins_with("#"):
		return false
	return v.substr(1).is_valid_hex_number(false)


static func _in_range(v: Variant, lo: float, hi: float) -> bool:
	return (v is int or v is float) and float(v) >= lo and float(v) <= hi


static func _whole_in(v: Variant, lo: int, hi: int) -> bool:
	return _is_int(v) and int(v) >= lo and int(v) <= hi


static func _validate_names(names: Variant, err: PackedStringArray) -> void:
	if not (names is Dictionary):
		err.append("names: must be an object")
		return
	for key: Variant in names:
		if str(key) not in ["nl", "en"]:
			err.append("names.%s: unknown key" % key)
	for lang in ["nl", "en"]:
		if not names.has(lang) or not (names[lang] is String) or (names[lang] as String).is_empty():
			err.append("names.%s: must be a non-empty string" % lang)


static func _validate_palette(pal: Variant, err: PackedStringArray) -> void:
	if not (pal is Dictionary):
		err.append("palette: must be an object")
		return
	for key: Variant in pal:
		if str(key) in ENGINE_KEYS or str(key) == "lip":
			err.append("palette.%s: engine-owned" % key)
		elif str(key) not in PALETTE_KEYS:
			err.append("palette.%s: unknown key" % key)
	for key in PALETTE_KEYS:
		if not pal.has(key):
			err.append("palette.%s: missing" % key)
		elif not _hex_ok(pal[key]):
			err.append("palette.%s: must be #RRGGBB" % key)


static func _validate_stones(st: Variant, err: PackedStringArray) -> void:
	if not (st is Dictionary):
		err.append("stones: must be an object")
		return
	for key: Variant in st:
		if str(key) not in STONE_KEYS:
			err.append("stones.%s: unknown key" % key)
	for key in STONE_KEYS:
		if not st.has(key):
			err.append("stones.%s: missing" % key)
	if not err.is_empty():
		return
	for key in ["pair", "big"]:
		if not _whole_in(st[key], 0, 100):
			err.append("stones.%s: whole number 0 to 100" % key)
	if st["bond"] not in BONDS:
		err.append("stones.bond: running or stack")
	if not _in_range(st["chamfer"], 2.0, 6.0):
		err.append("stones.chamfer: 2 to 6")
	if not _in_range(st["bevel"], 2.0, 4.0):
		err.append("stones.bevel: 2 to 4")
	if not _in_range(st["shade"], 0.0, 0.15):
		err.append("stones.shade: 0 to 0.15")
	if not _in_range(st["mortar"], 1.5, 4.0):
		err.append("stones.mortar: 1.5 to 4")


static func _validate_rim(rim: Variant, err: PackedStringArray) -> void:
	if not (rim is Dictionary):
		err.append("rim: must be an object")
		return
	for key: Variant in rim:
		if str(key) not in RIM_KEYS:
			err.append("rim.%s: unknown key" % key)
	for key in RIM_KEYS:
		var hi := CHIP_MAX if key == "chip" else RIM_MAX
		if not rim.has(key) or not _whole_in(rim[key], 0, hi):
			err.append("rim.%s: whole number 0 to %d" % [key, hi])


static func _validate_motifs(motifs: Variant, err: PackedStringArray) -> void:
	if not (motifs is Array):
		err.append("motifs: must be a list")
		return
	if motifs.size() > 2:
		err.append("motifs: at most 2 entries")
	for i in motifs.size():
		var m: Variant = motifs[i]
		if not (m is Dictionary) or not m.has("kind") or not m.has("chance"):
			err.append("motifs[%d]: needs kind and chance" % i)
			continue
		if m["kind"] not in MOTIFS:
			err.append("motifs[%d].kind: unknown motif" % i)
		if not _whole_in(m["chance"], 0, 50):
			err.append("motifs[%d].chance: whole number 0 to 50" % i)


## speeds up the geometry functions of one level and skin until end(); results never change
static func begin(level: MazeLevel, skin: Dictionary) -> void:
	if level == _memo_level and is_same(skin, _memo_skin):
		return
	_memo_level = level
	_memo_skin = skin
	_memo_amp.clear()
	_memo_d.clear()
	_memo_side.resize(level.width * level.height * 4)
	_memo_side.fill(255)
	for y in level.height:
		for x in level.width:
			var kind := level.cell(x, y)
			if kind == MazeLevel.Cell.SOLID or kind == MazeLevel.Cell.NO_RING:
				for f in 4:
					_memo_side[(y * level.width + x) * 4 + f] = _side(level, Vector2i(x, y), f)


static func in_scope(level: MazeLevel, skin: Dictionary) -> bool:
	return level == _memo_level and is_same(skin, _memo_skin)


static func end() -> void:
	_memo_level = null
	_memo_skin = {}
	_memo_side.clear()
	_memo_amp.clear()
	_memo_d.clear()


static func _key(cell: Vector2i, face: int) -> int:
	return (cell.y * 8192 + cell.x) * 4 + face


## what lies in front of a face of a # or X cell
static func side(level: MazeLevel, cell: Vector2i, face: int) -> int:
	if level == _memo_level and cell.x >= 0 and cell.y >= 0 and cell.x < level.width and cell.y < level.height:
		var v := _memo_side[(cell.y * level.width + cell.x) * 4 + face]
		if v != 255:
			return v
	return _side(level, cell, face)


static func _side(level: MazeLevel, cell: Vector2i, face: int) -> int:
	var n: Vector2i = cell + MazeLevel.FACE_STEP[face]
	if n.x < 0 or n.y < 0 or n.x >= level.width or n.y >= level.height:
		return Side.EDGE
	var other := level.cell(n.x, n.y)
	if other == MazeLevel.Cell.EMPTY:
		return Side.AIR
	if other == MazeLevel.Cell.SPIKE:
		return Side.SPIKE
	return Side.SAME if other == level.cell(cell.x, cell.y) else Side.SEAM


## a # face towards air: the faces that carry a ring and a trim; equals MazeStaticLayer.lip_drawn
static func rim_face(level: MazeLevel, cell: Vector2i, face: int) -> bool:
	return level.cell(cell.x, cell.y) == MazeLevel.Cell.SOLID and side(level, cell, face) == Side.AIR


## largest inward offset of a side in px; floors are straight
static func rim_amp(level: MazeLevel, skin: Dictionary, cell: Vector2i, face: int) -> int:
	if level != _memo_level or not is_same(skin, _memo_skin):
		return _rim_amp(level, skin, cell, face)
	var key := _key(cell, face)
	if not _memo_amp.has(key):
		_memo_amp[key] = _rim_amp(level, skin, cell, face)
	return _memo_amp[key]


static func _rim_amp(level: MazeLevel, skin: Dictionary, cell: Vector2i, face: int) -> int:
	if face == MazeLevel.Face.UP or not rim_face(level, cell, face):
		return 0
	var a: int = skin["rim"]["ceiling"] if face == MazeLevel.Face.DOWN else skin["rim"]["wall"]
	if side(level, cell, OPPOSITE[face]) == Side.AIR:
		a = mini(a, THIN_RIM_MAX)
	return a


## world px of vertex i (0..5) of a side
static func vertex(cell: Vector2i, face: int, i: int) -> Vector2i:
	return (cell + START[face]) * T + ALONG[face] * (RIM_STEP * i)


## inward offset of vertex i of a side, whole px, 0 at corners and where the face line ends
static func rim_d(level: MazeLevel, skin: Dictionary, cell: Vector2i, face: int, i: int) -> int:
	var amp := rim_amp(level, skin, cell, face)
	if amp == 0:
		return 0
	if level != _memo_level or not is_same(skin, _memo_skin):
		return _rim_d(level, skin, cell, face, i, amp)
	var key := _key(cell, face) * 8 + i
	if not _memo_d.has(key):
		_memo_d[key] = _rim_d(level, skin, cell, face, i, amp)
	return _memo_d[key]


static func _rim_d(level: MazeLevel, skin: Dictionary, cell: Vector2i, face: int, i: int, amp: int) -> int:
	var v := vertex(cell, face, i)
	var h := MazeArt.pick(v.x, v.y, SALT_RIM + face, RIM_MAX + 1)
	if i >= 1 and i <= 4:
		return mini(h, amp)
	var m: Vector2i = cell + ALONG[face] if i == 5 else cell - ALONG[face]
	if rim_face(level, m, face):
		return mini(h, mini(amp, rim_amp(level, skin, m, face)))
	return 0


## chip size at a convex corner (Corner enum), 0 when the corner is not chipped
static func chip(level: MazeLevel, skin: Dictionary, cell: Vector2i, corner: int) -> int:
	var p: int = CORNER_P[corner]
	var q: int = CORNER_Q[corner]
	if side(level, cell, p) != Side.AIR or side(level, cell, q) != Side.AIR or not rim_face(level, cell, p):
		return 0
	return _chip_size(skin, cell, corner, p, q)


static func _chip_size(skin: Dictionary, cell: Vector2i, corner: int, p: int, q: int) -> int:
	var k := (cell + CORNER_POS[corner]) * T
	var cap := FLOOR_CHIP_MAX if p == MazeLevel.Face.UP or q == MazeLevel.Face.UP else CHIP_MAX
	return maxi(0, mini(skin["rim"]["chip"], cap) - MazeArt.pick(k.x, k.y, SALT_CHIP, 2))


## inset of a side from the tile boundary, by outline mode
static func inset(skin: Dictionary, kind: int, mode: int) -> float:
	if mode == Mode.OUTER or kind == Side.EDGE:
		return 0.0
	match kind:
		Side.AIR, Side.SPIKE:
			return CONTOUR_W
		Side.SEAM:
			return SEAM_W
	match mode:
		Mode.STONE:
			return float(skin["stones"]["mortar"]) / 2.0
		Mode.SLAB:
			return SLAB_GAP / 2.0
	return 0.0


## closed polygon of a # or X cell: silhouette (inner = false) or inside the contour, seams and mortar (inner = true)
static func outline(level: MazeLevel, skin: Dictionary, cell: Vector2i, inner: bool) -> PackedVector2Array:
	return _rect_outline(level, skin, Rect2i(cell, Vector2i.ONE), Mode.INNER if inner else Mode.OUTER)


## corner point before any chip, with edge offsets and insets of its two sides
static func corner_base(level: MazeLevel, skin: Dictionary, cell: Vector2i, corner: int, mode: int) -> Vector2:
	var p: int = CORNER_P[corner]
	var q: int = CORNER_Q[corner]
	var k := Vector2((cell + CORNER_POS[corner]) * T)
	var ip := inset(skin, side(level, cell, p), mode)
	var iq := inset(skin, side(level, cell, q), mode)
	var dp := rim_d(level, skin, cell, p, 5) + ip
	var dq := rim_d(level, skin, cell, q, 0) + iq
	return k + Vector2(INWARD[p]) * dp + Vector2(INWARD[q]) * dq


## 2 x 2 lattice stone, else a 2 x 1 pair on the bond, else the cell itself
static func stone_of(level: MazeLevel, skin: Dictionary, cell: Vector2i) -> Rect2i:
	var a := Vector2i(cell.x - cell.x % 2, cell.y - cell.y % 2)
	if _big(level, skin, a):
		return Rect2i(a, Vector2i(2, 2))
	var off := cell.y % 2 if skin["stones"]["bond"] == "running" else 0
	var px := cell.x - posmod(cell.x - off, 2)
	if _pair(level, skin, Vector2i(px, cell.y)):
		return Rect2i(px, cell.y, 2, 1)
	return Rect2i(cell, Vector2i.ONE)


static func _big(level: MazeLevel, skin: Dictionary, a: Vector2i) -> bool:
	if not MazeArt.chance(a.x, a.y, SALT_BIG, skin["stones"]["big"]):
		return false
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		if level.cell(a.x + d.x, a.y + d.y) != MazeLevel.Cell.SOLID:
			return false
	return true


static func _pair(level: MazeLevel, skin: Dictionary, p: Vector2i) -> bool:
	if not MazeArt.chance(p.x, p.y, SALT_PAIR, skin["stones"]["pair"]):
		return false
	for x in [p.x, p.x + 1]:
		if level.cell(x, p.y) != MazeLevel.Cell.SOLID:
			return false
		if _big(level, skin, Vector2i(x - x % 2, p.y - p.y % 2)):
			return false
	return true


## outline of a stone: perimeter with stone insets, chamfered corners
static func stone_outline(level: MazeLevel, skin: Dictionary, rect: Rect2i) -> PackedVector2Array:
	return _rect_outline(level, skin, rect, Mode.STONE)


## the run of X cells a cell belongs to: row run of 2 or more, else a column of cells that have no row neighbours
static func slab_of(level: MazeLevel, cell: Vector2i) -> Rect2i:
	var x0 := cell.x
	var x1 := cell.x
	while _is_x(level, x0 - 1, cell.y):
		x0 -= 1
	while _is_x(level, x1 + 1, cell.y):
		x1 += 1
	if x1 > x0:
		return Rect2i(x0, cell.y, x1 - x0 + 1, 1)
	var y0 := cell.y
	var y1 := cell.y
	while _lone_x(level, cell.x, y0 - 1):
		y0 -= 1
	while _lone_x(level, cell.x, y1 + 1):
		y1 += 1
	return Rect2i(cell.x, y0, 1, y1 - y0 + 1)


static func slab_outline(level: MazeLevel, skin: Dictionary, rect: Rect2i) -> PackedVector2Array:
	return _rect_outline(level, skin, rect, Mode.SLAB)


static func _is_x(level: MazeLevel, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < level.width and y < level.height and level.cell(x, y) == MazeLevel.Cell.NO_RING


static func _lone_x(level: MazeLevel, x: int, y: int) -> bool:
	return _is_x(level, x, y) and not _is_x(level, x - 1, y) and not _is_x(level, x + 1, y)


## cells of one side of a rect in outline order
static func _side_cells(rect: Rect2i, face: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x1 := rect.end.x - 1
	var y1 := rect.end.y - 1
	match face:
		MazeLevel.Face.UP:
			for x in range(rect.position.x, x1 + 1):
				out.append(Vector2i(x, rect.position.y))
		MazeLevel.Face.RIGHT:
			for y in range(rect.position.y, y1 + 1):
				out.append(Vector2i(x1, y))
		MazeLevel.Face.DOWN:
			for x in range(x1, rect.position.x - 1, -1):
				out.append(Vector2i(x, y1))
		_:
			for y in range(y1, rect.position.y - 1, -1):
				out.append(Vector2i(rect.position.x, y))
	return out


## perimeter of a rect of cells clockwise: corner points per mode (chip, chamfer, arc), side vertices in between
## unless they fall inside a corner treatment
static func _rect_outline(level: MazeLevel, skin: Dictionary, rect: Rect2i, mode: int) -> PackedVector2Array:
	if rect.size == Vector2i.ONE and (mode == Mode.OUTER or mode == Mode.INNER):
		var plain := _plain_outline(level, skin, rect.position, mode)
		if not plain.is_empty():
			return plain
	elif mode == Mode.STONE:
		var plain := _plain_stone(level, skin, rect)
		if not plain.is_empty():
			return plain
	var corners: Array[PackedVector2Array] = []
	var sides: Array[Array] = []
	for ci in 4:
		var f: int = CORNER_Q[ci]
		var cells := _side_cells(rect, f)
		sides.append(cells)
		corners.append(_corner_points(level, skin, cells[0], ci, mode))
	var pts := PackedVector2Array()
	for ci in 4:
		var f: int = CORNER_Q[ci]
		var cells: Array = sides[ci]
		pts.append_array(corners[ci])
		var after: PackedVector2Array = corners[(ci + 1) % 4]
		var lo := Vector2(corners[ci][-1]).dot(Vector2(ALONG[f])) + 0.01
		var hi := after[0].dot(Vector2(ALONG[f])) - 0.01
		var inward := Vector2(INWARD[f])
		for j in cells.size():
			var c: Vector2i = cells[j]
			var ins := inset(skin, side(level, c, f), mode)
			var first := 0 if j > 0 else 1
			var last := 5 if j < cells.size() - 1 else 4
			var amp := rim_amp(level, skin, c, f)
			for i in range(first, last + 1):
				if amp == 0 and i != 0 and i != 5:
					continue
				var v := Vector2(vertex(c, f, i)) + inward * (rim_d(level, skin, c, f, i) + ins)
				var a := v.dot(Vector2(ALONG[f]))
				if a > lo and a < hi:
					pts.append(v)
	return clean(pts)


## cell without a face towards air: no edge offsets and no chips, so a rectangle; empty otherwise
static func _plain_outline(level: MazeLevel, skin: Dictionary, cell: Vector2i, mode: int) -> PackedVector2Array:
	var ins: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for f in 4:
		var kind := side(level, cell, f)
		if kind == Side.AIR:
			return PackedVector2Array()
		ins[f] = inset(skin, kind, mode)
	var o := Vector2(cell * T)
	var x0 := o.x + ins[MazeLevel.Face.LEFT]
	var x1 := o.x + T - ins[MazeLevel.Face.RIGHT]
	var y0 := o.y + ins[MazeLevel.Face.UP]
	var y1 := o.y + T - ins[MazeLevel.Face.DOWN]
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## stone without a face towards air and one kind of neighbour per side: a rectangle with chamfered corners
static func _plain_stone(level: MazeLevel, skin: Dictionary, rect: Rect2i) -> PackedVector2Array:
	var ins: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for f in 4:
		var cells := _side_cells(rect, f)
		var kind := side(level, cells[0], f)
		for c in cells:
			if side(level, c, f) != kind or kind == Side.AIR:
				return PackedVector2Array()
		ins[f] = inset(skin, kind, Mode.STONE)
	var o := Vector2(rect.position * T)
	var x0 := o.x + ins[MazeLevel.Face.LEFT]
	var x1 := o.x + rect.size.x * T - ins[MazeLevel.Face.RIGHT]
	var y0 := o.y + ins[MazeLevel.Face.UP]
	var y1 := o.y + rect.size.y * T - ins[MazeLevel.Face.DOWN]
	var c := float(skin["stones"]["chamfer"])
	return PackedVector2Array(
		[
			Vector2(x0 + c, y0), Vector2(x1 - c, y0), Vector2(x1, y0 + c), Vector2(x1, y1 - c),
			Vector2(x1 - c, y1), Vector2(x0 + c, y1), Vector2(x0, y1 - c), Vector2(x0, y0 + c),
		]
	)


## corner of a rect by mode: chip (cells), chamfer (stone) or arc (slab, flat at the level edge)
static func _corner_points(
	level: MazeLevel, skin: Dictionary, cell: Vector2i, ci: int, mode: int
) -> PackedVector2Array:
	var p: int = CORNER_P[ci]
	var q: int = CORNER_Q[ci]
	var sp := side(level, cell, p)
	var sq := side(level, cell, q)
	var ip := inset(skin, sp, mode)
	var iq := inset(skin, sq, mode)
	var k := 0
	var dp := 0
	var dq := 0
	if sp == Side.AIR and sq == Side.AIR and level.cell(cell.x, cell.y) == MazeLevel.Cell.SOLID:
		k = _chip_size(skin, cell, ci, p, q) # offsets are 0 at a chipped corner
	else:
		dp = rim_d(level, skin, cell, p, 5)
		dq = rim_d(level, skin, cell, q, 0)
	var base := Vector2((cell + CORNER_POS[ci]) * T) + Vector2(INWARD[p]) * (dp + ip) + Vector2(INWARD[q]) * (dq + iq)
	var pts := PackedVector2Array()
	if mode == Mode.OUTER or mode == Mode.INNER:
		if k > 0:
			pts.append(base + Vector2(INWARD[q]) * k)
			pts.append(base + Vector2(INWARD[p]) * k)
		else:
			pts.append(base)
	elif mode == Mode.STONE:
		var c := float(skin["stones"]["chamfer"])
		if k > 0:
			c = maxf(c, k + 1.0)
		pts.append(base - Vector2(ALONG[p]) * c)
		pts.append(base + Vector2(ALONG[q]) * c)
	elif sp == Side.EDGE or sq == Side.EDGE:
		pts.append(base)
	else:
		var centre := base + (Vector2(INWARD[p]) + Vector2(INWARD[q])) * SLAB_RADIUS
		var u := base - Vector2(ALONG[p]) * SLAB_RADIUS - centre
		var w := base + Vector2(ALONG[q]) * SLAB_RADIUS - centre
		for i in ARC_STEPS + 1:
			var a := PI / 2.0 * i / ARC_STEPS
			pts.append(centre + u * cos(a) + w * sin(a))
	return pts


## drops repeated and collinear points of a closed polygon
static func clean(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[-1].distance_squared_to(p) > 0.000001:
			out.append(p)
	while out.size() > 1 and out[-1].distance_squared_to(out[0]) <= 0.000001:
		out.remove_at(out.size() - 1)
	if out.size() < 4:
		return out
	var keep := PackedVector2Array()
	var n := out.size()
	for i in n:
		var a: Vector2 = keep[-1] if not keep.is_empty() else out[n - 1]
		var b := out[i]
		var c := out[(i + 1) % n]
		if absf((b - a).cross(c - b)) > 0.0001:
			keep.append(b)
	return keep
