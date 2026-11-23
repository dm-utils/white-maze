extends RefCounted
## L1-L4: shipped levels, validation rules, out-of-bounds cells, the check tool as a child process.

const H := preload("res://tests/helpers.gd")
const TMP := "user://white_maze_test_levels"

var _out := ""


func run(check: Callable, _node: Node) -> void:
	_shipped(check)
	_validation(check)
	_cells(check)
	_slopes(check)
	_valley(check)
	_slope_geometry(check)
	_loader(check)
	_tool(check)
	_tool_format2(check)


func _shipped(check: Callable) -> void:
	var ids := MazeLevels.ids()
	var series := PackedStringArray(["l001", "l002", "l003", "l004", "l005", "l006", "l007", "l008", "l009"])
	check.call(ids == series, "the index lists l001 to l009 in order")
	var beads := [3, 3, 3, 1, 3, 3, 3, 3, 3]
	var pars := [1, 2, 3, 3, 2, 4, 2, 2, 4]
	var diffs := []
	for id in ids:
		var lv := MazeLevels.load_level(id)
		check.call(lv.valid(), "%s is valid (%s)" % [id, str(lv.errors)])
		var file := WhitePuzzleStore.load_json("res://levels/%s.json" % id)
		check.call(lv.render() == PackedStringArray(file["rows"]), "%s: render() gives the file rows back" % id)
		var n := ids.find(id)
		check.call(lv.id == id and lv.beads == beads[n] and lv.par == pars[n], "%s: id, beads and par" % id)
		check.call(
			lv.hints.has("nl") and lv.hints.has("en") and lv.names["nl"] != "" and lv.names["en"] != "",
			"%s: names and hints in both languages" % id
		)
		diffs.append(lv.difficulty)
	check.call(diffs == [0, 1, 2, 0, 1, 1, 1, 2, 2], "difficulties follow the series: easy, medium, hard, easy, ...")
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
		["format", {"format": 3}, "format must be 1 or 2"],
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


func _slope_level(edits: Dictionary, extra: Dictionary = {}) -> MazeLevel:
	var d := {"format": 2, "rings": []}
	d.merge(extra, true)
	return H.level(H.rows(16, 8, edits), d)


