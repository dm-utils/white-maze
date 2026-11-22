class_name MazeLilith
extends RefCounted
## Lilith, the player figure: pose choice and shape list, pure data (design 18.6, ADR 0010).
## Local frame: origin at the feet centre, y down, facing right; the view mirrors for facing left.

enum Body { IDLE, RUN, JUMP, LAUNCH, FALL, DEAD }
enum Arm { REST, AIM, THROW, UP }

const RUN_MIN_VX := 500 # units per tick
const STRIDE_PX := 48.0
const LAND_TICKS := 6
const THROW_TICKS := 10
const DEAD_TILT_TICKS := 12
const DEAD_TILT_MAX := 70.0 # degrees
const LAUNCH_TILT_MAX := 8.0 # degrees
const HIP_LIFT := Vector2(0.0, -2.5)
const TAIL_BOUNDS := Rect2(-19.0, -34.0, 34.0, 34.0)

const SKIN := Color("#D9A07A")
const HAIR := Color("#C4701A")
const EYE := Color("#1E1A18")
const HEADBAND := Color("#E0306E")
const JACKET := Color("#2F7F86")
const JACKET_SHADOW := Color("#24646A")
const STRAP := Color("#3A2A1E")
const SLOT_EMPTY := Color("#1E1612")
const SATCHEL := Color("#6B4A2B")
const TROUSERS := Color("#5A5F40")
const TROUSERS_FAR := Color("#474B32")
const BOOTS := Color("#2B2420")
const OUTLINE := Color("#120E10", 0.85)
const BEAD := Color("#FFFFFF")

const OUTLINE_LINE := 3.0
const OUTLINE_CIRCLE := 1.5
const HEAD_C := Vector2(1.0, -25.5)
const HEAD_R := 6.0
const KNOT := Vector2(-5.0, -28.5)
const SHOULDER := Vector2(2.0, -19.0)
const SHOULDER_FAR := Vector2(-2.0, -19.0)
const ARM_LEN := 7.0
const TILT_PIVOT := Vector2(0.0, -16.0)
const SLOT_MAX := 4
const TAIL_LENS := [7.0, 6.0]
const TAIL_FLUTTER := 1.2
const TAIL_SPEED_FULL := 300.0
const TAIL_MIN_SPEED := 50.0


## pose of the legs and body from sim state
static func body_pose(alive: bool, grounded: bool, vx: int, vy: int, launched: bool) -> int:
	if not alive:
		return Body.DEAD
	if not grounded:
		if vy < 0:
			return Body.LAUNCH if launched else Body.JUMP
		return Body.FALL
	if absi(vx) >= RUN_MIN_VX:
		return Body.RUN
	return Body.IDLE


static func arm_mode(aiming: bool, ticks_since_throw: int, body: int) -> int:
	if body == Body.DEAD:
		return Arm.REST
	if aiming:
		return Arm.AIM
	if ticks_since_throw < THROW_TICKS:
		return Arm.THROW
	if body == Body.LAUNCH:
		return Arm.UP
	return Arm.REST


## joints of the figure for a pose, local frame; shapes() builds the figure from these. Keys of p as for shapes()
static func rig(p: Dictionary) -> Dictionary:
	var body: int = p.get("body", Body.IDLE)
	var arm: int = p.get("arm", Arm.REST)
	var phase: float = p.get("phase", 0.0)
	var tick: float = p.get("tick", 0.0)
	var vel: Vector2 = p.get("vel", Vector2.ZERO)
	# upper body offset, always downwards so the head stays under y = -32
	var drop := 0.0
	var tilt := 0.0
	match body:
		Body.IDLE:
			drop = 0.3 + 0.3 * sin(tick * TAU / 120.0)
		Body.RUN:
			drop = 0.5 - 0.5 * cos(phase * TAU * 2.0)
		Body.LAUNCH:
			tilt = deg_to_rad(clampf(vel.x / TAIL_SPEED_FULL, -1.0, 1.0) * LAUNCH_TILT_MAX)
	var legs := _legs(body, phase)
	return {
		"near_foot": legs["near_foot"], "far_foot": legs["far_foot"],
		"hand_near": _hand(arm, body, phase, p, SHOULDER), "hand_far": _hand_far(arm, body, phase),
		"drop": drop, "tilt": tilt, "hair_up": 1.0 if body == Body.FALL else 0.0,
	}


