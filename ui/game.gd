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
const SLOW_DIM := 0.85
const HUD_BAND := 110.0
const SPEED_MIN_PCT := 50
const SPEED_MAX_PCT := 150
const SPEED_PCT := [80, 82, 84, 86, 88, 90, 92, 94, 96] # per series position; later levels use the last value

var level: MazeLevel
var number := 1
var total := 1
var store: MazeProfileStore
var options := {} # parsed debug arguments (MazeMain.parse_args)

var sim: MazeSim
var controls := MazeControls.new()
var world: MazeWorldView
var camera: Camera2D
var rig := MazeCameraRig.new()
var hud: MazeHud
var touch: MazeTouchOverlay
var overlays: MazeOverlays

var rate := 1.0
var speed := 1.0 # level speed, ticks per real second as a fraction of 60
var paused := false
var frozen := false # debug: no ticks
var last_result := {}
var _frames_seen := 0

var _acc := 0.0
var _inputs: Array[MazeInput] = []
var _flushed_ticks := 0
var _flushed_deaths := 0
var _done := false # finished: nothing more to flush
var _snap_next := false # respawn: the camera cuts to the spawn
var _overview := false
var _links: Array = [] # chain of this attempt (design 22.4)
var _preset_seen := {}


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


## level speed for a series position (design 20.6)
static func level_speed(num: int) -> float:
	return SPEED_PCT[clampi(num, 1, SPEED_PCT.size()) - 1] / 100.0


func _ready() -> void:
	var pct := int(options.get("speed", 0))
	speed = pct / 100.0 if pct > 0 else level_speed(number)
	world = MazeWorldView.new()
	add_child(world)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
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
	overlays.safe_override = options.get("safe", "")
	overlay_layer.add_child(overlays)
	overlays.resume_pressed.connect(resume)
	overlays.restart_pressed.connect(restart)
	overlays.levels_pressed.connect(leave)
	overlays.next_pressed.connect(_next)

	rig.debug_view = str(options.get("camera", ""))
	_start_attempt(false)
	world.world_id = MazeWorlds.for_number(number)
	var forced := MazeWorlds.from_name(str(options.get("world", "")))
	if forced >= 0:
		world.world_id = forced
	world.build()
	hud.show_fps = options.get("fps", false)
	_debug_setup()
	_update_camera(0.0, true)
	if _intro_wanted():
		rig.start_intro()
		_update_camera(0.0, false)


## the intro shows the door when a level opens; never in debug shots, never when the door is in view anyway
func _intro_wanted() -> bool:
	if options.get("shot", false) or options.get("solve", false) or options.get("pause", false):
		return false
	if str(options.get("keys", "")) != "" or int(options.get("aim", -1)) >= 0 or str(options.get("camera", "")) != "":
		return false
	return not rig.play_rect().has_point(_door_centre())


func _door_centre() -> Vector2:
	return (Vector2(level.finish) + Vector2(0.5, 0.5)) * MazeCameraRig.TILE


func _debug_setup() -> void:
	var script := str(options.get("keys", ""))
	if options.get("solve", false):
		script = _solution_script()
	if script != "":
		var parsed := MazeRunScript.parse(script)
		if parsed["ok"]:
			for inp: MazeInput in parsed["inputs"]:
				_inputs.append(inp)
				_step_sim(inp)
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
	if str(options.get("camera", "")) != "":
		frozen = true
	world.blend.enabled = not frozen
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
	_links.clear()
	_preset_seen.clear()
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
	if overlays != null and overlays.result_visible() and not overlays.chain_animating() and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
			get_viewport().set_input_as_handled()
			if number < total:
				_next()
			else:
				leave()


func _process(delta: float) -> void:
	_note_first_frame()
	advance(delta)


## the second frame starts after the first one drew, baking included
func _note_first_frame() -> void:
	if MazeStaticBake.first_frame_usec >= 0:
		return
	_frames_seen += 1
	if _frames_seen >= 2:
		MazeStaticBake.first_frame_usec = Time.get_ticks_usec() - MazeStaticBake.built_at_usec
		if options.get("fps", false):
			var ms := [MazeStaticBake.build_usec / 1000, MazeStaticBake.first_frame_usec / 1000]
			print("bake %d ms, first frame %d ms" % ms)


