extends RefCounted
## Independent robustness and property tests: garbage into the level parser, run script parser and profile
## sanitize; merge laws on random profiles; take-back and par (ADR 0005/0009); solution determinism.

const H := preload("res://tests/helpers.gd")
const DEV_A := "9f2c4a1b7e3d5a60"
const DEV_B := "00112233445566ff"
const DEV_C := "abcdefabcdefabcd"


func run(check: Callable, _node: Node) -> void:
	_level_garbage(check)
	_run_script_garbage(check)
	_sanitize_garbage(check)
	_sanitize_lang_types(check)
	_sanitize_partial_pairs(check)
	_sanitize_big_numbers(check)
	_merge_laws(check)
	_take_back_and_par(check)
	_solution_determinism(check)


func _n(rng: WhiteRng, k: int) -> int:
	return rng.range_int(0, k - 1)


func _junk(rng: WhiteRng, depth: int = 0) -> Variant:
	var pool := [null, true, false, 0, 1, -1, 3, 1000000, 0.5, 2.0, -0.0, "", "x", "l001", "9f2c4a1b7e3d5a60",
			"nl", "en", "R5", [], {}, "....", PackedStringArray(["........"]), Vector2i(1, 2)]
	var kind := _n(rng, 8)
	if kind == 0 and depth < 3:
		var arr := []
		for i in _n(rng, 4):
			arr.append(_junk(rng, depth + 1))
		return arr
	if kind == 1 and depth < 3:
		var d := {}
		for i in _n(rng, 4):
			d[str(_junk(rng, depth + 1))] = _junk(rng, depth + 1)
		return d
	return pool[_n(rng, pool.size())]


## copy of the shipped l001 dictionary with random fields replaced
func _mutated_level(rng: WhiteRng) -> Variant:
	var data: Dictionary = WhitePuzzleStore.load_json("res://levels/l001.json").duplicate(true)
	var keys := data.keys() + ["extra"]
	for i in 1 + _n(rng, 3):
		var key: String = keys[_n(rng, keys.size())]
		if key == "rows" and _n(rng, 2) == 0 and data["rows"] is Array and not data["rows"].is_empty():
			var rows: Array = data["rows"].duplicate()
			var y := _n(rng, rows.size())
			if not rows[y] is String or rows[y].is_empty():
				continue
			var line: String = rows[y]
			var x := _n(rng, line.length())
			rows[y] = line.substr(0, x) + "SFX^#.Q "[_n(rng, 8)] + line.substr(x + 1)
			if _n(rng, 4) == 0:
				rows[y] = line.substr(0, line.length() - 1)
			data["rows"] = rows
		else:
			data[key] = _junk(rng)
	return data


func _level_garbage(check: Callable) -> void:
	var rng := WhiteRng.new(77)
	var never_null := true
	var consistent := true
	var simulated := 0
	var junk_roots := [null, 1, "x", [], [1], true, 2.5]
	for j in junk_roots:
		var lv := MazeLevel.from_dict(j)
		never_null = never_null and lv != null and not lv.valid()
	for i in 400:
		var lv := MazeLevel.from_dict(_mutated_level(rng))
		never_null = never_null and lv != null
		consistent = consistent and (lv.valid() == lv.errors.is_empty())
		if lv.valid():
			# a level that validates must be playable without script errors
			var sim := MazeSim.new(lv)
			for t in 30:
				sim.step(H.inp(1, true, t == 0, 18 if t == 5 else -1))
			simulated += 1
			consistent = consistent and not H.overlaps_solid(sim)
	check.call(never_null, "from_dict never returns null, also for non-object input")
	check.call(consistent, "mutated levels: valid() matches errors, valid ones simulate without overlap")
	check.call(simulated > 20, "the mutation test also produced valid levels (%d)" % simulated)


