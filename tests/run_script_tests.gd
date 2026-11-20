extends RefCounted
## R1-R4: run script grammar, errors, round trips.

const H := preload("res://tests/helpers.gd")


func run(check: Callable, _node: Node) -> void:
	_parse(check)
	_errors(check)
	_round_trip(check)


func _parse(check: Callable) -> void:
	var r := MazeRunScript.parse("R40 RJ12 R20 T30 -5 L18 U -1")
	check.call(r["ok"], "the design example parses (%s)" % r["error"])
	var inputs: Array = r["inputs"]
	check.call(inputs.size() == 40 + 12 + 20 + 5 + 18 + 1, "the example has 96 ticks (%d)" % inputs.size())
	check.call(inputs[0].move == 1 and not inputs[0].jump_held and not inputs[0].jump_pressed, "R40: move right")
	check.call(inputs[40].jump_held and inputs[40].jump_pressed and not inputs[41].jump_pressed and inputs[51].jump_held,
			"RJ12: held for 12 ticks, pressed on the first only")
	check.call(not inputs[52].jump_held and inputs[52].move == 1, "R20: released")
	check.call(inputs[72].throw_dir == 30 and inputs[72].move == 0 and inputs[71].throw_dir == -1,
			"T30 attaches to the first tick of the next hold")
	check.call(inputs[77].move == -1 and not inputs[77].undo, "L18: move left")
	check.call(inputs[95].move == 0 and inputs[95].undo and inputs[95].throw_dir == -1, "U attaches to the final idle tick")
	check.call(MazeRunScript.parse("RJ3 RJ3")["inputs"][3].jump_pressed == false, "a held jump across tokens is not pressed again")
	check.call(MazeRunScript.parse("RJ3 R1 RJ2")["inputs"][4].jump_pressed, "releasing and pressing again is a new press")
	check.call(MazeRunScript.parse("P3 -2")["inputs"][0].jump_pressed and not MazeRunScript.parse("P3")["inputs"][0].jump_held,
			"P forces a press without holding")
	check.call(MazeRunScript.parse("T0 -1")["inputs"][0].throw_dir == 0, "T0 is a valid index")
	check.call(MazeRunScript.parse("T143 -1")["inputs"][0].throw_dir == 143, "T143 is a valid index")
	check.call(MazeRunScript.parse("T3 U -1")["inputs"][0].undo and MazeRunScript.parse("U T3 -1")["inputs"][0].throw_dir == 3,
			"a throw and an undo may share a tick in either order")


func _errors(check: Callable) -> void:
	var bad := {
		"": "empty script", "R5  R5": "empty token", "R0": "zero count", "RL5": "RL", "JR5": "JR", "T144": "T144",
		"T05": "leading zero", "T1 T2 R5": "two T", "U U R5": "two U", "R5 T3": "trailing T", "R5 U": "trailing U",
		"Q5": "unknown letter", "R100000": "count 100000", "R": "no count", "-": "dash without count", "T R5": "T without index",
		"R-5": "negative count", "RJPP5": "double P", "RP J5": "stray", "LR5": "LR", "T-1 R5": "negative index",
	}
	for text in bad:
		var r := MazeRunScript.parse(text)
		check.call(not r["ok"] and r["error"] != "" and r["inputs"].is_empty(), "'%s' is an error (%s)" % [text, bad[text]])
	check.call(MazeRunScript.parse("R99999")["ok"], "count 99999 is allowed")
	check.call(MazeRunScript.run(H.level(H.rows(20, 8)), "R0") == null, "run returns null for a bad script")


func _random_inputs(rng: WhiteRng, ticks: int) -> Array:
	var out: Array = []
	var held := false
	var move := 0
	for i in ticks:
		var input := MazeInput.new()
		if rng.range_int(0, 6) == 0:
			move = rng.range_int(-1, 1)
		var was_held := held
		if rng.range_int(0, 5) == 0:
			held = not held
		input.move = move
		input.jump_held = held
		input.jump_pressed = (held and not was_held) or rng.range_int(0, 19) == 0
		if rng.range_int(0, 29) == 0:
			input.throw_dir = rng.range_int(0, 143)
		input.undo = rng.range_int(0, 49) == 0
		out.append(input)
	return out


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].equals(b[i]):
			return false
	return true


func _round_trip(check: Callable) -> void:
	var rng := WhiteRng.from_text("run-script-round-trip")
	var all_ok := true
	var canonical_ok := true
	for n in 50:
		var inputs := _random_inputs(rng, 500)
		var text := MazeRunScript.encode(inputs)
		var back := MazeRunScript.parse(text)
		all_ok = all_ok and back["ok"] and _same(back["inputs"], inputs)
		canonical_ok = canonical_ok and MazeRunScript.encode(back["inputs"]) == text
	check.call(all_ok, "parse(encode(x)) equals x for 50 random arrays of 500 ticks")
	check.call(canonical_ok, "encode(parse(s)) equals s for canonical scripts")
	var s := "R40 RJ12 R20 T30 -5 L18 U -1"
	check.call(MazeRunScript.encode(MazeRunScript.parse(s)["inputs"]) == s, "the design example is canonical")
	check.call(MazeRunScript.encode([]) == "", "an empty input array encodes to an empty script")
	var long: Array = []
	for i in 100001:
		long.append(MazeInput.idle())
	var long_text := MazeRunScript.encode(long)
	check.call(long_text == "-99999 -2" and _same(MazeRunScript.parse(long_text)["inputs"], long), "a long hold is split at 99999 ticks")
	# R4: a played run replays to the same finish
	var lv := H.level(H.rows(30, 12, {"F": 0, Vector2i(6, 10): "F"}))
	var first := MazeRunScript.run(lv, "R40")
	check.call(first.finished(), "a script that walks into F finishes")
	var recorded: Array = []
	var sim := MazeSim.new(lv)
	var driver: Array = MazeRunScript.parse("R40")["inputs"]
	for input in driver:
		recorded.append(input)
		sim.step(input)
		if sim.finished():
			break
	var again := MazeRunScript.run(lv, MazeRunScript.encode(recorded))
	check.call(again.finished() and again.finish_tick == first.finish_tick and again.beads_used() == first.beads_used(),
			"an encoded recording replays to the same finish tick and beads")
