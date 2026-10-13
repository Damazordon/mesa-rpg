class_name ActionBar
extends PanelContainer
## Parte inferior: a bandeja de ações.
## Texto livre vai para o mestre interpretar; os cartões geram ações estruturadas para o motor.
##
## Turno (SRD 5.2.1): ação, ação bônus, reação, deslocamento e interação com objeto.
## Os indicadores no meio mostram o que ainda sobra; cartões sem recurso ficam apagados
## e o motivo aparece passando o mouse.

signal ability_armed(actor_id: String, ability: Dictionary)
signal move_pressed

const GROUPS := [["attack", "Ataques"], ["spell", "Magias"], ["action", "Ações"], ["bonus", "Bônus e recursos"]]

var who_portrait: Portrait
var who_slot: Control
var who_l: Label
var who_sub: Label
var check_btn: Button
var input: LineEdit
var send_btn: Button
var tabs_row: HBoxContainer
var cards_scroll: ScrollContainer
var shortcuts: HBoxContainer
var dice_btn: MenuButton
var end_btn: Button
var move_btn: Button
var econ_row: HBoxContainer
var target_chip: PanelContainer
var target_l: Label
var slot_menu: PopupMenu
var _end_normal: StyleBox
var current_id := ""
var group := "attack"
var _cards: Array = []
var _pending_spell: Dictionary = {}
var _meta_checked := {}


func build() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.WOOD, 10, 1, UiTheme.WOOD_EDGE, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	who.custom_minimum_size.x = 230
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
	center.size_flags_stretch_ratio = 0.9
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
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 12)
	center.add_child(status_row)
	econ_row = HBoxContainer.new()
	econ_row.add_theme_constant_override("separation", 10)
	econ_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(econ_row)
	target_chip = PanelContainer.new()
	target_chip.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.08), 12, 1, Color(1, 1, 1, 0.5), 3))
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 6)
	target_chip.add_child(chip_row)
	target_l = UiTheme.label("", 15, UiTheme.BONE, UiTheme.sans_medium())
	chip_row.add_child(target_l)
	var clear_btn := Button.new()
	clear_btn.text = "limpar"
	clear_btn.flat = true
	clear_btn.add_theme_font_size_override("font_size", 14)
	clear_btn.add_theme_color_override("font_color", UiTheme.BONE_SOFT)
	clear_btn.tooltip_text = "Parar de falar com este personagem (Esc)"
	clear_btn.pressed.connect(func(): Game.select_target(""))
	chip_row.add_child(clear_btn)
	target_chip.visible = false
	target_chip.tooltip_text = "O mestre usa este alvo quando você escreve uma ação"
	status_row.add_child(target_chip)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	center.add_child(input_row)
	input = LineEdit.new()
	input.placeholder_text = "Descreva o que seu personagem faz (Enter envia)"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = 44
	input.add_theme_font_size_override("font_size", 18)
	input.text_submitted.connect(_on_submit)
	input_row.add_child(input)
	send_btn = Button.new()
	send_btn.text = "Enviar"
	send_btn.pressed.connect(func(): _on_submit(input.text))
	input_row.add_child(send_btn)

	# Cartões de ação por grupo
	var acts := VBoxContainer.new()
	acts.add_theme_constant_override("separation", 4)
	acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.size_flags_stretch_ratio = 1.15
	row.add_child(acts)
	tabs_row = HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 4)
	acts.add_child(tabs_row)
	cards_scroll = ScrollContainer.new()
	cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cards_scroll.custom_minimum_size.y = 74
	cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(cards_scroll)
	shortcuts = HBoxContainer.new()
	shortcuts.add_theme_constant_override("separation", 6)
	cards_scroll.add_child(shortcuts)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size.x = 160
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
	move_btn = Button.new()
	move_btn.text = "Mover (M)"
	move_btn.tooltip_text = "Clique no destino no mapa. Também dá para clicar no próprio token."
	move_btn.pressed.connect(func(): move_pressed.emit())
	right.add_child(move_btn)
	end_btn = Button.new()
	end_btn.text = "Encerrar turno"
	end_btn.pressed.connect(_on_end_pressed)
	right.add_child(end_btn)
	_end_normal = end_btn.get_theme_stylebox("normal")

	slot_menu = PopupMenu.new()
	slot_menu.hide_on_checkable_item_selection = false
	slot_menu.id_pressed.connect(_on_slot_menu)
	add_child(slot_menu)

	Game.turn_changed.connect(_on_turn)
	Game.busy_changed.connect(func(_b): _refresh())
	Game.state_changed.connect(_on_state)
	Game.check_requested.connect(_on_check)
	Game.check_cleared.connect(func(): check_btn.visible = false)
	Game.combat_ended.connect(_on_combat_end)
	Game.turn_resources_changed.connect(_refresh)
	Game.target_selected.connect(_on_target_selected)


