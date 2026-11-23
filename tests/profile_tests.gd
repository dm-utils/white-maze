extends RefCounted
## P1-P3, P5, P6: profile format, sanitize, statistics, merge. The file store is in profile_store_tests.gd.

const DEV_A := "9f2c4a1b7e3d5a60"
const DEV_B := "00112233445566ff"


func run(check: Callable, _node: Node) -> void:
	_create(check)
	_sanitize(check)
	_stats(check)
	_merge(check)
	_size(check)


func _create(check: Callable) -> void:
	var p := MazeProfile.create(DEV_A, "en", 100)
	check.call(
		(
			p["format"] == 2
			and p["game"] == "white-maze"
			and p["tick_hz"] == 60
			and p["device"] == DEV_A
			and p["updated"] == 100
			and p["lang"] == "en"
			and p["levels"] == {}
		),
		"create gives all top-level fields"
	)
	check.call(MazeProfile.create(DEV_A, "xx", 1)["lang"] == "nl", "create falls back to nl for an unknown language")
	check.call(not p.has("id"), "no id in phase 1")
	var s := MazeProfile.sanitize(p)
	check.call(s["status"] == "ok" and s["profile"] == p, "a fresh profile survives sanitize unchanged")


func _status(data: Variant) -> String:
	return MazeProfile.sanitize(data)["status"]


func _sanitize(check: Callable) -> void:
	for case in [
		["not a dictionary", [1, 2]],
		["null", null],
		["format missing", {"game": "x"}],
		["format string", {"format": "1"}],
		["format zero", {"format": 0}],
		["format fraction", {"format": 0.5}],
		["format negative", {"format": -1}]
	]:
		var r := MazeProfile.sanitize(case[1])
		check.call(r["status"] == "damaged" and r["profile"] == {}, "%s is damaged" % case[0])
	var newer := MazeProfile.sanitize({"format": 3})
	check.call(newer["status"] == "newer" and newer["profile"] == {}, "format 3 is newer")
	check.call(_status({"format": 1.0}) == "ok", "format 1.0 from JSON is accepted")
	var ok_profile := {
		"format": 1,
		"game": "other",
		"tick_hz": 30,
		"device": "XYZ",
		"updated": 5.0,
		"lang": "fr",
		"id": "x".repeat(65),
		"extra": {"keep": true},
		"levels":
		{
			"l001":
			{
				"best_ticks": 100.0,
				"best_rings": 2.0,
				"best_run": 5,
				"fewest_rings": 1.5,
				"first_finish": 7,
				"last_played": 9,
				"unknown_level_key": "kept",
				"counts":
				{DEV_A: {"starts": 3.0, "finishes": -2, "deaths": 1.5, "play_ticks": 10}, "nothex": {"starts": 1}},
			},
			"BAD KEY": {"best_ticks": 1},
			"l002": "not a dict",
		},
	}
	var p: Dictionary = MazeProfile.sanitize(ok_profile)["profile"]
	check.call(p["game"] == "white-maze" and p["tick_hz"] == 60, "game and tick_hz are forced")
	check.call(p["device"] == "" and p["lang"] == "nl", "bad device becomes empty, bad lang becomes nl")
	check.call(not p.has("id"), "an id of 65 characters is dropped")
	check.call(MazeProfile.sanitize({"format": 1, "id": "abc"})["profile"]["id"] == "abc", "a valid id is kept")
	check.call(p["extra"] == {"keep": true}, "unknown top-level keys are kept")
	check.call(p["updated"] == 5 and p["updated"] is int, "whole floats become ints")
	check.call(p["levels"].keys() == ["l001"], "a bad level key and a non-dictionary entry are dropped")
	var e: Dictionary = p["levels"]["l001"]
	check.call(
		e["best_ticks"] == 100 and e["best_ticks"] is int and e["first_finish"] == 7, "valid numbers are kept as ints"
	)
	check.call(
		e["best_rings"] == 2 and e["best_rings"] is int and not e.has("fewest_rings") and not e.has("best_run"),
		"fractional and wrongly typed fields are dropped, whole floats kept"
	)
	var pairs: Dictionary = MazeProfile.sanitize({"format": 1, "levels": {"l001": {
		"best_ticks": 100, "best_rings": -1, "fewest_rings": 1, "best_run": "R5",
	}}})["profile"]["levels"]["l001"]
	check.call(
		not pairs.has("best_ticks") and not pairs.has("best_rings") and not pairs.has("fewest_rings")
		and not pairs.has("best_run"),
		"linked fields go together: a bad partner drops the pair (best_run without best_ticks too)"
	)
	check.call(e["unknown_level_key"] == "kept", "unknown keys inside a level are kept")
	check.call(e["counts"].keys() == [DEV_A], "counts with a bad device key are dropped")
	var c: Dictionary = e["counts"][DEV_A]
	check.call(c == {"starts": 3, "finishes": 0, "deaths": 0, "play_ticks": 10}, "bad counters become 0 (%s)" % str(c))
	var long := MazeProfile.sanitize(
		{"format": 1, "levels": {"l001": {"best_run": "R".repeat(MazeProfile.MAX_RUN + 1)}}}
	)
	check.call(not long["profile"]["levels"]["l001"].has("best_run"), "an overlong best_run is dropped")
	check.call(
		MazeProfile.sanitize({"format": 1, "levels": 5})["profile"]["levels"] == {},
		"levels that is not a dictionary becomes empty"
	)
	check.call(MazeProfile.migrate({"format": 1, "a": 1}) == {"format": 2, "a": 1}, "migrate raises format 1 to 2")


