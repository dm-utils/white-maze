extends RefCounted
## U1-U7, U9: the main scene in the test tree (profile under user://white_maze_test_*).

const PROFILE := "user://white_maze_test_ui.json"
const SOLUTIONS := "res://tests/solutions.json"

var _check: Callable
var _node: Node


func run(check: Callable, node: Node) -> void:
	_check = check
	_node = node
	_clean()
	_args()
	_select()
	_language()
	_solution_flow()
	_hud_buttons()
	_pause_restart()
	_rotate()
	_hud_score()
	_texts()
	_start_options()
	_clean()
	WhiteText.lang = "nl"


func _clean() -> void:
	for p in [PROFILE, PROFILE + ".tmp"]:
		DirAccess.remove_absolute(p)


func _main(extra: Array = []) -> MazeMain:
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	var list := PackedStringArray(["--profile=" + PROFILE, "--speed=100"])
	list.append_array(PackedStringArray(extra))
	m.args = list
	_node.add_child(m)
	return m


func _close(m: MazeMain) -> void:
	_node.remove_child(m)
	m.free()


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += n.text + "\n"
	if n is Button:
		out += n.text + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out


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


func _solution(id: String) -> Array:
	var script: String = WhitePuzzleStore.load_json(SOLUTIONS)[id]
	return MazeRunScript.parse(script)["inputs"]


func _args() -> void:
	var o := MazeMain.parse_args(
		PackedStringArray(["--level=l002", "--all-levels", "--lang=en", "--touch", "--safe=1,2,3,4", "--print-run",
			"--keys=R5 J3", "--solve", "--aim=30", "--pause", "--shot=/x.png", "--profile=/p.json"])
	)
	_check.call(
		o["level"] == "l002" and o["all_levels"] and o["lang"] == "en" and o["touch"] and o["safe"] == "1,2,3,4",
		"debug arguments: level, all-levels, lang, touch, safe"
	)
	_check.call(
		o["print_run"] and o["keys"] == "R5 J3" and o["solve"] and o["aim"] == 30 and o["pause"],
		"debug arguments: print-run, keys, solve, aim, pause"
	)
	_check.call(o["shot"] == "/x.png" and o["profile"] == "/p.json", "debug arguments: shot, profile")
	var cam := MazeMain.parse_args(PackedStringArray(["--camera=overview"]))
	var bad := MazeMain.parse_args(PackedStringArray(["--camera=nope"]))
	_check.call(cam["camera"] == "overview" and bad["camera"] == "", "debug argument --camera takes door or overview")
	var d := MazeMain.parse_args(PackedStringArray())
	_check.call(d["level"] == "" and not d["all_levels"] and d["aim"] == -1, "no arguments give the defaults")


