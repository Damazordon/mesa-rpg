extends Control
## Monta a tela de jogo e liga os painéis entre si.
##
## Layout (1920x1080 de referência, escala para outras telas):
##   topo: campanha, rodada, iniciativa, botões
##   esquerda: grupo | centro: mapa (+ diário retrátil) | direita: mestre e histórico
##   baixo: barra de ações
##
## Atalhos: J diário, F8 modo streamer, C ficha de quem joga, 1-5 habilidades,
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

	party_panel.open_sheet.connect(_open_sheet)
	party_panel.hover_member.connect(func(id, on): map_view.linked_id = id if on else "")
	map_view.token_hovered.connect(func(id): party_panel.highlight(id))
	map_view.target_chosen.connect(func(actor, ab, ids): Game.use_ability(actor, ab, ids))
	action_bar.ability_armed.connect(map_view.begin_targeting)
	journal.close_requested.connect(func(): toggle_journal(false))
	top_bar.journal_pressed.connect(func(): toggle_journal(not journal_open))
	top_bar.streamer_pressed.connect(func(): set_streamer(not streamer))
	Game.narration_added.connect(_on_caption)
	Game.taunt_said.connect(func(t, _m): _on_caption("“%s”" % t))
	Game.turn_changed.connect(func(_id, _r): map_view.cancel_targeting())

	Game.start_combat.call_deferred()
	ScreenshotTour.maybe_run(self)


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
	var key: int = event.keycode
	match key:
		KEY_ESCAPE:
			if sheet.visible:
				sheet.close()
			elif not map_view.targeting.is_empty():
				map_view.cancel_targeting()
			elif journal_open:
				toggle_journal(false)
		KEY_J:
			toggle_journal(not journal_open)
		KEY_F8:
			set_streamer(not streamer)
		KEY_C:
			var c := Game.current()
			if not c.is_empty() and c["side"] == "party":
				_open_sheet(c["id"])
		KEY_ENTER, KEY_KP_ENTER:
			if not streamer:
				action_bar.input.grab_focus()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			if not streamer and not sheet.visible:
				action_bar.trigger(key - KEY_1)
		_:
			return
	get_viewport().set_input_as_handled()
