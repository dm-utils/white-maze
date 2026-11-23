class_name MazeCameraRig
extends RefCounted
## Pure follow camera (design 19, ADR 0011): zoom, follow, aim framing, intro pan and overview.
## No nodes, input or time source; MazeGame feeds one frame at a time and copies the result into a Camera2D.

const TILE := 40.0
const VIEW_H_TILES := 9.0
const MIN_VIEW_W_TILES := 16.0
const FEET_Y := 0.70 # ground anchor height in the play rect, fraction from its top
const LOOK_X := 120.0
const LOOK_SPEED := 180.0
const LOOK_MIN_VX := 60.0
const LOOK_TURN_S := 0.2
const X_RATE := 7.0
const Y_RATE := 3.5
const GUARD_X := 120.0
const GUARD_TOP := 40.0
const GUARD_BOTTOM := 96.0
const GUARD_BOTTOM_FALL := 160.0
const GUARD_SPEED := 300.0
const FALL_MIN := 40.0
const AIM_MARGIN := 40.0
const AIM_RATE := 6.0
const AIM_GRACE_S := 0.15 # real time: a throw reaches the sim up to a few frames after the key release
const INTRO_HOLD_S := 0.8
const INTRO_PAN_SPEED := 900.0
const INTRO_PAN_MIN_S := 0.8
const INTRO_PAN_MAX_S := 2.0
const SKIP_BLEND_S := 0.3
const OVERVIEW_BLEND_S := 0.25
const OVERVIEW_PAD := 20.0
const MAX_DT := 0.1

enum Intro { NONE, ACTIVE, SKIPPED }

var debug_view := "" # "", "door" or "overview" (--camera)

var _level := Vector2(1280, 720)
var _canvas := Vector2(1280, 720)
var _band := 110.0
var _door := Vector2.ZERO
var _z := 2.0
var _pw := 711.0
var _ph := 339.0
var _g_top := GUARD_TOP
var _g_bot := GUARD_BOTTOM
var _g_fall := GUARD_BOTTOM_FALL

var _c := Vector2.ZERO # centre of the play rect, follow view
var _anchor_y := 0.0
var _look_x := 0.0
var _look_dir := 1
var _turn_t := 0.0
var _guard_b := GUARD_BOTTOM
var _aim_off := Vector2.ZERO
var _aim_want := Vector2.ZERO
var _aim_hold := false
var _hold_t := 0.0
var _was_aim := false

var _intro := Intro.NONE
var _intro_t := 0.0
var _pan_s := 1.0
var _door_view := Vector2.ZERO
var _frozen := Vector2.ZERO
var _skip_t := 0.0
var _overview := false
var _ov := 0.0

var _final_c := Vector2.ZERO
var _final_z := 2.0


static func target_zoom(canvas: Vector2) -> float:
	return minf(canvas.y / (VIEW_H_TILES * TILE), canvas.x / (MIN_VIEW_W_TILES * TILE))


static func fit_zoom(level_px: Vector2, canvas: Vector2, band: float) -> float:
	var fit := minf(
		(canvas.x - 2.0 * OVERVIEW_PAD) / level_px.x, (canvas.y - band - 2.0 * OVERVIEW_PAD) / level_px.y
	)
	return minf(target_zoom(canvas), fit)


static func _clamp_axis(v: float, size: float, half: float) -> float:
	if size >= 2.0 * half:
		return clampf(v, half, size - half)
	return size / 2.0


## sizes of this frame; cheap, call every frame
func setup(level_px: Vector2, canvas: Vector2, band: float, door: Vector2) -> void:
	_level = level_px
	_canvas = canvas
	_band = band
	_door = door
	_z = target_zoom(canvas)
	_pw = canvas.x / _z
	_ph = (canvas.y - band) / _z
	var s := 1.0
	var need := GUARD_TOP + GUARD_BOTTOM_FALL
	if need > 0.8 * _ph:
		s = 0.8 * _ph / need
	_g_top = GUARD_TOP * s
	_g_bot = GUARD_BOTTOM * s
	_g_fall = GUARD_BOTTOM_FALL * s


