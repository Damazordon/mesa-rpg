class_name RoomSetup
extends Control
## Tela de criação de sala (mesa local: um PC monta tudo).
##
## Cinco etapas, na ordem de uma mesa de verdade: o mundo existe antes dos personagens.
##   1. Sala: nome, tema, história, quantas pessoas vão jogar e as regras da mesa.
##   2. Aventura: a IA cria a história e a lore pública; o motor confere monstros e XP.
##   3. Arte: pedidos de imagem (mapa de cada lugar, cada criatura) para o jogador gerar por fora
##      e importar. Os pedidos não contam a trama. Etapa opcional.
##   4. Jogadores: com a lore à vista, cada um monta seu personagem.
##   5. Lore: a história é reescrita com o grupo dentro dela, escrita na frente de todos.
##
## Ao jogar, Game.create_room grava a aventura e o grupo e emite room_created.

signal room_created
signal canceled

const STEPS := ["Sala", "Aventura", "Arte", "Jogadores", "Lore"]
const STORY_ROWS_H := 170.0

var cfg := {}
var step := 0
var sel := 0
var result := {}
var generating := false
var lore_done := false
var art_msg := ""
var book: LoreBook
var file_dialog: FileDialog
var _pending_art := {}

var card: PanelContainer
var title_l: Label
var continue_btn: Button
var steps_box: VBoxContainer
var content: VBoxContainer
var errors_l: Label
var back_btn: Button
var next_btn: Button
var creator: CharacterCreator
var gen: AdventureGen

var story_count_l: Label
var status_l: Label
var list_box: VBoxContainer
var edit_box: VBoxContainer
var name_btns: Array = []

var _prev_theme := {}
var _status := ""
var _t0 := 0.0


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	var bg := ColorRect.new()
	bg.color = UiTheme.FELT_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.custom_minimum_size = Vector2(1500, 900)
	card.add_theme_stylebox_override("panel", UiTheme.paper_box(10, 22))
	center.add_child(card)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	card.add_child(root)

	var head := HBoxContainer.new()
	title_l = UiTheme.label("Nova sala", 30, UiTheme.INK, UiTheme.serif())
	head.add_child(title_l)
	head.add_child(UiTheme.spacer(false))
	continue_btn = Button.new()
	continue_btn.pressed.connect(_cancel)
	head.add_child(continue_btn)
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
	next_btn.custom_minimum_size.x = 180
	next_btn.pressed.connect(_on_next)
	foot.add_child(next_btn)

	creator = CharacterCreator.new()
	add_child(creator)
	creator.build()
	creator.finished.connect(_on_creator_done)
	gen = AdventureGen.new()
	add_child(gen)
	gen.status.connect(func(t): _status = t)


# ---------------------------------------------------------------- abrir e fechar

## boot = true na abertura do jogo: o botão do topo vira "Continuar mesa atual".
func open(boot := false) -> void:
	_prev_theme = Srd.theme
	cfg = RoomBuilder.new_config()
	step = 0
	sel = 0
	result = {}
	generating = false
	lore_done = false
	art_msg = ""
	_apply_theme(str(cfg["theme"]))
	continue_btn.visible = not Game.party.is_empty()
	continue_btn.text = "Continuar mesa atual" if boot else "Cancelar"
	errors_l.text = ""
	visible = true
	_render()


func _cancel() -> void:
	if generating:
		return
	Srd.set_theme(_prev_theme)
	visible = false
	canceled.emit()


func _apply_theme(id: String) -> void:
	var t := RoomBuilder.theme_by_id(id)
	if not t.is_empty():
		Srd.set_theme(t)
	for p in cfg.get("players", []):
		RoomBuilder.fit_player(p)


## Mudou a ficha de alguém: a aventura continua valendo, a lore reescrita não.
func _dirty() -> void:
	lore_done = false


## Mudou a sala: a aventura gerada não vale mais.
func _invalidate() -> void:
	result = {}
	lore_done = false


func _process(_delta: float) -> void:
	if generating and is_instance_valid(status_l):
		status_l.text = "%s  (%d s)" % [_status, int(Time.get_ticks_msec() / 1000.0 - _t0)]


# ---------------------------------------------------------------- navegação

func _errors_for(target: int) -> Array:
	var errs: Array = []
	if target >= 1:
		errs.append_array(RoomBuilder.config_errors(cfg))
	if target >= 2 and result.is_empty():
		errs.append("Gere a aventura antes de seguir: é dela que sai a lore que o grupo vai ler.")
	if target >= 4:
		var players: Array = cfg.get("players", [])
		for i in players.size():
			for e in RoomBuilder.player_errors(players[i]):
				errs.append("Jogador %d: %s" % [i + 1, str(e)])
	return errs


