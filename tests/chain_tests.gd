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
	_profile_format(check)
	_profile_records(check)
	_profile_merge(check)
	_profile_size(check)
	_migration(check)
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
		check.call(
			m.store.data["levels"][id].get("chain", {}).get("links", "") == PINNED[id],
			"K5: %s: the finish stores the chain in the profile" % id
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


const DEV_A := "aaaaaaaaaaaaaaaa"
const DEV_B := "bbbbbbbbbbbbbbbb"


func _chain(rings: Variant, ticks: Variant, links: Variant) -> Dictionary:
	return {"rings": rings, "ticks": ticks, "links": links}


## sanitized profile with one finished level holding the given chain value
func _with_chain(value: Variant) -> Dictionary:
	var entry := {"best_ticks": 371, "best_rings": 3, "fewest_rings": 3, "fewest_ticks": 371}
	if not (value is String and value == "<absent>"):
		entry["chain"] = value
	return MazeProfile.sanitize({"format": 2, "device": DEV_A, "levels": {"l004": entry}})["profile"]["levels"]["l004"]


func _profile_format(check: Callable) -> void:
	var p := MazeProfile.create(DEV_A, "nl", 1)
	check.call(p["format"] == 2 and MazeProfile.FORMAT == 2, "K10: create gives format 2")
	check.call(MazeProfile.sanitize({"format": 3})["status"] == "newer", "K10: format 3 is newer")
	var one := MazeProfile.sanitize({"format": 1, "device": DEV_A})
	check.call(
		one["status"] == "ok" and one["migrated"] and one["profile"]["format"] == 2,
		"K10: format 1 is ok, migrated and becomes format 2"
	)
	var two := MazeProfile.sanitize({"format": 2, "device": DEV_A})
	check.call(two["status"] == "ok" and not two["migrated"], "K10: format 2 is ok and not migrated")
	var good := _chain(3, 371, "bu7.11-bu19.11-bu31.11")
	check.call(_with_chain(good).get("chain") == good, "K10: a valid chain is kept")
	check.call(_with_chain(_chain(0, 50, "")).get("chain") == _chain(0, 50, ""), "K10: a chain without links is kept")
	check.call(_with_chain(_chain(3.0, 371.0, good["links"])).get("chain") == good, "K10: JSON floats become whole numbers")
	var long_links := "bu1.1" + "-bu1.1".repeat(MazeChain.MAX_LINKS)
	var bad := {
		"links unparsable": _chain(3, 371, "bu7.11-xx"),
		"links too long": _chain(65, 371, long_links),
		"bead count differs": _chain(2, 371, good["links"]),
		"negative rings": _chain(-1, 371, ""),
		"negative ticks": _chain(3, -1, good["links"]),
		"fractional rings": _chain(2.5, 371, good["links"]),
		"fractional ticks": _chain(3, 371.5, good["links"]),
		"extra key": {"rings": 3, "ticks": 371, "links": good["links"], "x": 1},
		"missing key": {"rings": 3, "links": good["links"]},
		"links not a string": _chain(3, 371, 5),
		"not a dictionary": "bu7.11",
		"null": null,
		"array": [3, 371, "bu"],
	}
	for what: String in bad:
		check.call(not _with_chain(bad[what]).has("chain"), "K10: a chain with %s is removed" % what)
	check.call(not _with_chain("<absent>").has("chain"), "K10: no chain stays no chain")


func _profile_records(check: Callable) -> void:
	var p := MazeProfile.create(DEV_A, "nl", 1)
	var a := "bu1.1"
	var r := MazeProfile.record_finish(p, "l004", 400, 2, "R1", 5, a + "-bu2.2")
	check.call(r["new_chain"] and p["levels"]["l004"]["chain"] == _chain(2, 400, "bu1.1-bu2.2"), "K10: the first finish stores the chain")
	r = MazeProfile.record_finish(p, "l004", 500, 1, "R1", 6, a)
	check.call(r["new_chain"] and p["levels"]["l004"]["chain"] == _chain(1, 500, a), "K10: fewer rings replaces the chain")
	r = MazeProfile.record_finish(p, "l004", 450, 1, "R1", 7, "bu3.3")
	check.call(r["new_chain"] and p["levels"]["l004"]["chain"] == _chain(1, 450, "bu3.3"), "K10: equal rings and faster replaces")
	r = MazeProfile.record_finish(p, "l004", 460, 1, "R1", 8, "bu4.4")
	check.call(not r["new_chain"] and p["levels"]["l004"]["chain"]["links"] == "bu3.3", "K10: equal rings and slower keeps")
	r = MazeProfile.record_finish(p, "l004", 100, 2, "R1", 9, "bu1.1-bu2.2")
	check.call(not r["new_chain"] and p["levels"]["l004"]["chain"]["links"] == "bu3.3", "K10: more rings keeps")
	var before: Dictionary = p["levels"]["l004"]["chain"].duplicate()
	r = MazeProfile.record_finish(p, "l004", 10, 0, "R1", 10)
	check.call(not r["new_chain"] and p["levels"]["l004"]["chain"] == before, "K10: links null changes nothing")
	r = MazeProfile.record_finish(p, "l004", 10, 0, "R1", 11, "nonsense")
	check.call(not r["new_chain"] and p["levels"]["l004"]["chain"] == before, "K10: unparsable links change nothing")
	r = MazeProfile.record_finish(p, "l005", 10, 0, "R1", 12, "")
	check.call(r["new_chain"] and p["levels"]["l005"]["chain"] == _chain(0, 10, ""), "K10: an empty chain is stored")


func _profile_merge(check: Callable) -> void:
	var local := MazeProfile.create(DEV_A, "nl", 1)
	var remote := MazeProfile.create(DEV_B, "nl", 1)
	local["levels"]["l004"] = {"best_ticks": 400, "best_rings": 3, "chain": _chain(3, 400, "bu1.1-bu2.2-bu3.3")}
	remote["levels"]["l004"] = {"best_ticks": 500, "best_rings": 2, "chain": _chain(2, 500, "bu1.1-bu2.2")}
	var m := MazeProfile.merge(local, remote)
	check.call(m["levels"]["l004"]["chain"] == remote["levels"]["l004"]["chain"], "K10: merge takes the better chain from remote")
	m = MazeProfile.merge(remote, local)
	check.call(m["levels"]["l004"]["chain"] == remote["levels"]["l004"]["chain"], "K10: merge takes the better chain from local")
	var tie_l := MazeProfile.create(DEV_A, "nl", 1)
	var tie_r := MazeProfile.create(DEV_B, "nl", 1)
	tie_l["levels"]["l004"] = {"chain": _chain(1, 300, "bu1.1")}
	tie_r["levels"]["l004"] = {"chain": _chain(1, 300, "bu2.2")}
	check.call(MazeProfile.merge(tie_l, tie_r)["levels"]["l004"]["chain"]["links"] == "bu1.1", "K10: a tie goes to local")
	var none := MazeProfile.create(DEV_B, "nl", 1)
	none["levels"]["l004"] = {"best_ticks": 1, "best_rings": 1}
	check.call(MazeProfile.merge(local, none)["levels"]["l004"]["chain"] == local["levels"]["l004"]["chain"], "K10: an absent chain loses (remote absent)")
	check.call(MazeProfile.merge(none, local)["levels"]["l004"]["chain"] == local["levels"]["l004"]["chain"], "K10: an absent chain loses (local absent)")
	check.call(not MazeProfile.merge(none, none)["levels"]["l004"].has("chain"), "K10: no chain on either side stays none")
	var whole: Dictionary = MazeProfile.sanitize(local)["profile"]
	check.call(MazeProfile.merge(whole, whole) == whole, "K10: merge(a, a) == a with chains")
	var s := MazeProfile.sanitize(MazeProfile.merge(local, remote))
	check.call(s["status"] == "ok" and s["profile"]["levels"]["l004"].has("chain"), "K10: a merged chain survives sanitize")


func _profile_size(check: Callable) -> void:
	var p := MazeProfile.create(DEV_A, "nl", 1)
	var links := PackedStringArray()
	for i in MazeChain.MAX_LINKS:
		links.append("bu%d.%d" % [150 + i, 60])
	var counts := {
		DEV_A: {"starts": 10, "finishes": 5, "deaths": 20, "play_ticks": 100000},
		DEV_B: {"starts": 11, "finishes": 6, "deaths": 21, "play_ticks": 100001},
	}
	for i in 30:
		p["levels"]["l%03d" % i] = {
			"best_ticks": 1000 + i, "best_rings": 1, "fewest_rings": 1, "fewest_ticks": 1000 + i,
			"best_run": "R40 RJ12 ".repeat(222).substr(0, 2000), "first_finish": 1, "last_played": 1,
			"counts": counts.duplicate(true), "chain": _chain(MazeChain.MAX_LINKS, 5000, "-".join(links)),
		}
	var size := JSON.stringify(p).length()
	print("profile with 30 levels and 64-link chains: %d bytes" % size)
	check.call(size < 140 * 1024, "K10: P7: 30 levels with 64-link chains stay under 140 KB (%d bytes)" % size)
	check.call(MazeProfile.sanitize(p)["profile"]["levels"]["l029"].has("chain"), "K10: P7: the 64-link chains are valid")


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _format1(level_id: String, run: String, ticks: int, rings: int) -> Dictionary:
	return {
		"format": 1, "game": "white-maze", "tick_hz": 60, "device": DEV_A, "updated": 5, "lang": "nl",
		"levels": {level_id: {
			"best_ticks": ticks, "best_rings": rings, "best_run": run, "fewest_rings": rings, "fewest_ticks": ticks,
			"first_finish": 3, "last_played": 4,
			"counts": {DEV_A: {"starts": 2, "finishes": 1, "deaths": 0, "play_ticks": 500}},
		}},
	}


func _open(levels: Dictionary) -> MazeProfileStore:
	var s := MazeProfileStore.new()
	s.open(PROFILE, 100, levels)
	return s


func _migration(check: Callable) -> void:
	var lv := MazeLevels.load_level("l004")
	var sol: String = WhitePuzzleStore.load_json(SOLUTIONS)["l004"]
	var res := MazeChain.from_run(lv, sol)
	var levels := {"l004": lv}
	_clean()
	_write(PROFILE, _format1("l004", sol, res["ticks"], res["rings"]))
	var s := _open(levels)
	var disk := _read(PROFILE)
	var want := MazeChain.record(res["rings"], res["ticks"], res["links"])
	check.call(s.notice == "" and s.writable, "K11: a format 1 file opens without notice")
	var on_disk: Dictionary = disk["levels"]["l004"].get("chain", {})
	check.call(
		disk["format"] == 2 and not on_disk.is_empty() and int(on_disk["rings"]) == want["rings"]
			and int(on_disk["ticks"]) == want["ticks"] and on_disk["links"] == want["links"],
		"K11: the file on disk is format 2 with the replayed chain"
	)
	check.call(s.data["levels"]["l004"]["chain"] == want, "K11: the open profile holds the replayed chain")
	check.call(
		disk["levels"]["l004"]["best_run"] == sol and disk["levels"]["l004"]["counts"][DEV_A]["play_ticks"] == 500,
		"K11: the other fields survive the migration"
	)
	var bytes := FileAccess.get_file_as_string(PROFILE)
	var s2 := _open(levels)
	check.call(FileAccess.get_file_as_string(PROFILE) == bytes and s2.data["levels"] == s.data["levels"], "K11: a second open changes nothing")
	var damaged := false
	for f in DirAccess.get_files_at("user://"):
		damaged = damaged or f.begins_with("profile.damaged-")
	check.call(not damaged, "K11: a format 1 file is never set aside")
	# cases without a chain
	var long_script := "R%d" % (MazeChain.BACKFILL_MAX_TICKS + 1)
	var cases := {
		"empty best_run": _format1("l004", "", res["ticks"], res["rings"]),
		"wrong best_ticks": _format1("l004", sol, res["ticks"] + 1, res["rings"]),
		"wrong best_rings": _format1("l004", sol, res["ticks"], res["rings"] + 1),
		"script too long": _format1("l004", long_script, res["ticks"], res["rings"]),
		"script does not parse": _format1("l004", "X9", res["ticks"], res["rings"]),
		"script does not finish": _format1("l004", "R3", res["ticks"], res["rings"]),
	}
	for what: String in cases:
		_clean()
		_write(PROFILE, cases[what])
		var c := _open(levels)
		check.call(
			c.data["format"] == 2 and not c.data["levels"]["l004"].has("chain")
				and _read(PROFILE)["format"] == 2,
			"K11: %s gives no chain and format 2" % what
		)
	_clean()
	_write(PROFILE, _format1("l004", sol, res["ticks"], res["rings"]))
	var no_level := _open({})
	check.call(no_level.data["format"] == 2 and not no_level.data["levels"]["l004"].has("chain"), "K11: without the level in levels there is no chain")
	_clean()
	_write(PROFILE, _format1("l004", sol, res["ticks"], res["rings"]))
	var other := _open({"l004": MazeLevel.new()})
	check.call(not other.data["levels"]["l004"].has("chain"), "K11: an invalid level gets no chain")
