extends RefCounted
## S1: every integer tuning value equals the conversion of its readable value.

const SPEEDS := [
	"RUN_SPEED",
	"JUMP_SPEED",
	"APEX_THRESHOLD",
	"MAX_FALL",
	"FLOOR_LAUNCH",
	"WALL_LAUNCH_X",
	"WALL_LAUNCH_LIFT",
	"CEILING_LAUNCH",
	"BEAD_SPEED",
	"SLIDE_SPEED",
	"SLIDE_FAST",
	"SLIDE_SLOW"
]
const ACCELS := [
	"GROUND_ACCEL", "GROUND_DECEL", "AIR_ACCEL", "AIR_TURN", "AIR_DRAG", "GRAVITY_UP", "GRAVITY_DOWN", "APEX_GRAVITY",
	"SLIDE_ACCEL"
]
const DISTANCES := [
	"CORNER_CORRECTION",
	"CAST_RANGE",
	"CAST_STEP",
	"PLAYER_W",
	"PLAYER_H",
	"HAZARD_INSET",
	"RING_DEPTH",
	"RING_INSET",
	"SPIKE_INSET",
	"SLOPE_STEP",
	"SLOPE_SNAP"
]
const TIMES := {
	"COYOTE_TICKS": "COYOTE_S",
	"JUMP_BUFFER_TICKS": "JUMP_BUFFER_S",
	"WALL_LOCK_TICKS": "WALL_LOCK_S",
	"RING_COOLDOWN_TICKS": "RING_COOLDOWN_S",
	"DEATH_TICKS": "DEATH_S"
}


func run(check: Callable, _node: Node) -> void:
	var c: Dictionary = (load("res://sim/tuning.gd") as GDScript).get_script_constant_map()
	for n in SPEEDS:
		check.call(c[n] == roundi(c[n + "_PX"] * 1000.0 / 60.0), "%s equals roundi(px/s * 1000 / 60)" % n)
	for n in ACCELS:
		check.call(c[n] == roundi(c[n + "_PX"] * 1000.0 / 3600.0), "%s equals roundi(px/s2 * 1000 / 3600)" % n)
	for n in DISTANCES:
		check.call(c[n] == roundi(c[n + "_PX"] * 1000.0), "%s equals px * 1000" % n)
	for n in TIMES:
		check.call(c[n] == roundi(c[TIMES[n]] * 60.0), "%s equals roundi(seconds * 60)" % n)
	check.call(c["TILE"] == 40 * c["UNITS_PER_PX"], "a tile is 40 px")
	var bad := []
	for key in c:
		if key != "UNITS_PER_PX" and (key.ends_with("_PX") or key.ends_with("_S")):
			var base: String = key.trim_suffix("_PX").trim_suffix("_S")
			if not (c.has(base) or c.has(base + "_TICKS")):
				bad.append(key)
	check.call(bad.is_empty(), "every readable tuning value has an integer twin (%s)" % str(bad))
	_solver(check, c)


## the native solver keeps its own copy of the integer values (design 23.10.4)
func _solver(check: Callable, c: Dictionary) -> void:
	var f := FileAccess.open("res://tools/solver/maze_solver.cpp", FileAccess.READ)
	check.call(f != null, "the solver source is in the project")
	if f == null:
		return
	var re := RegEx.create_from_string("constexpr num ([A-Z_]+) = ([0-9]+);")
	var seen := 0
	var bad := []
	for m in re.search_all(f.get_as_text()):
		var name := m.get_string(1)
		if c.has(name):
			seen += 1
			if c[name] != int(m.get_string(2)):
				bad.append(name)
	check.call(bad.is_empty(), "the solver's tuning values equal MazeTuning (%s)" % str(bad))
	check.call(seen >= 35, "the solver copies the tuning values (%d found)" % seen)
