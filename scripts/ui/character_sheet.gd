class_name CharacterSheet
extends Control
## Modal da ficha do personagem (SRD 5.2.1). Abre ao clicar no retrato.
## Abas: Atributos e perícias, Características, Magias, Inventário e ataques, Perfil, Nível, Aparência.

signal closed
signal level_up_requested(id: String)

const TABS := ["Atributos e perícias", "Características", "Magias", "Inventário e ataques", "Perfil", "Nível", "Aparência e efeitos"]

var cid := ""
var card: PanelContainer
var header: HBoxContainer
var tabs: PaperTabs
var page: MarginContainer
var current_tab := 0


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.custom_minimum_size = Vector2(1180, 760)
	card.add_theme_stylebox_override("panel", UiTheme.paper_box(10, 26))
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	v.add_child(header)
	tabs = PaperTabs.new()
	tabs.setup(TABS)
	tabs.tab_selected.connect(_on_tab)
	v.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	page = MarginContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("margin_top", 6)
	page.add_theme_constant_override("margin_right", 14)
	scroll.add_child(page)
	Game.state_changed.connect(_on_state)


func _on_tab(i: int) -> void:
	current_tab = i
	_render_page()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _on_state(id: String) -> void:
	if visible and id == cid:
		_render_header()
		_render_page()


func open_for(id: String, tab := 0) -> void:
	cid = id
	current_tab = tab
	tabs.select(tab)
	_render_header()
	_render_page()
	visible = true
	modulate.a = 0.0
	card.scale = Vector2(0.97, 0.97)
	card.pivot_offset = card.custom_minimum_size / 2.0
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


# ---------------------------------------------------------------- utilitários de papel

func _ink(text: String, size := 18, f: Font = null, soft := false) -> Label:
	return UiTheme.label(text, size, UiTheme.INK_SOFT if soft else UiTheme.INK, f)


func _ink_wrap(text: String, size := 18, f: Font = null, soft := false) -> Label:
	return UiTheme.wrap_label(text, size, UiTheme.INK_SOFT if soft else UiTheme.INK, f)


func _section(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_ink(title, 19, UiTheme.sans_bold()))
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.INK, 0.18)
	rule.custom_minimum_size.y = 1
	v.add_child(rule)
	return v


