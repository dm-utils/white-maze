extends RefCounted
## L1-L4: shipped levels, validation rules, out-of-bounds cells, the check tool as a child process.

const H := preload("res://tests/helpers.gd")
const TMP := "user://white_maze_test_levels"


func run(check: Callable, _node: Node) -> void:
	_shipped(check)
	_validation(check)
	_cells(check)
	_loader(check)
	_tool(check)


func _shipped(check: Callable) -> void:
	var ids := MazeLevels.ids()
	check.call(ids == PackedStringArray(["l001", "l002", "l003"]), "the index lists l001, l002, l003 in order")
	var diffs := []
	for id in ids:
		var lv := MazeLevels.load_level(id)
		check.call(lv.valid(), "%s is valid (%s)" % [id, str(lv.errors)])
		var file := WhitePuzzleStore.load_json("res://levels/%s.json" % id)
		check.call(lv.render() == PackedStringArray(file["rows"]), "%s: render() gives the file rows back" % id)
		check.call(
			lv.id == id and lv.beads == 3 and lv.par >= 1 and lv.par <= MazeLevel.MAX_PAR, "%s: id, beads and par" % id
		)
		check.call(
			lv.hints.has("nl") and lv.hints.has("en") and lv.names["nl"] != "" and lv.names["en"] != "",
			"%s: names and hints in both languages" % id
		)
		diffs.append(lv.difficulty)
	check.call(diffs == [0, 1, 2], "difficulties are easy, medium, hard")
	var l1 := MazeLevels.load_level("l001")
	check.call(
		l1.width == 48 and l1.height == 14 and l1.spawn == Vector2i(2, 10) and l1.finish == Vector2i(44, 5),
		"l001 size, spawn and finish"
	)
	check.call(
		(
			l1.preset_rings.size() == 1
			and l1.preset_rings[0]["cell"] == Vector2i(26, 11)
			and l1.preset_rings[0]["face"] == MazeLevel.Face.UP
		),
		"l001 preset ring"
	)
	check.call(MazeLevels.load_level("l003").preset_rings.is_empty(), "l003 has no preset rings")


func _base() -> Dictionary:
	return {
		"format": 1,
		"id": "t001",
		"name": {"nl": "T", "en": "T"},
		"difficulty": "easy",
		"beads": 3,
		"par": 1,
		"hint": {"nl": "a", "en": "b"},
		"rows": ["........", "........", "........", "..S.....", "........", "........", ".....F..", "########"],
	}


func _rows_with(edits: Dictionary) -> Array:
	var rows: Array = _base()["rows"].duplicate()
	for key in edits:
		var line: String = rows[key.y]
		rows[key.y] = line.substr(0, key.x) + edits[key] + line.substr(key.x + 1)
	return rows


