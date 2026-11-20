class_name MazeRunScript
extends RefCounted
## Text form of a per-tick input sequence, e.g. "R40 RJ12 R20 T30 -5 L18 U -1".
## hold  = flags count; flags "-" or [L|R][J][P]; count 1..99999
## event = "T" index (0..143) or "U"; attaches to the first tick of the next hold
## A jump press is derived from J (held now, not held before) or forced with P.

const MAX_COUNT := 99999


## {"ok": bool, "inputs": Array[MazeInput], "error": String}
static func parse(text: String) -> Dictionary:
	var inputs: Array[MazeInput] = []
	var pending_throw := -1
	var pending_undo := false
	var prev_held := false
	var tokens := text.split(" ", true)
	for token in tokens:
		if token.is_empty():
			return _fail("empty token")
		if token == "U":
			if pending_undo:
				return _fail("two U before one hold")
			pending_undo = true
		elif token[0] == "T":
			var digits := token.substr(1)
			if not _is_number(digits) or (digits.length() > 1 and digits[0] == "0") or int(digits) > 143:
				return _fail("bad throw index in '%s'" % token)
			if pending_throw >= 0:
				return _fail("two T before one hold")
			pending_throw = int(digits)
		else:
			var hold := _parse_hold(token)
			if hold.is_empty():
				return _fail("bad hold token '%s'" % token)
			for i in hold["count"]:
				var input := MazeInput.new()
				input.move = hold["move"]
				input.jump_held = hold["held"]
				input.jump_pressed = (hold["held"] and not prev_held) or (i == 0 and hold["press"])
				if i == 0:
					input.throw_dir = pending_throw
					input.undo = pending_undo
				prev_held = hold["held"]
				inputs.append(input)
			pending_throw = -1
			pending_undo = false
	if pending_throw >= 0 or pending_undo:
		return _fail("event at the end without a hold")
	return {"ok": true, "inputs": inputs, "error": ""}


## canonical script of an input array; a press is only written when it cannot be derived
static func encode(inputs: Array) -> String:
	var tokens := PackedStringArray()
	var prev_held := false
	var i := 0
	while i < inputs.size():
		var first: MazeInput = inputs[i]
		var derived := first.jump_held and not prev_held
		var flags := "-"
		var letters := ("L" if first.move < 0 else ("R" if first.move > 0 else "")) \
				+ ("J" if first.jump_held else "") + ("P" if first.jump_pressed and not derived else "")
		if not letters.is_empty():
			flags = letters
		if first.throw_dir >= 0:
			tokens.append("T%d" % first.throw_dir)
		if first.undo:
			tokens.append("U")
		var count := 1
		while i + count < inputs.size() and count < MAX_COUNT:
			var next: MazeInput = inputs[i + count]
			if next.move != first.move or next.jump_held != first.jump_held or next.jump_pressed \
					or next.throw_dir >= 0 or next.undo:
				break
			count += 1
		tokens.append("%s%d" % [flags, count])
		prev_held = first.jump_held
		i += count
	return " ".join(tokens)


## steps every input, then idle ticks until finished or max_ticks; null when the script does not parse
static func run(level: MazeLevel, text: String, max_ticks: int = 36000) -> MazeSim:
	var parsed := parse(text)
	if not parsed["ok"]:
		return null
	var sim := MazeSim.new(level)
	for input in parsed["inputs"]:
		sim.step(input)
		if sim.finished():
			return sim
	var idle := MazeInput.idle()
	while not sim.finished() and sim.tick < max_ticks:
		sim.step(idle)
	return sim


static func _fail(message: String) -> Dictionary:
	var none: Array[MazeInput] = []
	return {"ok": false, "inputs": none, "error": message}


static func _is_number(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		if s.unicode_at(i) < 48 or s.unicode_at(i) > 57:
			return false
	return true


## {} when malformed
static func _parse_hold(token: String) -> Dictionary:
	var pos := 0
	var move := 0
	var held := false
	var press := false
	var any := false
	if token[0] == "-":
		pos = 1
		any = true
	else:
		if token[pos] == "L" or token[pos] == "R":
			move = -1 if token[pos] == "L" else 1
			pos += 1
			any = true
		if pos < token.length() and token[pos] == "J":
			held = true
			pos += 1
			any = true
		if pos < token.length() and token[pos] == "P":
			press = true
			pos += 1
			any = true
	var digits := token.substr(pos)
	if not any or not _is_number(digits) or digits[0] == "0" or digits.length() > 5:
		return {}
	var count := int(digits)
	if count < 1 or count > MAX_COUNT:
		return {}
	return {"move": move, "held": held, "press": press, "count": count}
