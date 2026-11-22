extends RefCounted
## Independent tests of the screens (phase 1b): profile file edge cases, unlocking through the main scene,
## aim and pause interplay, slow motion in the game loop, touch hit areas at other viewport sizes.

const PROFILE := "user://white_maze_test_tester.json"
const SOLUTIONS := "res://tests/solutions.json"

var _check: Callable
var _node: Node


func run(check: Callable, node: Node) -> void:
	_check = check
	_node = node
	_clean()
	_store_garbage()
	_store_idempotent()
	_unlock_chain()
	_aim_and_pause()
	_slow_motion_loop()
	_rotate_then_escape()
	_touch_geometry()
	_clean()
	WhiteText.lang = "nl"


func _clean() -> void:
	for p in [PROFILE, PROFILE + ".tmp"]:
		DirAccess.remove_absolute(p)
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("profile.damaged-"):
			DirAccess.remove_absolute("user://" + f)


func _write(bytes: PackedByteArray) -> void:
	var f := FileAccess.open(PROFILE, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


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


func _key(code: Key, down: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	return e


func _solution(id: String) -> Array:
	var script: String = WhitePuzzleStore.load_json(SOLUTIONS)[id]
	return MazeRunScript.parse(script)["inputs"]


func _play_solution(g: MazeGame, id: String) -> void:
	g.set_process(false)
	for inp: MazeInput in _solution(id):
		var c := g.controls
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
		g.advance(1.0 / 60.0)
		if g.sim.finished():
			break


func _store_garbage() -> void:
	var cases := {
		"empty file": PackedByteArray(),
		"json null": "null".to_utf8_buffer(),
		"json array": "[]".to_utf8_buffer(),
		"json number": "42".to_utf8_buffer(),
		"json string": '"hello"'.to_utf8_buffer(),
		"truncated": '{"format": 1, "levels": {'.to_utf8_buffer(),
		"bom prefix": PackedByteArray([0xEF, 0xBB, 0xBF]) + '{"format":1}'.to_utf8_buffer(),
		"binary": PackedByteArray([0, 255, 128, 7, 0, 1, 2, 3]),
		"format string": '{"format": "1"}'.to_utf8_buffer(),
		"format negative": '{"format": -3}'.to_utf8_buffer(),
		"format float": '{"format": 1.5}'.to_utf8_buffer(),
		"levels is a list": '{"format": 1, "levels": [1, 2]}'.to_utf8_buffer(),
	}
	for name in cases:
		_clean()
		_write(cases[name])
		var s := MazeProfileStore.new()
		s.open(PROFILE, 4242)
		var ok: bool = s.data.get("format") == 1 and s.data.get("levels") is Dictionary
		_check.call(ok, "store: '%s' gives a usable profile" % name)
		var again := MazeProfileStore.new()
		again.open(PROFILE, 4243)
		_check.call(again.notice == "" and again.data.get("format") == 1, "store: '%s' is repaired on disk" % name)
		var sel := MazeLevelSelect.new()
		var lv: Array[MazeLevel] = [MazeLevels.load_level("l001"), MazeLevels.load_level("l002")]
		sel.levels = lv
		sel.store = again
		_node.add_child(sel)
		_check.call(sel.cards.size() == 2, "store: '%s' still builds the level select" % name)
		_node.remove_child(sel)
		sel.free()
	_clean()
	# a profile with a finished level but odd stats must not break the card text
	var p := MazeProfile.create("0123456789abcdef", "nl", 1)
	p["levels"] = {"l001": {"best_ticks": 391, "best_rings": 1, "best_run": "R1"}}
	_write(JSON.stringify(p).to_utf8_buffer())
	var s2 := MazeProfileStore.new()
	s2.open(PROFILE, 5)
	var sel2 := MazeLevelSelect.new()
	var lv2: Array[MazeLevel] = [MazeLevels.load_level("l001"), MazeLevels.load_level("l002")]
	sel2.levels = lv2
	sel2.store = s2
	_node.add_child(sel2)
	_check.call(sel2.cards.size() == 2 and not sel2.cards[1].disabled, "store: a finished entry without a fewest pair still builds the select and unlocks level 2")
	_node.remove_child(sel2)
	sel2.free()
	_clean()


func _store_idempotent() -> void:
	_clean()
	var a := MazeProfileStore.new()
	a.open(PROFILE, 100)
	MazeProfile.record_start(a.data, "l001", 110)
	MazeProfile.record_finish(a.data, "l001", 391, 1, "R1", 120)
	a.save(130)
	var text1 := FileAccess.get_file_as_string(PROFILE)
	var b := MazeProfileStore.new()
	b.open(PROFILE, 140)
	b.save(130)
	var text2 := FileAccess.get_file_as_string(PROFILE)
	_check.call(text1 == text2, "store: open then save with the same clock is byte-identical")
	b.save(130)
	b.save(130)
	_check.call(FileAccess.get_file_as_string(PROFILE) == text1, "store: saving repeatedly changes nothing")
	_check.call(not FileAccess.file_exists(PROFILE + ".tmp"), "store: no temp file after saves")
	# a stale temp file from a crashed write does not disturb the next open or save
	var f := FileAccess.open(PROFILE + ".tmp", FileAccess.WRITE)
	f.store_string("half a wri")
	f.close()
	var c := MazeProfileStore.new()
	c.open(PROFILE, 150)
	_check.call(c.notice == "" and MazeProfile.is_finished(c.data, "l001"), "store: a stale temp file is ignored")
	_check.call(c.save(160) and not FileAccess.file_exists(PROFILE + ".tmp"), "store: save replaces a stale temp file")
	_clean()


func _unlock_chain() -> void:
	WhiteText.lang = "nl"
	_clean()
	var m := _main()
	_check.call(
		not m.select.cards[0].disabled and m.select.cards[1].disabled and m.select.cards[2].disabled,
		"unlock: a new profile opens only level 1"
	)
	m.start_level(0)
	_play_solution(m.game, "l001")
	_check.call(m.game.overlays.result_visible(), "unlock: l001 solution finishes")
	m.show_select()
	_check.call(
		not m.select.cards[1].disabled and m.select.cards[2].disabled,
		"unlock: finishing l001 opens l002 only, not l003"
	)
	_close(m)
	# the unlock survives a restart of the program
	var m2 := _main()
	_check.call(not m2.select.cards[1].disabled and m2.select.cards[2].disabled, "unlock: saved across a restart")
	m2.start_level(1)
	_play_solution(m2.game, "l002")
	_check.call(m2.game.overlays.result_visible(), "unlock: l002 solution finishes")
	m2.show_select()
	_check.call(not m2.select.cards[2].disabled, "unlock: finishing l002 opens l003")
	_close(m2)
	# a debug start of a locked level does not unlock the next one
	_clean()
	var m3 := _main(["--level=l003"])
	_check.call(m3.game != null and m3.game.level.id == "l003", "unlock: --level starts a locked level")
	m3.game.set_process(false)
	m3.show_select()
	_check.call(m3.select.cards[2].disabled, "unlock: starting l003 does not open it in the profile")
	_close(m3)
	# last level: Enter leaves to the select
	var m4 := _main(["--level=l009", "--solve"])
	var left := [false]
	m4.game.levels_requested.connect(func() -> void: left[0] = true)
	m4.game._input(_key(KEY_ENTER))
	_check.call(left[0], "unlock: Enter on the last level's result opens the level select")
	_close(m4)
	# the keyboard focus lands on the first open, unfinished level
	_clean()
	var m5 := _main()
	_check.call(m5.select.cards[0].has_focus(), "select: focus starts on the first open level")
	_close(m5)
	_clean()


func _aim_and_pause() -> void:
	_clean()
	var m := _main(["--level=l002"])
	var g := m.game
	g.set_process(false)
	var c := g.controls
	for i in 3:
		g.advance(1.0 / 60.0)
	c.handle_event(_key(KEY_J))
	g.advance(1.0 / 60.0)
	_check.call(c.aiming() and g.rate < 1.0, "aim+pause: J aims and slows the game down")
	g.pause()
	_check.call(not c.aiming() and g.rate == 0.0, "aim+pause: pausing cancels the aim and stops the game")
	c.handle_event(_key(KEY_J, false))
	g.resume()
	var beads := g.sim.beads_left
	for i in 5:
		g.advance(1.0 / 60.0)
	_check.call(g.sim.beads_left == beads, "aim+pause: releasing J after a pause throws nothing")
	# focus loss pauses
	g._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check.call(g.paused, "pause: losing application focus pauses the game")
	g.resume()
	# restart while aiming and while a throw is latched
	c.handle_event(_key(KEY_J))
	c.handle_event(_key(KEY_J, false))
	g.restart()
	_check.call(c.take_throw() == -1 and not c.aiming(), "restart: a latched throw does not survive the restart")
	# a restart on the result screen with R
	_close(m)
	var s := _main(["--level=l001", "--solve"])
	_check.call(s.game.overlays.result_visible(), "result: shown after --solve")
	s.game.controls.handle_event(_key(KEY_R))
	s.game.advance(1.0 / 60.0)
	_check.call(not s.game.overlays.result_visible() and s.game.sim.tick <= 1, "result: R restarts the level")
	_close(s)
	# the finish cancels aim and removes the throw ability
	var f := _main(["--level=l001", "--solve"])
	f.game.advance(1.0 / 60.0)
	_check.call(not f.game.controls.can_aim(), "result: after the finish no aiming is possible")
	f.game.pause()
	_check.call(not f.game.paused, "result: pause is not possible after the finish")
	_close(f)
	_clean()


func _slow_motion_loop() -> void:
	_clean()
	var m := _main(["--level=l002"])
	var g := m.game
	g.set_process(false)
	g.advance(1.0 / 60.0)
	g.controls.handle_event(_key(KEY_J))
	for i in 12: # ramp
		g.advance(1.0 / 60.0)
	var t0 := g.sim.tick
	for i in 120: # 2 s real time at 60 fps
		g.advance(1.0 / 60.0)
	var ticks := g.sim.tick - t0
	_check.call(absi(ticks - 30) <= 2, "slow motion: 30 ticks over 2 s of aiming in the game loop (%d)" % ticks)
	_check.call(g.world.modulate.r < 1.0, "slow motion: the world is dimmed while aiming")
	g.controls.handle_event(_key(KEY_K))
	for i in 10:
		g.advance(1.0 / 60.0)
	_check.call(is_equal_approx(g.rate, 1.0) and g.world.modulate.r == 1.0, "slow motion: back to full rate after K")
	# a long frame is capped: at most 6 ticks
	var t1 := g.sim.tick
	g.advance(1.0)
	_check.call(g.sim.tick - t1 <= 6, "slow motion: a one second frame gives at most 6 ticks")
	# no aiming without beads: use up the supply on a level with thrown rings
	_close(m)
	_clean()


func _rotate_then_escape() -> void:
	_clean()
	var m := _main(["--level=l001"])
	var g := m.game
	g.set_process(false)
	var win := _node.get_window()
	var old := win.size
	win.size = Vector2i(720, 1280)
	g.advance(1.0 / 60.0)
	var vs := g.get_viewport().get_visible_rect().size
	if vs.y > vs.x:
		g.controls.handle_event(_key(KEY_ESCAPE))
		g.advance(1.0 / 60.0)
		var tick := g.sim.tick
		g.controls.touch_move(1)
		for i in 20:
			g.advance(1.0 / 60.0)
		_check.call(
			not (g.overlays.rotate_visible() and g.sim.tick > tick),
			"rotate: Esc under the rotate hint does not start the game behind it"
		)
	else:
		_check.call(false, "rotate: window could not be made portrait")
	win.size = old
	_close(m)
	_clean()


func _touch_geometry() -> void:
	var sizes := [Vector2(1280, 720), Vector2(1600, 720), Vector2(2000, 720), Vector2(1280, 1000)]
	var insets := [
		{"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0},
		{"left": 60.0, "top": 0.0, "right": 60.0, "bottom": 24.0},
	]
	for size: Vector2 in sizes:
		for ins: Dictionary in insets:
			var o := MazeTouchOverlay.new()
			o.layout(size, ins)
			var j := o.jump_center()
			var t := o.throw_center()
			var tag := "%dx%d ins %d" % [size.x, size.y, ins["left"]]
			_check.call(
				j.distance_to(t) > MazeTouchOverlay.JUMP_HIT + MazeTouchOverlay.THROW_HIT,
				"touch geometry %s: jump and throw hit areas do not overlap" % tag
			)
			_check.call(
				t.x - MazeTouchOverlay.THROW_HIT > MazeTouchOverlay.MOVE_ZONE * size.x,
				"touch geometry %s: the throw stick lies outside the move zone" % tag
			)
			_check.call(
				j.y - MazeTouchOverlay.JUMP_HIT >= o.top_band() and t.y - MazeTouchOverlay.THROW_HIT >= o.top_band(),
				"touch geometry %s: right-hand controls stay below the HUD band" % tag
			)
			_check.call(
				j.x + MazeTouchOverlay.JUMP_R <= size.x - ins["right"],
				"touch geometry %s: the jump button stays inside the safe area" % tag
			)
			o.free()
