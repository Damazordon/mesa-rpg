extends Control
## Monta a tela de jogo e liga os painéis entre si.
##
## Layout (1920x1080 de referência, escala para outras telas):
##   topo: campanha, rodada, iniciativa, botões
##   esquerda: grupo | centro: mapa (+ diário retrátil) | direita: mestre e histórico
##   baixo: barra de ações
##
## Atalhos: J diário, F8 modo streamer, C ficha de quem joga, M mover, 1-5 habilidades,
## Enter vai para o campo de texto, Esc fecha o que estiver aberto.

const JOURNAL_W := 430.0

var top_bar: TopBar
var party_panel: PartyPanel
var map_area: Control
var map_view: MapView
var journal: JournalPanel
var caption: PanelContainer
var caption_l: Label
var master_panel: MasterPanel
var action_bar: ActionBar
var sheet: CharacterSheet
var creator: CharacterCreator
var room: RoomSetup
var chapter_panel: ChapterPanel
var _level_id := ""
var journal_open := false
var streamer := false
var _caption_tw: Tween


func _ready() -> void:
	theme = UiTheme.build()
	var bg := ColorRect.new()
	bg.color = UiTheme.FELT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	top_bar = TopBar.new()
	root.add_child(top_bar)
	top_bar.build()

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 14)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)

	party_panel = PartyPanel.new()
	mid.add_child(party_panel)
	party_panel.build()

	map_area = Control.new()
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_area.clip_contents = true
	mid.add_child(map_area)
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.FELT_DEEP, 12, 2, UiTheme.WOOD_EDGE, 6))
	map_area.add_child(frame)
	map_view = MapView.new()
	frame.add_child(map_view)
	_build_caption()
	journal = JournalPanel.new()
	map_area.add_child(journal)
	journal.build()
	journal.anchor_left = 1.0
	journal.anchor_right = 1.0
	journal.anchor_top = 0.0
	journal.anchor_bottom = 1.0
	journal.offset_top = 14
	journal.offset_bottom = -14
	_place_journal(false, false)

	master_panel = MasterPanel.new()
	mid.add_child(master_panel)
	master_panel.build()

	action_bar = ActionBar.new()
	root.add_child(action_bar)
	action_bar.build()

	sheet = CharacterSheet.new()
	add_child(sheet)
	sheet.build()
	creator = CharacterCreator.new()
	add_child(creator)
	creator.build()
	room = RoomSetup.new()
	add_child(room)
	room.build()
	room.room_created.connect(_on_room_created)
	top_bar.new_room_pressed.connect(_on_new_room)
	chapter_panel = ChapterPanel.new()
	add_child(chapter_panel)
	chapter_panel.build()
	chapter_panel.rest_requested.connect(_on_rest)
	chapter_panel.next_requested.connect(_on_next_chapter)
	top_bar.next_chapter_pressed.connect(_on_next_chapter)
	Game.chapter_cleared.connect(_on_chapter_cleared)
	party_panel.new_character.connect(_on_new_character)
	sheet.level_up_requested.connect(_on_level_up)
	creator.finished.connect(_on_creator_done)
	top_bar.start_pressed.connect(_on_start)
	top_bar.rest_pressed.connect(_on_rest)

	party_panel.open_sheet.connect(_open_sheet)
	party_panel.hover_member.connect(func(id, on): map_view.linked_id = id if on else "")
	map_view.token_hovered.connect(func(id): party_panel.highlight(id))
	map_view.target_chosen.connect(func(actor, ab, ids, center): Game.use_ability(actor, ab, ids, center))
	action_bar.move_pressed.connect(func(): map_view.begin_move())
	action_bar.ability_armed.connect(map_view.begin_targeting)
	journal.close_requested.connect(func(): toggle_journal(false))
	top_bar.journal_pressed.connect(func(): toggle_journal(not journal_open))
	top_bar.streamer_pressed.connect(func(): set_streamer(not streamer))
	Game.narration_added.connect(_on_caption)
	Game.taunt_said.connect(func(t, _m): _on_caption("“%s”" % t))

	var tour := false
	for a in OS.get_cmdline_user_args():
		for prefix in ["--shots", "--autoplay", "--fx-shots", "--dialog-shots", "--export-assets"]:
			if a.begins_with(prefix):
				tour = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--creator-shots") or a == "--rules-tests" or tour:
			Game.persist = false
	if tour:
		Game.start_combat.call_deferred()
	elif not "--rules-tests" in OS.get_cmdline_user_args():
		_prepare.call_deferred()
	ScreenshotTour.maybe_run(self)


