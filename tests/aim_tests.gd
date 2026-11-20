extends RefCounted
## S18: aim table and conversions.


func run(check: Callable, _node: Node) -> void:
	check.call(MazeAim.DIRS.size() == 144, "144 aim directions")
	check.call(MazeAim.dir(0) == Vector2i(10000, 0), "index 0 points right")
	check.call(MazeAim.dir(36) == Vector2i(0, -10000), "index 36 points up")
	check.call(MazeAim.dir(72) == Vector2i(-10000, 0), "index 72 points left")
	check.call(MazeAim.dir(108) == Vector2i(0, 10000), "index 108 points down")
	check.call(MazeAim.dir(144) == MazeAim.dir(0) and MazeAim.dir(-1) == MazeAim.dir(143), "indices wrap")
	var worst := 0
	for i in 144:
		var a := deg_to_rad(i * 2.5)
		var d := MazeAim.dir(i)
		worst = maxi(worst, maxi(absi(d.x - roundi(cos(a) * 10000)), absi(d.y + roundi(sin(a) * 10000))))
	check.call(worst <= 1, "every entry within 1 of cos/sin (worst %d)" % worst)
	check.call(MazeAim.keyboard_index(1, 3) == 18, "keyboard facing right, 45 degrees up: 18")
	check.call(MazeAim.keyboard_index(-1, 3) == 54, "keyboard facing left, 45 degrees up: 54")
	check.call(MazeAim.keyboard_index(1, 0) == 0 and MazeAim.keyboard_index(-1, 0) == 72, "keyboard level aim")
	check.call(MazeAim.keyboard_index(1, -6) == 108 and MazeAim.keyboard_index(1, 6) == 36, "keyboard extremes right")
	check.call(MazeAim.keyboard_index(-1, 6) == 36 and MazeAim.keyboard_index(-1, -6) == 108, "keyboard extremes left")
	check.call(MazeAim.index_from_vector(Vector2(1, 0)) == 0, "vector right: 0")
	check.call(MazeAim.index_from_vector(Vector2(0, -1)) == 36, "vector up: 36")
	check.call(MazeAim.index_from_vector(Vector2(-1, 0)) == 72, "vector left: 72")
	check.call(MazeAim.index_from_vector(Vector2(0, 1)) == 108, "vector down: 108")
	check.call(MazeAim.index_from_vector(Vector2(1, -1)) == 18, "vector up-right: 18")
	check.call(MazeAim.index_from_vector(Vector2(1, 1)) == 126, "vector down-right: 126")
	check.call(MazeAim.index_from_vector(Vector2.ZERO) == -1, "zero vector: -1")
	check.call(MazeAim.index_from_vector(Vector2(10, -0.01)) == 0, "slightly off right still rounds to 0")
