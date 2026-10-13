class_name DiceEntry
extends PanelContainer
## Uma linha do histórico de dados. Clique para ver a conta completa.
## É a prova de que o mestre joga limpo: todo número citado está aqui.

var detail_l: Label


static func result_color(result: String) -> Color:
	match result:
		"crit":
			return UiTheme.AMBER
		"hit", "success":
			return UiTheme.GOOD
		"heal":
			return UiTheme.GOOD
		"miss", "fail", "fumble":
			return UiTheme.MISS
	return UiTheme.BONE_SOFT


func setup(e: Dictionary) -> void:
	var col := result_color(str(e["result"]))
	var s := UiTheme.box(Color(0, 0, 0, 0.22), 5, 0, col, 8)
	s.border_width_left = 4
	s.content_margin_left = 12
	add_theme_stylebox_override("panel", s)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Clique para ver a conta"

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var title := UiTheme.wrap_label(str(e["title"]), 15, UiTheme.BONE_SOFT, UiTheme.sans_medium())
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var summary := UiTheme.wrap_label(str(e["summary"]), 17, col.lightened(0.15) if e["result"] != "neutral" else UiTheme.BONE, UiTheme.sans_bold())
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(summary)
	detail_l = UiTheme.wrap_label(str(e["detail"]), 15, UiTheme.BONE)
	detail_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_l.visible = false
	v.add_child(detail_l)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		detail_l.visible = not detail_l.visible
		accept_event()
