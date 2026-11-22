class_name MazeTouchOverlay
extends Control
## Touch controls (design 4.6): floating move stick on the left, throw stick and jump button on the right.
## Each finger keeps the role it got at touch-down until it is lifted.

const TOP_BAND := 110.0
const JUMP_OFFSET := Vector2(130, 130)
const JUMP_R := 80.0
const JUMP_HIT := 100.0
const THROW_OFFSET := Vector2(340, 120)
const THROW_R := 72.0
const THROW_HIT := 95.0
const THROW_DEAD := 26.0
const MAP_R := 34.0
const MAP_HIT := 48.0
const MAP_INSET := 80.0
const MOVE_ZONE := 0.45
const MOVE_R := 96.0
const MOVE_KNOB_MAX := 70.0
const MOVE_DEAD := 20.0
const MOVE_FOLLOW := 110.0
const MOVE_HOME := Vector2(200, 170)
const KNOB_R := 36.0
const FAINT := Color(1, 1, 1, 0.16)
const DISC_ALPHA := 0.35 # BG disc under every control, so it shows over light blocks
const FAINT_LINE := Color(1, 1, 1, 0.35)
const FONT := 20

enum Role { JUMP, THROW, MAP, MOVE }

var controls: MazeControls
var touch_mode := false # visible and active
var forced := false # --touch: key presses do not turn it off
var enabled := true # false while an overlay is open
var safe_override := ""

var _size := Vector2(1280, 720)
var _ins := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
var _fingers := {} # index -> {"role": Role, "pos": Vector2, "base": Vector2}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	touch_mode = forced or DisplayServer.is_touchscreen_available()
	_refresh_layout()


func layout(size_: Vector2, ins: Dictionary) -> void:
	_size = size_
	_ins = ins


func _refresh_layout() -> void:
	var vs := get_viewport_rect().size if is_inside_tree() else _size
	layout(vs, WhiteSafeArea.insets(vs, safe_override))


func _process(_delta: float) -> void:
	if touch_mode:
		_refresh_layout()
		queue_redraw()


func jump_center() -> Vector2:
	return Vector2(_size.x - JUMP_OFFSET.x - _ins["right"], _size.y - JUMP_OFFSET.y - _ins["bottom"])


func throw_center() -> Vector2:
	return Vector2(_size.x - THROW_OFFSET.x - _ins["right"], _size.y - THROW_OFFSET.y - _ins["bottom"])


func map_center() -> Vector2:
	return Vector2(_size.x - MAP_INSET - _ins["right"], TOP_BAND + _ins["top"] + 80.0)


func move_home() -> Vector2:
	return Vector2(MOVE_HOME.x + _ins["left"], _size.y - MOVE_HOME.y - _ins["bottom"])


func top_band() -> float:
	return TOP_BAND + _ins["top"]


## drops every finger (overlay opened, pause)
func reset() -> void:
	_fingers.clear()
	if controls != null:
		controls.touch_move(0)
		controls.touch_jump(false)
		controls.touch_map(false)
		controls.touch_aim(false, -1)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		reset()


func _input(event: InputEvent) -> void:
	if handle_event(event):
		get_viewport().set_input_as_handled()


## true when the event was used
func handle_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		if event.pressed and not forced:
			touch_mode = false
		return false
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return false
	touch_mode = true
	if not enabled or controls == null:
		return false
	if event is InputEventScreenTouch:
		if event.pressed:
			controls.note_touch()
		return _touch(event.index, event.position, event.pressed)
	return _drag(event.index, event.position)


func _touch(idx: int, pos: Vector2, down: bool) -> bool:
	if down:
		if pos.y < top_band():
			return false
		var role := -1
		var base := pos
		if pos.distance_to(jump_center()) <= JUMP_HIT:
			role = Role.JUMP
			controls.touch_jump(true)
		elif pos.distance_to(throw_center()) <= THROW_HIT:
			role = Role.THROW
		elif pos.distance_to(map_center()) <= MAP_HIT:
			role = Role.MAP
			controls.touch_map(true)
		elif pos.x < MOVE_ZONE * _size.x:
			role = Role.MOVE
		if role < 0:
			return false
		_fingers[idx] = {"role": role, "pos": pos, "base": base}
		_apply(idx)
		return true
	if not _fingers.has(idx):
		return false
	var f: Dictionary = _fingers[idx]
	match f["role"]:
		Role.JUMP:
			controls.touch_jump(false)
		Role.THROW:
			var v: Vector2 = f["pos"] - throw_center()
			if v.length() > THROW_DEAD:
				controls.touch_throw(MazeAim.index_from_vector(v))
			else:
				controls.touch_aim(false, -1)
		Role.MAP:
			controls.touch_map(false)
		Role.MOVE:
			controls.touch_move(0)
	_fingers.erase(idx)
	return true


