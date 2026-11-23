class_name MazeSim
extends RefCounted
## Fixed-step integer simulation of player, beads, rings, hazards and finish. Pure function of the level and the
## per-tick MazeInput. Integers only; positions in units (1/1000 px), velocities per tick. No nodes, input, time or
## randomness in here (ADR 0002).

enum Ground { NONE, FLAT, GENTLE, STEEP }

const T := MazeTuning.TILE
const HW := MazeTuning.PLAYER_W / 2

var level: MazeLevel
var tick := 0
var px := 0 # player bottom-centre
var py := 0
var prev_px := 0 # position before the last step, for render interpolation
var prev_py := 0
var vx := 0
var vy := 0 # positive = down
var facing := 1
var grounded := false
var ground := Ground.NONE # what the player stands on after the last step; grounded == (ground != NONE)
var coyote := 0
var buffer := 0
var jumping := false
var launched := false
var lock_ticks := 0
var dead_ticks := 0
var deaths := 0
var beads_left := 0
var rings_used := 0 # thrown rings that launched at least once; never decreases
var rings: Array[Dictionary] = [] # cell, face, preset, order, cooldown, used
var flights: Array[Dictionary] = [] # cell, face, from, to, throw_tick, arrive_tick, order
var throw_count := 0
var clock_start := -1
var finish_tick := -1
var events: Array[Dictionary] = []


func _init(lvl: MazeLevel) -> void:
	level = lvl
	beads_left = lvl.beads
	for r in lvl.preset_rings:
		rings.append({"cell": r["cell"], "face": r["face"], "preset": true, "order": -1, "cooldown": 0, "used": false})
	_respawn()
	prev_px = px
	prev_py = py


func finished() -> bool:
	return finish_tick >= 0


func alive() -> bool:
	return dead_ticks == 0


func sliding() -> bool:
	return ground == Ground.STEEP


## slope Cell under the centre when standing on a slope, else -1 (view)
func ground_kind() -> int:
	if ground != Ground.GENTLE and ground != Ground.STEEP:
		return -1
	return _slope_under(px, py).x


func time_ticks() -> int:
	if clock_start < 0:
		return 0
	if finish_tick >= 0:
		return finish_tick - clock_start + 1
	return tick - clock_start + 1


## canonical text of all state except level and events, for determinism tests
func snapshot() -> String:
	var parts := PackedStringArray()
	for v in [tick, px, py, prev_px, prev_py, vx, vy, facing, grounded, ground, coyote, buffer, jumping, launched, lock_ticks,
			dead_ticks, deaths, beads_left, rings_used, throw_count, clock_start, finish_tick]:
		parts.append(str(v))
	for r in rings:
		parts.append("r%s,%d,%s,%d,%d,%s" % [r["cell"], r["face"], r["preset"], r["order"], r["cooldown"], r["used"]])
	for f in flights:
		parts.append("f%s,%d,%s,%s,%d,%d,%d" % [f["cell"], f["face"], f["from"], f["to"], f["throw_tick"],
				f["arrive_tick"], f["order"]])
	return "|".join(parts)


static func _fdiv(a: int, b: int) -> int:
	return a / b if a >= 0 else -((-a + b - 1) / b)


static func _approach(v: int, target: int, rate: int) -> int:
	if v < target:
		return mini(v + rate, target)
	return maxi(v - rate, target)


static func _sign(v: int) -> int:
	return 1 if v > 0 else (-1 if v < 0 else 0)


func _event(type: String, extra: Dictionary = {}) -> void:
	var e := {"type": type}
	e.merge(extra)
	events.append(e)


func _respawn() -> void:
	px = level.spawn.x * T + T / 2
	py = (level.spawn.y + 1) * T
	vx = 0
	vy = 0
	facing = 1
	jumping = false
	launched = false
	lock_ticks = 0
	coyote = 0
	buffer = 0
	_compute_ground()


func _box() -> Rect2i:
	return Rect2i(px - HW, py - MazeTuning.PLAYER_H, MazeTuning.PLAYER_W, MazeTuning.PLAYER_H)


