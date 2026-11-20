extends RefCounted
## C1-C6: keyboard, mouse and touch intents, latching, slow motion.

var _check: Callable


func run(check: Callable, _node: Node) -> void:
	_check = check
	_keyboard()
	_latching()
	_keyboard_aim()
	_mouse()
	_touch()
	_slow_motion()


static func key(code: Key, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e


static func mouse(button: MouseButton, pos: Vector2, pressed: bool, device := 0) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.position = pos
	e.pressed = pressed
	e.device = device
	return e


func _keyboard() -> void:
	var c := MazeControls.new()
	c.handle_event(key(KEY_D))
	_check.call(c.move() == 1, "D walks right")
	c.handle_event(key(KEY_A))
	_check.call(c.move() == 0, "A and D together cancel")
	c.handle_event(key(KEY_D, false))
	_check.call(c.move() == -1, "A alone walks left")
	c.handle_event(key(KEY_A, false))
	c.handle_event(key(KEY_RIGHT))
	_check.call(c.move() == 1, "the arrow keys walk too")
	c.handle_event(key(KEY_RIGHT, false))
	_check.call(c.move() == 0, "released keys stop")
	c.handle_event(key(KEY_W))
	_check.call(c.jump_held() and c.take_jump_pressed(), "W jumps when not aiming")
	c.handle_event(key(KEY_W, false))
	c.handle_event(key(KEY_SPACE))
	_check.call(c.jump_held() and c.take_jump_pressed(), "Space jumps")
	c.handle_event(key(KEY_SPACE, false))
	_check.call(not c.jump_held(), "a released jump key is not held")
	c.handle_event(key(KEY_UP))
	_check.call(c.jump_held() and c.take_jump_pressed(), "Up jumps")
	c.handle_event(key(KEY_UP, false))
	c.handle_event(key(KEY_Z))
	_check.call(c.take_undo() and not c.take_undo(), "Z gives one undo")
	c.handle_event(key(KEY_BACKSPACE))
	_check.call(c.take_undo(), "Backspace undoes too")
	c.handle_event(key(KEY_R))
	_check.call(c.take_restart() and not c.take_restart(), "R restarts once")
	c.handle_event(key(KEY_P))
	_check.call(c.take_pause(), "P pauses")
	c.handle_event(key(KEY_ESCAPE))
	_check.call(c.take_pause(), "Esc pauses when not aiming")
	var echo := key(KEY_D)
	echo.echo = true
	c.handle_event(echo)
	_check.call(c.move() == 0, "key echoes are ignored")
	# W while aiming turns the aim and does not jump, Space still jumps
	c.handle_event(key(KEY_J))
	_check.call(c.aiming(), "J starts aiming")
	c.handle_event(key(KEY_W))
	_check.call(not c.jump_held() and not c.take_jump_pressed(), "W does not jump while aiming")
	c.handle_event(key(KEY_W, false))
	c.handle_event(key(KEY_SPACE))
	_check.call(c.jump_held() and c.take_jump_pressed(), "Space jumps while aiming")


func _latching() -> void:
	var c := MazeControls.new()
	c.handle_event(key(KEY_SPACE))
	c.handle_event(key(KEY_SPACE, false))
	_check.call(c.take_jump_pressed(), "a jump press and release between ticks still gives a press")
	_check.call(not c.take_jump_pressed(), "a press is consumed once")
	c.handle_event(key(KEY_J))
	c.handle_event(key(KEY_J, false))
	_check.call(c.take_throw() == 18, "a throw between ticks is latched")
	_check.call(c.take_throw() == -1, "a throw is consumed once")
	c.touch_throw(40)
	_check.call(c.take_throw() == 40 and c.take_throw() == -1, "a touch throw is latched and consumed once")
	c.handle_event(key(KEY_Z))
	c.handle_event(key(KEY_Z, false))
	_check.call(c.take_undo(), "an undo between ticks is latched")
	c.touch_jump(true)
	c.touch_jump(false)
	_check.call(c.take_jump_pressed() and not c.jump_held(), "a touch jump press is latched")


func _keyboard_aim() -> void:
	var c := MazeControls.new()
	c.set_facing(1)
	c.handle_event(key(KEY_J))
	_check.call(c.aiming() and c.aim_index() == 18, "keyboard aim starts at 45 degrees up facing right")
	c.handle_event(key(KEY_W))
	_check.call(c.aim_index() == 24, "W turns the aim up by 6")
	c.handle_event(key(KEY_W, false))
	c.handle_event(key(KEY_S))
	c.handle_event(key(KEY_S, false))
	c.handle_event(key(KEY_S))
	c.handle_event(key(KEY_S, false))
	_check.call(c.aim_index() == 12, "S turns the aim down by 6 per step")
	for i in 12:
		c.handle_event(key(KEY_W))
		c.handle_event(key(KEY_W, false))
	_check.call(c.aim_index() == 36 and c.elevation() == 6, "the aim stops at elevation 6")
	for i in 20:
		c.handle_event(key(KEY_S))
		c.handle_event(key(KEY_S, false))
	_check.call(c.aim_index() == posmod(-36, 144) and c.elevation() == -6, "the aim stops at elevation -6")
	c.handle_event(key(KEY_J, false))
	_check.call(c.take_throw() == 108, "releasing J throws at the aim")
	# facing left mirrors
	var l := MazeControls.new()
	l.set_facing(-1)
	l.handle_event(key(KEY_J))
	_check.call(l.aim_index() == 54, "facing left starts at index 54")
	# the elevation survives within an attempt, not across attempts
	l.handle_event(key(KEY_W))
	l.handle_event(key(KEY_W, false))
	l.handle_event(key(KEY_J, false))
	l.take_throw()
	l.handle_event(key(KEY_J))
	_check.call(l.aim_index() == 48, "the elevation is kept for the next throw")
	l.handle_event(key(KEY_J, false))
	l.take_throw()
	l.reset_attempt()
	l.handle_event(key(KEY_J))
	_check.call(l.aim_index() == 54, "a new attempt resets the elevation")
	# cancel with K and with Esc
	var k := MazeControls.new()
	k.handle_event(key(KEY_J))
	k.handle_event(key(KEY_K))
	_check.call(not k.aiming(), "K cancels the aim")
	k.handle_event(key(KEY_J, false))
	_check.call(k.take_throw() == -1, "releasing J after K throws nothing")
	k.handle_event(key(KEY_J))
	k.handle_event(key(KEY_ESCAPE))
	k.handle_event(key(KEY_J, false))
	_check.call(k.take_throw() == -1 and not k.take_pause(), "Esc cancels an aim first, no pause, no throw")
	k.handle_event(key(KEY_ESCAPE))
	_check.call(k.take_pause(), "Esc pauses when not aiming")
	# no aiming without beads
	var n := MazeControls.new()
	n.set_can_aim(false)
	n.handle_event(key(KEY_J))
	_check.call(not n.aiming(), "no aiming while set_can_aim(false)")
	n.handle_event(key(KEY_J, false))
	_check.call(n.take_throw() == -1, "no throw while set_can_aim(false)")
	# repeat of held aim keys: first after 0.25 s, then every 0.1 s
	var r := MazeControls.new()
	r.handle_event(key(KEY_J))
	r.handle_event(key(KEY_W))
	var e0 := r.elevation()
	r.update(0.2)
	_check.call(r.elevation() == e0, "no repeat before 0.25 s")
	r.update(0.06)
	_check.call(r.elevation() == e0 + 1, "first repeat after 0.25 s")
	r.update(0.1)
	_check.call(r.elevation() == e0 + 2, "then one step per 0.1 s")
	r.handle_event(key(KEY_W, false))
	r.update(1.0)
	_check.call(r.elevation() == e0 + 2, "no repeat after release")


func _mouse() -> void:
	var c := MazeControls.new()
	c.set_player_screen_pos(Vector2(400, 300))
	c.handle_event(mouse(MOUSE_BUTTON_LEFT, Vector2(500, 300), true))
	_check.call(c.aiming() and c.aim_index() == 0, "left press aims at the cursor (right = 0)")
	var move := InputEventMouseMotion.new()
	move.position = Vector2(400, 200)
	c.handle_event(move)
	_check.call(c.aim_index() == 36, "the aim follows the cursor (up = 36)")
	c.handle_event(mouse(MOUSE_BUTTON_LEFT, Vector2(300, 300), false))
	_check.call(c.take_throw() == 72 and not c.aiming(), "release throws towards the cursor (left = 72)")
	c.handle_event(mouse(MOUSE_BUTTON_LEFT, Vector2(500, 300), true))
	c.handle_event(mouse(MOUSE_BUTTON_RIGHT, Vector2(500, 300), true))
	_check.call(not c.aiming(), "right button cancels")
	c.handle_event(mouse(MOUSE_BUTTON_LEFT, Vector2(500, 300), false))
	_check.call(c.take_throw() == -1, "release after cancel throws nothing")
	c.handle_event(mouse(MOUSE_BUTTON_LEFT, Vector2(500, 300), true, InputEvent.DEVICE_ID_EMULATION))
	_check.call(not c.aiming(), "emulated mouse events are ignored")
	var em := InputEventMouseMotion.new()
	em.device = InputEvent.DEVICE_ID_EMULATION
	em.position = Vector2(1, 1)
	_check.call(not c.handle_event(em), "emulated motion is ignored")


func _overlay() -> Array:
	var c := MazeControls.new()
	var o := MazeTouchOverlay.new()
	o.controls = c
	o.layout(Vector2(1280, 720), {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})
	return [c, o]


static func touch(idx: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	return e


static func drag(idx: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	return e


func _touch() -> void:
	var s := _overlay()
	var c: MazeControls = s[0]
	var o: MazeTouchOverlay = s[1]
	o.handle_event(touch(0, Vector2(200, 400), true))
	o.handle_event(drag(0, Vector2(230, 400)))
	_check.call(c.move() == 1, "a drag of +30 px in the left zone moves right")
	o.handle_event(drag(0, Vector2(190, 400)))
	_check.call(c.move() == 0, "a drag of -10 px is inside the dead zone")
	o.handle_event(drag(0, Vector2(210, 400)))
	_check.call(c.move() == 0, "a drag of +10 px is no move")
	o.handle_event(drag(0, Vector2(150, 400)))
	_check.call(c.move() == -1, "a drag of -50 px moves left")
	o.handle_event(touch(0, Vector2(150, 400), false))
	_check.call(c.move() == 0, "lifting the finger stops")
	# the base follows a far finger
	o.handle_event(touch(0, Vector2(100, 400), true))
	o.handle_event(drag(0, Vector2(400, 400)))
	o.handle_event(drag(0, Vector2(330, 400)))
	_check.call(c.move() == 1, "the base follows a finger pulled far away")
	o.handle_event(touch(0, Vector2(330, 400), false))
	# jump button
	var j := o.jump_center()
	o.handle_event(touch(1, j, true))
	_check.call(c.jump_held() and c.take_jump_pressed(), "a touch on the jump button is a press and held")
	o.handle_event(touch(1, j, false))
	_check.call(not c.jump_held(), "lifting releases the jump")
	# throw stick: 50 px to the upper right is index 18
	var t := o.throw_center()
	o.handle_event(touch(2, t, true))
	o.handle_event(drag(2, t + Vector2(35.36, -35.36)))
	_check.call(c.aiming() and absi(c.aim_index() - 18) <= 1, "dragging 50 px to the upper right aims at 18")
	o.handle_event(touch(2, t + Vector2(35.36, -35.36), false))
	_check.call(absi(c.take_throw() - 18) <= 1 and not c.aiming(), "lifting throws")
	# back into the dead zone: no throw
	o.handle_event(touch(2, t, true))
	o.handle_event(drag(2, t + Vector2(50, 0)))
	o.handle_event(drag(2, t + Vector2(5, 0)))
	_check.call(not c.aiming(), "back in the dead zone stops aiming")
	o.handle_event(touch(2, t + Vector2(5, 0), false))
	_check.call(c.take_throw() == -1, "lifting in the dead zone throws nothing")
	# a tap does nothing
	o.handle_event(touch(2, t, true))
	o.handle_event(touch(2, t, false))
	_check.call(c.take_throw() == -1 and not c.aiming(), "a tap on the throw stick does nothing")
	# top band is ignored
	_check.call(not o.handle_event(touch(3, Vector2(200, 60), true)), "a touch in the top band is ignored")
	_check.call(c.move() == 0, "the top band does not move")
	# two fingers at once
	o.handle_event(touch(4, Vector2(200, 400), true))
	o.handle_event(drag(4, Vector2(240, 400)))
	o.handle_event(touch(5, j, true))
	_check.call(c.move() == 1 and c.jump_held(), "move and jump work at the same time")
	o.handle_event(touch(5, j, false))
	_check.call(c.move() == 1 and not c.jump_held(), "lifting the jump finger leaves the move finger")
	o.handle_event(touch(4, Vector2(240, 400), false))
	# no aiming without beads
	c.set_can_aim(false)
	o.handle_event(touch(6, t, true))
	o.handle_event(drag(6, t + Vector2(50, 0)))
	_check.call(not c.aiming(), "the throw stick does not aim without beads")
	o.handle_event(touch(6, t + Vector2(50, 0), false))
	_check.call(c.take_throw() == -1, "no throw without beads")
	c.set_can_aim(true)
	# a disabled overlay ignores fingers; keys switch touch mode off unless forced
	o.set_enabled(false)
	_check.call(not o.handle_event(touch(7, j, true)) and not c.jump_held(), "a disabled overlay ignores touches")
	o.set_enabled(true)
	_check.call(o.touch_mode, "a touch turns touch mode on")
	o.handle_event(key(KEY_A))
	_check.call(not o.touch_mode, "a key press turns touch mode off")
	o.handle_event(touch(8, j, false))
	o.forced = true
	o.handle_event(key(KEY_A))
	_check.call(o.touch_mode, "a forced touch mode survives key presses")
	o.free()
	# safe area moves the controls
	var s2 := _overlay()
	var o2: MazeTouchOverlay = s2[1]
	o2.layout(Vector2(1600, 720), {"left": 60.0, "top": 0.0, "right": 60.0, "bottom": 24.0})
	_check.call(o2.jump_center() == Vector2(1600 - 130 - 60, 720 - 130 - 24), "the jump button respects the safe area")
	o2.free()


func _slow_motion() -> void:
	var r := 1.0
	var t := 0.0
	while r > MazeGame.AIM_TIME_SCALE and t < 1.0:
		r = MazeGame.next_rate(r, true, 1.0 / 240.0)
		t += 1.0 / 240.0
	_check.call(is_equal_approx(r, 0.25) and t <= 0.08 + 0.005, "the rate reaches 0.25 within 0.08 s of aiming")
	t = 0.0
	while r < 1.0 and t < 1.0:
		r = MazeGame.next_rate(r, false, 1.0 / 240.0)
		t += 1.0 / 240.0
	_check.call(is_equal_approx(r, 1.0) and t <= 0.08 + 0.005, "the rate returns to 1.0 within 0.08 s")
	# ticks over one real second of aiming, at 60 frames per second, in steady state
	var acc := 0.0
	var ticks := 0
	r = 0.25
	for i in 60:
		r = MazeGame.next_rate(r, true, 1.0 / 60.0)
		acc += r / 60.0
		while acc >= 1.0 / 60.0 - 1e-9:
			acc -= 1.0 / 60.0
			ticks += 1
	_check.call(absi(ticks - 15) <= 1, "about 15 ticks per real second while aiming (%d)" % ticks)
