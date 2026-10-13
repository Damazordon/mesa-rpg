class_name TerrainPainter
extends RefCounted
## Desenha o terreno do capítulo (TerrainMap) no tabuleiro, com o visual do bioma.
##
## O chão, as paredes, a água e o terreno difícil são assados uma vez numa imagem (rápido de
## desenhar a cada quadro). Colunas, árvores e obstáculos baixos são desenhados por cima em
## vetor, para ficarem nítidos em qualquer tamanho de janela. A névoa é uma textura de uma
## célula por pixel com filtro linear: a borda do que o grupo vê sai suave de graça.

const PX := 20  # pixels por metro na imagem assada

## Pisos com desenho regular (lajotas, tábuas, placas).
const PATTERN := {"masmorra": "tiles", "interior": "planks", "industrial": "plates", "esgoto": "tiles",
	"cidade": "cobble", "metropole": "plates"}


static func col(b: Dictionary, key: String) -> Color:
	return Color("#" + str(b.get(key, "777777")))


static func organic(biome_id: String) -> bool:
	return str(MapGen.biome(biome_id).get("gen", "")) in ["cave", "outdoor"]


# ---------------------------------------------------------------- imagem assada

static func bake(t: TerrainMap) -> ImageTexture:
	var b := MapGen.biome(t.biome)
	var iw := t.w * PX
	var ih := t.h * PX
	var floor_a := col(b, "floor")
	var floor_b := col(b, "floor2")
	var wall := col(b, "wall")
	var wall_top := col(b, "wall_top")
	var rough := col(b, "rough")
	var gap := col(b, "gap")
	var gap_kind := str(b.get("gap_kind", "abismo"))
	var pattern := str(PATTERN.get(t.biome, ""))
	var round_walls := organic(t.biome)
	var low := FastNoiseLite.new()
	low.seed = 11
	low.frequency = 0.012
	var hi := FastNoiseLite.new()
	hi.seed = 23
	hi.frequency = 0.09
	var low_d := low.get_image(iw, ih).get_data()
	var hi_d := hi.get_image(iw, ih).get_data()
	var low_fmt := low.get_image(1, 1).get_format()
	var stride := 1 if low_fmt == Image.FORMAT_L8 else (3 if low_fmt == Image.FORMAT_RGB8 else 4)
	# Vizinhança de cada célula, calculada uma vez.
	var solid := PackedByteArray()
	solid.resize(t.w * t.h)
	for y in t.h:
		for x in t.w:
			solid[y * t.w + x] = 1 if t.at(x, y) == TerrainMap.WALL else 0
	var data := PackedByteArray()
	data.resize(iw * ih * 3)
	var i := 0
	for py in ih:
		var cy := py / PX
		var ly := py - cy * PX
		for px in iw:
			var cx := px / PX
			var lx := px - cx * PX
			var code := t.at(cx, cy)
			var nl := float(low_d[(py * iw + px) * stride]) / 255.0
			var nh := float(hi_d[(py * iw + px) * stride]) / 255.0
			var grain := float(((px * 73856093) ^ (py * 19349663)) & 255) / 255.0 - 0.5
			var c: Color
			# Manchas de terreno difícil e de água têm quina arredondada (e paredes, em caverna e ar livre).
			if code == TerrainMap.ROUGH and _cut_corner(t, cx, cy, lx, ly, TerrainMap.ROUGH):
				code = TerrainMap.FLOOR
			elif code == TerrainMap.GAP and _cut_corner(t, cx, cy, lx, ly, TerrainMap.GAP):
				code = TerrainMap.FLOOR
			var is_wall := code == TerrainMap.WALL
			if is_wall and round_walls:
				is_wall = not _cut_corner(t, cx, cy, lx, ly, TerrainMap.WALL)
			if is_wall:
				c = wall.lerp(wall.lightened(0.12), nh * 0.6)
				# Borda de cima da parede, virada para o chão: luz batendo.
				if t.at(cx, cy + 1) != TerrainMap.WALL and ly >= PX - 5:
					c = wall_top.darkened(float(PX - 1 - ly) * 0.07)
				elif t.at(cx, cy - 1) != TerrainMap.WALL and ly <= 2:
					c = wall_top.darkened(0.25)
				elif t.at(cx - 1, cy) != TerrainMap.WALL and lx <= 2:
					c = wall_top.darkened(0.35)
				elif t.at(cx + 1, cy) != TerrainMap.WALL and lx >= PX - 3:
					c = wall_top.darkened(0.35)
				c = c.lightened(grain * 0.06) if grain > 0.0 else c.darkened(-grain * 0.06)
			else:
				c = floor_a.lerp(floor_b, nl)
				match pattern:
					"tiles":
						if lx == 0 or ly == 0:
							c = c.darkened(0.22)
						elif (cx + cy) % 2 == 0:
							c = c.lightened(0.03)
					"planks":
						var board := (py / 7)
						if py % 7 == 0 or (px + board * 13) % 37 == 0:
							c = c.darkened(0.25)
						else:
							c = c.lerp(c.lightened(0.08), float((board * 7919) % 5) / 5.0)
					"plates":
						if lx == 0 or ly == 0:
							c = c.darkened(0.3)
						elif (lx == 3 or lx == PX - 4) and (ly == 3 or ly == PX - 4):
							c = c.lightened(0.18)
					"cobble":
						var bx := (px + (py / 6 % 2) * 4) % 8
						if bx == 0 or py % 6 == 0:
							c = c.darkened(0.18)
				c = c.lightened(grain * 0.08) if grain > 0.0 else c.darkened(-grain * 0.08)
				if code == TerrainMap.ROUGH:
					if nh > 0.52:
						c = rough.lerp(rough.lightened(0.15), (nh - 0.52) * 2.0)
					elif (px * 7 + py * 3) % 11 == 0:
						c = rough.darkened(0.2)
					else:
						c = c.lerp(rough, 0.35)
				elif code == TerrainMap.GAP:
					c = _gap_color(t, gap, gap_kind, cx, cy, lx, ly, nh, px, py)
				# Sombra das paredes sobre o chão (de cima e da esquerda, como luz do alto).
				var shade := 0.0
				if t.at(cx, cy - 1) == TerrainMap.WALL and ly < 9:
					shade = maxf(shade, (1.0 - ly / 9.0) * 0.45)
				if t.at(cx - 1, cy) == TerrainMap.WALL and lx < 6:
					shade = maxf(shade, (1.0 - lx / 6.0) * 0.3)
				if t.at(cx + 1, cy) == TerrainMap.WALL and lx > PX - 4:
					shade = maxf(shade, (lx - (PX - 4)) / 4.0 * 0.18)
				if t.at(cx, cy + 1) == TerrainMap.WALL and ly > PX - 4:
					shade = maxf(shade, (ly - (PX - 4)) / 4.0 * 0.2)
				if shade > 0.0:
					c = c.darkened(shade)
			data[i] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			data[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			data[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
			i += 3
	var img := Image.create_from_data(iw, ih, false, Image.FORMAT_RGB8, data)
	return ImageTexture.create_from_image(img)


## Caverna e ar livre: arredonda a quina da parede que dá para o chão.
static func _cut_corner(t: TerrainMap, cx: int, cy: int, lx: int, ly: int, same: int) -> bool:
	var h := PX / 2
	var sx := -1 if lx < h else 1
	var sy := -1 if ly < h else 1
	if t.at(cx + sx, cy) == same or t.at(cx, cy + sy) == same:
		return false
	# Quina exposta: arredonda com raio de meia célula, centrado no meio da célula.
	var d := Vector2(lx + 0.5 - h, ly + 0.5 - h).length()
	return d > float(h)


static func _gap_color(t: TerrainMap, gap: Color, kind: String, cx: int, cy: int, lx: int, ly: int, nh: float, px: int, py: int) -> Color:
	var edge := 99
	if t.at(cx - 1, cy) != TerrainMap.GAP:
		edge = mini(edge, lx)
	if t.at(cx + 1, cy) != TerrainMap.GAP:
		edge = mini(edge, PX - 1 - lx)
	if t.at(cx, cy - 1) != TerrainMap.GAP:
		edge = mini(edge, ly)
	if t.at(cx, cy + 1) != TerrainMap.GAP:
		edge = mini(edge, PX - 1 - ly)
	match kind:
		"agua", "lodo":
			var c := gap.lerp(gap.lightened(0.18), nh)
			var wave := sin(px * 0.35 + py * 0.12 + nh * 7.0)
			if wave > 0.93:
				c = c.lightened(0.22 if kind == "agua" else 0.1)
			if edge <= 2:
				c = c.lightened(0.25 if kind == "agua" else 0.12)
			return c
	# Abismo: escurece para o fundo, com a beirada clara.
	if edge <= 1:
		return gap.lightened(0.3)
	return gap.darkened(clampf(float(edge) / 8.0, 0.0, 0.9)).lerp(gap, 0.2)


# ---------------------------------------------------------------- linhas de parede

## Segmentos (em metros) da borda entre parede e o resto. Usados para o contorno nítido.
static func wall_edges(t: TerrainMap) -> PackedVector2Array:
	var out := PackedVector2Array()
	for y in t.h:
		var run_n := -1
		var run_s := -1
		for x in t.w + 1:
			var wall := x < t.w and t.at(x, y) == TerrainMap.WALL
			var n_edge := wall and y > 0 and t.at(x, y - 1) != TerrainMap.WALL
			var s_edge := wall and y < t.h - 1 and t.at(x, y + 1) != TerrainMap.WALL
			if n_edge and run_n < 0:
				run_n = x
			elif not n_edge and run_n >= 0:
				out.append(Vector2(run_n, y))
				out.append(Vector2(x, y))
				run_n = -1
			if s_edge and run_s < 0:
				run_s = x
			elif not s_edge and run_s >= 0:
				out.append(Vector2(run_s, y + 1))
				out.append(Vector2(x, y + 1))
				run_s = -1
	for x in t.w:
		var run_w := -1
		var run_e := -1
		for y in t.h + 1:
			var wall := y < t.h and t.at(x, y) == TerrainMap.WALL
			var w_edge := wall and x > 0 and t.at(x - 1, y) != TerrainMap.WALL
			var e_edge := wall and x < t.w - 1 and t.at(x + 1, y) != TerrainMap.WALL
			if w_edge and run_w < 0:
				run_w = y
			elif not w_edge and run_w >= 0:
				out.append(Vector2(x, run_w))
				out.append(Vector2(x, y))
				run_w = -1
			if e_edge and run_e < 0:
				run_e = y
			elif not e_edge and run_e >= 0:
				out.append(Vector2(x + 1, run_e))
				out.append(Vector2(x + 1, y))
				run_e = -1
	return out


# ---------------------------------------------------------------- névoa

## Uma célula por pixel: nunca visto quase preto, já visto meio escuro, à vista limpo.
static func fog_image(t: TerrainMap, seen: PackedByteArray, vis: PackedByteArray) -> Image:
	var img := Image.create(t.w, t.h, false, Image.FORMAT_RGBA8)
	for y in t.h:
		for x in t.w:
			var i := y * t.w + x
			var a := 0.93
			if i < vis.size() and vis[i] != 0:
				a = 0.0
			elif i < seen.size() and seen[i] != 0:
				a = 0.5
			img.set_pixel(x, y, Color(0.02, 0.02, 0.03, a))
	return img


# ---------------------------------------------------------------- objetos em vetor

## Colunas, árvores e obstáculos baixos. ci desenha; to_px converte metros em pixels.
static func draw_props(ci: CanvasItem, t: TerrainMap, origin: Vector2, ppm: float, alpha := 1.0, time := 0.0) -> void:
	var b := MapGen.biome(t.biome)
	var pillar := str(b.get("pillar", "coluna"))
	var low := str(b.get("low", "caixote"))
	var neon: bool = b.get("neon", false)
	for y in t.h:
		for x in t.w:
			var code := t.at(x, y)
			if code != TerrainMap.PILLAR and code != TerrainMap.LOW:
				continue
			if x == 0 or y == 0 or x == t.w - 1 or y == t.h - 1:
				if code == TerrainMap.PILLAR and pillar == "arvore":
					_tree(ci, origin + Vector2(x + 0.5, y + 0.5) * ppm, ppm, x * 31 + y * 17, alpha, true)
				continue
			var c := origin + Vector2(x + 0.5, y + 0.5) * ppm
			var seed_v := x * 31 + y * 17
			if code == TerrainMap.PILLAR:
				_pillar(ci, pillar, c, ppm, seed_v, alpha, neon, time)
			else:
				_low(ci, low, t, x, y, c, ppm, seed_v, alpha)


static func _shadow(ci: CanvasItem, c: Vector2, r: float, alpha: float) -> void:
	ci.draw_circle(c + Vector2(r * 0.18, r * 0.25), r, Color(0, 0, 0, 0.35 * alpha))


static func _pillar(ci: CanvasItem, kind: String, c: Vector2, ppm: float, seed_v: int, alpha: float, neon: bool, time: float) -> void:
	match kind:
		"arvore":
			_tree(ci, c, ppm, seed_v, alpha, false)
		"poste", "poste_neon":
			var r := ppm * 0.16
			var glow := Color("#7ef0ff") if neon and seed_v % 2 == 0 else (Color("#ff4fd8") if neon else Color("#ffd27a"))
			for k in 6:
				ci.draw_circle(c, ppm * (1.4 - k * 0.2), Color(glow, 0.035 * alpha * (0.85 + 0.15 * sin(time * 2.0 + seed_v))))
			_shadow(ci, c, r, alpha)
			ci.draw_circle(c, r, Color(Color("#2a2a2a"), alpha))
			ci.draw_circle(c, r * 0.55, Color(glow, alpha))
		"estalagmite", "rocha_alta":
			var r2 := ppm * 0.45
			_shadow(ci, c, r2, alpha)
			var pts := _blob_pts(c, r2, seed_v, 7)
			ci.draw_colored_polygon(pts, Color(Color("#4b4036") if kind == "estalagmite" else Color("#7a6248"), alpha))
			ci.draw_circle(c - Vector2(r2, r2) * 0.2, r2 * 0.35, Color(1, 1, 1, 0.12 * alpha))
			_outline(ci, pts, Color(0, 0, 0, 0.5 * alpha))
		"escora":
			var s := ppm * 0.28
			_shadow(ci, c, s, alpha)
			ci.draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), Color(Color("#6b4a2c"), alpha))
			ci.draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), Color(0, 0, 0, 0.6 * alpha), false, 2.0)
			ci.draw_line(c - Vector2(s, s), c + Vector2(s, s), Color(0, 0, 0, 0.4 * alpha), 2.0)
		_:  # coluna, pilar
			var r3 := ppm * 0.42
			_shadow(ci, c, r3, alpha)
			ci.draw_circle(c, r3, Color(Color("#6d6a63") if kind == "coluna" else Color("#5d666b"), alpha))
			ci.draw_circle(c, r3 * 0.72, Color(Color("#85817a") if kind == "coluna" else Color("#727c82"), alpha))
			ci.draw_arc(c, r3, 0.0, TAU, 24, Color(0, 0, 0, 0.55 * alpha), 2.0, true)
			ci.draw_arc(c, r3 * 0.72, PI * 1.1, PI * 1.7, 8, Color(1, 1, 1, 0.25 * alpha), 2.0, true)


