class_name MasterPanel
extends PanelContainer
## Canto direito: o escudo do mestre.
## Narração (serifada, texto principal) fica separada da provocação (violeta, balão).
## Assim o jogador sempre sabe o que é regra e o que é zoeira.

var avatar: MasterAvatar
var mood_l: Label
var bubble: PanelContainer
var bubble_l: Label
var feed: RichTextLabel
var tabs: TabContainer
var dice_scroll: ScrollContainer
var dice_list: VBoxContainer
var engine_feed: RichTextLabel
var _bubble_tw: Tween
var _first_line := true


func build() -> void:
	custom_minimum_size.x = 420
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	avatar = MasterAvatar.new()
	avatar.custom_minimum_size = Vector2(88, 88)
	head.add_child(avatar)
	var who := VBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	who.add_child(UiTheme.label("O Mestre", 26, UiTheme.BONE, UiTheme.serif()))
	mood_l = UiTheme.label(Master.mood_text(), 16, UiTheme.VIOLET, UiTheme.sans_italic())
	who.add_child(mood_l)

	bubble = PanelContainer.new()
	var bs := UiTheme.box(Color(UiTheme.VIOLET, 0.13), 10, 1, Color(UiTheme.VIOLET, 0.55), 12)
	bs.content_margin_left = 16
	bs.content_margin_right = 16
	bubble.add_theme_stylebox_override("panel", bs)
	bubble_l = UiTheme.wrap_label("", 20, UiTheme.VIOLET.lightened(0.35), UiTheme.serif_italic())
	bubble.add_child(bubble_l)
	bubble.visible = false
	v.add_child(bubble)

	var feed_box := PanelContainer.new()
	feed_box.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.18), 8, 0, Color(0, 0, 0, 0), 14))
	feed_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_box.size_flags_stretch_ratio = 1.25
	v.add_child(feed_box)
	feed = RichTextLabel.new()
	feed.bbcode_enabled = true
	feed.scroll_following = true
	feed.selection_enabled = true
	feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_box.add_child(feed)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)

	dice_scroll = ScrollContainer.new()
	dice_scroll.name = "Dados"
	dice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(dice_scroll)
	dice_list = VBoxContainer.new()
	dice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dice_list.add_theme_constant_override("separation", 6)
	dice_scroll.add_child(dice_list)

	engine_feed = RichTextLabel.new()
	engine_feed.name = "Decisões do motor"
	engine_feed.bbcode_enabled = true
	engine_feed.scroll_following = true
	engine_feed.add_theme_font_override("normal_font", UiTheme.sans())
	engine_feed.add_theme_font_size_override("normal_font_size", 16)
	engine_feed.add_theme_color_override("default_color", UiTheme.BONE_SOFT)
	tabs.add_child(engine_feed)

	Game.narration_added.connect(_on_narration)
	Game.player_spoke.connect(_on_player)
	Game.taunt_said.connect(_on_taunt)
	Game.dice_logged.connect(_on_dice)
	Game.engine_logged.connect(_on_engine)
	Game.turn_changed.connect(_on_turn)


static func esc(t: String) -> String:
	return t.replace("[", "[lb]")


func _para(bb: String) -> void:
	if not _first_line:
		feed.append_text("\n\n")
	_first_line = false
	feed.append_text(bb)


func _on_narration(text: String) -> void:
	if text.is_empty():
		return
	_para(esc(text))


func _on_player(actor_id: String, text: String) -> void:
	var c: Dictionary = Game.by_id[actor_id]
	var col := Color(str(c.get("color", "#cccccc"))).lightened(0.25)
	_para("[b][color=#%s]%s[/color][/b]  [color=#%s][i]%s[/i][/color]" % [col.to_html(false), esc(c["name"]), UiTheme.BONE_SOFT.to_html(false), esc(text)])


func _on_taunt(text: String, mood: String) -> void:
	avatar.set_mood(mood)
	mood_l.text = Master.mood_text()
	_para("[i][color=#%s]“%s”[/color][/i]" % [UiTheme.VIOLET.to_html(false), esc(text)])
	bubble_l.text = "“%s”" % text
	bubble.visible = true
	bubble.modulate.a = 0.0
	if _bubble_tw != null:
		_bubble_tw.kill()
	_bubble_tw = create_tween()
	_bubble_tw.tween_property(bubble, "modulate:a", 1.0, 0.2)
	_bubble_tw.tween_interval(7.0)
	_bubble_tw.tween_property(bubble, "modulate:a", 0.0, 0.6)
	_bubble_tw.tween_callback(func(): bubble.visible = false)


func _on_dice(e: Dictionary) -> void:
	var entry := DiceEntry.new()
	entry.setup(e)
	dice_list.add_child(entry)
	while dice_list.get_child_count() > 80:
		dice_list.get_child(0).free()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(entry):
		dice_scroll.ensure_control_visible(entry)


func _on_engine(text: String) -> void:
	engine_feed.append_text("[color=#%s]R%d[/color]  %s\n" % [UiTheme.WOOD_EDGE.lightened(0.3).to_html(false), Game.round_num, esc(text)])


func _on_turn(_id: String, _round: int) -> void:
	pass


func set_streamer(on: bool) -> void:
	tabs.set_tab_hidden(1, on)
	if on:
		tabs.current_tab = 0