func _go(i: int) -> void:
	if generating:
		return
	i = clampi(i, 0, STEPS.size() - 1)
	if i > step:
		var errs := _errors_for(i)
		if not errs.is_empty():
			errors_l.text = "\n".join(PackedStringArray(errs))
			return
	errors_l.text = ""
	step = i
	if step == 3:
		RoomBuilder.ensure_players(cfg)
		sel = clampi(sel, 0, cfg["players"].size() - 1)
	_render()


func _on_next() -> void:
	if step < STEPS.size() - 1:
		_go(step + 1)
	else:
		_play()


func _render() -> void:
	for n in [steps_box, content]:
		for x in n.get_children():
			x.queue_free()
	name_btns.clear()
	status_l = null
	story_count_l = null
	for i in STEPS.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, STEPS[i]]
		b.toggle_mode = true
		b.button_pressed = i == step
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_go.bind(i))
		steps_box.add_child(b)
	back_btn.disabled = step == 0 or generating
	next_btn.text = "Próximo" if step < STEPS.size() - 1 else "Jogar"
	next_btn.disabled = generating or (step == STEPS.size() - 1 and (result.is_empty() or not lore_done))
	match step:
		0:
			_page_room()
		1:
			_page_generate()
		2:
			_page_art()
		3:
			_page_players()
		4:
			_page_lore()


# ---------------------------------------------------------------- utilitários de interface

func _h(text: String, size := 22) -> Label:
	return UiTheme.label(text, size, UiTheme.INK, UiTheme.serif() if size >= 22 else UiTheme.sans_bold())


func _p(text: String, size := 16, soft := true) -> Label:
	return UiTheme.wrap_label(text, size, UiTheme.INK_SOFT if soft else UiTheme.INK)


func _row(label: String, control: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	var l := _p(label, 17, false)
	l.size_flags_horizontal = Control.SIZE_FILL
	l.custom_minimum_size.x = 170
	r.add_child(l)
	r.add_child(control)
	return r


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 8)
	return g


func _line(text: String, width: float, on_change: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.custom_minimum_size.x = width
	le.text_changed.connect(on_change)
	return le


func _text(text: String, height: float, on_change: Callable) -> TextEdit:
	var te := TextEdit.new()
	te.text = text
	te.custom_minimum_size = Vector2(0, height)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.FELT_DEEP, 6, 1, UiTheme.WOOD_EDGE, 10))
	te.add_theme_stylebox_override("focus", UiTheme.box(UiTheme.FELT_DEEP, 6, 2, UiTheme.AMBER, 10))
	te.add_theme_color_override("font_color", UiTheme.BONE)
	te.add_theme_color_override("caret_color", UiTheme.AMBER)
	te.add_theme_font_size_override("font_size", 18)
	te.text_changed.connect(func(): on_change.call(te.text))
	return te


func _spin(value: int, lo: int, hi: int, on_change: Callable) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.value = value
	sb.value_changed.connect(on_change)
	return sb


