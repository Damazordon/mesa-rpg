class_name UiTheme
extends RefCounted
## Paleta, fontes e estilos.
## Conceito: a mesa de jogo vista de cima, à noite. Feltro no centro (o mapa),
## madeira nas bordas (painéis), fichas de papel (grupo, ficha, diário).
## Violeta é exclusivo das provocações do mestre; âmbar é exclusivo de dados e da vez.

const FELT := Color("1d3833")
const FELT_DEEP := Color("10221e")
const WOOD := Color("2a1e18")
const WOOD_RAISED := Color("3a2b22")
const WOOD_EDGE := Color("5a4334")
const PAPER := Color("e6dcc6")
const PAPER_SHADE := Color("d6c9ad")
const INK := Color("2a211c")
const INK_SOFT := Color("6e5f50")
const BONE := Color("ece2cf")
const BONE_SOFT := Color("a99a8a")
const AMBER := Color("e3a63c")
const VIOLET := Color("b48ee8")
const HP := Color("c9483b")
const RES := Color("4f8ccb")
const GOOD := Color("6fb075")
const ENEMY := Color("c2543f")
const MISS := Color("9a9187")

const F_SANS := "res://assets/fonts/AlegreyaSans-Regular.ttf"
const F_SANS_MEDIUM := "res://assets/fonts/AlegreyaSans-Medium.ttf"
const F_SANS_BOLD := "res://assets/fonts/AlegreyaSans-Bold.ttf"
const F_SANS_ITALIC := "res://assets/fonts/AlegreyaSans-Italic.ttf"
const F_SERIF := "res://assets/fonts/Alegreya.ttf"
const F_SERIF_ITALIC := "res://assets/fonts/Alegreya-Italic.ttf"

static var _fonts := {}


static func font(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]


static func sans() -> Font: return font(F_SANS)
static func sans_medium() -> Font: return font(F_SANS_MEDIUM)
static func sans_bold() -> Font: return font(F_SANS_BOLD)
static func sans_italic() -> Font: return font(F_SANS_ITALIC)
static func serif() -> Font: return font(F_SERIF)
static func serif_italic() -> Font: return font(F_SERIF_ITALIC)