func _stat_box(caption: String, value: String, note := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.PAPER_SHADE, 0.55), 6, 1, Color(UiTheme.INK, 0.2), 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var cap := _ink(caption, 14, UiTheme.sans_medium(), true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var val := _ink(value, 28, UiTheme.sans_bold())
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	v.add_child(val)
	if note != "":
		var n := _ink(note, 14, null, true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
	return p


func _clear(node: Node) -> void:
	for ch in node.get_children():
		ch.queue_free()


func _row(sep := 10) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", sep)
	return r


func _col(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


## Texto de regra: avisa quando ainda está no original em inglês.
func _rule_text(kind: String, id: String, original: String) -> String:
	var t := Srd.text(kind, id, original)
	if not Srd.is_translated(kind, id) and t == original and original != "":
		t += "\n(texto original do SRD, em inglês; tradução em andamento)"
	return t


# ---------------------------------------------------------------- cabeçalho

func _render_header() -> void:
	_clear(header)
	var c: Dictionary = Game.by_id[cid]
	var por := Portrait.new()
	por.setup(c, 84)
	header.add_child(por)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 0)
	header.add_child(who)
	who.add_child(_ink(c["name"], 34, UiTheme.serif()))
	var line := "%s, %s" % [c["class"], c["species"]]
	if c.get("subclass_id", "") != "":
		line += " · " + Srd.label("subclass", c["subclass_id"])
	who.add_child(_ink(line, 18, null, true))
	var bg := Srd.label("background", c.get("background_id", "")) if c.get("background_id", "") != "" else ""
	who.add_child(_ink("Jogado por %s%s" % [c["player"], (" · " + bg) if bg != "" else ""], 15, UiTheme.sans_italic(), true))
	var temp: int = int(c.get("temp_hp", 0))
	var hp := _stat_box("Pontos de vida", "%d/%d" % [c["hp"], c["hp_max"]], ("+%d temporários" % temp) if temp > 0 else "")
	hp.custom_minimum_size.x = 140
	header.add_child(hp)
	var ac := _stat_box("Classe de armadura", str(Rules.ac(c)))
	ac.custom_minimum_size.x = 140
	ac.tooltip_text = _ac_breakdown(c)
	header.add_child(ac)
	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.tooltip_text = "Esc também fecha"
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.pressed.connect(close)
	header.add_child(close_btn)


func _ac_breakdown(c: Dictionary) -> String:
	var parts := PackedStringArray()
	var arm: Dictionary = Srd.armor.get(c.get("armor_id", ""), {})
	if not arm.is_empty():
		parts.append("%s (%d%s)" % [Srd.label("armor", arm["id"], arm["name"]), int(arm["ac_base"]), " + Des" if arm.get("dex", false) else ""])
	else:
		parts.append("sem armadura: 10 + Des" + (" + Con" if str(Rules.tv(c, "unarmored_defense", "")) == "con" else (" + Sab" if str(Rules.tv(c, "unarmored_defense", "")) == "wis" else "")))
	if c.get("shield", false):
		parts.append("escudo +2")
	if Rules.tv(c, "defense_style") and not arm.is_empty():
		parts.append("Estilo Defesa +1")
	var e := Rules.eff_sum(c, "ac")
	if e != 0:
		parts.append("efeitos %+d" % e)
	return "CA: " + ", ".join(parts)


func _render_page() -> void:
	_clear(page)
	var c: Dictionary = Game.by_id[cid]
	match current_tab:
		0: page.add_child(_page_status(c))
		1: page.add_child(_page_features(c))
		2: page.add_child(_page_spells(c))
		3: page.add_child(_page_inventory(c))
		4: page.add_child(_page_profile(c))
		5: page.add_child(_page_level(c))
		6: page.add_child(_page_appearance(c))


# ---------------------------------------------------------------- atributos e perícias

func _page_status(c: Dictionary) -> Control:
	var row := _row(28)
	var left := _col(12)
	row.add_child(left)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	for ab in Rules.ABILITIES:
		var score := Rules.score(c, ab)
		var sv := Rules.save_bonus(c, ab)
		var bx := _stat_box(Srd.ability_abbr(ab), "%+d" % Rules.mod(score), "valor %d · salv. %+d%s" % [score, sv, " ●" if Rules.save_prof(c, ab) else ""])
		bx.custom_minimum_size = Vector2(128, 108)
		bx.tooltip_text = "%s. Salvaguarda %+d%s." % [Srd.ability_name(ab), sv, " (proficiente)" if Rules.save_prof(c, ab) else ""]
		grid.add_child(bx)
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 10)
	stats.add_theme_constant_override("v_separation", 10)
	left.add_child(stats)
	var hd := PackedStringArray()
	for die in c.get("hit_dice", {}):
		hd.append("%d%s de %d" % [int(c["hit_dice"][die]["left"]), die, int(c["hit_dice"][die]["max"])])
	for s in [["Iniciativa", "%+d" % Rules.initiative_bonus(c)], ["Proficiência", "%+d" % Rules.pb(c)],
			["Deslocamento", Game.fmt_m(Rules.speed_m(c))], ["Percepção passiva", str(Rules.passive(c, "perception"))],
			["Dados de Vida", ", ".join(hd) if not hd.is_empty() else "-"], ["Exaustão", str(int(c.get("exhaustion", 0)))]]:
		var b := _stat_box(s[0], s[1])
		b.custom_minimum_size.x = 128
		stats.add_child(b)
	if c.get("darkvision_ft", 0) > 0:
		left.add_child(_ink("Visão no escuro: %s" % Game.fmt_m(Rules.m(int(c["darkvision_ft"]))), 16, null, true))
	var res := PackedStringArray()
	for dt in c.get("resist", []):
		res.append(Srd.dtype_name(dt))
	if not res.is_empty():
		left.add_child(_ink_wrap("Resistência: " + ", ".join(res), 16, null, true))

	var right := _col(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var skills := _section("Perícias (● proficiente, ●● especialista)")
	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 40)
	sg.add_theme_constant_override("v_separation", 2)
	var sk_list: Array = Srd.skills()
	sk_list.sort_custom(func(x, y): return Srd.skill_name(x) < Srd.skill_name(y))
	for sk in sk_list:
		var line := _row(8)
		line.custom_minimum_size.x = 270
		var p := Rules.skill_prof(c, sk)
		line.add_child(_ink(["○", "●", "●●"][p], 14, UiTheme.sans_bold(), p == 0))
		line.add_child(_ink("%s (%s)" % [Srd.skill_name(sk), Srd.ability_abbr(Srd.skill_ability(sk))], 17, null, p == 0))
		line.add_child(UiTheme.spacer(false))
		line.add_child(_ink("%+d" % Rules.skill_bonus(c, sk), 17, UiTheme.sans_bold()))
		sg.add_child(line)
	skills.add_child(sg)
	right.add_child(skills)
	var conds := _section("Condições e efeitos")
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	for ch in UiTheme.status_chips(c):
		chips.add_child(ch)
	if chips.get_child_count() == 0:
		conds.add_child(_ink("Nenhum.", 17, null, true))
	else:
		conds.add_child(chips)
	var d: Dictionary = c.get("death", {})
	if int(c["hp"]) == 0 and not d.get("dead", false):
		conds.add_child(_ink("Testes contra a morte: %d sucesso(s), %d falha(s)%s" % [int(d.get("success", 0)), int(d.get("fail", 0)), ", estável" if d.get("stable", false) else ""], 17, UiTheme.sans_bold()))
	right.add_child(conds)
	return row


# ---------------------------------------------------------------- características

func _page_features(c: Dictionary) -> Control:
	var v := _col(14)
	var res: Dictionary = c.get("resources", {})
	if not res.is_empty():
		var rs := _section("Recursos")
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 8)
		for rid in res:
			var r: Dictionary = res[rid]
			var rec := {"short": "descanso curto", "long": "descanso longo", "long_one_short": "longo (1 no curto)"}.get(str(r.get("recharge", "long")), "") as String
			var b := _stat_box(str(r["name"]), "%d/%d" % [int(r["left"]), int(r["max"])], rec)
			b.custom_minimum_size.x = 170
			flow.add_child(b)
		rs.add_child(flow)
		v.add_child(rs)
	var by_src := {}
	var order: Array = []
	for f in c.get("features", []):
		var src: String = str(f.get("source", ""))
		if not by_src.has(src):
			by_src[src] = []
			order.append(src)
		by_src[src].append(f)
	for src in order:
		var sec := _section(src)
		for f in by_src[src]:
			var block := _col(0)
			var title := str(f["name"])
			if int(f.get("level", 1)) > 1:
				title += "  (nível %d)" % int(f["level"])
			block.add_child(_ink(title, 18, UiTheme.sans_bold()))
			var txt := str(f.get("text", ""))
			block.add_child(_ink_wrap(txt + ("" if f.get("translated", false) else "\n(texto original do SRD, em inglês)"), 15, null, true))
			sec.add_child(block)
		v.add_child(sec)
	return v


