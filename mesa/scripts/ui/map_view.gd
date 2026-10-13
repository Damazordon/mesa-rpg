class_name MapView
extends Control
## Centro: o mapa de exploração (MVP: cena com pins e tokens, distâncias por zona).
## Sem arte própria, desenha uma galeria de mina provisória.
## Para usar arte do grupo, salve assets/art/scenes/<background>.png (16:9).

signal token_hovered(id: String)
signal target_chosen(actor_id: String, ability: Dictionary, ids: Array)
signal targeting_changed(active: bool)

var hovered_id := ""
var linked_id := ""
var targeting := {}
var mouse := Vector2.ZERO
var bg_tex: Texture2D
var _t := 0.0
var _rocks: Array = []
var _rails: PackedVector2Array
var _crates: Array = []
var _lights: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_gen_scene()
	var path := "res://assets/art/scenes/%s.png" % Game.scene_info.get("background", "")
	if ResourceLoader.exists(path):
		bg_tex = load(path)
	Game.floating_text.connect(_on_floating)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ---------------------------------------------------------------- geometria

func to_px(n: Vector2) -> Vector2:
	return Vector2(n.x * size.x, n.y * size.y)


func token_radius() -> float:
	return clampf(size.y * 0.042, 20.0, 38.0)


func _token_at(p: Vector2) -> String:
	var r := token_radius()
	var best := ""
	var best_d := INF
	for c in Game.party + Game.enemies:
		var d := p.distance_to(to_px(c["pos"]))
		if d <= r + 4.0 and d < best_d:
			best = c["id"]
			best_d = d
	return best


func _ids_in_area(center: Vector2, radius_px: float) -> Array:
	var ids: Array = []
	for c in Game.party + Game.enemies:
		if Game.is_alive(c) and center.distance_to(to_px(c["pos"])) <= radius_px:
			ids.append(c["id"])
	return ids


# ---------------------------------------------------------------- mira

func begin_targeting(actor_id: String, ability: Dictionary) -> void:
	targeting = {"actor": actor_id, "ability": ability}
	targeting_changed.emit(true)


func cancel_targeting() -> void:
	if not targeting.is_empty():
		targeting = {}
		targeting_changed.emit(false)


func _area_px() -> float:
	return float(targeting["ability"].get("area", 0.0)) * size.y


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = event.position
		var h := _token_at(mouse)
		if h != hovered_id:
			hovered_id = h
			token_hovered.emit(h)
	elif event is InputEventMouseButton and event.pressed:
		if targeting.is_empty():
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_targeting()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var ab: Dictionary = targeting["ability"]
			var ids: Array = []
			if ab.get("target", "single") == "area":
				ids = _ids_in_area(mouse, _area_px())
			elif hovered_id != "":
				var t: Dictionary = Game.by_id[hovered_id]
				if t["side"] == "enemy" and Game.is_alive(t):
					ids = [hovered_id]
			if not ids.is_empty():
				var actor: String = targeting["actor"]
				targeting = {}
				targeting_changed.emit(false)
				target_chosen.emit(actor, ab, ids)
			accept_event()


# ---------------------------------------------------------------- textos flutuantes

func _on_floating(id: String, text: String, kind: String) -> void:
	var c: Dictionary = Game.by_id.get(id, {})
	if c.is_empty():
		return
	var l := Label.new()
	l.text = text
	var fs := 34
	var col := UiTheme.HP.lightened(0.2)
	match kind:
		"crit":
			fs = 48
			col = UiTheme.AMBER
		"heal":
			col = UiTheme.GOOD.lightened(0.2)
		"miss":
			fs = 26
			col = UiTheme.BONE_SOFT
	l.add_theme_font_override("font", UiTheme.sans_bold())
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.reset_size()
	var start := to_px(c["pos"]) - Vector2(l.size.x / 2.0, token_radius() + l.size.y)
	l.position = start
	l.pivot_offset = l.size / 2.0
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", start.y - 70.0, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.8)
	if kind == "crit":
		l.scale = Vector2(1.5, 1.5)
		tw.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------- cena provisória