func _validation(check: Callable) -> void:
	# the S in the base rows has nothing below it; give it a block for the valid base
	var valid_rows := _rows_with({Vector2i(2, 4): "#"})
	var base := _base()
	base["rows"] = valid_rows
	var ok := MazeLevel.from_dict(base)
	check.call(
		ok.valid() and ok.spawn == Vector2i(2, 3) and ok.finish == Vector2i(5, 6),
		"the base level of the validation tests is valid (%s)" % str(ok.errors)
	)
	var cases := [
		["not an object", null, "level is not an object"],
		["format", {"format": 2}, "format must be 1"],
		["id", {"id": "L1"}, "id L1 does not match ^[a-z0-9-]{1,32}$"],
		["name", {"name": {"nl": "x"}}, "name needs non-empty nl and en"],
		["difficulty", {"difficulty": "extreme"}, "difficulty must be easy, medium or hard"],
		["beads", {"beads": 0}, "beads 0 is outside 1..9"],
		["par", {"par": 21}, "par 21 is outside 0..20"],
		["par negative", {"par": -1}, "par -1 is outside 0..20"],
		["hint", {"hint": {"nl": "x"}}, "hint needs non-empty nl and en"],
		["rows type", {"rows": "abc"}, "rows must be a list of strings"],
		["rows entry", {"rows": [1, 2]}, "rows must be a list of strings"],
		[
			"width",
			{"rows": ["#######", "#######", "#######", "#######", "#######", "#######", "#######", "#######"]},
			"width 7 is outside 8..256"
		],
		["height", {"rows": valid_rows.slice(0, 7)}, "height 7 is outside 8..64"],
		[
			"ragged",
			{
				"rows":
				_rows_with({}).map(func(r: String) -> String: return r.substr(0, 7) if r.begins_with("..S") else r)
			},
			"row 3 has length 7, expected 8"
		],
		["character", {"rows": _with(valid_rows, Vector2i(5, 2), "Q")}, "unknown character 'Q' at (5, 2)"],
		["two S", {"rows": _with(valid_rows, Vector2i(6, 1), "S")}, "need exactly one S, found 2"],
		["no F", {"rows": _with(valid_rows, Vector2i(5, 6), ".")}, "need exactly one F, found 0"],
		["two F", {"rows": _with(valid_rows, Vector2i(1, 1), "F")}, "need exactly one F, found 2"],
		["nothing below S", {"rows": _rows_with({})}, "nothing solid below S at (2, 3)"],
		["rings type", {"rows": valid_rows, "rings": 5}, "rings must be a list"],
		["ring shape", {"rows": valid_rows, "rings": [{"x": 1}]}, "ring 1 needs integer x, y and a face"],
		[
			"ring face",
			{"rows": valid_rows, "rings": [{"x": 4, "y": 7, "face": "sideways"}]},
			"ring 1 has unknown face 'sideways'"
		],
		[
			"ring on empty",
			{"rows": valid_rows, "rings": [{"x": 4, "y": 3, "face": "up"}]},
			"ring at (4, 3) up is not on a # block"
		],
		[
			"ring on X",
			{"rows": _with(valid_rows, Vector2i(4, 7), "X"), "rings": [{"x": 4, "y": 7, "face": "up"}]},
			"ring at (4, 7) up is not on a # block"
		],
		[
			"ring outside",
			{"rows": valid_rows, "rings": [{"x": 40, "y": 7, "face": "up"}]},
			"ring at (40, 7) up is not on a # block"
		],
		[
			"ring not exposed",
			{"rows": _with(valid_rows, Vector2i(4, 6), "#"), "rings": [{"x": 4, "y": 7, "face": "up"}]},
			"ring at (4, 7) up is not exposed"
		],
		[
			"ring under spike",
			{"rows": _with(valid_rows, Vector2i(4, 6), "^"), "rings": [{"x": 4, "y": 7, "face": "up"}]},
			"ring at (4, 7) up is not exposed"
		],
		[
			"ring duplicate",
			{"rows": valid_rows, "rings": [{"x": 4, "y": 7, "face": "up"}, {"x": 4, "y": 7, "face": "up"}]},
			"duplicate ring at (4, 7) up"
		],
	]
	for c in cases:
		var d: Variant
		if c[1] == null:
			d = []
		else:
			d = _base()
			d["rows"] = valid_rows
			d.merge(c[1], true)
		var lv := MazeLevel.from_dict(d)
		check.call(lv.errors == PackedStringArray([c[2]]), "%s: exactly '%s' (got %s)" % [c[0], c[2], str(lv.errors)])
	var good := _base()
	good["rows"] = _with(valid_rows, Vector2i(4, 6), "#")
	good["rings"] = [{"x": 4, "y": 6, "face": "up"}, {"x": 4, "y": 6, "face": "left"}]
	var with_rings := MazeLevel.from_dict(good)
	check.call(
		with_rings.valid() and with_rings.preset_rings.size() == 2,
		"two rings on different faces of one block are valid (%s)" % str(with_rings.errors)
	)
	good = _base()
	good["rows"] = valid_rows
	good.erase("beads")
	good.erase("hint")
	var defaults := MazeLevel.from_dict(good)
	check.call(
		defaults.valid() and defaults.beads == 3 and defaults.hints.is_empty(),
		"beads default to 3 and the hint is optional"
	)
	check.call(
		(
			MazeLevel
			. from_dict(
				{
					"format": 1.0,
					"id": "t",
					"name": {"nl": "a", "en": "b"},
					"difficulty": "hard",
					"par": 0.0,
					"rows": valid_rows
				}
			)
			. valid()
		),
		"whole floats from JSON are accepted"
	)
	var par_base := _base()
	par_base["rows"] = valid_rows
	var par_ok := true
	for case in [[0, 1], [1, 1], [5, 3], [20, 1], [20, 9]]:
		par_base["par"] = case[0]
		par_base["beads"] = case[1]
		par_ok = par_ok and MazeLevel.from_dict(par_base).valid()
	check.call(par_ok, "par 0..20 is valid whatever the number of beads")


func _with(rows: Array, at: Vector2i, ch: String) -> Array:
	var out := rows.duplicate()
	var line: String = out[at.y]
	out[at.y] = line.substr(0, at.x) + ch + line.substr(at.x + 1)
	return out