## per key linear mix of two rigs, k in 0..1
static func blend_rig(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key: String in a:
		out[key] = lerpf(a[key], b[key], k) if a[key] is float else (a[key] as Vector2).lerp(b[key], k)
	return out


## ordered shape list, outlines first. Keys of p: body, arm, phase, tick (float, render time), aim_angle (radians,
## local frame), throw_k, squash_k, dead_k, vel (px/s, local frame), slots, filled, fade (optional, alpha factor),
## rig (optional, blended joints; default rig(p))
static func shapes(p: Dictionary) -> Array[Dictionary]:
	var body: int = p.get("body", Body.IDLE)
	var arm: int = p.get("arm", Arm.REST)
	var tick: float = p.get("tick", 0.0)
	var vel: Vector2 = p.get("vel", Vector2.ZERO)
	var fade: float = p.get("fade", 1.0)
	var slots: int = clampi(p.get("slots", 0), 0, SLOT_MAX)
	var filled: int = clampi(p.get("filled", 0), 0, slots)

	var r: Dictionary = p["rig"] if p.has("rig") else rig(p)
	var drop: float = r["drop"]
	var tilt: float = r["tilt"]
	var up_off := Vector2(0.0, drop)

	var near_foot: Vector2 = r["near_foot"]
	var far_foot: Vector2 = r["far_foot"]
	var hand_near: Vector2 = r["hand_near"]
	var hand_far: Vector2 = r["hand_far"]

	var out: Array[Dictionary] = []
	# tails first: behind the head
	var tails := _tails(vel, tick, KNOT + up_off)
	for t in tails:
		out.append(_line(t, 2.2, HEADBAND, "tail"))
	# far limbs
	out.append(_line(PackedVector2Array([SHOULDER_FAR + up_off, hand_far]), 3.0, JACKET_SHADOW, "arm"))
	out.append(_circle(hand_far, 1.4, SKIN, "arm"))
	out.append(_line(PackedVector2Array([Vector2(-3.5, -11.5), far_foot + HIP_LIFT]), 4.0, TROUSERS_FAR, "leg"))
	out.append(_poly(_boot(far_foot), BOOTS, "leg"))
	out.append(_line(PackedVector2Array([Vector2(3.5, -11.5), near_foot + HIP_LIFT]), 4.0, TROUSERS, "leg"))
	out.append(_poly(_boot(near_foot), BOOTS, "leg"))
	# torso block
	var upper: Array[Dictionary] = []
	upper.append(_poly(_rrect(-12.0, -16.0, -6.0, -9.0, 1.5), SATCHEL, "body"))
	upper.append(_poly(_rrect(-8.0, -21.0, 8.0, -11.5, 3.0), JACKET, "body"))
	upper.append(_poly(_rrect(-8.0, -14.5, 8.0, -11.5, 1.4), JACKET_SHADOW, "body"))
	upper.append(_line(PackedVector2Array([Vector2(-8.0, -12.5), Vector2(8.0, -12.5)]), 1.8, STRAP, "body"))
	var s_a := Vector2(-6.0, -21.0)
	var s_b := Vector2(6.0, -12.5)
	upper.append(_line(PackedVector2Array([s_a, s_b]), 2.4, STRAP, "body"))
	for i in slots:
		var c := s_a.lerp(s_b, (i + 0.5) / SLOT_MAX)
		upper.append(_circle(c, 1.8, BEAD if i < filled else SLOT_EMPTY, "slot"))
	# near arm over the torso
	upper.append(_line(PackedVector2Array([SHOULDER, hand_near]), 3.0, JACKET, "arm"))
	upper.append(_circle(hand_near, 1.4, SKIN, "arm"))
	if arm == Arm.AIM:
		var d := Vector2.from_angle(float(p.get("aim_angle", 0.0)))
		var bp := hand_near + d * 1.5
		upper.append(_circle(bp, 3.5, Color(BEAD, 0.25), "bead"))
		upper.append(_circle(bp, 1.9, BEAD, "bead"))
	# head
	upper.append(_circle(HEAD_C, HEAD_R, SKIN, "head"))
	upper.append(_poly(_hair(float(r["hair_up"])), HAIR, "hair"))
	upper.append(_circle(Vector2(4.2, -25.5), 0.9, EYE, "head"))
	upper.append(_line(PackedVector2Array([Vector2(-5.0, -28.5), Vector2(7.0, -28.5)]), 2.0, HEADBAND, "band"))
	for s in upper:
		_shift(s, up_off)
		_rotate(s, tilt, TILT_PIVOT)
	for s in upper:
		out.append(s)

	# global transforms: dead tilt about the feet, squash about the feet
	if body == Body.DEAD:
		var k := minf(1.0, float(p.get("dead_k", 0.0)) * 30.0 / DEAD_TILT_TICKS)
		var a := deg_to_rad(-DEAD_TILT_MAX) * k
		for s in out:
			_rotate(s, a, Vector2.ZERO)
	var sq: float = p.get("squash_k", 0.0)
	if sq > 0.0:
		var scale := Vector2(1.0 + 0.06 * sq, 1.0 - 0.12 * sq)
		for s in out:
			_scale(s, scale)
	# tails stay inside their own bounds
	for s in out:
		if s["part"] == "tail":
			var pts: PackedVector2Array = s["pts"]
			for i in pts.size():
				pts[i] = _clamp(pts[i], TAIL_BOUNDS.grow(-float(s["w"]) / 2.0))
			s["pts"] = pts

	var result: Array[Dictionary] = []
	for s in out:
		if s["part"] != "bead" and s["part"] != "slot":
			result.append(_outline(s))
	for s in out:
		result.append(s)
	if fade < 1.0:
		for s in result:
			var col: Color = s["color"]
			col.a *= fade
			s["color"] = col
	return result


static func _legs(body: int, phase: float) -> Dictionary:
	var near := Vector2(4.0, -2.5)
	var far := Vector2(-4.0, -2.5)
	match body:
		Body.RUN:
			near = _stride(3.5, phase)
			far = _stride(-3.5, phase + 0.5)
		Body.JUMP:
			near = Vector2(7.0, -8.0)
			far = Vector2(-3.0, -3.5)
		Body.LAUNCH:
			near = Vector2(4.0, -6.0)
			far = Vector2(-3.0, -5.0)
		Body.FALL:
			near = Vector2(8.0, -2.5)
			far = Vector2(-8.0, -2.5)
		Body.DEAD:
			near = Vector2(5.0, -2.5)
			far = Vector2(-5.0, -2.5)
	return {"near_foot": near, "far_foot": far}


static func _stride(hip_x: float, phase: float) -> Vector2:
	var a := fposmod(phase, 1.0) * TAU
	var lift := 3.0 * maxf(0.0, cos(a))
	return Vector2(hip_x + 6.0 * sin(a), -2.5 - lift)


static func _hand(arm: int, body: int, phase: float, p: Dictionary, shoulder: Vector2) -> Vector2:
	var sh := shoulder
	match arm:
		Arm.AIM:
			return sh + Vector2.from_angle(float(p.get("aim_angle", 0.0))) * ARM_LEN
		Arm.THROW:
			var k := clampf(float(p.get("throw_k", 0.0)), 0.0, 1.0)
			var a := float(p.get("aim_angle", 0.0)) + 1.8 * (1.0 - k)
			return sh + Vector2.from_angle(a) * ARM_LEN
		Arm.UP:
			return Vector2(8.5, -24.0)
	match body:
		Body.RUN:
			return sh + Vector2(-5.0 * sin(phase * TAU), ARM_LEN)
		Body.JUMP:
			return sh + Vector2(-3.0, 6.5)
		Body.FALL:
			return sh + Vector2(6.5, 2.5)
		Body.DEAD:
			return sh + Vector2(0.0, ARM_LEN)
	return sh + Vector2(0.5, ARM_LEN)


static func _hand_far(arm: int, body: int, phase: float) -> Vector2:
	var sh := SHOULDER_FAR
	if arm == Arm.UP:
		return Vector2(-6.0, -25.0)
	match body:
		Body.RUN:
			return sh + Vector2(5.0 * sin(phase * TAU), ARM_LEN) + Vector2(0.0, 0.5)
		Body.JUMP:
			return sh + Vector2(-3.5, 6.0)
		Body.FALL:
			return sh + Vector2(-6.5, 2.5)
	return sh + Vector2(-0.5, ARM_LEN)


static func _hair(hair_up: float) -> PackedVector2Array:
	var back := Vector2(-6.8, -27.0).lerp(Vector2(-8.0, -30.5), hair_up)
	return PackedVector2Array(
		[
			Vector2(-6.5, -22.0), back, Vector2(-4.5, -30.6), Vector2(0.0, -31.8), Vector2(4.5, -31.0),
			Vector2(7.0, -28.0), Vector2(3.0, -28.6), Vector2(-1.0, -27.0), Vector2(-3.0, -22.0),
		]
	)


## three points per tail from the knot, opposite to the velocity (down and back at rest)
static func _tails(vel: Vector2, tick: float, knot: Vector2) -> Array[PackedVector2Array]:
	var speed := vel.length()
	var dir := Vector2(-0.6, 0.8).normalized()
	if speed > TAIL_MIN_SPEED:
		dir = -vel / speed
	var k := minf(1.0, speed / TAIL_SPEED_FULL)
	var tails: Array[PackedVector2Array] = []
	for n in 2:
		var d := dir.rotated(0.35 * n)
		var side := Vector2(-d.y, d.x)
		var len: float = TAIL_LENS[n] * lerpf(0.7, 1.0, k)
		var pts := PackedVector2Array([knot])
		for i in 3:
			var f := tick * 0.35 + i + n
			pts.append(knot + d * len * (i + 1) / 3.0 + side * TAIL_FLUTTER * k * sin(f))
		tails.append(pts)
	return tails


static func _boot(c: Vector2) -> PackedVector2Array:
	return _rrect(c.x - 3.5, c.y - 2.5, c.x + 3.5, c.y + 2.5, 1.5)


static func _rrect(x0: float, y0: float, x1: float, y1: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(x1 - r, y0 + r), -PI / 2.0], [Vector2(x1 - r, y1 - r), 0.0],
		[Vector2(x0 + r, y1 - r), PI / 2.0], [Vector2(x0 + r, y0 + r), PI],
	]
	for c in corners:
		for i in 4:
			var a: float = c[1] + (PI / 2.0) * i / 3.0
			pts.append(c[0] + Vector2.from_angle(a) * r)
	return pts