func _run_script_garbage(check: Callable) -> void:
	var rng := WhiteRng.new(78)
	var alphabet := "LRJPT-U0123456789 "
	var ok_consistent := true
	for i in 600:
		var s := ""
		for c in _n(rng, 24):
			s += alphabet[_n(rng, alphabet.length())]
		var r := MazeRunScript.parse(s)
		if r["ok"]:
			var inputs: Array = r["inputs"]
			# canonical re-encoding must parse back to the same inputs
			var again := MazeRunScript.parse(MazeRunScript.encode(inputs))
			ok_consistent = ok_consistent and again["ok"] and again["inputs"].size() == inputs.size()
			for k in inputs.size():
				ok_consistent = ok_consistent and again["inputs"][k].equals(inputs[k])
		else:
			ok_consistent = ok_consistent and r["error"] != "" and r["inputs"].is_empty()
	check.call(ok_consistent, "random script text: ok scripts round-trip through encode, failures carry a message")
	check.call(not MazeRunScript.parse("")["ok"], "an empty script is an error")
	check.call(not MazeRunScript.parse(" R5")["ok"] and not MazeRunScript.parse("R5 ")["ok"], "stray spaces are errors")
	check.call(not MazeRunScript.parse("R05")["ok"] and not MazeRunScript.parse("R-5")["ok"], "leading zero or sign")
	check.call(
		not MazeRunScript.parse("T")["ok"] and not MazeRunScript.parse("T-1 R1")["ok"],
		"T without or with a bad index"
	)
	check.call(MazeRunScript.parse("R99999")["ok"] and not MazeRunScript.parse("R100000")["ok"], "count limit 99999")
	check.call(MazeRunScript.run(MazeLevels.load_level("l001"), "R0") == null, "run returns null for a bad script")


func _sanitize_garbage(check: Callable) -> void:
	var rng := WhiteRng.new(79)
	var fine := true
	var idempotent := true
	var ops_ok := true
	var oks := 0
	for i in 500:
		var d := {"format": 1, "device": DEV_A, "lang": "en", "updated": 5, "levels": {"l001": {
			"best_ticks": 100, "best_rings": 1, "best_run": "R5", "fewest_rings": 1, "fewest_ticks": 100,
			"first_finish": 3, "last_played": 4,
			"counts": {DEV_A: {"starts": 1, "finishes": 1, "deaths": 0, "play_ticks": 9}},
		}}}
		# replace one random spot, at a random depth, with junk
		var target: Dictionary = d
		for step in _n(rng, 4):
			var keys := target.keys()
			var k: Variant = keys[_n(rng, keys.size())]
			if target[k] is Dictionary and _n(rng, 3) > 0:
				target = target[k]
			else:
				break
		var keys := target.keys()
		var key: Variant = keys[_n(rng, keys.size())]
		if key == "lang" and target == d:
			continue # non-string lang is covered by _sanitize_lang_types
		target[key] = _junk(rng)
		var r := MazeProfile.sanitize(d)
		fine = fine and ["ok", "damaged", "newer"].has(r["status"])
		if r["status"] != "ok":
			fine = fine and r["profile"] == {}
			continue
		oks += 1
		var p: Dictionary = r["profile"]
		idempotent = idempotent and MazeProfile.sanitize(p)["profile"] == p
		# every operation works on a sanitized profile
		var q := p.duplicate(true)
		if q["device"] == "":
			q["device"] = DEV_B
		MazeProfile.record_start(q, "l001", 10)
		MazeProfile.add_play(q, "l002", 50, 1, 11)
		# fewest_rings without fewest_ticks is covered by _sanitize_partial_pairs
		var e: Dictionary = q["levels"]["l001"]
		if e.has("fewest_rings") != e.has("fewest_ticks") or e.has("best_ticks") != e.has("best_rings"):
			continue
		var res := MazeProfile.record_finish(q, "l001", 90, 1, "R9", 12)
		ops_ok = ops_ok and res.has("new_best") and MazeProfile.level_totals(q, "l001")["starts"] >= 1
		ops_ok = ops_ok and MazeProfile.total_play_ticks(q) >= 0
		ops_ok = ops_ok and MazeProfile.sanitize(q)["status"] == "ok"
		var m := MazeProfile.merge(q, p)
		ops_ok = ops_ok and m["format"] == 1 and MazeProfile.sanitize(m)["status"] == "ok"
	check.call(fine, "sanitize always returns a status, and {} unless ok")
	check.call(oks > 100, "garbage inside an otherwise good profile mostly stays ok (%d of 500)" % oks)
	check.call(idempotent, "sanitize(sanitize(x)) == sanitize(x)")
	check.call(ops_ok, "operations and merge work on every sanitized profile and stay sanitize-clean")