func _on_target_selected(id: String) -> void:
	var c: Dictionary = Game.by_id.get(id, {})
	target_chip.visible = not c.is_empty()
	if not c.is_empty():
		target_l.text = "Falando com %s" % c["name"]


func _on_end_pressed() -> void:
	if Game.is_party_turn() and not Game.busy:
		Game.end_turn()


func _on_state(id: String) -> void:
	if id == current_id:
		_refresh()


func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty() or Game.busy or (Game.in_combat and not Game.is_party_turn()):
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
	if c["side"] == "party" and int(c["hp"]) <= 0:
		who_l.text = "Vez de %s" % c["name"]
		who_sub.text = "Caído: testes contra a morte."
	elif c["side"] == "party":
		who_l.text = "Vez de %s" % c["name"]
		who_sub.text = "%s joga agora" % c["player"]
	else:
		who_l.text = "Vez de %s" % c["name"]
		who_sub.text = "O mestre está decidindo."
	if c["side"] == "party":
		group = "attack"
	_refresh()


# ---------------------------------------------------------------- cartões

func _rebuild_cards() -> void:
	for ch in tabs_row.get_children():
		ch.queue_free()
	for ch in shortcuts.get_children():
		ch.queue_free()
	_cards.clear()
	var c: Dictionary = Game.by_id.get(current_id, {})
	if c.is_empty() or c["side"] != "party":
		return
	var acts: Array = Game.available_actions(c)
	var counts := {}
	for a in acts:
		var gname := _group_of(a)
		counts[gname] = int(counts.get(gname, 0)) + 1
	if int(counts.get(group, 0)) == 0:
		group = "attack"
	for gdef in GROUPS:
		if int(counts.get(gdef[0], 0)) == 0:
			continue
		var b := Button.new()
		b.text = gdef[1]
		b.toggle_mode = true
		b.button_pressed = gdef[0] == group
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		var gid: String = gdef[0]
		b.pressed.connect(_select_group.bind(gid))
		tabs_row.add_child(b)
	var i := 0
	for a in acts:
		if _group_of(a) != group:
			continue
		i += 1
		_cards.append(a)
		shortcuts.add_child(_make_card(a, i))


func _select_group(gid: String) -> void:
	group = gid
	_rebuild_cards()


func _group_of(a: Dictionary) -> String:
	var g: String = a.get("group", "action")
	return "bonus" if g in ["bonus", "special"] else g


func _make_card(ab: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 68)
	b.clip_contents = true
	b.focus_mode = Control.FOCUS_NONE
	var kind_col := UiTheme.RES
	match ab["group"]:
		"attack":
			kind_col = UiTheme.HP.lightened(0.15)
		"bonus", "special":
			kind_col = UiTheme.AMBER
		"action":
			kind_col = UiTheme.BONE_SOFT
	if ab.get("kind", "") == "spell" and str(Srd.spells.get(ab["ref"], {}).get("auto", {}).get("kind", "")) == "heal":
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
	v.offset_top = 11
	v.offset_bottom = -5
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	var icon_tex: Texture2D = null
	if ab.get("kind", "") == "attack" and ab.get("ref") is Dictionary:
		icon_tex = GameIcons.attack_texture(ab["ref"])
	if icon_tex != null:
		v.offset_right = -34
		var icon := GameIcons.rect(icon_tex, 26, Color(kind_col, 0.85))
		icon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		icon.offset_left = -32
		icon.offset_top = -32
		icon.offset_right = -6
		icon.offset_bottom = -6
		b.add_child(icon)
	var name_l := UiTheme.wrap_label(str(ab["name"]), 15, UiTheme.BONE, UiTheme.sans_bold())
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var sub := str(ab.get("sub", ""))
	var cost_word := str({"action": "ação", "magic": "ação", "bonus": "bônus", "reaction": "reação", "attack": "ataque", "free": "livre", "free_nick": "livre", "move": "movimento"}.get(str(ab["cost"]), ""))
	var sub_l := UiTheme.label(("%s · %s" % [cost_word, sub]) if sub != "" else cost_word, 12, UiTheme.BONE_SOFT)
	sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_l.clip_text = true
	v.add_child(sub_l)
	if index <= 9:
		var key_l := UiTheme.label(str(index), 12, Color(UiTheme.BONE_SOFT, 0.7), UiTheme.sans_bold())
		key_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		key_l.offset_left = -16
		key_l.offset_top = 8
		b.add_child(key_l)
	var tip := str(ab.get("desc", ab["name"]))
	if tip.length() > 900:
		tip = tip.substr(0, 900) + "…"
	if not ab.get("available", true) and str(ab.get("why", "")) != "":
		tip = "Indisponível: %s\n\n%s" % [ab["why"], tip]
	if ab.get("kind", "") == "spell" and not ab.get("automated", true):
		tip += "\n\nEfeito narrativo: o mestre decide o resultado."
	b.tooltip_text = tip
	b.disabled = not ab.get("available", true) or Game.busy
	b.pressed.connect(_use.bind(ab))
	return b