func _slopes(check: Callable) -> void:
	var all_six := H.rows(16, 8, {})
	all_six[6] = "..S../..\\.rRLl.."
	var lv := H.level(all_six, {"format": 2})
	check.call(
		lv.valid() and lv.slope_count == 6,
		"R3: a format-2 level with all six slopes loads (%s)" % str(lv.errors)
	)
	check.call(lv.render() == PackedStringArray(all_six), "R3: render() gives the slope rows back")
	check.call(
		lv.cell(5, 6) == MazeLevel.Cell.STEEP_R and lv.cell(8, 6) == MazeLevel.Cell.STEEP_L
		and lv.cell(10, 6) == MazeLevel.Cell.GENTLE_R_LO and lv.cell(11, 6) == MazeLevel.Cell.GENTLE_R_HI
		and lv.cell(12, 6) == MazeLevel.Cell.GENTLE_L_HI and lv.cell(13, 6) == MazeLevel.Cell.GENTLE_L_LO,
		"R3: the six characters map to their cells"
	)
	check.call(
		not lv.solid(5, 6) and lv.slope(5, 6) and lv.covered(5, 6) and lv.covered(0, 7) and not lv.covered(4, 6),
		"R3: slopes are not solid but covered"
	)
	var f1 := H.level(H.rows(16, 8, {Vector2i(5, 6): "/"}))
	check.call(f1.format == 1 and not f1.sky, "R3: format 1 is the default")
	var flat2 := H.level(H.rows(16, 8), {"format": 2, "sky": true})
	check.call(flat2.valid() and flat2.sky and flat2.slope_count == 0, "R3: sky in format 2 is read")
	var spike_ok := _slope_level({Vector2i(5, 6): "/", Vector2i(4, 6): "^"})
	check.call(spike_ok.valid(), "R3: a spike at the low side of a slope is allowed (%s)" % str(spike_ok.errors))
	var gable := _slope_level({Vector2i(5, 6): "/", Vector2i(6, 6): "#", Vector2i(6, 7): "#"})
	check.call(gable.valid(), "R3: a slope against a block at its high side is valid (%s)" % str(gable.errors))
	var cases := [
		["slope in format 1", H.level(H.rows(16, 8, {Vector2i(5, 6): "/"})), "slope '/' at (5, 6) needs format 2"],
		["sky in format 1", H.level(H.rows(16, 8), {"sky": true}), "sky needs format 2"],
		["sky not a bool", H.level(H.rows(16, 8), {"format": 2, "sky": 1}), "sky must be true or false"],
		["format 3", H.level(H.rows(16, 8), {"format": 3}), "format must be 1 or 2"],
		["V1 nothing below", _slope_level({Vector2i(5, 5): "/"}), "slope at (5, 5) needs # or X below"],
		[
			"V1 spike below",
			_slope_level({Vector2i(5, 5): "/", Vector2i(5, 6): "^"}),
			"slope at (5, 5) needs # or X below"
		],
		[
			"V2 block above",
			_slope_level({Vector2i(5, 6): "/", Vector2i(5, 5): "#"}),
			"slope at (5, 6) needs empty space above"
		],
		[
			"V2 spike above",
			_slope_level({Vector2i(5, 6): "/", Vector2i(5, 5): "^"}),
			"slope at (5, 6) needs empty space above"
		],
		["V3 r", _slope_level({Vector2i(6, 6): "r"}), "gentle slope 'r' at (6, 6) needs 'R' to its right"],
		["V3 R", _slope_level({Vector2i(6, 6): "R"}), "gentle slope 'R' at (6, 6) needs 'r' to its left"],
		["V3 L", _slope_level({Vector2i(6, 6): "L"}), "gentle slope 'L' at (6, 6) needs 'l' to its right"],
		["V3 l", _slope_level({Vector2i(6, 6): "l"}), "gentle slope 'l' at (6, 6) needs 'L' to its left"],
		[
			"V4 wall",
			_slope_level({Vector2i(5, 6): "/", Vector2i(4, 6): "#", Vector2i(4, 5): "."}),
			"slope at (5, 6) has a blocked low side"
		],
		[
			"V4 cliff",
			_slope_level({Vector2i(5, 6): "/", Vector2i(6, 6): "/"}),
			"slope at (6, 6) has a blocked low side"
		],
		["V4 edge", _slope_level({Vector2i(0, 6): "/"}), "slope at (0, 6) has a blocked low side"],
		[
			"ring under a slope",
			_slope_level({Vector2i(5, 6): "/"}, {"rings": [{"x": 5, "y": 7, "face": "up"}]}),
			"ring at (5, 7) up is not exposed"
		],
		[
			"ring beside a high side",
			_slope_level({Vector2i(5, 6): "/", Vector2i(6, 6): "#", Vector2i(6, 7): "#"},
					{"rings": [{"x": 6, "y": 6, "face": "left"}]}),
			"ring at (6, 6) left is not exposed"
		],
	]
	for c in cases:
		check.call(
			c[1].errors.size() == 1 and c[1].errors[0] == c[2],
			"R3: %s gives exactly '%s' (got %s)" % [c[0], c[2], str(c[1].errors)]
		)


func _valley(check: Callable) -> void:
	var lv := _slope_level({Vector2i(5, 6): "\\", Vector2i(6, 6): "/"})
	check.call(
		lv.errors
		== PackedStringArray(["slope at (5, 6) has a blocked low side", "slope at (6, 6) has a blocked low side"]),
		"R3: V4 a valley gives one error per slope (got %s)" % str(lv.errors)
	)


