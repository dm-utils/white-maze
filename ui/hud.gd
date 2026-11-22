class_name MazeHud
extends Control
## Top band of the game screen (design 8.3): name and score line, clock, bead dots, three buttons, level hint.

signal undo_pressed
signal restart_pressed
signal pause_pressed

const BAND := 110.0
const DOT_R := 12.0
const DOT_GAP := 8.0
const BTN_H := 52.0
const HIGHLIGHT_TICKS := 10
const SCRIM_ALPHA := 0.55
const SCRIM_FADE := 24.0

var sim: MazeSim
var number := 1
var safe_override := ""
var hint_at_top := false # touch mode: the bottom corners belong to the controls

var _name: Label
var _score: Label
var _clock: Label
var _dots: Control
var _undo: Button
var _restart: Button
var _pause: Button
var _hint: Label
var _left: VBoxContainer
var _right: HBoxContainer
var _counted_tick := -1000
var _hint_text := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_left = VBoxContainer.new()
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name = WhiteUi.label("", WhiteTheme.FONT_SUBTITLE, WhiteTheme.TEXT)
	_score = WhiteUi.label("", WhiteTheme.FONT_MESSAGE, WhiteTheme.DIM)
	_left.add_child(_name)
	_left.add_child(_score)
	add_child(_left)

	_clock = WhiteUi.label("0:00.00", WhiteTheme.FONT_INFO, WhiteTheme.TEXT)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clock)

	_right = HBoxContainer.new()
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_theme_constant_override("separation", WhiteTheme.SPACING)
	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	_right.add_child(_dots)
	_undo = _button("undo_bead", func() -> void: undo_pressed.emit())
	_restart = _button("restart", func() -> void: restart_pressed.emit())
	_pause = _button("pause", func() -> void: pause_pressed.emit())
	add_child(_right)

	_hint = WhiteUi.label("", WhiteTheme.FONT_MESSAGE, WhiteTheme.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	refresh_texts()


## scrim over the band: the world scrolls under the HUD (design 19.10, 18.11)
func _draw() -> void:
	var vs := get_viewport_rect().size
	var band := BAND + float(WhiteSafeArea.insets(vs, safe_override)["top"])
	var solid := Color(WhiteTheme.BG, SCRIM_ALPHA)
	var clear := Color(WhiteTheme.BG, 0.0)
	draw_rect(Rect2(0.0, 0.0, vs.x, band), solid)
	var pts := PackedVector2Array(
		[Vector2(0, band), Vector2(vs.x, band), Vector2(vs.x, band + SCRIM_FADE), Vector2(0, band + SCRIM_FADE)]
	)
	draw_polygon(pts, PackedColorArray([solid, solid, clear, clear]))


func scrim_band() -> float:
	return BAND + float(WhiteSafeArea.insets(get_viewport_rect().size, safe_override)["top"])


func _button(key: String, action: Callable) -> Button:
	var b := WhiteUi.button(MazeStrings.s(key), action)
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	_right.add_child(b)
	return b


func buttons() -> Array[Button]:
	return [_undo, _restart, _pause]


## texts for the current language
func refresh_texts() -> void:
	_undo.text = MazeStrings.s("undo_bead")
	_restart.text = MazeStrings.s("restart")
	_pause.text = MazeStrings.s("pause")


func set_hint(text: String) -> void:
	_hint_text = text
	_hint.text = text


func hint_text() -> String:
	return _hint.text


func hide_hint(hidden: bool) -> void:
	_hint.visible = not hidden and _hint_text != ""


func notify_events(events: Array[Dictionary]) -> void:
	for e in events:
		if e["type"] == "launch" and e["counted"]:
			_counted_tick = sim.tick


func reset() -> void:
	_counted_tick = -1000


func score_text() -> String:
	return MazeStrings.s("hud_rings") % [sim.rings_used, sim.level.par]


func clock_text() -> String:
	return MazeFormat.time(sim.time_ticks())


func level_text() -> String:
	return "%d · %s" % [number, sim.level.names.get(WhiteText.lang, "")]


func _process(_delta: float) -> void:
	if sim == null:
		return
	var vs := get_viewport_rect().size
	var ins := WhiteSafeArea.insets(vs, safe_override)
	_left.position = Vector2(WhiteTheme.MARGIN + ins["left"], ins["top"] + 12)
	_clock.position = Vector2(0, ins["top"] + 16)
	_clock.size = Vector2(vs.x, 40)
	var right_w := _right.get_combined_minimum_size().x
	_right.size = Vector2(right_w, BTN_H)
	_right.position = Vector2(vs.x - WhiteTheme.MARGIN - ins["right"] - right_w, ins["top"] + 12)
	_hint.position = Vector2(0, BAND + ins["top"] + 6) if hint_at_top else Vector2(0, vs.y - 56 - ins["bottom"])
	_hint.size = Vector2(vs.x, 30)
	_name.text = level_text()
	_score.text = score_text()
	var hot := sim.tick - _counted_tick < HIGHLIGHT_TICKS
	_score.add_theme_color_override("font_color", WhiteTheme.TEXT if hot else WhiteTheme.DIM)
	_clock.text = clock_text()
	var n := sim.level.beads
	var w := n * (DOT_R * 2.0 + DOT_GAP)
	_dots.custom_minimum_size = Vector2(w, BTN_H)
	_dots.queue_redraw()
	queue_redraw()


func _draw_dots() -> void:
	if sim == null:
		return
	for i in sim.level.beads:
		var c := Vector2(DOT_R + i * (DOT_R * 2.0 + DOT_GAP), BTN_H / 2.0)
		if i < sim.beads_left:
			_dots.draw_circle(c, DOT_R, WhiteTheme.TEXT)
		else:
			_dots.draw_arc(c, DOT_R - 1.5, 0.0, TAU, 24, WhiteTheme.DIM, 3.0, true)
