class_name FxPreview
extends Control
## Palco pequeno na ficha para testar a animação de um ataque antes de jogar.

var actor_id := ""
var fx: FxLayer
var _offset := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(380, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	fx = FxLayer.new()
	add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.lunge.connect(func(_id, off): _offset = off)


func _actor_pos() -> Vector2:
	return Vector2(size.x * 0.22, size.y * 0.58)


func _target_pos() -> Vector2:
	return Vector2(size.x * 0.78, size.y * 0.5)


func play(char_id: String, ability: Dictionary) -> void:
	actor_id = char_id
	var template := ArtStore.template_for(char_id, ability)
	var dtype: String = ability.get("dtype", "")
	var col := ArtStore.dtype_color(dtype)
	if template == "cura" and dtype == "":
		col = UiTheme.GOOD.lightened(0.2)
	var to := _target_pos()
	if template == "cura":
		to = _actor_pos()
	fx.play({
		"template": template, "actor_id": char_id, "color": col,
		"tex": ArtStore.fx_image(char_id, str(ability.get("id", ""))),
		"from": _actor_pos(), "to": to, "radius": size.y * 0.42,
	})


func _process(_delta: float) -> void:
	queue_redraw()


func _token(at: Vector2, tex: Texture2D, base: Color, ring: Color, label: String) -> void:
	var r := 28.0
	draw_circle(at + Vector2(0, 5), r, Color(0, 0, 0, 0.4))
	draw_circle(at, r, base)
	if tex != null:
		Portrait.draw_circle_texture(self, tex, at, r - 2.0)
	else:
		var f := UiTheme.sans_bold()
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(f, at + Vector2(-w / 2.0, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_arc(at, r - 1.0, 0.0, TAU, 40, ring, 2.5, true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("221c17"))
	draw_circle(_actor_pos(), size.y * 0.7, Color(1.0, 0.68, 0.32, 0.05))
	var c: Dictionary = Game.by_id.get(actor_id, {})
	var base := Color(str(c.get("color", "#777777")))
	var initials := Portrait.make_initials(str(c.get("name", "?")))
	_token(_actor_pos() + _offset, ArtStore.token(actor_id) if actor_id != "" else null, base, UiTheme.BONE, initials)
	_token(_target_pos(), null, Color("7d8a3a"), UiTheme.ENEMY, "Alvo")
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.WOOD_EDGE, false, 2.0)