func _select() -> void:
	WhiteText.lang = "nl"
	var m := _main()
	var s := m.select
	_check.call(s != null and s.cards.size() == 9, "U1: the main scene opens the level select with nine cards")
	_check.call(
		not s.cards[0].disabled and s.cards[1].disabled and s.cards[2].disabled,
		"U1: with an empty profile only card 1 is enabled"
	)
	_check.call("Op slot" in s.cards[1].text, "U1: a locked card says it is locked")
	MazeProfile.record_start(m.store.data, "l001", 10)
	MazeProfile.record_finish(m.store.data, "l001", 391, 1, "R1", 11)
	m.show_select()
	s = m.select
	_check.call(not s.cards[1].disabled and s.cards[2].disabled, "U1: after a finish of l001 card 2 is enabled")
	_check.call("Beste tijd 0:06.51" in s.cards[0].text, "U1: card 1 shows the best time")
	_check.call("Minste ringen 1 · par 1" in s.cards[0].text, "U1: card 1 shows the fewest rings line")
	_check.call("Gehaald 1/9" in s.subtitle.text, "the subtitle counts finished levels")
	_close(m)
	var all := _main(["--all-levels"])
	_check.call(not all.select.cards[8].disabled, "--all-levels opens every level")
	_close(all)
	# a damaged profile shows its notice
	var f := FileAccess.open(PROFILE, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	var d := _main()
	_check.call(d.select.notice_label.visible and "beschadigd" in d.select.notice_label.text, "a notice is shown")
	_close(d)
	for p in DirAccess.get_files_at("user://"):
		if p.begins_with("profile.damaged-"):
			DirAccess.remove_absolute("user://" + p)
	_clean()


func _language() -> void:
	WhiteText.lang = "nl"
	var m := _main()
	var nl := _all_text(m.select)
	_check.call("Gehaald" in nl and "Eerste ring" in nl and "Makkelijk" in nl, "U2: Dutch texts at first")
	m.toggle_language()
	var en := _all_text(m.select)
	_check.call(
		"Finished" in en and "First ring" in en and "Easy" in en and "Gehaald" not in en,
		"U2: the toggle switches every visible text"
	)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	_check.call(saved["lang"] == "en", "U2: the language is saved in the profile")
	_close(m)
	var again := _main()
	_check.call(WhiteText.lang == "en", "the saved language is used at the next start")
	_close(again)
	var over := _main(["--lang=nl"])
	_check.call(WhiteText.lang == "nl", "U2: --lang overrides for the session")
	over.toggle_language()
	_close(over)
	_clean()
	WhiteText.lang = "nl"


func _solution_flow() -> void:
	WhiteText.lang = "nl"
	var m := _main(["--level=l001"])
	var g := m.game
	g.set_process(false)
	_check.call(g != null and m.select == null, "--level starts that level directly")
	var totals := MazeProfile.level_totals(m.store.data, "l001")
	_check.call(totals["starts"] == 1, "opening a level counts a start")
	var n := 0
	for inp: MazeInput in _solution("l001"):
		_feed(g, inp)
		n += 1
		if g.sim.finished():
			break
	_check.call(g.sim.finished(), "U3: the solution through the controls finishes the level")
	_check.call(g.overlays.result_visible(), "U3: the result overlay is shown")
	var text := _all_text(g.overlays)
	_check.call(MazeFormat.time(g.sim.time_ticks()) in text, "U3: the result shows the time")
	_check.call("Ringen: 1 · par 1" in text, "U3: the result shows the rings and par")
	_check.call("Precies par!" in text, "U3: the result says perfect")
	_check.call("Nieuw record" in text, "U3: the result says new record")
	var entry: Dictionary = m.store.data["levels"]["l001"]
	_check.call(entry["best_rings"] == 1 and entry["fewest_rings"] == 1, "U3: the profile has the finish with 1 ring")
	_check.call(entry["best_ticks"] == g.sim.time_ticks(), "U3: the profile has the finish time")
	_check.call(entry["best_run"] != "", "the run is recorded")
	var replay := MazeRunScript.run(MazeLevels.load_level("l001"), entry["best_run"])
	_check.call(
		replay != null and replay.finished() and replay.time_ticks() == g.sim.time_ticks(),
		"the recorded run replays to the same finish"
	)
	# Enter opens the next level
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	g._input(key)
	_check.call(m.game != null and m.game.level.id == "l002", "Enter on the result opens the next level")
	_close(m)
	# a second, slower finish keeps the best time and shows it
	var m2 := _main(["--level=l001"])
	var g2 := m2.game
	g2.set_process(false)
	var slow := _solution("l001")
	for i in 30:
		_feed(g2, MazeInput.idle())
	for inp: MazeInput in slow:
		_feed(g2, inp)
		if g2.sim.finished():
			break
	_check.call(g2.overlays.result_visible() and not g2.last_result["new_best"], "a slower finish is no new record")
	_check.call("Beste tijd 0:06.51" in _all_text(g2.overlays), "a slower finish shows the best time")
	_close(m2)
	_clean()


func _hud_buttons() -> void:
	var m := _main(["--level=l001"])
	var g := m.game
	g.set_process(false)
	var ok := true
	for b in g.hud.buttons():
		ok = ok and b.focus_mode == Control.FOCUS_NONE
	_check.call(ok and g.hud.buttons().size() == 3, "U4: the HUD buttons take no focus")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	g.advance(1.0 / 60.0)
	_check.call(g.get_viewport().gui_get_focus_owner() == null, "U4: Space never focuses or presses a button")
	var release := space.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	_close(m)
	_clean()


func _pause_restart() -> void:
	var m := _main(["--level=l001"])
	var g := m.game
	g.set_process(false)
	g.controls.touch_move(1)
	for i in 10:
		g.advance(1.0 / 60.0)
	var tick := g.sim.tick
	_check.call(tick > 0, "the simulation runs")
	g.pause()
	_check.call(g.paused and g.overlays.pause_visible(), "U5: pause opens the overlay")
	for i in 30:
		g.advance(1.0 / 60.0)
	_check.call(g.sim.tick == tick, "U5: pause stops ticks over 30 frames")
	var text := _all_text(g.overlays)
	_check.call(
		"A/D of pijltjes" in text and "Par telt de ringen" in text, "the pause overlay shows the help and help_par"
	)
	g.resume()
	for i in 30:
		g.advance(1.0 / 60.0)
	_check.call(not g.paused and g.sim.tick > tick, "U5: resume continues")
	var old := g.sim
	g.restart()
	_check.call(g.sim != old and g.sim.tick == 0, "U5: restart creates a fresh simulation")
	_check.call(MazeProfile.level_totals(m.store.data, "l001")["starts"] == 2, "U5: restart counts a start")
	_check.call(MazeProfile.level_totals(m.store.data, "l001")["play_ticks"] > 0, "restart flushes the played ticks")
	# keys: Esc pauses and resumes
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	g.controls.handle_event(esc)
	g.advance(1.0 / 60.0)
	_check.call(g.paused, "Esc pauses")
	g.controls.handle_event(esc)
	g.advance(1.0 / 60.0)
	_check.call(not g.paused, "Esc resumes")
	g.pause()
	var levels_requested := [false]
	g.levels_requested.connect(func() -> void: levels_requested[0] = true)
	g.leave()
	_check.call(levels_requested[0], "leaving asks for the level select")
	_close(m)
	_clean()


func _rotate() -> void:
	var m := _main(["--level=l001"])
	var g := m.game
	g.set_process(false)
	var win := _node.get_window()
	var old := win.size
	win.size = Vector2i(720, 1280)
	g.advance(1.0 / 60.0)
	var portrait := g.get_viewport().get_visible_rect().size
	if portrait.y > portrait.x:
		_check.call(
			g.overlays.rotate_visible() and g.paused, "U6: a portrait viewport shows the rotate hint and pauses"
		)
		win.size = old
		g.advance(1.0 / 60.0)
		_check.call(not g.overlays.rotate_visible() and g.paused, "U6: turning back keeps the pause overlay")
	else:
		_check.call(false, "U6: the test window could not be made portrait")
	win.size = old
	_close(m)
	_clean()


func _hud_score() -> void:
	WhiteText.lang = "nl"
	var m := _main(["--level=l001"])
	var g := m.game
	g.set_process(false)
	g.hud._process(0.0)
	_check.call(g.hud._score.text == "Ringen 0 · par 1", "U9: the score line starts at 'Ringen 0 · par 1'")
	_check.call(g.hud._name.text == "1 · Eerste ring", "the HUD shows number and name")
	var launched := false
	for inp: MazeInput in _solution("l001"):
		_feed(g, inp)
		if g.sim.rings_used == 1:
			launched = true
			break
	_check.call(launched, "the solution's own ring launches the player")
	g.hud._process(0.0)
	_check.call(g.hud._score.text == "Ringen 1 · par 1", "U9: after the first launch the line reads 'Ringen 1 · par 1'")
	var left := g.sim.beads_left
	g.controls.queue_undo()
	g.advance(1.0 / 60.0)
	g.hud._process(0.0)
	_check.call(g.sim.beads_left == left + 1, "U9: a bead back refills a bead dot")
	_check.call(
		g.hud._score.text == "Ringen 1 · par 1", "U9: the line still reads 'Ringen 1 · par 1' after a bead back"
	)
	_check.call(g.hud.clock_text() == MazeFormat.time(g.sim.time_ticks()), "the clock shows game time")
	g.restart()
	g.hud._process(0.0)
	_check.call(g.hud._score.text == "Ringen 0 · par 1", "U9: a restart shows 'Ringen 0 · par 1' again")
	_close(m)
	_clean()


func _texts() -> void:
	_check.call(MazeFormat.time(0) == "0:00.00", "U7: time 0")
	_check.call(MazeFormat.time(59) == "0:00.98", "U7: time 59 ticks")
	_check.call(MazeFormat.time(60) == "0:01.00", "U7: time 60 ticks")
	_check.call(MazeFormat.time(216000) == "60:00.00", "U7: time 216000 ticks")
	_check.call(MazeFormat.time(-5) == "0:00.00", "U7: negative time")
	var nl: Dictionary = MazeStrings.TEXT["nl"]
	var en: Dictionary = MazeStrings.TEXT["en"]
	_check.call(nl.keys() == en.keys(), "U7: every text key exists in both languages")
	_check.call(
		not nl.has("card_beads") and not nl.has("result_beads") and not en.has("card_beads"),
		"U7: the bead keys of the first design no longer exist"
	)
	var lv := MazeLevels.load_level("l001")
	WhiteText.lang = "nl"
	_check.call("A/D" in MazeStrings.hint(lv, false) and "Spatie" in MazeStrings.hint(lv, false), "hint with keys")
	_check.call("springknop" in MazeStrings.hint(lv, true), "hint with touch controls")
	_check.call("{" not in MazeStrings.hint(lv, true), "no placeholder is left in the hint")


func _start_options() -> void:
	WhiteText.lang = "nl"
	var m := _main(["--level=l001", "--keys=R10 RJ5", "--aim=30", "--pause"])
	var g := m.game
	g.set_process(false)
	_check.call(g.sim.tick == 15 and g.frozen, "--keys steps the script at once and freezes")
	_check.call(g.world.aim_index == 30, "--aim shows the aim preview")
	_check.call(g.paused and g.overlays.pause_visible(), "--pause opens the pause overlay")
	_close(m)
	var s := _main(["--level=l001", "--solve"])
	_check.call(s.game.overlays.result_visible(), "--solve ends in the result overlay")
	_close(s)
	_clean()