## (kind, row) of the slope cell in the column of x whose row is fdiv(y - 1, T) or fdiv(y, T), else (-1, 0)
func _slope_under(x: int, y: int) -> Vector2i:
	if level.slope_count == 0:
		return Vector2i(-1, 0)
	var cx := _fdiv(x, T)
	for cy in [_fdiv(y - 1, T), _fdiv(y, T)]:
		var kind := level.cell(cx, cy)
		if MazeSlope.is_slope(kind):
			return Vector2i(kind, cy)
	return Vector2i(-1, 0)


func _surface_at(u: Vector2i, x: int) -> int:
	return MazeSlope.surface(u.x, u.y, x - _fdiv(x, T) * T)


func _compute_ground() -> void:
	var u := _slope_under(px, py)
	if u.x >= 0 and py == _surface_at(u, px):
		ground = Ground.STEEP if MazeSlope.steep(u.x) else Ground.GENTLE
	elif posmod(py, T) == 0 and _solid_in_cols(py / T, px - HW, px + HW):
		ground = Ground.FLAT
	else:
		ground = Ground.NONE
	grounded = ground != Ground.NONE


func _box_free(left: int, top: int, right: int, bottom: int) -> bool:
	for cy in range(_fdiv(top, T), _fdiv(bottom - 1, T) + 1):
		for cx in range(_fdiv(left, T), _fdiv(right - 1, T) + 1):
			if level.solid(cx, cy):
				return false
	return true


func step(input: MazeInput) -> void:
	events.clear()
	tick += 1
	if finished():
		return
	prev_px = px
	prev_py = py
	if clock_start < 0 and (input.move != 0 or input.jump_pressed):
		clock_start = tick
	if input.undo:
		_undo()
	if input.throw_dir >= 0:
		_throw(input.throw_dir)
	_land_flights()
	for r in rings:
		if r["cooldown"] > 0:
			r["cooldown"] -= 1
	if dead_ticks > 0:
		dead_ticks -= 1
		if dead_ticks == 0:
			_respawn()
			_event("respawn")
		return
	_horizontal(input)
	_jump(input)
	_gravity(input)
	_move(input.move)
	_launch_from_rings()
	if _hazard_hit():
		dead_ticks = MazeTuning.DEATH_TICKS
		deaths += 1
		vx = 0
		vy = 0
		_event("death")
		return
	if _box().intersects(Rect2i(level.finish.x * T, level.finish.y * T, T, T)):
		finish_tick = tick
		if clock_start < 0:
			clock_start = tick
		_event("finish", {"ticks": time_ticks(), "rings": rings_used})


func _undo() -> void:
	var best_order := -1
	var best_ring := -1
	var best_flight := -1
	for i in rings.size():
		if not rings[i]["preset"] and rings[i]["order"] > best_order:
			best_order = rings[i]["order"]
			best_ring = i
			best_flight = -1
	for i in flights.size():
		if flights[i]["order"] > best_order:
			best_order = flights[i]["order"]
			best_flight = i
			best_ring = -1
	if best_order < 0:
		return
	if best_ring >= 0:
		rings.remove_at(best_ring)
	else:
		flights.remove_at(best_flight)
	beads_left += 1
	_event("undo", {"order": best_order})


func _throw(dir_index: int) -> void:
	var t := cast(dir_index)
	if not t["valid"]:
		_event("throw_invalid", {"reason": t["reason"]})
		return
	beads_left -= 1
	var travel: int = maxi(1, (t["dist"] + MazeTuning.BEAD_SPEED - 1) / MazeTuning.BEAD_SPEED)
	flights.append({
		"cell": t["cell"], "face": t["face"], "from": t["origin"], "to": t["hit"],
		"throw_tick": tick, "arrive_tick": tick + travel, "order": throw_count,
	})
	_event("throw", {"cell": t["cell"], "face": t["face"], "order": throw_count})
	throw_count += 1
	if clock_start < 0:
		clock_start = tick


