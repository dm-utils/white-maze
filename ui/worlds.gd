class_name MazeWorlds
extends RefCounted
## The three worlds: series position to world, shared colours; palettes live in MazeSkins (design 18.3, 21.4).

enum World { TEMPLE, JUNGLE, CAVE }

const COUNT := 3
const LEVELS_PER_WORLD := 3
const NAMES := ["temple", "jungle", "cave"]

const HAZARD := Color("#D24A3A")
const HAZARD_HI := Color("#F39A7E")
const HAZARD_DARK := Color("#8E2A22")
const RING := Color("#FFFFFF")
const DOOR_LIGHT := Color("#FFE7B0")
const HAZARD_LINE := Color("#2A0F0C")


## world of the n-th level (1-based); levels past the last world stay in it
@warning_ignore("integer_division")
static func for_number(number: int) -> int:
	return clampi((number - 1) / LEVELS_PER_WORLD, 0, COUNT - 1)


## debug argument name to world, -1 when unknown
static func from_name(world_name: String) -> int:
	return NAMES.find(world_name)


## colours of a world, from its skin pack (design 21.4.3)
static func palette(world: int) -> Dictionary:
	return MazeSkins.skin(world)["pal"]