func _slope_geometry(check: Callable) -> void:
	var T := MazeTuning.TILE
	var b := 3 * T
	var table := {
		MazeLevel.Cell.STEEP_R: [b + T, b + T / 2, b],
		MazeLevel.Cell.STEEP_L: [b, b + T / 2, b + T],
		MazeLevel.Cell.GENTLE_R_LO: [b + T, b + T - T / 4, b + T / 2],
		MazeLevel.Cell.GENTLE_R_HI: [b + T / 2, b + T / 4, b],
		MazeLevel.Cell.GENTLE_L_HI: [b, b + T / 4, b + T / 2],
		MazeLevel.Cell.GENTLE_L_LO: [b + T / 2, b + T - T / 4, b + T],
	}
	var surfaces_ok := true
	var inside_ok := true
	for kind in table:
		var i := 0
		for lx in [0, T / 2, T]:
			var s := MazeSlope.surface(kind, 3, lx)
			surfaces_ok = surfaces_ok and s == table[kind][i]
			var p := Vector2i(5 * T + lx, s)
			inside_ok = (
				inside_ok
				and MazeSlope.inside(kind, 5, 3, p)
				and MazeSlope.inside(kind, 5, 3, p + Vector2i(0, 3000))
				and not MazeSlope.inside(kind, 5, 3, p - Vector2i(0, 1))
			)
			i += 1
	check.call(surfaces_ok, "R4: surface() at lx 0, 20000 and 40000 equals the table for every kind")
	check.call(inside_ok, "R4: inside() is true on and below the surface and false 1 unit above")
	var cell := MazeLevel.Cell
	check.call(
		MazeSlope.surface(cell.GENTLE_R_LO, 3, T) == MazeSlope.surface(cell.GENTLE_R_HI, 3, 0),
		"R4: joint rR meets at equal y"
	)
	check.call(
		MazeSlope.surface(cell.GENTLE_L_HI, 3, T) == MazeSlope.surface(cell.GENTLE_L_LO, 3, 0),
		"R4: joint Ll meets at equal y"
	)
	check.call(
		MazeSlope.surface(cell.STEEP_R, 3, T) == MazeSlope.surface(cell.STEEP_L, 3, 0), "R4: joint /\\ meets at equal y"
	)
	check.call(
		MazeSlope.surface(cell.GENTLE_R_HI, 3, T) == MazeSlope.surface(cell.GENTLE_L_HI, 3, 0),
		"R4: joint RL meets at equal y"
	)
	check.call(
		MazeSlope.surface(cell.GENTLE_R_HI, 3, T) == MazeSlope.surface(cell.GENTLE_R_LO, 2, 0),
		"R4: a tier R to r meets at equal y"
	)
	check.call(
		MazeSlope.surface(cell.STEEP_R, 3, T) == 3 * T and MazeSlope.surface(cell.GENTLE_L_LO, 3, T) == 4 * T,
		"R4: a top joint meets the floor at equal y"
	)
	var steep_ok := MazeSlope.steep(cell.STEEP_R) and MazeSlope.steep(cell.STEEP_L)
	steep_ok = steep_ok and not MazeSlope.steep(cell.GENTLE_R_HI)
	check.call(steep_ok and not MazeSlope.is_slope(cell.SPIKE) and MazeSlope.is_slope(cell.GENTLE_L_LO), "R4: kinds")
	check.call(
		MazeSlope.downhill(cell.STEEP_R) == -1 and MazeSlope.downhill(cell.GENTLE_R_LO) == -1
		and MazeSlope.downhill(cell.GENTLE_R_HI) == -1 and MazeSlope.downhill(cell.STEEP_L) == 1
		and MazeSlope.downhill(cell.GENTLE_L_HI) == 1 and MazeSlope.downhill(cell.GENTLE_L_LO) == 1,
		"R4: downhill directions"
	)
	check.call(
		MazeSlope.high_side(cell.STEEP_R) == MazeLevel.Face.RIGHT
		and MazeSlope.high_side(cell.GENTLE_R_HI) == MazeLevel.Face.RIGHT
		and MazeSlope.high_side(cell.STEEP_L) == MazeLevel.Face.LEFT
		and MazeSlope.high_side(cell.GENTLE_L_HI) == MazeLevel.Face.LEFT
		and MazeSlope.high_side(cell.GENTLE_R_LO) == -1 and MazeSlope.high_side(cell.GENTLE_L_LO) == -1,
		"R4: high sides"
	)
	var poly_ok := true
	for kind in table:
		var poly := MazeSlope.polygon(kind)
		poly_ok = poly_ok and poly.size() >= 3
		for v in poly:
			# every vertex on or below the surface line
			poly_ok = poly_ok and v.y * 1000 >= MazeSlope.surface(kind, 0, v.x * 1000)
	check.call(poly_ok, "R4: polygon() vertices lie on or below the surface")


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
	_out = ""
	var full := PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/check_levels.gd", "--"]
	)
	full.append_array(args)
	var code := OS.execute(OS.get_executable_path(), full, out, true)
	if not out.is_empty():
		_out = out[0]
	return code


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