func _land_flights() -> void:
	var remaining: Array[Dictionary] = []
	for f in flights:
		if f["arrive_tick"] > tick:
			remaining.append(f)
			continue
		var ring := {"cell": f["cell"], "face": f["face"], "preset": false, "order": f["order"], "cooldown": 0, "used": false}
		var at := rings.size()
		for i in rings.size():
			if rings[i]["order"] > f["order"]:
				at = i
				break
		rings.insert(at, ring)
		_event("ring", {"cell": f["cell"], "face": f["face"]})
	flights = remaining


func _horizontal(input: MazeInput) -> void:
	var move := input.move
	var target := move * MazeTuning.RUN_SPEED
	if lock_ticks > 0:
		lock_ticks -= 1
		return
	if grounded and ground == Ground.STEEP:
		var d := MazeSlope.downhill(ground_kind())
		var goal := d * MazeTuning.SLIDE_SPEED
		if move == d:
			goal = d * MazeTuning.SLIDE_FAST
		elif move == -d:
			goal = d * MazeTuning.SLIDE_SLOW
		vx = _approach(vx, goal, MazeTuning.SLIDE_ACCEL)
		if move != 0:
			facing = move
		return
	var same_dir := vx == 0 or (move != 0 and _sign(move) == _sign(vx))
	var slow := absi(vx) <= MazeTuning.RUN_SPEED
	if grounded:
		vx = _approach(vx, target, MazeTuning.GROUND_ACCEL if (same_dir and slow) else MazeTuning.GROUND_DECEL)
	elif move == 0:
		vx = _approach(vx, 0, MazeTuning.AIR_DRAG)
	elif same_dir:
		vx = _approach(vx, target, MazeTuning.AIR_ACCEL if slow else MazeTuning.AIR_DRAG)
	else:
		vx = _approach(vx, target, MazeTuning.AIR_TURN)
	if move != 0:
		facing = move


func _jump(input: MazeInput) -> void:
	# check the counters as left by the previous tick, then update them
	var can_jump := grounded or coyote > 0
	var wants_jump := input.jump_pressed or buffer > 0
	coyote = MazeTuning.COYOTE_TICKS if grounded else maxi(0, coyote - 1)
	buffer = MazeTuning.JUMP_BUFFER_TICKS if input.jump_pressed else maxi(0, buffer - 1)
	if can_jump and wants_jump:
		vy = -MazeTuning.JUMP_SPEED
		jumping = true
		launched = false
		buffer = 0
		coyote = 0
		grounded = false
		_event("jump")


func _gravity(input: MazeInput) -> void:
	var g := MazeTuning.GRAVITY_DOWN
	if jumping and input.jump_held and absi(vy) < MazeTuning.APEX_THRESHOLD:
		g = MazeTuning.APEX_GRAVITY
	elif vy < 0 and ((jumping and input.jump_held) or launched):
		g = MazeTuning.GRAVITY_UP
	vy = mini(vy + g, MazeTuning.MAX_FALL)


func _move(move: int) -> void:
	var start := ground
	var was_grounded := grounded
	var vy_before := vy
	var allow := MazeTuning.SLOPE_STEP if (start == Ground.GENTLE or start == Ground.STEEP) else 0
	var ox := px
	var oy := py
	_move_x(allow)
	if level.slope_count > 0 and _lift(allow):
		px = ox
		py = oy
		vx = 0
	var landed := _move_y()
	_compute_ground()
	if level.slope_count > 0 and was_grounded and vy >= 0:
		if ground == Ground.NONE:
			_snap(start, false)
		elif ground == Ground.FLAT and (start == Ground.STEEP or start == Ground.GENTLE):
			# leaving a slope past a block corner at the high end of the next one: follow the roof
			_snap(start, true)
	if grounded and vy > 0:
		vy = 0
		landed = true
	if landed:
		jumping = false
		launched = false
		if not was_grounded:
			_event("land")
			if ground == Ground.STEEP:
				# fall turns into a slide
				vx = (vx + MazeSlope.downhill(ground_kind()) * vy_before) / 2
	if ground == Ground.STEEP and start != Ground.STEEP:
		var d := MazeSlope.downhill(ground_kind())
		_event("slide", {"dir": d})
		if move == 0:
			facing = d
	if vy >= MazeTuning.APEX_THRESHOLD:
		jumping = false
	if vy >= 0:
		launched = false


