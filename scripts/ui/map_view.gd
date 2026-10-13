class_name MapView
extends Control
## Centro: o tabuleiro. Retângulo 16:9 com escala real (18 m de altura, 32 m de largura).
## Com terreno (Game.terrain), desenha o mapa do capítulo no visual do bioma, a névoa do que o
## grupo ainda não viu e a prévia do caminho. Sem terreno (cenas antigas), a galeria de mina provisória.
## Para usar arte do grupo, salve assets/art/scenes/<background>.png (16:9).
##
## Interações:
##   clicar no próprio token (ou M)  -> modo de movimento: o círculo mostra até onde dá para ir
##   atalho de ataque               -> mira: o círculo mostra o alcance; fora dele não dá para clicar
##   clicar num NPC                 -> escolhe com quem falar (o mestre usa esse alvo)
##   botão direito ou Esc           -> cancela

signal token_hovered(id: String)
signal target_chosen(actor_id: String, ability: Dictionary, ids: Array, center: Vector2)
signal targeting_changed(active: bool)
signal move_mode_changed(active: bool)

var scene_only := false  # só o cenário, sem pins e tokens (usado para exportar a arte)
var fx: FxLayer
var token_offsets := {}
var last_area_point := Vector2(-1, -1)  # centro clicado da última área, normalizado
var hovered_id := ""
var linked_id := ""
var targeting := {}
var move_mode := false
## Quem está selecionado para andar na exploração (fora de combate).
var explore_sel := ""
var mouse := Vector2.ZERO
var bg_tex: Texture2D
var _t := 0.0
var _flash := ""
var _flash_until := 0.0
var _rocks: Array = []
var _rails: PackedVector2Array
var _crates: Array = []
var _lights: Array = []
var _terrain_tex: Texture2D
var _fog_tex: ImageTexture
var _wall_lines := PackedVector2Array()
## Prévia de caminho: recalcula só quando o ponteiro muda de lugar.
var _path_key := ""
var _path_prev := {}
## Área alcançável a pé no modo de movimento: células (metros) e a chave do cache.
var _reach_key := ""
var _reach_cells: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_gen_scene()
	_build_terrain()
	Game.vision_changed.connect(_refresh_fog)
	# Primeiro o mapa que o jogador importou para esta cena; depois a arte que vem com o jogo.
	var art_key := str(Game.scene_info.get("art_key", ""))
	if art_key == "":
		art_key = "%s_%s" % [str(Game.adventure.get("id", "")), str(Game.scene_info.get("id", ""))]
	bg_tex = ArtStore.scene_image(art_key)
	if bg_tex == null:
		var path := "res://assets/art/scenes/%s.png" % Game.scene_info.get("background", "")
		if ResourceLoader.exists(path):
			bg_tex = load(path)
	Game.floating_text.connect(_on_floating)
	fx = FxLayer.new()
	add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.lunge.connect(func(id, off): token_offsets[id] = off)
	Game.fx_requested.connect(_on_fx)
	Game.token_moved.connect(_on_token_moved)
	Game.turn_changed.connect(_on_turn_changed)


## Assa a imagem do terreno e as linhas de parede. Sem terreno, nada muda.
func _build_terrain() -> void:
	_terrain_tex = null
	_wall_lines = PackedVector2Array()
	if not Game.has_terrain():
		return
	_terrain_tex = TerrainPainter.bake(Game.terrain)
	if not TerrainPainter.organic(Game.terrain.biome):
		_wall_lines = TerrainPainter.wall_edges(Game.terrain)
	_refresh_fog()


func _refresh_fog() -> void:
	if not Game.has_terrain() or Game.seen.is_empty():
		_fog_tex = null
		return
	var img := TerrainPainter.fog_image(Game.terrain, Game.seen, Game.visible_now)
	if _fog_tex == null or _fog_tex.get_size() != Vector2(img.get_size()):
		_fog_tex = ImageTexture.create_from_image(img)
	else:
		_fog_tex.update(img)


func _on_turn_changed(_id: String, _round: int) -> void:
	cancel_targeting()
	cancel_move()
	explore_sel = ""


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ---------------------------------------------------------------- geometria

## Maior retângulo 16:9 que cabe no espaço do mapa.
func board() -> Rect2:
	var w := size.x
	var h := w / Game.BOARD_ASPECT
	if h > size.y:
		h = size.y
		w = h * Game.BOARD_ASPECT
	return Rect2((size - Vector2(w, h)) / 2.0, Vector2(w, h))


func to_px(n: Vector2) -> Vector2:
	var b := board()
	return b.position + Vector2(n.x * b.size.x, n.y * b.size.y)


func from_px(p: Vector2) -> Vector2:
	var b := board()
	return Vector2((p.x - b.position.x) / b.size.x, (p.y - b.position.y) / b.size.y)


func px_per_m() -> float:
	return board().size.y / Game.BOARD_H_M


func token_radius() -> float:
	return Game.TOKEN_RADIUS_M * px_per_m()


func _token_px(c: Dictionary) -> Vector2:
	var offset: Vector2 = token_offsets.get(c["id"], Vector2.ZERO)
	return to_px(c["pos"]) + offset