func _gen_scene() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 34:
		var edge := i % 4
		var p := Vector2.ZERO
		match edge:
			0: p = Vector2(rng.randf(), rng.randf_range(-0.02, 0.1))
			1: p = Vector2(rng.randf(), rng.randf_range(0.9, 1.02))
			2: p = Vector2(rng.randf_range(-0.02, 0.07), rng.randf())
			3: p = Vector2(rng.randf_range(0.93, 1.02), rng.randf())
		_rocks.append(_rock(rng, p, rng.randf_range(0.05, 0.11)))
	for p in [Vector2(0.46, 0.27), Vector2(0.86, 0.72), Vector2(0.12, 0.45)]:
		_rocks.append(_rock(rng, p, rng.randf_range(0.035, 0.05)))
	_crates = [Vector2(0.53, 0.47), Vector2(0.58, 0.29), Vector2(0.09, 0.84), Vector2(0.88, 0.5)]
	_lights = [
		{"p": Vector2(0.24, 0.66), "r": 0.42, "a": 1.0},
		{"p": Vector2(0.55, 0.44), "r": 0.3, "a": 0.6},
		{"p": Vector2(0.84, 0.28), "r": 0.26, "a": 0.45},
	]
	_rails = PackedVector2Array()
	var a := Vector2(-0.05, 0.86)
	var ctrl := Vector2(0.48, 0.74)
	var b := Vector2(0.8, 0.02)
	for i in 41:
		var t := float(i) / 40.0
		_rails.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))


func _rock(rng: RandomNumberGenerator, center: Vector2, radius: float) -> Dictionary:
	var k: Array = []
	for i in 8:
		k.append(rng.randf_range(0.7, 1.15))
	return {"c": center, "r": radius, "k": k, "shade": rng.randf_range(0.0, 0.25)}


func _rock_poly(rk: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := to_px(rk["c"])
	var r: float = rk["r"] * size.y
	var k: Array = rk["k"]
	for i in k.size():
		var ang := TAU * float(i) / float(k.size())
		pts.append(c + Vector2(cos(ang), sin(ang)) * r * float(k[i]))
	return pts


func _draw_scene() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if bg_tex != null:
		var ts := bg_tex.get_size()
		var s := maxf(size.x / ts.x, size.y / ts.y)
		var dsize := ts * s
		draw_texture_rect(bg_tex, Rect2((size - dsize) / 2.0, dsize), false)
		return
	draw_rect(full, Color("221c17"))
	for lt in _lights:
		var p := to_px(lt["p"])
		var r: float = lt["r"] * size.y
		for i in 14:
			var f := 1.0 - float(i) / 14.0
			draw_circle(p, r * f, Color(1.0, 0.68, 0.32, 0.022 * float(lt["a"])))
	# Trilhos
	var px_rails := PackedVector2Array()
	for p in _rails:
		px_rails.append(to_px(p))
	var off := size.y * 0.016
	for i in range(0, px_rails.size() - 1, 2):
		var dir := (px_rails[i + 1] - px_rails[i]).normalized()
		var n := Vector2(-dir.y, dir.x)
		draw_line(px_rails[i] - n * off * 1.6, px_rails[i] + n * off * 1.6, Color("3b2c20"), size.y * 0.009)
	for side in [-1.0, 1.0]:
		var line := PackedVector2Array()
		for i in px_rails.size():
			var j := mini(i + 1, px_rails.size() - 1)
			var k := maxi(j - 1, 0)
			var dir2 := (px_rails[j] - px_rails[k]).normalized()
			line.append(px_rails[i] + Vector2(-dir2.y, dir2.x) * off * side)
		draw_polyline(line, Color("6a6158"), 2.5, true)
	# Caixotes
	for c in _crates:
		var cp := to_px(c)
		var s2 := size.y * 0.045
		var rect := Rect2(cp - Vector2(s2, s2) / 2.0, Vector2(s2, s2))
		draw_rect(rect, Color("4a3524"))
		draw_rect(rect, Color("2b1f15"), false, 2.0)
		draw_line(rect.position, rect.end, Color("2b1f15"), 2.0)
	# Rochas
	for rk in _rocks:
		var poly := _rock_poly(rk)
		draw_colored_polygon(poly, Color("15110e").lerp(Color("3a332c"), rk["shade"]))
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, Color(0, 0, 0, 0.45), 2.0, true)
	# Vinheta
	for i in 10:
		var w := size.y * 0.02
		draw_rect(Rect2(Vector2(i, i) * w * 0.6, size - Vector2(i, i) * w * 1.2), Color(0, 0, 0, 0.07), false, w)


