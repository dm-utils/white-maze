class_name MazeSkin
extends RefCounted
## Engine rules of a tile skin: constants, pack validation, resolving, palette checks (design 21.4, 21.13). Packs are
## data (MazeSkins); what keeps the game readable (lip, pins, door, outlines) lives here and never in a pack.

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
const SHEEN_ALPHAS := [0.18, 0.45, 0.5] # wide band, thin line, top line
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
	var sheen_on: Color = (pal["noring"] as Color).lerp(pal["sheen"], SHEEN_ALPHAS[2])
	var lighter: Array[Color] = [
		pal["block_hi"], pal["joint"], pal["mortar"], pal["speck"], pal["motif"], pal["noring_hi"], sheen_on,
		pal["door_frame"],
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