## items: [[id, texto]]
func _opt(items: Array, selected: String, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	var idx := 0
	for i in items.size():
		ob.add_item(str(items[i][1]), i)
		if str(items[i][0]) == selected:
			idx = i
	ob.select(idx)
	ob.item_selected.connect(func(i): on_pick.call(items[i][0]))
	return ob


## items: [[id, título, subtítulo]]
func _card_grid(items: Array, selected: String, on_pick: Callable, cols := 2) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for it in items:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = str(it[0]) == selected
		b.custom_minimum_size = Vector2(560, 100)
		b.clip_text = true
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 12
		v.offset_top = 8
		v.offset_right = -10
		v.add_theme_constant_override("separation", 2)
		var t := UiTheme.label(str(it[1]), 20, UiTheme.BONE, UiTheme.sans_bold())
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		var s := UiTheme.wrap_label(str(it[2]), 14, UiTheme.BONE_SOFT)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(s)
		b.add_child(v)
		b.pressed.connect(func(): on_pick.call(it[0]))
		grid.add_child(b)
	return grid


func _swatch(col: String, size := 16.0, border := 1) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(size, size)
	pc.add_theme_stylebox_override("panel", UiTheme.box(Color(col), int(size / 2.0), border, UiTheme.INK, 0))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc


# ---------------------------------------------------------------- 1. sala

func _page_room() -> void:
	content.add_child(_h("A mesa"))
	content.add_child(_p("Escolha o tema e escreva a história. A IA monta a aventura a partir disso; o motor confere monstros, dificuldade e regras.", 16))
	content.add_child(_row("Nome da sala", _line(str(cfg["name"]), 460, _on_room_name)))

	content.add_child(_h("Tema", 20))
	var items: Array = []
	for t in RoomBuilder.themes():
		items.append([str(t["id"]), str(t.get("name", t["id"])), "%s\nTom: %s" % [str(t.get("description", "")), str(t.get("tone", ""))]])
	content.add_child(_card_grid(items, str(cfg["theme"]), _pick_theme, 2))

	content.add_child(_h("História", 20))
	content.add_child(_p("A IA usa este texto como premissa: quem pede ajuda, o que está em jogo, onde começa. Quanto mais específico, melhor a aventura.", 15))
	var te := _text(str(cfg["story"]), STORY_ROWS_H, _on_story)
	content.add_child(te)
	var srow := HBoxContainer.new()
	story_count_l = _p("", 15)
	srow.add_child(story_count_l)
	srow.add_child(UiTheme.spacer(false))
	var seed_btn := Button.new()
	seed_btn.text = "Sugerir uma ideia"
	seed_btn.tooltip_text = "Preenche a história com uma ideia do tema escolhido. Você pode editar depois."
	seed_btn.pressed.connect(_on_seed.bind(te))
	srow.add_child(seed_btn)
	content.add_child(srow)
	_count()

	content.add_child(_h("Regras da sala", 20))
	var g := _grid(4)
	g.add_child(_p("Nível inicial", 17, false))
	g.add_child(_spin(int(cfg["level"]), 1, RoomBuilder.MAX_LEVEL, _set_level))
	g.add_child(_p("Pontos de atributo", 17, false))
	var sb := _spin(int(cfg["budget"]), RoomBuilder.MIN_BUDGET, RoomBuilder.MAX_BUDGET, _set_budget)
	sb.tooltip_text = "Quantos pontos cada jogador distribui entre os seis atributos (padrão do livro: 27)."
	g.add_child(sb)
	g.add_child(_p("Dificuldade do encontro", 17, false))
	g.add_child(_opt(RoomBuilder.DIFFICULTIES, str(cfg["difficulty"]), _set_difficulty))
	g.add_child(_p("Mestre", 17, false))
	var lv_items: Array = []
	for id in ["calmo", "normal", "cinico"]:
		lv_items.append([id, str(Master.LEVELS[id]["label"])])
	g.add_child(_opt(lv_items, str(cfg["master_level"]), _set_master))
	g.add_child(_p("Subir de nível", 17, false))
	var mode_btn := _opt([["xp", "Por experiência"], ["marco", "Por marco de história"]], str(cfg["level_mode"]), _set_level_mode)
	mode_btn.tooltip_text = "Por experiência: só sobe com XP suficiente (a XP vem dos encontros). Por marco: você libera quando quiser."
	g.add_child(mode_btn)
	g.add_child(_p("Jogadores", 17, false))
	var pc_sb := _spin(int(cfg["player_count"]), 1, RoomBuilder.MAX_PLAYERS, _set_player_count)
	pc_sb.tooltip_text = "Quantas pessoas vão jogar. O orçamento dos encontros é calculado por aqui; as fichas vêm depois da lore."
	g.add_child(pc_sb)
	g.add_child(_p("Capítulos", 17, false))
	var ch_sb := _spin(int(cfg["chapters"]), 1, AdventureGen.MAX_CHAPTERS, _set_chapters)
	ch_sb.tooltip_text = "Encontros em sequência, formando um arco. Cada capítulo pesa mais que o anterior."
	g.add_child(ch_sb)
	g.add_child(_p("Descanso longo", 17, false))
	var rest_btn := _opt([["aventura", "Só nos pontos de descanso"], ["livre", "Quando o grupo quiser"]], str(cfg["rest_mode"]), _set_rest_mode)
	rest_btn.tooltip_text = "O desgaste entre capítulos é o que cria tensão. Descanso longo livre devolve tudo depois de cada luta e esvazia a dificuldade."
	g.add_child(rest_btn)
	content.add_child(g)
	if int(cfg["chapters"]) > 1:
		content.add_child(_p("Os capítulos sobem de peso: %s do orçamento base." % _ramp_text(), 14))
	content.add_child(_p("Nível 1 a %d. Níveis mais altos pedem escolhas extras (subclasse, aumento de atributo); use \"Ficha completa\" para ajustá-las." % RoomBuilder.MAX_LEVEL, 14))


func _on_room_name(t: String) -> void:
	cfg["name"] = t
	_invalidate()


func _on_story(t: String) -> void:
	cfg["story"] = t
	_invalidate()
	_count()


func _count() -> void:
	if story_count_l == null:
		return
	var n := str(cfg["story"]).strip_edges().length()
	story_count_l.text = "%d caracteres (mínimo %d)" % [n, RoomBuilder.MIN_STORY]


func _on_seed(te: TextEdit) -> void:
	var seeds := RoomBuilder.seeds(str(cfg["theme"]))
	var i := int(cfg["seed_i"]) % seeds.size()
	cfg["story"] = str(seeds[i])
	cfg["seed_i"] = i + 1
	te.text = str(cfg["story"])
	_invalidate()
	_count()


func _pick_theme(id: String) -> void:
	cfg["theme"] = id
	_apply_theme(id)
	_invalidate()
	_render()


func _set_level(v: float) -> void:
	cfg["level"] = int(v)
	for p in cfg.get("players", []):
		RoomBuilder.set_level(p, int(v))
	_invalidate()


func _set_budget(v: float) -> void:
	cfg["budget"] = int(v)
	for p in cfg.get("players", []):
		p["point_budget"] = int(v)
		if RoomBuilder.points_left(p) < 0:
			RoomBuilder.reset_scores(p)
	_invalidate()


func _set_difficulty(id: String) -> void:
	cfg["difficulty"] = id
	_invalidate()


func _set_master(id: String) -> void:
	cfg["master_level"] = id


func _set_level_mode(id: String) -> void:
	cfg["level_mode"] = id


func _set_chapters(v: float) -> void:
	cfg["chapters"] = int(v)
	_invalidate()
	_render()


func _set_rest_mode(id: String) -> void:
	cfg["rest_mode"] = id


func _set_player_count(v: float) -> void:
	cfg["player_count"] = int(v)
	_invalidate()


func _ramp_text() -> String:
	var parts := PackedStringArray()
	for i in int(cfg["chapters"]):
		parts.append("%d%%" % int(float(AdventureGen.CHAPTER_RAMP[mini(i, AdventureGen.CHAPTER_RAMP.size() - 1)]) * 100.0))
	return ", ".join(parts)


# ---------------------------------------------------------------- 2. jogadores

func _page_players() -> void:
	content.add_child(_h("A lore que todos leram"))
	content.add_child(_lore_panel(190))
	content.add_child(_p("Monte os personagens sabendo onde eles estão. Quem eles são entra na história na etapa seguinte.", 15))
	var sized := int(result.get("adventure", {}).get("player_count", 0))
	if sized > 0 and sized != cfg["players"].size():
		content.add_child(UiTheme.wrap_label("Atenção: os encontros foram calculados para %d jogador(es) e a mesa está com %d. Volte à etapa Aventura e gere de novo para reequilibrar." % [sized, cfg["players"].size()], 15, UiTheme.HP.darkened(0.25)))
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 22)
	content.add_child(wrap)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 270
	left.add_theme_constant_override("separation", 8)
	wrap.add_child(left)
	left.add_child(_h("Jogadores", 20))
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 6)
	left.add_child(list_box)
	var add_btn := Button.new()
	add_btn.text = "+ Adicionar jogador"
	add_btn.disabled = cfg["players"].size() >= RoomBuilder.MAX_PLAYERS
	add_btn.pressed.connect(_add_player)
	left.add_child(add_btn)
	var rm_btn := Button.new()
	rm_btn.text = "Remover este jogador"
	rm_btn.disabled = cfg["players"].size() <= 1
	rm_btn.pressed.connect(_remove_player)
	left.add_child(rm_btn)
	edit_box = VBoxContainer.new()
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_box.add_theme_constant_override("separation", 10)
	wrap.add_child(edit_box)
	sel = clampi(sel, 0, cfg["players"].size() - 1)
	_fill_list()
	_fill_editor()


