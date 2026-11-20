class_name MazeGame
extends Node
## Game screen: one level, one attempt at a time (design 8.3). Owns the simulation, the controls and the profile
## bookkeeping; the world view, HUD, touch overlay and overlays only show state.

signal levels_requested
signal next_requested

const TICK_S := 1.0 / 60.0
const AIM_TIME_SCALE := 0.25
const AIM_RAMP_S := 0.08
const MAX_STEPS := 6
const MAX_FRAME_S := 0.1
const LOOK_AHEAD := 60.0
const LOOK_RATE := 6.0
const CAMERA_SPEED := 8.0
const SLOW_DIM := 0.85
const HUD_BAND := 110.0

var level: MazeLevel
var number := 1
var total := 1
var store: MazeProfileStore
var options := {} # parsed debug arguments (MazeMain.parse_args)

var sim: MazeSim
var controls := MazeControls.new()
var world: MazeWorldView
var camera: Camera2D
var hud: MazeHud
var touch: MazeTouchOverlay
var overlays: MazeOverlays

var rate := 1.0
var paused := false
var frozen := false # debug: no ticks
var last_result := {}

var _acc := 0.0
var _inputs: Array[MazeInput] = []
var _flushed_ticks := 0
var _flushed_deaths := 0
var _done := false # finished: nothing more to flush
var _look := 0.0


func setup(lv: MazeLevel, num: int, count: int, profile: MazeProfileStore, opts: Dictionary = {}) -> void:
	level = lv
	number = num
	total = count
	store = profile
	options = opts


## rate of game time: a quarter while aiming, ramped over AIM_RAMP_S of real time
static func next_rate(current: float, aiming: bool, delta: float) -> float:
	var target := AIM_TIME_SCALE if aiming else 1.0
	return move_toward(current, target, delta * (1.0 - AIM_TIME_SCALE) / AIM_RAMP_S)


func _ready() -> void:
	world = MazeWorldView.new()
	add_child(world)
	camera = Camera2D.new()
	camera.position_smoothing_speed = CAMERA_SPEED
	camera.position_smoothing_enabled = not options.get("shot", false)
	world.add_child(camera)
	camera.make_current()

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	hud = MazeHud.new()
	hud.safe_override = options.get("safe", "")
	hud.number = number
	hud_layer.add_child(hud)
	hud.undo_pressed.connect(func() -> void: _on_undo_button())
	hud.restart_pressed.connect(restart)
	hud.pause_pressed.connect(pause)

	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 2
	add_child(touch_layer)
	touch = MazeTouchOverlay.new()
	touch.controls = controls
	touch.forced = options.get("touch", false)
	touch.safe_override = options.get("safe", "")
	touch_layer.add_child(touch)

	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 3
	add_child(overlay_layer)
	overlays = MazeOverlays.new()
	overlay_layer.add_child(overlays)
	overlays.resume_pressed.connect(resume)
	overlays.restart_pressed.connect(restart)
	overlays.levels_pressed.connect(leave)
	overlays.next_pressed.connect(_next)

	_start_attempt(false)
	_debug_setup()
	_update_camera(0.0, true)


func _debug_setup() -> void:
	var script := str(options.get("keys", ""))
	if options.get("solve", false):
		script = _solution_script()
	if script != "":
		var parsed := MazeRunScript.parse(script)
		if parsed["ok"]:
			for inp: MazeInput in parsed["inputs"]:
				_inputs.append(inp)
				sim.step(inp)
				world.notify_events(sim.events)
				hud.notify_events(sim.events)
				if sim.finished():
					break
			_acc = 0.0
			world.alpha = 1.0
			frozen = true
			if sim.finished():
				_on_finish()
		else:
			push_warning("--keys: %s" % parsed["error"])
	if options.get("shot", false):
		frozen = true
	var aim := int(options.get("aim", -1))
	if aim >= 0:
		world.aim_index = aim
		frozen = true
	if options.get("pause", false):
		pause()


func _solution_script() -> String:
	var data := WhitePuzzleStore.load_json("res://tests/solutions.json")
	return str(data.get(level.id, ""))


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _start_attempt(restart_: bool) -> void:
	if restart_:
		_flush_play()
	sim = MazeSim.new(level)
	_inputs.clear()
	_flushed_ticks = 0
	_flushed_deaths = 0
	_done = false
	_acc = 0.0
	frozen = false
	last_result = {}
	controls.reset_attempt()
	world.sim = sim
	world.alpha = 1.0
	world.reset()
	world.aim_index = -1
	hud.sim = sim
	hud.reset()
	overlays.hide_result()
	hud.hide_hint(false)
	touch.set_enabled(true)
	if store != null:
		MazeProfile.record_start(store.data, level.id, _now())
		store.save(_now())
	if paused:
		_close_pause()
	_update_camera(0.0, true)


func restart() -> void:
	_start_attempt(true)


func pause() -> void:
	if paused or sim.finished():
		return
	paused = true
	rate = 0.0
	controls.release_all()
	touch.set_enabled(false)
	overlays.show_pause(touch.touch_mode)
	_flush_play()
	_save()


func resume() -> void:
	if not paused:
		return
	_close_pause()


func _close_pause() -> void:
	paused = false
	overlays.hide_pause()
	touch.set_enabled(true)


func leave() -> void:
	_flush_play()
	_save()
	levels_requested.emit()


func _next() -> void:
	next_requested.emit()


func _on_undo_button() -> void:
	if not paused and not frozen:
		controls.queue_undo()


