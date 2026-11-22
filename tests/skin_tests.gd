extends RefCounted
## Skins (design 21): data packs and engine rules (S2, S3, S8), geometry, shapes, bake. Grows with the card steps.

const PALETTE_USED := [
	"void", "back_top", "back_bottom", "back_line", "back_decor", "block", "joint", "speck", "lip", "noring",
	"noring_edge", "sheen", "detail", "light", "door_frame",
]

var _check: Callable
var _node: Node


func run(check: Callable, node: Node) -> void:
	_check = check
	_node = node
	_data()
	_guard()
	_palette_rules()


func _packs() -> Array:
	return [MazeSkins.TEMPLE, MazeSkins.JUNGLE, MazeSkins.CAVE]


## S2
func _data() -> void:
	for w in MazeWorlds.COUNT:
		var pack := MazeSkins.pack(w)
		var name: String = MazeWorlds.NAMES[w]
		_check.call(MazeSkin.validate(pack).is_empty(), "S2 %s pack is valid (%s)" % [name, MazeSkin.validate(pack)])
		var skin := MazeSkins.skin(w)
		_check.call(MazeWorlds.palette(w) == skin["pal"], "S2 %s palette comes from the skin" % name)
		var all := true
		for key in PALETTE_USED:
			all = all and skin["pal"].has(key) and skin["pal"][key] is Color
		_check.call(all, "S2 %s palette holds every key the layers read" % name)
		var round_trip: Dictionary = JSON.parse_string(JSON.stringify(pack))
		_check.call(MazeSkin.resolve(round_trip) == skin, "S2 %s pack survives a JSON round trip" % name)
	_check.call(MazeWorlds.palette(99) == MazeWorlds.palette(MazeWorlds.World.TEMPLE), "S2 palette(99) is the temple")
	_check.call(MazeSkins.skin(-1) == MazeSkins.skin(0), "S2 an unknown world gives the temple skin")


func _with(path: Array, value: Variant) -> Dictionary:
	var pack: Dictionary = MazeSkins.TEMPLE.duplicate(true)
	var node: Variant = pack
	for i in path.size() - 1:
		node = node[path[i]]
	node[path[-1]] = value
	return pack


## S3
func _guard() -> void:
	for key in ["contour", "lip_hi", "door_frame", "hazard", "ring"]:
		var pack := _with(["palette", key], "#112233")
		_check.call(_has(MazeSkin.validate(pack), "engine-owned"), "S3 palette.%s is engine-owned" % key)
		var top := _with([key], "#112233")
		_check.call(_has(MazeSkin.validate(top), "engine-owned"), "S3 top-level %s is engine-owned" % key)
	_check.call(_has(MazeSkin.validate(_with(["palette", "lip"], "#FFFFFF")), "engine-owned"), "S3 palette.lip is engine-owned")
	var bad := {
		"rim.wall 9": _with(["rim", "wall"], 9),
		"stones.chamfer 20": _with(["stones", "chamfer"], 20.0),
		"3 motifs": _with(["motifs"], [{"kind": "moss", "chance": 1}, {"kind": "moss", "chance": 1}, {"kind": "moss", "chance": 1}]),
		"unknown tint": _with(["lip"], "neon"),
		"unknown motif": _with(["motifs"], [{"kind": "snake", "chance": 5}]),
		"unknown key": _with(["extra"], 1),
		"bad colour": _with(["palette", "block"], "red"),
	}
	var temple := MazeSkins.skin(MazeWorlds.World.TEMPLE)
	for label: String in bad:
		var pack: Dictionary = bad[label]
		_check.call(not MazeSkin.validate(pack).is_empty(), "S3 %s gives an error" % label)
		_check.call(MazeSkin.from_pack(pack) == temple, "S3 %s: from_pack returns the temple skin" % label)
	var wide := _with(["rim", "wall"], 9)
	_check.call(MazeSkin.resolve(wide)["rim"]["wall"] == 3, "S3 resolve clamps rim.wall 9 to 3")
	var skin := MazeSkins.skin(MazeWorlds.World.JUNGLE)
	var pal: Dictionary = skin["pal"]
	var tint: Array = MazeSkin.LIP_TINTS["moss"]
	_check.call(
		pal["lip_hi"] == Color(tint[1]) and pal["lip_lo"] == Color(tint[2]) and pal["lip"] == Color(tint[0])
		and pal["contour"] == (pal["block"] as Color).darkened(MazeSkin.CONTOUR_DARKEN)
		and pal["door_frame"] == (pal["block"] as Color).lightened(MazeSkin.DOOR_FRAME_LIGHTEN),
		"S3 lip shades, contour and door frame come from the engine"
	)
	var ints := _with(["rim", "wall"], 2.0)
	_check.call(MazeSkin.validate(ints).is_empty(), "S3 a whole float is accepted")


func _has(err: PackedStringArray, text: String) -> bool:
	for line in err:
		if text in line:
			return true
	return false


## S8
func _palette_rules() -> void:
	for w in MazeWorlds.COUNT:
		var err := MazeSkin.check_palette(MazeWorlds.palette(w))
		_check.call(err.is_empty(), "S8 %s palette passes the checks (%s)" % [MazeWorlds.NAMES[w], err])
	var base := MazeWorlds.palette(MazeWorlds.World.TEMPLE)
	var white := Color("#F0F0F0")
	var grey := Color("#808080")
	var hz := MazeWorlds.HAZARD
	var cases := {
		"C1": {"lip": base["block"]},
		"C2": {"block_hi": base["lip"]},
		"C3": {"joint": base["lip"]},
		"C4": {"block_lo": base["block_hi"]},
		"C5": {"contour": base["block"]},
		"C6": {"mortar": (base["block"] as Color).darkened(0.1)},
		"C7": {"noring": base["back_top"]},
		"C8": {"noring_hi": base["lip"]},
		"C9": {"back_top": hz},
		"C10": {"back_line": grey},
		"C11": {"speck": white},
		"C12": {"light": hz},
		"C13": {"back_top": MazeLilith.HAIR},
		"C14": {"door_frame": base["back_top"]},
	}
	for id: String in cases:
		var pal := base.duplicate()
		pal.merge(cases[id], true)
		_check.call(_has(MazeSkin.check_palette(pal), id + ":"), "S8 %s fires on a broken palette" % id)
	var bad_tints := {"snow": ["#FFFFFF", "#FFFFFF", "#FFFFFF"]}
	_check.call(_has(MazeSkin.check_palette(base, bad_tints), "C15:"), "S8 C15 fires on a near white lip tint")
	_check.call(
		_has(MazeSkin.check_palette(base, MazeSkin.LIP_TINTS, MazeWorlds.HAZARD), "C15:"),
		"S8 C15 fires on a pin outline lighter than the dark pin"
	)