static func _tree(ci: CanvasItem, c: Vector2, ppm: float, seed_v: int, alpha: float, border: bool) -> void:
	var r := ppm * (0.62 + float(seed_v % 5) * 0.05) * (1.15 if border else 1.0)
	_shadow(ci, c, r, alpha)
	var base := Color("#2f4a24").lerp(Color("#3d5a2a"), float(seed_v % 7) / 7.0)
	ci.draw_colored_polygon(_blob_pts(c, r, seed_v, 9), Color(base.darkened(0.25), alpha))
	ci.draw_colored_polygon(_blob_pts(c - Vector2(r, r) * 0.1, r * 0.78, seed_v + 3, 9), Color(base, alpha))
	ci.draw_circle(c - Vector2(r, r) * 0.28, r * 0.3, Color(base.lightened(0.18), alpha))


static func _low(ci: CanvasItem, kind: String, t: TerrainMap, x: int, y: int, c: Vector2, ppm: float, seed_v: int, alpha: float) -> void:
	match kind:
		"rocha", "pedra":
			var r := ppm * 0.4
			_shadow(ci, c, r, alpha)
			var pts := _blob_pts(c, r, seed_v, 7)
			ci.draw_colored_polygon(pts, Color(Color("#5c5246") if kind == "rocha" else Color("#8a8170"), alpha))
			ci.draw_circle(c - Vector2(r, r) * 0.25, r * 0.3, Color(1, 1, 1, 0.13 * alpha))
			_outline(ci, pts, Color(0, 0, 0, 0.5 * alpha))
		"tronco":
			var horiz := seed_v % 2 == 0
			var rs := Vector2(ppm * 0.9, ppm * 0.38) if horiz else Vector2(ppm * 0.38, ppm * 0.9)
			var rect := Rect2(c - rs / 2.0, rs)
			ci.draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.3 * alpha))
			ci.draw_rect(rect, Color(Color("#5b4027"), alpha))
			ci.draw_rect(rect, Color(0, 0, 0, 0.5 * alpha), false, 2.0)
			ci.draw_circle(rect.position + (Vector2(0, rs.y / 2.0) if horiz else Vector2(rs.x / 2.0, 0)), minf(rs.x, rs.y) * 0.5, Color(Color("#8a6a45"), alpha))
		"barril":
			var r2 := ppm * 0.36
			_shadow(ci, c, r2, alpha)
			ci.draw_circle(c, r2, Color(Color("#5a4630"), alpha))
			ci.draw_arc(c, r2 * 0.7, 0.0, TAU, 20, Color(Color("#2b2117"), alpha), 2.0, true)
			ci.draw_arc(c, r2, 0.0, TAU, 20, Color(0, 0, 0, 0.6 * alpha), 2.0, true)
		"carro", "carroca":
			# Dois "o" lado a lado viram um veículo comprido.
			var pair := t.at(x + 1, y) == TerrainMap.LOW
			var prev := t.at(x - 1, y) == TerrainMap.LOW
			if prev and not pair:
				return
			var size := Vector2(ppm * (1.85 if pair else 0.9), ppm * 0.8)
			var center := c + Vector2(ppm * 0.5 if pair else 0.0, 0.0)
			var rect2 := Rect2(center - size / 2.0, size)
			var body := Color("#3a4a6a") if kind == "carro" else Color("#6b4a2c")
			if kind == "carro" and seed_v % 3 == 0:
				body = Color("#6a2a3a")
			ci.draw_rect(Rect2(rect2.position + Vector2(4, 5), rect2.size), Color(0, 0, 0, 0.35 * alpha))
			ci.draw_rect(rect2, Color(body, alpha))
			ci.draw_rect(rect2.grow(-size.y * 0.18), Color(body.lightened(0.15), alpha))
			ci.draw_rect(rect2, Color(0, 0, 0, 0.6 * alpha), false, 2.0)
		"movel", "sarcofago":
			var s := Vector2(ppm * 0.86, ppm * 0.62)
			var rect3 := Rect2(c - s / 2.0, s)
			ci.draw_rect(Rect2(rect3.position + Vector2(3, 4), rect3.size), Color(0, 0, 0, 0.3 * alpha))
			ci.draw_rect(rect3, Color(Color("#6b4a2c") if kind == "movel" else Color("#5f5b55"), alpha))
			ci.draw_rect(rect3.grow(-4), Color(Color("#7d5a37") if kind == "movel" else Color("#76726a"), alpha))
			ci.draw_rect(rect3, Color(0, 0, 0, 0.55 * alpha), false, 2.0)
		"cerca":
			var horiz2 := t.at(x - 1, y) == TerrainMap.LOW or t.at(x + 1, y) == TerrainMap.LOW or t.at(x, y - 1) != TerrainMap.LOW
			var d := Vector2(ppm * 0.48, 0) if horiz2 else Vector2(0, ppm * 0.48)
			ci.draw_line(c - d + Vector2(3, 4), c + d + Vector2(3, 4), Color(0, 0, 0, 0.3 * alpha), ppm * 0.22)
			ci.draw_line(c - d, c + d, Color(Color("#8a6a45"), alpha), ppm * 0.2)
			ci.draw_line(c - d, c + d, Color(Color("#5b4027"), alpha), ppm * 0.07)
			for k in [-0.85, 0.0, 0.85]:
				ci.draw_circle(c + d * k, ppm * 0.14, Color(Color("#4a3320"), alpha))
		_:  # caixote
			var s2 := ppm * 0.82
			var rect4 := Rect2(c - Vector2(s2, s2) / 2.0, Vector2(s2, s2))
			ci.draw_rect(Rect2(rect4.position + Vector2(3, 4), rect4.size), Color(0, 0, 0, 0.35 * alpha))
			ci.draw_rect(rect4, Color(Color("#6b4d30"), alpha))
			ci.draw_rect(rect4.grow(-s2 * 0.12), Color(Color("#7d5c3a"), alpha), false, 2.0)
			ci.draw_line(rect4.position, rect4.end, Color(Color("#3b2a1a"), alpha), 2.0)
			ci.draw_rect(rect4, Color(0, 0, 0, 0.6 * alpha), false, 2.0)


static func _blob_pts(c: Vector2, r: float, seed_v: int, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var k := 0.82 + float(((seed_v + i * 37) * 2654435761) % 1000) / 1000.0 * 0.3
		var ang := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r * k)
	return pts


static func _outline(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	var o := pts.duplicate()
	o.append(pts[0])
	ci.draw_polyline(o, color, 2.0, true)


static func cell_text(code: int, b: Dictionary) -> String:
	match code:
		TerrainMap.ROUGH:
			return "Terreno difícil: andar custa o dobro"
		TerrainMap.LOW:
			return "Obstáculo baixo: não passa, mas dá meia cobertura"
		TerrainMap.GAP:
			match str(b.get("gap_kind", "")):
				"agua":
					return "Água funda: não dá para atravessar"
				"lodo":
					return "Lodo fundo: não dá para atravessar"
			return "Abismo: não dá para atravessar"
		TerrainMap.WALL:
			return "Parede: bloqueia passagem e visão"
		TerrainMap.PILLAR:
			return "Árvore: bloqueia passagem e visão" if str(b.get("pillar", "")) == "arvore" else "Coluna: bloqueia passagem e visão"
	return ""
