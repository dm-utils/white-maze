class_name MazeMain
extends Control
## Root scene: parses the debug arguments, opens the profile and switches between level select and game.
## Debug (after --): --level=<id> --all-levels --lang=nl|en --touch --safe=l,t,r,b --profile=<path> --print-run
## --keys=<script> --solve --aim=<index> --pause --camera=door|overview --world=temple|jungle|cave --fps --shot=<png>
## --speed=<50-150> (percent of 60 ticks per second, overrides the level curve)
## --chain-t=<seconds> (freeze the result chain at that time) --reduced-motion (no chain animation)
## --chain-export (the result shows only the share card) --demo-profile (with --shot: finished levels from the
## stored solutions, for the mini chains on the level select)
## --lab (the test series res://levels/lab/ instead of the levels, every card open, profile in memory only)
## Web: the same keys as query parameters, a subset: ?fps&world=cave&level=l001 (see QUERY_KEYS).

const BG := Color("#1B1F26")
const SHOT_WAIT_S := 0.5
const REDUCED_MOTION_JS := "!!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches)"
# no profile path, shot or solve from a URL
const QUERY_KEYS := ["fps", "world", "level", "camera", "lang", "touch", "speed", "lab"]
const QUERY_FLAGS := ["fps", "touch", "lab"]

var args := PackedStringArray()
var use_cmdline := true # tests set this false and fill args

var opts := {}
var store: MazeProfileStore
var level_ids := PackedStringArray()
var levels: Array[MazeLevel] = []
var select: MazeLevelSelect
var game: MazeGame
var current_index := -1


