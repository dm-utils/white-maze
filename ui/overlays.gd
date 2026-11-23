class_name MazeOverlays
extends Control
## Pause, result and rotate-hint panels over the game screen (design 8.4).

signal resume_pressed
signal restart_pressed
signal levels_pressed
signal next_pressed

const PANEL_BG := Color(0.106, 0.122, 0.149, 0.85)
const RESULT_COL_W := 480.0
const RESULT_GAP := 40.0
const CARD_MIN_W := 480.0
const CARD_MAX_W := 800.0
const SKIP_GRACE_S := 0.3

var chain_view: MazeChainView # the card of the open result, or null
var result_column: Control # the text and button column of the open result
var safe_override := ""

var _result_margin: MarginContainer
var _result_vs := Vector2.ZERO
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


## data: ticks, rings, par, new_best, best_ticks, has_next; for the chain card also level, links, world and
## optionally reduced_motion, chain_t (design 22.8)
func show_result(data: Dictionary) -> void:
	_free(_result)
	chain_view = null
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", WhiteTheme.SPACING)
	col.custom_minimum_size = Vector2(RESULT_COL_W, 0)
	col.add_child(_centered(WhiteUi.label(MazeStrings.s("finished"), WhiteTheme.FONT_TITLE, WhiteTheme.ACCENT)))
	col.add_child(_centered(WhiteUi.label(MazeFormat.time(data["ticks"]), WhiteTheme.FONT_TITLE, WhiteTheme.TEXT)))
	var rings := MazeStrings.s("result_rings") % [data["rings"], data["par"]]
	if data["rings"] == data["par"]:
		rings += "  " + str(WhiteText.t("perfect"))
	elif data["rings"] < data["par"]:
		rings += "  " + MazeStrings.s("under_par")
	col.add_child(_centered(WhiteUi.label(rings, WhiteTheme.FONT_INFO, WhiteTheme.TEXT)))
	if data["rings"] == 0:
		col.add_child(_centered(WhiteUi.label(MazeStrings.s("no_rings"), WhiteTheme.FONT_INFO, WhiteTheme.TEXT)))
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
	result_column = col
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(RESULT_GAP))
	if data.has("level") and data["level"] is MazeLevel:
		chain_view = _chain_card(data)
		row.add_child(chain_view)
	row.add_child(col)
	_result = _result_panel(row)
	_layout_result()
	_keep_rotate_on_top()
	(next if next != null else restart).grab_focus()


func _chain_card(data: Dictionary) -> MazeChainView:
	var view := MazeChainView.new()
	view.style = MazeChainShapes.Style.CARD
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t0 := 0.0
	var frozen := false
	if data.get("reduced_motion", false):
		t0 = MazeChainShapes.FINAL_T
		frozen = true
	elif float(data.get("chain_t", -1.0)) >= 0.0:
		t0 = float(data["chain_t"])
		frozen = true
	view.setup(data["level"], data.get("links", []), int(data.get("world", 0)), data["rings"] <= data["par"], t0, frozen)
	return view


## true while the chain is still being strung
func chain_animating() -> bool:
	return result_visible() and chain_view != null and chain_view.animating()


## key, mouse or touch press during the animation skips it; the first SKIP_GRACE_S of it eat presses silently
func _input(event: InputEvent) -> void:
	if not chain_animating():
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventScreenTouch:
		pressed = event.pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if chain_view.time() >= SKIP_GRACE_S:
		chain_view.finish_now()


## card size and safe margins follow the viewport (design 22.8)
func _process(_delta: float) -> void:
	if result_visible() and get_viewport_rect().size != _result_vs:
		_layout_result()


func _layout_result() -> void:
	if _result_margin == null:
		return
	var vs := get_viewport_rect().size
	_result_vs = vs
	var ins := WhiteSafeArea.insets(vs, safe_override)
	var m := float(WhiteTheme.MARGIN)
	_result_margin.add_theme_constant_override("margin_left", int(m + ins["left"]))
	_result_margin.add_theme_constant_override("margin_right", int(m + ins["right"]))
	_result_margin.add_theme_constant_override("margin_top", int(m + ins["top"]))
	_result_margin.add_theme_constant_override("margin_bottom", int(m + ins["bottom"]))
	if chain_view != null:
		chain_view.custom_minimum_size = card_size(vs - Vector2(2.0 * m + ins["left"] + ins["right"],
				2.0 * m + ins["top"] + ins["bottom"]))


## 16:9 card beside the column in the free area (design 22.8)
static func card_size(avail: Vector2) -> Vector2:
	var w := clampf(avail.x - RESULT_COL_W - RESULT_GAP, CARD_MIN_W, CARD_MAX_W)
	var h := floorf(w * 9.0 / 16.0)
	if h > avail.y:
		h = avail.y
		w = floorf(h * 16.0 / 9.0)
	return Vector2(w, h)


func hide_result() -> void:
	_free(_result)
	_result = null
	_result_margin = null
	chain_view = null
	result_column = null


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


## full-screen dim panel with the content centred inside the safe margins
func _result_panel(content: Control) -> Control:
	var bg := ColorRect.new()
	bg.color = PANEL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_margin = MarginContainer.new()
	_result_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(content)
	_result_margin.add_child(center)
	bg.add_child(_result_margin)
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