func trigger(index: int) -> void:
	if index >= 0 and index < _cards.size() and _cards[index].get("available", false):
		_use(_cards[index])


func defend() -> void:
	if Game.is_party_turn() and not Game.busy:
		Game.perform(current_id, "std:dodge")


func _use(ab: Dictionary) -> void:
	if not Game.is_party_turn() or Game.busy:
		return
	var c: Dictionary = Game.by_id[current_id]
	if ab.get("kind", "") == "spell":
		var lvl := int(ab.get("level", 0))
		var meta: Array = Rules.tv(c, "metamagic", [])
		var choices := _slot_choices(c, str(ab["ref"]), lvl)
		if choices.size() > 1 or (not meta.is_empty() and Rules.res_left(c, "sorcery_points") > 0):
			_open_slot_menu(c, ab, choices, meta)
			return
		_go(ab, {"slot": choices[0] if not choices.is_empty() else 0})
		return
	_go(ab, {})


## Níveis de espaço possíveis para a magia (o primeiro é o padrão).
func _slot_choices(c: Dictionary, sid: String, lvl: int) -> Array:
	if lvl == 0:
		return [0]
	var out: Array = []
	var free: String = c.get("spellcasting", {}).get("free", {}).get(sid, "")
	if free != "" and Rules.res_left(c, free) > 0:
		out.append(lvl)
	for l in range(lvl, 10):
		if Rules.slot_left(c, l) > 0 and not l in out:
			out.append(l)
	return out


func _open_slot_menu(c: Dictionary, ab: Dictionary, choices: Array, meta: Array) -> void:
	slot_menu.clear()
	_pending_spell = ab
	_meta_checked = {}
	var free: String = c.get("spellcasting", {}).get("free", {}).get(str(ab["ref"]), "")
	for l in choices:
		var label := "Truque" if l == 0 else "Espaço de nível %d (%d)" % [l, Rules.slot_left(c, l)]
		if l == int(ab.get("level", 0)) and free != "" and Rules.res_left(c, free) > 0:
			label = "Nível %d, uso grátis (%s)" % [l, c["resources"][free]["name"]]
		slot_menu.add_item(label, int(l))
	if not meta.is_empty() and Rules.res_left(c, "sorcery_points") > 0:
		slot_menu.add_separator("Metamagia (%d pontos)" % Rules.res_left(c, "sorcery_points"))
		var idx := 100
		for mm in meta:
			slot_menu.add_check_item(Srd.label("feature", mm, str(mm).replace("_", " ").capitalize()), idx)
			slot_menu.set_item_metadata(slot_menu.get_item_index(idx), mm)
			idx += 1
	slot_menu.position = Vector2i(get_global_mouse_position()) - Vector2i(0, 40 + 28 * slot_menu.item_count)
	slot_menu.popup()


func _on_slot_menu(id: int) -> void:
	if id >= 100:
		var i := slot_menu.get_item_index(id)
		slot_menu.toggle_item_checked(i)
		_meta_checked[str(slot_menu.get_item_metadata(i))] = slot_menu.is_item_checked(i)
		return
	slot_menu.hide()
	var meta: Array = []
	for k in _meta_checked:
		if _meta_checked[k]:
			meta.append(k)
	_go(_pending_spell, {"slot": id, "metamagic": meta})


