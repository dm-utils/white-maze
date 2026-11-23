extends SceneTree
## Plain-text level export for the native solver (design 23.10.4).
## godot --headless --path . -s res://tools/export_levels.gd -- --out=build/solver/levels.txt [--dir=res://levels/x]
##     [--no-fixtures]
## Writes the levels of the index, of the lab and of every --dir, and the trace fixtures of 23.10.4 (ids fx-*).
##   level <id> <width> <height> <beads> <par> <sky 0|1>
##   row <cells as MazeLevel.CHARS, S and F included>      (height lines)
##   ring <x> <y> <face 0..3>                               (one line per preset ring)
##   end

const FX := preload("res://tools/solver_fixtures.gd")


func _init() -> void:
	var out := "build/solver/levels.txt"
	var dirs: Array[String] = [MazeLevels.DIR, MazeLevels.LAB_DIR]
	var fixtures := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--dir="):
			dirs.append(a.get_slice("=", 1))
		elif a == "--no-fixtures":
			fixtures = false
	var levels: Array[MazeLevel] = []
	for dir in dirs:
		for id in MazeLevels.ids(dir):
			levels.append(MazeLevels.load_level(id, dir))
	if fixtures:
		levels.append_array(FX.levels())
	var text := ""
	for lv in levels:
		if not lv.valid():
			printerr("export: %s is invalid: %s" % [lv.id, str(lv.errors)])
			quit(1)
			return
		text += _block(lv)
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		printerr("export: cannot write %s" % out)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("export: %d levels to %s" % [levels.size(), out])
	quit(0)


static func _block(lv: MazeLevel) -> String:
	var s := "level %s %d %d %d %d %d\n" % [lv.id, lv.width, lv.height, lv.beads, lv.par, 1 if lv.sky else 0]
	for row in lv.render():
		s += "row %s\n" % row
	for r in lv.preset_rings:
		s += "ring %d %d %d\n" % [r["cell"].x, r["cell"].y, r["face"]]
	return s + "end\n"
