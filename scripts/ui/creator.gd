class_name CharacterCreator
extends Control
## Criação de personagem (SRD 5.2.1, passo a passo do livro de 2024) e subida de nível.
## A ficha à direita é recalculada pelo CharBuilder a cada escolha; erros aparecem embaixo.
##
## Modo "create": todas as etapas. Modo "level": só o que muda ao ganhar um nível.

signal finished(choices: Dictionary)
signal canceled

const STEPS := ["Classe", "Origem", "Atributos", "Perícias e equipamento", "Magias e opções", "Detalhes"]
const CLASS_BLURB := {
	"barbarian": "Força bruta e resistência. Entra em Fúria, aguenta pancada e bate forte.",
	"bard": "Magia pela música e pela palavra. Inspira aliados e sabe um pouco de tudo.",
	"cleric": "Poder divino: cura, protege e castiga. Armadura e magia na mesma pessoa.",
	"druid": "Magia da natureza. Vira animal, controla o terreno e cura.",
	"fighter": "Mestre das armas. Mais ataques, Surto de Ação e o melhor com qualquer equipamento.",
	"monk": "Artes marciais e foco interior. Rápido, golpeia várias vezes e desvia ataques.",
	"paladin": "Guerreiro sagrado. Destruição Divina, auras e cura pelas mãos.",
	"ranger": "Caçador e batedor. Arco, Marca do Caçador e magia da natureza.",
	"rogue": "Furtividade e precisão. Ataque Furtivo, perícias e Ação Ardilosa.",
	"sorcerer": "Magia no sangue. Poucas magias, mas moldadas com Metamagia.",
	"warlock": "Pacto com um patrono. Rajada Mística, invocações e espaços que voltam no descanso curto.",
	"wizard": "Estudo arcano. A maior lista de magias do jogo e Recuperação Arcana.",
}
const SUBCLASS_BLURB := {
	"path_of_the_berserker": "Fúria sem freio: Frenesi dá dano extra ao atacar de forma imprudente.",
	"college_of_lore": "Saber e lábia: mais perícias e Palavras Cortantes para atrapalhar inimigos.",
	"life_domain": "Mestre da cura: magias de cura curam mais e Preservar a Vida salva o grupo.",
	"circle_of_the_land": "Magia da terra natal: magias extras do bioma e Auxílio da Terra.",
	"champion": "Simples e letal: crítico com 19 ou 20 e atletismo extraordinário.",
	"warrior_of_the_open_hand": "Golpes que derrubam e empurram; cura a si mesmo depois.",
	"oath_of_devotion": "Honra e justiça: Arma Sagrada soma Carisma aos ataques.",
	"hunter": "Caçador de presas grandes ou de hordas; táticas defensivas depois.",
	"thief": "Mãos rápidas, escalada e uso de itens mágicos.",
	"draconic_sorcery": "Sangue de dragão: escamas dão CA, resistência elemental e asas.",
	"fiend_patron": "Pacto infernal: PV temporários a cada inimigo derrubado.",
	"evoker": "Especialista em evocação: truques nunca erram totalmente e esculpe áreas.",
}
const ALIGNMENTS := ["Leal e Bom", "Neutro e Bom", "Caótico e Bom", "Leal e Neutro", "Neutro", "Caótico e Neutro", "Leal e Mau", "Neutro e Mau", "Caótico e Mau"]
const COLORS := ["#3e9a8f", "#b8733d", "#6f86c9", "#8fa349", "#a8577a", "#c9a227", "#5f7d8e", "#9a4a34"]

