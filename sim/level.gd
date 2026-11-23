class_name MazeLevel
extends RefCounted
## One handmade level: metadata and a grid of tiles. Built with from_dict; invalid input never gives null, the
## problems are listed in errors.

enum Cell { EMPTY, SOLID, NO_RING, SPIKE, STEEP_R, STEEP_L, GENTLE_R_LO, GENTLE_R_HI, GENTLE_L_HI, GENTLE_L_LO }
enum Face { UP, DOWN, LEFT, RIGHT }

const CHARS := ".#X^/\\rRLl"
const FACE_NAMES := ["up", "down", "left", "right"]
const FACE_STEP: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const DIFFICULTIES := ["easy", "medium", "hard"]
const MIN_SIZE := Vector2i(8, 8)
const MAX_SIZE := Vector2i(256, 64)
const MAX_PAR := 20

var id := ""
var format := 1
var sky := false
var slope_count := 0
var names := {}
var difficulty := 0
var beads := 3
var par := 0
var hints := {}
var width := 0
var height := 0
var cells := PackedByteArray()
var spawn := Vector2i()
var finish := Vector2i()
var preset_rings: Array[Dictionary] = []
var errors := PackedStringArray()


static func from_dict(d: Variant) -> MazeLevel:
	var lv := MazeLevel.new()
	if not d is Dictionary:
		lv.errors.append("level is not an object")
		return lv
	lv._parse(d)
	return lv


static func _whole(v: Variant) -> bool:
	return (v is int) or (v is float and is_finite(v) and v == floorf(v))


static func _text_pair(v: Variant) -> bool:
	if not v is Dictionary:
		return false
	for key in ["nl", "en"]:
		if not (v.get(key) is String) or (v[key] as String).is_empty():
			return false
	return true


static func _valid_id(s: String) -> bool:
	if s.is_empty() or s.length() > 32:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45):
			return false
	return true


func valid() -> bool:
	return errors.is_empty()


## out of bounds left, right, top: NO_RING; below: EMPTY
func cell(x: int, y: int) -> int:
	if x < 0 or x >= width or y < 0:
		return Cell.NO_RING
	if y >= height:
		return Cell.EMPTY
	return cells[y * width + x]


func solid(x: int, y: int) -> bool:
	var c := cell(x, y)
	return c == Cell.SOLID or c == Cell.NO_RING


func slope(x: int, y: int) -> bool:
	return MazeSlope.is_slope(cell(x, y))


## a face with this cell in front is not exposed
func covered(x: int, y: int) -> bool:
	return solid(x, y) or slope(x, y)


## rows back as text, S and F at their cells
func render() -> PackedStringArray:
	var out := PackedStringArray()
	for y in height:
		var line := ""
		for x in width:
			var p := Vector2i(x, y)
			if p == spawn:
				line += "S"
			elif p == finish:
				line += "F"
			else:
				line += CHARS[cells[y * width + x]]
		out.append(line)
	return out


func _parse(d: Dictionary) -> void:
	if _whole(d.get("format")) and (int(d["format"]) == 1 or int(d["format"]) == 2):
		format = int(d["format"])
	else:
		errors.append("format must be 1 or 2")
	if d.has("sky"):
		if format != 2:
			errors.append("sky needs format 2")
		elif d["sky"] is bool:
			sky = d["sky"]
		else:
			errors.append("sky must be true or false")
	var raw_id: Variant = d.get("id")
	if raw_id is String and _valid_id(raw_id):
		id = raw_id
	else:
		errors.append("id %s does not match ^[a-z0-9-]{1,32}$" % str(raw_id))
	if _text_pair(d.get("name")):
		names = {"nl": d["name"]["nl"], "en": d["name"]["en"]}
	else:
		errors.append("name needs non-empty nl and en")
	var diff: Variant = d.get("difficulty")
	if diff is String and DIFFICULTIES.has(diff):
		difficulty = DIFFICULTIES.find(diff)
	else:
		errors.append("difficulty must be easy, medium or hard")
	if d.has("beads"):
		if _whole(d["beads"]) and int(d["beads"]) >= 1 and int(d["beads"]) <= 9:
			beads = int(d["beads"])
		else:
			errors.append("beads %s is outside 1..9" % str(d["beads"]))
	if _whole(d.get("par")) and int(d["par"]) >= 0 and int(d["par"]) <= MAX_PAR:
		par = int(d["par"])
	else:
		errors.append("par %s is outside 0..%d" % [str(d.get("par")), MAX_PAR])
	if d.has("hint"):
		if _text_pair(d["hint"]):
			hints = {"nl": d["hint"]["nl"], "en": d["hint"]["en"]}
		else:
			errors.append("hint needs non-empty nl and en")
	if _parse_rows(d.get("rows")):
		_parse_rings(d.get("rings", []))


