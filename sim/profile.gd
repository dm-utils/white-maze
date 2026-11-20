class_name MazeProfile
extends RefCounted
## Local profile: pure functions on a Dictionary, no file access (design 7). Format 1.

const FORMAT := 1
const GAME := "white-maze"
const MAX_RUN := 20000
const COUNTERS := ["starts", "finishes", "deaths", "play_ticks"]
const NO_VALUE := 1 << 60


static func create(device: String, lang: String, now: int) -> Dictionary:
	return {
		"format": FORMAT, "game": GAME, "tick_hz": MazeTuning.TICK_HZ, "device": device, "updated": now,
		"lang": lang if (lang == "nl" or lang == "en") else "nl", "levels": {},
	}


## {"profile": Dictionary or {}, "status": "ok" | "damaged" | "newer"}
static func sanitize(data: Variant) -> Dictionary:
	if not data is Dictionary or not _count(data.get("format")) or int(data["format"]) < 1:
		return {"profile": {}, "status": "damaged"}
	if int(data["format"]) > FORMAT:
		return {"profile": {}, "status": "newer"}
	var src := migrate(data)
	var out: Dictionary = src.duplicate(true)
	out["format"] = FORMAT
	out["game"] = GAME
	out["tick_hz"] = MazeTuning.TICK_HZ
	var device: Variant = src.get("device")
	out["device"] = device if (device is String and _is_hex16(device)) else ""
	if src.has("id"):
		if src["id"] is String and src["id"].length() >= 1 and src["id"].length() <= 64:
			out["id"] = src["id"]
		else:
			out.erase("id")
	out["updated"] = int(src["updated"]) if _count(src.get("updated")) else 0
	out["lang"] = src["lang"] if (src.get("lang") == "nl" or src.get("lang") == "en") else "nl"
	var levels := {}
	if src.get("levels") is Dictionary:
		for key in src["levels"]:
			if key is String and MazeLevel._valid_id(key) and src["levels"][key] is Dictionary:
				levels[key] = _sanitize_level(src["levels"][key])
	out["levels"] = levels
	return {"profile": out, "status": "ok"}


## older formats to the current one; format 1: unchanged copy
static func migrate(data: Dictionary) -> Dictionary:
	return data.duplicate(true)


static func record_start(p: Dictionary, level_id: String, now: int) -> void:
	var entry := _entry(p, level_id)
	_counts(p, entry)["starts"] += 1
	entry["last_played"] = now
	p["updated"] = now


static func add_play(p: Dictionary, level_id: String, ticks: int, deaths: int, now: int) -> void:
	var entry := _entry(p, level_id)
	var counts := _counts(p, entry)
	counts["play_ticks"] += maxi(ticks, 0)
	counts["deaths"] += maxi(deaths, 0)
	entry["last_played"] = now
	p["updated"] = now


## {"new_best": bool, "new_fewest": bool, "best_ticks": int, "fewest_beads": int}
static func record_finish(p: Dictionary, level_id: String, ticks: int, beads: int, run: String, now: int) -> Dictionary:
	var entry := _entry(p, level_id)
	_counts(p, entry)["finishes"] += 1
	var new_best: bool = not entry.has("best_ticks") or ticks < entry["best_ticks"]
	if new_best:
		entry["best_ticks"] = ticks
		entry["best_beads"] = beads
		entry["best_run"] = run if run.length() <= MAX_RUN else ""
	var new_fewest: bool = not entry.has("fewest_beads") or beads < entry["fewest_beads"] \
			or (beads == entry["fewest_beads"] and ticks < entry["fewest_ticks"])
	if new_fewest:
		entry["fewest_beads"] = beads
		entry["fewest_ticks"] = ticks
	if not entry.has("first_finish"):
		entry["first_finish"] = now
	entry["last_played"] = now
	p["updated"] = now
	return {"new_best": new_best, "new_fewest": new_fewest, "best_ticks": entry["best_ticks"],
			"fewest_beads": entry["fewest_beads"]}


## starts, finishes, deaths, play_ticks summed over devices
static func level_totals(p: Dictionary, level_id: String) -> Dictionary:
	var total := {"starts": 0, "finishes": 0, "deaths": 0, "play_ticks": 0}
	var levels: Variant = p.get("levels")
	if not (levels is Dictionary and levels.get(level_id) is Dictionary):
		return total
	var counts: Variant = levels[level_id].get("counts")
	if counts is Dictionary:
		for device in counts:
			for name in COUNTERS:
				total[name] += int(counts[device].get(name, 0))
	return total


static func is_finished(p: Dictionary, level_id: String) -> bool:
	var levels: Variant = p.get("levels")
	return levels is Dictionary and levels.get(level_id) is Dictionary and levels[level_id].has("best_ticks")


static func total_play_ticks(p: Dictionary) -> int:
	var total := 0
	var levels: Variant = p.get("levels")
	if levels is Dictionary:
		for id in levels:
			total += level_totals(p, id)["play_ticks"]
	return total


