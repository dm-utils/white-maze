class_name MazeChainView
extends Control
## Draws one chain, animated or not (design 22.8). Replays the primitives of MazeChainShapes; owns no rules.

const EXPORT_SIZE := Vector2(1200, 675)
const EXPORT_BOX := Rect2(40, 124, 1120, 488)
const EXPORT_RIGHT := 1160.0
const NAME_MAX_W := 640.0
const PLAY_ADDRESS := "play.white-maze.steefbeest.nl"

var style := MazeChainShapes.Style.CARD
## EXPORT only, for the header and footer texts (design 22.11.1): number, name, ticks, rings, par, code
var export_info := {}

var _level: MazeLevel
var _links: Array = []
var _world := 0
var _clasp := false
var _n := 0
var _t := 0.0
var _frozen := false
var _lay := {}
var _lay_size := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## t0: time into the finish moment; frozen: t stays at t0 (use MazeChainShapes.FINAL_T for the end state)
func setup(level: MazeLevel, links: Array, world: int, clasp: bool, t0: float = 0.0, frozen: bool = false) -> void:
	_level = level
	_links = links
	_world = world
	_clasp = clasp
	_n = MazeChainShapes.drawn_count(links)
	_t = t0
	_frozen = frozen
	_lay = {}
	queue_redraw()


func finish_now() -> void:
	_t = MazeChainShapes.duration(_n)
	queue_redraw()


func animating() -> bool:
	return _level != null and not _frozen and _t < MazeChainShapes.duration(_n)


func time() -> float:
	return _t


## primitives for the current time; tests read the same data that is drawn
func primitives() -> Array:
	if _level == null or size.x <= 0.0 or size.y <= 0.0:
		return []
	_ensure_layout()
	var mini := style == MazeChainShapes.Style.MINI
	var under := WhiteTheme.BUTTON["normal"] if mini else Color(0, 0, 0, 0)
	var state := MazeChainShapes.anim_state(MazeChainShapes.FINAL_T if mini else _t, _n)
	return MazeChainShapes.shapes(_lay, state, MazeChainShapes.colours(_world, under), _clasp, style)


## EXPORT header and footer: [{"text", "pos", "size", "align" ("left" | "right"), "col"}]; pos is the left (or
## right) end of the baseline
func texts() -> Array:
	if style != MazeChainShapes.Style.EXPORT or export_info.is_empty():
		return []
	var i := export_info
	var out := []
	out.append(_text(MazeStrings.s("title"), Vector2(40, 46), 22, WhiteTheme.DIM, "left"))
	var heading := _fit("%d  %s" % [i["number"], i["name"]], 36, NAME_MAX_W)
	out.append(_text(heading, Vector2(40, 92), 36, WhiteTheme.TEXT, "left"))
	out.append(_text(MazeFormat.time(i["ticks"]), Vector2(EXPORT_RIGHT, 52), 36, WhiteTheme.TEXT, "right"))
	var rings: String = MazeStrings.s("result_rings") % [i["rings"], i["par"]]
	if i["rings"] == 0:
		rings += "  " + MazeStrings.s("no_rings")
	elif i["rings"] == i["par"]:
		rings += "  " + str(WhiteText.t("perfect"))
	elif i["rings"] < i["par"]:
		rings += "  " + MazeStrings.s("under_par")
	out.append(_text(rings, Vector2(EXPORT_RIGHT, 92), 22, WhiteTheme.TEXT, "right"))
	if str(i.get("code", "")) != "":
		out.append(_text(str(i["code"]), Vector2(40, 652), 18, WhiteTheme.DIM, "left"))
	out.append(_text(PLAY_ADDRESS, Vector2(EXPORT_RIGHT, 652), 18, WhiteTheme.DIM, "right"))
	return out


func layout() -> Dictionary:
	_ensure_layout()
	return _lay


func _process(delta: float) -> void:
	if animating():
		_t += minf(delta, 0.1)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_lay = {}
		queue_redraw()


func _ensure_layout() -> void:
	if _level != null and (_lay.is_empty() or _lay_size != size):
		var export := style == MazeChainShapes.Style.EXPORT
		_lay = MazeChainShapes.layout(_level, _links, EXPORT_BOX if export else Rect2(Vector2.ZERO, size), style)
		if export:
			_lay["canvas"] = Rect2(Vector2.ZERO, size)
		_lay_size = size


static func _text(text: String, pos: Vector2, font_size: int, col: Color, align: String) -> Dictionary:
	return {"text": text, "pos": pos, "size": font_size, "col": col, "align": align}


## text cut with an ellipsis to fit max_w
static func _fit(text: String, font_size: int, max_w: float) -> String:
	var font := ThemeDB.fallback_font
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var cut := text
	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
		cut = cut.left(cut.length() - 1)
	return cut + "…"


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for s: Dictionary in primitives():
		match s["t"]:
			"poly":
				draw_colored_polygon(s["pts"], s["col"])
			"vpoly":
				draw_polygon(s["pts"], s["cols"])
			"line":
				draw_line(s["pts"][0], s["pts"][1], s["col"], s["w"], true)
			"polyline":
				draw_polyline(s["pts"], s["col"], s["w"], true)
			"circle":
				draw_circle(s["c"], s["r"], s["col"])
			"text":
				draw_string(font, s["pos"], s["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, s["size"], s["col"])
	for t: Dictionary in texts():
		var p: Vector2 = t["pos"]
		if t["align"] == "right":
			draw_string(font, p - Vector2(EXPORT_SIZE.x, 0), t["text"], HORIZONTAL_ALIGNMENT_RIGHT, EXPORT_SIZE.x,
					t["size"], t["col"])
		else:
			draw_string(font, p, t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, t["size"], t["col"])