## URL query string (with or without the leading ?) to debug arguments; unknown keys and odd values are dropped
static func query_args(query: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in query.trim_prefix("?").split("&", false):
		var key := part.get_slice("=", 0)
		if key not in QUERY_KEYS:
			continue
		var value := part.get_slice("=", 1).uri_decode() if part.contains("=") else ""
		if key in QUERY_FLAGS:
			if value not in ["0", "false"]:
				out.append("--" + key)
			continue
		var ok := not value.is_empty()
		for ch in value:
			ok = ok and (ch in "abcdefghijklmnopqrstuvwxyz0123456789_-")
		if ok:
			out.append("--%s=%s" % [key, value])
	return out


## debug arguments to a Dictionary
static func parse_args(list: PackedStringArray) -> Dictionary:
	var o := {
		"level": "", "all_levels": false, "lang": "", "touch": false, "safe": "", "profile": "", "print_run": false,
		"keys": "", "solve": false, "aim": -1, "pause": false, "shot": "", "camera": "", "world": "", "fps": false,
		"speed": 0, "chain_t": -1.0, "reduced_motion": false,
		"chain_export": false, "demo_profile": false, "lab": false,
	}
	for a in list:
		if a.begins_with("--level="):
			o["level"] = a.get_slice("=", 1)
		elif a == "--all-levels":
			o["all_levels"] = true
		elif a.begins_with("--lang="):
			o["lang"] = a.get_slice("=", 1)
		elif a == "--touch":
			o["touch"] = true
		elif a.begins_with("--safe="):
			o["safe"] = a.get_slice("=", 1)
		elif a.begins_with("--profile="):
			o["profile"] = a.get_slice("=", 1)
		elif a == "--print-run":
			o["print_run"] = true
		elif a.begins_with("--keys="):
			o["keys"] = a.substr(7).replace(",", " ") # commas let a script with spaces fit one scenario argument
		elif a == "--solve":
			o["solve"] = true
		elif a.begins_with("--aim=") and a.get_slice("=", 1).is_valid_int():
			o["aim"] = int(a.get_slice("=", 1))
		elif a == "--pause":
			o["pause"] = true
		elif a.begins_with("--shot="):
			o["shot"] = a.substr(7)
		elif a.begins_with("--world="):
			var w := a.get_slice("=", 1)
			if MazeWorlds.from_name(w) >= 0:
				o["world"] = w
			else:
				push_warning("--world: unknown world '%s'" % w)
		elif a.begins_with("--speed="):
			var v := a.get_slice("=", 1)
			var lo := MazeGame.SPEED_MIN_PCT
			var hi := MazeGame.SPEED_MAX_PCT
			if v.is_valid_int() and int(v) >= lo and int(v) <= hi:
				o["speed"] = int(v)
			else:
				push_warning("--speed: expected %d to %d, got '%s'" % [lo, hi, v])
		elif a.begins_with("--chain-t="):
			var v := a.get_slice("=", 1)
			if v.is_valid_float() and float(v) >= 0.0:
				o["chain_t"] = float(v)
			else:
				push_warning("--chain-t: expected seconds >= 0, got '%s'" % v)
		elif a == "--reduced-motion":
			o["reduced_motion"] = true
		elif a == "--chain-export":
			o["chain_export"] = true
		elif a == "--demo-profile":
			o["demo_profile"] = true
		elif a == "--fps":
			o["fps"] = true
		elif a == "--lab":
			o["lab"] = true
		elif a.begins_with("--camera="):
			var v := a.get_slice("=", 1)
			if v == "door" or v == "overview":
				o["camera"] = v
			else:
				push_warning("--camera: unknown view '%s'" % v)
	return o


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if use_cmdline:
		args = OS.get_cmdline_user_args()
		if OS.has_feature("web"):
			args.append_array(query_args(str(JavaScriptBridge.eval("window.location.search", true))))
	opts = parse_args(args)
	opts["shot_mode"] = opts["shot"] != ""
	if OS.has_feature("web") and JavaScriptBridge.eval(REDUCED_MOTION_JS, true):
		opts["reduced_motion"] = true
	MazeStrings.register()
	var now := int(Time.get_unix_time_from_system())
	var dir: String = MazeLevels.LAB_DIR if opts["lab"] else MazeLevels.DIR
	level_ids = MazeLevels.ids(dir)
	var valid := {}
	for id in level_ids:
		var lv := MazeLevels.load_level(id, dir)
		if lv.valid():
			valid[id] = lv
		else:
			push_error("level %s is invalid: %s" % [id, "; ".join(lv.errors)])
		levels.append(lv)
	store = MazeProfileStore.new()
	if opts["shot_mode"] or opts["lab"]:
		store.open_memory(opts["lang"] if opts["lang"] != "" else "nl", now)
	else:
		store.open(opts["profile"] if opts["profile"] != "" else MazeProfileStore.DEFAULT_PATH, now, valid)
	if opts["demo_profile"]:
		if opts["shot_mode"]:
			fill_demo_profile(store.data, levels)
		else:
			push_warning("--demo-profile only works with --shot")
	WhiteText.lang = str(store.data.get("lang", "nl"))
	if opts["lang"] != "" and WhiteText.has_lang(opts["lang"]):
		WhiteText.lang = opts["lang"]
	var start := level_ids.find(opts["level"]) if opts["level"] != "" else -1
	if start >= 0:
		start_level(start)
	else:
		show_select()
	if opts["shot_mode"]:
		_take_shot(opts["shot"])


## every level with a stored solution finished by replaying it (design 22.15)
static func fill_demo_profile(p: Dictionary, list: Array[MazeLevel]) -> void:
	var solutions := WhitePuzzleStore.load_json("res://tests/solutions.json")
	for lv in list:
		if not (lv.valid() and solutions.get(lv.id) is String):
			continue
		var script: String = solutions[lv.id]
		var r := MazeChain.from_run(lv, script)
		if not (r["ok"] and r["finished"]):
			continue
		MazeProfile.record_start(p, lv.id, 0)
		MazeProfile.record_finish(p, lv.id, r["ticks"], r["rings"], script, 0, MazeChain.encode(r["links"]))


func _debug_game_options() -> Dictionary:
	return {
		"keys": opts["keys"], "solve": opts["solve"], "aim": opts["aim"], "pause": opts["pause"],
		"shot": opts["shot_mode"], "print_run": opts["print_run"], "touch": opts["touch"], "safe": opts["safe"],
		"camera": opts["camera"], "world": opts["world"], "fps": opts["fps"], "speed": opts["speed"],
		"chain_t": opts["chain_t"], "reduced_motion": opts["reduced_motion"], "chain_export": opts["chain_export"],
	}


func show_select() -> void:
	_clear()
	select = MazeLevelSelect.new()
	select.levels = levels
	select.store = store
	select.all_open = opts["all_levels"] or opts["lab"]
	select.safe_override = opts["safe"]
	select.level_chosen.connect(start_level)
	select.language_toggled.connect(toggle_language)
	add_child(select)
	current_index = -1


func start_level(index: int) -> void:
	if index < 0 or index >= levels.size() or not levels[index].valid():
		return
	_clear()
	store.notice = ""
	game = MazeGame.new()
	game.setup(levels[index], index + 1, levels.size(), store, _debug_game_options())
	game.levels_requested.connect(show_select)
	game.next_requested.connect(func() -> void: start_level(index + 1))
	add_child(game)
	current_index = index


func toggle_language() -> void:
	WhiteText.lang = WhiteText.next_lang()
	store.data["lang"] = WhiteText.lang
	store.save(int(Time.get_unix_time_from_system()))
	show_select()


func _clear() -> void:
	for n: Node in [select, game]:
		if n != null and is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	select = null
	game = null


func _take_shot(path: String) -> void:
	await get_tree().create_timer(SHOT_WAIT_S).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	get_tree().quit()
