class_name PartyCard
extends PanelContainer
## Ficha de papel de um jogador no painel do grupo.

signal open_requested(id: String)
signal hover_changed(id: String, on: bool)

var cid := ""
var portrait: Portrait
var name_l: Label
var sub_l: Label
var hp_bar: ProgressBar
var hp_l: Label
var res_bar: ProgressBar
var res_l: Label
var chips: HFlowContainer
var active := false
var _style: StyleBoxFlat


func setup(c: Dictionary) -> void:
	cid = c["id"]
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	_style = UiTheme.paper_box(6, 10)
	_style.set_border_width_all(2)
	add_theme_stylebox_override("panel", _style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	portrait = Portrait.new()
	portrait.setup(c, 62)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	name_l = UiTheme.label(c["name"], 22, UiTheme.INK, UiTheme.sans_bold())
	col.add_child(name_l)
	sub_l = UiTheme.label("%s, %s" % [c["class"], c["species"]], 15, UiTheme.INK_SOFT)
	sub_l.clip_text = true
	col.add_child(sub_l)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar = UiTheme.bar(UiTheme.HP, 11, true)
	hp_l = UiTheme.label("", 15, UiTheme.INK, UiTheme.sans_medium())
	hp_l.custom_minimum_size.x = 74
	hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_row.add_child(hp_bar)
	hp_row.add_child(hp_l)
	col.add_child(hp_row)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 8)
	res_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res_bar = UiTheme.bar(UiTheme.RES, 7, true)
	res_l = UiTheme.label("", 14, UiTheme.INK_SOFT)
	res_l.custom_minimum_size.x = 74
	res_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	res_row.add_child(res_bar)
	res_row.add_child(res_l)
	col.add_child(res_row)

	chips = HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	chips.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(chips)

	tooltip_text = "%s (%s). Clique para abrir a ficha." % [c["name"], c["player"]]
	res_row.tooltip_text = str(Rules.main_resource(c)[0]).capitalize()
	mouse_entered.connect(func(): hover_changed.emit(cid, true))
	mouse_exited.connect(func(): hover_changed.emit(cid, false))
	refresh(c, false)
	set_active(false)


func _gui_input(event: InputEvent) -> void:
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var keyed: bool = event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)
	if clicked or keyed:
		open_requested.emit(cid)
		accept_event()


func refresh(c: Dictionary, animate := true) -> void:
	var res := Rules.main_resource(c)
	hp_bar.max_value = c["hp_max"]
	res_bar.max_value = maxi(1, int(res[2]))
	res_bar.get_parent().visible = int(res[2]) > 0
	if animate:
		var tw := create_tween().set_parallel()
		tw.tween_property(hp_bar, "value", float(c["hp"]), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(res_bar, "value", float(res[1]), 0.3)
	else:
		hp_bar.value = c["hp"]
		res_bar.value = int(res[1])
	var temp: int = int(c.get("temp_hp", 0))
	hp_l.text = "PV %d/%d%s" % [c["hp"], c["hp_max"], (" +%d" % temp) if temp > 0 else ""]
	res_l.text = "%d/%d" % [int(res[1]), int(res[2])]
	res_l.get_parent().tooltip_text = str(res[0]).capitalize()
	for ch in chips.get_children():
		ch.queue_free()
	var d: Dictionary = c.get("death", {})
	if d.get("dead", false):
		chips.add_child(UiTheme.condition_chip({"id": "dead", "name": "Morto", "abbr": "Morto", "kind": "debuff", "desc": "Precisa de magia para voltar (Revivificar)."}, -1))
	elif int(c["hp"]) <= 0:
		var txt := "Morte %s%s" % ["✓".repeat(int(d.get("success", 0))), "✗".repeat(int(d.get("fail", 0)))]
		if d.get("stable", false):
			txt = "Estável"
		chips.add_child(UiTheme.condition_chip({"id": "death", "name": "Testes contra a morte", "abbr": txt, "kind": "debuff",
			"desc": "%d sucesso(s), %d falha(s). Três sucessos estabilizam; três falhas, morte. Qualquer cura levanta." % [int(d.get("success", 0)), int(d.get("fail", 0))]}, -1))
	for chip in UiTheme.status_chips(c):
		chips.add_child(chip)
	var down: bool = c["hp"] <= 0
	portrait.refresh_texture(cid)
	portrait.set_down(down)
	modulate = Color(1, 1, 1, 0.72) if down else Color.WHITE


func set_active(on: bool) -> void:
	active = on
	portrait.set_active(on)
	_style.border_color = UiTheme.AMBER if on else UiTheme.PAPER_SHADE
	_style.set_border_width_all(3 if on else 1)
	_style.bg_color = UiTheme.PAPER if on else UiTheme.PAPER.darkened(0.06)


func flash(kind: String) -> void:
	var col := UiTheme.GOOD if kind == "heal" else UiTheme.HP
	if kind == "miss":
		return
	self_modulate = col.lightened(0.3)
	create_tween().tween_property(self, "self_modulate", Color.WHITE, 0.5)


func set_linked(on: bool) -> void:
	if not active:
		_style.border_color = UiTheme.BONE_SOFT if on else UiTheme.PAPER_SHADE
		_style.set_border_width_all(2 if on else 1)