func _flush_play() -> void:
	if store == null or _done or sim == null:
		return
	var t := sim.time_ticks() - _flushed_ticks
	var d := sim.deaths - _flushed_deaths
	if t > 0 or d > 0:
		MazeProfile.add_play(store.data, level.id, t, d, _now())
		_flushed_ticks = sim.time_ticks()
		_flushed_deaths = sim.deaths


func _save() -> void:
	if store != null:
		store.save(_now())


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if sim != null:
				pause()
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED:
			if sim != null:
				_flush_play()
				_save()


func _unhandled_input(event: InputEvent) -> void:
	controls.handle_event(event)


func _input(event: InputEvent) -> void:
	if overlays != null and overlays.result_visible() and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
			get_viewport().set_input_as_handled()
			if number < total:
				_next()
			else:
				leave()


func _process(delta: float) -> void:
	advance(delta)


## one frame; tests call it with fixed deltas
func advance(delta: float) -> void:
	_check_rotate()
	controls.update(delta)
	if overlays.rotate_visible() and not overlays.result_visible():
		# rotate hint keeps the game paused; drop pause/restart keys until landscape
		controls.take_pause()
		controls.take_restart()
	if controls.take_pause():
		if overlays.result_visible():
			leave()
			return
		if paused:
			resume()
		else:
			pause()
	if controls.take_restart():
		restart()
	var active := not paused and not frozen and not sim.finished()
	controls.set_facing(sim.facing)
	controls.set_player_screen_pos(world.get_canvas_transform() * world.player_centre())
	controls.set_can_aim(active and sim.alive() and sim.beads_left > 0)
	if not active:
		controls.clear_latches()
	if paused:
		rate = 0.0
	elif active:
		rate = next_rate(rate, controls.aiming(), delta)
	else:
		rate = 1.0
	if active:
		_acc += minf(delta, MAX_FRAME_S) * rate
		var n := 0
		while _acc >= TICK_S and n < MAX_STEPS:
			_acc -= TICK_S
			n += 1
			_tick()
			if sim.finished():
				break
		_acc = minf(_acc, TICK_S * 0.999)
	if options.get("aim", -1) < 0:
		world.aim_index = controls.aim_index() if controls.aiming() else -1
	world.alpha = clampf(_acc / TICK_S, 0.0, 1.0) if active else 1.0
	world.modulate = Color(SLOW_DIM, SLOW_DIM, SLOW_DIM) if (active and rate < 1.0) else Color.WHITE
	hud.set_hint(MazeStrings.hint(level, touch.touch_mode))
	hud.hide_hint(overlays.any_open())
	hud.hint_at_top = touch.touch_mode
	_update_camera(delta, false)
	world.queue_redraw()


func _tick() -> void:
	var inp := MazeInput.new()
	inp.move = controls.move()
	inp.jump_held = controls.jump_held()
	inp.jump_pressed = controls.take_jump_pressed()
	inp.throw_dir = controls.take_throw()
	inp.undo = controls.take_undo()
	_inputs.append(inp)
	sim.step(inp)
	world.notify_events(sim.events)
	hud.notify_events(sim.events)
	for e in sim.events:
		match e["type"]:
			"death":
				controls.cancel_aim()
			"finish":
				_on_finish()


func _on_finish() -> void:
	controls.cancel_aim()
	touch.set_enabled(false)
	world.aim_index = -1
	var ticks := sim.time_ticks()
	var script := MazeRunScript.encode(_inputs)
	var result := {
		"ticks": ticks, "rings": sim.rings_used, "par": level.par, "new_best": false, "best_ticks": ticks,
		"has_next": number < total, "script": script,
	}
	if store != null:
		_flush_play()
		var now := _now()
		var res := MazeProfile.record_finish(store.data, level.id, ticks, sim.rings_used, script, now)
		result["new_best"] = res["new_best"]
		result["best_ticks"] = res["best_ticks"]
		store.save(now)
	_done = true
	last_result = result
	if options.get("print_run", false):
		print("run %s %d %d %s" % [level.id, ticks, sim.rings_used, script])
	overlays.show_result(result)


func _check_rotate() -> void:
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	if portrait and not overlays.rotate_visible():
		overlays.show_rotate(true)
		if not paused and not sim.finished():
			pause()
	elif not portrait and overlays.rotate_visible():
		overlays.show_rotate(false)


func _update_camera(delta: float, snap: bool) -> void:
	var vs := get_viewport().get_visible_rect().size
	var ins := WhiteSafeArea.insets(vs, options.get("safe", ""))
	var lw := level.width * 40.0
	var lh := level.height * 40.0
	var band: float = HUD_BAND + ins["top"]
	var left := 0.0
	var right := lw
	if lw <= vs.x:
		left = -(vs.x - lw) / 2.0
		right = left + vs.x
	var top := 0.0
	var bottom := lh
	if lh <= vs.y - band:
		top = -(band + (vs.y - band - lh) / 2.0)
		bottom = top + vs.y
	elif lh <= vs.y:
		top = -(vs.y - lh) / 2.0
		bottom = top + vs.y
	camera.limit_left = floori(left)
	camera.limit_right = ceili(right)
	camera.limit_top = floori(top)
	camera.limit_bottom = ceili(bottom)
	var f := float(sim.facing)
	_look = f * LOOK_AHEAD if snap else lerpf(_look, f * LOOK_AHEAD, 1.0 - exp(-delta * LOOK_RATE))
	camera.position = world.player_centre() + Vector2(_look, 0.0)
	if snap or options.get("shot", false):
		camera.reset_smoothing()
		camera.force_update_scroll()
