class_name Portrait
extends Control
## Retrato redondo. Placeholder: iniciais sobre a cor do personagem.
## Para usar arte própria, salve assets/art/portraits/<id>.png (quadrado).

var initials := "?"
var color := Color.GRAY
var active := false
var down := false
var texture: Texture2D
var _t := 0.0


func setup(c: Dictionary, diameter := 56.0) -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	initials = make_initials(str(c["name"]))
	color = Color(str(c.get("color", "#777777")))
	var path := "res://assets/art/portraits/%s.png" % c["id"]
	if ResourceLoader.exists(path):
		texture = load(path)
	queue_redraw()


static func make_initials(n: String) -> String:
	var parts := n.split(" ", false)
	if parts.size() >= 2:
		return (parts[0].substr(0, 1) + parts[1].substr(0, 1)).to_upper()
	return n.substr(0, 2)


func set_active(on: bool) -> void:
	active = on
	queue_redraw()


func set_down(on: bool) -> void:
	down = on
	queue_redraw()


func _process(delta: float) -> void:
	if active:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	if active:
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(c, r, Color(UiTheme.AMBER, 0.18 + 0.22 * pulse))
	var col := color
	if down:
		col = color.lerp(Color(0.25, 0.25, 0.25), 0.75)
	draw_circle(c, r - 3.0, col.darkened(0.4))
	draw_circle(c, r - 5.0, col)
	if texture != null:
		var inner := r - 6.0
		draw_texture_rect(texture, Rect2(c - Vector2(inner, inner), Vector2(inner, inner) * 2.0), false)
	else:
		var f := UiTheme.sans_bold()
		var fs := int(r * 0.78)
		var w := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var baseline := c.y + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
		draw_string(f, Vector2(c.x - w / 2.0, baseline), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92 if not down else 0.5))
	var ring := UiTheme.AMBER if active else Color(UiTheme.BONE, 0.55)
	draw_arc(c, r - 2.0, 0.0, TAU, 48, ring, 2.5 if active else 1.0, true)
	if down:
		draw_line(c + Vector2(-r * 0.45, -r * 0.45), c + Vector2(r * 0.45, r * 0.45), Color(UiTheme.HP, 0.9), 3.0, true)
		draw_line(c + Vector2(r * 0.45, -r * 0.45), c + Vector2(-r * 0.45, r * 0.45), Color(UiTheme.HP, 0.9), 3.0, true)
