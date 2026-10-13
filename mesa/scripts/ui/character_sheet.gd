class_name CharacterSheet
extends Control
## Modal da ficha do personagem. Abre ao clicar no retrato.
## Abas: Status e atributos, Pontos de upgrade, Perfil e biografia, Inventário e magias.

signal closed

const ATTRS := [["for", "FOR", "Força"], ["des", "DES", "Destreza"], ["con", "CON", "Constituição"],
	["int", "INT", "Inteligência"], ["sab", "SAB", "Sabedoria"], ["car", "CAR", "Carisma"]]

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
	card.custom_minimum_size = Vector2(1080, 720)
	card.add_theme_stylebox_override("panel", UiTheme.paper_box(10, 26))
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	v.add_child(header)
	tabs = PaperTabs.new()
	tabs.setup(["Status e atributos", "Pontos de upgrade", "Perfil e biografia", "Inventário e magias"])
	tabs.tab_selected.connect(_on_tab)
	v.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	page = MarginContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("margin_top", 6)
	page.add_theme_constant_override("margin_right", 10)
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


func open_for(id: String) -> void:
	cid = id
	current_tab = 0
	tabs.select(0)
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
	var val := _ink(value, 30, UiTheme.sans_bold())
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	v.add_child(val)
	if note != "":
		var n := _ink(note, 15, null, true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
	return p


func _clear(node: Node) -> void:
	for ch in node.get_children():
		ch.queue_free()


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
	var cls: String = "%s %d" % [c["class"], c["level"]]
	if c.get("custom_class", false):
		cls += " (classe personalizada)"
	who.add_child(_ink("%s, %s" % [cls, c["species"]], 18, null, true))
	who.add_child(_ink("Jogado por %s" % c["player"], 15, UiTheme.sans_italic(), true))
	var hp := _stat_box("Pontos de vida", "%d/%d" % [c["hp"], c["hp_max"]])
	hp.custom_minimum_size.x = 140
	header.add_child(hp)
	var ac := _stat_box("Classe de armadura", str(c["ac"]))
	ac.custom_minimum_size.x = 140
	header.add_child(ac)
	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.tooltip_text = "Esc também fecha"
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.pressed.connect(close)
	header.add_child(close_btn)


func _render_page() -> void:
	_clear(page)
	var c: Dictionary = Game.by_id[cid]
	match current_tab:
		0: page.add_child(_page_status(c))
		1: page.add_child(_page_upgrades(c))
		2: page.add_child(_page_profile(c))
		3: page.add_child(_page_inventory(c))


# ---------------------------------------------------------------- abas

func _page_status(c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	for a in ATTRS:
		var score: int = c["attrs"][a[0]]
		var bx := _stat_box(a[1], "%+d" % RulesEngine.mod(score), "valor %d" % score)
		bx.custom_minimum_size = Vector2(120, 112)
		bx.tooltip_text = a[2]
		grid.add_child(bx)
	var prof := RulesEngine.proficiency(c["level"])
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	left.add_child(stats)
	for s in [["Iniciativa", "%+d" % Game.dex_mod(c)], ["Proficiência", "%+d" % prof], ["Deslocamento", "%s m" % str(c["speed"])]]:
		var b := _stat_box(s[0], s[1])
		b.custom_minimum_size.x = 120
		stats.add_child(b)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 18)
	row.add_child(right)
	var res := _section(c["res_name"])
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 10)
	var rb := UiTheme.bar(UiTheme.RES, 12, true)
	rb.max_value = maxi(1, c["res_max"])
	rb.value = c["res"]
	res_row.add_child(rb)
	res_row.add_child(_ink("%d de %d" % [c["res"], c["res_max"]], 17, UiTheme.sans_medium()))
	res.add_child(res_row)
	right.add_child(res)
	var saves := _section("Salvaguardas com proficiência")
	saves.add_child(_ink(", ".join(PackedStringArray(c["saves"])), 18))
	right.add_child(saves)
	var skills := _section("Perícias")
	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 40)
	for s in c["skills"]:
		var line := HBoxContainer.new()
		line.custom_minimum_size.x = 220
		line.add_child(_ink(s["name"], 18))
		line.add_child(UiTheme.spacer(false))
		line.add_child(_ink("%+d" % int(s["bonus"]), 18, UiTheme.sans_bold()))
		sg.add_child(line)
	skills.add_child(sg)
	right.add_child(skills)
	var conds := _section("Condições ativas")
	if c["conditions"].is_empty():
		conds.add_child(_ink("Nenhuma.", 17, null, true))
	for cd in c["conditions"]:
		var def: Dictionary = Game.conditions[cd["id"]]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.add_child(UiTheme.condition_chip(def, cd["rounds"]))
		var txt: String = "%s: %s" % [def["name"], def["desc"]]
		line.add_child(_ink_wrap(txt, 17))
		conds.add_child(line)
	right.add_child(conds)
	return row