## true when the lift put the box into a full block outside the step band
func _lift(allow: int) -> bool:
	var cx := _fdiv(px, T)
	var cy := _fdiv(py - 1, T)
	var kind := level.cell(cx, cy)
	var before := py
	if MazeSlope.is_slope(kind):
		py = mini(py, MazeSlope.surface(kind, cy, px - cx * T))
	elif allow > 0 and level.solid(cx, cy) and py - cy * T <= allow:
		# a roof standing on this block is the floor, not the block top
		var above := level.cell(cx, cy - 1)
		if MazeSlope.is_slope(above):
			py = mini(py, MazeSlope.surface(above, cy - 1, px - cx * T))
		else:
			py = cy * T
	if py == before:
		return false
	return not _box_free(px - HW, py - MazeTuning.PLAYER_H, px + HW, py - allow)


## keep the feet on the roof: nearest support below within SLOPE_SNAP + abs(vx)
func _snap(start: int, slope_only: bool) -> void:
	var reach := MazeTuning.SLOPE_SNAP + absi(vx)
	var floor_y := -1
	for cy in range(_fdiv(py + T - 1, T), _fdiv(py + reach, T) + 1):
		if _solid_in_cols(cy, px - HW, px + HW):
			floor_y = cy * T
			break
	var slope_y := -1
	var cx := _fdiv(px, T)
	for cy in range(_fdiv(py - 1, T), _fdiv(py + reach, T) + 1):
		var kind := level.cell(cx, cy)
		if MazeSlope.is_slope(kind):
			var sy := MazeSlope.surface(kind, cy, px - cx * T)
			if sy >= py and sy <= py + reach:
				slope_y = sy
				break
	if slope_only and slope_y < 0:
		return
	# on a roof the slope under the centre wins over a nearer block corner at the high end of the next slope
	var on_slope := slope_y >= 0 and (slope_only or start != Ground.FLAT or floor_y < 0 or slope_y <= floor_y)
	var support := slope_y if on_slope else floor_y
	if support < 0 or support > py + reach:
		return
	if not (start == Ground.GENTLE or start == Ground.STEEP or on_slope):
		return
	py = support
	vy = 0
	_compute_ground()


func _solid_in_rows(cx: int, top: int, bottom: int) -> bool:
	for cy in range(_fdiv(top, T), _fdiv(bottom - 1, T) + 1):
		if level.solid(cx, cy):
			return true
	return false


func _solid_in_cols(cy: int, left: int, right: int) -> bool:
	for cx in range(_fdiv(left, T), _fdiv(right - 1, T) + 1):
		if level.solid(cx, cy):
			return true
	return false


## full blocks in rows top..bottom of column cx, or a slope whose vertical high side faces the mover
func _blocks_x(cx: int, top: int, bottom: int, dir: int) -> bool:
	if _solid_in_rows(cx, top, bottom):
		return true
	if level.slope_count == 0:
		return false
	for cy in range(_fdiv(top, T), _fdiv(bottom - 1, T) + 1):
		var side := MazeSlope.high_side(level.cell(cx, cy))
		if side == (MazeLevel.Face.LEFT if dir > 0 else MazeLevel.Face.RIGHT):
			return true
	return false


func _move_x(allow: int) -> void:
	if vx == 0:
		return
	var top := py - MazeTuning.PLAYER_H
	var bottom := py - allow
	if vx > 0:
		for cx in range(_fdiv(px + HW - 1, T) + 1, _fdiv(px + vx + HW - 1, T) + 1):
			if _blocks_x(cx, top, bottom, 1):
				px = cx * T - HW
				vx = 0
				return
	else:
		for cx in range(_fdiv(px - HW, T) - 1, _fdiv(px + vx - HW, T) - 1, -1):
			if _blocks_x(cx, top, bottom, -1):
				px = (cx + 1) * T + HW
				vx = 0
				return
	px += vx


