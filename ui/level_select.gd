class_name MazeLevelSelect
extends Control
## Level select (design 8.2): title, language button, progress line and one card per level.

signal level_chosen(index: int)
signal language_toggled

const MAX_WIDTH := 1100.0
const COLUMNS := 3
const CARD_H := 170.0
const MINI_SIZE := Vector2(104, 58)
const MINI_INSET := 10.0

var levels: Array[MazeLevel] = []
var store: MazeProfileStore
var all_open := false
var safe_override := ""

var cards: Array[Button] = []
var title: Label
var subtitle: Label
var notice_label: Label
var lang_button: Button
var _column: VBoxContainer
var _margin: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", WhiteTheme.SPACING)
	_margin.add_child(_column)
	build()


func _process(_delta: float) -> void:
	var vs := get_viewport_rect().size
	var ins := WhiteSafeArea.insets(vs, safe_override)
	_margin.add_theme_constant_override("margin_left", int(WhiteTheme.MARGIN + ins["left"]))
	_margin.add_theme_constant_override("margin_right", int(WhiteTheme.MARGIN + ins["right"]))
	_margin.add_theme_constant_override("margin_top", int(WhiteTheme.MARGIN + ins["top"]))
	_margin.add_theme_constant_override("margin_bottom", int(WhiteTheme.MARGIN + ins["bottom"]))
	var w := minf(MAX_WIDTH, vs.x - 2.0 * WhiteTheme.MARGIN - ins["left"] - ins["right"])
	_column.custom_minimum_size.x = w


func is_open(i: int) -> bool:
	if not levels[i].valid():
		return false
	if all_open or i == 0:
		return true
	return MazeProfile.is_finished(store.data, levels[i - 1].id)


func build() -> void:
	for c in _column.get_children():
		_column.remove_child(c)
		c.queue_free()
	cards.clear()
	var top := HBoxContainer.new()
	title = WhiteUi.label(MazeStrings.s("title"), WhiteTheme.FONT_TITLE, WhiteTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	lang_button = WhiteUi.button(str(WhiteText.t("lang")), func() -> void: language_toggled.emit())
	lang_button.focus_mode = Control.FOCUS_ALL
	lang_button.custom_minimum_size = Vector2(90, WhiteTheme.BUTTON_HEIGHT)
	top.add_child(lang_button)
	_column.add_child(top)

	var done := 0
	for lv in levels:
		if MazeProfile.is_finished(store.data, lv.id):
			done += 1
	var ms := MazeProfile.total_play_ticks(store.data) * 1000 / 60
	subtitle = WhiteUi.label(
		"%s  ·  %s  ·  %s" % [MazeStrings.s("tagline"), MazeStrings.s("levels_done") % [done, levels.size()],
		MazeStrings.s("play_time") % WhiteFormat.clock(ms)],
		WhiteTheme.FONT_SUBTITLE, WhiteTheme.DIM
	)
	_column.add_child(subtitle)
	notice_label = WhiteUi.label("", WhiteTheme.FONT_MESSAGE, WhiteTheme.DIM)
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if store.notice != "":
		notice_label.text = MazeStrings.s("profile_" + store.notice)
	notice_label.visible = notice_label.text != ""
	_column.add_child(notice_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", WhiteTheme.SPACING)
	grid.add_theme_constant_override("v_separation", WhiteTheme.SPACING)
	# room for the focus border, the scroll clip cuts it off otherwise
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 5) # nine cards must fit 1280 x 720 without a scrollbar
	scroll.add_child(pad)
	pad.add_child(grid)
	var first_open := -1
	for i in levels.size():
		var card := _card(i)
		grid.add_child(card)
		cards.append(card)
		if first_open < 0 and not card.disabled and not MazeProfile.is_finished(store.data, levels[i].id):
			first_open = i
	_link_focus()
	var target := first_open if first_open >= 0 else 0
	if not cards.is_empty():
		cards[target].grab_focus()


func _card(i: int) -> Button:
	var lv := levels[i]
	var open := is_open(i)
	var lines := PackedStringArray()
	if lv.valid():
		lines.append("%d  %s" % [i + 1, lv.names.get(WhiteText.lang, "")])
		lines.append(str(WhiteText.t("levels")[lv.difficulty]))
		var entry: Dictionary = store.data.get("levels", {}).get(lv.id, {})
		if open and MazeProfile.is_finished(store.data, lv.id):
			lines.append(MazeStrings.s("card_time") % MazeFormat.time(int(entry["best_ticks"])))
			lines.append(MazeStrings.s("card_rings") % [int(entry.get("fewest_rings", entry.get("best_rings", 0))), lv.par])
		elif open:
			lines.append(MazeStrings.s("not_done"))
			lines.append(str(WhiteText.t("par")) % lv.par)
		else:
			lines.append(MazeStrings.s("locked"))
	else:
		lines.append("%d" % (i + 1))
		lines.append(MazeStrings.s("locked"))
	var b := WhiteUi.button("\n".join(lines), func() -> void: level_chosen.emit(i))
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, CARD_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not open
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if lv.valid() and open:
		_add_mini_chain(b, i)
	return b


## best chain of a finished level as a small picture in the top right corner of its card (design 22.10)
func _add_mini_chain(card: Button, i: int) -> void:
	var lv := levels[i]
	var entry: Dictionary = store.data.get("levels", {}).get(lv.id, {})
	if not (MazeProfile.is_finished(store.data, lv.id) and entry.get("chain") is Dictionary):
		return
	var chain: Dictionary = entry["chain"]
	var parsed := MazeChain.parse(str(chain.get("links", "")))
	if not parsed["ok"] or not MazeChain.fits(lv, parsed["links"]):
		return
	var view := MazeChainView.new()
	view.style = MazeChainShapes.Style.MINI
	view.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	view.offset_left = -(MINI_SIZE.x + MINI_INSET)
	view.offset_right = -MINI_INSET
	view.offset_top = MINI_INSET
	view.offset_bottom = MINI_INSET + MINI_SIZE.y
	view.setup(lv, parsed["links"], MazeWorlds.for_number(i + 1), int(chain["rings"]) <= lv.par,
			MazeChainShapes.FINAL_T, true)
	card.add_child(view)


func _link_focus() -> void:
	# disabled cards take no focus; keep the language button reachable from the first row
	for i in mini(COLUMNS, cards.size()):
		cards[i].focus_neighbor_top = cards[i].get_path_to(lang_button)
	lang_button.focus_neighbor_bottom = lang_button.get_path_to(cards[0]) if not cards.is_empty() else NodePath()
