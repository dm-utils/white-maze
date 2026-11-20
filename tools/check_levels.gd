extends SceneTree
## Level check: godot --headless --path . -s res://tools/check_levels.gd [-- --dir=<level folder>]
## Validates every level of the index, replays its solution from tests/solutions.json, exit code 1 on any problem.

const SOLUTIONS := "res://tests/solutions.json"
const MAX_TICKS := 36000


func _init() -> void:
	var dir := MazeLevels.DIR
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
	quit(1 if _check(dir) > 0 else 0)


## number of problems
func _check(dir: String) -> int:
	var problems := 0
	var solutions := WhitePuzzleStore.load_json(SOLUTIONS)
	var ids := MazeLevels.ids(dir)
	if ids.is_empty():
		print("error index: no levels in %s" % dir.path_join("index.json"))
		problems += 1
	for id in ids:
		var lv := MazeLevels.load_level(id, dir)
		if not lv.valid():
			for e in lv.errors:
				print("error %s: %s" % [id, e])
				problems += 1
			continue
		print("ok %s %dx%d beads %d par %d" % [id, lv.width, lv.height, lv.beads, lv.par])
		if solutions.has(id):
			problems += _check_solution(lv, str(solutions[id]))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".json") and file != "index.json" and not ids.has(file.trim_suffix(".json")):
			print("error %s: level file is not in the index" % file.trim_suffix(".json"))
			problems += 1
	return problems


func _check_solution(lv: MazeLevel, script: String) -> int:
	var sim := MazeRunScript.run(lv, script, MAX_TICKS)
	if sim == null:
		print("solution %s FAILED script does not parse: %s" % [lv.id, MazeRunScript.parse(script)["error"]])
		return 1
	if not sim.finished():
		print("solution %s FAILED not finished within %d ticks" % [lv.id, MAX_TICKS])
		return 1
	if sim.rings_used > lv.par:
		print("solution %s FAILED used %d rings, par is %d" % [lv.id, sim.rings_used, lv.par])
		return 1
	print("solution %s finished ticks %d rings %d" % [lv.id, sim.time_ticks(), sim.rings_used])
	return 0
