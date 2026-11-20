class_name MazeControls
extends RefCounted
## Keyboard, mouse and touch merged into one intent, sampled once per simulation tick (design 4.1).
## Jump press, throw, undo, restart and pause are latched until taken, so they survive frames without a tick.

const KEY_AIM_START := 3 # elevation steps of 15 degrees at the start of an attempt
const KEY_AIM_MAX := 6
const REPEAT_FIRST_S := 0.25
const REPEAT_NEXT_S := 0.1

var _facing := 1
var _player_pos := Vector2.ZERO
var _can_aim := true

var _keys_left := {}
var _keys_right := {}
var _keys_jump := {}
var _touch_move := 0
var _touch_jump_held := false
var _jump_press := false

var _kb_aim := false
var _elevation := KEY_AIM_START
var _turn_keys := {} # keycode -> +1 / -1 for aim keys held now
var _turn_timer := 0.0
var _mouse_aim := false
var _mouse_pos := Vector2.ZERO
var _mouse_idx := -1
var _touch_aim := false
var _touch_idx := -1

var _throw := -1
var _undo := false
var _restart := false
var _pause := false


func move() -> int:
	var k := (1 if not _keys_right.is_empty() else 0) - (1 if not _keys_left.is_empty() else 0)
	return k if k != 0 else _touch_move


func jump_held() -> bool:
	return not _keys_jump.is_empty() or _touch_jump_held


func take_jump_pressed() -> bool:
	var v := _jump_press
	_jump_press = false
	return v


func aiming() -> bool:
	return _can_aim and (_kb_aim or _mouse_aim or _touch_aim)


## index 0..143 of the current aim; valid while aiming
func aim_index() -> int:
	if _touch_aim:
		return _touch_idx
	if _mouse_aim:
		var i := MazeAim.index_from_vector(_mouse_pos - _player_pos)
		if i >= 0:
			_mouse_idx = i
		return _mouse_idx if _mouse_idx >= 0 else 0
	return MazeAim.keyboard_index(_facing, _elevation)


func can_aim() -> bool:
	return _can_aim


func elevation() -> int:
	return _elevation


## latched throw index, or -1
func take_throw() -> int:
	var v := _throw
	_throw = -1
	return v


func take_undo() -> bool:
	var v := _undo
	_undo = false
	return v


func take_restart() -> bool:
	var v := _restart
	_restart = false
	return v


func take_pause() -> bool:
	var v := _pause
	_pause = false
	return v


func cancel_aim() -> void:
	_kb_aim = false
	_mouse_aim = false
	_touch_aim = false
	_turn_keys.clear()


func set_facing(f: int) -> void:
	_facing = f


func set_player_screen_pos(p: Vector2) -> void:
	_player_pos = p


func set_can_aim(ok: bool) -> void:
	_can_aim = ok
	if not ok:
		cancel_aim()


## fresh attempt: aim elevation back to its start, latches dropped
func reset_attempt() -> void:
	_elevation = KEY_AIM_START
	clear_latches()
	cancel_aim()


func clear_latches() -> void:
	_jump_press = false
	_throw = -1
	_undo = false
	_restart = false
	_pause = false


## keys and fingers released, for pause and focus loss
func release_all() -> void:
	_keys_left.clear()
	_keys_right.clear()
	_keys_jump.clear()
	_touch_move = 0
	_touch_jump_held = false
	cancel_aim()


## real-time step for the repeat of the aim keys
func update(delta: float) -> void:
	if _turn_keys.is_empty() or not aiming():
		return
	_turn_timer -= delta
	while _turn_timer <= 0.0:
		_turn_timer += REPEAT_NEXT_S
		for k in _turn_keys:
			_turn(_turn_keys[k])


## keyboard and mouse; true when the event was used
func handle_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key(event)
	if event is InputEventMouseButton:
		return _mouse_button(event)
	if event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_mouse_pos = event.position
		return false
	return false


func queue_undo() -> void:
	_undo = true


func touch_move(m: int) -> void:
	_touch_move = clampi(m, -1, 1)


func touch_jump(down: bool) -> void:
	if down and not _touch_jump_held:
		_jump_press = true
	_touch_jump_held = down


func touch_aim(active: bool, index: int) -> void:
	_touch_aim = active and _can_aim
	_touch_idx = index


func touch_throw(index: int) -> void:
	_touch_aim = false
	if _can_aim and index >= 0:
		_throw = index


func _turn(step: int) -> void:
	_elevation = clampi(_elevation + step, -KEY_AIM_MAX, KEY_AIM_MAX)


static func _code(e: InputEventKey) -> int:
	return e.physical_keycode if e.physical_keycode != 0 else e.keycode


func _key(e: InputEventKey) -> bool:
	if e.echo:
		return false
	var code := _code(e)
	var down := e.pressed
	var used := false
	if e.is_action("move_left"):
		_hold(_keys_left, code, down)
		used = true
	if e.is_action("move_right"):
		_hold(_keys_right, code, down)
		used = true
	if e.is_action("aim_up") or e.is_action("aim_down"):
		var step := 1 if e.is_action("aim_up") else -1
		if down and aiming():
			_turn(step)
			_turn_keys[code] = step
			_turn_timer = REPEAT_FIRST_S
			used = true
		else:
			_turn_keys.erase(code)
			if e.is_action("jump"):
				_hold(_keys_jump, code, down)
				if down:
					_jump_press = true
				used = true
	elif e.is_action("jump"):
		_hold(_keys_jump, code, down)
		if down:
			_jump_press = true
		used = true
	if e.is_action("aim"):
		if down and _can_aim and not _kb_aim:
			_kb_aim = true
		elif not down and _kb_aim:
			_kb_aim = false
			_turn_keys.clear()
			if _can_aim:
				_throw = MazeAim.keyboard_index(_facing, _elevation)
		used = true
	if down:
		if e.is_action("aim_cancel"):
			cancel_aim()
			used = true
		if e.is_action("pause"):
			if aiming():
				cancel_aim()
			else:
				_pause = true
			used = true
		if e.is_action("undo"):
			_undo = true
			used = true
		if e.is_action("restart"):
			_restart = true
			used = true
	return used


static func _hold(keys: Dictionary, code: int, down: bool) -> void:
	if down:
		keys[code] = true
	else:
		keys.erase(code)


func _mouse_button(e: InputEventMouseButton) -> bool:
	if e.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	_mouse_pos = e.position
	if e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _can_aim and not _mouse_aim:
			_mouse_aim = true
			_mouse_idx = -1
			return true
		if not e.pressed and _mouse_aim:
			var i := aim_index()
			_mouse_aim = false
			if _can_aim:
				_throw = i
			return true
	elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and _mouse_aim:
		_mouse_aim = false
		return true
	return false
