class_name MazeStrings
extends RefCounted
## Player-facing texts, Dutch and English; registered through WhiteText (base keys: levels, par, restart, next,
## perfect, lang). Hint placeholders {move} {jump} {throw} {undo} come from the keys / touch tables.

const TEXT := {
	"nl": {
		"title": "WHITE MAZE",
		"tagline": "Een avontuur met Lilith",
		"levels_done": "Gehaald %d/%d",
		"play_time": "Speeltijd %s",
		"locked": "Op slot",
		"not_done": "Nog niet gehaald",
		"card_time": "Beste tijd %s",
		"card_rings": "Minste ringen %d · par %d",
		"hud_rings": "Ringen %d · par %d",
		"undo_bead": "Kraal terug",
		"pause": "Pauze",
		"resume": "Doorgaan",
		"levels_btn": "Levels",
		"finished": "Gehaald!",
		"result_rings": "Ringen: %d · par %d",
		"under_par": "Onder par!",
		"new_record": "Nieuw record",
		"best_time": "Beste tijd %s",
		"rotate": "Draai je toestel",
		"profile_damaged": "Het profiel was beschadigd en is opnieuw begonnen.",
		"profile_newer": "Dit profiel komt van een nieuwere versie; je tijden worden nu niet bewaard.",
		"ctl_move": "lopen",
		"ctl_throw": "werpen",
		"ctl_jump": "springen",
		"ctl_map": "kaart",
		"keys": {"move": "A/D", "jump": "Spatie", "throw": "J vasthouden en loslaten", "undo": "Z"},
		"touch": {"move": "je linkerduim", "jump": "de springknop", "throw": "de werpstick", "undo": "Kraal terug"},
		"help_keys":
			"A/D of pijltjes: lopen\nSpatie of W: springen (vasthouden = hoger)\nJ vasthouden: " +
			"richten, W/S draaien, loslaten: werpen, K: annuleren\nTab of M vasthouden: overzicht\n" +
			"Z: kraal terug  ·  R: opnieuw  ·  Esc: pauze",
		"help_touch":
			"Linkerduim: lopen\nSpringknop: springen (vasthouden = hoger)\nWerpstick: slepen = " +
			"richten, loslaten = werpen, terug naar het midden = annuleren\nKaartknop vasthouden: overzicht",
		"help_par":
			"Par telt de ringen waar je vanaf bent gestuiterd. Kraal terug geeft je de kraal terug, " +
			"maar een gebruikte ring blijft meetellen.",
	},
	"en": {
		"title": "WHITE MAZE",
		"tagline": "An adventure with Lilith",
		"levels_done": "Finished %d/%d",
		"play_time": "Play time %s",
		"locked": "Locked",
		"not_done": "Not finished yet",
		"card_time": "Best time %s",
		"card_rings": "Fewest rings %d · par %d",
		"hud_rings": "Rings %d · par %d",
		"undo_bead": "Bead back",
		"pause": "Pause",
		"resume": "Resume",
		"levels_btn": "Levels",
		"finished": "Finished!",
		"result_rings": "Rings: %d · par %d",
		"under_par": "Under par!",
		"new_record": "New record",
		"best_time": "Best time %s",
		"rotate": "Rotate your device",
		"profile_damaged": "The profile was damaged and has been started again.",
		"profile_newer": "This profile comes from a newer version; your times are not saved now.",
		"ctl_move": "move",
		"ctl_throw": "throw",
		"ctl_jump": "jump",
		"ctl_map": "map",
		"keys": {"move": "A/D", "jump": "Space", "throw": "hold and release J", "undo": "Z"},
		"touch":
		{"move": "your left thumb", "jump": "the jump button", "throw": "the throw stick", "undo": "Bead back"},
		"help_keys":
			"A/D or arrows: walk\nSpace or W: jump (hold = higher)\nHold J: aim, W/S turn, release: " +
			"throw, K: cancel\nHold Tab or M: overview\nZ: bead back  ·  R: restart  ·  Esc: pause",
		"help_touch":
			"Left thumb: walk\nJump button: jump (hold = higher)\nThrow stick: drag = aim, release " +
			"= throw, back to the centre = cancel\nHold the map button: overview",
		"help_par": "Par counts the rings you bounced off. Bead back returns the bead, but a used ring still counts.",
	},
}


static func register() -> void:
	WhiteText.register(TEXT)


## text for a key as String
static func s(key: String) -> String:
	return str(WhiteText.t(key))


## hint with placeholders filled for the input mode
static func hint(level: MazeLevel, touch: bool) -> String:
	var h: Variant = level.hints.get(WhiteText.lang, "")
	if not h is String or h == "":
		return ""
	var table: Variant = WhiteText.t("touch" if touch else "keys")
	return (h as String).format(table) if table is Dictionary else h
