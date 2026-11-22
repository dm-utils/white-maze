class_name MazeWorldView
extends Node2D
## Draws the level, rings, beads, player and aim preview from a MazeSim (design 8.1, 4.5). Never changes the sim.

const TILE := 40.0
const GRID := Color("#20252D")
const SOLID := WhiteTheme.BUTTON["normal"]
const EDGE := WhiteTheme.BUTTON["pressed"]
const EDGE_W := 4.0
const NO_RING_FILL := Color("#20252D")
const HATCH := Color("#343B48")
const HATCH_STEP := 10
const SPIKE := WhiteTheme.BUTTON["pressed"]
const DOOR_FRAME := WhiteTheme.BUTTON["pressed"]
const DOOR_LIGHT := Color("#FFE7B0")
const DOOR_POST := 5.0
const DOOR_LINTEL := 6.0
const DOOR_ALPHA_BOTTOM := 0.9
const DOOR_ALPHA_TOP := 0.15
const DOOR_GLOWS := [[34.0, 0.06], [22.0, 0.08]]
const LILITH_SLOTS := 4
const NEVER := -1000
const RING_LEN := 38.0
const RING_THICK := 10.0
const RING_STROKE := 5.0
const RING_LIFT := 5.0 # ring centre sits this far in front of its face
const RING_POINTS := 28
const FLASH_TICKS := 10
const FADE_IN_TICKS := 10
const BEAD_R := 7.0
const DOT_R := 1.5
const DOT_STEP := 14.0
const ARROW_ALPHA := 0.35
const EDGE_INSET := 24.0 # edge marker sits this far inside the play rect
const CHEVRON_LEN := 10.0
const CHEVRON_OPEN := 7.0
const CHEVRON_W := 3.0
const MARKER_R := 22.0 # player marker in the overview, canvas units
const MARKER_W := 2.0
const MARKER_ALPHA := 0.6

var sim: MazeSim
var alpha := 1.0 # render interpolation between the last two ticks
var aim_index := -1 # >= 0 while aiming
var view_rect := Rect2() # world px visible below the HUD band (camera)
var view_zoom := 1.0
var overview_k := 0.0 # 0..1, weight of the overview view

var _flash := {}
var _respawn_tick := NEVER
var _land_tick := NEVER
var _throw_tick := NEVER
var _death_tick := NEVER
var _throw_dir := Vector2.RIGHT # px, from the newest throw
var _face := 1 # view-only facing: follows the aim and the throw


## effects that come from sim events
func notify_events(events: Array[Dictionary]) -> void:
	for e in events:
		if e["type"] == "launch":
			_flash[[e["cell"], e["face"]]] = sim.tick
		elif e["type"] == "respawn":
			_respawn_tick = sim.tick
		elif e["type"] == "land":
			_land_tick = sim.tick
		elif e["type"] == "death":
			_death_tick = sim.tick
		elif e["type"] == "throw":
			_throw_tick = sim.tick
			if not sim.flights.is_empty():
				var f: Dictionary = sim.flights.back()
				_throw_dir = Vector2(f["to"] - f["from"])


func reset() -> void:
	_flash.clear()
	_respawn_tick = NEVER
	_land_tick = NEVER
	_throw_tick = NEVER
	_death_tick = NEVER
	_face = 1


## interpolated player centre in world px
func player_centre() -> Vector2:
	var a := alpha if (sim.alive() and _respawn_tick != sim.tick) else 1.0
	var x := lerpf(sim.prev_px, sim.px, a) / 1000.0
	var y := lerpf(sim.prev_py, sim.py, a) / 1000.0
	return Vector2(x, y - 16.0)


func _visible_tiles() -> Rect2i:
	var vr := get_canvas_transform().affine_inverse() * get_viewport_rect()
	var l := clampi(floori(vr.position.x / TILE) - 1, 0, sim.level.width)
	var t := clampi(floori(vr.position.y / TILE) - 1, 0, sim.level.height)
	var r := clampi(ceili(vr.end.x / TILE) + 1, 0, sim.level.width)
	var b := clampi(ceili(vr.end.y / TILE) + 1, 0, sim.level.height)
	return Rect2i(l, t, r - l, b - t)