func _go(ab: Dictionary, opts: Dictionary) -> void:
	var a: Dictionary = ab.duplicate(true)
	a["opts_extra"] = opts
	var meta: Array = opts.get("metamagic", [])
	if "distant_spell" in meta:
		a["range_m"] = 9.0 if float(a.get("range_m", 0.0)) <= 1.6 else float(a["range_m"]) * 2.0
	if "twinned_spell" in meta:
		a["count"] = int(a.get("count", 1)) + 1
	var slot := int(opts.get("slot", 0))
	var auto: Dictionary = Srd.spells.get(str(a.get("ref", "")), {}).get("auto", {})
	if slot > int(a.get("level", 0)) and auto.has("upcast_targets"):
		a["count"] = int(a.get("count", 1)) + int(auto["upcast_targets"]) * (slot - int(a["level"]))
	if slot > int(a.get("level", 0)) and auto.has("upcast_darts"):
		a["count"] = int(a.get("count", 1)) + int(auto["upcast_darts"]) * (slot - int(a["level"]))
	if a.get("target", "") in ["self", "none"]:
		Game.perform(current_id, str(a["id"]), [current_id], Vector2(-1, -1), opts)
	else:
		ability_armed.emit(current_id, a)


# ---------------------------------------------------------------- estado

func _refresh() -> void:
	if not Game.in_combat:
		return
	var c: Dictionary = Game.by_id.get(current_id, {})
	var can := Game.is_party_turn() and not Game.busy
	input.editable = can
	send_btn.disabled = not can
	end_btn.disabled = not can
	var sm: Dictionary = Game.turn_summary(c) if not c.is_empty() else {}
	move_btn.disabled = not can or float(sm.get("move_left", 0.0)) <= 0.05
	var chk_action: bool = Game.pending_check.get("uses_action", true)
	check_btn.disabled = not can or (chk_action and not sm.get("action", false))
	_rebuild_cards()
	for ch in econ_row.get_children():
		ch.queue_free()
	if Game.is_party_turn() and not c.is_empty():
		_pip("Ação", sm.get("action", false), "Atacar, conjurar, Disparada, Esquivar...")
		if int(sm.get("attacks_left", 0)) > 0:
			_pip("Ataques %d" % int(sm["attacks_left"]), true, "Ataques restantes da ação Atacar (Ataque Extra).")
		_pip("Bônus", sm.get("bonus", false), "Ação bônus: características e magias de ação bônus.")
		_pip("Reação", sm.get("reaction", false), "Reação: ataque de oportunidade, Escudo Arcano... Volta no seu turno.")
		var mv := UiTheme.label("Movimento %s de %s" % [Game.fmt_m(float(sm.get("move_left", 0.0))), Game.fmt_m(float(sm.get("speed", 0.0)))], 15, UiTheme.BONE_SOFT, UiTheme.sans_medium())
		econ_row.add_child(mv)
	var spent: bool = not sm.get("action", true) and int(sm.get("attacks_left", 0)) == 0
	if can and spent:
		end_btn.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.AMBER, 0.2), 6, 2, UiTheme.AMBER, 8))
	else:
		end_btn.add_theme_stylebox_override("normal", _end_normal)
	if not can and Game.in_combat:
		input.placeholder_text = "Aguarde a sua vez"
	else:
		input.placeholder_text = "Descreva o que seu personagem faz (Enter envia)"


func _pip(text: String, on: bool, tip: String) -> void:
	var l := UiTheme.label(("● " if on else "○ ") + text, 15, UiTheme.GOOD.lightened(0.25) if on else Color(UiTheme.BONE_SOFT, 0.5), UiTheme.sans_bold())
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	econ_row.add_child(l)


func _on_check(chk: Dictionary) -> void:
	var with := ""
	if chk.get("target", "") != "":
		with = " com %s" % Game.by_id[chk["target"]]["name"]
	var sk := Game.skill_id(str(chk["skill"]))
	var nm: String = Srd.skill_name(sk) if sk in Srd.skills() else Srd.ability_name(sk)
	check_btn.text = "Rolar %s%s (CD %d)" % [nm, with, chk["dc"]]
	check_btn.tooltip_text = "Dificuldade: %s" % chk.get("dc_reason", "")
	check_btn.visible = true
	_refresh()


func _on_combat_end(victory: bool) -> void:
	who_l.text = "Combate encerrado"
	who_sub.text = "Vitória do grupo." if victory else "O grupo caiu."
	for ch in shortcuts.get_children():
		ch.queue_free()
	for ch in tabs_row.get_children():
		ch.queue_free()
	for ch in econ_row.get_children():
		ch.queue_free()
	end_btn.disabled = true
	move_btn.disabled = true
	input.editable = true
	send_btn.disabled = false
	input.placeholder_text = "Fora de combate: descanse, suba de nível ou converse com o mestre"
