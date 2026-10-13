class_name ActionBar
extends PanelContainer
## Parte inferior: a bandeja de dados.
## Texto livre vai para a IA interpretar; atalhos geram ação estruturada direto para o motor.

signal ability_armed(actor_id: String, ability: Dictionary)

var who_portrait: Portrait
var who_slot: Control
var who_l: Label
var who_sub: Label
var check_btn: Button
var input: LineEdit
var send_btn: Button
var shortcuts: HBoxContainer
var dice_btn: MenuButton
var end_btn: Button
var current_id := ""
var _abilities: Array = []


func build() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.WOOD, 10, 1, UiTheme.WOOD_EDGE, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	who.custom_minimum_size.x = 250
	row.add_child(who)
	who_slot = CenterContainer.new()
	who_slot.custom_minimum_size = Vector2(56, 56)
	who.add_child(who_slot)
	var who_text := VBoxContainer.new()
	who_text.alignment = BoxContainer.ALIGNMENT_CENTER
	who_text.add_theme_constant_override("separation", 0)
	who_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(who_text)
	who_l = UiTheme.label("", 21, UiTheme.BONE, UiTheme.sans_bold())
	who_sub = UiTheme.wrap_label("", 15, UiTheme.BONE_SOFT)
	who_text.add_child(who_l)
	who_text.add_child(who_sub)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 6)
	row.add_child(center)
	check_btn = Button.new()
	check_btn.visible = false
	var cs := UiTheme.box(Color(UiTheme.AMBER, 0.2), 6, 2, UiTheme.AMBER, 6)
	check_btn.add_theme_stylebox_override("normal", cs)
	var csh: StyleBoxFlat = cs.duplicate()
	csh.bg_color = Color(UiTheme.AMBER, 0.32)
	check_btn.add_theme_stylebox_override("hover", csh)
	check_btn.add_theme_color_override("font_color", UiTheme.AMBER.lightened(0.3))
	check_btn.add_theme_font_override("font", UiTheme.sans_bold())
	check_btn.pressed.connect(func(): Game.resolve_check())
	center.add_child(check_btn)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	center.add_child(input_row)
	input = LineEdit.new()
	input.placeholder_text = "Descreva o que seu personagem faz (Enter envia)"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = 46
	input.add_theme_font_size_override("font_size", 19)
	input.text_submitted.connect(_on_submit)
	input_row.add_child(input)
	send_btn = Button.new()
	send_btn.text = "Enviar"
	send_btn.pressed.connect(func(): _on_submit(input.text))
	input_row.add_child(send_btn)

	shortcuts = HBoxContainer.new()
	shortcuts.add_theme_constant_override("separation", 8)
	row.add_child(shortcuts)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size.x = 170
	row.add_child(right)
	dice_btn = MenuButton.new()
	dice_btn.text = "Rolar dados"
	dice_btn.flat = false
	dice_btn.add_theme_color_override("font_color", UiTheme.AMBER)
	dice_btn.tooltip_text = "Rolagem livre, sem efeito no jogo"
	var pop := dice_btn.get_popup()
	for sides in [4, 6, 8, 10, 12, 20, 100]:
		pop.add_item("d%d" % sides, sides)
	pop.id_pressed.connect(func(id): Game.free_roll(current_id, id))
	right.add_child(dice_btn)
	end_btn = Button.new()
	end_btn.text = "Encerrar turno"
	end_btn.pressed.connect(_on_end_pressed)
	right.add_child(end_btn)

	Game.turn_changed.connect(_on_turn)
	Game.busy_changed.connect(func(_b): _refresh_enabled())
	Game.state_changed.connect(_on_state)
	Game.check_requested.connect(_on_check)
	Game.check_cleared.connect(func(): check_btn.visible = false)
	Game.combat_ended.connect(_on_combat_end)


func _on_end_pressed() -> void:
	if Game.is_party_turn() and not Game.busy:
		Game.end_turn()


func _on_state(id: String) -> void:
	if id == current_id:
		_refresh_enabled()


func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty() or not Game.is_party_turn() or Game.busy:
		return
	input.clear()
	Game.player_free_text(current_id, t)