func _clamp_view(c: Vector2) -> Vector2:
	return Vector2(_clamp_axis(c.x, _level.x, _pw / 2.0), _clamp_axis(c.y, _level.y, _ph / 2.0))


func _base_target(f: Dictionary) -> Vector2:
	var p: Vector2 = f["player"]
	var feet_y := p.y + 16.0
	var ref_y := maxf(_anchor_y, feet_y)
	return Vector2(p.x + _look_x, ref_y - (FEET_Y - 0.5) * _ph)


func _aim_axis(base: float, p: float, h: float, half: float, g_lo: float, g_hi: float, size: float) -> float:
	var lo := maxf(h - (half - AIM_MARGIN), p - (half - g_lo))
	var hi := minf(h + (half - AIM_MARGIN), p + (half - g_hi))
	var want := clampf(base, lo, hi) if lo <= hi else (p + (half - g_hi) if h > p else p - (half - g_lo))
	return _clamp_axis(want, size, half)


func _want_aim(base_t: Vector2, f: Dictionary) -> Vector2:
	var p: Vector2 = f["player"]
	var h: Vector2 = f["aim_hit"]
	var wx := _aim_axis(base_t.x, p.x, h.x, _pw / 2.0, GUARD_X, GUARD_X, _level.x)
	var wy := _aim_axis(base_t.y, p.y, h.y, _ph / 2.0, _guard_b, _g_top, _level.y)
	return Vector2(wx, wy) - base_t


func _guards(f: Dictionary) -> void:
	var p: Vector2 = f["player"]
	_c.x = clampf(_c.x, p.x - (_pw / 2.0 - GUARD_X), p.x + (_pw / 2.0 - GUARD_X))
	_c.y = clampf(_c.y, p.y - (_ph / 2.0 - _guard_b), p.y + (_ph / 2.0 - _g_top))
	_c = _clamp_view(_c)


## follow state jumps to its target, no smoothing; intro and overview untouched
func snap(f: Dictionary) -> void:
	var p: Vector2 = f["player"]
	_anchor_y = p.y + 16.0
	_look_dir = int(f.get("facing", 1))
	if _look_dir == 0:
		_look_dir = 1
	_look_x = _look_dir * LOOK_X
	_turn_t = 0.0
	_guard_b = _g_bot
	_aim_hold = false
	_hold_t = 0.0
	_was_aim = bool(f["aim_frame"])
	var base_t := _base_target(f)
	_aim_want = _want_aim(base_t, f) if _was_aim else Vector2.ZERO
	_aim_off = _aim_want
	_c = base_t + _aim_off
	_guards(f)
	_present(0.0)


## one frame of real time
func update(dt: float, f: Dictionary) -> void:
	dt = minf(dt, MAX_DT)
	if not f["alive"]:
		_aim_want = Vector2.ZERO
		_aim_hold = false
		_was_aim = false
		_present(dt)
		return
	var p: Vector2 = f["player"]
	var vel: Vector2 = f["vel"]
	var feet_y := p.y + 16.0
	if f["grounded"]:
		_anchor_y = feet_y
	var falling: bool = (not f["grounded"] and vel.y > 0.0 and feet_y > _anchor_y + FALL_MIN) or f.get("slide", false)
	# look dir from velocity, not facing: wall launches look where the player flies
	var vdir := signf(vel.x) if absf(vel.x) >= LOOK_MIN_VX else 0.0
	if vdir != 0.0 and int(vdir) != _look_dir:
		_turn_t += dt
		if _turn_t >= LOOK_TURN_S:
			_look_dir = int(vdir)
			_turn_t = 0.0
	else:
		_turn_t = 0.0
	_look_x = move_toward(_look_x, _look_dir * LOOK_X, LOOK_SPEED * dt)
	_guard_b = move_toward(_guard_b, _g_fall if falling else _g_bot, GUARD_SPEED * dt)
	var base_t := _base_target(f)
	_update_aim_want(dt, base_t, f)
	_aim_off += (_aim_want - _aim_off) * (1.0 - exp(-AIM_RATE * dt))
	var t := base_t + _aim_off
	_c.x += (t.x - _c.x) * (1.0 - exp(-X_RATE * dt))
	_c.y += (t.y - _c.y) * (1.0 - exp(-Y_RATE * dt))
	_guards(f)
	_present(dt)