func _page_upgrades(c: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var pts: int = c["upgrade_points"]
	v.add_child(_ink("%d %s" % [pts, "ponto disponível" if pts == 1 else "pontos disponíveis"], 28, UiTheme.serif()))
	if Game.in_combat:
		v.add_child(_ink_wrap("Em combate. As compras liberam fora de combate e passam pelo motor de regras antes de valer.", 17, UiTheme.sans_italic(), true))
	for up in c["upgrades"]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.PAPER_SHADE, 0.45), 6, 1, Color(UiTheme.INK, 0.15), 14))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		p.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		info.add_child(_ink(up["name"], 20, UiTheme.sans_bold()))
		info.add_child(_ink_wrap(up["desc"], 17, null, true))
		row.add_child(info)
		var cost := int(up["cost"])
		var cost_l := _ink("%d %s" % [cost, "ponto" if cost == 1 else "pontos"], 18, UiTheme.sans_medium())
		cost_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cost_l)
		var buy := Button.new()
		buy.text = "Comprar"
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.disabled = Game.in_combat or cost > pts
		if Game.in_combat:
			buy.tooltip_text = "Disponível fora de combate"
		elif cost > pts:
			buy.tooltip_text = "Faltam %d pontos" % (cost - pts)
		var chosen: Dictionary = up
		buy.pressed.connect(func(): Game.buy_upgrade(cid, chosen))
		row.add_child(buy)
		v.add_child(p)
	if not c["upgrades_owned"].is_empty():
		var owned := _section("Já adquiridos")
		owned.add_child(_ink(", ".join(PackedStringArray(c["upgrades_owned"])), 18))
		v.add_child(owned)
	return v


func _page_profile(c: Dictionary) -> Control:
	var pr: Dictionary = c["profile"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 16)
	row.add_child(left)
	for item in [["Antecedente", "background"], ["Traços de personalidade", "traits"], ["Ideais", "ideals"], ["Vínculos", "bonds"], ["Defeitos", "flaws"]]:
		var s := _section(item[0])
		s.add_child(_ink_wrap(pr.get(item[1], ""), 18))
		left.add_child(s)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.15
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	var bio := _section("Biografia")
	var bio_l := _ink_wrap(pr.get("bio", ""), 20, UiTheme.serif())
	bio_l.add_theme_constant_override("line_spacing", 6)
	bio.add_child(bio_l)
	right.add_child(bio)
	return row


func _page_inventory(c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	var inv := _section("Inventário")
	for it in c["inventory"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var qty := int(it["qty"])
		line.add_child(_ink("%d×" % qty, 18, UiTheme.sans_bold(), true))
		line.add_child(_ink(it["name"], 18))
		line.add_child(UiTheme.spacer(false))
		line.add_child(_ink(str(it.get("note", "")), 16, null, true))
		inv.add_child(line)
	left.add_child(inv)
	var coins := _section("Moedas")
	coins.add_child(_ink(str(c.get("coins", "")), 18))
	left.add_child(coins)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	var spells: Array = c.get("spells", [])
	if spells.is_empty():
		var ab := _section("Habilidades")
		for a in c["abilities"]:
			var block := VBoxContainer.new()
			block.add_theme_constant_override("separation", 0)
			block.add_child(_ink(a["name"], 18, UiTheme.sans_bold()))
			block.add_child(_ink_wrap(a.get("desc", ""), 16, null, true))
			ab.add_child(block)
		right.add_child(ab)
		return row
	var slots: Dictionary = c.get("slots", {})
	if not slots.is_empty():
		var sl := _section("Espaços de magia")
		for lvl in slots.keys():
			var pair: Array = slots[lvl]
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			line.add_child(_ink("%sº nível" % lvl, 18))
			line.add_child(SlotPips.make(int(pair[0]), int(pair[1])))
			sl.add_child(line)
		right.add_child(sl)
	var by_level := {}
	for sp in spells:
		var lv := int(sp["level"])
		if not by_level.has(lv):
			by_level[lv] = []
		by_level[lv].append(sp)
	var levels := by_level.keys()
	levels.sort()
	for lv in levels:
		var sec := _section("Truques" if lv == 0 else "Magias de %dº nível" % lv)
		for sp in by_level[lv]:
			var block := VBoxContainer.new()
			block.add_theme_constant_override("separation", 0)
			block.add_child(_ink(sp["name"], 18, UiTheme.sans_bold()))
			block.add_child(_ink_wrap(sp.get("desc", ""), 16, null, true))
			sec.add_child(block)
		right.add_child(sec)
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
