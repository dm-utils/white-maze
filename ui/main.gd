class_name MazeMain
extends Control
## Root scene: parses the debug arguments, opens the profile and switches between level select and game.
## Debug (after --): --level=<id> --all-levels --lang=nl|en --touch --safe=l,t,r,b --profile=<path> --print-run
## --keys=<script> --solve --aim=<index> --pause --camera=door|overview --shot=<png>

const BG := Color("#1B1F26")
const SHOT_WAIT_S := 0.5

var args := PackedStringArray()
var use_cmdline := true # tests set this false and fill args

var opts := {}
var store: MazeProfileStore
var level_ids := PackedStringArray()
var levels: Array[MazeLevel] = []
var select: MazeLevelSelect
var game: MazeGame
var current_index := -1


## debug arguments to a Dictionary
static func parse_args(list: PackedStringArray) -> Dictionary:
	var o := {
		"level": "", "all_levels": false, "lang": "", "touch": false, "safe": "", "profile": "", "print_run": false,
		"keys": "", "solve": false, "aim": -1, "pause": false, "shot": "", "camera": "",
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
			o["keys"] = a.substr(7)
		elif a == "--solve":
			o["solve"] = true
		elif a.begins_with("--aim=") and a.get_slice("=", 1).is_valid_int():
			o["aim"] = int(a.get_slice("=", 1))
		elif a == "--pause":
			o["pause"] = true
		elif a.begins_with("--shot="):
			o["shot"] = a.substr(7)
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
	opts = parse_args(args)
	opts["shot_mode"] = opts["shot"] != ""
	MazeStrings.register()
	var now := int(Time.get_unix_time_from_system())
	store = MazeProfileStore.new()
	if opts["shot_mode"]:
		store.open_memory(opts["lang"] if opts["lang"] != "" else "nl", now)
	else:
		store.open(opts["profile"] if opts["profile"] != "" else MazeProfileStore.DEFAULT_PATH, now)
	WhiteText.lang = str(store.data.get("lang", "nl"))
	if opts["lang"] != "" and WhiteText.has_lang(opts["lang"]):
		WhiteText.lang = opts["lang"]
	level_ids = MazeLevels.ids()
	for id in level_ids:
		var lv := MazeLevels.load_level(id)
		if not lv.valid():
			push_error("level %s is invalid: %s" % [id, "; ".join(lv.errors)])
		levels.append(lv)
	var start := level_ids.find(opts["level"]) if opts["level"] != "" else -1
	if start >= 0:
		start_level(start)
	else:
		show_select()
	if opts["shot_mode"]:
		_take_shot(opts["shot"])


func _debug_game_options() -> Dictionary:
	return {
		"keys": opts["keys"], "solve": opts["solve"], "aim": opts["aim"], "pause": opts["pause"],
		"shot": opts["shot_mode"], "print_run": opts["print_run"], "touch": opts["touch"], "safe": opts["safe"],
		"camera": opts["camera"],
	}


func show_select() -> void:
	_clear()
	select = MazeLevelSelect.new()
	select.levels = levels
	select.store = store
	select.all_open = opts["all_levels"]
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