func _player_title(i: int) -> String:
	var p: Dictionary = cfg["players"][i]
	var nm := str(p["name"]).strip_edges()
	return "%d. %s · %s" % [i + 1, nm if nm != "" else "(sem nome)", Srd.label("class", str(p["classes"][0]["class_id"]))]


func _fill_list() -> void:
	for x in list_box.get_children():
		x.queue_free()
	name_btns.clear()
	for i in cfg["players"].size():
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var sw := _swatch(str(cfg["players"][i]["color"]), 18.0)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(sw)
		var b := Button.new()
		b.text = _player_title(i)
		b.toggle_mode = true
		b.button_pressed = i == sel
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_select.bind(i))
		r.add_child(b)
		list_box.add_child(r)
		name_btns.append(b)


func _update_list_labels() -> void:
	for i in name_btns.size():
		if is_instance_valid(name_btns[i]):
			name_btns[i].text = _player_title(i)


func _select(i: int) -> void:
	sel = i
	_fill_list()
	_fill_editor()


func _add_player() -> void:
	if cfg["players"].size() >= RoomBuilder.MAX_PLAYERS:
		return
	cfg["players"].append(RoomBuilder.default_player(cfg["players"].size(), int(cfg["level"]), int(cfg["budget"])))
	RoomBuilder.fit_player(cfg["players"][cfg["players"].size() - 1])
	cfg["player_count"] = cfg["players"].size()
	sel = cfg["players"].size() - 1
	_dirty()
	_render()


func _remove_player() -> void:
	if cfg["players"].size() <= 1:
		return
	cfg["players"].remove_at(sel)
	cfg["player_count"] = cfg["players"].size()
	sel = clampi(sel, 0, cfg["players"].size() - 1)
	_dirty()
	_render()