func _drag(idx: int, pos: Vector2) -> bool:
	if not _fingers.has(idx):
		return false
	_fingers[idx]["pos"] = pos
	_apply(idx)
	return true


func _apply(idx: int) -> void:
	var f: Dictionary = _fingers[idx]
	match f["role"]:
		Role.THROW:
			var v: Vector2 = f["pos"] - throw_center()
			if v.length() > THROW_DEAD:
				controls.touch_aim(true, MazeAim.index_from_vector(v))
			else:
				controls.touch_aim(false, -1)
		Role.MOVE:
			var base: Vector2 = f["base"]
			var d: Vector2 = f["pos"] - base
			if d.length() > MOVE_FOLLOW:
				base = f["pos"] - d.normalized() * MOVE_FOLLOW
				f["base"] = base
				d = f["pos"] - base
			controls.touch_move(1 if d.x > MOVE_DEAD else (-1 if d.x < -MOVE_DEAD else 0))


func _finger_of(role: int) -> Variant:
	for k in _fingers:
		if _fingers[k]["role"] == role:
			return _fingers[k]
	return null


func _draw() -> void:
	if not touch_mode or controls == null:
		return
	var font := ThemeDB.fallback_font
	# move stick
	var mf: Variant = _finger_of(Role.MOVE)
	var mbase := move_home()
	var mknob := mbase
	var malpha := 0.5
	if mf != null:
		mbase = mf["base"]
		mknob = mbase + (mf["pos"] - mbase).limit_length(MOVE_KNOB_MAX)
		malpha = 1.0
	draw_circle(mbase, MOVE_R, Color(WhiteTheme.BG, DISC_ALPHA * malpha))
	draw_circle(mbase, MOVE_R, Color(FAINT, FAINT.a * malpha))
	draw_arc(mbase, MOVE_R, 0, TAU, 48, Color(FAINT_LINE, FAINT_LINE.a * malpha), 2.0)
	draw_circle(mknob, KNOB_R, Color(1, 1, 1, 0.4 * malpha))
	_label(font, WhiteText.t("ctl_move"), mbase + Vector2(0, MOVE_R - 22), malpha * 0.6)
	# throw stick
	var tc := throw_center()
	var talpha := 1.0 if controls.can_aim() else 0.4
	var tf: Variant = _finger_of(Role.THROW)
	var tknob := tc
	if tf != null:
		tknob = tc + (tf["pos"] - tc).limit_length(THROW_R)
	draw_circle(tc, THROW_R, Color(WhiteTheme.BG, DISC_ALPHA * talpha))
	draw_circle(tc, THROW_R, Color(FAINT, FAINT.a * talpha))
	draw_arc(tc, THROW_R, 0, TAU, 48, Color(FAINT_LINE, FAINT_LINE.a * talpha), 2.0)
	draw_circle(tknob, KNOB_R, Color(1, 1, 1, 0.4 * talpha))
	_label(font, WhiteText.t("ctl_throw"), tc + Vector2(0, THROW_R + 26), talpha)
	# jump button
	var jc := jump_center()
	var down := _finger_of(Role.JUMP) != null
	draw_circle(jc, JUMP_R, Color(WhiteTheme.BG, DISC_ALPHA))
	draw_circle(jc, JUMP_R, Color(1, 1, 1, 0.28 if down else 0.16))
	draw_arc(jc, JUMP_R, 0, TAU, 48, FAINT_LINE, 2.0)
	_label(font, WhiteText.t("ctl_jump"), jc + Vector2(0, JUMP_R + 26), 1.0)
	# map button (overview, held)
	var mc := map_center()
	var mdown := _finger_of(Role.MAP) != null
	draw_circle(mc, MAP_R, Color(WhiteTheme.BG, DISC_ALPHA))
	draw_circle(mc, MAP_R, Color(1, 1, 1, 0.28 if mdown else 0.16))
	draw_arc(mc, MAP_R, 0, TAU, 48, FAINT_LINE, 2.0)
	_label(font, WhiteText.t("ctl_map"), mc + Vector2(0, MAP_R + 22), 1.0)


func _label(font: Font, text: String, pos: Vector2, alpha: float) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	var c := Color(WhiteTheme.DIM, alpha)
	draw_string(font, pos - Vector2(w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, c)
