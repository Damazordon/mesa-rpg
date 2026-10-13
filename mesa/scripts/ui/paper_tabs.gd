class_name PaperTabs
extends HBoxContainer
## Abas desenhadas para fundo de papel (ficha e diário).

signal tab_selected(index: int)

var buttons: Array[Button] = []
var group := ButtonGroup.new()


func setup(titles: Array) -> void:
	add_theme_constant_override("separation", 4)
	var sel := UiTheme.box(UiTheme.PAPER_SHADE, 6, 0, UiTheme.INK, 8)
	sel.border_width_bottom = 3
	sel.corner_radius_bottom_left = 0
	sel.corner_radius_bottom_right = 0
	sel.content_margin_left = 16
	sel.content_margin_right = 16
	var un: StyleBoxFlat = sel.duplicate()
	un.bg_color = Color(0, 0, 0, 0)
	un.border_color = Color(UiTheme.INK, 0.15)
	un.border_width_bottom = 1
	var hov: StyleBoxFlat = un.duplicate()
	hov.bg_color = Color(UiTheme.PAPER_SHADE, 0.5)
	var focus := UiTheme.box(Color(0, 0, 0, 0), 6, 2, UiTheme.AMBER.darkened(0.2), 8)
	focus.draw_center = false
	for i in titles.size():
		var b := Button.new()
		b.text = str(titles[i])
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_stylebox_override("normal", un)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_stylebox_override("hover_pressed", sel)
		b.add_theme_stylebox_override("focus", focus)
		b.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		b.add_theme_color_override("font_hover_color", UiTheme.INK)
		b.add_theme_color_override("font_pressed_color", UiTheme.INK)
		b.add_theme_color_override("font_hover_pressed_color", UiTheme.INK)
		b.add_theme_color_override("font_focus_color", UiTheme.INK)
		b.add_theme_font_override("font", UiTheme.sans_bold())
		b.add_theme_font_size_override("font_size", 18)
		var idx := i
		b.pressed.connect(func(): tab_selected.emit(idx))
		add_child(b)
		buttons.append(b)
	buttons[0].button_pressed = true


func select(index: int) -> void:
	buttons[index].button_pressed = true
	tab_selected.emit(index)
