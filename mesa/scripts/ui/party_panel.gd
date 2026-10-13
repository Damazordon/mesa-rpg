class_name PartyPanel
extends PanelContainer
## Canto esquerdo: o grupo. Atualiza em tempo real pelos sinais do Game.

signal open_sheet(id: String)
signal hover_member(id: String, on: bool)

var cards := {}
var hint: Label


func build() -> void:
	custom_minimum_size.x = 330
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.label("Grupo", 23, UiTheme.BONE, UiTheme.sans_bold()))
	head.add_child(UiTheme.spacer(false))
	head.add_child(UiTheme.label("%d jogadores" % Game.party.size(), 15, UiTheme.BONE_SOFT))
	v.add_child(head)
	for c in Game.party:
		var card := PartyCard.new()
		card.setup(c)
		card.open_requested.connect(func(id): open_sheet.emit(id))
		card.hover_changed.connect(func(id, on): hover_member.emit(id, on))
		v.add_child(card)
		cards[c["id"]] = card
	v.add_child(UiTheme.spacer())
	hint = UiTheme.wrap_label("Clique num retrato para abrir a ficha. Passe o mouse num ícone para ver a condição.", 14, UiTheme.BONE_SOFT)
	v.add_child(hint)

	Game.state_changed.connect(_on_state)
	Game.turn_changed.connect(_on_turn)
	Game.floating_text.connect(_on_float)


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
