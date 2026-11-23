class_name MazeChain
extends RefCounted
## The chain: used rings as beads, first preset launches as knots, in event order (design 22). Pure, only reads
## simulation events and replays run scripts.

enum Kind { BEAD, KNOT }

const MAX_LINKS := 64 # longer chains are drawn up to here and never stored
const MAX_LINKS_TEXT := 1024
const MAX_CODE := 1100
const CODE_TAG := "wm1"
const FACE_LETTERS := "udlr" # index = MazeLevel.Face
const BACKFILL_MAX_TICKS := 7200
const MAX_X := 255
const MAX_Y := 63


## call once after every sim.step; seen and links belong to one attempt
static func note(events: Array, level: MazeLevel, seen: Dictionary, links: Array) -> void:
	for e: Dictionary in events:
		if e["type"] != "launch":
			continue
		if e["counted"]:
			links.append({"kind": Kind.BEAD, "cell": e["cell"], "face": e["face"]})
			continue
		var id := key(e["cell"], e["face"])
		if seen.has(id) or not _is_preset(level, e["cell"], e["face"]):
			continue
		seen[id] = true
		links.append({"kind": Kind.KNOT, "cell": e["cell"], "face": e["face"]})


## {"ok", "finished", "ticks", "rings", "links"}; ok false when the script does not parse
static func from_run(level: MazeLevel, script: String, max_ticks: int = 36000) -> Dictionary:
	var out := {"ok": false, "finished": false, "ticks": 0, "rings": 0, "links": []}
	var parsed := MazeRunScript.parse(script)
	if not parsed["ok"]:
		return out
	var sim := MazeSim.new(level)
	var seen := {}
	var links: Array = []
	for input: MazeInput in parsed["inputs"]:
		sim.step(input)
		note(sim.events, level, seen, links)
		if sim.finished():
			break
	var idle := MazeInput.idle()
	while not sim.finished() and sim.tick < max_ticks:
		sim.step(idle)
		note(sim.events, level, seen, links)
	out["ok"] = true
	out["finished"] = sim.finished()
	out["ticks"] = sim.time_ticks()
	out["rings"] = sim.rings_used
	out["links"] = links
	return out


static func encode(links: Array) -> String:
	var parts := PackedStringArray()
	for l: Dictionary in links:
		parts.append("%s%s%d.%d" % ["b" if l["kind"] == Kind.BEAD else "k", FACE_LETTERS[l["face"]],
				l["cell"].x, l["cell"].y])
	return "-".join(parts)


## {"ok", "links", "error"}; the empty text is the empty chain
static func parse(text: String) -> Dictionary:
	var links: Array = []
	if text.length() > MAX_LINKS_TEXT:
		return _fail("links text is longer than %d" % MAX_LINKS_TEXT)
	if text.is_empty():
		return {"ok": true, "links": links, "error": ""}
	var tokens := text.split("-", true)
	if tokens.size() > MAX_LINKS:
		return _fail("more than %d links" % MAX_LINKS)
	for token in tokens:
		var link := _parse_link(token)
		if link.is_empty():
			return _fail("bad link '%s'" % token.left(16))
		links.append(link)
	return {"ok": true, "links": links, "error": ""}


static func bead_count(links: Array) -> int:
	var n := 0
	for l: Dictionary in links:
		if l["kind"] == Kind.BEAD:
			n += 1
	return n


## every cell inside the grid
static func fits(level: MazeLevel, links: Array) -> bool:
	for l: Dictionary in links:
		var c: Vector2i = l["cell"]
		if c.x < 0 or c.y < 0 or c.x >= level.width or c.y >= level.height:
			return false
	return true


static func record(rings: int, ticks: int, links: Array) -> Dictionary:
	return {"rings": rings, "ticks": ticks, "links": encode(links)}


## a beats b: fewest rings, then fastest; an empty b is always beaten
static func better(a: Dictionary, b: Dictionary) -> bool:
	if b.is_empty():
		return true
	if a.is_empty():
		return false
	if a["rings"] != b["rings"]:
		return a["rings"] < b["rings"]
	return a["ticks"] < b["ticks"]


## "" when the code would exceed MAX_CODE
static func code(level_id: String, rings: int, par: int, ticks: int, links_text: String) -> String:
	var text := "%s/%s/%d/%d/%d/%s" % [CODE_TAG, level_id, rings, par, ticks, links_text]
	return text if text.length() <= MAX_CODE else ""


## {"ok", "level", "rings", "par", "ticks", "links", "error"}
static func parse_code(text: String) -> Dictionary:
	var out := {"ok": false, "level": "", "rings": 0, "par": 0, "ticks": 0, "links": [], "error": ""}
	if text.length() > MAX_CODE:
		out["error"] = "code is longer than %d" % MAX_CODE
		return out
	var fields := text.split("/", true)
	if fields.size() != 6 or fields[0] != CODE_TAG:
		out["error"] = "expected %s and six fields" % CODE_TAG
		return out
	if not MazeLevel._valid_id(fields[1]):
		out["error"] = "bad level id"
		return out
	for i in [2, 3, 4]:
		if not _is_number(fields[i]):
			out["error"] = "bad number '%s'" % fields[i].left(16)
			return out
	var parsed := parse(fields[5])
	if not parsed["ok"]:
		out["error"] = parsed["error"]
		return out
	if bead_count(parsed["links"]) != int(fields[2]):
		out["error"] = "bead count differs from rings"
		return out
	out["ok"] = true
	out["level"] = fields[1]
	out["rings"] = int(fields[2])
	out["par"] = int(fields[3])
	out["ticks"] = int(fields[4])
	out["links"] = parsed["links"]
	return out


## unique int per cell and face
static func key(cell: Vector2i, face: int) -> int:
	return cell.x * 4096 + cell.y * 4 + face


static func _is_preset(level: MazeLevel, cell: Vector2i, face: int) -> bool:
	for r in level.preset_rings:
		if r["cell"] == cell and r["face"] == face:
			return true
	return false


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "links": [], "error": message}


## whole number without leading zeros, at most 9 digits
static func _is_number(s: String) -> bool:
	if s.is_empty() or s.length() > 9 or (s.length() > 1 and s[0] == "0"):
		return false
	for i in s.length():
		if s.unicode_at(i) < 48 or s.unicode_at(i) > 57:
			return false
	return true


## {} when malformed
static func _parse_link(token: String) -> Dictionary:
	if token.length() < 5 or (token[0] != "b" and token[0] != "k"):
		return {}
	var face := FACE_LETTERS.find(token[1])
	if face < 0:
		return {}
	var coords := token.substr(2).split(".", true)
	if coords.size() != 2 or not _is_number(coords[0]) or not _is_number(coords[1]):
		return {}
	var x := int(coords[0])
	var y := int(coords[1])
	if x > MAX_X or y > MAX_Y:
		return {}
	return {"kind": Kind.BEAD if token[0] == "b" else Kind.KNOT, "cell": Vector2i(x, y), "face": face}