## true when the grid is usable (rings can be checked against it)
func _parse_rows(rows: Variant) -> bool:
	if not rows is Array:
		errors.append("rows must be a list of strings")
		return false
	var list: Array = rows
	for r in list:
		if not r is String:
			errors.append("rows must be a list of strings")
			return false
	height = list.size()
	width = (list[0] as String).length() if height > 0 else 0
	var ok := true
	if width < MIN_SIZE.x or width > MAX_SIZE.x:
		errors.append("width %d is outside %d..%d" % [width, MIN_SIZE.x, MAX_SIZE.x])
		ok = false
	if height < MIN_SIZE.y or height > MAX_SIZE.y:
		errors.append("height %d is outside %d..%d" % [height, MIN_SIZE.y, MAX_SIZE.y])
		ok = false
	for y in height:
		if (list[y] as String).length() != width:
			errors.append("row %d has length %d, expected %d" % [y, (list[y] as String).length(), width])
			ok = false
	if not ok:
		return false
	cells.resize(width * height)
	var starts: Array[Vector2i] = []
	var finishes: Array[Vector2i] = []
	for y in height:
		var line: String = list[y]
		for x in width:
			var ch := line[x]
			var kind := Cell.EMPTY
			match ch:
				".":
					pass
				"#":
					kind = Cell.SOLID
				"X":
					kind = Cell.NO_RING
				"^":
					kind = Cell.SPIKE
				"/", "\\", "r", "R", "L", "l":
					if format == 2:
						kind = CHARS.find(ch)
						slope_count += 1
					else:
						errors.append("slope '%s' at (%d, %d) needs format 2" % [ch, x, y])
						ok = false
				"S":
					starts.append(Vector2i(x, y))
				"F":
					finishes.append(Vector2i(x, y))
				_:
					errors.append("unknown character '%s' at (%d, %d)" % [ch, x, y])
					ok = false
			cells[y * width + x] = kind
	if starts.size() != 1:
		errors.append("need exactly one S, found %d" % starts.size())
		ok = false
	if finishes.size() != 1:
		errors.append("need exactly one F, found %d" % finishes.size())
		ok = false
	if starts.size() == 1:
		spawn = starts[0]
		if not solid(spawn.x, spawn.y + 1):
			errors.append("nothing solid below S at (%d, %d)" % [spawn.x, spawn.y])
	if finishes.size() == 1:
		finish = finishes[0]
	if slope_count > 0:
		_check_slopes(starts)
	return ok


## V1 to V4 of design 23.4.3
func _check_slopes(starts: Array[Vector2i]) -> void:
	for y in height:
		for x in width:
			var kind: int = cells[y * width + x]
			if not MazeSlope.is_slope(kind):
				continue
			var at := "(%d, %d)" % [x, y]
			var below := cell(x, y + 1)
			if y + 1 >= height or not (below == Cell.SOLID or below == Cell.NO_RING):
				errors.append("slope at %s needs # or X below" % at)
			if y > 0 and (cell(x, y - 1) != Cell.EMPTY or starts.has(Vector2i(x, y - 1))):
				errors.append("slope at %s needs empty space above" % at)
			var partner := _partner(kind)
			if not partner.is_empty() and cell(x + partner["dx"], y) != partner["kind"]:
				errors.append("gentle slope '%s' at %s needs '%s' to its %s" % [
						CHARS[kind], at, CHARS[partner["kind"]], "right" if partner["dx"] > 0 else "left"])
			if kind == Cell.STEEP_R or kind == Cell.STEEP_L or kind == Cell.GENTLE_R_LO or kind == Cell.GENTLE_L_LO:
				var lx := x + MazeSlope.downhill(kind)
				var low := cell(lx, y)
				if lx < 0 or lx >= width or not (low == Cell.EMPTY or low == Cell.SPIKE):
					errors.append("slope at %s has a blocked low side" % at)


static func _partner(kind: int) -> Dictionary:
	match kind:
		Cell.GENTLE_R_LO:
			return {"kind": Cell.GENTLE_R_HI, "dx": 1}
		Cell.GENTLE_R_HI:
			return {"kind": Cell.GENTLE_R_LO, "dx": -1}
		Cell.GENTLE_L_HI:
			return {"kind": Cell.GENTLE_L_LO, "dx": 1}
		Cell.GENTLE_L_LO:
			return {"kind": Cell.GENTLE_L_HI, "dx": -1}
	return {}


func _parse_rings(rings: Variant) -> void:
	if not rings is Array:
		errors.append("rings must be a list")
		return
	var seen := {}
	var index := 0
	for r in rings:
		index += 1
		if not (r is Dictionary and _whole(r.get("x")) and _whole(r.get("y")) and r.get("face") is String):
			errors.append("ring %d needs integer x, y and a face" % index)
			continue
		var cell_pos := Vector2i(int(r["x"]), int(r["y"]))
		var face: int = FACE_NAMES.find(r["face"])
		if face < 0:
			errors.append("ring %d has unknown face '%s'" % [index, r["face"]])
			continue
		var label := "ring at (%d, %d) %s" % [cell_pos.x, cell_pos.y, r["face"]]
		if cell(cell_pos.x, cell_pos.y) != Cell.SOLID:
			errors.append("%s is not on a # block" % label)
			continue
		var front := cell_pos + FACE_STEP[face]
		if covered(front.x, front.y) or cell(front.x, front.y) == Cell.SPIKE:
			errors.append("%s is not exposed" % label)
			continue
		var key := cell_pos.x * 4096 + cell_pos.y * 4 + face
		if seen.has(key):
			errors.append("duplicate %s" % label)
			continue
		seen[key] = true
		preset_rings.append({"cell": cell_pos, "face": face})
