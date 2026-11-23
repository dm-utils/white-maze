class_name MazeChainView
extends Control
## Draws one chain, animated or not (design 22.8). Replays the primitives of MazeChainShapes; owns no rules.

var style := MazeChainShapes.Style.CARD
var export_info := {} # EXPORT only: header and footer texts (design 22.11.1)

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
		_lay = MazeChainShapes.layout(_level, _links, Rect2(Vector2.ZERO, size), style)
		_lay_size = size


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
