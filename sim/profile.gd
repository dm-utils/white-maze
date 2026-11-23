class_name MazeProfile
extends RefCounted
## Local profile: pure functions on a Dictionary, no file access (design 7, 22.9). Format 2: format 1 plus the
## chain record per level.

const FORMAT := 2
const GAME := "white-maze"
const MAX_RUN := 20000
const COUNTERS := ["starts", "finishes", "deaths", "play_ticks"]
const MAX_COUNT := 1 << 53
const NO_VALUE := 1 << 60


static func create(device: String, lang: String, now: int) -> Dictionary:
	return {
		"format": FORMAT, "game": GAME, "tick_hz": MazeTuning.TICK_HZ, "device": device, "updated": now,
		"lang": lang if (lang == "nl" or lang == "en") else "nl", "levels": {},
	}


## {"profile": Dictionary or {}, "status": "ok" | "damaged" | "newer", "migrated": bool}
## levels: id -> MazeLevel, only used to backfill chains when migrating from format 1 (design 22.9.5)
static func sanitize(data: Variant, levels: Dictionary = {}) -> Dictionary:
	if not data is Dictionary or not _count(data.get("format")) or int(data["format"]) < 1:
		return {"profile": {}, "status": "damaged", "migrated": false}
	if int(data["format"]) > FORMAT:
		return {"profile": {}, "status": "newer", "migrated": false}
	var from := int(data["format"])
	var src: Dictionary = migrate(data) if from < FORMAT else data
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
	out["lang"] = _lang(src.get("lang"))
	var entries := {}
	if src.get("levels") is Dictionary:
		for key in src["levels"]:
			if key is String and MazeLevel._valid_id(key) and src["levels"][key] is Dictionary:
				entries[key] = _sanitize_level(src["levels"][key])
	out["levels"] = entries
	var migrated := from < FORMAT
	if migrated:
		backfill_chains(out, levels)
	return {"profile": out, "status": "ok", "migrated": migrated}