func _on_turn(id: String, _round: int) -> void:
	current_id = id
	var c: Dictionary = Game.by_id[id]
	for ch in who_slot.get_children():
		ch.queue_free()
	who_portrait = Portrait.new()
	who_portrait.setup(c, 52)
	who_slot.add_child(who_portrait)
	if c["side"] == "party" and not Game.is_alive(c):
		who_l.text = "Vez de %s" % c["name"]
		who_sub.text = "Inconsciente, perde o turno."
	elif c["side"] == "party":
		who_l.text = "Vez de %s" % c["name"]
		who_sub.text = "%s joga agora" % c["player"]
	else:
		who_l.text = "Vez do %s" % c["name"]
		who_sub.text = "O mestre está decidindo."
	_build_shortcuts(c)
	_refresh_enabled()


func _build_shortcuts(c: Dictionary) -> void:
	for ch in shortcuts.get_children():
		ch.queue_free()
	_abilities = c.get("abilities", [])
	var i := 0
	for ab in _abilities:
		i += 1
		shortcuts.add_child(_make_shortcut(ab, i))


func _make_shortcut(ab: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 66)
	b.clip_contents = true
	var tip: String = "%s\n%s" % [ab["name"], ab.get("desc", "")]
	b.tooltip_text = tip + "\nAtalho: tecla %d" % index
	var kind_col := UiTheme.RES
	match ab["kind"]:
		"attack":
			kind_col = UiTheme.HP.lightened(0.15)
		"heal", "cure":
			kind_col = UiTheme.GOOD
	var stripe := ColorRect.new()
	stripe.color = kind_col
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_left = 6
	stripe.offset_right = -6
	stripe.offset_top = 4
	stripe.offset_bottom = 7
	b.add_child(stripe)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -8
	v.offset_top = 12
	v.offset_bottom = -6
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	var name_l := UiTheme.wrap_label(ab["name"], 16, UiTheme.BONE, UiTheme.sans_bold())
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var sub := ""
	if ab["kind"] in ["attack", "spell"]:
		sub = ab["damage"] + " " + str(ab.get("dtype", ""))
		if ab.get("target", "") == "area":
			sub += ", área"
	elif ab["kind"] == "heal":
		sub = "cura " + ab["damage"]
	else:
		sub = "item"
	if int(ab.get("cost", 0)) > 0:
		sub += ", custa %d" % int(ab["cost"])
	var sub_l := UiTheme.label(sub, 13, UiTheme.BONE_SOFT)
	sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_l.clip_text = true
	v.add_child(sub_l)
	var key_l := UiTheme.label(str(index), 12, Color(UiTheme.BONE_SOFT, 0.7), UiTheme.sans_bold())
	key_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	key_l.offset_left = -16
	key_l.offset_top = 8
	b.add_child(key_l)
	b.pressed.connect(func(): _use(ab))
	b.set_meta("ability", ab)
	return b


func _use(ab: Dictionary) -> void:
	if not Game.is_party_turn() or Game.busy:
		return
	if ab.get("target", "single") == "self":
		Game.use_ability(current_id, ab, [current_id])
	else:
		ability_armed.emit(current_id, ab)


func trigger(index: int) -> void:
	if index >= 0 and index < _abilities.size():
		_use(_abilities[index])


func _refresh_enabled() -> void:
	var can := Game.is_party_turn() and not Game.busy
	input.editable = can
	send_btn.disabled = not can
	end_btn.disabled = not can
	check_btn.disabled = not can
	var c: Dictionary = Game.by_id.get(current_id, {})
	for b in shortcuts.get_children():
		var ab: Dictionary = b.get_meta("ability", {})
		var affordable: bool = c.is_empty() or int(ab.get("cost", 0)) <= int(c.get("res", 0))
		b.disabled = not can or not affordable
		if not affordable:
			b.tooltip_text = "%s\nSem %s suficiente." % [ab["name"], c.get("res_name", "recurso")]
	if not can and Game.in_combat:
		input.placeholder_text = "Aguarde a sua vez"
	else:
		input.placeholder_text = "Descreva o que seu personagem faz (Enter envia)"


func _on_check(chk: Dictionary) -> void:
	check_btn.text = "Rolar %s (CD %d)" % [chk["skill"], chk["dc"]]
	check_btn.visible = true
	_refresh_enabled()


func _on_combat_end(victory: bool) -> void:
	who_l.text = "Combate encerrado"
	who_sub.text = "Vitória do grupo." if victory else "O grupo caiu."
	for b in shortcuts.get_children():
		b.disabled = true
	end_btn.disabled = true
	input.editable = true
	send_btn.disabled = false
	input.placeholder_text = "Fora de combate: a exploração entra na próxima etapa"