var mode := "create"
var ch := {}           # escolhas em construção
var base_ch := {}      # escolhas antes da subida de nível
var level_class := ""  # classe que ganha o nível (modo level)
var step := 0
var card: PanelContainer
var steps_box: VBoxContainer
var content: VBoxContainer
var preview: VBoxContainer
var errors_l: Label
var next_btn: Button
var back_btn: Button
var title_l: Label
var _rolled: Array = []


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.custom_minimum_size = Vector2(1500, 860)
	card.add_theme_stylebox_override("panel", UiTheme.paper_box(10, 22))
	center.add_child(card)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	card.add_child(root)
	var head := HBoxContainer.new()
	title_l = UiTheme.label("Novo personagem", 30, UiTheme.INK, UiTheme.serif())
	head.add_child(title_l)
	head.add_child(UiTheme.spacer(false))
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.pressed.connect(func(): visible = false; canceled.emit())
	head.add_child(cancel)
	root.add_child(head)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	steps_box = VBoxContainer.new()
	steps_box.custom_minimum_size.x = 210
	steps_box.add_theme_constant_override("separation", 6)
	body.add_child(steps_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var pscroll := ScrollContainer.new()
	pscroll.custom_minimum_size.x = 330
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(pscroll)
	preview = VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_theme_constant_override("separation", 6)
	pscroll.add_child(preview)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	root.add_child(foot)
	errors_l = UiTheme.wrap_label("", 15, UiTheme.HP.darkened(0.2))
	errors_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(errors_l)
	back_btn = Button.new()
	back_btn.text = "Voltar"
	back_btn.pressed.connect(func(): _go(step - 1))
	foot.add_child(back_btn)
	next_btn = Button.new()
	next_btn.text = "Próximo"
	next_btn.custom_minimum_size.x = 180
	next_btn.pressed.connect(_on_next)
	foot.add_child(next_btn)


# ---------------------------------------------------------------- abrir

func open_create() -> void:
	mode = "create"
	var lv := 1
	var lr: Array = Game.adventure.get("level_range", [1, 1])
	if not lr.is_empty():
		lv = int(lr[0])
	ch = {"name": "", "player": "Jogador %d" % (Game.party.size() + 1), "color": COLORS[Game.party.size() % COLORS.size()],
		"classes": [{"class_id": "fighter", "level": lv, "subclass_id": ""}], "species_id": "human", "species_choice": {},
		"background_id": "soldier", "method": "standard",
		"base_scores": {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}, "bg_bonus": {"str": 2, "con": 1},
		"skills": [], "expertise": [], "equipment_option": "A", "bg_equipment_option": "A",
		"cantrips": [], "spells": [], "options": {}, "feats": [], "hp_rolls": [], "profile": {}, "alignment": ""}
	_fit_theme()
	title_l.text = "Novo personagem · %s" % Srd.theme.get("name", "")
	step = 0
	visible = true
	_render()


## Edita escolhas já montadas (usado pela tela de criação de sala). Abre na etapa indicada.
func open_edit(choices: Dictionary, start_step := 0) -> void:
	mode = "create"
	ch = choices.duplicate(true)
	_fit_theme()
	title_l.text = "Ficha de %s · %s" % [str(ch.get("name", "")) if str(ch.get("name", "")) != "" else "novo personagem", Srd.theme.get("name", "")]
	step = clampi(start_step, 0, STEPS.size() - 1)
	visible = true
	_render()


func open_level_up(id: String) -> void:
	mode = "level"
	var c: Dictionary = Game.by_id[id]
	base_ch = c["choices"].duplicate(true)
	ch = base_ch.duplicate(true)
	level_class = str(ch["classes"][0]["class_id"])
	_apply_level_class()
	title_l.text = "%s sobe para o nível %d" % [c["name"], CharBuilder.level_of(ch)]
	step = 0
	visible = true
	_render()


## Garante que as escolhas iniciais respeitam o tema (ex.: realista só tem humanos).
func _fit_theme() -> void:
	var classes := Srd.list("class")
	if not ch["classes"][0]["class_id"] in classes and not classes.is_empty():
		ch["classes"][0]["class_id"] = classes[0]
	var sp := Srd.list("species")
	if not ch["species_id"] in sp and not sp.is_empty():
		ch["species_id"] = sp[0]


## Modo nível: soma 1 nível na classe escolhida (ou adiciona uma classe nova, multiclasse).
func _apply_level_class() -> void:
	ch = base_ch.duplicate(true)
	var found := false
	for k in ch["classes"]:
		if k["class_id"] == level_class:
			k["level"] = int(k["level"]) + 1
			found = true
	if not found:
		ch["classes"].append({"class_id": level_class, "level": 1, "subclass_id": ""})


# ---------------------------------------------------------------- navegação

func _steps() -> Array:
	if mode == "level":
		return ["Nível", "Escolhas do nível"]
	return STEPS


func _go(i: int) -> void:
	step = clampi(i, 0, _steps().size() - 1)
	_render()


func _on_next() -> void:
	if step < _steps().size() - 1:
		_go(step + 1)
		return
	var errs := _errors()
	if not errs.is_empty():
		errors_l.text = "\n".join(errs)
		return
	visible = false
	finished.emit(ch.duplicate(true))


func _render() -> void:
	for n in [steps_box, content]:
		for x in n.get_children():
			x.queue_free()
	var names := _steps()
	for i in names.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, names[i]]
		b.toggle_mode = true
		b.button_pressed = i == step
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_go.bind(i))
		steps_box.add_child(b)
	back_btn.disabled = step == 0
	next_btn.text = "Concluir" if step == names.size() - 1 else "Próximo"
	if mode == "level":
		match step:
			0: _page_level_class()
			1: _page_options(true)
	else:
		match step:
			0: _page_class()
			1: _page_origin()
			2: _page_scores()
			3: _page_skills_equipment()
			4: _page_options(false)
			5: _page_details()
	_refresh_preview()


func _changed() -> void:
	_refresh_preview()


# ---------------------------------------------------------------- utilitários

func _h(text: String, size := 22) -> Label:
	return UiTheme.label(text, size, UiTheme.INK, UiTheme.serif() if size >= 22 else UiTheme.sans_bold())


func _p(text: String, size := 16, soft := true) -> Label:
	return UiTheme.wrap_label(text, size, UiTheme.INK_SOFT if soft else UiTheme.INK)


func _card_grid(items: Array, selected: String, on_pick: Callable, cols := 3) -> GridContainer:
	## items: [[id, título, subtítulo, tooltip]]
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for it in items:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = it[0] == selected
		b.custom_minimum_size = Vector2(250, 86)
		b.clip_text = true
		b.tooltip_text = str(it[3]) if it.size() > 3 else ""
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 12
		v.offset_top = 8
		v.offset_right = -10
		v.add_theme_constant_override("separation", 2)
		var t := UiTheme.label(str(it[1]), 18, UiTheme.BONE, UiTheme.sans_bold())
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		var s := UiTheme.wrap_label(str(it[2]), 13, UiTheme.BONE_SOFT)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(s)
		b.add_child(v)
		b.pressed.connect(func(): on_pick.call(it[0]))
		grid.add_child(b)
	return grid


## Lista de caixas de marcar com limite. picked é alterado no lugar.
func _checklist(options: Array, picked: Array, limit: int, labeler: Callable, locked: Array = []) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 4)
	for id in options:
		var cb := CheckBox.new()
		cb.text = str(labeler.call(id))
		cb.button_pressed = id in picked or id in locked
		cb.disabled = id in locked
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			cb.add_theme_stylebox_override(st, empty)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
			cb.add_theme_color_override(fc, UiTheme.INK if fc != "font_disabled_color" else UiTheme.INK_SOFT)
		cb.toggled.connect(func(on): _toggle(picked, id, on, limit, cb))
		flow.add_child(cb)
	return flow


func _toggle(picked: Array, id: Variant, on: bool, limit: int, cb: CheckBox) -> void:
	if on and not id in picked:
		if limit > 0 and picked.size() >= limit:
			cb.set_pressed_no_signal(false)
			errors_l.text = "Limite de %d escolha(s). Desmarque outra antes." % limit
			return
		picked.append(id)
	elif not on:
		picked.erase(id)
	errors_l.text = ""
	_changed()


func _option_button(items: Array, selected: String, on_pick: Callable) -> OptionButton:
	## items: [[id, texto]]
	var ob := OptionButton.new()
	var idx := 0
	for i in items.size():
		ob.add_item(str(items[i][1]), i)
		if str(items[i][0]) == selected:
			idx = i
	ob.select(idx)
	ob.item_selected.connect(func(i): on_pick.call(items[i][0]))
	return ob


func _first() -> Dictionary:
	return ch["classes"][0]


func _cls(id := "") -> Dictionary:
	return Srd.classes.get(id if id != "" else str(_first()["class_id"]), {})


# ---------------------------------------------------------------- 1. classe

