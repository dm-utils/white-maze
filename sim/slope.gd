class_name MazeSlope
extends RefCounted
## Geometry of slope tiles in units; integers only. Used by the simulation, the cast, the tools and the view.

const T := MazeTuning.TILE
const FIRST := 4 # MazeLevel.Cell.STEEP_R
const LAST := 9 # MazeLevel.Cell.GENTLE_L_LO


static func is_slope(kind: int) -> bool:
	return kind >= FIRST and kind <= LAST


static func steep(kind: int) -> bool:
	return kind == MazeLevel.Cell.STEEP_R or kind == MazeLevel.Cell.STEEP_L


## -1: the surface falls to the left (/ r R), 1: to the right (\ L l)
static func downhill(kind: int) -> int:
	match kind:
		MazeLevel.Cell.STEEP_R, MazeLevel.Cell.GENTLE_R_LO, MazeLevel.Cell.GENTLE_R_HI:
			return -1
	return 1


## Face.RIGHT for / and R, Face.LEFT for \ and L, -1 for the low halves r and l
static func high_side(kind: int) -> int:
	match kind:
		MazeLevel.Cell.STEEP_R, MazeLevel.Cell.GENTLE_R_HI:
			return MazeLevel.Face.RIGHT
		MazeLevel.Cell.STEEP_L, MazeLevel.Cell.GENTLE_L_HI:
			return MazeLevel.Face.LEFT
	return -1


## y of the surface at local x lx (0..T) in row cy
static func surface(kind: int, cy: int, lx: int) -> int:
	var b := cy * T
	match kind:
		MazeLevel.Cell.STEEP_R:
			return b + T - lx
		MazeLevel.Cell.STEEP_L:
			return b + lx
		MazeLevel.Cell.GENTLE_R_LO:
			return b + T - lx / 2
		MazeLevel.Cell.GENTLE_R_HI:
			return b + T / 2 - lx / 2
		MazeLevel.Cell.GENTLE_L_HI:
			return b + lx / 2
		MazeLevel.Cell.GENTLE_L_LO:
			return b + T / 2 + lx / 2
	return b + T


## p on or below the surface, within the tile's columns
static func inside(kind: int, cx: int, cy: int, p: Vector2i) -> bool:
	return p.y >= surface(kind, cy, p.x - cx * T)


## shape in local px (cell 40 x 40), clockwise from the top left; view only
static func polygon(kind: int) -> Array[Vector2i]:
	match kind:
		MazeLevel.Cell.STEEP_R:
			return [Vector2i(40, 0), Vector2i(40, 40), Vector2i(0, 40)]
		MazeLevel.Cell.STEEP_L:
			return [Vector2i(0, 0), Vector2i(40, 40), Vector2i(0, 40)]
		MazeLevel.Cell.GENTLE_R_LO:
			return [Vector2i(40, 20), Vector2i(40, 40), Vector2i(0, 40)]
		MazeLevel.Cell.GENTLE_R_HI:
			return [Vector2i(0, 20), Vector2i(40, 0), Vector2i(40, 40), Vector2i(0, 40)]
		MazeLevel.Cell.GENTLE_L_HI:
			return [Vector2i(0, 0), Vector2i(40, 20), Vector2i(40, 40), Vector2i(0, 40)]
		MazeLevel.Cell.GENTLE_L_LO:
			return [Vector2i(0, 20), Vector2i(40, 40), Vector2i(0, 40)]
	return []