## older formats to the current one; format 1 to 2 changes no structure
static func migrate(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	if _count(out.get("format")) and int(out["format"]) < FORMAT:
		out["format"] = FORMAT
	return out


## chain of the fastest run for every finished level without one; number of chains added (design 22.9.5)
static func backfill_chains(p: Dictionary, levels: Dictionary) -> int:
	var added := 0
	var entries: Variant = p.get("levels")
	if not entries is Dictionary:
		return 0
	for id in entries:
		var entry: Dictionary = entries[id]
		var lv: Variant = levels.get(id)
		if entry.has("chain") or not lv is MazeLevel or not lv.valid():
			continue
		var script: String = entry.get("best_run", "")
		if script.is_empty() or not entry.has("best_ticks") or not entry.has("best_rings"):
			continue
		var parsed := MazeRunScript.parse(script)
		if not parsed["ok"] or parsed["inputs"].size() > MazeChain.BACKFILL_MAX_TICKS:
			continue
		var r := MazeChain.from_run(lv, script, MazeChain.BACKFILL_MAX_TICKS)
		if r["ok"] and r["finished"] and r["ticks"] == entry["best_ticks"] and r["rings"] == entry["best_rings"] \
				and r["links"].size() <= MazeChain.MAX_LINKS:
			entry["chain"] = MazeChain.record(r["rings"], r["ticks"], r["links"])
			added += 1
	return added


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


## {"new_best": bool, "new_fewest": bool, "new_chain": bool, "best_ticks": int, "fewest_rings": int}
## links: link text of the finish; null or unparsable leaves the chain record alone
static func record_finish(
	p: Dictionary, level_id: String, ticks: int, rings: int, run: String, now: int, links: Variant = null
) -> Dictionary:
	var entry := _entry(p, level_id)
	_counts(p, entry)["finishes"] += 1
	var new_best: bool = not entry.has("best_ticks") or ticks < entry["best_ticks"]
	if new_best:
		entry["best_ticks"] = ticks
		entry["best_rings"] = rings
		entry["best_run"] = run if run.length() <= MAX_RUN else ""
	var new_fewest: bool = not entry.has("fewest_rings") or rings < entry["fewest_rings"] \
			or (rings == entry["fewest_rings"] and ticks < entry["fewest_ticks"])
	if new_fewest:
		entry["fewest_rings"] = rings
		entry["fewest_ticks"] = ticks
	var new_chain := false
	if links is String and MazeChain.parse(links)["ok"]:
		var cand := {"rings": rings, "ticks": ticks, "links": links}
		if MazeChain.better(cand, entry.get("chain", {})):
			entry["chain"] = cand
			new_chain = true
	if not entry.has("first_finish"):
		entry["first_finish"] = now
	entry["last_played"] = now
	p["updated"] = now
	return {"new_best": new_best, "new_fewest": new_fewest, "new_chain": new_chain, "best_ticks": entry["best_ticks"],
			"fewest_rings": entry["fewest_rings"]}


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


## new profile; both inputs are sanitized profiles (design 7.6, 22.9.4)
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
	out["lang"] = _lang(remote.get("lang")) if ru > lu else _lang(local.get("lang"))
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
	for key in ["best_ticks", "best_rings", "best_run", "fewest_rings", "fewest_ticks", "chain"]:
		out.erase(key)
	var chain_a: Dictionary = a.get("chain", {})
	var chain_b: Dictionary = b.get("chain", {})
	if not chain_a.is_empty() or not chain_b.is_empty():
		out["chain"] = chain_b.duplicate() if MazeChain.better(chain_b, chain_a) else chain_a.duplicate()
	var pick_best := _better_best(a, b)
	if pick_best.has("best_ticks") and pick_best.has("best_rings"):
		for key in ["best_ticks", "best_rings", "best_run"]:
			if pick_best.has(key):
				out[key] = pick_best[key]
	var pick_fewest := _better_fewest(a, b)
	if pick_fewest.has("fewest_rings") and pick_fewest.has("fewest_ticks"):
		out["fewest_rings"] = pick_fewest["fewest_rings"]
		out["fewest_ticks"] = pick_fewest["fewest_ticks"]
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
	if ta < tb or (ta == tb and a.get("best_rings", NO_VALUE) <= b.get("best_rings", NO_VALUE)):
		return a
	return b


static func _better_fewest(a: Dictionary, b: Dictionary) -> Dictionary:
	var fa: int = a.get("fewest_rings", NO_VALUE)
	var fb: int = b.get("fewest_rings", NO_VALUE)
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


static func _lang(v: Variant) -> String:
	return v if (v is String and (v == "nl" or v == "en")) else "nl"


## whole number 0..MAX_COUNT; beyond that int() would wrap
static func _count(v: Variant) -> bool:
	return (v is int and v >= 0 and v <= MAX_COUNT) or (v is float and is_finite(v) and v == floorf(v) and v >= 0.0 \
			and v <= float(MAX_COUNT))


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
	for key in ["best_ticks", "best_rings", "fewest_rings", "fewest_ticks", "first_finish", "last_played"]:
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
	# linked fields stay whole or go together
	for pair in [["best_ticks", "best_rings"], ["fewest_rings", "fewest_ticks"]]:
		if not (out.has(pair[0]) and out.has(pair[1])):
			out.erase(pair[0])
			out.erase(pair[1])
	if not out.has("best_ticks"):
		out.erase("best_run")
	if src.has("chain"):
		var chain := _sanitize_chain(src["chain"])
		if chain.is_empty():
			out.erase("chain")
		else:
			out["chain"] = chain
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


## closed record {rings, ticks, links}, or {} when invalid
static func _sanitize_chain(v: Variant) -> Dictionary:
	if not v is Dictionary or v.size() != 3:
		return {}
	var d: Dictionary = v
	if not (d.has("rings") and d.has("ticks") and d.has("links")):
		return {}
	if not (_count(d["rings"]) and _count(d["ticks"]) and d["links"] is String):
		return {}
	if d["links"].length() > MazeChain.MAX_LINKS_TEXT:
		return {}
	var parsed := MazeChain.parse(d["links"])
	if not parsed["ok"] or MazeChain.bead_count(parsed["links"]) != int(d["rings"]):
		return {}
	return {"rings": int(d["rings"]), "ticks": int(d["ticks"]), "links": d["links"]}
