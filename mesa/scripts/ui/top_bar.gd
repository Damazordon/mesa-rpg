class_name TopBar
extends HBoxContainer
## Faixa superior: campanha, rodada, ordem de iniciativa e atalhos de painel.

signal journal_pressed
signal streamer_pressed

var round_l: Label
var order_box: HBoxContainer
var journal_btn: Button
var streamer_btn: Button
var streamer_note: Label


func build() -> void:
	add_theme_constant_override("separation", 18)
	custom_minimum_size.y = 52
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -4)
	title.add_child(UiTheme.label(Game.scene_info.get("campaign", ""), 26, UiTheme.BONE, UiTheme.serif()))
	title.add_child(UiTheme.label(Game.scene_info.get("chapter", ""), 15, UiTheme.BONE_SOFT))
	add_child(title)
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


func _on_turn(_id: String, round_num: int) -> void:
	round_l.text = "Rodada %d" % round_num
	_refresh_order()


func _refresh_order() -> void:
	for ch in order_box.get_children():
		ch.queue_free()
	var cur: String = Game.current().get("id", "")
	for id in Game.order:
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
	journal_btn.visible = not on
	streamer_btn.visible = not on
	streamer_note.visible = on