func _draw_pins() -> void:
	var f := UiTheme.sans_medium()
	for pin in Game.scene_info.get("pins", []):
		var p := to_px(Vector2(pin["pos"][0], pin["pos"][1]))
		var top := p - Vector2(0, 22)
		draw_colored_polygon(PackedVector2Array([top + Vector2(-8, 4), top + Vector2(8, 4), p]), Color(UiTheme.BONE, 0.9))
		draw_circle(top, 9.0, Color(UiTheme.BONE, 0.95))
		draw_circle(top, 3.5, UiTheme.INK)
		var txt: String = pin["name"]
		var fs := 16
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := top + Vector2(14, 5)
		draw_rect(Rect2(lp + Vector2(-6, -15), Vector2(w + 12, 22)), Color(0, 0, 0, 0.55))
		draw_string(f, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.BONE)


# ---------------------------------------------------------------- tokens

func _draw_token(c: Dictionary, current_id: String, area_ids: Array) -> void:
	var p := to_px(c["pos"])
	var r := token_radius()
	var alive := Game.is_alive(c)
	var is_enemy: bool = c["side"] == "enemy"
	var base := Color(str(c.get("color", "#777777")))
	if not alive:
		base = Color("4a4540")
	draw_circle(p + Vector2(0, r * 0.18), r * 1.02, Color(0, 0, 0, 0.45))
	if c["id"] == current_id and alive:
		var pulse := 0.5 + 0.5 * sin(_t * 3.2)
		draw_circle(p, r + 9.0 + pulse * 3.0, Color(UiTheme.AMBER, 0.16 + 0.14 * pulse))
		draw_arc(p, r + 6.0, 0.0, TAU, 48, UiTheme.AMBER, 3.0, true)
	draw_circle(p, r, base.darkened(0.45))
	draw_circle(p, r - 3.0, base)
	var ring := UiTheme.ENEMY.lightened(0.15) if is_enemy else UiTheme.BONE
	if not alive:
		ring = Color(0.5, 0.5, 0.5)
	draw_arc(p, r - 1.5, 0.0, TAU, 48, ring, 3.0, true)
	var f := UiTheme.sans_bold()
	var fs := int(r * 0.75)
	var initials := Portrait.make_initials(str(c["name"]))
	var w := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var baseline := p.y + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
	draw_string(f, Vector2(p.x - w / 2.0, baseline), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95 if alive else 0.5))
	if not alive:
		draw_line(p + Vector2(-r, -r) * 0.6, p + Vector2(r, r) * 0.6, Color(UiTheme.HP, 0.85), 4.0, true)
		draw_line(p + Vector2(r, -r) * 0.6, p + Vector2(-r, r) * 0.6, Color(UiTheme.HP, 0.85), 4.0, true)
	# Mini barra de vida do grupo; inimigos mostram só o estado (ferido etc.) ao passar o mouse.
	if not is_enemy and alive:
		var bw := r * 1.8
		var bp := p + Vector2(-bw / 2.0, r + 6.0)
		draw_rect(Rect2(bp, Vector2(bw, 5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bp, Vector2(bw * float(c["hp"]) / float(c["hp_max"]), 5)), UiTheme.HP)
	if c["id"] in area_ids:
		var warn: bool = not is_enemy
		draw_arc(p, r + 4.0, 0.0, TAU, 48, UiTheme.HP if warn else UiTheme.AMBER, 3.5, true)
	elif c["id"] == hovered_id or c["id"] == linked_id:
		draw_arc(p, r + 4.0, 0.0, TAU, 48, Color(UiTheme.BONE, 0.9), 2.0, true)


func _draw_hover_card(current_id: String) -> void:
	if hovered_id == "":
		return
	var c: Dictionary = Game.by_id[hovered_id]
	var lines_out: Array = [c["name"]]
	if c["side"] == "enemy":
		lines_out.append("Estado: %s" % Game.health_word(c))
	else:
		lines_out.append("PV %d/%d, CA %d" % [c["hp"], c["hp_max"], c["ac"]])
	var cur: Dictionary = Game.by_id.get(current_id, {})
	if not cur.is_empty() and cur["id"] != c["id"]:
		lines_out.append("Distância de %s: %s" % [cur["name"], Game.zone_between(cur, c)])
	var f := UiTheme.sans()
	var fb := UiTheme.sans_bold()
	var w := 0.0
	for i in lines_out.size():
		w = maxf(w, (fb if i == 0 else f).get_string_size(str(lines_out[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
	var box_size := Vector2(w + 24, 14 + 22 * lines_out.size())
	var p := to_px(c["pos"]) + Vector2(token_radius() + 12, -box_size.y / 2.0)
	if p.x + box_size.x > size.x - 8:
		p.x = to_px(c["pos"]).x - token_radius() - 12 - box_size.x
	p.y = clampf(p.y, 8.0, size.y - box_size.y - 8.0)
	draw_rect(Rect2(p, box_size), Color(UiTheme.INK, 0.94))
	draw_rect(Rect2(p, box_size), UiTheme.WOOD_EDGE, false, 1.0)
	for i in lines_out.size():
		draw_string(fb if i == 0 else f, p + Vector2(12, 26 + 22 * i), str(lines_out[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.BONE if i == 0 else UiTheme.BONE_SOFT)


func _draw_targeting() -> Array:
	if targeting.is_empty():
		return []
	var actor: Dictionary = Game.by_id[targeting["actor"]]
	var ap := to_px(actor["pos"])
	var f := UiTheme.sans_medium()
	# Anéis de zona: perto, médio, longe
	# As zonas são medidas em coordenadas normalizadas do mapa, por isso viram elipses.
	var zone_names := ["perto", "médio"]
	var zone_radius := [0.2, 0.42]
	for i in 2:
		var zr: float = zone_radius[i]
		var ring := PackedVector2Array()
		for s in 97:
			var ang := TAU * float(s) / 96.0
			ring.append(ap + Vector2(cos(ang) * zr * size.x, sin(ang) * zr * size.y))
		draw_polyline(ring, Color(UiTheme.BONE, 0.22), 1.5, true)
		draw_string(f, ap + Vector2(-20, -zr * size.y - 6), zone_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UiTheme.BONE, 0.55))
	var ab: Dictionary = targeting["ability"]
	var hint := ""
	var area_ids: Array = []
	if ab.get("target", "single") == "area":
		var rr := _area_px()
		draw_circle(mouse, rr, Color(UiTheme.AMBER, 0.16))
		draw_arc(mouse, rr, 0.0, TAU, 64, UiTheme.AMBER, 2.0, true)
		area_ids = _ids_in_area(mouse, rr)
		hint = "%s: clique para lançar a área. Botão direito cancela." % ab["name"]
		for id in area_ids:
			if Game.by_id[id]["side"] == "party":
				hint = "Cuidado: aliados dentro da área. " + hint
				break
	else:
		draw_dashed_line(ap, mouse, Color(UiTheme.AMBER, 0.75), 2.0, 10.0)
		hint = "%s: escolha um inimigo. Botão direito cancela." % ab["name"]
	var fs := 18
	var w := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var hp := Vector2((size.x - w) / 2.0, 16)
	draw_rect(Rect2(hp - Vector2(16, 0), Vector2(w + 32, 34)), Color(UiTheme.INK, 0.9))
	draw_rect(Rect2(hp - Vector2(16, 0), Vector2(w + 32, 34)), UiTheme.AMBER, false, 1.5)
	draw_string(f, hp + Vector2(0, 24), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.BONE)
	return area_ids


func _draw() -> void:
	_draw_scene()
	_draw_pins()
	var current_id: String = Game.current().get("id", "")
	var area_ids := _draw_targeting()
	var all: Array = Game.enemies + Game.party
	all.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
	for c in all:
		_draw_token(c, current_id, area_ids)
	_draw_hover_card(current_id)