func _cells(check: Callable) -> void:
	var lv := H.level(H.rows(10, 8))
	check.call(
		(
			lv.cell(-1, 3) == MazeLevel.Cell.NO_RING
			and lv.cell(10, 3) == MazeLevel.Cell.NO_RING
			and lv.cell(3, -1) == MazeLevel.Cell.NO_RING
		),
		"cells left, right and above the grid are NO_RING"
	)
	check.call(
		lv.cell(3, 8) == MazeLevel.Cell.EMPTY and lv.cell(-5, 99) == MazeLevel.Cell.NO_RING,
		"cells below the grid are EMPTY"
	)
	check.call(
		(
			lv.solid(-1, 0)
			and lv.solid(10, 0)
			and lv.solid(0, -1)
			and not lv.solid(0, 8)
			and lv.solid(0, 7)
			and not lv.solid(3, 3)
		),
		"solid() follows the cells"
	)
	check.call(
		lv.cell(2, 6) == MazeLevel.Cell.EMPTY and lv.cell(5, 7) == MazeLevel.Cell.SOLID, "S and F cells are empty"
	)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _loader(check: Callable) -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var d := _base()
	d["rows"] = _rows_with({Vector2i(2, 4): "#"})
	d["id"] = "l1"
	_write(TMP + "/l001.json", JSON.stringify(d))
	_write(TMP + "/index.json", JSON.stringify({"format": 1, "levels": ["l001", "l404"]}))
	_write(TMP + "/bad.json", "not json")
	WhitePuzzleStore.clear_cache()
	var lv := MazeLevels.load_level("l001", TMP)
	check.call(
		lv.errors == PackedStringArray(["id 'l1' does not match file name 'l001'"]),
		"an id that differs from the file name is an error (%s)" % str(lv.errors)
	)
	check.call(not MazeLevels.load_level("l404", TMP).valid(), "a missing level file gives a level with an error")
	check.call(not MazeLevels.load_level("bad", TMP).valid(), "a file that is not JSON gives a level with an error")
	check.call(MazeLevels.ids(TMP) == PackedStringArray(["l001", "l404"]), "ids() reads the index of another folder")
	check.call(MazeLevels.ids("user://white_maze_test_nothing").is_empty(), "a missing index gives no ids")
	_clean()


func _clean() -> void:
	for f in DirAccess.get_files_at(TMP):
		DirAccess.remove_absolute(TMP + "/" + f)
	DirAccess.remove_absolute(TMP)


func _run_tool(args: PackedStringArray) -> int:
	var out := []
	var full := PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/check_levels.gd", "--"]
	)
	full.append_array(args)
	return OS.execute(OS.get_executable_path(), full, out, true)


func _tool(check: Callable) -> void:
	check.call(_run_tool(PackedStringArray()) == 0, "check_levels exits 0 on the shipped data")
	DirAccess.make_dir_recursive_absolute(TMP)
	var good := _base()
	good["rows"] = _rows_with({Vector2i(2, 4): "#"})
	var broken := good.duplicate(true)
	broken["id"] = "l002"
	broken["rows"] = _rows_with({})
	_write(TMP + "/l001.json", JSON.stringify(good).replace("t001", "l001"))
	_write(TMP + "/l002.json", JSON.stringify(broken))
	_write(TMP + "/index.json", JSON.stringify({"format": 1, "levels": ["l001", "l002"]}))
	var path := ProjectSettings.globalize_path(TMP)
	check.call(
		_run_tool(PackedStringArray(["--dir=" + path])) == 1, "check_levels exits 1 on a folder with a broken level"
	)
	_write(TMP + "/index.json", JSON.stringify({"format": 1, "levels": ["l001"]}))
	check.call(
		_run_tool(PackedStringArray(["--dir=" + path])) == 1,
		"check_levels exits 1 on a level file that is not in the index"
	)
	DirAccess.remove_absolute(TMP + "/l002.json")
	check.call(
		_run_tool(PackedStringArray(["--dir=" + path])) == 0, "check_levels exits 0 on a folder with only good levels"
	)
	_write(TMP + "/index.json", JSON.stringify({"format": 1, "levels": ["l001", "l001"]}))
	check.call(_run_tool(PackedStringArray(["--dir=" + path])) == 1, "check_levels exits 1 on a duplicate id")
	_write(TMP + "/index.json", JSON.stringify({"format": 1, "levels": ["l001", 5]}))
	check.call(_run_tool(PackedStringArray(["--dir=" + path])) == 1, "check_levels exits 1 on a non-string item")
	_clean()