func _page_class() -> void:
	content.add_child(_h("Escolha a classe"))
	content.add_child(_p("A classe define o papel no grupo: dados de vida, salvaguardas, perícias, armas e magia."))
	var items: Array = []
	for cid in Srd.list("class"):
		var c: Dictionary = Srd.classes[cid]
		var prim := PackedStringArray()
		for ab in c["primary"]:
			prim.append(Srd.ability_name(ab))
		items.append([cid, Srd.label("class", cid), "d%d · %s\n%s" % [c["hit_die"], " ou ".join(prim), CLASS_BLURB.get(cid, "")], CLASS_BLURB.get(cid, "")])
	content.add_child(_card_grid(items, str(_first()["class_id"]), func(id): _first()["class_id"] = id; _first()["subclass_id"] = ""; ch["skills"] = []; ch["cantrips"] = []; ch["spells"] = []; ch["options"] = {}; _render()))
	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 10)
	lv_row.add_child(_p("Nível inicial", 17, false))
	var sb := SpinBox.new()
	sb.min_value = 1
	sb.max_value = 20
	sb.value = int(_first()["level"])
	sb.value_changed.connect(func(v): _first()["level"] = int(v); _render())
	lv_row.add_child(sb)
	lv_row.add_child(_p("(a mesa sugere %s)" % "–".join(PackedStringArray(Game.adventure.get("level_range", [1, 1]).map(func(x): return str(int(x)))))))
	content.add_child(lv_row)
	if int(_first()["level"]) >= 3:
		content.add_child(_h("Subclasse", 18))
		var subs: Array = []
		for s in _cls()["subclasses"]:
			subs.append([s["id"], Srd.label("subclass", s["id"], s["name"]), SUBCLASS_BLURB.get(s["id"], ""), s.get("text", "")])
		if str(_first()["subclass_id"]) == "" and not subs.is_empty():
			_first()["subclass_id"] = subs[0][0]
		content.add_child(_card_grid(subs, str(_first()["subclass_id"]), func(id): _first()["subclass_id"] = id; _render(), 2))
	var feats := _section_text("Características até o nível %d" % int(_first()["level"]))
	for f in _cls()["features"]:
		if int(f["level"]) <= int(_first()["level"]) and not f["id"] in ["ability_score_improvement", "epic_boon"]:
			feats.add_child(_p("Nível %d · %s" % [int(f["level"]), Srd.label("feature", f["id"], f["name"])], 15, false))
	content.add_child(feats)