static func _circle(c: Vector2, r: float, color: Color, part: String) -> Dictionary:
	return {"type": "circle", "part": part, "c": c, "r": r, "pts": PackedVector2Array(), "w": 0.0, "color": color}


static func _line(pts: PackedVector2Array, w: float, color: Color, part: String) -> Dictionary:
	return {"type": "line", "part": part, "c": Vector2.ZERO, "r": 0.0, "pts": pts, "w": w, "color": color}


static func _poly(pts: PackedVector2Array, color: Color, part: String) -> Dictionary:
	return {"type": "poly", "part": part, "c": Vector2.ZERO, "r": 0.0, "pts": pts, "w": 0.0, "color": color}


## dark twin of a shape: lines wider, circles bigger, polygons as closed polylines
static func _outline(s: Dictionary) -> Dictionary:
	var o: Dictionary = s.duplicate(true)
	o["color"] = OUTLINE
	match s["type"]:
		"circle":
			o["r"] = float(s["r"]) + OUTLINE_CIRCLE
		"line":
			o["w"] = float(s["w"]) + OUTLINE_LINE
		"poly":
			var pts: PackedVector2Array = s["pts"]
			pts.append(pts[0])
			o["type"] = "loop"
			o["pts"] = pts
			o["w"] = OUTLINE_LINE
	o["part"] = "outline"
	return o


static func _map(s: Dictionary, f: Callable) -> void:
	s["c"] = f.call(s["c"])
	var pts: PackedVector2Array = s["pts"]
	for i in pts.size():
		pts[i] = f.call(pts[i])
	s["pts"] = pts


static func _shift(s: Dictionary, off: Vector2) -> void:
	_map(s, func(v: Vector2) -> Vector2: return v + off)


static func _rotate(s: Dictionary, angle: float, pivot: Vector2) -> void:
	if angle != 0.0:
		_map(s, func(v: Vector2) -> Vector2: return pivot + (v - pivot).rotated(angle))


static func _scale(s: Dictionary, k: Vector2) -> void:
	_map(s, func(v: Vector2) -> Vector2: return v * k)


static func _clamp(v: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(v.x, r.position.x, r.end.x), clampf(v.y, r.position.y, r.end.y))
