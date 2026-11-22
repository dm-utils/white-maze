class_name MazeSkins
extends RefCounted
## The shipped skin packs as data (design 21.4) and their resolved, cached skins. Index = MazeWorlds.World.

const TEMPLE := {
	"format": 1,
	"id": "temple",
	"names": {"nl": "Tempel", "en": "Temple"},
	"palette": {
		"void": "#140F18", "back_top": "#2A2030", "back_bottom": "#17121C", "back_line": "#33283B",
		"back_decor": "#3A2D45", "block": "#C29A62", "block_hi": "#D8AE70", "block_lo": "#93703F",
		"joint": "#9A7442", "mortar": "#4A3622", "speck": "#A7804C", "motif": "#9A7442",
		"noring": "#3F4260", "noring_hi": "#5B6190", "noring_lo": "#2A2C42", "noring_edge": "#2A2C42",
		"sheen": "#8A90B8", "detail": "#D9B77B", "light": "#FFB45A",
	},
	"lip": "sand",
	"spikes": "spear",
	"back": "masonry",
	"stones": {"pair": 70, "big": 0, "bond": "running", "chamfer": 5.0, "bevel": 3.0, "shade": 0.10, "mortar": 2.5},
	"rim": {"wall": 2, "ceiling": 2, "chip": 4},
	"motifs": [{"kind": "glyph", "chance": 18}],
	"tufts": false,
}

const JUNGLE := {
	"format": 1,
	"id": "jungle",
	"names": {"nl": "Jungle", "en": "Jungle"},
	"palette": {
		"void": "#0C1410", "back_top": "#1A2A22", "back_bottom": "#0F1A15", "back_line": "#20332A",
		"back_decor": "#22402A", "block": "#6E7D62", "block_hi": "#8A9B79", "block_lo": "#4B5843",
		"joint": "#556349", "mortar": "#2C3526", "speck": "#617055", "motif": "#55703F",
		"noring": "#34504C", "noring_hi": "#4F7770", "noring_lo": "#243833", "noring_edge": "#243833",
		"sheen": "#7FB8B0", "detail": "#86C25E", "light": "#FFB45A",
	},
	"lip": "moss",
	"spikes": "thorn",
	"back": "courses",
	"stones": {"pair": 40, "big": 0, "bond": "stack", "chamfer": 6.0, "bevel": 3.0, "shade": 0.12, "mortar": 2.5},
	"rim": {"wall": 3, "ceiling": 3, "chip": 5},
	"motifs": [{"kind": "moss", "chance": 40}],
	"tufts": true,
}

const CAVE := {
	"format": 1,
	"id": "cave",
	"names": {"nl": "Grot", "en": "Cave"},
	"palette": {
		"void": "#0A0F17", "back_top": "#172234", "back_bottom": "#0D1420", "back_line": "#1C2A3D",
		"back_decor": "#22344A", "block": "#5A6A82", "block_hi": "#7484A0", "block_lo": "#414E64",
		"joint": "#44526A", "mortar": "#27303F", "speck": "#4E5D74", "motif": "#44526A",
		"noring": "#2E5B7A", "noring_hi": "#4A82A6", "noring_lo": "#1F3F56", "noring_edge": "#1F3F56",
		"sheen": "#BFE3F7", "detail": "#3A6EA5", "light": "#7FC8E8",
	},
	"lip": "frost",
	"spikes": "crystal",
	"back": "strata",
	"stones": {"pair": 25, "big": 45, "bond": "stack", "chamfer": 4.0, "bevel": 2.5, "shade": 0.08, "mortar": 2.0},
	"rim": {"wall": 3, "ceiling": 3, "chip": 6},
	"motifs": [{"kind": "crack", "chance": 35}, {"kind": "crystal", "chance": 15}],
	"tufts": false,
}

const PACKS := [TEMPLE, JUNGLE, CAVE]

static var _cache := {}


## pack of a world; unknown world: temple
static func pack(world: int) -> Dictionary:
	return PACKS[world] if world >= 0 and world < PACKS.size() else TEMPLE


## resolved skin of a world, built once
static func skin(world: int) -> Dictionary:
	var key := world if world >= 0 and world < PACKS.size() else MazeWorlds.World.TEMPLE
	if not _cache.has(key):
		_cache[key] = MazeSkin.from_pack(pack(key))
	return _cache[key]