func _section_text(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(_h(title, 18))
	return v


# ---------------------------------------------------------------- 2. origem

func _page_origin() -> void:
	content.add_child(_h("Antecedente"))
	content.add_child(_p("O antecedente dá três atributos para aumentar, um talento de origem, duas perícias, uma ferramenta e equipamento."))
	var bgs: Array = []
	for bid in Srd.list("background"):
		var b: Dictionary = Srd.backgrounds[bid]
		var abs := PackedStringArray()
		for ab in b["abilities"]:
			abs.append(Srd.ability_abbr(ab))
		var sk := PackedStringArray()
		for s in b["skills"]:
			sk.append(Srd.skill_name(s))
		bgs.append([bid, Srd.label("background", bid), "%s · %s\nTalento: %s" % [", ".join(abs), ", ".join(sk), Srd.label("feat", b["feat"])]])
	content.add_child(_card_grid(bgs, str(ch["background_id"]), func(id): ch["background_id"] = id; ch["bg_bonus"] = _default_bonus(id); _render()))
	content.add_child(_h("Espécie"))
	var sps: Array = []
	for sid in Srd.list("species"):
		var s: Dictionary = Srd.species[sid]
		var tr := PackedStringArray()
		for t in s["traits"]:
			tr.append(Srd.label("feature", t["id"], t["name"]))
		sps.append([sid, Srd.label("species", sid), "%s · %s" % [Game.fmt_m(Rules.m(int(s["speed_ft"]))), ", ".join(tr)]])
	content.add_child(_card_grid(sps, str(ch["species_id"]), func(id): ch["species_id"] = id; ch["species_choice"] = {}; _render()))
	var sc: Dictionary = ch["species_choice"]
	match str(ch["species_id"]):
		"dragonborn":
			content.add_child(_p("Ancestralidade dracônica (tipo de dano do sopro e da resistência):", 16, false))
			var items: Array = []
			for k in [["black", "Negro (ácido)"], ["blue", "Azul (elétrico)"], ["brass", "Latão (fogo)"], ["bronze", "Bronze (elétrico)"], ["copper", "Cobre (ácido)"], ["gold", "Dourado (fogo)"], ["green", "Verde (veneno)"], ["red", "Vermelho (fogo)"], ["silver", "Prateado (frio)"], ["white", "Branco (frio)"]]:
				items.append(k)
			content.add_child(_option_button(items, str(sc.get("ancestry", "red")), func(v): sc["ancestry"] = v; _changed()))
		"elf":
			content.add_child(_p("Linhagem élfica e Sentidos Aguçados:", 16, false))
			content.add_child(_option_button([["high", "Alto elfo (Prestidigitação)"], ["wood", "Elfo da floresta (Arte Druídica, 10,5 m)"], ["drow", "Drow (Luzes Dançantes, visão 36 m)"]], str(sc.get("lineage", "high")), func(v): sc["lineage"] = v; _changed()))
			content.add_child(_option_button([["perception", "Percepção"], ["insight", "Intuição"], ["survival", "Sobrevivência"]], str(sc.get("keen_senses", "perception")), func(v): sc["keen_senses"] = v; _changed()))
		"gnome":
			content.add_child(_option_button([["rock", "Gnomo das rochas (Consertar)"], ["forest", "Gnomo da floresta (Ilusão Menor)"]], str(sc.get("lineage", "rock")), func(v): sc["lineage"] = v; _changed()))
		"goliath":
			content.add_child(_p("Ancestralidade gigante:", 16, false))
			content.add_child(_option_button([["stone", "Pedra: reduz dano (reação)"], ["fire", "Fogo: +1d10 de fogo no acerto"], ["frost", "Gelo: +1d6 de frio e lentidão"], ["hill", "Colina: derruba o alvo"], ["storm", "Tempestade: 1d8 trovejante (reação)"], ["cloud", "Nuvem: teleporte curto"]], str(sc.get("ancestry", "stone")), func(v): sc["ancestry"] = v; _changed()))
		"tiefling":
			content.add_child(_option_button([["infernal", "Infernal (fogo, Raio de Fogo)"], ["abyssal", "Abissal (veneno, Spray Venenoso)"], ["chthonic", "Ctônico (necrótico, Toque Arrepiante)"]], str(sc.get("lineage", "infernal")), func(v): sc["lineage"] = v; _changed()))
		"human":
			content.add_child(_p("Habilidoso: uma perícia extra. Versátil: um talento de origem extra.", 16, false))
			var sk_items: Array = []
			for sk in Srd.skills():
				sk_items.append([sk, Srd.skill_name(sk)])
			content.add_child(_option_button(sk_items, str(sc.get("skillful", "perception")), func(v): sc["skillful"] = v; _changed()))
			var fts: Array = []
			for f in Srd.feats.values():
				if f["category"] == "origin" and Srd.allowed("feat", f["id"]):
					fts.append([f["id"], Srd.label("feat", f["id"], f["name"])])
			if not ch["options"].has("versatile_feat"):
				ch["options"]["versatile_feat"] = "alert"
			content.add_child(_option_button(fts, str(ch["options"]["versatile_feat"]), func(v): ch["options"]["versatile_feat"] = v; _changed()))
	if not sc.has("skillful") and ch["species_id"] == "human":
		sc["skillful"] = "perception"


func _default_bonus(bid: String) -> Dictionary:
	var abs: Array = Srd.backgrounds[bid]["abilities"]
	return {abs[0]: 2, abs[1]: 1}


# ---------------------------------------------------------------- 3. atributos

func _page_scores() -> void:
	content.add_child(_h("Atributos"))
	content.add_child(_option_button([["standard", "Conjunto padrão (15, 14, 13, 12, 10, 8)"], ["point_buy", "Compra de pontos (27)"], ["roll", "Rolar 4d6 e descartar o menor"]], str(ch["method"]), func(v): ch["method"] = v; _reset_scores(); _render()))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	var base: Dictionary = ch["base_scores"]
	for ab in Rules.ABILITIES:
		grid.add_child(_p("%s (%s)" % [Srd.ability_name(ab), Srd.ability_abbr(ab)], 17, false))
		var sb := SpinBox.new()
		sb.min_value = 3 if ch["method"] == "roll" else 8
		sb.max_value = 18 if ch["method"] == "roll" else 15
		sb.value = int(base.get(ab, 10))
		sb.value_changed.connect(func(v): base[ab] = int(v); _changed())
		grid.add_child(sb)
		var bonus := int(ch["bg_bonus"].get(ab, 0))
		grid.add_child(_p(("+%d do antecedente" % bonus) if bonus > 0 else "", 15))
		var total := int(base.get(ab, 10)) + bonus
		grid.add_child(_p("= %d (%+d)" % [total, Rules.mod(total)], 17, false))
	content.add_child(grid)
	if ch["method"] == "point_buy":
		var cost := 0
		for ab in base:
			cost += int(Srd.tables["point_buy"].get(str(clampi(int(base[ab]), 8, 15)), 0))
		content.add_child(_p("Pontos gastos: %d de %d." % [cost, int(ch.get("point_budget", 27))], 17, false))
	elif ch["method"] == "standard":
		content.add_child(_p("Use cada valor do conjunto uma vez: 15, 14, 13, 12, 10 e 8.", 16))
	else:
		var b := Button.new()
		b.text = "Rolar de novo"
		b.pressed.connect(func(): _roll_scores(); _render())
		content.add_child(b)
		if not _rolled.is_empty():
			content.add_child(_p("Rolagens: %s. Distribua como quiser." % ", ".join(PackedStringArray(_rolled.map(func(x): return str(x))))))
	content.add_child(_h("Bônus do antecedente", 18))
	var bg: Dictionary = Srd.backgrounds[ch["background_id"]]
	content.add_child(_p("Escolha +2 em um e +1 em outro, ou +1 nos três: %s." % ", ".join(PackedStringArray(bg["abilities"].map(func(a): return Srd.ability_name(a))))))
	var opts: Array = []
	var a3: Array = bg["abilities"]
	for i in 3:
		for j in 3:
			if i != j:
				opts.append(["%s2_%s1" % [a3[i], a3[j]], "+2 %s, +1 %s" % [Srd.ability_abbr(a3[i]), Srd.ability_abbr(a3[j])]])
	opts.append(["all1", "+1 em %s, %s e %s" % [Srd.ability_abbr(a3[0]), Srd.ability_abbr(a3[1]), Srd.ability_abbr(a3[2])]])
	var cur := "all1"
	for k in ch["bg_bonus"]:
		if int(ch["bg_bonus"][k]) == 2:
			for k2 in ch["bg_bonus"]:
				if int(ch["bg_bonus"][k2]) == 1:
					cur = "%s2_%s1" % [k, k2]
	content.add_child(_option_button(opts, cur, func(v): _set_bonus(v, a3); _render()))


func _set_bonus(code: String, a3: Array) -> void:
	if code == "all1":
		ch["bg_bonus"] = {a3[0]: 1, a3[1]: 1, a3[2]: 1}
	else:
		var parts := code.split("_")
		ch["bg_bonus"] = {parts[0].substr(0, 3): 2, parts[1].substr(0, 3): 1}


func _reset_scores() -> void:
	if ch["method"] == "standard":
		ch["base_scores"] = _standard_for(str(_first()["class_id"]))
	elif ch["method"] == "point_buy":
		ch["base_scores"] = {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}
	else:
		_roll_scores()


## Conjunto padrão distribuído pelos atributos principais da classe.
func _standard_for(cid: String) -> Dictionary:
	var prim: Array = Srd.classes[cid]["primary"]
	var pref: Array = prim.duplicate()
	for ab in ["con", "dex", "wis", "str", "cha", "int"]:
		if not ab in pref:
			pref.append(ab)
	var vals := [15, 14, 13, 12, 10, 8]
	var out := {}
	for i in 6:
		out[pref[i]] = vals[i]
	return out


func _roll_scores() -> void:
	_rolled.clear()
	var base := {}
	for ab in Rules.ABILITIES:
		var r: Array = [Rules.d(6), Rules.d(6), Rules.d(6), Rules.d(6)]
		r.sort()
		var v: int = r[1] + r[2] + r[3]
		_rolled.append(v)
		base[ab] = v
	ch["base_scores"] = base


# ---------------------------------------------------------------- 4. perícias e equipamento

func _page_skills_equipment() -> void:
	var cls := _cls()
	var bg: Dictionary = Srd.backgrounds[ch["background_id"]]
	var locked: Array = bg["skills"].duplicate()
	content.add_child(_h("Perícias da classe"))
	content.add_child(_p("Escolha %d. As do antecedente (%s) já vêm marcadas." % [int(cls["skills"]["choose"]), ", ".join(PackedStringArray(locked.map(func(s): return Srd.skill_name(s))))]))
	var options: Array = cls["skills"]["from"]
	content.add_child(_checklist(options, ch["skills"], int(cls["skills"]["choose"]), func(s): return Srd.skill_name(s), locked))
	var exp_n := _expertise_count()
	if exp_n > 0:
		content.add_child(_h("Especialização (dobra a proficiência)", 18))
		var profs: Array = []
		for s in locked + ch["skills"]:
			if not s in profs:
				profs.append(s)
		content.add_child(_checklist(profs, ch["expertise"], exp_n, func(s): return Srd.skill_name(s)))
	content.add_child(_h("Equipamento inicial"))
	var eq_items: Array = []
	for opt in cls["equipment"]:
		eq_items.append([opt["option"], _equip_text(opt)])
	content.add_child(_option_button(eq_items, str(ch["equipment_option"]), func(v): ch["equipment_option"] = v; _changed()))
	var bg_items: Array = []
	for opt in bg["equipment"]:
		bg_items.append([opt["option"], "Antecedente: " + _equip_text(opt)])
	content.add_child(_option_button(bg_items, str(ch["bg_equipment_option"]), func(v): ch["bg_equipment_option"] = v; _changed()))


func _equip_text(opt: Dictionary) -> String:
	var parts := PackedStringArray()
	for it in opt["items"]:
		var f := Srd.find_item(str(it["item"]))
		var nm: String = Srd.label(Srd.item_kind(f), f["id"], f["name"]) if not f.is_empty() else str(it["item"])
		parts.append(("%d %s" % [int(it["qty"]), nm]) if int(it["qty"]) > 1 else nm)
	if int(opt["gp"]) > 0:
		parts.append("%d %s" % [int(opt["gp"]), Srd.currency()])
	return "(%s) %s" % [opt["option"], ", ".join(parts)]


func _expertise_count() -> int:
	var n := 0
	for k in ch["classes"]:
		var lv := int(k["level"])
		match str(k["class_id"]):
			"rogue":
				n += 2 + (2 if lv >= 6 else 0)
			"bard":
				n += (2 if lv >= 2 else 0) + (2 if lv >= 9 else 0)
			"ranger":
				n += (1 if lv >= 2 else 0) + (2 if lv >= 9 else 0)
			"wizard":
				n += 1 if lv >= 2 else 0
	return n


# ---------------------------------------------------------------- 5. magias e opções

func _page_options(level_mode: bool) -> void:
	var o: Dictionary = ch["options"]
	var shown := false
	for k in ch["classes"]:
		var cid: String = k["class_id"]
		var lv := int(k["level"])
		var before := 0
		if level_mode:
			for k0 in base_ch["classes"]:
				if k0["class_id"] == cid:
					before = int(k0["level"])
			if before == lv:
				continue
		var title := "%s nível %d" % [Srd.label("class", cid), lv]
		content.add_child(_h(title))
		shown = true
		if lv >= 3 and str(k.get("subclass_id", "")) == "":
			content.add_child(_p("Subclasse:", 16, false))
			var subs: Array = []
			for s in Srd.classes[cid]["subclasses"]:
				subs.append([s["id"], Srd.label("subclass", s["id"], s["name"])])
			k["subclass_id"] = subs[0][0]
			content.add_child(_option_button(subs, str(k["subclass_id"]), func(v): k["subclass_id"] = v; _changed()))
		_class_options(cid, lv, o)
		_spell_options(cid, lv)
	_asi_options(level_mode)
	if level_mode:
		content.add_child(_h("Pontos de vida", 18))
		var hd := int(Srd.classes[level_class]["hit_die"])
		var rolls: Array = ch.get("hp_rolls", [])
		content.add_child(_option_button([["fixed", "Média fixa: %d + Con" % (hd / 2 + 1)], ["roll", "Rolar 1d%d + Con" % hd]], "roll" if ch.get("_rolled_hp", false) else "fixed", func(v): _hp_choice(v, hd); _render()))
		if ch.get("_rolled_hp", false):
			content.add_child(_p("Rolou %d." % int(rolls[rolls.size() - 1]), 17, false))
	if not shown and not level_mode:
		content.add_child(_p("Nada a escolher para esta classe neste nível.", 18))


func _hp_choice(v: String, hd: int) -> void:
	var rolls: Array = base_ch.get("hp_rolls", []).duplicate()
	var total_before := CharBuilder.level_of(base_ch)
	# Preenche com média fixa os níveis anteriores sem rolagem registrada
	while rolls.size() < total_before - 1:
		rolls.append(hd / 2 + 1)
	if v == "roll":
		rolls.append(Rules.d(hd))
		ch["_rolled_hp"] = true
	else:
		ch.erase("_rolled_hp")
	ch["hp_rolls"] = rolls if v == "roll" else base_ch.get("hp_rolls", []).duplicate()


func _class_options(cid: String, lv: int, o: Dictionary) -> void:
	var fs_feats: Array = []
	for f in Srd.feats.values():
		if f["category"] == "fighting_style":
			fs_feats.append([f["id"], Srd.label("feat", f["id"], f["name"])])
	match cid:
		"fighter":
			content.add_child(_p("Estilo de Luta:", 16, false))
			if not o.has("fighting_style"):
				o["fighting_style"] = "defense"
			content.add_child(_option_button(fs_feats, str(o["fighting_style"]), func(v): o["fighting_style"] = v; _changed()))
			_mastery_picker(o, Srd.class_value(cid, lv, "weapon_mastery"))
		"barbarian":
			_mastery_picker(o, Srd.class_value(cid, lv, "weapon_mastery"))
		"paladin", "ranger":
			if lv >= 2:
				content.add_child(_p("Estilo de Luta:", 16, false))
				if not o.has("fighting_style"):
					o["fighting_style"] = "defense" if cid == "paladin" else "archery"
				content.add_child(_option_button(fs_feats, str(o["fighting_style"]), func(v): o["fighting_style"] = v; _changed()))
			_mastery_picker(o, 2)
			if cid == "ranger" and lv >= 3:
				if not o.has("hunters_prey"):
					o["hunters_prey"] = "colossus_slayer"
				content.add_child(_option_button([["colossus_slayer", "Matador de Colossos (+1d8 em alvo ferido)"], ["horde_breaker", "Quebra-Hordas (ataque extra em vizinho)"]], str(o["hunters_prey"]), func(v): o["hunters_prey"] = v; _changed()))
		"rogue":
			_mastery_picker(o, 2)
		"cleric":
			if not o.has("divine_order"):
				o["divine_order"] = "protector"
			content.add_child(_p("Ordem Divina:", 16, false))
			content.add_child(_option_button([["protector", "Protetor: armas marciais e armadura pesada"], ["thaumaturge", "Taumaturgo: truque extra e bônus em Arcanismo/Religião"]], str(o["divine_order"]), func(v): o["divine_order"] = v; _changed()))
			if lv >= 7:
				if not o.has("blessed_strikes"):
					o["blessed_strikes"] = "divine_strike"
				content.add_child(_option_button([["divine_strike", "Golpe Divino (+1d8 com arma)"], ["potent_spellcasting", "Conjuração Potente (+Sab nos truques)"]], str(o["blessed_strikes"]), func(v): o["blessed_strikes"] = v; _changed()))
		"druid":
			if not o.has("primal_order"):
				o["primal_order"] = "warden"
			content.add_child(_p("Ordem Primitiva:", 16, false))
			content.add_child(_option_button([["warden", "Guardião: armas marciais e armadura média"], ["magician", "Mágico: truque extra e bônus em Arcanismo/Natureza"]], str(o["primal_order"]), func(v): o["primal_order"] = v; _changed()))
			if lv >= 2:
				var max_cr := 0.25 if lv < 4 else (0.5 if lv < 8 else 1.0)
				var n := 4 if lv < 4 else (6 if lv < 8 else 8)
				var beasts: Array = []
				for m in Srd.monsters.values():
					if m.get("source", "") == "animals" and _cr(str(m["cr"])) <= max_cr and (lv >= 8 or not str(m.get("speed_text", "")).contains("Fly")):
						beasts.append(m["id"])
				beasts.sort()
				if not o.has("beast_forms"):
					o["beast_forms"] = ["wolf", "rat", "spider", "riding_horse"].filter(func(b): return b in beasts)
				content.add_child(_p("Formas Selvagens conhecidas (%d, ND até %s):" % [n, str(max_cr).replace("0.25", "1/4").replace("0.5", "1/2")], 16, false))
				content.add_child(_checklist(beasts, o["beast_forms"], n, func(b): return Srd.label("monster", b)))
			if lv >= 3 and _sub_of(cid) == "circle_of_the_land":
				if not o.has("land_type"):
					o["land_type"] = "temperate"
				content.add_child(_option_button([["arid", "Árida"], ["polar", "Polar"], ["temperate", "Temperada"], ["tropical", "Tropical"]], str(o["land_type"]), func(v): o["land_type"] = v; _changed()))
			if lv >= 7:
				if not o.has("elemental_fury"):
					o["elemental_fury"] = "primal_strike"
				content.add_child(_option_button([["primal_strike", "Golpe Primal (+1d8 elemental)"], ["potent_spellcasting", "Conjuração Potente (+Sab nos truques)"]], str(o["elemental_fury"]), func(v): o["elemental_fury"] = v; _changed()))
		"sorcerer":
			if lv >= 2:
				var n2 := 2 + (2 if lv >= 10 else 0) + (2 if lv >= 17 else 0)
				if not o.has("metamagic"):
					o["metamagic"] = []
				var mm: Array = Srd.classes["sorcerer"]["options"]["metamagic"].map(func(x): return x["id"])
				content.add_child(_p("Metamagia (%d):" % n2, 16, false))
				content.add_child(_checklist(mm, o["metamagic"], n2, func(x): return Srd.label("feature", x)))
			if lv >= 6 and _sub_of(cid) == "draconic_sorcery":
				if not o.has("elemental_affinity"):
					o["elemental_affinity"] = "fire"
				content.add_child(_option_button([["acid", "Ácido"], ["cold", "Frio"], ["fire", "Fogo"], ["lightning", "Elétrico"], ["poison", "Veneno"]], str(o["elemental_affinity"]), func(v): o["elemental_affinity"] = v; _changed()))
		"warlock":
			var n3 := Srd.class_value("warlock", lv, "eldritch_invocations")
			if not o.has("invocations"):
				o["invocations"] = []
			var inv: Array = []
			for x in Srd.classes["warlock"]["options"]["eldritch_invocation"]:
				var pre: String = x["prerequisite"]
				var need := 0
				var m := RegEx.create_from_string("Level (\\d+)\\+").search(pre)
				if m:
					need = int(m.get_string(1))
				if lv >= need:
					inv.append(x["id"])
			content.add_child(_p("Invocações Místicas (%d):" % n3, 16, false))
			content.add_child(_checklist(inv, o["invocations"], n3, func(x): return Srd.label("feature", x)))


func _sub_of(cid: String) -> String:
	for k in ch["classes"]:
		if k["class_id"] == cid:
			return str(k.get("subclass_id", ""))
	return ""


func _cr(s: String) -> float:
	if s.contains("/"):
		var p := s.split("/")
		return float(p[0]) / float(p[1])
	return float(s)


func _mastery_picker(o: Dictionary, n: int) -> void:
	if n <= 0:
		return
	if not o.has("weapon_masteries"):
		o["weapon_masteries"] = []
	var ws: Array = Srd.weapons.keys()
	ws.sort_custom(func(a, b): return Srd.label("weapon", a) < Srd.label("weapon", b))
	content.add_child(_p("Maestria em Armas (%d): escolha as armas cujas propriedades de maestria você usa." % n, 16, false))
	content.add_child(_checklist(ws, o["weapon_masteries"], n, func(w): return "%s (%s)" % [Srd.label("weapon", w), Srd.label("property", Srd.weapons[w]["mastery"])]))


func _spell_options(cid: String, lv: int) -> void:
	if not CharBuilder.CASTER.has(cid):
		return
	var n_cantrips := Srd.class_value(cid, lv, "cantrips")
	if (cid == "cleric" and ch["options"].get("divine_order", "") == "thaumaturge") or (cid == "druid" and ch["options"].get("primal_order", "") == "magician"):
		n_cantrips += 1
	var n_prep := Srd.class_value(cid, lv, "prepared_spells")
	var max_lvl := 0
	for l in range(1, 10):
		if Srd.class_value(cid, lv, "slot_%d" % l) > 0:
			max_lvl = l
	if cid == "warlock":
		max_lvl = Srd.class_value(cid, lv, "slot_level")
	if n_cantrips > 0:
		var cants := Srd.spells_for_class(cid, 0)
		cants.sort_custom(func(a, b): return Srd.label("spell", a) < Srd.label("spell", b))
		content.add_child(_p("Truques (%d):" % n_cantrips, 16, false))
		content.add_child(_checklist(cants, ch["cantrips"], n_cantrips, func(s): return Srd.label("spell", s)))
	if n_prep > 0 and max_lvl > 0:
		var pool: Array = []
		var always: Array = CharBuilder.build(ch).get("spellcasting", {}).get("always", [])
		for l in range(1, max_lvl + 1):
			pool += Srd.spells_for_class(cid, l).filter(func(x): return not x in always)
		for x in always:
			ch["spells"].erase(x)
		pool.sort_custom(func(a, b): return _spell_key(a) < _spell_key(b))
		content.add_child(_p("Magias preparadas (%d, até o nível %d):" % [n_prep, max_lvl], 16, false))
		content.add_child(_checklist(pool, ch["spells"], n_prep, func(s): return "%s (%d)" % [Srd.label("spell", s), int(Srd.spells[s]["level"])]))


func _spell_key(s: String) -> String:
	return "%d %s" % [int(Srd.spells[s]["level"]), Srd.label("spell", s)]


func _asi_options(level_mode: bool) -> void:
	## Aumento de Atributo / talento em cada nível de ASI alcançado (por classe).
	var feats: Array = ch["feats"]
	var slots: Array = []
	for k in ch["classes"]:
		var before := 0
		if level_mode:
			for k0 in base_ch["classes"]:
				if k0["class_id"] == k["class_id"]:
					before = int(k0["level"])
		for l in CharBuilder.asi_levels(str(k["class_id"])):
			if int(l) <= int(k["level"]) and int(l) > before:
				slots.append("%s:%d" % [k["class_id"], l])
	if slots.is_empty():
		return
	content.add_child(_h("Aumento de atributo ou talento", 18))
	var general: Array = [["asi_2", "+2 em um atributo"], ["asi_11", "+1 em dois atributos"]]
	for f in Srd.feats.values():
		if f["category"] in ["general", "fighting_style"] and f["id"] != "ability_score_improvement" and Srd.allowed("feat", f["id"]):
			general.append([f["id"], "Talento: " + Srd.label("feat", f["id"], f["name"])])
	for f in Srd.feats.values():
		if f["category"] == "epic_boon":
			general.append([f["id"], "Dádiva Épica: " + Srd.label("feat", f["id"], f["name"])])
	for slot in slots:
		var entry: Dictionary = {}
		for f in feats:
			if f.get("slot", "") == slot:
				entry = f
		if entry.is_empty():
			entry = {"slot": slot, "id": "ability_score_improvement", "level": int(slot.split(":")[1]), "scores": {_best_ab(): 2}, "kind": "asi_2"}
			feats.append(entry)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_p("%s %s:" % [Srd.label("class", slot.split(":")[0]), slot.split(":")[1]], 16, false))
		row.add_child(_option_button(general, str(entry.get("kind", entry["id"])), func(v): _set_asi(entry, v); _render()))
		var ab_items: Array = Rules.ABILITIES.map(func(a): return [a, Srd.ability_abbr(a)])
		var keys: Array = entry.get("scores", {}).keys()
		if str(entry.get("kind", "")) == "asi_2":
			row.add_child(_option_button(ab_items, str(keys[0]) if not keys.is_empty() else "str", func(v): entry["scores"] = {v: 2}; _changed()))
		elif str(entry.get("kind", "")) == "asi_11":
			row.add_child(_option_button(ab_items, str(keys[0]) if keys.size() > 0 else "str", func(v): _set_11(entry, 0, v)))
			row.add_child(_option_button(ab_items, str(keys[1]) if keys.size() > 1 else "con", func(v): _set_11(entry, 1, v)))
		content.add_child(row)