## Ao abrir o jogo sem argumentos de teste, começa pela criação de sala. "Continuar mesa atual"
## segue com a última mesa. Depois de criar uma sala a cena é recarregada e a tela não reabre.
func _prepare() -> void:
	if OS.get_cmdline_user_args().is_empty():
		if Game.skip_room_once:
			Game.skip_room_once = false
		else:
			room.open(true)
	if Game.ex.has_exploration():
		Game.narration_added.emit("%s — %s. %s" % [Game.adventure.get("title", ""), Game.chapter_title(), Game.scene_info.get("intro", "")])
		Game.engine_log("Exploração: clique num personagem do grupo e depois no mapa para andar (o tracejado mostra o caminho). Os bandos só notam vocês de perto e à vista: parede esconde, e no combate dá cobertura.")
	elif Game.chapter_count() > 1:
		Game.narration_added.emit("%s — capítulo %d de %d: %s. %s" % [Game.adventure.get("title", ""), Game.chapter + 1,
			Game.chapter_count(), Game.chapter_title(), Game.scene_info.get("intro", "")])
	else:
		Game.narration_added.emit("Mesa pronta: %s. %s Criem personagens no painel do grupo ou cliquem em Iniciar encontro." % [Game.adventure.get("title", ""), Game.adventure.get("synopsis", "")])
	if not Game.party.is_empty():
		action_bar.current_id = Game.party[0]["id"]


## Capítulo vencido: deixa a narração de vitória aparecer e então abre o balanço do capítulo.
func _on_chapter_cleared(_index: int, _total: int) -> void:
	if streamer or not OS.get_cmdline_user_args().is_empty():
		return
	await get_tree().create_timer(1.5).timeout
	if not Game.in_combat and not room.visible:
		chapter_panel.open()


func _on_next_chapter() -> void:
	if Game.in_combat or not Game.has_next_chapter():
		return
	chapter_panel.close()
	if Game.advance_chapter():
		# A cena nova precisa de mapa, painéis e barra do topo refeitos; o grupo vive no Game e persiste.
		Game.skip_room_once = true
		get_tree().reload_current_scene.call_deferred()


func _on_new_room() -> void:
	if not Game.in_combat:
		room.open(false)


## A aventura nova já foi gravada e carregada no Game; recarrega a tela principal para refazer
## barra do topo, grupo e mapa com os dados dela.
func _on_room_created() -> void:
	Game.skip_room_once = true
	get_tree().reload_current_scene.call_deferred()


func _on_new_character() -> void:
	if not Game.in_combat:
		creator.open_create()


func _on_start() -> void:
	if not Game.in_combat and not Game.party.is_empty():
		Game.start_combat()


func _on_level_up(id: String) -> void:
	if Game.in_combat:
		return
	# No modo por experiência, o motor decide: sem XP suficiente não sobe, venha o pedido de onde vier.
	if str(Game.settings.get("level_mode", "xp")) == "xp" and not Game.can_level_up(Game.by_id[id]):
		Game.engine_log("%s ainda não tem experiência para o próximo nível." % Game.by_id[id]["name"])
		return
	_level_id = id
	sheet.close()
	creator.open_level_up(id)


func _on_creator_done(ch: Dictionary) -> void:
	if creator.mode == "level" and _level_id != "":
		ch.erase("_rolled_hp")
		var c := Game.rebuild(_level_id, ch)
		Game.engine_log("%s agora é %s." % [c["name"], c["class"]])
		_level_id = ""
	else:
		var c2 := Game.add_character(ch)
		Game.engine_log("%s entrou no grupo (%s, %s)." % [c2["name"], c2["class"], c2["species"]])
		Game.narration_added.emit("%s chega à mesa. Vamos ver quanto tempo dura." % c2["name"])


