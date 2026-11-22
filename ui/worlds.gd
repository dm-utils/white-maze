class_name MazeWorlds
extends RefCounted
## The three worlds: series position to world, and the palettes (design 18.3, 18.4).

enum World { TEMPLE, JUNGLE, CAVE }

const COUNT := 3
const LEVELS_PER_WORLD := 3
const NAMES := ["temple", "jungle", "cave"]

const HAZARD := Color("#D24A3A")
const HAZARD_HI := Color("#F39A7E")
const HAZARD_DARK := Color("#8E2A22")
const RING := Color("#FFFFFF")
const DOOR_LIGHT := Color("#FFE7B0")

const TEMPLE := {
	"void": Color("#140F18"), "back_top": Color("#2A2030"), "back_bottom": Color("#17121C"),
	"back_line": Color("#33283B"), "back_decor": Color("#3A2D45"),
	"block": Color("#C29A62"), "joint": Color("#9A7442"), "speck": Color("#A7804C"), "lip": Color("#F3E0AE"),
	"noring": Color("#3F4260"), "noring_edge": Color("#2A2C42"), "sheen": Color("#8A90B8"),
	"detail": Color("#D9B77B"), "light": Color("#FFB45A"), "door_frame": Color("#D9B77B"),
}
const JUNGLE := {
	"void": Color("#0C1410"), "back_top": Color("#1A2A22"), "back_bottom": Color("#0F1A15"),
	"back_line": Color("#20332A"), "back_decor": Color("#22402A"),
	"block": Color("#6E7D62"), "joint": Color("#556349"), "speck": Color("#617055"), "lip": Color("#9BD36A"),
	"noring": Color("#34504C"), "noring_edge": Color("#243833"), "sheen": Color("#7FB8B0"),
	"detail": Color("#86C25E"), "light": Color("#FFB45A"), "door_frame": Color("#8C9A7A"),
}
# lip and sheen lowered from the start values: the near-white rule (A3) wants saturation >= 0.2
const CAVE := {
	"void": Color("#0A0F17"), "back_top": Color("#172234"), "back_bottom": Color("#0D1420"),
	"back_line": Color("#1C2A3D"), "back_decor": Color("#22344A"),
	"block": Color("#5A6A82"), "joint": Color("#44526A"), "speck": Color("#4E5D74"), "lip": Color("#A9C6E4"),
	"noring": Color("#2E5B7A"), "noring_edge": Color("#1F3F56"), "sheen": Color("#BFE3F7"),
	"detail": Color("#3A6EA5"), "light": Color("#7FC8E8"), "door_frame": Color("#7D8CA4"),
}


## world of the n-th level (1-based); levels past the last world stay in it
@warning_ignore("integer_division")
static func for_number(number: int) -> int:
	return clampi((number - 1) / LEVELS_PER_WORLD, 0, COUNT - 1)


## debug argument name to world, -1 when unknown
static func from_name(world_name: String) -> int:
	return NAMES.find(world_name)


static func palette(world: int) -> Dictionary:
	match world:
		World.JUNGLE:
			return JUNGLE
		World.CAVE:
			return CAVE
	return TEMPLE