func _sanitize_lang_types(check: Callable) -> void:
	for v in [1, 0.5, true, [], {}]:
		var r: Variant = MazeProfile.sanitize({"format": 1, "lang": v})
		check.call(
			r is Dictionary and r["status"] == "ok" and r["profile"]["lang"] == "nl",
			"a lang of type %d falls back to nl instead of raising a script error" % typeof(v)
		)


func _sanitize_partial_pairs(check: Callable) -> void:
	# a damaged entry keeps one field of a pair; later play must not raise
	var cases := [
		{"fewest_rings": 1},
		{"fewest_ticks": 100},
		{"best_ticks": 100},
		{"best_rings": 1},
		{"best_ticks": 100, "fewest_rings": 2},
	]
	for entry in cases:
		var d := {"format": 1, "device": DEV_A, "levels": {"l001": entry.duplicate()}}
		var p: Dictionary = MazeProfile.sanitize(d)["profile"]
		var res: Variant = MazeProfile.record_finish(p, "l001", 120, 1, "R5", 50)
		var m: Variant = MazeProfile.merge(p, p)
		check.call(
			res is Dictionary and res.has("new_best") and m is Dictionary and m["levels"].has("l001"),
			"record_finish and merge work on a partial entry %s" % JSON.stringify(entry)
		)


func _sanitize_big_numbers(check: Callable) -> void:
	for big in [1e19, 9223372036854775808.0, 1e30]:
		var d := {"format": 1, "device": DEV_A, "levels": {"l001": {
			"best_ticks": big, "counts": {DEV_A: {"starts": big, "play_ticks": big}},
		}}}
		var e: Dictionary = MazeProfile.sanitize(d)["profile"]["levels"]["l001"]
		var counter: int = e["counts"][DEV_A]["starts"]
		check.call(
			(not e.has("best_ticks") or e["best_ticks"] >= 0) and counter >= 0,
			"a number beyond int64 (%s) never becomes negative" % str(big)
		)


func _random_profile(rng: WhiteRng, device: String) -> Dictionary:
	var p := MazeProfile.create(device, "nl" if _n(rng, 2) == 0 else "en", 1000 + _n(rng, 50))
	if _n(rng, 4) == 0:
		p["id"] = "acc%d" % _n(rng, 3)
	if _n(rng, 3) == 0:
		p["future_key"] = _n(rng, 100)
	for id in ["l001", "l002", "l003"]:
		if _n(rng, 4) == 0:
			continue
		MazeProfile.record_start(p, id, 1000 + _n(rng, 50))
		MazeProfile.add_play(p, id, _n(rng, 3000), _n(rng, 5), 1000 + _n(rng, 50))
		for f in _n(rng, 3):
			var run := "R%d" % (1 + _n(rng, 9))
			MazeProfile.record_finish(p, id, 200 + _n(rng, 400), _n(rng, 4), run, 1000 + _n(rng, 50))
	return p


func _levels_of(p: Dictionary) -> Dictionary:
	return p["levels"]