## new profile; both inputs are sanitized format-1 profiles (design 7.6)
static func merge(local: Dictionary, remote: Dictionary) -> Dictionary:
	var out: Dictionary = remote.duplicate(true)
	out.merge(local.duplicate(true), true)
	out["format"] = FORMAT
	out["game"] = GAME
	out["tick_hz"] = MazeTuning.TICK_HZ
	out["device"] = local.get("device", "")
	if remote.has("id"):
		out["id"] = remote["id"]
	elif local.has("id"):
		out["id"] = local["id"]
	var lu: int = local.get("updated", 0)
	var ru: int = remote.get("updated", 0)
	out["updated"] = maxi(lu, ru)
	out["lang"] = remote.get("lang", "nl") if ru > lu else local.get("lang", "nl")
	var levels := {}
	var ll: Dictionary = local.get("levels", {})
	var rl: Dictionary = remote.get("levels", {})
	var ids := {}
	for id in ll:
		ids[id] = true
	for id in rl:
		ids[id] = true
	for id in ids:
		levels[id] = _merge_level(ll.get(id, {}), rl.get(id, {}))
	out["levels"] = levels
	return out


static func _merge_level(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = b.duplicate(true)
	out.merge(a.duplicate(true), true)
	for key in ["best_ticks", "best_beads", "best_run", "fewest_beads", "fewest_ticks"]:
		out.erase(key)
	var pick_best := _better_best(a, b)
	if pick_best.has("best_ticks"):
		for key in ["best_ticks", "best_beads", "best_run"]:
			if pick_best.has(key):
				out[key] = pick_best[key]
	var pick_fewest := _better_fewest(a, b)
	if pick_fewest.has("fewest_beads"):
		out["fewest_beads"] = pick_fewest["fewest_beads"]
		out["fewest_ticks"] = pick_fewest.get("fewest_ticks", 0)
	var firsts := []
	for e in [a, b]:
		if e.has("first_finish"):
			firsts.append(e["first_finish"])
	if firsts.is_empty():
		out.erase("first_finish")
	else:
		out["first_finish"] = firsts.min()
	if a.has("last_played") or b.has("last_played"):
		out["last_played"] = maxi(a.get("last_played", 0), b.get("last_played", 0))
	var counts := {}
	for e in [b, a]:
		if e.get("counts") is Dictionary:
			for device in e["counts"]:
				if not counts.has(device):
					counts[device] = {}
				for name in COUNTERS:
					if e["counts"][device].has(name):
						counts[device][name] = maxi(counts[device].get(name, 0), e["counts"][device][name])
	out["counts"] = counts
	return out


static func _better_best(a: Dictionary, b: Dictionary) -> Dictionary:
	var ta: int = a.get("best_ticks", NO_VALUE)
	var tb: int = b.get("best_ticks", NO_VALUE)
	if ta < tb or (ta == tb and a.get("best_beads", NO_VALUE) <= b.get("best_beads", NO_VALUE)):
		return a
	return b


static func _better_fewest(a: Dictionary, b: Dictionary) -> Dictionary:
	var fa: int = a.get("fewest_beads", NO_VALUE)
	var fb: int = b.get("fewest_beads", NO_VALUE)
	if fa < fb or (fa == fb and a.get("fewest_ticks", NO_VALUE) <= b.get("fewest_ticks", NO_VALUE)):
		return a
	return b


static func _entry(p: Dictionary, level_id: String) -> Dictionary:
	if not p.get("levels") is Dictionary:
		p["levels"] = {}
	if not p["levels"].get(level_id) is Dictionary:
		p["levels"][level_id] = {}
	return p["levels"][level_id]


static func _counts(p: Dictionary, entry: Dictionary) -> Dictionary:
	if not entry.get("counts") is Dictionary:
		entry["counts"] = {}
	var device: String = p.get("device", "")
	if not entry["counts"].get(device) is Dictionary:
		entry["counts"][device] = {}
	var counts: Dictionary = entry["counts"][device]
	for name in COUNTERS:
		if not counts.has(name):
			counts[name] = 0
	return counts


static func _count(v: Variant) -> bool:
	return (v is int and v >= 0) or (v is float and is_finite(v) and v == floorf(v) and v >= 0.0)


static func _is_hex16(s: String) -> bool:
	if s.length() != 16:
		return false
	for i in 16:
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


static func _sanitize_level(src: Dictionary) -> Dictionary:
	var out: Dictionary = src.duplicate(true)
	for key in ["best_ticks", "best_beads", "fewest_beads", "fewest_ticks", "first_finish", "last_played"]:
		if src.has(key):
			if _count(src[key]):
				out[key] = int(src[key])
			else:
				out.erase(key)
	if src.has("best_run"):
		if src["best_run"] is String and src["best_run"].length() <= MAX_RUN:
			out["best_run"] = src["best_run"]
		else:
			out.erase("best_run")
	var counts := {}
	if src.get("counts") is Dictionary:
		for device in src["counts"]:
			if device is String and _is_hex16(device) and src["counts"][device] is Dictionary:
				var c := {}
				for name in COUNTERS:
					c[name] = int(src["counts"][device][name]) if _count(src["counts"][device].get(name)) else 0
				counts[device] = c
	out["counts"] = counts
	return out