func _best_ab() -> String:
	var prim: Array = _cls()["primary"]
	return str(prim[0]) if not prim.is_empty() else "str"


func _set_asi(entry: Dictionary, v: String) -> void:
	entry["kind"] = v
	if v == "asi_2":
		entry["id"] = "ability_score_improvement"
		entry["scores"] = {_best_ab(): 2}
	elif v == "asi_11":
		entry["id"] = "ability_score_improvement"
		entry["scores"] = {_best_ab(): 1, "con": 1}
	else:
		entry["id"] = v
		entry["scores"] = {}
		if v == "grappler":
			entry["scores"] = {"str": 1}
		elif v.begins_with("boon_"):
			entry["scores"] = {_best_ab(): 1}
			ch["epic_cap"] = 1


func _set_11(entry: Dictionary, idx: int, v: String) -> void:
	var keys: Array = entry["scores"].keys()
	while keys.size() < 2:
		keys.append("con" if not "con" in keys else "dex")
	keys[idx] = v
	if keys[0] == keys[1]:
		entry["scores"] = {keys[0]: 2}
	else:
		entry["scores"] = {keys[0]: 1, keys[1]: 1}
	_changed()


# ---------------------------------------------------------------- 6. detalhes

func _page_details() -> void:
	content.add_child(_h("Detalhes"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	for f in [["name", "Nome"], ["player", "Jogador"]]:
		grid.add_child(_p(f[1], 17, false))
		var le := LineEdit.new()
		le.text = str(ch.get(f[0], ""))
		le.custom_minimum_size.x = 380
		le.text_changed.connect(func(t): ch[f[0]] = t; _changed())
		grid.add_child(le)
	grid.add_child(_p("Tendência", 17, false))
	var al: Array = [["", "Sem tendência definida"]]
	for a in ALIGNMENTS:
		al.append([a, a])
	grid.add_child(_option_button(al, str(ch.get("alignment", "")), func(v): ch["alignment"] = v))
	grid.add_child(_p("Cor do token", 17, false))
	var colors := HBoxContainer.new()
	for col in COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		var st := UiTheme.box(Color(col), 17, 3 if ch.get("color", "") == col else 1, UiTheme.INK if ch.get("color", "") == col else Color(UiTheme.INK, 0.3), 0)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.pressed.connect(func(): ch["color"] = col; _render())
		colors.add_child(b)
	grid.add_child(colors)
	content.add_child(grid)
	var pr: Dictionary = ch["profile"]
	for f in [["traits", "Traços de personalidade"], ["ideals", "Ideais"], ["bonds", "Vínculos"], ["flaws", "Defeitos"], ["bio", "Biografia"]]:
		content.add_child(_p(f[1], 16, false))
		var te := TextEdit.new()
		te.text = str(pr.get(f[0], ""))
		te.custom_minimum_size = Vector2(0, 70 if f[0] != "bio" else 130)
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.text_changed.connect(func(): pr[f[0]] = te.text)
		content.add_child(te)
	content.add_child(_p("Retrato e token: depois de criar, abra a ficha na aba Aparência e efeitos.", 15))


# ---------------------------------------------------------------- nível (modo level)

func _page_level_class() -> void:
	var c: Dictionary = {}
	for p in Game.party:
		if p["choices"] == base_ch or p["choices"].get("name", "") == base_ch.get("name", ""):
			c = p
	content.add_child(_h("Em qual classe ganhar o nível?"))
	content.add_child(_p("Continuar na mesma classe é o normal. Multiclasse pede 13 ou mais no atributo principal da classe atual e da nova."))
	var items: Array = []
	for cid in Srd.list("class"):
		var current_lv := 0
		for k in base_ch["classes"]:
			if k["class_id"] == cid:
				current_lv = int(k["level"])
		var ok := current_lv > 0 or _can_multiclass(cid)
		if not ok:
			continue
		items.append([cid, Srd.label("class", cid), ("nível %d → %d" % [current_lv, current_lv + 1]) if current_lv > 0 else "nova classe (multiclasse)"])
	content.add_child(_card_grid(items, level_class, func(id): level_class = id; _apply_level_class(); _render()))
	var cls: Dictionary = Srd.classes[level_class]
	var new_lv := 0
	for k in ch["classes"]:
		if k["class_id"] == level_class:
			new_lv = int(k["level"])
	var fl := _section_text("Novidades no nível %d de %s" % [new_lv, Srd.label("class", level_class)])
	for f in cls["features"]:
		if int(f["level"]) == new_lv:
			fl.add_child(_p("· " + Srd.label("feature", f["id"], f["name"]), 16, false))
	var sub := _sub_of(level_class)
	for s in cls["subclasses"]:
		if s["id"] == sub:
			for f in s["features"]:
				if int(f["level"]) == new_lv:
					fl.add_child(_p("· " + Srd.label("feature", f["id"], f["name"]), 16, false))
	content.add_child(fl)


func _can_multiclass(cid: String) -> bool:
	var c := CharBuilder.build(base_ch)
	var ok_new := false
	for ab in Srd.classes[cid]["primary"]:
		if Rules.score(c, ab) >= 13:
			ok_new = true
	var ok_old := true
	for k in base_ch["classes"]:
		var any := false
		for ab in Srd.classes[k["class_id"]]["primary"]:
			if Rules.score(c, ab) >= 13:
				any = true
		ok_old = ok_old and any
	return ok_new and ok_old


# ---------------------------------------------------------------- prévia

func _errors() -> Array:
	if mode == "level":
		return []
	var errs := CharBuilder.validate(ch)
	return errs


func _refresh_preview() -> void:
	for x in preview.get_children():
		x.queue_free()
	var c := CharBuilder.build(ch)
	preview.add_child(UiTheme.label(str(ch.get("name", "")) if str(ch.get("name", "")) != "" else "(sem nome)", 24, UiTheme.INK, UiTheme.serif()))
	preview.add_child(_p("%s, %s" % [c["class"], c["species"]], 16, false))
	if c.get("subclass_id", "") != "":
		preview.add_child(_p(Srd.label("subclass", c["subclass_id"]), 15))
	preview.add_child(_p("PV %d · CA %d · Desloc. %s" % [c["hp_max"], Rules.ac(c), Game.fmt_m(Rules.speed_m(c))], 17, false))
	preview.add_child(_p("Iniciativa %+d · Proficiência %+d · Percepção passiva %d" % [Rules.initiative_bonus(c), Rules.pb(c), Rules.passive(c, "perception")], 15))
	var sc := PackedStringArray()
	for ab in Rules.ABILITIES:
		sc.append("%s %d (%+d)" % [Srd.ability_abbr(ab), Rules.score(c, ab), Rules.amod(c, ab)])
	preview.add_child(_p(" · ".join(sc), 15, false))
	var sv := PackedStringArray()
	for ab in c["save_prof"]:
		sv.append(Srd.ability_abbr(ab))
	preview.add_child(_p("Salvaguardas: " + ", ".join(sv), 15))
	var sk := PackedStringArray()
	for s in c["skill_prof"]:
		sk.append("%s %+d" % [Srd.skill_name(s), Rules.skill_bonus(c, s)])
	preview.add_child(_p("Perícias: " + ", ".join(sk), 15))
	var at := PackedStringArray()
	for a in c["attacks"]:
		at.append("%s %+d (%s)" % [a["name"], int(a["to_hit"]), a["damage"]])
	preview.add_child(_p("Ataques: " + "; ".join(at), 15))
	if not c.get("spellcasting", {}).is_empty():
		var slots := PackedStringArray()
		for l in c["slots"]:
			slots.append("%s×%d" % [l, int(c["slots"][l]["max"])])
		if not c.get("pact", {}).is_empty():
			slots.append("pacto %d×nível %d" % [int(c["pact"]["max"]), int(c["pact"]["level"])])
		preview.add_child(_p("Magia: CD %d, ataque %+d. Espaços: %s" % [Rules.spell_dc(c), Rules.spell_attack(c), ", ".join(slots)], 15))
	var res := PackedStringArray()
	for rid in c["resources"]:
		res.append("%s %d" % [c["resources"][rid]["name"], int(c["resources"][rid]["max"])])
	if not res.is_empty():
		preview.add_child(_p("Recursos: " + ", ".join(res), 15))
	var errs := _errors()
	errors_l.text = "" if errs.is_empty() else ("Falta: " + " ".join(errs))