func _fill_editor() -> void:
	for x in edit_box.get_children():
		x.queue_free()
	var ch: Dictionary = cfg["players"][sel]
	var first: Dictionary = ch["classes"][0]
	edit_box.add_child(_h("Jogador %d" % (sel + 1), 22))

	var g := _grid(2)
	g.add_child(_p("Jogador", 17, false))
	g.add_child(_line(str(ch["player"]), 320, _on_player_name.bind(ch)))
	g.add_child(_p("Personagem", 17, false))
	g.add_child(_line(str(ch["name"]), 320, _on_char_name.bind(ch)))
	var classes: Array = []
	for cid in Srd.list("class"):
		classes.append([cid, Srd.label("class", cid)])
	g.add_child(_p("Classe", 17, false))
	g.add_child(_opt(classes, str(first["class_id"]), _on_class.bind(ch)))
	var sps: Array = []
	for sid in Srd.list("species"):
		sps.append([sid, Srd.label("species", sid)])
	g.add_child(_p("Espécie", 17, false))
	g.add_child(_opt(sps, str(ch["species_id"]), _on_species.bind(ch)))
	var bgs: Array = []
	for bid in Srd.list("background"):
		bgs.append([bid, Srd.label("background", bid)])
	g.add_child(_p("Antecedente", 17, false))
	g.add_child(_opt(bgs, str(ch["background_id"]), _on_background.bind(ch)))
	g.add_child(_p("Token", 17, false))
	var tok := HBoxContainer.new()
	tok.add_theme_constant_override("separation", 6)
	var big := _swatch(str(ch["color"]), 44.0, 3)
	tok.add_child(big)
	for col in CharacterCreator.COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(32, 32)
		var on: bool = str(ch["color"]) == col
		var st := UiTheme.box(Color(col), 16, 3 if on else 1, UiTheme.INK if on else Color(UiTheme.INK, 0.3), 0)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("pressed", st)
		b.pressed.connect(_on_color.bind(col, ch))
		tok.add_child(b)
	g.add_child(tok)
	edit_box.add_child(g)

	_scores_block(ch)

	edit_box.add_child(_h("História do personagem", 20))
	edit_box.add_child(_p("A IA usa estes textos para amarrar o personagem à aventura.", 15))
	edit_box.add_child(_p("Origem em uma frase", 16, false))
	edit_box.add_child(_line(str(ch["profile"].get("background", "")), 640, _on_profile.bind(ch, "background")))
	edit_box.add_child(_p("História", 16, false))
	edit_box.add_child(_text(str(ch["profile"].get("bio", "")), 120, _on_profile.bind(ch, "bio")))
	edit_box.add_child(_p("Objetivo pessoal (vira uma missão no diário)", 16, false))
	edit_box.add_child(_line(str(ch["profile"].get("bonds", "")), 640, _on_profile.bind(ch, "bonds")))

	var pv := RoomBuilder.preview(ch)
	edit_box.add_child(_p("%s, %s · PV %d · CA %d · Iniciativa %+d" % [pv["class"], pv["species"], int(pv["hp_max"]), Rules.ac(pv), Rules.initiative_bonus(pv)], 16, false))
	var full := Button.new()
	full.text = "Ficha completa (perícias, magias, opções)"
	full.tooltip_text = "Abre o criador do SRD já com estas escolhas. O que você não escolher aqui é preenchido com padrões razoáveis."
	full.pressed.connect(_open_full.bind(ch))
	edit_box.add_child(full)


func _scores_block(ch: Dictionary) -> void:
	edit_box.add_child(_h("Habilidades", 20))
	if str(ch.get("method", "point_buy")) != "point_buy":
		edit_box.add_child(_p("Os atributos deste personagem vieram da ficha completa (conjunto padrão ou rolagem).", 15))
		var reset := Button.new()
		reset.text = "Voltar para a compra de pontos"
		reset.pressed.connect(_on_reset_scores.bind(ch))
		edit_box.add_child(reset)
		return
	var left := RoomBuilder.points_left(ch)
	edit_box.add_child(_p("Distribua os pontos: cada atributo vai de 8 a 15. Restam %d de %d." % [left, int(cfg["budget"])], 16, left == 0))
	var g := _grid(6)
	var base: Dictionary = ch["base_scores"]
	for ab in Rules.ABILITIES:
		var v := int(base[ab])
		var bonus := int(ch["bg_bonus"].get(ab, 0))
		var total := v + bonus
		g.add_child(_p("%s (%s)" % [Srd.ability_name(ab), Srd.ability_abbr(ab)], 17, false))
		var minus := Button.new()
		minus.text = "−"
		minus.disabled = not RoomBuilder.can_step(ch, ab, -1)
		minus.pressed.connect(_on_step.bind(ch, ab, -1))
		g.add_child(minus)
		var val := UiTheme.label(str(v), 22, UiTheme.INK, UiTheme.sans_bold())
		val.custom_minimum_size.x = 36
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_child(val)
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = not RoomBuilder.can_step(ch, ab, 1)
		plus.pressed.connect(_on_step.bind(ch, ab, 1))
		g.add_child(plus)
		g.add_child(_p(("+%d do antecedente" % bonus) if bonus > 0 else "", 15))
		g.add_child(_p("= %d (%+d)" % [total, Rules.mod(total)], 17, false))
	edit_box.add_child(g)
	edit_box.add_child(_p("Bônus do antecedente (+2 e +1, ou +1 em três):", 16, false))
	edit_box.add_child(_opt(RoomBuilder.bonus_options(str(ch["background_id"])), RoomBuilder.bonus_code(ch), _on_bonus.bind(ch)))