## one frame; tests call it with fixed deltas
func advance(delta: float) -> void:
	_check_rotate()
	controls.update(delta)
	if controls.take_any_input() and rig.intro_active():
		rig.skip_intro()
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
	var held := controls.overview_held() and not paused and not frozen and not sim.finished()
	held = held and not overlays.any_open()
	if held and not _overview:
		controls.cancel_aim()
	_overview = held
	var active := not paused and not frozen and not sim.finished() and not _overview
	controls.set_facing(sim.facing)
	controls.set_can_aim(active and sim.alive() and sim.beads_left > 0)
	if not active:
		controls.clear_latches()
	if paused or _overview:
		rate = 0.0
	elif active:
		rate = next_rate(rate, controls.aiming(), delta)
	else:
		rate = 1.0
	if active:
		_acc += minf(delta, MAX_FRAME_S) * rate * speed
		var n := 0
		while _acc >= TICK_S and n < MAX_STEPS:
			_acc -= TICK_S
			n += 1
			_tick()
			if sim.finished():
				break
		_acc = minf(_acc, TICK_S * 0.999)
	# paused and overview keep the interpolation, so nothing jumps forward by a tick
	var tweened := not frozen and not sim.finished()
	world.alpha = clampf(_acc / TICK_S, 0.0, 1.0) if tweened else 1.0
	world.blend.enabled = not frozen
	world.modulate = Color(SLOW_DIM, SLOW_DIM, SLOW_DIM) if (active and rate < 1.0) else Color.WHITE
	rig.set_overview(_overview)
	_update_camera(delta, false)
	controls.set_player_screen_pos(world.get_canvas_transform() * world.player_centre())
	if options.get("aim", -1) < 0:
		world.aim_index = controls.aim_index() if controls.aiming() else -1
	hud.set_hint(MazeStrings.hint(level, touch.touch_mode))
	hud.hide_hint(overlays.any_open() or rig.overview_k() > 0.0) # overview: the hint would cover the bottom row
	hud.hint_at_top = touch.touch_mode
	world.queue_redraw()


func _tick() -> void:
	var inp := MazeInput.new()
	inp.move = controls.move()
	inp.jump_held = controls.jump_held()
	inp.jump_pressed = controls.take_jump_pressed()
	inp.throw_dir = controls.take_throw()
	inp.undo = controls.take_undo()
	_inputs.append(inp)
	_step_sim(inp)
	for e in sim.events:
		match e["type"]:
			"death":
				controls.cancel_aim()
			"respawn":
				_snap_next = true
			"finish":
				_on_finish()


## one simulation step with the chain and the view notifications
func _step_sim(inp: MazeInput) -> void:
	sim.step(inp)
	MazeChain.note(sim.events, level, _preset_seen, _links)
	world.notify_events(sim.events)
	world.after_tick()
	hud.notify_events(sim.events)


func _on_finish() -> void:
	controls.cancel_aim()
	touch.set_enabled(false)
	world.aim_index = -1
	var ticks := sim.time_ticks()
	var script := MazeRunScript.encode(_inputs)
	var still: bool = options.get("reduced_motion", false) \
			or (options.get("shot", false) and float(options.get("chain_t", -1.0)) < 0.0)
	var storable := _links.size() <= MazeChain.MAX_LINKS
	var links_text := MazeChain.encode(_links) if storable else ""
	var result := {
		"ticks": ticks, "rings": sim.rings_used, "par": level.par, "new_best": false, "best_ticks": ticks,
		"has_next": number < total, "script": script, "links": _links.duplicate(), "links_text": links_text,
		"code": MazeChain.code(level.id, sim.rings_used, level.par, ticks, links_text) if storable else "",
		"level": level, "world": world.world_id, "number": number, "name": str(level.names.get(WhiteText.lang, "")),
		"reduced_motion": still, "chain_t": options.get("chain_t", -1.0),
		"chain_export": options.get("chain_export", false),
	}
	if store != null:
		_flush_play()
		var now := _now()
		var res := MazeProfile.record_finish(
			store.data, level.id, ticks, sim.rings_used, script, now, links_text if storable else null
		)
		result["new_best"] = res["new_best"]
		result["best_ticks"] = res["best_ticks"]
		store.save(now)
	_done = true
	last_result = result
	if options.get("print_run", false):
		for line in print_lines(result):
			print(line)
	overlays.show_result(result)


## lines of --print-run
func print_lines(result: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"run %s %d %d %s" % [level.id, result["ticks"], result["rings"], result["script"]],
		"chain %s" % result["code"],
	])


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
	var band: float = HUD_BAND + ins["top"]
	rig.setup(Vector2(level.width, level.height) * MazeCameraRig.TILE, vs, band, _door_centre())
	var aim := _aim_for_camera()
	var f := {
		"player": world.player_centre(),
		"vel": Vector2(sim.vx, sim.vy) * 60.0 / 1000.0,
		"grounded": sim.grounded, "alive": sim.alive(), "facing": sim.facing,
		"aim_frame": aim >= 0, "aim_hit": Vector2.ZERO, "flights": not sim.flights.is_empty(),
	}
	if aim >= 0:
		f["aim_hit"] = Vector2(sim.cast(aim)["hit"]) / 1000.0
	if snap or _snap_next:
		_snap_next = false
		rig.snap(f)
	else:
		rig.update(0.0 if paused else delta, f)
	var z := rig.view_zoom()
	camera.zoom = Vector2(z, z)
	camera.position = rig.view_centre()
	camera.force_update_scroll()
	world.view_rect = rig.play_rect()
	world.view_zoom = z
	world.overview_k = rig.overview_k()


## aim index to frame, or -1: keyboard and stick aims and --aim; a mouse aim never moves the camera
func _aim_for_camera() -> int:
	var dbg := int(options.get("aim", -1))
	if dbg >= 0:
		return dbg
	if not controls.aiming():
		return -1
	var src := controls.aim_source()
	if src == MazeControls.AimSource.KEYS or src == MazeControls.AimSource.TOUCH:
		return controls.aim_index()
	return -1
