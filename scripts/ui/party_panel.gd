class_name PartyPanel
extends PanelContainer
## Canto esquerdo: o grupo. Atualiza em tempo real pelos sinais do Game.

signal open_sheet(id: String)
signal hover_member(id: String, on: bool)
signal new_character

var cards := {}
var hint: Label
var list: VBoxContainer
var count_l: Label
var new_btn: Button


func build() -> void:
	custom_minimum_size.x = 330
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.label("Grupo", 23, UiTheme.BONE, UiTheme.sans_bold()))
	head.add_child(UiTheme.spacer(false))
	count_l = UiTheme.label("", 15, UiTheme.BONE_SOFT)
	head.add_child(count_l)
	v.add_child(head)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	v.add_child(list)
	new_btn = Button.new()
	new_btn.text = "+ Novo personagem"
	new_btn.tooltip_text = "Criar personagem pelas regras do SRD 5.2.1 (fora de combate)"
	new_btn.pressed.connect(func(): new_character.emit())
	v.add_child(new_btn)
	_rebuild()
	v.add_child(UiTheme.spacer())
	hint = UiTheme.wrap_label("Clique num retrato para abrir a ficha. Passe o mouse num ícone para ver a condição.", 14, UiTheme.BONE_SOFT)
	v.add_child(hint)

	Game.state_changed.connect(_on_state)
	Game.turn_changed.connect(_on_turn)
	Game.floating_text.connect(_on_float)
	Game.party_changed.connect(_rebuild)
	Game.combat_ended.connect(func(_v): new_btn.visible = true)
	Game.turn_changed.connect(func(_i, _r): new_btn.visible = not Game.in_combat)


func _rebuild() -> void:
	for ch in list.get_children():
		ch.queue_free()
	cards.clear()
	for c in Game.party:
		var card := PartyCard.new()
		card.setup(c)
		card.open_requested.connect(func(id): open_sheet.emit(id))
		card.hover_changed.connect(func(id, on): hover_member.emit(id, on))
		list.add_child(card)
		cards[c["id"]] = card
	count_l.text = "%d jogadores" % Game.party.size()
	new_btn.visible = not Game.in_combat and Game.party.size() < 8


func _on_state(id: String) -> void:
	if cards.has(id):
		cards[id].refresh(Game.by_id[id])


func _on_turn(id: String, _round: int) -> void:
	for k in cards:
		cards[k].set_active(k == id)


func _on_float(id: String, _text: String, kind: String) -> void:
	if cards.has(id):
		cards[id].flash(kind)


func highlight(id: String) -> void:
	for k in cards:
		cards[k].set_linked(k == id)


func set_streamer(on: bool) -> void:
	hint.visible = not on
