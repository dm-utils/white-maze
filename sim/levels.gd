class_name MazeLevels
extends RefCounted
## The fixed series: levels/index.json and one levels/<id>.json per level.

const DIR := "res://levels/"


## ids in series order; [] when the index is missing or bad
static func ids(dir: String = DIR) -> PackedStringArray:
	var out := PackedStringArray()
	var data := WhitePuzzleStore.load_json(dir.path_join("index.json"))
	var list: Variant = data.get("levels")
	if not list is Array:
		return out
	for v in list:
		if v is String:
			out.append(v)
	return out


## a missing or bad file gives a level with errors, never null
static func load_level(id: String, dir: String = DIR) -> MazeLevel:
	var path := dir.path_join(id + ".json")
	var lv: MazeLevel
	if not FileAccess.file_exists(path):
		lv = MazeLevel.new()
		lv.errors.append("level file %s is missing" % path)
		return lv
	var data := WhitePuzzleStore.load_json(path)
	lv = MazeLevel.from_dict(data if not data.is_empty() else null)
	if data.is_empty():
		lv.errors = PackedStringArray(["level file %s is not a JSON object" % path])
	elif lv.id != "" and lv.id != id:
		lv.errors.append("id '%s' does not match file name '%s'" % [lv.id, id])
	return lv
