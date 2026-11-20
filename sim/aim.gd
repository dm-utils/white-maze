class_name MazeAim
extends RefCounted
## 144 throw directions, i * 2.5 degrees counter-clockwise on screen from pointing right (36 up, 72 left, 108 down).
## Vectors scaled by 10000, y down. Literal table: the sim never calls cos/sin.

const STEPS := 144
const SCALE := 10000
const DIRS: Array[Vector2i] = [
	Vector2i(10000, 0), Vector2i(9990, -436), Vector2i(9962, -872), Vector2i(9914, -1305),
	Vector2i(9848, -1736), Vector2i(9763, -2164), Vector2i(9659, -2588), Vector2i(9537, -3007),
	Vector2i(9397, -3420), Vector2i(9239, -3827), Vector2i(9063, -4226), Vector2i(8870, -4617),
	Vector2i(8660, -5000), Vector2i(8434, -5373), Vector2i(8192, -5736), Vector2i(7934, -6088),
	Vector2i(7660, -6428), Vector2i(7373, -6756), Vector2i(7071, -7071), Vector2i(6756, -7373),
	Vector2i(6428, -7660), Vector2i(6088, -7934), Vector2i(5736, -8192), Vector2i(5373, -8434),
	Vector2i(5000, -8660), Vector2i(4617, -8870), Vector2i(4226, -9063), Vector2i(3827, -9239),
	Vector2i(3420, -9397), Vector2i(3007, -9537), Vector2i(2588, -9659), Vector2i(2164, -9763),
	Vector2i(1736, -9848), Vector2i(1305, -9914), Vector2i(872, -9962), Vector2i(436, -9990),
	Vector2i(0, -10000), Vector2i(-436, -9990), Vector2i(-872, -9962), Vector2i(-1305, -9914),
	Vector2i(-1736, -9848), Vector2i(-2164, -9763), Vector2i(-2588, -9659), Vector2i(-3007, -9537),
	Vector2i(-3420, -9397), Vector2i(-3827, -9239), Vector2i(-4226, -9063), Vector2i(-4617, -8870),
	Vector2i(-5000, -8660), Vector2i(-5373, -8434), Vector2i(-5736, -8192), Vector2i(-6088, -7934),
	Vector2i(-6428, -7660), Vector2i(-6756, -7373), Vector2i(-7071, -7071), Vector2i(-7373, -6756),
	Vector2i(-7660, -6428), Vector2i(-7934, -6088), Vector2i(-8192, -5736), Vector2i(-8434, -5373),
	Vector2i(-8660, -5000), Vector2i(-8870, -4617), Vector2i(-9063, -4226), Vector2i(-9239, -3827),
	Vector2i(-9397, -3420), Vector2i(-9537, -3007), Vector2i(-9659, -2588), Vector2i(-9763, -2164),
	Vector2i(-9848, -1736), Vector2i(-9914, -1305), Vector2i(-9962, -872), Vector2i(-9990, -436),
	Vector2i(-10000, 0), Vector2i(-9990, 436), Vector2i(-9962, 872), Vector2i(-9914, 1305),
	Vector2i(-9848, 1736), Vector2i(-9763, 2164), Vector2i(-9659, 2588), Vector2i(-9537, 3007),
	Vector2i(-9397, 3420), Vector2i(-9239, 3827), Vector2i(-9063, 4226), Vector2i(-8870, 4617),
	Vector2i(-8660, 5000), Vector2i(-8434, 5373), Vector2i(-8192, 5736), Vector2i(-7934, 6088),
	Vector2i(-7660, 6428), Vector2i(-7373, 6756), Vector2i(-7071, 7071), Vector2i(-6756, 7373),
	Vector2i(-6428, 7660), Vector2i(-6088, 7934), Vector2i(-5736, 8192), Vector2i(-5373, 8434),
	Vector2i(-5000, 8660), Vector2i(-4617, 8870), Vector2i(-4226, 9063), Vector2i(-3827, 9239),
	Vector2i(-3420, 9397), Vector2i(-3007, 9537), Vector2i(-2588, 9659), Vector2i(-2164, 9763),
	Vector2i(-1736, 9848), Vector2i(-1305, 9914), Vector2i(-872, 9962), Vector2i(-436, 9990),
	Vector2i(0, 10000), Vector2i(436, 9990), Vector2i(872, 9962), Vector2i(1305, 9914),
	Vector2i(1736, 9848), Vector2i(2164, 9763), Vector2i(2588, 9659), Vector2i(3007, 9537),
	Vector2i(3420, 9397), Vector2i(3827, 9239), Vector2i(4226, 9063), Vector2i(4617, 8870),
	Vector2i(5000, 8660), Vector2i(5373, 8434), Vector2i(5736, 8192), Vector2i(6088, 7934),
	Vector2i(6428, 7660), Vector2i(6756, 7373), Vector2i(7071, 7071), Vector2i(7373, 6756),
	Vector2i(7660, 6428), Vector2i(7934, 6088), Vector2i(8192, 5736), Vector2i(8434, 5373),
	Vector2i(8660, 5000), Vector2i(8870, 4617), Vector2i(9063, 4226), Vector2i(9239, 3827),
	Vector2i(9397, 3420), Vector2i(9537, 3007), Vector2i(9659, 2588), Vector2i(9763, 2164),
	Vector2i(9848, 1736), Vector2i(9914, 1305), Vector2i(9962, 872), Vector2i(9990, 436),
]


static func dir(i: int) -> Vector2i:
	return DIRS[posmod(i, STEPS)]


## UI side only (mouse, touch); -1 for a zero vector
static func index_from_vector(v: Vector2) -> int:
	if v == Vector2.ZERO:
		return -1
	return posmod(roundi(rad_to_deg(atan2(-v.y, v.x)) / 2.5), STEPS)


## elevation -6..6 in 15 degree steps
static func keyboard_index(facing: int, elevation: int) -> int:
	if facing >= 0:
		return posmod(elevation * 6, STEPS)
	return posmod(72 - elevation * 6, STEPS)