func _stats(check: Callable) -> void:
	var p := MazeProfile.create(DEV_A, "nl", 1)
	check.call(
		not MazeProfile.is_finished(p, "l001") and MazeProfile.level_totals(p, "l001")["starts"] == 0,
		"nothing recorded yet"
	)
	MazeProfile.record_start(p, "l001", 10)
	check.call(
		(
			p["levels"]["l001"]["counts"][DEV_A]["starts"] == 1
			and p["levels"]["l001"]["last_played"] == 10
			and p["updated"] == 10
		),
		"record_start creates the entry and counts"
	)
	MazeProfile.add_play(p, "l001", 500, 2, 20)
	var counts: Dictionary = p["levels"]["l001"]["counts"][DEV_A]
	check.call(
		counts["play_ticks"] == 500 and counts["deaths"] == 2 and p["updated"] == 20, "add_play adds ticks and deaths"
	)
	var r := MazeProfile.record_finish(p, "l001", 900, 2, "R40", 30)
	var e: Dictionary = p["levels"]["l001"]
	check.call(
		(
			r["new_best"]
			and r["new_fewest"]
			and e["best_ticks"] == 900
			and e["best_rings"] == 2
			and e["best_run"] == "R40"
			and e["fewest_rings"] == 2
			and e["fewest_ticks"] == 900
			and e["first_finish"] == 30
		),
		"first finish sets best and fewest"
	)
	check.call(e["counts"][DEV_A]["finishes"] == 1 and MazeProfile.is_finished(p, "l001"), "finishes counted")
	r = MazeProfile.record_finish(p, "l001", 1200, 2, "slow", 40)
	check.call(
		(
			not r["new_best"]
			and not r["new_fewest"]
			and e["best_ticks"] == 900
			and e["best_run"] == "R40"
			and e["first_finish"] == 30
			and e["last_played"] == 40
		),
		"a slower finish keeps the best and the first finish"
	)
	r = MazeProfile.record_finish(p, "l001", 1500, 1, "few", 50)
	check.call(
		(
			not r["new_best"]
			and r["new_fewest"]
			and e["best_ticks"] == 900
			and e["fewest_rings"] == 1
			and e["fewest_ticks"] == 1500
			and r["fewest_rings"] == 1
		),
		"fewer beads but slower updates only fewest"
	)
	r = MazeProfile.record_finish(p, "l001", 1400, 1, "few2", 60)
	check.call(r["new_fewest"] and e["fewest_ticks"] == 1400, "same beads and faster updates fewest")
	r = MazeProfile.record_finish(p, "l001", 800, 3, "fast", 70)
	check.call(
		r["new_best"] and not r["new_fewest"] and e["best_rings"] == 3 and e["best_run"] == "fast",
		"faster finish with more beads updates only best"
	)
	MazeProfile.record_finish(p, "l002", 100, 1, "R".repeat(MazeProfile.MAX_RUN + 1), 80)
	check.call(p["levels"]["l002"]["best_run"] == "", "an overlong run is stored as an empty string")
	MazeProfile.record_start(p, "l002", 90)
	var totals := MazeProfile.level_totals(p, "l001")
	check.call(
		totals == {"starts": 1, "finishes": 5, "deaths": 2, "play_ticks": 500},
		"level_totals sums the counters (%s)" % str(totals)
	)
	check.call(MazeProfile.total_play_ticks(p) == 500, "total_play_ticks sums over levels")
	# a second device adds to the totals
	p["levels"]["l001"]["counts"][DEV_B] = {"starts": 2, "finishes": 1, "deaths": 0, "play_ticks": 40}
	check.call(MazeProfile.level_totals(p, "l001")["play_ticks"] == 540, "totals include other devices")