func _update_aim_want(dt: float, base_t: Vector2, f: Dictionary) -> void:
	if f["aim_frame"]:
		_aim_hold = false
		_was_aim = true
		_aim_want = _want_aim(base_t, f)
		return
	if _was_aim:
		_aim_hold = true
		_hold_t = 0.0
		_was_aim = false
	if _aim_hold:
		_hold_t += dt
		if not f["flights"] and _hold_t > AIM_GRACE_S:
			_aim_hold = false
			_aim_want = Vector2.ZERO
	else:
		_aim_want = Vector2.ZERO


func start_intro() -> void:
	_door_view = _clamp_view(_door)
	_pan_s = clampf(_door_view.distance_to(_c) / INTRO_PAN_SPEED, INTRO_PAN_MIN_S, INTRO_PAN_MAX_S)
	_intro = Intro.ACTIVE
	_intro_t = 0.0
	_present(0.0)


func skip_intro() -> void:
	if _intro != Intro.ACTIVE:
		return
	_frozen = _intro_centre()
	_intro = Intro.SKIPPED
	_skip_t = 0.0


func look_dir() -> int:
	return _look_dir


func intro_active() -> bool:
	return _intro == Intro.ACTIVE


func set_overview(on: bool) -> void:
	_overview = on


func _intro_centre() -> Vector2:
	if _intro_t < INTRO_HOLD_S:
		return _door_view
	var u := clampf((_intro_t - INTRO_HOLD_S) / _pan_s, 0.0, 1.0)
	return _door_view.lerp(_c, smoothstep(0.0, 1.0, u))


func _present(dt: float) -> void:
	var base := _c
	match _intro:
		Intro.ACTIVE:
			_intro_t += dt
			if _intro_t >= INTRO_HOLD_S + _pan_s:
				_intro = Intro.NONE
			else:
				base = _intro_centre()
		Intro.SKIPPED:
			_skip_t += dt
			if _skip_t >= SKIP_BLEND_S:
				_intro = Intro.NONE
			else:
				base = _c.lerp(_frozen, 1.0 - smoothstep(0.0, 1.0, _skip_t / SKIP_BLEND_S))
	if debug_view == "door":
		_final_c = _clamp_view(_door)
		_final_z = _z
		return
	if debug_view == "overview":
		_ov = 1.0
	else:
		_ov = move_toward(_ov, 1.0 if _overview else 0.0, dt / OVERVIEW_BLEND_S)
	var k := smoothstep(0.0, 1.0, _ov)
	var fz := fit_zoom(_level, _canvas, _band)
	_final_z = exp(lerpf(log(_z), log(fz), k))
	_final_c = base.lerp(_level / 2.0, k)


## world px: the Camera2D position (centre of the whole viewport)
func view_centre() -> Vector2:
	return _final_c - Vector2(0.0, _band / (2.0 * _final_z))


func view_zoom() -> float:
	return _final_z


## world px: the part of the world visible below the HUD band
func play_rect() -> Rect2:
	var size := Vector2(_canvas.x, _canvas.y - _band) / _final_z
	return Rect2(_final_c - size / 2.0, size)


func overview_k() -> float:
	return smoothstep(0.0, 1.0, _ov)
