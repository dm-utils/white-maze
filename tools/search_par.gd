extends SceneTree
## Par check by ring-set relaxation: pre-place extra rings as if they were presets and search for a finish with
## weighted A* over macro steps of k ticks (move x jump). A set of fewer rings than par that finishes is a lead
## (throwability and timing must still be checked by hand); no result proves nothing.
## godot --headless --path . -s res://tools/search_par.gd -- --level=l002 --rings="0,4,right;22,11,up" [--k=4]
##     [--nodes=30000]
## godot --headless --path . -s res://tools/search_par.gd -- --level=l002 --subset=1 [--faces=x0,y0,x1,y1]
##     [--anchor=x0,y0,x1,y1] [--part=i/n]
##     tries every set of N exposed faces (--faces: candidate area, --anchor: at least one ring inside this tile
##     rectangle, --part: every n-th set, for parallel runs) on top of the preset rings.

var H_WEIGHT := 1

var _level: MazeLevel
var _k := 4
var _max_nodes := 30000


func _init() -> void:
	var id := "l001"
	var subset := 0
	var rings: Array[Dictionary] = []
	var rect := Rect2i(0, 0, 100000, 100000)
	var anchor := Rect2i(0, 0, 100000, 100000)
	var part := Vector2i(0, 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			id = a.get_slice("=", 1)
		elif a.begins_with("--k="):
			_k = int(a.get_slice("=", 1))
		elif a.begins_with("--weight="):
			H_WEIGHT = int(a.get_slice("=", 1))
		elif a.begins_with("--nodes="):
			_max_nodes = int(a.get_slice("=", 1))
		elif a.begins_with("--subset="):
			subset = int(a.get_slice("=", 1))
		elif a.begins_with("--faces="):
			var f := a.get_slice("=", 1).split(",")
			rect = Rect2i(int(f[0]), int(f[1]), int(f[2]) - int(f[0]) + 1, int(f[3]) - int(f[1]) + 1)
		elif a.begins_with("--anchor="):
			var f := a.get_slice("=", 1).split(",")
			anchor = Rect2i(int(f[0]), int(f[1]), int(f[2]) - int(f[0]) + 1, int(f[3]) - int(f[1]) + 1)
		elif a.begins_with("--part="):
			part = Vector2i(int(a.get_slice("=", 1).get_slice("/", 0)), int(a.get_slice("=", 1).get_slice("/", 1)))
		elif a.begins_with("--rings="):
			for item in a.get_slice("=", 1).split(";"):
				var f := item.split(",")
				rings.append({"cell": Vector2i(int(f[0]), int(f[1])), "face": MazeLevel.FACE_NAMES.find(f[2])})
	_level = MazeLevels.load_level(id)
	if subset == 0:
		_try(rings)
		quit(0)
		return
	var faces := _faces(rect)
	print("%d candidate faces" % faces.size())
	var found := 0
	var n := 0
	for combo in _combos(faces.size(), subset):
		var set: Array[Dictionary] = []
		var anchored := false
		for i in combo:
			set.append(faces[i])
			anchored = anchored or anchor.has_point(faces[i]["cell"])
		if not anchored:
			continue
		n += 1
		if n % part.y != part.x:
			continue
		if _try(set, true):
			found += 1
	print("sets with a finish: %d" % found)
	quit(0)


func _faces(rect: Rect2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for y in _level.height:
		for x in _level.width:
			if not rect.has_point(Vector2i(x, y)) or _level.cell(x, y) != MazeLevel.Cell.SOLID:
				continue
			for face in 4:
				var f := Vector2i(x, y) + MazeLevel.FACE_STEP[face]
				if _level.solid(f.x, f.y) or _level.cell(f.x, f.y) == MazeLevel.Cell.SPIKE:
					continue
				if _is_preset(Vector2i(x, y), face):
					continue
				out.append({"cell": Vector2i(x, y), "face": face})
	return out


func _is_preset(c: Vector2i, face: int) -> bool:
	for r in _level.preset_rings:
		if r["cell"] == c and r["face"] == face:
			return true
	return false


static func _combos(n: int, k: int) -> Array:
	var out: Array = []
	var idx: Array = []
	for i in k:
		idx.append(i)
	while true:
		out.append(idx.duplicate())
		var i := k - 1
		while i >= 0 and idx[i] == n - k + i:
			i -= 1
		if i < 0:
			break
		idx[i] += 1
		for j in range(i + 1, k):
			idx[j] = idx[j - 1] + 1
	return out


## true when a finish was found
func _try(extra: Array[Dictionary], quiet := false) -> bool:
	var lv := MazeLevel.from_dict({
		"format": 1, "id": "tmp", "name": {"nl": "t", "en": "t"}, "difficulty": "easy", "beads": 1, "par": 0,
		"rows": Array(_level.render()),
	})
	lv.preset_rings = _level.preset_rings.duplicate()
	lv.preset_rings.append_array(extra)
	var script := _search(lv)
	var label := ""
	for r in extra:
		label += " (%d,%d,%s)" % [r["cell"].x, r["cell"].y, MazeLevel.FACE_NAMES[r["face"]]]
	if script == "":
		if not quiet:
			print("extra rings%s: no finish within the node limit" % label)
		return false
	print("extra rings%s: FINISH script %s" % [label, script])
	return true


static func _clone(s: MazeSim) -> MazeSim:
	var n := MazeSim.new(s.level)
	for f in ["tick", "px", "py", "prev_px", "prev_py", "vx", "vy", "facing", "grounded", "coyote", "buffer",
			"jumping", "launched", "lock_ticks", "dead_ticks", "deaths", "beads_left", "throw_count",
			"clock_start", "finish_tick"]:
		n.set(f, s.get(f))
	n.rings.clear()
	for r in s.rings:
		n.rings.append(r.duplicate())
	return n


func _key(s: MazeSim, held: bool) -> int:
	var cd := 0
	for r in s.rings:
		cd = cd * 2 + (1 if r["cooldown"] > 0 else 0)
	return [s.px / 3000, s.py / 3000, s.vx / 1500, s.vy / 1500, s.grounded, s.coyote > 0, s.buffer > 0, s.jumping,
			s.launched, s.lock_ticks, s.dead_ticks, cd, held].hash()


func _h(s: MazeSim) -> int:
	var dx := absi(s.px - (_level.finish.x * 40000 + 20000))
	var dy := absi(s.py - (_level.finish.y * 40000 + 40000))
	return maxi(dx, dy) / 5000


func _search(lv: MazeLevel) -> String:
	var root := MazeSim.new(lv)
	var nodes: Array = [[root, false, -1, []]]
	var seen := {_key(root, false): true}
	var heap: Array = [[_h(root) * H_WEIGHT, 0]] # [f, node index]
	while not heap.is_empty() and nodes.size() < _max_nodes:
		var top: Array = _pop(heap)
		var idx: int = top[1]
		var s: MazeSim = nodes[idx][0]
		var held: bool = nodes[idx][1]
		for move in [1, -1, 0]:
			for jump in [false, true]:
				var n := _clone(s)
				var macro: Array = []
				var hh := held
				for i in _k:
					var inp := MazeInput.new()
					inp.move = move
					inp.jump_held = jump
					inp.jump_pressed = jump and not hh
					hh = jump
					n.step(inp)
					macro.append(inp)
					if n.finished():
						break
				if n.finished():
					nodes.append([n, hh, idx, macro])
					return _script(nodes, nodes.size() - 1)
				if n.dead_ticks > 0:
					continue
				var key := _key(n, hh)
				if seen.has(key):
					continue
				seen[key] = true
				nodes.append([n, hh, idx, macro])
				_push(heap, [n.tick + _h(n) * H_WEIGHT, nodes.size() - 1])
	print("  nodes %d, open %d" % [nodes.size(), heap.size()])
	return ""


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0 and heap[(i - 1) / 2][0] > heap[i][0]:
		var p := (i - 1) / 2
		var t: Array = heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < heap.size() and heap[l][0] < heap[m][0]:
				m = l
			if r < heap.size() and heap[r][0] < heap[m][0]:
				m = r
			if m == i:
				break
			var t: Array = heap[m]
			heap[m] = heap[i]
			heap[i] = t
			i = m
	return top


func _script(nodes: Array, idx: int) -> String:
	var chain: Array = []
	while idx > 0:
		chain.append(nodes[idx][3])
		idx = nodes[idx][2]
	chain.reverse()
	var inputs: Array = []
	for m in chain:
		inputs.append_array(m)
	return MazeRunScript.encode(inputs)