# ---------------------------------------------------------------- magias

func _page_spells(c: Dictionary) -> Control:
	var v := _col(14)
	var sc: Dictionary = c.get("spellcasting", {})
	if sc.is_empty():
		v.add_child(_ink("Este personagem não conjura magias.", 20, UiTheme.serif(), true))
		return v
	var top := _row(12)
	for s in [["Atributo", Srd.ability_name(sc.get("ability", "int"))], ["CD de magia", str(Rules.spell_dc(c))], ["Ataque mágico", "%+d" % Rules.spell_attack(c)]]:
		var b := _stat_box(s[0], s[1])
		b.custom_minimum_size.x = 160
		top.add_child(b)
	v.add_child(top)
	var slots: Dictionary = c.get("slots", {})
	var pact: Dictionary = c.get("pact", {})
	if not slots.is_empty() or not pact.is_empty():
		var sl := _section("Espaços de magia")
		var keys: Array = slots.keys()
		keys.sort()
		for lvl in keys:
			var line := _row(10)
			line.add_child(_ink("Nível %s" % lvl, 18))
			line.add_child(SlotPips.make(int(slots[lvl]["left"]), int(slots[lvl]["max"])))
			sl.add_child(line)
		if not pact.is_empty():
			var line2 := _row(10)
			line2.add_child(_ink("Magia de Pacto (nível %d, volta no descanso curto)" % int(pact["level"]), 18))
			line2.add_child(SlotPips.make(int(pact["left"]), int(pact["max"])))
			sl.add_child(line2)
		v.add_child(sl)
	var spells: Array = CharBuilder.castable_spells(c)
	var by_level := {}
	for sid in spells:
		var lv := int(Srd.spells[sid]["level"])
		if not by_level.has(lv):
			by_level[lv] = []
		by_level[lv].append(sid)
	var levels := by_level.keys()
	levels.sort()
	for lv in levels:
		var sec := _section("Truques" if lv == 0 else "Magias de nível %d" % lv)
		for sid in by_level[lv]:
			var sp: Dictionary = Srd.spells[sid]
			var block := _col(0)
			var tags := PackedStringArray([Srd.label("school", sp["school"], sp["school"])])
			if sp.get("concentration", false):
				tags.append("concentração")
			if sp.get("ritual", false):
				tags.append("ritual")
			if sid in sc.get("always", []):
				tags.append("sempre preparada")
			tags.append("automática" if sp.get("auto", {}).get("kind", "manual") != "manual" else "o mestre arbitra")
			block.add_child(_ink("%s  (%s)" % [Srd.label("spell", sid), ", ".join(tags)], 18, UiTheme.sans_bold()))
			block.add_child(_ink(Srd.spell_meta(sid), 14, UiTheme.sans_italic(), true))
			block.add_child(_ink_wrap(_rule_text("spell", sid, Srd.spell_text(sid)), 15, null, true))
			sec.add_child(block)
		v.add_child(sec)
	return v


