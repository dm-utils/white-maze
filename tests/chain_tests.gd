extends RefCounted
## K2-K4: chain links from events, pinned chains per solution, link text and share code.

const H := preload("res://tests/helpers.gd")
const SOLUTIONS := "res://tests/solutions.json"
const PROFILE := "user://white_maze_test_chain.json"

const PINNED := {
	"l001": "ku26.11-bu38.11",
	"l002": "ku1.11-br0.5-bu22.11",
	"l003": "bu1.11-br0.4-bu24.11",
	"l004": "bu7.11-bu19.11-bu31.11",
	"l005": "ku22.16-br21.9-bl26.9",
	"l006": "bu5.21-bu9.17-bu13.13-bu17.9",
	"l007": "br10.9-bu27.12",
	"l008": "ku1.13-br0.6-bu10.13",
	"l009": "bu8.13-bu11.13-br10.6-bu20.13",
}


var _node: Node


func run(check: Callable, node: Node) -> void:
	_node = node
	_clean()
	_links_from_events(check)
	_every_tick(check)
	_pinned(check)
	_codecs(check)
	_records(check)
	_game_equals_replay(check)
	_clean()
	WhiteText.lang = "nl"


func _clean() -> void:
	for p in [PROFILE, PROFILE + ".tmp"]:
		DirAccess.remove_absolute(p)


func _main(extra: Array) -> MazeMain:
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	m.args = PackedStringArray(["--profile=" + PROFILE, "--speed=100"] + extra)
	_node.add_child(m)
	return m


func _close(m: MazeMain) -> void:
	_node.remove_child(m)
	m.free()


## steps with the same input, collecting links like the game does
class Rec:
	var sim: MazeSim
	var level: MazeLevel
	var seen := {}
	var links: Array = []

	func _init(lv: MazeLevel) -> void:
		level = lv
		sim = MazeSim.new(lv)

	func step(input: MazeInput) -> void:
		sim.step(input)
		MazeChain.note(sim.events, level, seen, links)

	func until(done: Callable, limit: int = 400) -> void:
		var guard := 0
		while not done.call() and guard < limit:
			step(H.inp())
			guard += 1


func _throw_down() -> MazeInput:
	return H.inp(0, false, false, 108)


func _links_from_events(check: Callable) -> void:
	var lv := H.level(H.rows(20, 12), {"par": 2})
	# a) one thrown ring, one launch
	var r := Rec.new(lv)
	r.step(_throw_down())
	r.until(func() -> bool: return r.sim.rings_used >= 1)
	check.call(
		r.links.size() == 1 and r.links[0]["kind"] == MazeChain.Kind.BEAD and r.sim.rings_used == 1,
		"K2a: a thrown ring that launches gives one bead (%s)" % MazeChain.encode(r.links)
	)
	# b) bouncing on it again adds nothing
	var launches := 0
	for i in 300:
		r.step(H.inp())
		launches += 1 if H.has_event(r.sim, "launch") else 0
	check.call(
		launches >= 2 and r.links.size() == 1, "K2b: %d more launches on the same ring still give one bead" % launches
	)
	# c) taken back before any launch
	r = Rec.new(lv)
	r.step(_throw_down())
	r.step(H.inp(0, false, false, -1, true))
	r.until(func() -> bool: return false, 120)
	check.call(r.links.is_empty() and r.sim.rings_used == 0, "K2c: a ring taken back before a launch gives no link")
	# d) take back after the launch, throw again to the same face: two beads at one place
	r = Rec.new(lv)
	r.step(_throw_down())
	r.until(func() -> bool: return r.sim.rings_used >= 1)
	r.step(H.inp(0, false, false, -1, true))
	r.step(_throw_down())
	r.until(func() -> bool: return r.sim.rings_used >= 2)
	check.call(
		r.links.size() == 2 and r.links[0]["cell"] == r.links[1]["cell"] and r.links[0]["face"] == r.links[1]["face"]
			and r.sim.rings_used == 2,
		"K2d: take back and throw again gives two beads with equal cell and face (%s)" % MazeChain.encode(r.links)
	)
	# e) preset launched many times: one knot, no bead
	var pre := H.level(H.rows(20, 16), {"rings": [{"x": 2, "y": 15, "face": "up"}]})
	r = Rec.new(pre)
	var pre_launches := 0
	for i in 400:
		r.step(H.inp())
		pre_launches += 1 if H.has_event(r.sim, "launch") else 0
	check.call(
		pre_launches >= 2 and r.links.size() == 1 and r.links[0]["kind"] == MazeChain.Kind.KNOT
			and MazeChain.bead_count(r.links) == 0,
		"K2e: a preset launched %d times gives one knot and no bead (%s)" % [pre_launches, MazeChain.encode(r.links)]
	)
	# f) a death after a counted launch keeps the bead
	var spike := H.level(H.rows(20, 12, {Vector2i(8, 10): "^", Vector2i(9, 10): "^"}), {"par": 1})
	r = Rec.new(spike)
	r.step(_throw_down())
	r.until(func() -> bool: return r.sim.rings_used >= 1, 100)
	r.sim.px = 8 * MazeTuning.TILE + MazeTuning.TILE
	r.sim.py = 10 * MazeTuning.TILE
	r.sim.grounded = false
	r.until(func() -> bool: return not r.sim.alive(), 100)
	check.call(
		not r.sim.alive() and MazeChain.bead_count(r.links) == 1,
		"K2f: a death after a counted launch keeps the bead"
	)