func _draw() -> void:
	if sim == null:
		return
	var vis := _visible_tiles()
	_draw_grid(vis)
	_draw_tiles(vis)
	_draw_finish()
	for r in sim.rings:
		_draw_ring(r["cell"], r["face"], _ring_color(r))
	_draw_beads()
	_draw_player()
	_draw_player_marker()
	if aim_index >= 0:
		_draw_aim()


func _draw_grid(vis: Rect2i) -> void:
	for x in range(vis.position.x, vis.end.x + 1):
		draw_line(Vector2(x * TILE, vis.position.y * TILE), Vector2(x * TILE, vis.end.y * TILE), GRID, 1.0)
	for y in range(vis.position.y, vis.end.y + 1):
		draw_line(Vector2(vis.position.x * TILE, y * TILE), Vector2(vis.end.x * TILE, y * TILE), GRID, 1.0)


func _draw_tiles(vis: Rect2i) -> void:
	var lv := sim.level
	for y in range(vis.position.y, vis.end.y):
		for x in range(vis.position.x, vis.end.x):
			var c := lv.cell(x, y)
			var o := Vector2(x * TILE, y * TILE)
			match c:
				MazeLevel.Cell.SOLID:
					draw_rect(Rect2(o, Vector2(TILE, TILE)), SOLID)
					_draw_edges(x, y, o)
				MazeLevel.Cell.NO_RING:
					draw_rect(Rect2(o, Vector2(TILE, TILE)), NO_RING_FILL)
					_draw_hatch(o)
				MazeLevel.Cell.SPIKE:
					_draw_spikes(o)


func _draw_edges(x: int, y: int, o: Vector2) -> void:
	var lv := sim.level
	if not lv.solid(x, y - 1):
		draw_rect(Rect2(o, Vector2(TILE, EDGE_W)), EDGE)
	if not lv.solid(x, y + 1):
		draw_rect(Rect2(o + Vector2(0, TILE - EDGE_W), Vector2(TILE, EDGE_W)), EDGE)
	if not lv.solid(x - 1, y):
		draw_rect(Rect2(o, Vector2(EDGE_W, TILE)), EDGE)
	if not lv.solid(x + 1, y):
		draw_rect(Rect2(o + Vector2(TILE - EDGE_W, 0), Vector2(EDGE_W, TILE)), EDGE)


func _draw_hatch(o: Vector2) -> void:
	for t in range(HATCH_STEP, 2 * int(TILE), HATCH_STEP):
		var a := Vector2(minf(t, TILE), maxf(0.0, t - TILE))
		var b := Vector2(maxf(0.0, t - TILE), minf(t, TILE))
		draw_line(o + a, o + b, HATCH, 1.0)


func _draw_spikes(o: Vector2) -> void:
	for i in 2:
		var x := o.x + i * TILE / 2.0
		var pts := PackedVector2Array(
			[
				Vector2(x + 1, o.y + TILE),
				Vector2(x + TILE / 4.0, o.y + TILE / 2.0),
				Vector2(x + TILE / 2.0 - 1, o.y + TILE),
			]
		)
		draw_colored_polygon(pts, SPIKE)


func _draw_finish() -> void:
	var o := Vector2(sim.level.finish) * TILE
	var mid := o + Vector2(TILE, TILE) / 2.0
	for g in DOOR_GLOWS:
		draw_circle(mid, g[0], Color(DOOR_LIGHT, g[1]))
	var inner := Rect2(o + Vector2(DOOR_POST, DOOR_LINTEL), Vector2(TILE - 2.0 * DOOR_POST, TILE - DOOR_LINTEL))
	var top := Color(DOOR_LIGHT, DOOR_ALPHA_TOP)
	var bottom := Color(DOOR_LIGHT, DOOR_ALPHA_BOTTOM)
	var corners := PackedVector2Array(
		[
			inner.position, Vector2(inner.end.x, inner.position.y),
			inner.end, Vector2(inner.position.x, inner.end.y),
		]
	)
	draw_polygon(corners, PackedColorArray([top, top, bottom, bottom]))
	draw_rect(Rect2(o, Vector2(DOOR_POST, TILE)), DOOR_FRAME)
	draw_rect(Rect2(o + Vector2(TILE - DOOR_POST, 0), Vector2(DOOR_POST, TILE)), DOOR_FRAME)
	draw_rect(Rect2(o, Vector2(TILE, DOOR_LINTEL)), DOOR_FRAME)