# ---------------------------------------------------------------- inventário e ataques

func _page_inventory(c: Dictionary) -> Control:
	var row := _row(36)
	var left := _col(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var atk := _section("Ataques")
	for a in c.get("attacks", []):
		var line := _row(10)
		var nm := _ink(str(a["name"]), 18, UiTheme.sans_bold())
		nm.custom_minimum_size.x = 210
		line.add_child(nm)
		line.add_child(_ink("%+d" % int(a["to_hit"]), 18, UiTheme.sans_bold()))
		line.add_child(_ink("%s %s" % [a["damage"], Srd.dtype_name(str(a["dtype"]))], 17))
		line.add_child(UiTheme.spacer(false))
		var extra := PackedStringArray()
		if a.get("mastery", "") != "":
			extra.append("maestria: " + Srd.label("property", a["mastery"]))
		if not a.get("proficient", true):
			extra.append("sem proficiência")
		line.add_child(_ink(", ".join(extra), 15, UiTheme.sans_italic(), true))
		atk.add_child(line)
	left.add_child(atk)
	var worn := _section("Vestindo")
	var arm: Dictionary = Srd.armor.get(c.get("armor_id", ""), {})
	worn.add_child(_ink((Srd.label("armor", arm["id"], arm["name"]) if not arm.is_empty() else "Sem armadura") + (" e escudo" if c.get("shield", false) else ""), 18))
	left.add_child(worn)
	var right := _col(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var inv := _section("Inventário")
	for it in c.get("inventory", []):
		var line := _row(10)
		line.add_child(_ink("%d×" % int(it["qty"]), 18, UiTheme.sans_bold(), true))
		line.add_child(_ink(str(it["name"]), 18))
		inv.add_child(line)
	right.add_child(inv)
	var coins := _section("Dinheiro")
	coins.add_child(_ink("%d %s" % [int(c.get("coins", {}).get("gp", 0)), Srd.currency()], 18))
	right.add_child(coins)
	return row


# ---------------------------------------------------------------- perfil

func _page_profile(c: Dictionary) -> Control:
	var pr: Dictionary = c.get("profile", {})
	var row := _row(36)
	var left := _col(16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	for item in [["Antecedente", "background"], ["Traços de personalidade", "traits"], ["Ideais", "ideals"], ["Vínculos", "bonds"], ["Defeitos", "flaws"]]:
		var s := _section(item[0])
		s.add_child(_ink_wrap(str(pr.get(item[1], "")), 18))
		left.add_child(s)
	var right := _col(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.15
	row.add_child(right)
	var bio := _section("Biografia")
	var bio_l := _ink_wrap(str(pr.get("bio", "")), 20, UiTheme.serif())
	bio_l.add_theme_constant_override("line_spacing", 6)
	bio.add_child(bio_l)
	right.add_child(bio)
	var al := _section("Tendência e idiomas")
	al.add_child(_ink("%s · %s" % [str(c.get("alignment", "")) if str(c.get("alignment", "")) != "" else "Tendência não definida", ", ".join(PackedStringArray(c.get("languages", [])))], 17, null, true))
	right.add_child(al)
	return row


# ---------------------------------------------------------------- nível

func _page_level(c: Dictionary) -> Control:
	var v := _col(14)
	var lv := int(c["level"])
	var xp := int(c.get("xp", 0))
	var next := Srd.xp_for_level(lv + 1)
	v.add_child(_ink("Nível %d" % lv, 30, UiTheme.serif()))
	v.add_child(_ink("Experiência: %d%s" % [xp, ("  ·  próximo nível em %d" % next) if lv < 20 else ""], 18))
	var bar := UiTheme.bar(UiTheme.AMBER, 12, true)
	bar.max_value = maxi(1, next - Srd.xp_for_level(lv))
	bar.value = clampi(xp - Srd.xp_for_level(lv), 0, int(bar.max_value))
	bar.custom_minimum_size.x = 420
	v.add_child(bar)
	var by_xp: bool = str(Game.settings.get("level_mode", "xp")) == "xp"
	var ready: bool = Game.can_level_up(c)
	var btn := Button.new()
	btn.text = "Subir de nível"
	btn.custom_minimum_size.x = 220
	btn.disabled = Game.in_combat or lv >= 20 or (by_xp and not ready)
	if Game.in_combat:
		btn.tooltip_text = "Disponível fora de combate."
	elif lv >= 20:
		btn.tooltip_text = "O nível 20 é o máximo."
	elif by_xp and not ready:
		btn.tooltip_text = "Faltam %d XP para o nível %d. Esta sala sobe de nível por experiência." % [maxi(0, next - xp), lv + 1]
	else:
		btn.tooltip_text = "Pode subir agora." if ready else "Esta sala libera níveis por marco de história."
	btn.pressed.connect(func(): level_up_requested.emit(cid))
	v.add_child(btn)
	if ready:
		v.add_child(_ink("Experiência suficiente para o nível %d." % (lv + 1), 18, UiTheme.sans_bold()))
	elif not by_xp:
		v.add_child(_ink("Esta sala libera níveis por marco de história, não por experiência.", 18))
	var cls := _section("Classes")
	for k in c.get("choices", {}).get("classes", []):
		var sub := str(k.get("subclass_id", ""))
		cls.add_child(_ink("%s %d%s" % [Srd.label("class", k["class_id"]), int(k["level"]), (" · " + Srd.label("subclass", sub)) if sub != "" else ""], 18))
	v.add_child(cls)
	return v


# ---------------------------------------------------------------- aparência e efeitos

var _dialog: FileDialog
var _pending := {}  # {kind, key} da importação em andamento
var _status_l: Label
var _preview: FxPreview


func _open_import(kind: String, key: String) -> void:
	_pending = {"kind": kind, "key": key}
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.title = "Escolha uma imagem"
		_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Imagens"])
		_dialog.file_selected.connect(_on_file_chosen)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


func _on_file_chosen(path: String) -> void:
	import_from_path(path, _pending.get("kind", ""), _pending.get("key", ""))


## Separado do diálogo para poder ser testado sem clicar.
func import_from_path(path: String, kind: String, key: String) -> void:
	var err := ArtStore.import_image(path, kind, key)
	Game.state_changed.emit(cid)
	if _status_l != null and is_instance_valid(_status_l):
		_status_l.text = err if err != "" else "Imagem importada."


func _remove_art(kind: String, key: String) -> void:
	ArtStore.remove_image(kind, key)
	Game.state_changed.emit(cid)


func _on_token_same(on: bool, id: String) -> void:
	ArtStore.set_token_same(id, on)
	Game.state_changed.emit(id)


func _ink_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _page_appearance(c: Dictionary) -> Control:
	var id: String = c["id"]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 40)
	v.add_child(top)

	var por_sec := _section("Retrato")
	var por_row := HBoxContainer.new()
	por_row.add_theme_constant_override("separation", 14)
	var por := Portrait.new()
	por.setup(c, 128)
	por_row.add_child(por)
	var por_btns := VBoxContainer.new()
	por_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var imp_p := _ink_button("Importar retrato")
	imp_p.pressed.connect(func(): _open_import("portraits", id))
	por_btns.add_child(imp_p)
	var rem_p := _ink_button("Remover")
	rem_p.disabled = ArtStore.portrait(id) == null
	rem_p.pressed.connect(func(): _remove_art("portraits", id))
	por_btns.add_child(rem_p)
	por_row.add_child(por_btns)
	por_sec.add_child(por_row)
	top.add_child(por_sec)

	var tok_sec := _section("Token do mapa")
	var tok_row := HBoxContainer.new()
	tok_row.add_theme_constant_override("separation", 14)
	var tok := Portrait.new()
	tok.setup(c, 84)
	tok.texture = ArtStore.token(id)
	tok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tok_row.add_child(tok)
	var tok_btns := VBoxContainer.new()
	tok_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var same := CheckBox.new()
	same.text = "Usar o retrato como token"
	same.button_pressed = ArtStore.token_same(id)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		same.add_theme_stylebox_override(st, empty)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		same.add_theme_color_override(fc, UiTheme.INK)
	same.toggled.connect(_on_token_same.bind(id))
	tok_btns.add_child(same)
	var imp_t := _ink_button("Importar token (ex.: foto do mini 3D)")
	imp_t.disabled = ArtStore.token_same(id)
	imp_t.pressed.connect(func(): _open_import("tokens", id))
	tok_btns.add_child(imp_t)
	tok_row.add_child(tok_btns)
	tok_sec.add_child(tok_row)
	top.add_child(tok_sec)

	var fx_head := HBoxContainer.new()
	fx_head.add_theme_constant_override("separation", 24)
	v.add_child(fx_head)
	var fx_sec := _section("Ataques e efeitos")
	fx_sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fx_sec.add_child(_ink_wrap("O jogo escolhe a animação pelo tipo do ataque. Envie uma imagem do ataque (bola de fogo, machado, sino) e ela é animada no lugar do efeito padrão. Prefira PNG quadrado com fundo transparente.", 16, null, true))
	for ab in _fx_abilities(c):
		fx_sec.add_child(_fx_row(id, ab))
	fx_head.add_child(fx_sec)
	var prev_col := VBoxContainer.new()
	prev_col.add_theme_constant_override("separation", 6)
	prev_col.add_child(_ink("Teste da animação", 17, UiTheme.sans_bold()))
	_preview = FxPreview.new()
	_preview.actor_id = id
	prev_col.add_child(_preview)
	_status_l = _ink("", 15, UiTheme.sans_italic(), true)
	prev_col.add_child(_status_l)
	fx_head.add_child(prev_col)
	return v


## Ataques e magias que têm animação: o que aparece na lista de efeitos.
func _fx_abilities(c: Dictionary) -> Array:
	var out: Array = []
	for a in c.get("attacks", []):
		out.append(Game._fx_for_attack(a))
	for sid in CharBuilder.castable_spells(c):
		var sp: Dictionary = Srd.spells[sid]
		if sp.get("auto", {}).get("kind", "manual") in ["attack", "save", "heal", "auto_hit"]:
			out.append(Game.cb._fx_ability(sp))
	return out


func _fx_row(id: String, ab: Dictionary) -> Control:
	var ab_id: String = ab["id"]
	var key := "%s_%s" % [id, ab_id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := PanelContainer.new()
	var col := ArtStore.dtype_color(str(ab.get("dtype", "")))
	if ab["kind"] in ["heal", "cure"]:
		col = UiTheme.GOOD
	icon.add_theme_stylebox_override("panel", UiTheme.box(Color("221c17"), 6, 2, col, 2))
	icon.custom_minimum_size = Vector2(44, 44)
	var tex := ArtStore.fx_image(id, ab_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.add_child(tr)
	row.add_child(icon)
	var name_l := _ink(ab["name"], 18, UiTheme.sans_bold())
	name_l.custom_minimum_size.x = 190
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_l)
	var opt := OptionButton.new()
	opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	opt.custom_minimum_size.x = 250
	var auto_name: String = ArtStore.TEMPLATE_NAMES[ArtStore.auto_template(ab)].split(" (")[0]
	opt.add_item("Automático: %s" % auto_name)
	for t in ArtStore.TEMPLATES:
		opt.add_item(ArtStore.TEMPLATE_NAMES[t])
	if not ArtStore.is_auto(id, ab_id):
		opt.select(ArtStore.TEMPLATES.find(ArtStore.template_for(id, ab)) + 1)
	opt.item_selected.connect(func(i): ArtStore.set_template(id, ab_id, "auto" if i == 0 else ArtStore.TEMPLATES[i - 1]))
	row.add_child(opt)
	var imp := _ink_button("Imagem")
	imp.tooltip_text = "Importar imagem para este ataque"
	imp.pressed.connect(func(): _open_import("fx", key))
	row.add_child(imp)
	if tex != null:
		var rem := _ink_button("Remover")
		rem.pressed.connect(func(): _remove_art("fx", key))
		row.add_child(rem)
	var test := _ink_button("Testar")
	test.pressed.connect(func(): _preview.play(id, ab))
	row.add_child(test)
	return row


## Bolinhas de espaços de magia (cheias = disponíveis).
class SlotPips extends Control:
	var filled := 0
	var total := 0

	static func make(f: int, t: int) -> SlotPips:
		var p := SlotPips.new()
		p.filled = f
		p.total = t
		p.custom_minimum_size = Vector2(t * 22, 20)
		p.tooltip_text = "%d de %d disponíveis" % [f, t]
		return p

	func _draw() -> void:
		for i in total:
			var c := Vector2(10 + i * 22, size.y / 2.0)
			if i < filled:
				draw_circle(c, 7.0, UiTheme.RES)
			draw_arc(c, 7.0, 0.0, TAU, 24, UiTheme.INK, 1.5, true)