## Com terreno, criatura que não é do grupo e está fora da vista do grupo não aparece.
func hidden(c: Dictionary) -> bool:
	if not Game.has_terrain() or Game.visible_now.is_empty() or c.get("side", "") == "party":
		return false
	var cell := TerrainMap.cell_of(Game.to_m(c["pos"]))
	var i := cell.y * Game.terrain.w + cell.x
	return i >= 0 and i < Game.visible_now.size() and Game.visible_now[i] == 0


func _token_at(p: Vector2) -> String:
	var r := token_radius()
	var best := ""
	var best_d := INF
	for c in Game.all_combatants():
		if hidden(c):
			continue
		var d := p.distance_to(to_px(c["pos"]))
		if d <= r + 4.0 and d < best_d:
			best = c["id"]
			best_d = d
	return best


func _ids_in_area(center_px: Vector2, radius_px: float) -> Array:
	var ids: Array = []
	for c in Game.all_combatants():
		if Game.is_alive(c) and center_px.distance_to(to_px(c["pos"])) <= radius_px:
			ids.append(c["id"])
	return ids


func flash(text: String) -> void:
	_flash = text
	_flash_until = _t + 3.0


# ---------------------------------------------------------------- modos

func begin_targeting(actor_id: String, ability: Dictionary) -> void:
	cancel_move()
	targeting = {"actor": actor_id, "ability": ability, "picks": []}
	targeting_changed.emit(true)


## Com vários alvos (Mísseis Mágicos, Bênção...): confirma com os escolhidos até agora.
func confirm_targets() -> void:
	if targeting.is_empty() or targeting["picks"].is_empty():
		return
	_fire(targeting["picks"].duplicate(), Vector2(-1, -1))


func _fire(ids: Array, center: Vector2) -> void:
	var ab: Dictionary = targeting["ability"]
	var actor_id: String = targeting["actor"]
	targeting = {}
	targeting_changed.emit(false)
	target_chosen.emit(actor_id, ab, ids, center)


func cancel_targeting() -> void:
	if not targeting.is_empty():
		targeting = {}
		targeting_changed.emit(false)


func begin_move() -> bool:
	if not Game.is_party_turn() or Game.busy:
		return false
	if Game.item_used:
		flash("Você usou um item neste turno; item e movimento dividem o mesmo slot.")
		return false
	if Game.move_left <= 0.05:
		flash("Sem movimento sobrando neste turno.")
		return false
	cancel_targeting()
	move_mode = true
	move_mode_changed.emit(true)
	return true