func _every_tick(check: Callable) -> void:
	var solutions := WhitePuzzleStore.load_json(SOLUTIONS)
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		var inputs: Array = MazeRunScript.parse(solutions[id])["inputs"]
		var r := Rec.new(lv)
		var same := true
		for input: MazeInput in inputs:
			r.step(input)
			same = same and MazeChain.bead_count(r.links) == r.sim.rings_used
			if r.sim.finished():
				break
		check.call(same and r.sim.finished(), "K2g: %s: bead count equals rings used after every tick" % id)


func _pinned(check: Callable) -> void:
	var solutions := WhitePuzzleStore.load_json(SOLUTIONS)
	for id in MazeLevels.ids():
		var lv := MazeLevels.load_level(id)
		var res := MazeChain.from_run(lv, solutions[id])
		var text := MazeChain.encode(res["links"])
		check.call(res["ok"] and res["finished"], "K3: %s: from_run finishes" % id)
		check.call(text == PINNED.get(id, ""), "K3: %s: chain %s is pinned (%s)" % [id, PINNED.get(id, ""), text])
		var plain := MazeRunScript.run(lv, solutions[id])
		check.call(
			res["ticks"] == plain.time_ticks() and res["rings"] == plain.rings_used,
			"K3: %s: from_run ticks and rings equal MazeRunScript.run" % id
		)
		check.call(MazeChain.fits(lv, res["links"]), "K3: %s: every link lies inside the grid" % id)
		var code := MazeChain.code(id, res["rings"], lv.par, res["ticks"], text)
		var back := MazeChain.parse_code(code)
		check.call(
			back["ok"] and back["level"] == id and back["rings"] == res["rings"]
				and MazeChain.encode(back["links"]) == text,
			"K4: %s: the share code round-trips (%s)" % [id, code]
		)
	check.call(not MazeChain.from_run(H.level(H.rows(20, 12)), "X9")["ok"], "K3: an unparsable script gives ok false")


func _codecs(check: Callable) -> void:
	var rng := WhiteRng.new(14)
	var same := true
	for n in 50:
		var links: Array = []
		for i in rng.range_int(0, MazeChain.MAX_LINKS):
			links.append({
				"kind": rng.range_int(0, 1), "cell": Vector2i(rng.range_int(0, 255), rng.range_int(0, 63)),
				"face": rng.range_int(0, 3),
			})
		var back := MazeChain.parse(MazeChain.encode(links))
		same = same and back["ok"] and back["links"] == links
	check.call(same, "K4: parse(encode(x)) equals x for 50 random chains")
	check.call(
		MazeChain.parse("")["ok"] and MazeChain.parse("")["links"].is_empty(), "K4: the empty text is the empty chain"
	)
	var bad := [
		"bu7.11--bu3.4", "-bu7.11", "bu7.11-", "xu7.11", "bx7.11", "bu711", "bu07.11", "bu7.011", "bu256.1",
		"bu1.64", "bu7.11 ", "bu7.11-BU3.4", "bu-1.4", "bu1.2.3", "bu.4", "bu7.", "b", "bu1e2.3",
	]
	var all_rejected := true
	var quiet := true
	for text: String in bad:
		var res := MazeChain.parse(text)
		all_rejected = all_rejected and not res["ok"]
		quiet = quiet and res["error"] != "" and not res["error"].contains("\n") and res["links"].is_empty()
		if res["ok"]:
			printerr("parse accepted '%s'" % text)
	check.call(all_rejected, "K4: parse rejects empty tokens, unknown kind or face, bad numbers and stray text")
	check.call(quiet, "K4: parse errors are one English line")
	var too_many := PackedStringArray()
	for i in MazeChain.MAX_LINKS + 1:
		too_many.append("bu1.1")
	check.call(not MazeChain.parse("-".join(too_many))["ok"], "K4: parse rejects more than MAX_LINKS links")
	too_many.remove_at(0)
	check.call(MazeChain.parse("-".join(too_many))["ok"], "K4: parse accepts exactly MAX_LINKS links")
	check.call(not MazeChain.parse("b".repeat(MazeChain.MAX_LINKS_TEXT + 1))["ok"], "K4: parse rejects a long text")
	var good := "wm1/l004/3/3/371/bu7.11-bu19.11-bu31.11"
	check.call(MazeChain.parse_code(good)["ok"], "K4: the example code parses")
	var bad_codes := [
		"wm2/l004/3/3/371/bu7.11-bu19.11-bu31.11", "wm1/l004/3/3/bu7.11-bu19.11-bu31.11",
		"wm1/l004/3/3/371/bu7.11-bu19.11-bu31.11/x", "wm1/L004/3/3/371/bu7.11-bu19.11-bu31.11",
		"wm1//3/3/371/bu7.11-bu19.11-bu31.11", "wm1/l004/03/3/371/bu7.11-bu19.11-bu31.11",
		"wm1/l004/3/3/0371/bu7.11-bu19.11-bu31.11", "wm1/l004/3/3/-1/bu7.11-bu19.11-bu31.11",
		"wm1/l004/2/3/371/bu7.11-bu19.11-bu31.11", "wm1/l004/3/3/371/bu7.11--bu31.11",
		"wm1/l004/x/3/371/bu7.11-bu19.11-bu31.11", "wm1/l004/3/3/371/" + "a".repeat(MazeChain.MAX_CODE),
	]
	var codes_rejected := true
	for text: String in bad_codes:
		var res := MazeChain.parse_code(text)
		codes_rejected = codes_rejected and not res["ok"] and res["error"] != ""
		if res["ok"]:
			printerr("parse_code accepted '%s'" % text)
	check.call(codes_rejected, "K4: parse_code rejects wrong tag, field count, id, numbers, beads and length")
	check.call(
		MazeChain.parse_code("wm1/l004/0/1/50/")["ok"] and MazeChain.code("l004", 0, 1, 50, "") == "wm1/l004/0/1/50/",
		"K4: a code without links has an empty last field"
	)
	check.call(MazeChain.code("l004", 3, 3, 371, "b".repeat(MazeChain.MAX_CODE)) == "", "K4: a code too long is empty")


