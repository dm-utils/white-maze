extends RefCounted
## F1-F2: level speed in the game screen (design 20.6); F4-F8 follow with the Lilith pass.

const H := preload("res://tests/helpers.gd")
const C := preload("res://tests/controls_tests.gd")
const PROFILE := "user://white_maze_test_feel.json"
const DT := 1.0 / 60.0

var _check: Callable
var _node: Node


func run(check: Callable, node: Node) -> void:
	_check = check
	_node = node
	_level_speed()
	_args()
	_game_speed()
	_clean()


func _clean() -> void:
	for p in [PROFILE, PROFILE + ".tmp"]:
		DirAccess.remove_absolute(p)


func _main(extra: Array = []) -> MazeMain:
	WhiteText.lang = "nl"
	var m: MazeMain = load("res://ui/main.tscn").instantiate()
	m.use_cmdline = false
	m.args = PackedStringArray(["--profile=" + PROFILE, "--level=l001"]) + PackedStringArray(extra)
	_node.add_child(m)
	m.game.set_process(false)
	m.game.rig.skip_intro()
	return m


func _close(m: MazeMain) -> void:
	_node.remove_child(m)
	m.free()


func _level_speed() -> void:
	var want := [0.80, 0.82, 0.84, 0.86, 0.88, 0.90, 0.92, 0.94, 0.96]
	var ok := true
	for i in want.size():
		ok = ok and is_equal_approx(MazeGame.level_speed(i + 1), want[i])
	_check.call(ok, "F1 level_speed gives 0.80 to 0.96 for the levels 1 to 9")
	_check.call(
		is_equal_approx(MazeGame.level_speed(10), 0.96) and is_equal_approx(MazeGame.level_speed(12), 0.96),
		"F1 level_speed stays at 0.96 from level 10"
	)
	_check.call(
		is_equal_approx(MazeGame.level_speed(0), 0.80) and is_equal_approx(MazeGame.level_speed(-3), 0.80),
		"F1 level_speed never goes below the first level"
	)


func _args() -> void:
	_check.call(MazeMain.parse_args(PackedStringArray(["--speed=110"]))["speed"] == 110, "F1 --speed=110 is taken")
	_check.call(MazeMain.parse_args(PackedStringArray(["--speed=20"]))["speed"] == 0, "F1 --speed=20 is ignored")
	_check.call(MazeMain.parse_args(PackedStringArray(["--speed=abc"]))["speed"] == 0, "F1 --speed=abc is ignored")
	_check.call(MazeMain.parse_args(PackedStringArray([]))["speed"] == 0, "F1 no --speed uses the table")
	_check.call(
		MazeMain.query_args("?speed=90") == PackedStringArray(["--speed=90"]), "F1 the web query key speed is passed on"
	)
	var m := _main(["--speed=110"])
	_check.call(is_equal_approx(m.game.speed, 1.1), "F1 --speed=110 gives 1.1 on l001")
	_close(m)
	m = _main()
	_check.call(is_equal_approx(m.game.speed, 0.8), "F1 l001 runs at the table speed 0.80")
	_close(m)


func _walk(g: MazeGame, frames: int) -> void:
	g.controls.handle_event(C.key(KEY_D))
	for i in frames:
		g.advance(DT)


func _game_speed() -> void:
	var m := _main()
	var g := m.game
	_walk(g, 300)
	_check.call(absi(g.sim.tick - 240) <= 1, "F2 300 frames at the table speed give 240 ticks (%d)" % g.sim.tick)
	var plain := MazeSim.new(g.level)
	for i in g.sim.tick:
		plain.step(H.inp(1))
	_check.call(plain.snapshot() == g.sim.snapshot(), "F2 the game at 0.80 plays the same simulation as a plain run")
	_check.call(g.world.modulate == Color.WHITE, "F2 a level at 0.80 is not drawn dimmed")
	_close(m)
	m = _main(["--speed=100"])
	_walk(m.game, 300)
	_check.call(m.game.sim.tick == 300, "F2 speed 100 gives 300 ticks (%d)" % m.game.sim.tick)
	_close(m)
	m = _main()
	g = m.game
	g.controls.handle_event(C.key(KEY_J))
	for i in 6:
		g.advance(DT)
	_check.call(g.controls.aiming() and g.world.modulate != Color.WHITE, "F2 aiming dims the world")
	var t0 := g.sim.tick
	for i in 60:
		g.advance(DT)
	_check.call(absi(g.sim.tick - t0 - 12) <= 1, "F2 aiming on l001 gives 12 ticks per second (%d)" % (g.sim.tick - t0))
	_close(m)
