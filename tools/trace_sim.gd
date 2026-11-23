extends SceneTree
## Reference traces of MazeSim for the native solver (design 23.10.4).
## godot --headless --path . -s res://tools/trace_sim.gd -- --levels=build/solver/levels.txt --seeds=12 --ticks=900
##     --out=build/solver/
## Reads the export of export_levels.gd. Per level and seed one hold-only run script from WhiteRng (half of the seeds
## with three random extra presets on exposed faces, every third one starting at a random free spot instead of S).
## --sweep=<units> adds, for the fx-* levels, runs from standing and falling starts at every <units> along the level
## with the right or left key held (and jump held in half of them), like the landing tests of the slope suite.
## Writes cases.txt and trace_gd.txt:
##   case <n> <level id> <x,y,face;... or -> <px,py or -> <run script>
##   <n> <tick> px py vx vy ground grounded dead_ticks rings_used coyote buffer jumping launched lock_ticks facing
##   finished
## A case ends at the finish tick or after --ticks ticks.


func _init() -> void:
	var src := "build/solver/levels.txt"
	var out := "build/solver/"
	var seeds := 12
	var ticks := 900
	var sweep := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--levels="):
			src = a.get_slice("=", 1)
		elif a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--ticks="):
			ticks = int(a.get_slice("=", 1))
		elif a.begins_with("--sweep="):
			sweep = int(a.get_slice("=", 1))
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var root := ProjectSettings.globalize_path("res://")
	if not src.is_absolute_path():
		src = root.path_join(src)
	if not out.is_absolute_path():
		out = root.path_join(out)
	var levels := _read(src)
	if levels.is_empty():
		printerr("trace: no levels in %s" % src)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var cases := FileAccess.open(out.path_join("cases.txt"), FileAccess.WRITE)
	var trace := FileAccess.open(out.path_join("trace_gd.txt"), FileAccess.WRITE)
	var n := 0
	var total := 0
	for lv in levels:
		for s in seeds:
			var rng := WhiteRng.new(7000 + n)
			var extra: Array[Dictionary] = []
			if s % 2 == 1:
				extra = _random_rings(lv, rng, 3)
			var start := _random_start(lv, rng) if s % 3 == 2 else Vector2i(-1, -1)
			var script := _script(rng, ticks)
			var start_text := "-" if start.x < 0 else "%d,%d" % [start.x, start.y]
			cases.store_string("case %d %s %s %s %s\n" % [n, lv.id, _rings_text(extra), start_text, script])
			total += _trace(trace, lv, extra, start, script, n, ticks)
			n += 1
		if sweep > 0 and lv.id.begins_with("fx-"):
			for c in _sweeps(lv, sweep):
				cases.store_string("case %d %s - %d,%d %s\n" % [n, lv.id, c["start"].x, c["start"].y, c["script"]])
				total += _trace(trace, lv, [], c["start"], c["script"], n, 100)
				n += 1
	cases.close()
	trace.close()
	print("trace: %d cases, %d ticks" % [n, total])
	quit(0)


static func _read(path: String) -> Array[MazeLevel]:
	var out: Array[MazeLevel] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var head := PackedStringArray()
	var rows: Array = []
	var rings: Array = []
	for line in f.get_as_text().split("\n", false):
		var p := line.split(" ")
		match p[0]:
			"level":
				head = p
				rows = []
				rings = []
			"row":
				rows.append(p[1])
			"ring":
				rings.append({"x": int(p[1]), "y": int(p[2]), "face": MazeLevel.FACE_NAMES[int(p[3])]})
			"end":
				var lv := MazeLevel.from_dict({
					"format": 2, "id": head[1], "name": {"nl": head[1], "en": head[1]}, "difficulty": "easy",
					"beads": int(head[4]), "par": int(head[5]), "sky": head[6] == "1", "rows": rows, "rings": rings,
				})
				if not lv.valid():
					printerr("trace: %s is invalid: %s" % [head[1], str(lv.errors)])
				else:
					out.append(lv)
	return out


static func _rings_text(rings: Array[Dictionary]) -> String:
	if rings.is_empty():
		return "-"
	var parts := PackedStringArray()
	for r in rings:
		parts.append("%d,%d,%d" % [r["cell"].x, r["cell"].y, r["face"]])
	return ";".join(parts)


## exposed faces as in tools/search_par.gd
static func _random_rings(lv: MazeLevel, rng: WhiteRng, count: int) -> Array[Dictionary]:
	var faces: Array[Dictionary] = []
	for y in lv.height:
		for x in lv.width:
			if lv.cell(x, y) != MazeLevel.Cell.SOLID:
				continue
			for face in 4:
				var f := Vector2i(x, y) + MazeLevel.FACE_STEP[face]
				if lv.covered(f.x, f.y) or lv.cell(f.x, f.y) == MazeLevel.Cell.SPIKE:
					continue
				var taken := false
				for r in lv.preset_rings:
					taken = taken or (r["cell"] == Vector2i(x, y) and r["face"] == face)
				if not taken:
					faces.append({"cell": Vector2i(x, y), "face": face})
	var out: Array[Dictionary] = []
	while out.size() < count and not faces.is_empty():
		out.append(faces.pop_at(rng.range_int(0, faces.size() - 1)))
	return out


