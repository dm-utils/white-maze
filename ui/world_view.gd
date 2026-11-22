class_name MazeWorldView
extends Node2D
## Draws the level, rings, beads, player and aim preview from a MazeSim (design 8.1, 4.5). Never changes the sim.

const TILE := 40.0
const BASE_Z := 10
const LILITH_SLOTS := 4
const NEVER := -1000
const RING_LEN := 38.0
const RING_THICK := 10.0
const RING_STROKE := 5.0
const RING_LIFT := 5.0 # ring centre sits this far in front of its face
const RING_POINTS := 28
const RING_GLOW := [[17.0, 0.08], [11.0, 0.18]] # width, alpha of the two halo strokes
const RING_GLOW_FLASH := [[17.0, 0.25], [11.0, 0.5]]
const BEAD_HALO_R := 11.0
const BEAD_HALO_ALPHA := 0.2
const FLASH_TICKS := 10
const FADE_IN_TICKS := 10
const LOOK_FOLLOW := 0.35 # per tick, share of the velocity change taken by the look velocity
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
var world_id := MazeWorlds.World.TEMPLE
var build_count := 0 # tests: static layers are built once per level
var blend := MazePoseBlend.new()
var last_rig := {} # joints as last drawn, local frame

var _bake: MazeStaticBake

var _flash := {}
var _respawn_tick := NEVER
var _land_tick := NEVER
var _throw_tick := NEVER
var _death_tick := NEVER
var _throw_dir := Vector2.RIGHT # px, from the newest throw
var _face := 1 # view-only facing: follows the aim and the throw
var _look_prev := Vector2.ZERO # smoothed velocity in px/s, see after_tick
var _look_cur := Vector2.ZERO


func _init() -> void:
	z_index = BASE_Z # baked chunks sit at -2 relative to this, above the screen background


## effects that come from sim events
func notify_events(events: Array[Dictionary]) -> void:
	for e in events:
		if e["type"] == "launch":
			_flash[[e["cell"], e["face"]]] = sim.tick
		elif e["type"] == "respawn":
			_respawn_tick = sim.tick
			blend.reset()
			_look_prev = Vector2.ZERO
			_look_cur = Vector2.ZERO
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
	_look_prev = Vector2.ZERO
	_look_cur = Vector2.ZERO
	last_rig = {}
	blend.reset()


## after the events of every tick: smooths the velocity that drives tails and launch tilt (20.3.4)
func after_tick() -> void:
	_look_prev = _look_cur
	_look_cur = _look_cur.lerp(Vector2(sim.vx, sim.vy) * 60.0 / 1000.0, LOOK_FOLLOW)


## render time in ticks: the state that lerp(prev, current, alpha) shows
func render_time() -> float:
	return float(sim.tick) - 1.0 + alpha


## interpolated player centre in world px
func player_centre() -> Vector2:
	var a := alpha if (sim.alive() and _respawn_tick != sim.tick) else 1.0
	var x := lerpf(sim.prev_px, sim.px, a) / 1000.0
	var y := lerpf(sim.prev_py, sim.py, a) / 1000.0
	return Vector2(x, y - 16.0)


## (re)creates the baked static world for the current level and world; call once per level, not per attempt
func build() -> void:
	if _bake == null:
		_bake = MazeStaticBake.new()
		add_child(_bake)
	_bake.build(sim.level, world_id)
	build_count += 1


## canvas draws of the static layers so far
func static_draws() -> int:
	return 0 if _bake == null else _bake.draws()


func chunk_count() -> int:
	return 0 if _bake == null else _bake.chunk_count()


## texture memory of the baked chunks in bytes
func baked_bytes() -> int:
	return 0 if _bake == null else _bake.baked_bytes


func _draw() -> void:
	if sim == null:
		return
	for r in sim.rings:
		_draw_ring(r["cell"], r["face"], _flashing(r))
	_draw_beads()
	_draw_player()
	_draw_player_marker()
	if aim_index >= 0:
		_draw_aim()


func _flashing(r: Dictionary) -> bool:
	var t: Variant = _flash.get([r["cell"], r["face"]])
	return t != null and sim.tick - int(t) < FLASH_TICKS


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


func _draw_ring(cell: Vector2i, face: int, flash: bool) -> void:
	var centre := face_point(cell, face, RING_LIFT)
	var pts := ring_points(centre, face)
	var color := WhiteTheme.ACCENT if flash else MazeWorlds.RING
	for g: Array in (RING_GLOW_FLASH if flash else RING_GLOW):
		draw_polyline(pts, Color(color, g[1]), g[0], true)
	draw_polyline(pts, color, RING_STROKE, true)
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
		draw_circle(p, BEAD_HALO_R, Color(MazeWorlds.RING, BEAD_HALO_ALPHA))
		draw_circle(p, BEAD_R, MazeWorlds.RING)


func _draw_player() -> void:
	var p := player_params()
	if p.is_empty():
		return
	draw_set_transform(player_centre() + Vector2(0.0, 16.0), 0.0, Vector2(_face, 1.0))
	for s in MazeLilith.shapes(p):
		_draw_shape(s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## pose of Lilith for this frame, or {} when she is not visible; also advances the pose blend
func player_params() -> Dictionary:
	var t := render_time()
	var fade := 1.0
	var dead_k := 0.0
	if not sim.alive():
		var born := float(sim.tick - (MazeTuning.DEATH_TICKS - sim.dead_ticks))
		if _death_tick != NEVER:
			born = float(_death_tick)
		dead_k = clampf(t - born, 0.0, float(MazeTuning.DEATH_TICKS)) / MazeTuning.DEATH_TICKS
		fade = 1.0 - dead_k
	else:
		fade = clampf((t - float(_respawn_tick)) / FADE_IN_TICKS, 0.0, 1.0)
	if fade <= 0.0:
		return {}
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
		var age := t - float(_land_tick)
		if age < 0.0:
			squash = 0.0
		elif age < 1.0:
			squash = age
		else:
			squash = maxf(0.0, 1.0 - (age - 1.0) / MazeLilith.LAND_TICKS)
	var look := _look_prev.lerp(_look_cur, alpha)
	var p := {
		"body": body, "arm": arm, "tick": t, "fade": fade, "squash_k": squash,
		"phase": fposmod(feet.x / MazeLilith.STRIDE_PX, 1.0),
		"aim_angle": atan2(dir.y, dir.x * _face),
		"throw_k": clampf((t - float(_throw_tick)) / MazeLilith.THROW_TICKS, 0.0, 1.0),
		"dead_k": dead_k,
		"vel": Vector2(look.x * _face, look.y),
		"slots": mini(sim.level.beads, LILITH_SLOTS), "filled": mini(sim.beads_left, LILITH_SLOTS),
	}
	p["rig"] = blend.apply(Vector2i(body, arm), MazeLilith.rig(p), t)
	last_rig = p["rig"]
	return p


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