## R24: format-2 output line, 900-cell budget, headroom warning; one level per folder
func _tool_format2(check: Callable) -> void:
	var slope := _base()
	slope["format"] = 2
	slope["id"] = "t001"
	slope["rows"] = _rows_with({Vector2i(2, 4): "#", Vector2i(3, 6): "/"})
	check.call(_run_level(slope) == 0, "R24: check_levels exits 0 on a format-2 level")
	check.call(
		"ok t001 8x8 beads 3 par 1 slopes 1" in _out, "R24: the ok line of a format-2 level ends in the slope count"
	)
	var flat := _base()
	flat["id"] = "t001"
	flat["rows"] = _rows_with({Vector2i(2, 4): "#"})
	_run_level(flat)
	check.call("ok t001 8x8 beads 3 par 1\n" in _out, "R24: the ok line of a format-1 level is unchanged")
	var big := _base()
	big["id"] = "t001"
	big["rows"] = H.rows(31, 30)
	check.call(_run_level(big) == 1, "R24: check_levels exits 1 on a 31 x 30 level")
	check.call("error t001: 31x30 is 930 cells, more than 900" in _out, "R24: the 900-cell error text")
	big["rows"] = H.rows(30, 30)
	check.call(_run_level(big) == 0, "R24: a 30 x 30 level (900 cells) passes")
	# floor 5 rows under the top edge of a sky level
	var rows := H.rows(16, 8, {"S": 1, "F": 1, Vector2i(2, 4): "S", Vector2i(14, 4): "F"})
	for y in [5, 6]:
		rows[y] = "#".repeat(16)
	var low := _base()
	low["format"] = 2
	low["sky"] = true
	low["id"] = "t001"
	low["rows"] = rows
	check.call(_run_level(low) == 0, "R24: a headroom warning does not fail the check")
	check.call(
		(
			"warn t001: floor face (0, 5) has 5 rows of sky" in _out
			and "warn t001: floor face (15, 5) has 5 rows of sky" in _out
		),
		"R24: the warning names every floor face of the low floor"
	)
	low["rows"] = H.rows(16, 12, {Vector2i(2, 10): "S", "S": 1})
	_run_level(low)
	check.call("warn" not in _out, "R24: a floor with 11 rows of sky gives no warning")
	low["sky"] = false
	low["format"] = 1
	low["rows"] = rows
	_run_level(low)
	check.call("warn" not in _out, "R24: a level without sky gives no warning")
	_clean()


## writes the level as the only one of a temporary folder and runs the tool on it
func _run_level(d: Dictionary) -> int:
	DirAccess.make_dir_recursive_absolute(TMP)
	_write(TMP + "/" + d["id"] + ".json", JSON.stringify(d))
	_write(TMP + "/index.json", JSON.stringify({"format": 1, "levels": [d["id"]]}))
	return _run_tool(PackedStringArray(["--dir=" + ProjectSettings.globalize_path(TMP)]))