func _merge_laws(check: Callable) -> void:
	var rng := WhiteRng.new(80)
	var idem := true
	var comm := true
	var assoc := true
	var no_double := true
	var stable := true
	var cases := 0
	for i in 200:
		var a := _random_profile(rng, DEV_A)
		var b := _random_profile(rng, DEV_B)
		var c := _random_profile(rng, DEV_C)
		var m := MazeProfile.merge(a, a)
		idem = idem and m == a
		var ab := MazeProfile.merge(a, b)
		var ba := MazeProfile.merge(b, a)
		# no ties in best/fewest when strictly different; compare level stats only where both sides differ
		if _no_ties(a, b):
			cases += 1
			comm = comm and _levels_of(ab) == _levels_of(ba)
		var left := MazeProfile.merge(MazeProfile.merge(a, b), c)
		var right := MazeProfile.merge(a, MazeProfile.merge(b, c))
		if _no_ties(a, b) and _no_ties(b, c) and _no_ties(a, c):
			assoc = assoc and _levels_of(left) == _levels_of(right)
		# totals count every device once: a and b have different devices
		for id in ["l001", "l002", "l003"]:
			var ta := MazeProfile.level_totals(a, id)
			var tb := MazeProfile.level_totals(b, id)
			var tm := MazeProfile.level_totals(ab, id)
			for name in MazeProfile.COUNTERS:
				no_double = no_double and tm[name] == ta[name] + tb[name]
		stable = stable and _levels_of(MazeProfile.merge(ab, b)) == _levels_of(ab) \
				and _levels_of(MazeProfile.merge(ab, a)) == _levels_of(ab)
	check.call(idem, "merge(a, a) == a on random profiles")
	check.call(
		comm and cases > 50,
		"merge(a, b) and merge(b, a) agree on the levels when there are no ties (%d cases)" % cases
	)
	check.call(assoc, "merge is associative on the levels when there are no ties")
	check.call(no_double, "totals after a merge of two devices are the sum, never double-counted")
	check.call(stable, "merging an input into the result again leaves the levels unchanged")


## true when for every level that both profiles finished the best and fewest keys differ
func _no_ties(a: Dictionary, b: Dictionary) -> bool:
	for id in a["levels"]:
		if not b["levels"].has(id):
			continue
		var x: Dictionary = a["levels"][id]
		var y: Dictionary = b["levels"][id]
		if x.has("best_ticks") and y.has("best_ticks") and x["best_ticks"] == y["best_ticks"]:
			return false
		if x.has("fewest_rings") and y.has("fewest_rings") and x["fewest_rings"] == y["fewest_rings"] \
				and x["fewest_ticks"] == y["fewest_ticks"]:
			return false
	return a["lang"] == b["lang"] or a["updated"] != b["updated"]


## Taking back every ring right after its launch must not lower the par count. Under ADR 0005 (beads left at the
## finish) it does: every shipped level finishes with 0 beads used. ADR 0009 counts rings used, which closes this;
## the check follows whichever rule the sim implements (sim.rings_used exists from then on).
func _take_back_and_par(check: Callable) -> void:
	var sols := WhitePuzzleStore.load_json("res://tests/solutions.json")
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		var inputs: Array = MazeRunScript.parse(str(sols[id]))["inputs"]
		var sim := MazeSim.new(lv)
		var undo_next := false
		var i := 0
		while not sim.finished() and sim.tick < 3000:
			var inp: MazeInput = inputs[i] if i < inputs.size() else MazeInput.idle()
			i += 1
			if undo_next:
				inp.undo = true
				undo_next = false
			sim.step(inp)
			for e in sim.events:
				if e["type"] == "launch":
					for r in sim.rings:
						if r["cell"] == e["cell"] and r["face"] == e["face"] and not r["preset"]:
							undo_next = true
		var used: Variant = sim.get("rings_used")
		if used == null:
			check.call(
				sim.finished() and sim.beads_left == lv.beads,
				"%s: ADR 0005 only: taking back each used ring finishes with 0 beads used (par %d)" % [id, lv.par]
			)
		else:
			check.call(
				sim.finished() and used == lv.par,
				"%s: taking back each used ring after its launch still counts %d rings used (par %d)"
				% [id, used, lv.par]
			)


func _solution_determinism(check: Callable) -> void:
	var sols := WhitePuzzleStore.load_json("res://tests/solutions.json")
	var expected := {"l001": 391, "l002": 256, "l003": 295}
	var first := {}
	for round in 2:
		for id in ["l003", "l001", "l002"]:
			var sim := MazeRunScript.run(MazeLevels.load_level(id), str(sols[id]))
			if round == 0:
				first[id] = sim.snapshot()
			else:
				check.call(
					first[id] == sim.snapshot(), "%s: the solution gives the same final state on a second run" % id
				)
				check.call(
					sim.time_ticks() == expected[id],
					"%s: the solution takes %d ticks (%d)" % [id, expected[id], sim.time_ticks()]
				)