## true when the player lands
func _move_y() -> bool:
	if vy > 0:
		var floor_y := -1
		for cy in range(_fdiv(py - 1, T) + 1, _fdiv(py + vy - 1, T) + 1):
			if _solid_in_cols(cy, px - HW, px + HW):
				floor_y = cy * T
				break
		if level.slope_count > 0:
			var cx := _fdiv(px, T)
			for cy in range(_fdiv(py - 1, T), _fdiv(py + vy, T) + 1):
				var kind := level.cell(cx, cy)
				if MazeSlope.is_slope(kind):
					var sy := MazeSlope.surface(kind, cy, px - cx * T)
					if sy >= py and sy <= py + vy and (floor_y < 0 or sy < floor_y):
						floor_y = sy
					break
		if floor_y >= 0:
			py = floor_y
			vy = 0
			return true
		py += vy
	elif vy < 0:
		_move_up()
	return false


func _move_up() -> void:
	var new_py := py + vy
	var new_top := new_py - MazeTuning.PLAYER_H
	var left := px - HW
	var right := px + HW
	var c_lo := _fdiv(left, T)
	var c_hi := _fdiv(right - 1, T)
	var blocked_cols := {}
	var lowest_row := -1000000
	for cy in range(_fdiv(new_top, T), _fdiv(py - MazeTuning.PLAYER_H - 1, T) + 1):
		for cx in range(c_lo, c_hi + 1):
			if level.solid(cx, cy):
				blocked_cols[cx] = true
				lowest_row = maxi(lowest_row, cy)
	if blocked_cols.is_empty():
		py = new_py
		return
	# corner correction: head clips a corner by a few px, slide off it
	var shift := 0
	var left_overlap := (c_lo + 1) * T - left
	var right_overlap := right - c_hi * T
	if blocked_cols.size() == 1 and blocked_cols.has(c_lo) and left_overlap <= MazeTuning.CORNER_CORRECTION:
		shift = left_overlap
	elif blocked_cols.size() == 1 and blocked_cols.has(c_hi) and right_overlap <= MazeTuning.CORNER_CORRECTION:
		shift = -right_overlap
	if shift != 0 and _box_free(left + shift, new_top, right + shift, new_py):
		px += shift
		py = new_py
		return
	py = (lowest_row + 1) * T + MazeTuning.PLAYER_H
	vy = 0


static func ring_zone(cell: Vector2i, face: int) -> Rect2i:
	var d := MazeTuning.RING_DEPTH
	var i := MazeTuning.RING_INSET
	var x0 := cell.x * T
	var y0 := cell.y * T
	match face:
		MazeLevel.Face.UP:
			return Rect2i(x0 + i, y0 - d, T - 2 * i, d + 1)
		MazeLevel.Face.DOWN:
			return Rect2i(x0 + i, y0 + T - 1, T - 2 * i, d + 1)
		MazeLevel.Face.LEFT:
			return Rect2i(x0 - d, y0 + i, d + 1, T - 2 * i)
		_:
			return Rect2i(x0 + T - 1, y0 + i, d + 1, T - 2 * i)


func _launch_from_rings() -> void:
	var box := _box()
	for r in rings:
		if r["cooldown"] > 0 or not box.intersects(ring_zone(r["cell"], r["face"])):
			continue
		match r["face"]:
			MazeLevel.Face.UP:
				vy = -MazeTuning.FLOOR_LAUNCH
			MazeLevel.Face.DOWN:
				vy = MazeTuning.CEILING_LAUNCH
			MazeLevel.Face.LEFT:
				vx = -MazeTuning.WALL_LAUNCH_X
				vy = mini(vy, -MazeTuning.WALL_LAUNCH_LIFT)
				lock_ticks = MazeTuning.WALL_LOCK_TICKS
				facing = -1
			_:
				vx = MazeTuning.WALL_LAUNCH_X
				vy = mini(vy, -MazeTuning.WALL_LAUNCH_LIFT)
				lock_ticks = MazeTuning.WALL_LOCK_TICKS
				facing = 1
		launched = r["face"] != MazeLevel.Face.DOWN
		jumping = false
		coyote = 0
		buffer = 0
		grounded = false
		ground = Ground.NONE
		r["cooldown"] = MazeTuning.RING_COOLDOWN_TICKS
		var counted: bool = not r["preset"] and not r["used"]
		if counted:
			r["used"] = true
			rings_used += 1
		_event("launch", {"cell": r["cell"], "face": r["face"], "counted": counted})
		return