func _on_player_name(t: String, ch: Dictionary) -> void:
	ch["player"] = t
	_dirty()


func _on_char_name(t: String, ch: Dictionary) -> void:
	ch["name"] = t
	_dirty()
	_update_list_labels()


func _on_class(id: String, ch: Dictionary) -> void:
	ch["classes"][0]["class_id"] = id
	RoomBuilder.reset_class_picks(ch)
	_dirty()
	_fill_list()
	_fill_editor()


func _on_species(id: String, ch: Dictionary) -> void:
	ch["species_id"] = id
	ch["species_choice"] = {}
	ch["options"].erase("versatile_feat")
	_dirty()
	_fill_editor()


func _on_background(id: String, ch: Dictionary) -> void:
	ch["background_id"] = id
	ch["bg_bonus"] = RoomBuilder.default_bonus(id)
	ch["skills"] = []
	_dirty()
	_fill_editor()


func _on_color(col: String, ch: Dictionary) -> void:
	ch["color"] = col
	_dirty()
	_fill_list()
	_fill_editor()


func _on_step(ch: Dictionary, ab: String, dir: int) -> void:
	if RoomBuilder.can_step(ch, ab, dir):
		ch["base_scores"][ab] = int(ch["base_scores"][ab]) + dir
		_dirty()
	_fill_editor()


func _on_bonus(code: String, ch: Dictionary) -> void:
	RoomBuilder.apply_bonus(ch, code)
	_dirty()
	_fill_editor()


func _on_reset_scores(ch: Dictionary) -> void:
	RoomBuilder.reset_scores(ch)
	_dirty()
	_fill_editor()


func _on_profile(t: String, ch: Dictionary, key: String) -> void:
	ch["profile"][key] = t
	_dirty()


func _open_full(ch: Dictionary) -> void:
	var full := RoomBuilder.finalize_player(ch)
	full["point_budget"] = int(cfg["budget"])
	creator.open_edit(full, 3)


func _on_creator_done(new_ch: Dictionary) -> void:
	new_ch["point_budget"] = int(cfg["budget"])
	cfg["players"][sel] = new_ch
	_dirty()
	_fill_list()
	_fill_editor()


## A lore num quadro com rolagem, para caber junto de outra coisa na tela.
func _lore_panel(height: float) -> Control:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, height)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = false
	rt.fit_content = true
	rt.scroll_active = false
	rt.text = str(result.get("adventure", {}).get("lore", ""))
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", UiTheme.serif())
	rt.add_theme_font_size_override("normal_font_size", 18)
	rt.add_theme_color_override("default_color", UiTheme.INK)
	rt.add_theme_constant_override("line_separation", 4)
	sc.add_child(rt)
	return sc


# ---------------------------------------------------------------- 3. arte

func _page_art() -> void:
	content.add_child(_h("Arte da mesa"))
	content.add_child(_p("A IA diz de que imagens precisa e escreve o pedido. Gere por fora, à mão ou com a IA de imagem que você usar, e importe aqui. Pode pular: sem imagem, o jogo desenha o cenário e os tokens como sempre.", 16))
	content.add_child(_p("Os pedidos não contam a trama: sem nome próprio, sem número de capítulo e fora de ordem. Mas um pedido revela o assunto dele — se você quer ser surpreendido por completo, deixe outra pessoa gerar as imagens.", 15))
	if art_msg != "":
		content.add_child(UiTheme.wrap_label(art_msg, 16, UiTheme.HP.darkened(0.25)))
	var reqs: Array = result.get("art", [])
	if reqs.is_empty():
		content.add_child(_p("Esta aventura não pediu imagem nenhuma.", 17, false))
		return
	var done := 0
	for r in reqs:
		if ArtStore.has_image(str(r["kind"]), str(r["key"])):
			done += 1
	content.add_child(_p("%d de %d importadas." % [done, reqs.size()], 17, false))
	for r2 in reqs:
		content.add_child(_art_block(r2))


