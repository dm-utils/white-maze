class_name MazeArt
extends RefCounted
## Pure helpers for the look: deterministic hash of a cell, ring-face rule, contrast maths (design 18.5).


## integer-only hash of (x, y, salt); same value on every platform
static func hash3(x: int, y: int, salt: int) -> int:
	var h := (x * 374761393 + y * 668265263 + salt * 2147483647) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return h ^ (h >> 16)


static func pick(x: int, y: int, salt: int, n: int) -> int:
	return hash3(x, y, salt) % n


static func chance(x: int, y: int, salt: int, percent: int) -> bool:
	return hash3(x, y, salt) % 100 < percent


## true when a ring may sit on this face: # block, cell in front neither solid, slope nor spike (design 3.10 step 6)
static func lip_face(level: MazeLevel, cell: Vector2i, face: int) -> bool:
	if level.cell(cell.x, cell.y) != MazeLevel.Cell.SOLID:
		return false
	var front := cell + MazeLevel.FACE_STEP[face]
	return not level.covered(front.x, front.y) and level.cell(front.x, front.y) != MazeLevel.Cell.SPIKE


## WCAG relative luminance
static func luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


## WCAG contrast ratio, symmetric
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