func _hazard_hit() -> bool:
	var inset := MazeTuning.HAZARD_INSET
	var box := Rect2i(px - HW + inset, py - MazeTuning.PLAYER_H + inset, MazeTuning.PLAYER_W - 2 * inset,
			MazeTuning.PLAYER_H - 2 * inset)
	if py - MazeTuning.PLAYER_H >= level.height * T:
		return true
	var si := MazeTuning.SPIKE_INSET
	for cy in range(_fdiv(box.position.y, T), _fdiv(box.end.y - 1, T) + 1):
		for cx in range(_fdiv(box.position.x, T), _fdiv(box.end.x - 1, T) + 1):
			if level.cell(cx, cy) == MazeLevel.Cell.SPIKE:
				var spike := Rect2i(cx * T + si, cy * T + T / 2, T - 2 * si, T / 2)
				if box.intersects(spike):
					return true
	return false


## pure query on the current state; the aim preview and the throw use it
func cast(dir_index: int) -> Dictionary:
	var o := Vector2i(px, py - MazeTuning.PLAYER_H / 2)
	var d := MazeAim.dir(dir_index)
	var result := {
		"valid": false, "reason": "none", "cell": Vector2i(), "face": MazeLevel.Face.UP,
		"origin": o, "hit": o, "dist": 0,
	}
	var prev_point := o
	var prev_cell := Vector2i(_fdiv(o.x, T), _fdiv(o.y, T))
	var steps := MazeTuning.CAST_RANGE / MazeTuning.CAST_STEP
	var hit_k := 0
	var hit_cell := Vector2i()
	for k in range(1, steps + 1):
		var travel := k * MazeTuning.CAST_STEP
		var p := Vector2i(o.x + d.x * travel / MazeAim.SCALE, o.y + d.y * travel / MazeAim.SCALE)
		var c := Vector2i(_fdiv(p.x, T), _fdiv(p.y, T))
		if level.solid(c.x, c.y):
			hit_k = k
			hit_cell = c
			break
		prev_point = p
		prev_cell = c
	result["hit"] = prev_point
	if hit_k == 0:
		if not alive():
			result["reason"] = "dead"
		elif beads_left == 0:
			result["reason"] = "no_beads"
		return result
	var face := _hit_face(prev_cell, hit_cell, d)
	var front := hit_cell + MazeLevel.FACE_STEP[face]
	result["cell"] = hit_cell
	result["face"] = face
	result["dist"] = hit_k * MazeTuning.CAST_STEP
	var reason := "ok"
	if level.cell(hit_cell.x, hit_cell.y) != MazeLevel.Cell.SOLID or level.solid(front.x, front.y):
		reason = "no_ring"
	elif level.cell(front.x, front.y) == MazeLevel.Cell.SPIKE:
		reason = "hazard"
	elif _face_taken(hit_cell, face):
		reason = "taken"
	if not alive():
		reason = "dead"
	elif beads_left == 0:
		reason = "no_beads"
	result["reason"] = reason
	result["valid"] = reason == "ok"
	return result


static func _hit_face(prev_cell: Vector2i, hit_cell: Vector2i, d: Vector2i) -> int:
	var dx := hit_cell.x - prev_cell.x
	var dy := hit_cell.y - prev_cell.y
	var vertical := dx == 0 or (dy != 0 and absi(d.y) >= absi(d.x))
	if vertical:
		return MazeLevel.Face.UP if dy > 0 else MazeLevel.Face.DOWN
	return MazeLevel.Face.LEFT if dx > 0 else MazeLevel.Face.RIGHT


func _face_taken(c: Vector2i, face: int) -> bool:
	for r in rings:
		if r["cell"] == c and r["face"] == face:
			return true
	for f in flights:
		if f["cell"] == c and f["face"] == face:
			return true
	return false