## feet at the bottom edge of a random empty cell with free cells left, right and above it; half of the starts stand
## on a block or a roof (the cell below is not empty), so floors, edges and eaves are met from rest
static func _random_start(lv: MazeLevel, rng: WhiteRng) -> Vector2i:
	var spots: Array[Vector2i] = []
	var floors: Array[Vector2i] = []
	for y in range(1, lv.height):
		for x in range(1, lv.width - 1):
			if lv.cell(x, y) == MazeLevel.Cell.EMPTY and lv.cell(x, y - 1) == MazeLevel.Cell.EMPTY \
					and lv.cell(x - 1, y) == MazeLevel.Cell.EMPTY and lv.cell(x + 1, y) == MazeLevel.Cell.EMPTY:
				spots.append(Vector2i(x, y))
				if lv.cell(x, y + 1) != MazeLevel.Cell.EMPTY:
					floors.append(Vector2i(x, y))
	if not floors.is_empty() and rng.range_int(0, 1) == 0:
		spots = floors
	if spots.is_empty():
		return Vector2i(-1, -1)
	var c: Vector2i = spots[rng.range_int(0, spots.size() - 1)]
	return Vector2i(c.x * MazeTuning.TILE + rng.range_int(0, MazeTuning.TILE - 1), (c.y + 1) * MazeTuning.TILE)


## [{start, script}]: per column step the topmost standing spot and a spot 2 tiles above it, 100 ticks each way
static func _sweeps(lv: MazeLevel, step: int) -> Array:
	var out: Array = []
	var T := MazeTuning.TILE
	for cx in range(1, lv.width - 1):
		var row := -1
		for cy in range(1, lv.height - 1):
			if lv.cell(cx, cy) == MazeLevel.Cell.EMPTY and lv.cell(cx, cy + 1) != MazeLevel.Cell.EMPTY:
				row = cy
				break
		if row < 0:
			continue
		for x in range(0, T, step):
			for lift in [0, 2]:
				if row + 1 - lift < 1:
					continue
				for dir in [-1, 1]:
					for jump in [false, true]:
						var inputs: Array = []
						for i in 100:
							var inp := MazeInput.new()
							inp.move = dir
							inp.jump_held = jump and i < 30
							inp.jump_pressed = inp.jump_held and i == 0
							inputs.append(inp)
						out.append({
							"start": Vector2i(cx * T + x, (row + 1 - lift) * T),
							"script": MazeRunScript.encode(inputs),
						})
	return out


## segments of 1..40 ticks, leaning one way, jump held about half of them
static func _script(rng: WhiteRng, ticks: int) -> String:
	var lean := 1 if rng.range_int(0, 1) == 0 else -1
	var inputs: Array = []
	var held := false
	while inputs.size() < ticks:
		var roll := rng.range_int(0, 9)
		var move := lean if roll < 6 else (0 if roll < 8 else -lean)
		var want := rng.range_int(0, 1) == 0
		for i in rng.range_int(1, 40):
			var inp := MazeInput.new()
			inp.move = move
			inp.jump_held = want
			inp.jump_pressed = want and not held
			held = want
			inputs.append(inp)
	inputs.resize(ticks)
	return MazeRunScript.encode(inputs)


## writes the trace lines of one case, returns the number of ticks
static func _trace(file: FileAccess, lv: MazeLevel, extra: Array[Dictionary], start: Vector2i, script: String, n: int,
		ticks: int) -> int:
	var run := MazeLevel.from_dict({
		"format": 2, "id": lv.id, "name": {"nl": "t", "en": "t"}, "difficulty": "easy", "beads": lv.beads, "par": 0,
		"sky": lv.sky, "rows": Array(lv.render()),
	})
	run.preset_rings = lv.preset_rings.duplicate()
	run.preset_rings.append_array(extra)
	var sim := MazeSim.new(run)
	if start.x >= 0:
		sim.px = start.x
		sim.py = start.y
		sim._compute_ground()
	var count := 0
	for inp in MazeRunScript.parse(script)["inputs"]:
		sim.step(inp)
		count += 1
		file.store_string("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n" % [n, sim.tick, sim.px, sim.py, sim.vx, sim.vy,
				sim.ground, int(sim.grounded), sim.dead_ticks, sim.rings_used, sim.coyote, sim.buffer,
				int(sim.jumping), int(sim.launched), sim.lock_ticks, sim.facing, int(sim.finished())])
		if sim.finished() or count >= ticks:
			break
	return count