func _level(
	best: int, beads: int, fewest_b: int, fewest_t: int, counts: Dictionary, extra: Dictionary = {}
) -> Dictionary:
	var e := {
		"best_ticks": best,
		"best_rings": beads,
		"best_run": "run%d" % best,
		"fewest_rings": fewest_b,
		"fewest_ticks": fewest_t,
		"first_finish": 100 + best,
		"last_played": best,
		"counts": counts
	}
	e.merge(extra, true)
	return e


func _profile(device: String, updated: int, lang: String, levels: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var p := MazeProfile.create(device, lang, updated)
	p["levels"] = levels
	p.merge(extra, true)
	return p


func _merge(check: Callable) -> void:
	var c1 := {DEV_A: {"starts": 3, "finishes": 1, "deaths": 2, "play_ticks": 900}}
	var c2 := {DEV_B: {"starts": 5, "finishes": 2, "deaths": 1, "play_ticks": 700}}
	var local := _profile(DEV_A, 50, "nl", {"l001": _level(900, 2, 2, 900, c1)})
	var remote := _profile(DEV_B, 60, "en", {"l001": _level(800, 3, 1, 1500, c2), "l002": _level(500, 1, 1, 500, c2)})
	var m := MazeProfile.merge(local, remote)
	var e: Dictionary = m["levels"]["l001"]
	check.call(
		e["best_ticks"] == 800 and e["best_rings"] == 3 and e["best_run"] == "run800",
		"best comes from remote as a group"
	)
	check.call(e["fewest_rings"] == 1 and e["fewest_ticks"] == 1500, "fewest comes from remote as a group")
	check.call(
		e["first_finish"] == 900 and e["last_played"] == 900, "first_finish is the minimum, last_played the maximum"
	)
	check.call(
		e["counts"].size() == 2 and e["counts"][DEV_A]["play_ticks"] == 900 and e["counts"][DEV_B]["starts"] == 5,
		"counts from two devices are united"
	)
	check.call(
		m["levels"].has("l002") and m["device"] == DEV_A and m["updated"] == 60 and m["lang"] == "en",
		"levels united, device from local, updated maximum, lang from the newer profile"
	)
	# tie goes to local
	var tie_l := _profile(DEV_A, 70, "nl", {"l001": _level(800, 2, 2, 800, c1, {"best_run": "local"})})
	var tie_r := _profile(DEV_B, 70, "en", {"l001": _level(800, 2, 2, 800, c2, {"best_run": "remote"})})
	var tie := MazeProfile.merge(tie_l, tie_r)
	check.call(tie["levels"]["l001"]["best_run"] == "local" and tie["lang"] == "nl", "ties go to local (best, lang)")
	# tie on ticks broken by rings
	var b_l := _profile(DEV_A, 1, "nl", {"l001": _level(800, 3, 3, 800, c1)})
	var b_r := _profile(DEV_B, 1, "nl", {"l001": _level(800, 2, 2, 800, c2)})
	check.call(MazeProfile.merge(b_l, b_r)["levels"]["l001"]["best_rings"] == 2, "equal best ticks: fewer rings wins")
	# equal fewest rings: the faster finish wins, as a group
	var f_l := _profile(DEV_A, 1, "nl", {"l001": _level(900, 3, 2, 900, c1)})
	var f_r := _profile(DEV_B, 1, "nl", {"l001": _level(950, 3, 2, 700, c2)})
	var f_e: Dictionary = MazeProfile.merge(f_l, f_r)["levels"]["l001"]
	check.call(f_e["fewest_rings"] == 2 and f_e["fewest_ticks"] == 700, "equal fewest rings: faster finish wins")
	# an absent best counts as infinite
	var none_l := _profile(DEV_A, 1, "nl", {"l001": {"counts": c1, "last_played": 5}})
	var none := MazeProfile.merge(none_l, remote)
	check.call(
		none["levels"]["l001"]["best_ticks"] == 800 and none["levels"]["l001"]["last_played"] == 800,
		"an absent best loses"
	)
	var none2 := MazeProfile.merge(remote, none_l)
	check.call(none2["levels"]["l001"]["best_ticks"] == 800, "an absent best loses on the other side too")
	# id from remote, else local
	var id_l := _profile(DEV_A, 1, "nl", {}, {"id": "local-id"})
	var id_r := _profile(DEV_B, 1, "nl", {}, {"id": "remote-id"})
	check.call(
		MazeProfile.merge(id_l, id_r)["id"] == "remote-id" and MazeProfile.merge(id_l, remote).get("id") == "local-id",
		"id from remote when present, else local"
	)
	# unknown keys: local wins, else remote
	var u_l := _profile(DEV_A, 1, "nl", {"l001": _level(1, 1, 1, 1, c1, {"x": "l"})}, {"a": "local"})
	var u_r := _profile(
		DEV_B, 1, "nl", {"l001": _level(1, 1, 1, 1, c2, {"x": "r", "y": "r"})}, {"a": "remote", "b": "remote"}
	)
	var u := MazeProfile.merge(u_l, u_r)
	check.call(
		(
			u["a"] == "local"
			and u["b"] == "remote"
			and u["levels"]["l001"]["x"] == "l"
			and u["levels"]["l001"]["y"] == "r"
		),
		"unknown keys: local when present, else remote"
	)
	# same device on both sides: maximum per counter, never a sum
	var same_l := _profile(
		DEV_A,
		1,
		"nl",
		{"l001": _level(1, 1, 1, 1, {DEV_A: {"starts": 3, "finishes": 1, "deaths": 0, "play_ticks": 100}})}
	)
	var same_r := _profile(
		DEV_A,
		1,
		"nl",
		{"l001": _level(1, 1, 1, 1, {DEV_A: {"starts": 2, "finishes": 4, "deaths": 0, "play_ticks": 90}})}
	)
	var same := MazeProfile.merge(same_l, same_r)
	check.call(
		same["levels"]["l001"]["counts"][DEV_A] == {"starts": 3, "finishes": 4, "deaths": 0, "play_ticks": 100},
		"a device is never double counted: maximum per counter"
	)
	check.call(MazeProfile.level_totals(same, "l001")["starts"] == 3, "totals after a merge do not double count")
	# properties
	check.call(MazeProfile.merge(local, local) == local, "merge(a, a) == a")
	var ab := MazeProfile.merge(local, remote)
	var ba := MazeProfile.merge(remote, local)
	check.call(ab["levels"] == ba["levels"], "merge(a, b) and merge(b, a) have equal levels without ties")
	var s: Dictionary = MazeProfile.sanitize(ab)
	check.call(s["status"] == "ok" and s["profile"]["levels"] == ab["levels"], "a merge result is a valid profile")


func _size(check: Callable) -> void:
	var p := MazeProfile.create(DEV_A, "nl", 1)
	for i in 30:
		var id := "l%03d" % i
		p["levels"][id] = _level(
			1000 + i,
			1,
			1,
			1000 + i,
			{
				DEV_A: {"starts": 10, "finishes": 5, "deaths": 20, "play_ticks": 100000},
				DEV_B: {"starts": 11, "finishes": 6, "deaths": 21, "play_ticks": 100001}
			},
			{"best_run": "R40 RJ12 ".repeat(222).substr(0, 2000)}
		)
	var size := JSON.stringify(p).length()
	print("profile with 30 levels: %d bytes" % size)
	check.call(
		size < 100 * 1024, "a profile with 30 levels and 2000-character runs stays under 100 KB (%d bytes)" % size
	)