func _records(check: Callable) -> void:
	var one: Array = [{"kind": MazeChain.Kind.BEAD, "cell": Vector2i(7, 11), "face": 0}]
	var rec := MazeChain.record(1, 200, one)
	check.call(
		rec == {"rings": 1, "ticks": 200, "links": "bu7.11"}, "K4: record holds rings, ticks and the link text"
	)
	var worse := {"rings": 2, "ticks": 100, "links": ""}
	var slower := {"rings": 1, "ticks": 300, "links": "bu7.11"}
	check.call(MazeChain.better(rec, {}), "K4: any record beats an empty one")
	check.call(not MazeChain.better({}, rec), "K4: an empty record beats nothing")
	check.call(MazeChain.better(rec, worse) and not MazeChain.better(worse, rec), "K4: fewer rings wins")
	check.call(MazeChain.better(rec, slower) and not MazeChain.better(slower, rec), "K4: equal rings, faster wins")
	check.call(not MazeChain.better(rec, rec), "K4: an equal record does not beat itself")


func _game_equals_replay(check: Callable) -> void:
	WhiteText.lang = "nl"
	for id in MazeLevels.ids():
		_clean()
		var m := _main(["--level=" + id, "--solve"])
		var g := m.game
		g.set_process(false)
		var res := g.last_result
		var lv := MazeLevels.load_level(id)
		check.call(
			not res.is_empty() and res["links_text"] == PINNED[id], "K5: %s: --solve ends with the pinned chain" % id
		)
		check.call(
			res["code"] == MazeChain.code(id, res["rings"], lv.par, res["ticks"], PINNED[id])
				and res["level"].id == id and res["number"] == MazeLevels.ids().find(id) + 1,
			"K5: %s: the result carries code, level and number" % id
		)
		_close(m)
	# the same through the controls (U3 path)
	_clean()
	var m := _main(["--level=l001"])
	var g := m.game
	g.set_process(false)
	var solution: String = WhitePuzzleStore.load_json(SOLUTIONS)["l001"]
	for inp: MazeInput in MazeRunScript.parse(solution)["inputs"]:
		_feed(g, inp)
		if g.sim.finished():
			break
	check.call(
		g.sim.finished() and g.last_result["links_text"] == PINNED["l001"],
		"K5: l001 through the controls gives the same links as from_run"
	)
	var lines := g.print_lines(g.last_result)
	check.call(
		lines.size() == 2 and lines[0].begins_with("run l001 ") and lines[1] == "chain " + g.last_result["code"]
			and lines[1].begins_with("chain wm1/l001/1/1/"),
		"K15: --print-run prints the chain line after the run line (%s)" % lines[1]
	)
	_close(m)


## drives the game through its controls, one tick per frame
func _feed(game: MazeGame, inp: MazeInput) -> void:
	var c := game.controls
	c.touch_move(inp.move)
	if inp.jump_pressed:
		c.touch_jump(false)
		c.touch_jump(true)
		if not inp.jump_held:
			c.touch_jump(false)
	else:
		c.touch_jump(inp.jump_held)
	if inp.throw_dir >= 0:
		c.touch_throw(inp.throw_dir)
	if inp.undo:
		c.queue_undo()
	game.advance(1.0 / 60.0)