func _ring_color(r: Dictionary) -> Color:
	var t: Variant = _flash.get([r["cell"], r["face"]])
	if t != null and sim.tick - int(t) < FLASH_TICKS:
		return WhiteTheme.ACCENT
	return WhiteTheme.TEXT


## point on the face centre, pushed out by lift
static func face_point(cell: Vector2i, face: int, lift: float) -> Vector2:
	var c := (Vector2(cell) + Vector2(0.5, 0.5)) * TILE
	var n := Vector2(MazeLevel.FACE_STEP[face])
	return c + n * (TILE / 2.0 + lift)


static func ring_points(centre: Vector2, face: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var horizontal := face == MazeLevel.Face.UP or face == MazeLevel.Face.DOWN
	var rx := (RING_LEN if horizontal else RING_THICK) / 2.0
	var ry := (RING_THICK if horizontal else RING_LEN) / 2.0
	for i in RING_POINTS + 1:
		var a := TAU * i / RING_POINTS
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_ring(cell: Vector2i, face: int, color: Color) -> void:
	var centre := face_point(cell, face, RING_LIFT)
	draw_polyline(ring_points(centre, face), color, RING_STROKE, true)
	_draw_arrow(centre, face, Color(color, ARROW_ALPHA))


func _draw_arrow(centre: Vector2, face: int, color: Color) -> void:
	var n := Vector2(MazeLevel.FACE_STEP[face])
	var side := Vector2(-n.y, n.x)
	var tip := centre + n * 24.0
	var base := centre + n * 12.0
	draw_line(base, tip, color, 3.0)
	draw_line(tip, tip - n * 6.0 + side * 5.0, color, 3.0)
	draw_line(tip, tip - n * 6.0 - side * 5.0, color, 3.0)


func _draw_beads() -> void:
	for f in sim.flights:
		var span := maxi(1, int(f["arrive_tick"]) - int(f["throw_tick"]))
		var k := clampf((sim.tick - int(f["throw_tick"]) + alpha) / span, 0.0, 1.0)
		var p := Vector2(f["from"]).lerp(Vector2(f["to"]), k) / 1000.0
		draw_circle(p, BEAD_R, WhiteTheme.ACCENT)


func _draw_player() -> void:
	var fade := 1.0
	if not sim.alive():
		fade = float(sim.dead_ticks) / MazeTuning.DEATH_TICKS
	else:
		fade = clampf(float(sim.tick - _respawn_tick) / FADE_IN_TICKS, 0.0, 1.0)
	if fade <= 0.0:
		return
	var feet := player_centre() + Vector2(0.0, 16.0)
	var aiming := aim_index >= 0
	var since_throw := sim.tick - _throw_tick
	var dir := Vector2.ZERO
	if aiming:
		dir = Vector2(MazeAim.dir(aim_index))
	elif since_throw < MazeLilith.THROW_TICKS:
		dir = _throw_dir
	if dir.x != 0.0:
		_face = 1 if dir.x > 0.0 else -1
	elif dir == Vector2.ZERO and not aiming:
		_face = sim.facing if sim.facing != 0 else _face
	var body := MazeLilith.body_pose(sim.alive(), sim.grounded, sim.vx, sim.vy, sim.launched)
	var arm := MazeLilith.arm_mode(aiming, since_throw, body)
	var squash := 0.0
	if sim.grounded and sim.alive():
		squash = maxf(0.0, 1.0 - float(sim.tick - _land_tick) / MazeLilith.LAND_TICKS)
	var vel := Vector2(sim.vx, sim.vy) * 60.0 / 1000.0
	var p := {
		"body": body, "arm": arm, "tick": sim.tick, "fade": fade, "squash_k": squash,
		"phase": fposmod(feet.x / MazeLilith.STRIDE_PX, 1.0),
		"aim_angle": atan2(dir.y, dir.x * _face),
		"throw_k": clampf(float(since_throw) / MazeLilith.THROW_TICKS, 0.0, 1.0),
		"dead_k": 1.0 - float(sim.dead_ticks) / MazeTuning.DEATH_TICKS if not sim.alive() else 0.0,
		"vel": Vector2(vel.x * _face, vel.y),
		"slots": mini(sim.level.beads, LILITH_SLOTS), "filled": mini(sim.beads_left, LILITH_SLOTS),
	}
	draw_set_transform(feet, 0.0, Vector2(_face, 1.0))
	for s in MazeLilith.shapes(p):
		_draw_shape(s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_player_marker() -> void:
	if overview_k <= 0.0 or not sim.alive():
		return
	var col := Color(WhiteTheme.TEXT, MARKER_ALPHA * overview_k)
	draw_arc(player_centre(), MARKER_R / view_zoom, 0.0, TAU, 32, col, MARKER_W / view_zoom, true)


## where the segment a to b leaves the rect (a inside), or b when it does not
static func exit_point(a: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var d := b - a
	var t := 1.0
	for axis in 2:
		if d[axis] > 0.0:
			t = minf(t, (rect.end[axis] - a[axis]) / d[axis])
		elif d[axis] < 0.0:
			t = minf(t, (rect.position[axis] - a[axis]) / d[axis])
	return a + d * maxf(t, 0.0)


func _draw_edge_marker(from: Vector2, to: Vector2, col: Color) -> void:
	if view_rect.size == Vector2.ZERO or view_rect.has_point(to):
		return
	var inner := view_rect.grow(-EDGE_INSET)
	if not inner.has_point(from):
		return
	var p := exit_point(from, to, inner)
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var back := p - dir * CHEVRON_LEN
	draw_line(p, back + side * CHEVRON_OPEN, col, CHEVRON_W, true)
	draw_line(p, back - side * CHEVRON_OPEN, col, CHEVRON_W, true)


func _draw_shape(s: Dictionary) -> void:
	var pts: PackedVector2Array = s["pts"]
	match s["type"]:
		"circle":
			draw_circle(s["c"], s["r"], s["color"])
		"line":
			draw_polyline(pts, s["color"], s["w"], true)
		"loop":
			draw_polyline(pts, s["color"], s["w"], true)
		"poly":
			draw_colored_polygon(pts, s["color"])


func _draw_aim() -> void:
	var cast := sim.cast(aim_index)
	var from := player_centre()
	var to := Vector2(cast["hit"]) / 1000.0
	var ok: bool = cast["valid"]
	var col := Color(WhiteTheme.TEXT, 0.7) if ok else WhiteTheme.DIM
	var len := from.distance_to(to)
	if len > 1.0:
		var dir := (to - from) / len
		var d := DOT_STEP
		while d < len:
			draw_circle(from + dir * d, DOT_R, col)
			d += DOT_STEP
		_draw_edge_marker(from, to, col)
	if ok:
		var centre := face_point(cast["cell"], cast["face"], RING_LIFT)
		var pts := ring_points(centre, cast["face"])
		for i in range(0, pts.size() - 1, 2):
			draw_line(pts[i], pts[i + 1], WhiteTheme.TEXT, 3.0)
		_draw_arrow(centre, cast["face"], Color(WhiteTheme.TEXT, ARROW_ALPHA))
	elif cast["reason"] != "dead":
		draw_line(to + Vector2(-6, -6), to + Vector2(6, 6), WhiteTheme.DIM, 3.0)
		draw_line(to + Vector2(-6, 6), to + Vector2(6, -6), WhiteTheme.DIM, 3.0)