func _art_block(r: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.INK, 0.06), 8, 1, Color(UiTheme.INK, 0.18), 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	var has: bool = ArtStore.has_image(str(r["kind"]), str(r["key"]))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiTheme.label(str(r["label"]), 19, UiTheme.INK, UiTheme.sans_bold()))
	head.add_child(UiTheme.spacer(false))
	head.add_child(UiTheme.label("importada" if has else "pendente", 15,
		UiTheme.GOOD.darkened(0.35) if has else UiTheme.INK_SOFT, UiTheme.sans_bold()))
	v.add_child(head)
	var prompt := TextEdit.new()
	prompt.text = str(r["prompt"])
	prompt.custom_minimum_size = Vector2(0, 62)
	prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	prompt.editable = false
	prompt.add_theme_stylebox_override("read_only", UiTheme.box(Color(1, 1, 1, 0.45), 6, 1, Color(UiTheme.INK, 0.2), 10))
	prompt.add_theme_color_override("font_readonly_color", UiTheme.INK)
	prompt.add_theme_font_size_override("font_size", 16)
	v.add_child(prompt)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var copy := Button.new()
	copy.text = "Copiar pedido"
	copy.pressed.connect(_copy_prompt.bind(str(r["prompt"])))
	row.add_child(copy)
	var imp := Button.new()
	imp.text = "Trocar imagem" if has else "Importar imagem"
	imp.pressed.connect(_pick_art.bind(r))
	row.add_child(imp)
	if has:
		var rm := Button.new()
		rm.text = "Remover"
		rm.pressed.connect(_drop_art.bind(r))
		row.add_child(rm)
	v.add_child(row)
	return box


func _copy_prompt(text: String) -> void:
	DisplayServer.clipboard_set(text)
	art_msg = "Pedido copiado para a área de transferência."
	_render()


func _drop_art(r: Dictionary) -> void:
	ArtStore.remove_image(str(r["kind"]), str(r["key"]))
	art_msg = ""
	_render()


func _pick_art(r: Dictionary) -> void:
	_pending_art = r
	if file_dialog == null:
		file_dialog = FileDialog.new()
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp;Imagens"])
		file_dialog.size = Vector2i(900, 620)
		file_dialog.file_selected.connect(_on_art_chosen)
		add_child(file_dialog)
	file_dialog.title = "Escolha a imagem: %s" % str(r["label"])
	file_dialog.popup_centered()


func _on_art_chosen(path: String) -> void:
	if _pending_art.is_empty():
		return
	art_msg = ArtStore.import_image(path, str(_pending_art["kind"]), str(_pending_art["key"]))
	_pending_art = {}
	_render()


# ---------------------------------------------------------------- 5. a lore ganha o grupo

func _page_lore() -> void:
	content.add_child(_h("A história ganha o grupo"))
	if generating:
		status_l = UiTheme.wrap_label(_status, 17, UiTheme.INK, UiTheme.sans_italic())
		content.add_child(status_l)
		content.add_child(_p("Não feche a janela.", 14))
		return
	if not lore_done:
		content.add_child(_p("Os personagens existem agora. A lore é reescrita com eles dentro: como chegaram, quem já ouviu falar de quem, o que cada um tem a ganhar. Os encontros e o orçamento de XP não mudam.", 16))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var ai := Button.new()
		ai.text = "Reescrever com a IA"
		ai.pressed.connect(_update_lore.bind(true))
		row.add_child(ai)
		var tpl := Button.new()
		tpl.text = "Sem IA (o motor acrescenta o grupo)"
		tpl.pressed.connect(_update_lore.bind(false))
		row.add_child(tpl)
		content.add_child(row)
		return
	book = LoreBook.new()
	book.build(str(result["adventure"]["title"]))
	book.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(book)
	book.write(str(result["adventure"]["lore"]))
	content.add_child(_p("Clique no texto para pular a escrita. Depois, Jogar começa a mesa.", 14))


func _update_lore(use_ai: bool) -> void:
	if generating:
		return
	generating = true
	_status = "Preparando."
	_t0 = Time.get_ticks_msec() / 1000.0
	set_process(true)
	_render()
	var players: Array = _final_cfg()["players"]
	result = await gen.update_lore(result, players, use_ai)
	generating = false
	set_process(false)
	lore_done = true
	if visible:
		_render()


# ---------------------------------------------------------------- 2. aventura

func _page_generate() -> void:
	content.add_child(_h("Aventura"))
	var theme := RoomBuilder.theme_by_id(str(cfg["theme"]))
	content.add_child(_p("Sala: %s · Tema: %s · Nível %d · %d jogador(es) · %d capítulo(s) · Mestre %s" % [str(cfg["name"]), str(theme.get("name", "")), int(cfg["level"]), cfg["players"].size(), int(cfg["chapters"]), str(Master.LEVELS[str(cfg["master_level"])]["label"])], 17, false))
	var who := PackedStringArray()
	for p in cfg["players"]:
		who.append("%s (%s)" % [str(p["name"]), Srd.label("class", str(p["classes"][0]["class_id"]))])
	content.add_child(_p("Grupo: " + ", ".join(who), 16))
	content.add_child(_p("História: " + str(cfg["story"]).strip_edges().left(500), 16))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var ai_btn := Button.new()
	ai_btn.text = "Gerar de novo com a IA" if not result.is_empty() else "Gerar com a IA"
	ai_btn.disabled = generating
	ai_btn.tooltip_text = "Usa o Ollama local (%s). Se não responder, o motor monta um modelo com o que você escreveu." % Master.MODEL
	ai_btn.pressed.connect(_generate.bind(true))
	row.add_child(ai_btn)
	var tpl_btn := Button.new()
	tpl_btn.text = "Gerar sem IA (modelo do motor)"
	tpl_btn.disabled = generating
	tpl_btn.pressed.connect(_generate.bind(false))
	row.add_child(tpl_btn)
	content.add_child(row)

	if generating:
		status_l = UiTheme.wrap_label(_status, 17, UiTheme.INK, UiTheme.sans_italic())
		content.add_child(status_l)
		content.add_child(_p("Modelos locais pequenos levam de 20 s a 2 min. Não feche a janela.", 14))
		return
	if result.is_empty():
		content.add_child(_p("Quando a aventura estiver pronta, ela aparece aqui e o botão Jogar é liberado.", 15))
		return
	_result_view()