static func box(bg: Color, radius := 8, border := 0, border_color := Color(0, 0, 0, 0), pad := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func paper_box(radius := 6, pad := 12.0) -> StyleBoxFlat:
	var s := box(PAPER, radius, 1, PAPER_SHADE, pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


static func label(text: String, size := 18, color := BONE, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


static func wrap_label(text: String, size := 18, color := BONE, f: Font = null) -> Label:
	var l := label(text, size, color, f)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func bar(fill: Color, height := 10, on_paper := false) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_col := Color(INK, 0.18) if on_paper else Color(0, 0, 0, 0.4)
	b.add_theme_stylebox_override("background", box(bg_col, 3, 0, Color(0, 0, 0, 0), 0))
	b.add_theme_stylebox_override("fill", box(fill, 3, 0, Color(0, 0, 0, 0), 0))
	return b


static func spacer(vertical := true) -> Control:
	var c := Control.new()
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func kind_color(kind: String) -> Color:
	match kind:
		"buff":
			return GOOD
		"debuff":
			return HP
	return BONE_SOFT


## Ícone de condição. Placeholder até a arte do grupo chegar:
## se existir assets/art/conditions/<id>.png, ele é usado no lugar da sigla.
static func condition_chip(def: Dictionary, rounds: int) -> Control:
	var col := kind_color(def.get("kind", "neutral"))
	var chip := PanelContainer.new()
	var s := box(Color(col, 0.28), 4, 1, col.darkened(0.15), 3)
	s.content_margin_left = 6
	s.content_margin_right = 6
	chip.add_theme_stylebox_override("panel", s)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var tip: String = "%s. %s" % [def["name"], def["desc"]]
	if rounds > 0:
		tip += "\nTermina em %d %s." % [rounds, "rodada" if rounds == 1 else "rodadas"]
	chip.tooltip_text = tip
	var icon_path := "res://assets/art/conditions/%s.png" % def["id"]
	if ResourceLoader.exists(icon_path):
		var tr := TextureRect.new()
		tr.texture = load(icon_path)
		tr.custom_minimum_size = Vector2(20, 20)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(tr)
	else:
		var text: String = def["abbr"]
		if rounds > 0:
			text += " %d" % rounds
		var l := label(text, 14, col.darkened(0.55), sans_bold())
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(l)
	return chip


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = sans()
	t.default_font_size = 18
	t.set_color("font_color", "Label", BONE)

	# Botões: madeira em relevo, borda âmbar no foco (teclado visível).
	var normal := box(WOOD_RAISED, 6, 1, WOOD_EDGE, 8)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = WOOD_RAISED.lightened(0.07)
	hover.border_color = AMBER.darkened(0.25)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = WOOD.darkened(0.15)
	pressed.border_color = AMBER
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = WOOD
	disabled.border_color = WOOD_RAISED
	var focus := box(Color(0, 0, 0, 0), 6, 2, AMBER, 8)
	focus.draw_center = false
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", BONE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_hover_pressed_color", "Button", AMBER)
	t.set_color("font_focus_color", "Button", BONE)
	t.set_color("font_disabled_color", "Button", BONE_SOFT.darkened(0.35))

	# Campo de texto: um buraco escuro no feltro.
	t.set_stylebox("normal", "LineEdit", box(FELT_DEEP, 6, 1, WOOD_EDGE, 12))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), 6, 2, AMBER, 12))
	t.set_stylebox("read_only", "LineEdit", box(WOOD, 6, 1, WOOD_RAISED, 12))
	t.set_color("font_color", "LineEdit", BONE)
	t.set_color("font_placeholder_color", "LineEdit", BONE_SOFT)
	t.set_color("font_uneditable_color", "LineEdit", BONE_SOFT.darkened(0.3))
	t.set_color("caret_color", "LineEdit", AMBER)
	t.set_color("selection_color", "LineEdit", Color(AMBER, 0.35))

	t.set_stylebox("panel", "PanelContainer", box(WOOD, 10, 1, WOOD_EDGE, 14))
	t.set_stylebox("panel", "TooltipPanel", box(INK, 6, 1, WOOD_EDGE, 10))
	t.set_color("font_color", "TooltipLabel", BONE)
	t.set_font_size("font_size", "TooltipLabel", 16)

	t.set_stylebox("panel", "PopupMenu", box(WOOD_RAISED, 8, 1, WOOD_EDGE, 6))
	t.set_stylebox("hover", "PopupMenu", box(WOOD_EDGE, 4, 0, Color(0, 0, 0, 0), 4))
	t.set_color("font_color", "PopupMenu", BONE)
	t.set_color("font_hover_color", "PopupMenu", AMBER)
	t.set_font_size("font_size", "PopupMenu", 18)

	# Abas do painel do mestre.
	var tab_sel := box(WOOD_RAISED, 6, 0, Color(0, 0, 0, 0), 8)
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	tab_sel.border_width_bottom = 2
	tab_sel.border_color = AMBER
	tab_sel.content_margin_left = 16
	tab_sel.content_margin_right = 16
	var tab_un: StyleBoxFlat = tab_sel.duplicate()
	tab_un.bg_color = Color(0, 0, 0, 0)
	tab_un.border_color = Color(0, 0, 0, 0)
	var tab_hov: StyleBoxFlat = tab_un.duplicate()
	tab_hov.bg_color = Color(WOOD_RAISED, 0.5)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	t.set_stylebox("tab_focus", "TabContainer", focus)
	t.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0.2), 6, 0, Color(0, 0, 0, 0), 8))
	t.set_color("font_selected_color", "TabContainer", AMBER)
	t.set_color("font_unselected_color", "TabContainer", BONE_SOFT)
	t.set_color("font_hovered_color", "TabContainer", BONE)
	t.set_font_size("font_size", "TabContainer", 17)

	# Barras de rolagem finas, para não competir com o conteúdo.
	var track := box(Color(0, 0, 0, 0.2), 4, 0, Color(0, 0, 0, 0), 0)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab := box(WOOD_EDGE, 4, 0, Color(0, 0, 0, 0), 0)
	var grab_hi := box(AMBER.darkened(0.3), 4, 0, Color(0, 0, 0, 0), 0)
	for typ in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", typ, track)
		t.set_stylebox("grabber", typ, grab)
		t.set_stylebox("grabber_highlight", typ, grab_hi)
		t.set_stylebox("grabber_pressed", typ, grab_hi)

	# Texto narrado: serifada, a voz do mestre.
	t.set_font("normal_font", "RichTextLabel", serif())
	t.set_font("italics_font", "RichTextLabel", serif_italic())
	t.set_font("bold_font", "RichTextLabel", sans_bold())
	t.set_font_size("normal_font_size", "RichTextLabel", 20)
	t.set_font_size("italics_font_size", "RichTextLabel", 20)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)
	t.set_color("default_color", "RichTextLabel", BONE)
	t.set_constant("line_separation", "RichTextLabel", 3)
	return t
