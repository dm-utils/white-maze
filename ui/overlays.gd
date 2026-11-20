class_name MazeOverlays
extends Control
## Pause, result and rotate-hint panels over the game screen (design 8.4).

signal resume_pressed
signal restart_pressed
signal levels_pressed
signal next_pressed

const PANEL_BG := Color(0.106, 0.122, 0.149, 0.85)

var _pause: Control
var _result: Control
var _rotate: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func pause_visible() -> bool:
	return _pause != null and _pause.visible


func result_visible() -> bool:
	return _result != null and _result.visible


func rotate_visible() -> bool:
	return _rotate != null and _rotate.visible


func any_open() -> bool:
	return pause_visible() or result_visible()


func show_pause(touch: bool) -> void:
	_free(_pause)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", WhiteTheme.SPACING)
	col.add_child(_centered(WhiteUi.label(MazeStrings.s("pause"), WhiteTheme.FONT_TITLE, WhiteTheme.ACCENT)))
	var first := _button(col, "resume", func() -> void: resume_pressed.emit())
	_button(col, "restart", func() -> void: restart_pressed.emit())
	_button(col, "levels_btn", func() -> void: levels_pressed.emit())
	col.add_child(_dim_label(MazeStrings.s("help_touch" if touch else "help_keys")))
	col.add_child(_dim_label(MazeStrings.s("help_par")))
	_pause = _panel(col)
	_keep_rotate_on_top()
	first.grab_focus()


func hide_pause() -> void:
	_free(_pause)
	_pause = null


## data: ticks, rings, par, new_best, best_ticks, has_next
func show_result(data: Dictionary) -> void:
	_free(_result)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", WhiteTheme.SPACING)
	col.add_child(_centered(WhiteUi.label(MazeStrings.s("finished"), WhiteTheme.FONT_TITLE, WhiteTheme.ACCENT)))
	col.add_child(_centered(WhiteUi.label(MazeFormat.time(data["ticks"]), WhiteTheme.FONT_TITLE, WhiteTheme.TEXT)))
	var rings := MazeStrings.s("result_rings") % [data["rings"], data["par"]]
	if data["rings"] == data["par"]:
		rings += "  " + str(WhiteText.t("perfect"))
	elif data["rings"] < data["par"]:
		rings += "  " + MazeStrings.s("under_par")
	col.add_child(_centered(WhiteUi.label(rings, WhiteTheme.FONT_INFO, WhiteTheme.TEXT)))
	if data["new_best"]:
		col.add_child(_centered(WhiteUi.label(MazeStrings.s("new_record"), WhiteTheme.FONT_INFO, WhiteTheme.ACCENT)))
	else:
		var best := MazeStrings.s("best_time") % MazeFormat.time(data["best_ticks"])
		col.add_child(_centered(WhiteUi.label(best, WhiteTheme.FONT_INFO, WhiteTheme.DIM)))
	var restart := _button(col, "restart", func() -> void: restart_pressed.emit())
	var next: Button = null
	if data["has_next"]:
		next = _button(col, "next", func() -> void: next_pressed.emit())
	_button(col, "levels_btn", func() -> void: levels_pressed.emit())
	_result = _panel(col)
	_keep_rotate_on_top()
	(next if next != null else restart).grab_focus()


func hide_result() -> void:
	_free(_result)
	_result = null


func show_rotate(on: bool) -> void:
	if on and _rotate == null:
		var l := WhiteUi.label(MazeStrings.s("rotate"), WhiteTheme.FONT_TITLE, WhiteTheme.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_rotate = _solid_panel(l)
	elif not on and _rotate != null:
		_free(_rotate)
		_rotate = null


func _free(c: Control) -> void:
	if c != null:
		if c.get_parent() == self:
			remove_child(c)
		c.queue_free()


func _keep_rotate_on_top() -> void:
	if _rotate != null:
		move_child(_rotate, get_child_count() - 1)


func _solid_panel(content: Control) -> Control:
	var bg := ColorRect.new()
	bg.color = WhiteTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.add_child(content)
	add_child(bg)
	return bg


func _panel(col: Control) -> Control:
	var bg := ColorRect.new()
	bg.color = PANEL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.custom_minimum_size = Vector2(560, 0)
	center.add_child(col)
	bg.add_child(center)
	add_child(bg)
	return bg


func _button(col: Control, key: String, action: Callable) -> Button:
	var b := WhiteUi.button(MazeStrings.s(key), action)
	b.focus_mode = Control.FOCUS_ALL
	col.add_child(b)
	return b


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _dim_label(text: String) -> Label:
	var l := WhiteUi.label(text, WhiteTheme.FONT_MESSAGE, WhiteTheme.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	return l