func _result_view() -> void:
	var adv: Dictionary = result["adventure"]
	var src := "IA local (%s)" % Master.MODEL if str(result["source"]) == "ia" else "gerador de modelo do motor"
	content.add_child(_h(str(adv["title"]), 28))
	content.add_child(_p("Gerada por: %s" % src, 14))
	content.add_child(_p(str(adv["synopsis"]), 17, false))
	content.add_child(_h("Lore (é isto que os jogadores leem)", 20))
	content.add_child(_lore_panel(220))
	content.add_child(_p("Os segredos ficam na bíblia rápida, que só o mestre lê. A lore é reescrita com os personagens na última etapa.", 14))
	for n in result.get("notes", []):
		content.add_child(UiTheme.wrap_label("• " + str(n), 15, UiTheme.HP.darkened(0.25)))
	var main_objs: Array = result["quests"][0].get("objectives", []) if not result["quests"].is_empty() else []
	for i in adv["scenes"].size():
		var sc: Dictionary = adv["scenes"][i]
		var st: Dictionary = result["stats"][i]
		content.add_child(_h(str(sc["title"]), 20))
		if i < main_objs.size():
			content.add_child(_p("Objetivo: %s" % str(main_objs[i]["text"]), 16, false))
		content.add_child(_p(str(sc["intro"]), 16, false))
		var names := PackedStringArray()
		var mons: Array = sc["encounter"]["monsters"].duplicate()
		for grp in sc.get("groups", []):
			mons.append_array(grp.get("monsters", []))
		for m in mons:
			names.append(str(m["name"]) + (" (chefe)" if m.get("boss", false) else ""))
		content.add_child(_p("Encontro (%d de %d XP): %s" % [int(st["xp"]), int(st["budget"]), ", ".join(names)], 16))
		if str(st.get("biome", "")) != "":
			var feats: Array = sc.get("map", {}).get("features", [])
			content.add_child(_p("Mapa: %s%s. O motor desenha o traçado e confere que tudo é alcançável." % [str(st["biome"]),
				(" com " + ", ".join(PackedStringArray(feats))) if not feats.is_empty() else ""], 15))
	if adv["scenes"].size() > 1:
		var rp := PackedStringArray()
		for p in adv.get("rest_points", []):
			rp.append("capítulo %d" % (int(p) + 1))
		content.add_child(_p("Descanso longo liberado em: %s. Fora deles, os ferimentos passam de um capítulo para o outro." % ", ".join(rp), 16))
	var quests := PackedStringArray()
	for q in result["quests"]:
		quests.append(str(q["title"]))
	content.add_child(_p("Missões no diário: " + "; ".join(quests), 16))
	var npcs := PackedStringArray()
	for e in result["bible"].get("npcs", []):
		npcs.append("%s (%s)" % [str(e["name"]), str(e["role"])])
	if not npcs.is_empty():
		content.add_child(_p("NPCs: " + ", ".join(npcs), 16))


func _generate(use_ai: bool) -> void:
	if generating:
		return
	# Só as regras da sala. Usar _errors_for(2) aqui era um impasse: ele exige que a aventura
	# já exista, e é exatamente ela que este botão vai criar.
	var errs := RoomBuilder.config_errors(cfg)
	if not errs.is_empty():
		errors_l.text = "\n".join(PackedStringArray(errs))
		return
	errors_l.text = ""
	generating = true
	result = {}
	_status = "Preparando."
	_t0 = Time.get_ticks_msec() / 1000.0
	set_process(true)
	_render()
	var out: Dictionary = await gen.generate(_final_cfg(), use_ai)
	generating = false
	set_process(false)
	result = out
	if visible:
		_render()


func _final_cfg() -> Dictionary:
	var out: Dictionary = cfg.duplicate(true)
	var ps: Array = []
	for p in cfg.get("players", []):
		ps.append(RoomBuilder.finalize_player(p))
	out["players"] = ps
	out["player_count"] = int(cfg.get("player_count", maxi(1, ps.size())))
	return out


func _play() -> void:
	if result.is_empty() or generating:
		return
	if not Game.create_room(_final_cfg(), result):
		errors_l.text = "Não consegui gravar a aventura em user://. Veja o espaço em disco e as permissões da pasta."
		return
	visible = false
	room_created.emit()
