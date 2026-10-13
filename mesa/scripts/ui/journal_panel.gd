class_name JournalPanel
extends PanelContainer
## Diário de missões e bíblia rápida. Painel retrátil sobre a borda direita do mapa.

signal close_requested

var tabs: PaperTabs
var quests_page: ScrollContainer
var bible_page: VBoxContainer
var search: LineEdit
var bible_list: VBoxContainer


func build() -> void:
	add_theme_stylebox_override("panel", UiTheme.paper_box(8, 18))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.label("Diário", 30, UiTheme.INK, UiTheme.serif()))
	head.add_child(UiTheme.spacer(false))
	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.tooltip_text = "J também abre e fecha"
	close_btn.pressed.connect(func(): close_requested.emit())
	head.add_child(close_btn)
	v.add_child(head)
	tabs = PaperTabs.new()
	tabs.setup(["Missões", "Bíblia rápida"])
	tabs.tab_selected.connect(_on_tab)
	v.add_child(tabs)

	quests_page = ScrollContainer.new()
	quests_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quests_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(quests_page)
	var ql := VBoxContainer.new()
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ql.add_theme_constant_override("separation", 18)
	quests_page.add_child(ql)
	for q in Game.quests:
		ql.add_child(_quest_block(q))

	bible_page = VBoxContainer.new()
	bible_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bible_page.add_theme_constant_override("separation", 10)
	bible_page.visible = false
	v.add_child(bible_page)
	search = LineEdit.new()
	search.placeholder_text = "Buscar NPC, facção ou lugar"
	search.clear_button_enabled = true
	search.add_theme_stylebox_override("normal", UiTheme.box(Color(1, 1, 1, 0.45), 6, 1, Color(UiTheme.INK, 0.25), 10))
	search.add_theme_stylebox_override("focus", UiTheme.box(Color(1, 1, 1, 0.6), 6, 2, UiTheme.AMBER.darkened(0.2), 10))
	search.add_theme_color_override("font_color", UiTheme.INK)
	search.add_theme_color_override("font_placeholder_color", UiTheme.INK_SOFT)
	search.add_theme_color_override("caret_color", UiTheme.INK)
	search.text_changed.connect(func(_t): _render_bible())
	bible_page.add_child(search)
	var bs := ScrollContainer.new()
	bs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bible_page.add_child(bs)
	bible_list = VBoxContainer.new()
	bible_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bible_list.add_theme_constant_override("separation", 12)
	bs.add_child(bible_list)
	_render_bible()


func _on_tab(i: int) -> void:
	quests_page.visible = i == 0
	bible_page.visible = i == 1


func _quest_block(q: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	var t := UiTheme.wrap_label(q["title"], 20, UiTheme.INK, UiTheme.sans_bold())
	title_row.add_child(t)
	if q.get("pinned", false):
		var pin := PanelContainer.new()
		pin.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.AMBER, 0.25), 4, 1, UiTheme.AMBER.darkened(0.2), 3))
		pin.add_child(UiTheme.label("principal", 13, UiTheme.INK, UiTheme.sans_bold()))
		pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(pin)
	v.add_child(title_row)
	v.add_child(UiTheme.wrap_label(q["summary"], 16, UiTheme.INK_SOFT))
	for o in q["objectives"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(CheckMark.make(bool(o["done"])))
		var ol := UiTheme.wrap_label(o["text"], 17, UiTheme.INK_SOFT if o["done"] else UiTheme.INK)
		row.add_child(ol)
		v.add_child(row)
	return v


func _render_bible() -> void:
	for ch in bible_list.get_children():
		ch.queue_free()
	var term := search.text.strip_edges().to_lower()
	var any := false
	for sec in [["npcs", "NPCs"], ["factions", "Facções"], ["places", "Lugares"]]:
		var entries: Array = []
		for e in Game.bible.get(sec[0], []):
			var hay := ("%s %s %s" % [e["name"], e["role"], e["known"]]).to_lower()
			if term == "" or hay.contains(term):
				entries.append(e)
		if entries.is_empty():
			continue
		any = true
		bible_list.add_child(UiTheme.label(sec[1], 15, UiTheme.INK_SOFT, UiTheme.sans_bold()))
		for e in entries:
			var b := VBoxContainer.new()
			b.add_theme_constant_override("separation", 1)
			var nm := HBoxContainer.new()
			nm.add_theme_constant_override("separation", 8)
			nm.add_child(UiTheme.label(e["name"], 19, UiTheme.INK, UiTheme.sans_bold()))
			nm.add_child(UiTheme.label(e["role"], 16, UiTheme.INK_SOFT, UiTheme.sans_italic()))
			b.add_child(nm)
			b.add_child(UiTheme.wrap_label(e["known"], 16, UiTheme.INK))
			bible_list.add_child(b)
	if not any:
		bible_list.add_child(UiTheme.wrap_label("Nada com \"%s\". O grupo ainda não conhece ninguém com esse nome." % search.text, 16, UiTheme.INK_SOFT))


class CheckMark extends Control:
	var done := false

	static func make(d: bool) -> CheckMark:
		var c := CheckMark.new()
		c.done = d
		c.custom_minimum_size = Vector2(18, 22)
		c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return c

	func _draw() -> void:
		var r := Rect2(1, 4, 16, 16)
		draw_rect(r, UiTheme.INK, false, 1.5)
		if done:
			draw_polyline(PackedVector2Array([Vector2(4, 12), Vector2(8, 16), Vector2(15, 6)]), UiTheme.GOOD.darkened(0.3), 2.5, true)
