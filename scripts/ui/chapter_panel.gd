class_name ChapterPanel
extends Control
## Painel entre capítulos: o que o grupo ganhou, em que estado ficou e o que vem depois.
##
## É aqui que o desgaste aparece: PV, recursos e Dados de Vida gastos NÃO voltam ao passar de
## capítulo. Descanso curto é sempre possível; o longo depende dos pontos de descanso da aventura
## (Game.can_long_rest). Subir de nível continua passando pela ficha, com a XP do motor.

signal rest_requested(kind: String)
signal next_requested
signal closed

var card: PanelContainer
var body: VBoxContainer


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.custom_minimum_size = Vector2(900, 0)
	card.add_theme_stylebox_override("panel", UiTheme.paper_box(10, 24))
	center.add_child(card)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)
	Game.state_changed.connect(_on_state_changed)


func _on_state_changed(_id: String) -> void:
	if visible:
		refresh()


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func _h(text: String, size := 22) -> Label:
	return UiTheme.label(text, size, UiTheme.INK, UiTheme.serif() if size >= 22 else UiTheme.sans_bold())


func _p(text: String, size := 16, soft := true) -> Label:
	return UiTheme.wrap_label(text, size, UiTheme.INK_SOFT if soft else UiTheme.INK)


func refresh() -> void:
	for x in body.get_children():
		x.queue_free()
	var finished := not Game.has_next_chapter()
	var total := Game.chapter_count()
	var idx := Game.chapter

	if finished:
		body.add_child(_h("Aventura concluída", 32))
		body.add_child(_p(str(Game.adventure.get("epilogue", "")), 19, false))
	else:
		body.add_child(_h("Capítulo %d de %d concluído" % [idx + 1, total], 32))
		body.add_child(_p(str(Game.scene_info.get("victory", "")), 19, false))

	# Diário: o objetivo deste capítulo acabou de ser marcado pelo motor.
	for q in Game.quests:
		if q.get("pinned", false) and idx < q.get("objectives", []).size():
			body.add_child(_p("Objetivo concluído: %s" % str(q["objectives"][idx]["text"]), 17, false))
			break

	body.add_child(_h("O grupo", 20))
	body.add_child(_p("Ferimentos e recursos gastos seguem para o próximo capítulo. Pense no que vale gastar agora.", 15))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	for c in Game.party:
		var dead: bool = c.get("death", {}).get("dead", false)
		grid.add_child(_p(str(c["name"]), 17, false))
		var hp := int(c["hp"])
		var hp_max := int(c["hp_max"])
		var col := UiTheme.HP.darkened(0.2) if (dead or hp == 0) else (UiTheme.INK if hp > hp_max / 2 else UiTheme.HP.darkened(0.35))
		var hp_l := UiTheme.label("morto" if dead else "PV %d/%d" % [hp, hp_max], 17, col, UiTheme.sans_bold())
		grid.add_child(hp_l)
		grid.add_child(_p("nível %d · %d XP" % [int(c["level"]), int(c.get("xp", 0))], 16))
		grid.add_child(_p("pode subir de nível" if Game.can_level_up(c) else "", 16, false))
	body.add_child(grid)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var short_btn := Button.new()
	short_btn.text = "Descanso curto"
	short_btn.tooltip_text = "Uma hora. Gasta Dados de Vida para recuperar PV e devolve o que volta no descanso curto."
	short_btn.pressed.connect(func(): rest_requested.emit("short"))
	row.add_child(short_btn)
	var long_btn := Button.new()
	long_btn.text = "Descanso longo"
	long_btn.disabled = not Game.can_long_rest()
	long_btn.tooltip_text = "Oito horas: recupera tudo." if not long_btn.disabled else "Esta aventura só libera descanso longo nos pontos de descanso. O próximo vem mais adiante."
	long_btn.pressed.connect(func(): rest_requested.emit("long"))
	row.add_child(long_btn)
	row.add_child(UiTheme.spacer(false))
	var close_btn := Button.new()
	close_btn.text = "Ficar na mesa"
	close_btn.tooltip_text = "Fecha este painel para abrir fichas e ajustar o grupo. O botão do capítulo continua na barra de cima."
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	if not finished:
		var next_btn := Button.new()
		next_btn.text = "Próximo capítulo"
		next_btn.custom_minimum_size.x = 240
		next_btn.add_theme_color_override("font_color", UiTheme.AMBER.darkened(0.45))
		next_btn.tooltip_text = Game.chapter_title(idx + 1)
		next_btn.pressed.connect(func(): next_requested.emit())
		row.add_child(next_btn)
	body.add_child(row)
	if not finished:
		body.add_child(_p("A seguir: %s" % Game.chapter_title(idx + 1), 16, false))
