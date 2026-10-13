class_name MasterAvatar
extends Control
## Avatar do mestre: um vulto encapuzado atrás do escudo.
## As expressões mudam com o humor. Para usar arte própria, salve
## assets/art/master/<humor>.png (neutro, satisfeito, irritado, entediado).

var mood := "neutro"
var _talk := 0.0
var _t := 0.0
var _textures := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for m in ["neutro", "satisfeito", "irritado", "entediado"]:
		var path := "res://assets/art/master/%s.png" % m
		if ResourceLoader.exists(path):
			_textures[m] = load(path)


func set_mood(m: String) -> void:
	mood = m
	_talk = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _talk > 0.0:
		_talk = maxf(0.0, _talk - delta * 0.8)
	queue_redraw()


func _ellipse(center: Vector2, rx: float, ry: float, from := 0.0, to := TAU, n := 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := from + (to - from) * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	draw_circle(c, r, Color("1b1521"))
	draw_arc(c, r - 1.0, 0.0, TAU, 64, Color(UiTheme.VIOLET, 0.55), 1.5, true)
	if _textures.has(mood):
		var inner := r - 4.0
		draw_texture_rect(_textures[mood], Rect2(c - Vector2(inner, inner), Vector2(inner, inner) * 2.0), false)
		return

	var bob := sin(_t * 1.6) * 1.2 - _talk * 2.0
	var hc := c + Vector2(0, r * 0.12 + bob)
	# Capuz
	var hood := PackedVector2Array()
	hood.append(hc + Vector2(-r * 0.78, r * 0.85))
	hood.append_array(_ellipse(hc + Vector2(0, -r * 0.05), r * 0.62, r * 0.72, PI, TAU, 24))
	hood.append(hc + Vector2(r * 0.78, r * 0.85))
	draw_colored_polygon(hood, Color("3a2a4a"))
	# Sombra do rosto
	draw_colored_polygon(_ellipse(hc + Vector2(0, r * 0.08), r * 0.42, r * 0.48), Color("0e0a12"))

	var glow := UiTheme.VIOLET.lightened(0.25)
	var el := hc + Vector2(-r * 0.17, r * 0.02)
	var er := hc + Vector2(r * 0.17, r * 0.02)
	var ew := r * 0.11
	match mood:
		"satisfeito":
			# Olhos sorrindo, de lado
			draw_polyline(_ellipse(el, ew, ew * 0.7, PI, TAU, 10), glow, 2.5, true)
			draw_polyline(_ellipse(er, ew, ew * 0.7, PI, TAU, 10), glow, 2.5, true)
			draw_polyline(_ellipse(hc + Vector2(r * 0.03, r * 0.22), r * 0.14, r * 0.06, 0.15, PI - 0.6, 10), Color(glow, 0.8), 2.0, true)
		"irritado":
			draw_line(el + Vector2(-ew, -ew * 1.1), el + Vector2(ew, -ew * 0.3), glow, 2.5, true)
			draw_line(er + Vector2(ew, -ew * 1.1), er + Vector2(-ew, -ew * 0.3), glow, 2.5, true)
			draw_circle(el + Vector2(0, ew * 0.25), ew * 0.45, glow)
			draw_circle(er + Vector2(0, ew * 0.25), ew * 0.45, glow)
		"entediado":
			draw_line(el + Vector2(-ew, 0), el + Vector2(ew, 0), glow, 2.5, true)
			draw_line(er + Vector2(-ew, 0), er + Vector2(ew, 0), glow, 2.5, true)
		_:
			draw_colored_polygon(_ellipse(el, ew, ew * 0.55), glow)
			draw_colored_polygon(_ellipse(er, ew, ew * 0.55), glow)
	if _talk > 0.0:
		draw_arc(c, r - 1.0, 0.0, TAU, 64, Color(UiTheme.VIOLET, 0.8 * _talk), 3.0, true)
