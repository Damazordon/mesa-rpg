class_name FxLayer
extends Control
## Animações de ataque. Quatro modelos genéricos que animam qualquer imagem:
##   projetil  a imagem voa do atacante até o alvo e explode no impacto
##   golpe     o token do atacante avança e a imagem risca o alvo
##   area      a imagem cresce no centro da área com um anel de choque
##   cura      a imagem sobe do personagem com partículas brilhando
## Sem imagem do jogador, desenha um efeito padrão na cor do tipo de dano.

signal lunge(actor_id: String, offset: Vector2)

var _effects: Array = []


static func duration(template: String) -> float:
	return ArtStore.fx_duration(template)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## params: template, from (px), to (px), color, tex (opcional), radius (px, área), actor_id
func play(params: Dictionary) -> void:
	var e := params.duplicate()
	e["t"] = 0.0
	e["dur"] = duration(e["template"])
	e["seed"] = randi()
	_effects.append(e)


func is_playing() -> bool:
	return not _effects.is_empty()


func _process(delta: float) -> void:
	if _effects.is_empty():
		return
	var still: Array = []
	for e in _effects:
		e["t"] += delta
		var p: float = clampf(e["t"] / e["dur"], 0.0, 1.0)
		if e["template"] == "golpe":
			var dir: Vector2 = (e["to"] - e["from"])
			var reach := minf(dir.length() * 0.35, 60.0)
			var amount := sin(minf(p / 0.6, 1.0) * PI) * reach
			lunge.emit(e.get("actor_id", ""), dir.normalized() * amount)
		if p < 1.0:
			still.append(e)
		elif e["template"] == "golpe":
			lunge.emit(e.get("actor_id", ""), Vector2.ZERO)
	_effects = still
	queue_redraw()


static func _ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 3.0)


func _draw_glow(at: Vector2, radius: float, col: Color, strength := 1.0) -> void:
	for i in 5:
		var f := 1.0 - float(i) / 5.0
		draw_circle(at, radius * (0.4 + f), Color(col, 0.12 * strength * (1.0 - f) + 0.05 * strength))
	draw_circle(at, radius * 0.45, Color(col.lightened(0.5), 0.9 * strength))


func _draw_image(tex: Texture2D, at: Vector2, side: float, angle: float, alpha: float) -> void:
	draw_set_transform(at, angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-side, -side) / 2.0, Vector2(side, side)), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	for e in _effects:
		var p: float = clampf(e["t"] / e["dur"], 0.0, 1.0)
		match e["template"]:
			"projetil":
				_draw_projectile(e, p)
			"golpe":
				_draw_slash(e, p)
			"area":
				_draw_area(e, p)
			"cura":
				_draw_heal(e, p)


func _draw_projectile(e: Dictionary, p: float) -> void:
	var a: Vector2 = e["from"]
	var b: Vector2 = e["to"]
	var col: Color = e["color"]
	var tex: Texture2D = e.get("tex")
	var flight := 0.78
	if p < flight:
		var q := _ease_out(p / flight) if tex == null else p / flight
		var arc := sin(q * PI) * minf(a.distance_to(b) * 0.12, 50.0)
		var pos := a.lerp(b, q) + Vector2(0, -arc)
		for i in range(1, 7):
			var tq := maxf(0.0, q - 0.035 * i)
			var tp := a.lerp(b, tq) + Vector2(0, -sin(tq * PI) * minf(a.distance_to(b) * 0.12, 50.0))
			draw_circle(tp, 9.0 - i, Color(col, 0.35 - 0.05 * i))
		if tex != null:
			_draw_image(tex, pos, 64.0, (b - a).angle(), 1.0)
		else:
			_draw_glow(pos, 16.0, col)
	else:
		var k := (p - flight) / (1.0 - flight)
		draw_circle(b, 18.0 + 40.0 * k, Color(col, 0.35 * (1.0 - k)))
		draw_arc(b, 20.0 + 46.0 * k, 0.0, TAU, 40, Color(col.lightened(0.3), 1.0 - k), 3.0, true)


func _draw_slash(e: Dictionary, p: float) -> void:
	if p < 0.3 or p > 0.95:
		return
	var b: Vector2 = e["to"]
	var col: Color = e["color"]
	var tex: Texture2D = e.get("tex")
	var k := (p - 0.3) / 0.65
	var dir: Vector2 = (b - e["from"]).normalized()
	var base := dir.angle() - PI / 2.0
	var r := 58.0
	var a0 := base - 1.1
	var a1 := a0 + 2.2 * _ease_out(minf(k * 1.6, 1.0))
	if tex != null:
		var ang := lerpf(a0, a0 + 2.2, minf(k * 1.4, 1.0))
		_draw_image(tex, b + Vector2(cos(ang), sin(ang)) * r * 0.55, 72.0, ang + PI / 2.0, 1.0 - maxf(0.0, k - 0.7) / 0.3)
	var fade := 1.0 - maxf(0.0, k - 0.5) / 0.5
	draw_arc(b, r, a0, a1, 24, Color(col, 0.4 * fade), 20.0, true)
	draw_arc(b, r, a0, a1, 24, Color(col.lightened(0.4), 0.95 * fade), 6.0, true)


func _draw_area(e: Dictionary, p: float) -> void:
	var c: Vector2 = e["to"]
	var col: Color = e["color"]
	var tex: Texture2D = e.get("tex")
	var radius: float = e.get("radius", 80.0)
	var g := _ease_out(p)
	draw_circle(c, radius * g, Color(col, 0.28 * (1.0 - p)))
	draw_arc(c, radius * g, 0.0, TAU, 64, Color(col.lightened(0.3), 1.0 - p), 4.0, true)
	draw_arc(c, radius * g * 0.7, 0.0, TAU, 64, Color(col, 0.6 * (1.0 - p)), 2.0, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = e["seed"]
	for i in 12:
		var ang := TAU * float(i) / 12.0 + rng.randf() * 0.4
		var d := radius * (0.2 + 0.9 * g) * rng.randf_range(0.7, 1.05)
		draw_circle(c + Vector2(cos(ang), sin(ang)) * d, 4.0 * (1.0 - p) + 1.0, Color(col.lightened(0.4), 1.0 - p))
	if tex != null:
		_draw_image(tex, c, radius * (0.6 + 1.0 * g), p * 0.6, 1.0 - p * p)


func _draw_heal(e: Dictionary, p: float) -> void:
	var c: Vector2 = e["from"]
	var col: Color = e["color"]
	var tex: Texture2D = e.get("tex")
	var rng := RandomNumberGenerator.new()
	rng.seed = e["seed"]
	draw_arc(c, 34.0 + 10.0 * p, 0.0, TAU, 48, Color(col, 0.8 * (1.0 - p)), 3.0, true)
	for i in 14:
		var delay := rng.randf() * 0.4
		var q := clampf((p - delay) / 0.6, 0.0, 1.0)
		if q <= 0.0 or q >= 1.0:
			continue
		var x := rng.randf_range(-38.0, 38.0)
		var pos := c + Vector2(x, 20.0 - 90.0 * q)
		var s := 5.0 * (1.0 - q) + 2.0
		draw_line(pos - Vector2(s, 0), pos + Vector2(s, 0), Color(col.lightened(0.4), 1.0 - q), 2.0, true)
		draw_line(pos - Vector2(0, s), pos + Vector2(0, s), Color(col.lightened(0.4), 1.0 - q), 2.0, true)
	if tex != null:
		_draw_image(tex, c + Vector2(0, -70.0 * _ease_out(p)), 60.0, 0.0, 1.0 - p)