func _on_rest(kind: String) -> void:
	if Game.in_combat:
		return
	if kind == "long":
		Game.long_rest()
	else:
		var dice := {}
		for c in Game.party:
			# Gasta Dados de Vida até ficar perto do máximo
			var missing: int = int(c["hp_max"]) - int(c["hp"])
			var avg := 1
			for die in c.get("hit_dice", {}):
				avg = int(die.substr(1)) / 2 + 1 + Rules.amod(c, "con")
			dice[c["id"]] = ceili(float(missing) / maxf(1.0, float(avg))) if missing > 0 else 0
		Game.short_rest(dice)


func _build_caption() -> void:
	caption = PanelContainer.new()
	caption.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.72), 8, 0, Color(0, 0, 0, 0), 18))
	caption.anchor_left = 0.08
	caption.anchor_right = 0.92
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_bottom = -28
	caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.visible = false
	caption_l = UiTheme.wrap_label("", 28, UiTheme.BONE, UiTheme.serif())
	caption_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(caption_l)
	map_area.add_child(caption)


func _on_caption(text: String) -> void:
	if not streamer or text.is_empty():
		return
	caption_l.text = text
	caption.visible = true
	caption.modulate.a = 0.0
	if _caption_tw != null:
		_caption_tw.kill()
	_caption_tw = create_tween()
	_caption_tw.tween_property(caption, "modulate:a", 1.0, 0.25)
	_caption_tw.tween_interval(8.0)
	_caption_tw.tween_property(caption, "modulate:a", 0.0, 0.6)


func _place_journal(open: bool, animate := true) -> void:
	var left := -JOURNAL_W - 14.0 if open else 20.0
	var right := -14.0 if open else JOURNAL_W + 20.0
	if animate:
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(journal, "offset_left", left, 0.25)
		tw.tween_property(journal, "offset_right", right, 0.25)
	else:
		journal.offset_left = left
		journal.offset_right = right


func toggle_journal(open: bool) -> void:
	if streamer and open:
		return
	journal_open = open
	_place_journal(open)


func _open_sheet(id: String) -> void:
	if streamer:
		return
	map_view.cancel_targeting()
	sheet.open_for(id)


func set_streamer(on: bool) -> void:
	streamer = on
	action_bar.visible = not on
	top_bar.set_streamer(on)
	master_panel.set_streamer(on)
	party_panel.set_streamer(on)
	if on:
		toggle_journal(false)
		sheet.close()
		map_view.cancel_targeting()
	else:
		caption.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if room.visible or chapter_panel.visible:
		return
	var key: int = event.keycode
	match key:
		KEY_ESCAPE:
			if sheet.visible:
				sheet.close()
			elif not map_view.targeting.is_empty():
				map_view.cancel_targeting()
			elif map_view.move_mode:
				map_view.cancel_move()
			elif Game.selected_target != "":
				Game.select_target("")
			elif journal_open:
				toggle_journal(false)
		KEY_J:
			toggle_journal(not journal_open)
		KEY_M:
			if not streamer and not sheet.visible:
				map_view.begin_move()
		KEY_D:
			if not streamer and not sheet.visible:
				action_bar.defend()
		KEY_F8:
			set_streamer(not streamer)
		KEY_C:
			var c := Game.current()
			if not c.is_empty() and c["side"] == "party":
				_open_sheet(c["id"])
		KEY_ENTER, KEY_KP_ENTER:
			if not map_view.targeting.is_empty() and not map_view.targeting.get("picks", []).is_empty():
				map_view.confirm_targets()
			elif not streamer:
				action_bar.input.grab_focus()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			if not streamer and not sheet.visible:
				action_bar.trigger(key - KEY_1)
		_:
			return
	get_viewport().set_input_as_handled()