func cancel_move() -> void:
	if move_mode:
		move_mode = false
		move_mode_changed.emit(false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = event.position
		var h := _token_at(mouse)
		if h != hovered_id:
			hovered_id = h
			token_hovered.emit(h)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	accept_event()
	if event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_targeting()
		cancel_move()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if move_mode:
		_click_move()
	elif not targeting.is_empty():
		_click_target()
	elif Game.ex.active():
		_click_explore()
	else:
		_click_idle()


func _click_idle() -> void:
	var cur := Game.current()
	if hovered_id == "":
		return
	if Game.is_party_turn() and hovered_id == cur["id"]:
		begin_move()
	elif Game.by_id[hovered_id]["side"] != "party" and Game.is_alive(Game.by_id[hovered_id]):
		Game.select_target("" if Game.selected_target == hovered_id else hovered_id)


## Exploração: clique num personagem do grupo para escolher quem anda, clique no chão para andar.
func _click_explore() -> void:
	if hovered_id != "" and Game.by_id.has(hovered_id) and Game.by_id[hovered_id]["side"] == "party":
		explore_sel = "" if explore_sel == hovered_id else hovered_id
		return
	if explore_sel == "":
		flash("Clique num personagem do grupo para escolher quem anda.")
		return
	var err: String = Game.ex.explore_move(explore_sel, from_px(mouse))
	if err != "":
		flash(err)


func _click_move() -> void:
	var cur := Game.current()
	if hovered_id == cur.get("id", ""):
		cancel_move()
		return
	var err := Game.move_token(cur["id"], from_px(mouse))
	if err != "":
		flash(err)
	else:
		cancel_move()


func _target_ok(actor: Dictionary, ab: Dictionary, t: Dictionary) -> String:
	var kind: String = ab.get("target", "enemy")
	if t.is_empty():
		return "Escolha um alvo."
	var dead: bool = t.get("death", {}).get("dead", false)
	var stab := str(ab.get("ref", "")) in ["spare_the_dying", "revivify"] or str(ab.get("id", "")).contains("revivify") or str(ab.get("id", "")).contains("spare_the_dying")
	if (not Game.is_alive(t) and not stab) or (dead and not str(ab.get("id", "")).contains("revivify")):
		return "Esse alvo está fora de combate."
	match kind:
		"enemy":
			if not Game.hostile(actor, t):
				return "Escolha um inimigo."
		"ally":
			if Game.hostile(actor, t):
				return "Escolha um aliado (ou você mesmo)."
	var d: float = Game.dist_between(actor, t)
	var reach: float = Game.ability_range(ab)
	if d > reach + 0.05:
		return "%s está a %s; o alcance de %s é %s.%s" % [t["name"], Game.fmt_m(d), ab["name"], Game.fmt_m(reach), " Mova-se primeiro (M)." if Game.is_party_turn() else ""]
	if actor["id"] != t["id"] and Game.has_terrain() and Game.cover_between(actor, t) >= TerrainMap.COVER_TOTAL:
		return "%s está atrás de cobertura total: sem linha de visão.%s" % [t["name"], " Mova-se primeiro (M)." if Game.is_party_turn() else ""]
	return ""


func _click_target() -> void:
	var ab: Dictionary = targeting["ability"]
	var actor: Dictionary = Game.by_id[targeting["actor"]]
	var kind: String = ab.get("target", "enemy")
	if kind in ["point", "direction"]:
		var center := from_px(mouse)
		var area: Dictionary = ab.get("area", {})
		if kind == "point" and Game.dist_m(actor["pos"], center) > Game.ability_range(ab) + 0.05:
			flash("O centro da área precisa ficar a até %s de %s." % [Game.fmt_m(Game.ability_range(ab)), actor["name"]])
			return
		if kind == "point" and Game.has_terrain() and not Game.line_clear(actor["pos"], center):
			flash("%s não enxerga esse ponto: escolha um lugar à vista." % actor["name"])
			return
		var ids: Array = _area_ids(actor, ab, center)
		if ids.is_empty() and not area.is_empty():
			flash("Ninguém dentro da área.")
			return
		last_area_point = center
		_fire(ids, center)
		return
	if hovered_id == "":
		return
	var t: Dictionary = Game.by_id[hovered_id]
	var err := _target_ok(actor, ab, t)
	if err != "":
		flash(err)
		return
	var count: int = int(ab.get("count", 1))
	if count <= 1:
		_fire([hovered_id], Vector2(-1, -1))
		return
	targeting["picks"].append(hovered_id)
	if targeting["picks"].size() >= count:
		_fire(targeting["picks"].duplicate(), Vector2(-1, -1))


func _area_ids(actor: Dictionary, ab: Dictionary, center: Vector2) -> Array:
	var area: Dictionary = ab.get("area", {})
	if area.is_empty():
		return []
	var origin_self: bool = area.get("origin", "point") == "self" or area.get("shape", "") == "emanation"
	return Game.cb.in_area(actor, str(area["shape"]), float(area["size_ft"]), center, origin_self).map(func(c): return c["id"])


# ---------------------------------------------------------------- animações

func _on_token_moved(id: String, from: Vector2, to: Vector2, duration: float) -> void:
	var route: PackedVector2Array = Game.move_paths.get(id, PackedVector2Array())
	Game.move_paths.erase(id)
	if route.size() > 2:
		# Segue o caminho de verdade (contornando paredes), não a reta.
		var pts := PackedVector2Array()
		for p in route:
			pts.append(to_px(p))
		var total := 0.0
		for i in range(1, pts.size()):
			total += pts[i - 1].distance_to(pts[i])
		var end_px := to_px(to)
		token_offsets[id] = pts[0] - end_px
		var tw0 := create_tween()
		tw0.tween_method(func(f: float): token_offsets[id] = _along(pts, total * f) - end_px, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	var start := to_px(from) - to_px(to)
	token_offsets[id] = start
	var tw := create_tween()
	tw.tween_method(func(v: Vector2): token_offsets[id] = v, start, Vector2.ZERO, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func _along(pts: PackedVector2Array, dist: float) -> Vector2:
	var left := dist
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if left <= seg:
			return pts[i - 1].lerp(pts[i], left / maxf(seg, 0.001))
		left -= seg
	return pts[pts.size() - 1]


func _on_fx(actor_id: String, ability: Dictionary, target_ids: Array) -> void:
	var a: Dictionary = Game.by_id.get(actor_id, {})
	if a.is_empty():
		return
	var template := ArtStore.template_for(actor_id, ability)
	var dtype: String = ability.get("dtype", "")
	var col := ArtStore.dtype_color(dtype)
	if template == "cura" and dtype == "":
		col = UiTheme.GOOD.lightened(0.2)
	var params := {
		"template": template, "actor_id": actor_id, "color": col,
		"tex": ArtStore.fx_image(actor_id, str(ability.get("id", ""))),
		"from": to_px(a["pos"]), "to": to_px(a["pos"]),
	}
	match template:
		"cura":
			fx.play(params)
		"area":
			var center := last_area_point
			if center.x < 0.0:
				center = Vector2.ZERO
				for id in target_ids:
					center += Game.by_id[id]["pos"]
				center /= maxf(1.0, float(target_ids.size()))
			params["to"] = to_px(center)
			params["radius"] = float(ability.get("area_m", 3.0)) * px_per_m()
			fx.play(params)
		_:
			for id in target_ids:
				var p2: Dictionary = params.duplicate()
				p2["to"] = to_px(Game.by_id[id]["pos"])
				fx.play(p2)
	last_area_point = Vector2(-1, -1)


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
	var r: float = rk["r"] * board().size.y
	var k: Array = rk["k"]
	for i in k.size():
		var ang := TAU * float(i) / float(k.size())
		pts.append(c + Vector2(cos(ang), sin(ang)) * r * float(k[i]))
	return pts


func _draw_scene() -> void:
	var b := board()
	if Game.has_terrain():
		_draw_terrain(b)
		return
	if bg_tex != null:
		draw_texture_rect(bg_tex, b, false)
		return
	draw_rect(b, Color("221c17"))
	for lt in _lights:
		var p := to_px(lt["p"])
		var r: float = lt["r"] * b.size.y
		for i in 14:
			var f := 1.0 - float(i) / 14.0
			draw_circle(p, r * f, Color(1.0, 0.68, 0.32, 0.022 * float(lt["a"])))
	# Trilhos
	var px_rails := PackedVector2Array()
	for p in _rails:
		px_rails.append(to_px(p))
	var off := b.size.y * 0.016
	for i in range(0, px_rails.size() - 1, 2):
		var dir := (px_rails[i + 1] - px_rails[i]).normalized()
		var n := Vector2(-dir.y, dir.x)
		draw_line(px_rails[i] - n * off * 1.6, px_rails[i] + n * off * 1.6, Color("3b2c20"), b.size.y * 0.009)
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
		var s2 := b.size.y * 0.045
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
		var w := b.size.y * 0.02
		draw_rect(Rect2(b.position + Vector2(i, i) * w * 0.6, b.size - Vector2(i, i) * w * 1.2), Color(0, 0, 0, 0.07), false, w)


## Terreno: imagem assada (ou a arte importada, com o terreno por cima em transparência),
## contorno das paredes e os objetos em vetor.
func _draw_terrain(b: Rect2) -> void:
	var ppm := px_per_m()
	if bg_tex != null:
		# A arte importada não conhece o traçado: o terreno vai por cima, discreto, para quem joga
		# saber onde está a parede de verdade.
		draw_texture_rect(bg_tex, b, false)
		if _terrain_tex != null:
			draw_texture_rect(_terrain_tex, b, false, Color(1, 1, 1, 0.35))
	elif _terrain_tex != null:
		draw_texture_rect(_terrain_tex, b, false)
	for i in range(0, _wall_lines.size() - 1, 2):
		draw_line(b.position + _wall_lines[i] * ppm, b.position + _wall_lines[i + 1] * ppm, Color(0, 0, 0, 0.55), 2.0)
	TerrainPainter.draw_props(self, Game.terrain, b.position, ppm, 0.9 if bg_tex != null else 1.0, _t)


func _draw_fog(b: Rect2) -> void:
	if _fog_tex == null or scene_only:
		return
	draw_texture_rect(_fog_tex, b, false)


## Prévia do caminho até o ponteiro: {"points" (px), "cost", "ok"}. Em cache por posição.
func _preview_path(c: Dictionary, budget: float) -> Dictionary:
	var dest := Game.settle(from_px(mouse))
	var key := "%s|%d|%d|%.2f|%s|%d" % [c["id"], int(dest.x * 400.0), int(dest.y * 400.0), budget, str(c["pos"]), Game.enemies.size()]
	if key == _path_key:
		return _path_prev
	_path_key = key
	_path_prev = {}
	if not Game.walkable(dest):
		_path_prev = {"points": PackedVector2Array([to_px(c["pos"]), mouse]), "cost": 0.0, "ok": false, "why": "ali não dá para pisar"}
		return _path_prev
	var plan := Game.plan_path(c, dest)
	if plan.is_empty():
		_path_prev = {"points": PackedVector2Array([to_px(c["pos"]), mouse]), "cost": 0.0, "ok": false, "why": "sem caminho"}
		return _path_prev
	var pts := PackedVector2Array()
	for p in plan["points"]:
		pts.append(to_px(p))
	_path_prev = {"points": pts, "cost": float(plan["cost"]), "ok": float(plan["cost"]) <= budget + 0.05, "why": "",
		"rough": float(plan["cost"]) > float(plan["length"]) + 0.1}
	return _path_prev


func _draw_path_preview(pv: Dictionary, col: Color) -> void:
	var pts: PackedVector2Array = pv["points"]
	for i in range(1, pts.size()):
		draw_dashed_line(pts[i - 1], pts[i], Color(col, 0.85), 2.5, 10.0)
	for i2 in range(1, pts.size() - 1):
		draw_circle(pts[i2], 3.0, Color(col, 0.7))


## Legenda do terreno sob o ponteiro (só quando ajuda: andando ou explorando).
func _draw_cell_hint() -> void:
	if not Game.has_terrain() or hovered_id != "" or not targeting.is_empty():
		return
	if not (move_mode or (Game.ex.active() and explore_sel != "")):
		return
	var m := Game.to_m(from_px(mouse))
	var cell := TerrainMap.cell_of(m)
	var txt := TerrainPainter.cell_text(Game.terrain.atv(cell), MapGen.biome(Game.terrain.biome))
	if txt == "":
		return
	if not Game.seen.is_empty():
		var i := cell.y * Game.terrain.w + cell.x
		if i >= 0 and i < Game.seen.size() and Game.seen[i] == 0:
			return
	var f := UiTheme.sans()
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var p := mouse + Vector2(16, 30)
	draw_rect(Rect2(p - Vector2(8, 16), Vector2(w + 16, 22)), Color(UiTheme.INK, 0.9))
	draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.BONE_SOFT)


## Exploração: ponto pressentido vira "?", descoberto mostra o nome, visitado fica apagado.
## A saída aparece trancada enquanto faltar ponto obrigatório.
func _draw_pois() -> void:
	var f := UiTheme.sans_medium()
	for poi in Game.pois:
		if not poi["sensed"]:
			continue
		var p := to_px(poi["pos"])
		if not poi["found"]:
			draw_circle(p, 13.0, Color(UiTheme.BONE, 0.08))
			_draw_dashed_circle(p, 13.0, Color(UiTheme.BONE, 0.35), 1.5)
			draw_string(f, p + Vector2(-4, 6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(UiTheme.BONE, 0.6))
			continue
		var kind := str(poi["kind"])
		var done: bool = poi["taken"]
		var locked: bool = kind == "exit" and not Game.ex.exit_open()
		var col := UiTheme.BONE
		var glyph := "!"
		match kind:
			"chest":
				col = UiTheme.AMBER
				glyph = "o"
			"exit":
				col = UiTheme.MISS if locked else UiTheme.GOOD
				glyph = ">"
		var a := 0.4 if done else 1.0
		draw_circle(p, 12.0, Color(col, 0.22 * a))
		draw_arc(p, 12.0, 0.0, TAU, 28, Color(col, 0.9 * a), 2.0)
		if not done:
			draw_string(f, p + Vector2(-5, 6), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
		var txt := str(poi["name"])
		if locked:
			txt += " (faltam %d ponto(s))" % Game.ex.required_left()
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var lp := p + Vector2(18, 5)
		draw_rect(Rect2(lp + Vector2(-6, -14), Vector2(w + 12, 20)), Color(0, 0, 0, 0.55 * a))
		draw_string(f, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiTheme.BONE, a))


## Quem está escolhido para andar, e para onde o clique vai levar.
func _draw_explore() -> void:
	if explore_sel == "" or not Game.by_id.has(explore_sel):
		return
	var p := _token_px(Game.by_id[explore_sel])
	_draw_dashed_circle(p, token_radius() + 8.0, UiTheme.AMBER, 2.0)
	if hovered_id != "":
		return
	if Game.has_terrain():
		var pv := _preview_path(Game.by_id[explore_sel], INF)
		_draw_path_preview(pv, UiTheme.AMBER if pv["ok"] else UiTheme.HP)
	else:
		draw_line(p, mouse, Color(UiTheme.AMBER, 0.3), 2.0)


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

func _ring_color(c: Dictionary) -> Color:
	if not Game.is_alive(c):
		return Color(0.5, 0.5, 0.5)
	match c["side"]:
		"enemy":
			return UiTheme.ENEMY.lightened(0.15)
		"ally":
			return UiTheme.GOOD.lightened(0.1)
		"neutral":
			return UiTheme.BONE_SOFT
	return UiTheme.BONE


func _draw_token(c: Dictionary, current_id: String, area_ids: Array) -> void:
	var p := _token_px(c)
	var r := token_radius()
	var alive := Game.is_alive(c)
	var base := Color(str(c.get("color", "#777777")))
	if not alive:
		base = Color("4a4540")
	elif c["side"] == "neutral":
		base = base.lerp(Color(0.5, 0.5, 0.5), 0.5)
	draw_circle(p + Vector2(0, r * 0.18), r * 1.02, Color(0, 0, 0, 0.45))
	if c["id"] == current_id and alive:
		var pulse := 0.5 + 0.5 * sin(_t * 3.2)
		draw_circle(p, r + 9.0 + pulse * 3.0, Color(UiTheme.AMBER, 0.16 + 0.14 * pulse))
		draw_arc(p, r + 6.0, 0.0, TAU, 48, UiTheme.AMBER, 3.0, true)
	draw_circle(p, r, base.darkened(0.45))
	draw_circle(p, r - 3.0, base)
	var tex := ArtStore.token(str(c["id"]))
	if tex != null:
		Portrait.draw_circle_texture(self, tex, p, r - 3.0, Color.WHITE if alive else Color(0.4, 0.4, 0.4))
	else:
		var f := UiTheme.sans_bold()
		var fs := int(r * 0.72)
		var initials := Portrait.make_initials(str(c["name"]))
		var w := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var baseline := p.y + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
		draw_string(f, Vector2(p.x - w / 2.0, baseline), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95 if alive else 0.5))
	draw_arc(p, r - 1.5, 0.0, TAU, 48, _ring_color(c), 3.0, true)
	if not alive:
		draw_line(p + Vector2(-r, -r) * 0.6, p + Vector2(r, r) * 0.6, Color(UiTheme.HP, 0.85), 4.0, true)
		draw_line(p + Vector2(r, -r) * 0.6, p + Vector2(-r, r) * 0.6, Color(UiTheme.HP, 0.85), 4.0, true)
	elif c["side"] == "ally":
		# Bandeirinha verde: passou para o lado do grupo.
		draw_circle(p + Vector2(r * 0.72, -r * 0.72), 7.0, UiTheme.GOOD)
		draw_arc(p + Vector2(r * 0.72, -r * 0.72), 7.0, 0.0, TAU, 20, Color.WHITE, 1.5, true)
	elif c["side"] == "neutral":
		draw_rect(Rect2(p + Vector2(r * 0.55, -r * 1.05), Vector2(12, 9)), Color.WHITE)
		draw_line(p + Vector2(r * 0.55, -r * 1.05), p + Vector2(r * 0.55, -r * 0.45), Color.WHITE, 2.0)
	if Game.has_condition(c, "escondido"):
		draw_arc(p, r + 3.0, 0.0, TAU, 32, Color(UiTheme.BONE, 0.5), 2.0, true)
		draw_circle(p, r, Color(0, 0, 0, 0.35))
	# Mini barra de vida: grupo e aliados. Inimigos mostram só o estado ao passar o mouse.
	if Game.is_hero(c) and alive:
		var bw := r * 1.8
		var bp := p + Vector2(-bw / 2.0, r + 6.0)
		draw_rect(Rect2(bp, Vector2(bw, 5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bp, Vector2(bw * float(c["hp"]) / float(c["hp_max"]), 5)), UiTheme.HP)
	if c["id"] == Game.selected_target and alive:
		var pulse2 := 0.5 + 0.5 * sin(_t * 2.0)
		draw_arc(p, r + 8.0, 0.0, TAU, 48, Color(1, 1, 1, 0.5 + 0.4 * pulse2), 2.0, true)
		draw_arc(p, r + 12.0, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 1.5, true)
	if c["id"] in area_ids:
		draw_arc(p, r + 4.0, 0.0, TAU, 48, UiTheme.HP if c["side"] == "party" else UiTheme.AMBER, 3.5, true)
	elif c["id"] == hovered_id or c["id"] == linked_id:
		draw_arc(p, r + 4.0, 0.0, TAU, 48, Color(UiTheme.BONE, 0.9), 2.0, true)


func _draw_hover_card(current_id: String) -> void:
	if hovered_id == "" or move_mode or not Game.by_id.has(hovered_id):
		return
	var c: Dictionary = Game.by_id[hovered_id]
	if hidden(c):
		return
	var lines_out: Array = [c["name"]]
	if c["side"] == "party":
		lines_out.append("PV %d/%d%s, CA %d" % [c["hp"], c["hp_max"], (" +%d" % int(c.get("temp_hp", 0))) if int(c.get("temp_hp", 0)) > 0 else "", Rules.ac(c)])
	else:
		lines_out.append("%s, %s" % [Game.side_word(c).capitalize(), Game.health_word(c)])
	var cur: Dictionary = Game.by_id.get(current_id, {})
	if not cur.is_empty() and cur["id"] != c["id"]:
		var d := Game.dist_between(cur, c)
		var line := "A %s de %s" % [Game.fmt_m(d), cur["name"]]
		if not targeting.is_empty() and targeting["ability"].get("target", "") in ["enemy", "ally", "creature"]:
			var ok := d <= Game.ability_range(targeting["ability"]) + 0.05
			line += ": no alcance" if ok else ": fora do alcance"
		lines_out.append(line)
		if Game.has_terrain() and Game.in_combat:
			var cov := Game.cover_between(cur, c)
			if cov >= TerrainMap.COVER_TOTAL:
				lines_out.append("Sem linha de visão (cobertura total)")
			elif cov > 0:
				lines_out.append("%s: +%d na CA" % [TerrainMap.cover_name(cov).capitalize(), cov])
	var conds := PackedStringArray()
	for cd in c.get("conditions", []):
		if Game.conditions.has(cd["id"]):
			conds.append(Game.conditions[cd["id"]]["name"])
	if not conds.is_empty():
		lines_out.append(", ".join(conds))
	if c["side"] != "party" and Game.is_alive(c) and targeting.is_empty():
		lines_out.append("Clique para falar com ele")
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


func _draw_dashed_circle(center: Vector2, radius: float, col: Color, width := 2.0) -> void:
	var seg := 48
	for i in seg:
		if i % 2 == 0:
			draw_arc(center, radius, TAU * i / seg, TAU * (i + 1) / seg, 4, col, width, true)


func _draw_banner(text: String, col: Color) -> void:
	var f := UiTheme.sans_medium()
	var fs := 18
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var hp := Vector2((size.x - w) / 2.0, 16)
	draw_rect(Rect2(hp - Vector2(16, 0), Vector2(w + 32, 34)), Color(UiTheme.INK, 0.92))
	draw_rect(Rect2(hp - Vector2(16, 0), Vector2(w + 32, 34)), col, false, 1.5)
	draw_string(f, hp + Vector2(0, 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.BONE)


func _draw_move_mode() -> void:
	var cur := Game.current()
	if cur.is_empty():
		return
	var ap := to_px(cur["pos"])
	var radius := Game.move_left * px_per_m()
	if Game.has_terrain():
		_draw_reach(cur)
	else:
		draw_circle(ap, radius, Color(UiTheme.BONE, 0.06))
		_draw_dashed_circle(ap, radius, Color(UiTheme.BONE, 0.6))
	var dest := from_px(mouse)
	var d := Game.dist_m(cur["pos"], dest)
	var ok := d <= Game.move_left + 0.05
	var col := UiTheme.BONE if ok else UiTheme.HP
	if Game.has_terrain():
		var budget := Game.move_left / (2.0 if Rules.has_condition(cur, "prone") else 1.0)
		var pv := _preview_path(cur, budget)
		ok = pv["ok"]
		d = float(pv["cost"])
		col = UiTheme.BONE if ok else UiTheme.HP
		_draw_path_preview(pv, col)
	else:
		draw_dashed_line(ap, mouse, Color(col, 0.8), 2.0, 10.0)
	draw_arc(mouse, token_radius(), 0.0, TAU, 40, Color(col, 0.7), 2.0, true)
	draw_circle(mouse, token_radius(), Color(col, 0.12))
	var f := UiTheme.sans_bold()
	var label := Game.fmt_m(d)
	if Game.has_terrain():
		var pv2: Dictionary = _path_prev
		if not pv2.is_empty() and str(pv2.get("why", "")) != "":
			label = str(pv2["why"])
		elif pv2.get("rough", false):
			label += " (terreno difícil)"
	var ls := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	var lp := mouse + Vector2(-ls.x / 2.0, -token_radius() - 12)
	draw_rect(Rect2(lp + Vector2(-6, -ls.y + 2), ls + Vector2(12, 6)), Color(0, 0, 0, 0.7))
	draw_string(f, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
	_draw_banner("Mover %s: clique no destino (resta %s). Botão direito cancela." % [cur["name"], Game.fmt_m(Game.move_left)], UiTheme.BONE_SOFT)


## Com terreno: pinta as células que dá para alcançar a pé com o movimento que resta.
func _draw_reach(cur: Dictionary) -> void:
	var budget := Game.move_left / (2.0 if Rules.has_condition(cur, "prone") else 1.0)
	var key := "%s|%s|%.2f|%d" % [cur["id"], str(cur["pos"]), budget, Game.enemies.size()]
	if key != _reach_key:
		_reach_key = key
		_reach_cells = []
		var field := Game.terrain.cost_field(Game.to_m(cur["pos"]), budget, Game.blocked_cells_for(cur))
		for cell in field:
			_reach_cells.append(cell)
	var ppm := px_per_m()
	var b := board()
	var fill := Color(UiTheme.BONE, 0.09)
	for cell2 in _reach_cells:
		draw_rect(Rect2(b.position + Vector2(cell2.x, cell2.y) * ppm, Vector2(ppm, ppm)), fill)


func _draw_targeting() -> Array:
	if targeting.is_empty():
		return []
	var actor: Dictionary = Game.by_id[targeting["actor"]]
	var ap := to_px(actor["pos"])
	var ab: Dictionary = targeting["ability"]
	var kind: String = ab.get("target", "enemy")
	var reach := Game.ability_range(ab)
	var reach_px := reach * px_per_m()
	var f := UiTheme.sans_medium()
	if kind != "direction":
		draw_circle(ap, reach_px, Color(UiTheme.AMBER, 0.05))
		_draw_dashed_circle(ap, reach_px, Color(UiTheme.AMBER, 0.55))
		draw_string(f, ap + Vector2(-30, -reach_px - 8), "alcance %s" % Game.fmt_m(reach), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UiTheme.AMBER, 0.85))
	var hint := ""
	var area_ids: Array = []
	if kind in ["point", "direction"]:
		var center := from_px(mouse)
		var inside := kind == "direction" or Game.dist_m(actor["pos"], center) <= reach + 0.05
		if kind == "point" and Game.has_terrain() and not Game.line_clear(actor["pos"], center):
			inside = false
		var col := UiTheme.AMBER if inside else UiTheme.HP
		_draw_area_shape(actor, ab, col)
		if inside:
			area_ids = _area_ids(actor, ab, center)
		hint = "%s: %s. Botão direito cancela." % [ab["name"], "aponte a direção e clique" if kind == "direction" else "clique para escolher o centro"]
		if not inside:
			hint = "Fora do alcance: o centro precisa ficar a até %s." % Game.fmt_m(reach)
			if Game.dist_m(actor["pos"], center) <= reach + 0.05:
				hint = "%s não enxerga esse ponto: escolha um lugar à vista." % actor["name"]
		for id in area_ids:
			if not Game.hostile(actor, Game.by_id[id]):
				hint = "Cuidado: aliados dentro da área. " + hint
				break
	else:
		for c in Game.all_combatants():
			if Game.is_alive(c) and _target_ok(actor, ab, c) != "" and c["id"] != actor["id"]:
				draw_circle(_token_px(c), token_radius(), Color(0, 0, 0, 0.45))
		var over: Dictionary = Game.by_id.get(hovered_id, {})
		var ok := not over.is_empty() and _target_ok(actor, ab, over) == ""
		draw_dashed_line(ap, mouse, Color(UiTheme.AMBER if ok or over.is_empty() else UiTheme.HP, 0.75), 2.0, 10.0)
		var who := {"enemy": "um inimigo", "ally": "um aliado", "creature": "um alvo"}.get(kind, "um alvo") as String
		hint = "%s: escolha %s dentro do círculo. Botão direito cancela." % [ab["name"], who]
		var count: int = int(ab.get("count", 1))
		if count > 1:
			var picks: Array = targeting["picks"]
			var names := PackedStringArray()
			for id in picks:
				names.append(Game.by_id[id]["name"])
				draw_arc(_token_px(Game.by_id[id]), token_radius() + 6, 0, TAU, 32, UiTheme.AMBER, 3.0, true)
			hint = "%s: %d de %d alvos%s. Clique de novo para repetir alvo; Enter confirma." % [ab["name"], picks.size(), count, (" (" + ", ".join(names) + ")") if not names.is_empty() else ""]
	_draw_banner(hint, UiTheme.AMBER)
	return area_ids


## Desenha esfera, cubo, cone ou linha no ponteiro (ou a partir do conjurador).
func _draw_area_shape(actor: Dictionary, ab: Dictionary, col: Color) -> void:
	var area: Dictionary = ab.get("area", {})
	if area.is_empty():
		return
	var ppm := px_per_m()
	var size: float = float(area["size_ft"]) * 0.3 * ppm
	var ap := to_px(actor["pos"])
	var dir := (mouse - ap).normalized() if mouse.distance_to(ap) > 1.0 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	var fill := Color(col, 0.16)
	match str(area["shape"]):
		"sphere", "cylinder":
			draw_circle(mouse, size, fill)
			draw_arc(mouse, size, 0.0, TAU, 64, col, 2.0, true)
		"emanation":
			draw_circle(ap, size, fill)
			draw_arc(ap, size, 0.0, TAU, 64, col, 2.0, true)
		"cone":
			var tip := ap + dir * size
			var pts := PackedVector2Array([ap, tip + perp * size * 0.5, tip - perp * size * 0.5])
			draw_colored_polygon(pts, fill)
			draw_polyline(PackedVector2Array([ap, pts[1], pts[2], ap]), col, 2.0, true)
		"line":
			var w := 1.5 * ppm * 0.5
			var pts2 := PackedVector2Array([ap + perp * w, ap + perp * w + dir * size, ap - perp * w + dir * size, ap - perp * w])
			draw_colored_polygon(pts2, fill)
			draw_polyline(PackedVector2Array([pts2[0], pts2[1], pts2[2], pts2[3], pts2[0]]), col, 2.0, true)
		"cube":
			var pts3: PackedVector2Array
			if area.get("origin", "point") == "self":
				pts3 = PackedVector2Array([ap + perp * size * 0.5, ap + perp * size * 0.5 + dir * size, ap - perp * size * 0.5 + dir * size, ap - perp * size * 0.5])
			else:
				var h := size * 0.5
				pts3 = PackedVector2Array([mouse + Vector2(-h, -h), mouse + Vector2(h, -h), mouse + Vector2(h, h), mouse + Vector2(-h, h)])
			draw_colored_polygon(pts3, fill)
			draw_polyline(PackedVector2Array([pts3[0], pts3[1], pts3[2], pts3[3], pts3[0]]), col, 2.0, true)


func _draw() -> void:
	var b := board()
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.FELT_DEEP)
	_draw_scene()
	if scene_only:
		return
	_draw_fog(b)
	if Game.ex.has_exploration():
		_draw_pois()
	else:
		_draw_pins()
	var current_id: String = Game.current().get("id", "")
	if Game.ex.active():
		_draw_explore()
		_draw_banner("Explorando · %s" % Game.ex.progress_text(), UiTheme.BONE)
	if move_mode:
		_draw_move_mode()
	var area_ids := _draw_targeting()
	var all: Array = Game.all_combatants()
	all.sort_custom(func(x, y): return x["pos"].y < y["pos"].y)
	for c in all:
		if hidden(c) and c["id"] != current_id:
			continue
		_draw_token(c, current_id, area_ids)
	_draw_hover_card(current_id)
	_draw_cell_hint()
	draw_rect(b, Color(UiTheme.WOOD_EDGE, 0.8), false, 2.0)
	# Escala do tabuleiro, no canto
	var ppm := px_per_m()
	var sp := b.position + Vector2(16, b.size.y - 18)
	draw_line(sp, sp + Vector2(ppm * 3.0, 0), Color(UiTheme.BONE, 0.8), 3.0)
	draw_line(sp + Vector2(0, -5), sp + Vector2(0, 5), Color(UiTheme.BONE, 0.8), 2.0)
	draw_line(sp + Vector2(ppm * 3.0, -5), sp + Vector2(ppm * 3.0, 5), Color(UiTheme.BONE, 0.8), 2.0)
	draw_string(UiTheme.sans_medium(), sp + Vector2(ppm * 3.0 + 8, 5), "3 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UiTheme.BONE, 0.8))
	if _t < _flash_until and _flash != "":
		var f := UiTheme.sans_bold()
		var w := f.get_string_size(_flash, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var fp := Vector2((size.x - w) / 2.0, size.y - 64)
		draw_rect(Rect2(fp - Vector2(16, 26), Vector2(w + 32, 38)), Color(UiTheme.INK, 0.95))
		draw_rect(Rect2(fp - Vector2(16, 26), Vector2(w + 32, 38)), UiTheme.HP, false, 2.0)
		draw_string(f, fp, _flash, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.BONE)
