class_name TopBar
extends HBoxContainer
## Faixa superior: campanha, rodada, ordem de iniciativa e atalhos de painel.

signal journal_pressed
signal streamer_pressed
signal start_pressed
signal rest_pressed(kind: String)
signal new_room_pressed
signal next_chapter_pressed

var round_l: Label
var order_box: HBoxContainer
var journal_btn: Button
var streamer_btn: Button
var streamer_note: Label
var start_btn: Button
var rest_btn: MenuButton
var level_btn: OptionButton
var room_btn: Button
var next_btn: Button
var chapter_l: Label


func build() -> void:
	add_theme_constant_override("separation", 18)
	custom_minimum_size.y = 52
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -4)
	title.add_child(UiTheme.label(Game.scene_info.get("campaign", ""), 26, UiTheme.BONE, UiTheme.serif()))
	title.add_child(UiTheme.label(Game.scene_info.get("chapter", ""), 15, UiTheme.BONE_SOFT))
	add_child(title)
	chapter_l = UiTheme.label("", 16, UiTheme.BONE_SOFT, UiTheme.sans_bold())
	chapter_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(chapter_l)
	add_child(UiTheme.spacer(false))
	round_l = UiTheme.label("", 18, UiTheme.AMBER, UiTheme.sans_bold())
	round_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(round_l)
	order_box = HBoxContainer.new()
	order_box.add_theme_constant_override("separation", 6)
	order_box.tooltip_text = "Ordem de iniciativa"
	add_child(order_box)
	add_child(UiTheme.spacer(false))
	streamer_note = UiTheme.label("Modo streamer. F8 volta ao normal.", 16, UiTheme.BONE_SOFT, UiTheme.sans_italic())
	streamer_note.visible = false
	streamer_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(streamer_note)
	level_btn = OptionButton.new()
	level_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_btn.tooltip_text = "Nível do mestre. Calmo: CD -2 e tom acolhedor. Normal: sem ajuste. Cínico: CD +2, cobra cada falha."
	var level_ids: Array = ["calmo", "normal", "cinico"]
	for i in level_ids.size():
		level_btn.add_item("Mestre: " + str(Master.LEVELS[level_ids[i]]["label"]), i)
		if level_ids[i] == Master.level:
			level_btn.select(i)
	level_btn.item_selected.connect(func(i): Master.set_level(level_ids[i]))
	add_child(level_btn)
	rest_btn = MenuButton.new()
	rest_btn.text = "Descansar"
	rest_btn.flat = false
	rest_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rest_btn.tooltip_text = "Descanso curto (1 hora): gasta Dados de Vida. Descanso longo (8 horas): recupera tudo."
	rest_btn.get_popup().add_item("Descanso curto (gasta Dados de Vida)", 0)
	rest_btn.get_popup().add_item("Descanso longo", 1)
	rest_btn.get_popup().id_pressed.connect(func(i): rest_pressed.emit("short" if i == 0 else "long"))
	add_child(rest_btn)
	start_btn = Button.new()
	start_btn.text = "Iniciar encontro"
	start_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start_btn.add_theme_color_override("font_color", UiTheme.AMBER.lightened(0.2))
	start_btn.pressed.connect(func(): start_pressed.emit())
	add_child(start_btn)
	next_btn = Button.new()
	next_btn.text = "Próximo capítulo"
	next_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next_btn.add_theme_color_override("font_color", UiTheme.AMBER.lightened(0.2))
	next_btn.pressed.connect(func(): next_chapter_pressed.emit())
	add_child(next_btn)
	room_btn = Button.new()
	room_btn.text = "Nova sala"
	room_btn.tooltip_text = "Criar outra mesa: tema, história, jogadores e aventura gerada pela IA"
	room_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	room_btn.pressed.connect(func(): new_room_pressed.emit())
	add_child(room_btn)
	journal_btn = Button.new()
	journal_btn.text = "Diário (J)"
	journal_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	journal_btn.pressed.connect(func(): journal_pressed.emit())
	add_child(journal_btn)
	streamer_btn = Button.new()
	streamer_btn.text = "Modo streamer (F8)"
	streamer_btn.tooltip_text = "Interface limpa para gravar ou transmitir"
	streamer_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	streamer_btn.pressed.connect(func(): streamer_pressed.emit())
	add_child(streamer_btn)
	Game.turn_changed.connect(_on_turn)
	Game.state_changed.connect(func(_id): _refresh_order())
	Game.combat_ended.connect(func(_v): _set_combat(false))
	Game.chapter_ready.connect(func(_i, _t): _set_combat(Game.in_combat))
	Game.pois_changed.connect(func(): _set_combat(Game.in_combat))
	_set_combat(Game.in_combat)


func _set_combat(on: bool) -> void:
	# Vencido o capítulo, "Iniciar encontro" dá lugar a "Próximo capítulo".
	var cleared: bool = Game.chapter_done and Game.has_next_chapter()
	# Em capítulo com exploração o combate começa ao topar com um bando, não por botão.
	start_btn.visible = not on and not cleared and not Game.ex.has_exploration()
	next_btn.visible = not on and cleared
	rest_btn.visible = not on
	room_btn.visible = not on
	if Game.chapter_count() > 1:
		chapter_l.text = "Capítulo %d de %d" % [Game.chapter + 1, Game.chapter_count()]
		chapter_l.tooltip_text = Game.chapter_title()
	else:
		chapter_l.text = ""
	if not on:
		round_l.text = Game.ex.progress_text() if Game.ex.has_exploration() else "Fora de combate"
		# Descanso longo pode estar travado pelos pontos de descanso da aventura.
		var ok := Game.can_long_rest()
		rest_btn.get_popup().set_item_disabled(1, not ok)
		rest_btn.tooltip_text = "Descanso curto (1 hora): gasta Dados de Vida. Descanso longo (8 horas): recupera tudo." if ok else "Descanso curto disponível. O longo só nos pontos de descanso desta aventura."


func _on_turn(_id: String, round_num: int) -> void:
	_set_combat(true)
	round_l.text = "Rodada %d" % round_num
	_refresh_order()


func _refresh_order() -> void:
	for ch in order_box.get_children():
		ch.queue_free()
	var cur: String = Game.current().get("id", "")
	for id in Game.order:
		# A ordem pode citar quem já saiu do tabuleiro (troca de capítulo, inimigo removido).
		if not Game.by_id.has(id):
			continue
		var c: Dictionary = Game.by_id[id]
		var p := Portrait.new()
		p.setup(c, 40 if id == cur else 32)
		p.active = id == cur
		p.down = not Game.is_alive(c)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.tooltip_text = c["name"]
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		order_box.add_child(p)


func set_streamer(on: bool) -> void:
	room_btn.visible = not on and not Game.in_combat
	next_btn.visible = not on and not Game.in_combat and Game.chapter_done and Game.has_next_chapter()
	journal_btn.visible = not on
	streamer_btn.visible = not on
	streamer_note.visible = on
