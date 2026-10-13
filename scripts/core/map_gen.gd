class_name MapGen
extends RefCounted
## Mapas por tema. A IA NÃO desenha mapa: modelo pequeno erra coordenada, sobrepõe obstáculo e
## tranca a entrada do grupo. Ela devolve só um briefing de terreno — um bioma e algumas feições,
## das listas fechadas abaixo, sem coordenada nenhuma — e o motor gera o traçado a partir de uma
## semente da história, confere e posiciona tudo:
##   - o grupo começa numa área aberta, à esquerda;
##   - a saída fica do outro lado, longe a pé;
##   - todo ponto de interesse, bando e saída é alcançável andando a partir do início;
##   - os bandos ficam longe do início e, sempre que dá, fora da linha de visão dele;
##   - os pontos de interesse se espalham e não caem colados num bando.
## A mesma semente dá o mesmo mapa (é o que deixa as aventuras antigas ganharem mapa ao carregar).

const W := 32
const H := 18
const START_M := Vector2(4.5, 10.5)
const MIN_SPACING := 1.5
const MIN_REACH_CELLS := 170

## Biomas: gerador, nome, alcance da visão (m) e o visual. "gap" diz o que é o vão ("_"), "pillar"
## o que é a coluna ("T") e "low" o que é o obstáculo baixo ("o").
const BIOMES := {
	"caverna": {"name": "Caverna", "gen": "cave", "vision_m": 10.0, "floor": "3a3128", "floor2": "2c251f", "wall": "17120e", "wall_top": "4b4036", "rough": "54473a", "gap": "0b1418", "gap_kind": "agua", "pillar": "estalagmite", "low": "rocha", "feats": ["lama"]},
	"mina": {"name": "Mina", "gen": "cave", "vision_m": 10.0, "floor": "3b3027", "floor2": "2e251e", "wall": "16110d", "wall_top": "5a4a3a", "rough": "5d4c3b", "gap": "050505", "gap_kind": "abismo", "pillar": "escora", "low": "caixote", "feats": ["caixotes", "entulho"]},
	"masmorra": {"name": "Masmorra", "gen": "rooms", "corridor": 2, "vision_m": 10.0, "floor": "3c3a36", "floor2": "302e2b", "wall": "1a1917", "wall_top": "5b5852", "rough": "57534b", "gap": "050506", "gap_kind": "abismo", "pillar": "coluna", "low": "sarcofago", "feats": ["pilares", "entulho"]},
	"interior": {"name": "Interior", "gen": "rooms", "corridor": 2, "vision_m": 12.0, "floor": "5a4430", "floor2": "4d3a29", "wall": "2a1d14", "wall_top": "7a6048", "rough": "6b5540", "gap": "0c0a08", "gap_kind": "abismo", "pillar": "coluna", "low": "movel", "feats": ["caixotes"]},
	"industrial": {"name": "Instalação", "gen": "rooms", "corridor": 3, "vision_m": 12.0, "floor": "3d4245", "floor2": "33383b", "wall": "1b1e20", "wall_top": "5d666b", "rough": "4a4436", "gap": "07090a", "gap_kind": "abismo", "pillar": "pilar", "low": "caixote", "feats": ["caixotes", "barricadas"]},
	"esgoto": {"name": "Esgoto", "gen": "rooms", "corridor": 3, "vision_m": 9.0, "floor": "3a3d34", "floor2": "30332b", "wall": "171a15", "wall_top": "4f5647", "rough": "4b5233", "gap": "1d2a1c", "gap_kind": "lodo", "pillar": "pilar", "low": "barril", "feats": ["lama", "rio"]},
	"floresta": {"name": "Floresta", "gen": "outdoor", "vision_m": 13.0, "floor": "3f5130", "floor2": "354628", "wall": "263220", "wall_top": "4a5e36", "rough": "566b35", "gap": "1f3a48", "gap_kind": "agua", "pillar": "arvore", "low": "tronco", "feats": ["arvores", "mato"]},
	"pantano": {"name": "Pântano", "gen": "outdoor", "vision_m": 11.0, "floor": "45482f", "floor2": "3a3d27", "wall": "262a1b", "wall_top": "51573a", "rough": "5c5a34", "gap": "1f3029", "gap_kind": "lodo", "pillar": "arvore", "low": "tronco", "feats": ["lama", "lago"]},
	"ruinas": {"name": "Ruínas", "gen": "outdoor", "vision_m": 14.0, "floor": "57513f", "floor2": "4b4636", "wall": "2c2924", "wall_top": "7a725f", "rough": "6e6650", "gap": "0b0b0a", "gap_kind": "abismo", "pillar": "coluna", "low": "pedra", "feats": ["ruinas", "pilares", "entulho"]},
	"campo": {"name": "Campo aberto", "gen": "outdoor", "vision_m": 16.0, "floor": "56663a", "floor2": "4b5a32", "wall": "333a28", "wall_top": "6b7550", "rough": "6f7a40", "gap": "2a4a5a", "gap_kind": "agua", "pillar": "arvore", "low": "cerca", "feats": ["mato"]},
	"deserto": {"name": "Deserto", "gen": "outdoor", "vision_m": 16.0, "floor": "a08a5c", "floor2": "93804f", "wall": "5a4630", "wall_top": "b59a6a", "rough": "b89c62", "gap": "1a120b", "gap_kind": "abismo", "pillar": "rocha_alta", "low": "pedra", "feats": ["areia"]},
	"cidade": {"name": "Cidade", "gen": "street", "vision_m": 14.0, "floor": "4b4842", "floor2": "403e39", "wall": "22201d", "wall_top": "6c655b", "rough": "5c574d", "gap": "0a0a0a", "gap_kind": "abismo", "pillar": "poste", "low": "carroca", "feats": ["barricadas"]},
	"metropole": {"name": "Metrópole", "gen": "street", "vision_m": 14.0, "floor": "2a2d36", "floor2": "23252d", "wall": "121318", "wall_top": "3d4250", "rough": "3a3346", "gap": "06060a", "gap_kind": "abismo", "pillar": "poste_neon", "low": "carro", "feats": ["barricadas", "entulho"], "neon": true},
}

## Feições que a IA pode pedir. Qualquer outra palavra é ignorada.
const FEATURES := {
	"rio": "um rio corta o mapa, com vau ou ponte",
	"ponte": "uma ponte sobre o vão",
	"lago": "um lago ou poço de água funda",
	"abismo": "uma fenda funda com passagem estreita",
	"pilares": "colunas ou pilares que dão cobertura",
	"caixotes": "caixotes, barris ou móveis espalhados",
	"barricadas": "barricadas e muretas",
	"entulho": "entulho e escombros",
	"lama": "lama ou poças que atrasam",
	"mato": "mato alto ou arbustos",
	"areia": "areia fofa",
	"arvores": "árvores e troncos",
	"ruinas": "paredes caídas e ruínas",
}

## Bioma padrão por tema, quando nem a IA nem o texto dizem nada.
const THEME_BIOMES := {
	"fantasia": ["masmorra", "floresta", "caverna", "ruinas", "campo"],
	"cyberpunk": ["metropole", "industrial", "esgoto", "interior"],
	"realista": ["cidade", "campo", "interior", "floresta", "industrial"],
	"mistico": ["ruinas", "floresta", "caverna", "pantano", "masmorra"],
}

## Palavras do texto da cena que puxam um bioma (português, sem acento).
const KEYWORDS := [
	["esgoto", ["esgoto", "cisterna", "galeria pluvial", "bueiro"]],
	["mina", ["mina", "minerio", "mineir", "garimpo"]],
	["caverna", ["caverna", "gruta", "toca", "subterran", "covil"]],
	["masmorra", ["masmorra", "cripta", "tumba", "catacumba", "calabouco", "templo", "santuario", "mausoleu", "porao"]],
	["industrial", ["fabrica", "armazem", "galpao", "doca", "laboratorio", "usina", "refinaria", "deposito", "hangar"]],
	["interior", ["taverna", "estalagem", "mansao", "castelo", "palacio", "salao", "biblioteca", "igreja", "casarao", "fortaleza"]],
	["pantano", ["pantano", "brejo", "charco", "mangue", "lamacal"]],
	["floresta", ["floresta", "bosque", "mata", "selva"]],
	["deserto", ["deserto", "duna", "areal"]],
	["ruinas", ["ruina", "escombro", "abandonad"]],
	["metropole", ["neon", "megacorp", "arranha", "distrito"]],
	["cidade", ["cidade", "rua", "beco", "mercado", "praca", "bairro", "porto"]],
	["campo", ["estrada", "campo", "colina", "planicie", "fazenda", "aldeia", "acampamento", "trilha", "vila"]],
]


# ---------------------------------------------------------------- briefing

static func biome(id: String) -> Dictionary:
	return BIOMES.get(id, BIOMES["masmorra"])


## Lê o briefing da IA ({"bioma": ..., "feicoes": [...]}), recusando o que não está nas listas.
static func read_brief(raw: Variant) -> Dictionary:
	var out := {"biome": "", "features": []}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var b := _plain(str(raw.get("bioma", raw.get("biome", ""))))
	if BIOMES.has(b):
		out["biome"] = b
	var feats: Variant = raw.get("feicoes", raw.get("features", []))
	if typeof(feats) == TYPE_ARRAY:
		for f in feats:
			var fid := _plain(str(f))
			if FEATURES.has(fid) and not fid in out["features"] and out["features"].size() < 3:
				out["features"].append(fid)
	return out


## Escolhe o bioma: o da IA; senão o que o texto da cena sugere; senão um do tema.
static func pick_biome(brief_biome: String, theme_id: String, scene_text: String, story: String, rng: RandomNumberGenerator) -> String:
	if BIOMES.has(brief_biome):
		return brief_biome
	for txt in [scene_text, story]:
		var plain := _plain(txt)
		for kw in KEYWORDS:
			for word in kw[1]:
				if plain.contains(word):
					return kw[0]
	var opts: Array = THEME_BIOMES.get(theme_id, THEME_BIOMES["fantasia"])
	return str(opts[rng.randi() % opts.size()])


static func _plain(s: String) -> String:
	var t := s.to_lower().strip_edges()
	var from := "áàâãäéèêëíìîïóòôõöúùûüç"
	var to := "aaaaaeeeeiiiiooooouuuuc"
	for i in from.length():
		t = t.replace(from[i], to[i])
	return t


# ---------------------------------------------------------------- geração

## Gera o terreno. Tenta algumas sementes até sair um mapa com área aberta suficiente.
static func generate(biome_id: String, features: Array, seed_v: int) -> TerrainMap:
	var b := biome(biome_id)
	var best: TerrainMap = null
	var best_n := -1
	for attempt in 8:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v + attempt * 7919
		var t := TerrainMap.blank(W, H)
		t.biome = biome_id
		match str(b["gen"]):
			"cave":
				_gen_cave(t, rng, biome_id)
			"rooms":
				_gen_rooms(t, rng, biome_id, int(b.get("corridor", 2)))
			"street":
				_gen_street(t, rng, biome_id)
			_:
				_gen_outdoor(t, rng, biome_id)
		var feats: Array = features.duplicate()
		for f in b.get("feats", []):
			if feats.size() < 4 and not f in feats:
				feats.append(f)
		for f2 in feats:
			_feature(t, rng, str(f2), feats)
		_border(t, WALL if str(b["gen"]) != "outdoor" else (TerrainMap.PILLAR if str(b["pillar"]) == "arvore" else TerrainMap.WALL))
		_open_start(t, rng)
		_connect_all(t, rng)
		var n := _reach_count(t)
		if n >= MIN_REACH_CELLS:
			return t
		if n > best_n:
			best_n = n
			best = t
	return best


const WALL := TerrainMap.WALL
const FLOOR := TerrainMap.FLOOR


static func _border(t: TerrainMap, code: int) -> void:
	for x in t.w:
		t.set_at(x, 0, code)
		t.set_at(x, t.h - 1, code)
	for y in t.h:
		t.set_at(0, y, code)
		t.set_at(t.w - 1, y, code)


static func _noise(rng: RandomNumberGenerator, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


static func _interior(t: TerrainMap, x: int, y: int) -> bool:
	return x >= 1 and y >= 1 and x <= t.w - 2 and y <= t.h - 2


static func _walls_around(t: TerrainMap, x: int, y: int) -> int:
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if t.at(x + dx, y + dy) == WALL:
				n += 1
	return n


static func _open_around(t: TerrainMap, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if t.at(x + dx, y + dy) != FLOOR:
				return false
	return true


## Caverna: autômato celular (rocha onde há rocha em volta) e decoração.
static func _gen_cave(t: TerrainMap, rng: RandomNumberGenerator, biome_id: String) -> void:
	t.cells.fill(WALL)
	for y in range(1, t.h - 1):
		for x in range(1, t.w - 1):
			t.set_at(x, y, WALL if rng.randf() < 0.45 else FLOOR)
	for it in 5:
		var nxt := t.cells.duplicate()
		for y in range(1, t.h - 1):
			for x in range(1, t.w - 1):
				var n := _walls_around(t, x, y)
				if n >= 5:
					nxt[y * t.w + x] = WALL
				elif n <= 3:
					nxt[y * t.w + x] = FLOOR
		t.cells = nxt
	# Estalagmites (ou escoras) soltas no meio dos salões
	for y in range(2, t.h - 2):
		for x in range(2, t.w - 2):
			if _open_around(t, x, y) and rng.randf() < 0.035:
				t.set_at(x, y, TerrainMap.PILLAR)
	# Pedras soltas junto das paredes
	for y in range(1, t.h - 1):
		for x in range(1, t.w - 1):
			if t.at(x, y) == FLOOR and _walls_around(t, x, y) >= 2 and rng.randf() < 0.06:
				t.set_at(x, y, TerrainMap.LOW)


## Salas e corredores: masmorra, interior, instalação, esgoto. Laços extras deixam rotas
## alternativas, que é o que permite contornar um bando.
static func _gen_rooms(t: TerrainMap, rng: RandomNumberGenerator, biome_id: String, cw: int) -> void:
	t.cells.fill(WALL)
	var rooms: Array = []
	var sh := rng.randi_range(5, 7)
	rooms.append(Rect2i(1, clampi(11 - sh / 2, 1, t.h - 1 - sh), rng.randi_range(6, 8), sh))
	var eh := rng.randi_range(4, 7)
	var ew := rng.randi_range(4, 7)
	rooms.append(Rect2i(t.w - 1 - ew, rng.randi_range(1, t.h - 1 - eh), ew, eh))
	for attempt in 80:
		if rooms.size() >= 9:
			break
		var rw := rng.randi_range(4, 9)
		var rh := rng.randi_range(4, 7)
		var r := Rect2i(rng.randi_range(1, t.w - 1 - rw), rng.randi_range(1, t.h - 1 - rh), rw, rh)
		var ok := true
		for o in rooms:
			if (o as Rect2i).grow(1).intersects(r):
				ok = false
				break
		if ok:
			rooms.append(r)
	for r2 in rooms:
		_fill_rect(t, r2, FLOOR)
	rooms.sort_custom(func(a, b): return a.get_center().x < b.get_center().x)
	var linked: Array = [rooms[0]]
	var edges := {}
	for i in range(1, rooms.size()):
		var best: Rect2i = linked[0]
		var best_d := INF
		for o2 in linked:
			var d := Vector2(o2.get_center()).distance_to(Vector2(rooms[i].get_center()))
			if d < best_d:
				best_d = d
				best = o2
		_corridor(t, rooms[i].get_center(), best.get_center(), cw, rng)
		edges["%s|%s" % [rooms[i], best]] = true
		linked.append(rooms[i])
	# Laços: duas ligações a mais entre salas que ainda não se ligavam direto
	var loops := 0
	for attempt2 in 20:
		if loops >= 2 or rooms.size() < 4:
			break
		var a: Rect2i = rooms[rng.randi() % rooms.size()]
		var b2: Rect2i = rooms[rng.randi() % rooms.size()]
		if a == b2 or edges.has("%s|%s" % [a, b2]) or edges.has("%s|%s" % [b2, a]):
			continue
		if Vector2(a.get_center()).distance_to(Vector2(b2.get_center())) > 16.0:
			continue
		_corridor(t, a.get_center(), b2.get_center(), cw, rng)
		edges["%s|%s" % [a, b2]] = true
		loops += 1
	# Decoração por sala
	for r3 in rooms:
		var rr: Rect2i = r3
		if rr.size.x >= 7 and rr.size.y >= 5 and biome_id in ["masmorra", "interior", "industrial"] and rng.randf() < 0.7:
			for px in [rr.position.x + 1, rr.end.x - 2]:
				for py in [rr.position.y + 1, rr.end.y - 2]:
					t.set_at(px, py, TerrainMap.PILLAR)
		var n_low := rng.randi_range(0, 2) if biome_id != "industrial" else rng.randi_range(1, 3)
		for k in n_low:
			var lx := rng.randi_range(rr.position.x + 1, rr.end.x - 2)
			var ly := rng.randi_range(rr.position.y + 1, rr.end.y - 2)
			if t.at(lx, ly) == FLOOR:
				t.set_at(lx, ly, TerrainMap.LOW)
				if rng.randf() < 0.5 and t.at(lx + 1, ly) == FLOOR:
					t.set_at(lx + 1, ly, TerrainMap.LOW)


static func _fill_rect(t: TerrainMap, r: Rect2i, code: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _interior(t, x, y):
				t.set_at(x, y, code)


## Corredor em L de largura cw entre dois pontos.
static func _corridor(t: TerrainMap, a: Vector2i, b: Vector2i, cw: int, rng: RandomNumberGenerator, code := FLOOR) -> void:
	var elbow := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_carve_line(t, a, elbow, cw, code)
	_carve_line(t, elbow, b, cw, code)


static func _carve_line(t: TerrainMap, a: Vector2i, b: Vector2i, cw: int, code := FLOOR) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	var off := cw / 2
	for i in steps + 1:
		var f := float(i) / float(maxi(1, steps))
		var p := Vector2i(roundi(lerpf(a.x, b.x, f)), roundi(lerpf(a.y, b.y, f)))
		for dy in cw:
			for dx in cw:
				var x := p.x + dx - off
				var y := p.y + dy - off
				if _interior(t, x, y) and (code != FLOOR or not TerrainMap.passable_code(t.at(x, y))):
					t.set_at(x, y, code)


## Ar livre: floresta, pântano, ruínas, campo, deserto.
static func _gen_outdoor(t: TerrainMap, rng: RandomNumberGenerator, biome_id: String) -> void:
	t.cells.fill(FLOOR)
	var n1 := _noise(rng, 0.13)
	var n2 := _noise(rng, 0.22)
	for y in range(1, t.h - 1):
		for x in range(1, t.w - 1):
			var a := n1.get_noise_2d(x, y)
			var b := n2.get_noise_2d(x, y)
			match biome_id:
				"floresta":
					if a > 0.18 and rng.randf() < 0.5:
						t.set_at(x, y, TerrainMap.PILLAR)
					elif b > 0.3:
						t.set_at(x, y, TerrainMap.ROUGH)
				"pantano":
					if a > 0.32:
						t.set_at(x, y, TerrainMap.GAP)
					elif a > 0.02 or b > 0.35:
						t.set_at(x, y, TerrainMap.ROUGH)
					elif rng.randf() < 0.04:
						t.set_at(x, y, TerrainMap.PILLAR)
				"campo":
					if rng.randf() < 0.025:
						t.set_at(x, y, TerrainMap.PILLAR)
					elif rng.randf() < 0.02:
						t.set_at(x, y, TerrainMap.LOW)
					elif b > 0.32:
						t.set_at(x, y, TerrainMap.ROUGH)
				"deserto":
					if a > 0.45:
						t.set_at(x, y, WALL)
					elif b > 0.15:
						t.set_at(x, y, TerrainMap.ROUGH)
					elif rng.randf() < 0.02:
						t.set_at(x, y, TerrainMap.LOW)
				_:  # ruínas
					if b > 0.38:
						t.set_at(x, y, TerrainMap.ROUGH)
					elif rng.randf() < 0.03:
						t.set_at(x, y, TerrainMap.LOW)
	# Trilha do início até o lado de lá: é por onde a história anda.
	if biome_id in ["floresta", "pantano", "campo"]:
		var p := Vector2i(int(START_M.x), int(START_M.y))
		var goal := Vector2i(t.w - 3, rng.randi_range(3, t.h - 4))
		var guard := 200
		while p.x < goal.x and guard > 0:
			guard -= 1
			for dy in 2:
				if _interior(t, p.x, p.y + dy):
					t.set_at(p.x, p.y + dy, FLOOR)
			if rng.randf() < 0.65:
				p.x += 1
			else:
				p.y = clampi(p.y + (1 if goal.y > p.y else -1) * (1 if rng.randf() < 0.7 else -1), 2, t.h - 4)


## Cidade: quarteirões e ruas. Algumas quadras viram praça.
static func _gen_street(t: TerrainMap, rng: RandomNumberGenerator, biome_id: String) -> void:
	t.cells.fill(FLOOR)
	var xs: Array = []
	var x := 1 + rng.randi_range(2, 3)
	while x < t.w - 3:
		var bw := rng.randi_range(4, 7)
		xs.append([x, mini(x + bw, t.w - 2)])
		x += bw + rng.randi_range(2, 3)
	var ys: Array = []
	var y := 1 + rng.randi_range(1, 2)
	while y < t.h - 3:
		var bh := rng.randi_range(3, 5)
		ys.append([y, mini(y + bh, t.h - 2)])
		y += bh + rng.randi_range(2, 3)
	for cx in xs:
		for cy in ys:
			var r := Rect2i(cx[0], cy[0], cx[1] - cx[0], cy[1] - cy[0])
			var roll := rng.randf()
			if roll < 0.72:
				_fill_rect(t, r, WALL)
			elif roll < 0.88:
				# Praça: postes ou árvores nos cantos e um banco no meio
				for px in [r.position.x, r.end.x - 1]:
					for py in [r.position.y, r.end.y - 1]:
						t.set_at(px, py, TerrainMap.PILLAR)
				t.set_at(r.get_center().x, r.get_center().y, TerrainMap.LOW)
			else:
				# Prédio com pátio: só a casca, com uma porta
				for px2 in range(r.position.x, r.end.x):
					t.set_at(px2, r.position.y, WALL)
					t.set_at(px2, r.end.y - 1, WALL)
				for py2 in range(r.position.y, r.end.y):
					t.set_at(r.position.x, py2, WALL)
					t.set_at(r.end.x - 1, py2, WALL)
				var door := rng.randi_range(r.position.x + 1, maxi(r.position.x + 1, r.end.x - 3))
				t.set_at(door, r.end.y - 1, FLOOR)
				t.set_at(door + 1, r.end.y - 1, FLOOR)
	# Veículos e entulho nas ruas
	var props := rng.randi_range(6, 10)
	for i in props * 4:
		if props <= 0:
			break
		var px3 := rng.randi_range(2, t.w - 4)
		var py3 := rng.randi_range(2, t.h - 3)
		if t.at(px3, py3) == FLOOR and t.at(px3 + 1, py3) == FLOOR and _walls_around(t, px3, py3) <= 3:
			t.set_at(px3, py3, TerrainMap.LOW)
			t.set_at(px3 + 1, py3, TerrainMap.LOW)
			props -= 1


# ---------------------------------------------------------------- feições

static func _feature(t: TerrainMap, rng: RandomNumberGenerator, f: String, all_feats: Array) -> void:
	match f:
		"rio":
			_river(t, rng, TerrainMap.GAP, rng.randi_range(2, 3), "ponte" in all_feats)
		"abismo":
			_river(t, rng, TerrainMap.GAP, 2, true)
		"lago":
			var c := Vector2i(rng.randi_range(12, t.w - 8), rng.randi_range(4, t.h - 5))
			_blob(t, rng, c, rng.randf_range(1.8, 3.0), TerrainMap.GAP, false)
		"pilares":
			var r := _open_rect(t, rng, 8, 6)
			if r.size.x > 0:
				for y in range(r.position.y + 1, r.end.y, 3):
					for x in range(r.position.x + 1, r.end.x, 3):
						if t.at(x, y) == FLOOR:
							t.set_at(x, y, TerrainMap.PILLAR)
		"caixotes":
			for i in rng.randi_range(4, 7):
				var p := _rand_floor(t, rng)
				if p.x < 0:
					break
				t.set_at(p.x, p.y, TerrainMap.LOW)
				if rng.randf() < 0.6 and t.at(p.x, p.y + 1) == FLOOR:
					t.set_at(p.x, p.y + 1, TerrainMap.LOW)
		"barricadas":
			for i2 in rng.randi_range(3, 4):
				var p2 := _rand_floor(t, rng)
				if p2.x < 0:
					break
				var horiz := rng.randf() < 0.5
				var length := rng.randi_range(3, 5)
				for k in length:
					var q := p2 + (Vector2i(k, 0) if horiz else Vector2i(0, k))
					if t.at(q.x, q.y) == FLOOR and _interior(t, q.x, q.y):
						t.set_at(q.x, q.y, TerrainMap.LOW)
		"entulho":
			var n := _noise(rng, 0.25)
			for y2 in range(1, t.h - 1):
				for x2 in range(1, t.w - 1):
					if t.at(x2, y2) == FLOOR:
						if n.get_noise_2d(x2, y2) > 0.42:
							t.set_at(x2, y2, TerrainMap.ROUGH)
						elif rng.randf() < 0.015:
							t.set_at(x2, y2, TerrainMap.LOW)
		"lama", "mato", "areia":
			var n2 := _noise(rng, 0.18)
			for y3 in range(1, t.h - 1):
				for x3 in range(1, t.w - 1):
					if t.at(x3, y3) == FLOOR and n2.get_noise_2d(x3, y3) > 0.3:
						t.set_at(x3, y3, TerrainMap.ROUGH)
		"arvores":
			for i3 in rng.randi_range(6, 10):
				var p3 := _rand_floor(t, rng)
				if p3.x < 0:
					break
				_blob(t, rng, p3, rng.randf_range(0.6, 1.6), TerrainMap.PILLAR, true)
		"ruinas":
			for i4 in rng.randi_range(3, 4):
				var rw := rng.randi_range(4, 7)
				var rh := rng.randi_range(3, 5)
				var r2 := Rect2i(rng.randi_range(8, t.w - 2 - rw), rng.randi_range(1, t.h - 1 - rh), rw, rh)
				for x4 in range(r2.position.x, r2.end.x):
					for y4 in [r2.position.y, r2.end.y - 1]:
						if rng.randf() < 0.7:
							t.set_at(x4, y4, WALL)
				for y5 in range(r2.position.y, r2.end.y):
					for x5 in [r2.position.x, r2.end.x - 1]:
						if rng.randf() < 0.7:
							t.set_at(x5, y5, WALL)
				t.set_at(r2.get_center().x, r2.end.y - 1, FLOOR)
				t.set_at(r2.get_center().x + 1, r2.end.y - 1, FLOOR)


## Faixa vertical de vão (rio, fenda) que serpenteia; cruza o mapa inteiro. Com ponte, abre
## uma ou duas passagens secas; sem ponte, os vaus são terreno difícil.
static func _river(t: TerrainMap, rng: RandomNumberGenerator, code: int, width: int, bridge: bool) -> void:
	var x0 := rng.randi_range(12, 19)
	var phase := rng.randf() * TAU
	var amp := rng.randf_range(1.0, 2.5)
	var crossings: Array = [rng.randi_range(3, 7), rng.randi_range(10, 14)]
	for y in range(1, t.h - 1):
		var cx := x0 + roundi(sin(y * 0.45 + phase) * amp)
		var crossing := false
		for cy in crossings:
			if y == cy or y == cy + 1:
				crossing = true
		for k in width:
			var x := cx + k
			if not _interior(t, x, y):
				continue
			if crossing:
				t.set_at(x, y, FLOOR if bridge else TerrainMap.ROUGH)
			elif t.at(x, y) != WALL:
				t.set_at(x, y, code)


static func _blob(t: TerrainMap, rng: RandomNumberGenerator, c: Vector2i, r: float, code: int, only_floor: bool) -> void:
	var ri := int(ceil(r)) + 1
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var d := Vector2(dx, dy).length() + rng.randf_range(-0.4, 0.4)
			if d > r:
				continue
			var x := c.x + dx
			var y := c.y + dy
			if not _interior(t, x, y):
				continue
			if only_floor and t.at(x, y) != FLOOR:
				continue
			t.set_at(x, y, code)


static func _rand_floor(t: TerrainMap, rng: RandomNumberGenerator) -> Vector2i:
	for i in 60:
		var x := rng.randi_range(2, t.w - 3)
		var y := rng.randi_range(2, t.h - 3)
		if t.at(x, y) == FLOOR and Vector2(x, y).distance_to(START_M) > 4.0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


## Um retângulo de chão aberto (para colunatas). Tamanho zero se não achar.
static func _open_rect(t: TerrainMap, rng: RandomNumberGenerator, rw: int, rh: int) -> Rect2i:
	for i in 40:
		var r := Rect2i(rng.randi_range(8, t.w - 2 - rw), rng.randi_range(1, t.h - 1 - rh), rw, rh)
		var floors := 0
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if t.at(x, y) == FLOOR:
					floors += 1
		if floors >= rw * rh * 0.7:
			return r
	return Rect2i()


# ---------------------------------------------------------------- garantias

## Área aberta no começo: o grupo nunca nasce encaixotado.
static func _open_start(t: TerrainMap, rng: RandomNumberGenerator) -> void:
	var c := Vector2i(int(START_M.x), int(START_M.y))
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if Vector2(dx, dy).length() <= 2.9 and _interior(t, c.x + dx, c.y + dy):
				t.set_at(c.x + dx, c.y + dy, FLOOR)
	# E algum chão do outro lado, para a saída.
	var right := 0
	for y in range(1, t.h - 1):
		for x in range(t.w - 5, t.w - 1):
			if t.passable(x, y):
				right += 1
	if right < 6:
		var ey := rng.randi_range(3, t.h - 4)
		for dy2 in range(-1, 2):
			for dx2 in range(-3, 1):
				if _interior(t, t.w - 2 + dx2, ey + dy2):
					t.set_at(t.w - 2 + dx2, ey + dy2, FLOOR)


## Liga ao início toda região de chão com algum tamanho, cavando um corredor de 2 m.
## Atravessar água ou fenda vira ponte; atravessar parede vira passagem.
static func _connect_all(t: TerrainMap, rng: RandomNumberGenerator) -> void:
	var start := Vector2i(int(START_M.x), int(START_M.y))
	for guard in 30:
		var mask := t.reach_mask(start)
		# Acha a maior região ainda desligada
		var seen := PackedByteArray()
		seen.resize(t.w * t.h)
		seen.fill(0)
		var biggest: Array = []
		for y in range(1, t.h - 1):
			for x in range(1, t.w - 1):
				var i := y * t.w + x
				if mask[i] != 0 or seen[i] != 0 or not t.passable(x, y):
					continue
				var region: Array = []
				var stack: Array = [Vector2i(x, y)]
				seen[i] = 1
				while not stack.is_empty():
					var c: Vector2i = stack.pop_back()
					region.append(c)
					for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nc: Vector2i = c + dv
						if t.inside(nc.x, nc.y) and seen[nc.y * t.w + nc.x] == 0 and t.passable_v(nc) and mask[nc.y * t.w + nc.x] == 0:
							seen[nc.y * t.w + nc.x] = 1
							stack.append(nc)
				if region.size() > biggest.size():
					biggest = region
		if biggest.size() < 4:
			return
		# Liga o ponto da região mais perto de algo alcançável
		var best_a := Vector2i(-1, -1)
		var best_b := Vector2i(-1, -1)
		var best_d := INF
		for c2 in biggest:
			for y2 in range(1, t.h - 1):
				for x2 in range(1, t.w - 1):
					if mask[y2 * t.w + x2] == 0:
						continue
					var d := Vector2(c2).distance_squared_to(Vector2(x2, y2))
					if d < best_d:
						best_d = d
						best_a = c2
						best_b = Vector2i(x2, y2)
		if best_a.x < 0:
			return
		_carve_line(t, best_a, best_b, 2)


static func _reach_count(t: TerrainMap) -> int:
	var mask := t.reach_mask(Vector2i(int(START_M.x), int(START_M.y)))
	var n := 0
	for v in mask:
		n += v
	return n


# ---------------------------------------------------------------- posicionamento

## Gera o mapa da cena e põe no lugar o grupo, a saída, os pontos de interesse e os bandos.
## Muda a cena no lugar: grava sc["map"] e reescreve as posições. Determinística pela semente.
static func layout(sc: Dictionary, biome_id: String, features: Array, seed_v: int) -> TerrainMap:
	var t := generate(biome_id, features, seed_v)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0x5bd1e995
	sc["map"] = {"biome": biome_id, "features": features.duplicate(), "seed": seed_v, "rows": t.to_rows()}
	var start_c := t.nearest_passable(START_M, 6)
	var mask := t.reach_mask(start_c)
	var field := t.cost_field(TerrainMap.center(start_c))
	var cells: Array = []
	for c in field:
		var cc: Vector2i = c
		if cc.x >= 1 and cc.y >= 1 and cc.x <= t.w - 2 and cc.y <= t.h - 2:
			cells.append(cc)
	cells.sort_custom(func(a, b): return float(field[a]) < float(field[b]) or (float(field[a]) == float(field[b]) and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	var used: Array = []  # posições em metros já ocupadas

	# 1) Grupo: as células mais perto do início, com folga entre os tokens.
	var n_party: int = maxi(sc.get("party_start", []).size(), 8)
	var party: Array = []
	for c2 in cells:
		if party.size() >= n_party:
			break
		var p := TerrainMap.center(c2)
		if t.walkable_m(p) and _far_from(p, party, MIN_SPACING):
			party.append(p)
	sc["party_start"] = party.map(func(p): return _norm(p))
	used.append_array(party)
	var start_center := TerrainMap.center(start_c)

	# 2) Saída: do lado direito, a mais longe a pé.
	var exit_c := Vector2i(-1, -1)
	var best := -INF
	for c3 in cells:
		var score: float = float(field[c3]) + (30.0 if c3.x >= t.w - 6 else 0.0) + rng.randf() * 2.0
		if score > best and t.walkable_m(TerrainMap.center(c3)):
			best = score
			exit_c = c3
	var exit_p := TerrainMap.center(exit_c)

	# 3) Bandos: longe do início, longe entre si, fora da vista do início se der.
	var groups: Array = sc.get("groups", [])
	var centers: Array = []
	for gi in groups.size():
		var grp: Dictionary = groups[gi]
		var pref := _meters(grp.get("pos", [0.65, 0.5]))
		var is_last: bool = gi == groups.size() - 1 and groups.size() > 1
		if is_last:
			pref = exit_p + Vector2(-6.0, 0.0)
		var n_mon: int = grp.get("monsters", []).size()
		var g_best := Vector2i(-1, -1)
		var g_score := -INF
		for relax in 3:
			for c4 in cells:
				var p4 := TerrainMap.center(c4)
				if float(field[c4]) < 10.0 - relax * 2.0 or p4.distance_to(exit_p) < 3.5 - relax:
					continue
				if not _far_from(p4, centers, 8.0 - relax * 2.0) or not _far_from(p4, party, 7.0):
					continue
				if _room_for(t, mask, c4, n_mon, used) < n_mon:
					continue
				var s := -p4.distance_to(pref) + rng.randf() * 3.0
				if t.ray_blocked(start_center, p4):
					s += 6.0
				if s > g_score:
					g_score = s
					g_best = c4
			if g_best.x >= 0:
				break
		if g_best.x < 0:
			g_best = t.nearest_passable(pref, 10, mask)
		var gc := TerrainMap.center(g_best)
		centers.append(gc)
		grp["pos"] = _norm(gc)
		var spots := _cluster(t, mask, g_best, n_mon, used)
		for mi in n_mon:
			var mp: Vector2 = spots[mi] if mi < spots.size() else gc
			grp["monsters"][mi]["pos"] = _norm(mp)
			used.append(mp)

	# 4) Pontos de interesse: espalhados, longe dos bandos e uns dos outros.
	var placed: Array = used.duplicate()
	placed.append(exit_p)
	for poi in sc.get("pois", []):
		if str(poi.get("kind", "")) == "exit":
			poi["pos"] = _norm(exit_p)
			continue
		var p_best := Vector2i(-1, -1)
		var p_score := -INF
		for relax2 in 3:
			for c5 in cells:
				var p5 := TerrainMap.center(c5)
				if float(field[c5]) < 6.0 - relax2 * 2.0 or not t.walkable_m(p5):
					continue
				if not _far_from(p5, centers, 4.0 - relax2):
					continue
				var md := _min_dist(p5, placed)
				if md < 3.0 - relax2:
					continue
				var s2 := minf(md, 9.0) + rng.randf() * 3.0
				if s2 > p_score:
					p_score = s2
					p_best = c5
			if p_best.x >= 0:
				break
		if p_best.x < 0:
			p_best = cells[cells.size() / 2]
		var pp := TerrainMap.center(p_best)
		poi["pos"] = _norm(pp)
		placed.append(pp)
	return t


## Quantas vagas cabem em volta da célula (até 3 m), sem encostar no que já está em `used`.
static func _room_for(t: TerrainMap, mask: PackedByteArray, c: Vector2i, want: int, used: Array) -> int:
	return _cluster(t, mask, c, want, used).size()


static func _cluster(t: TerrainMap, mask: PackedByteArray, c: Vector2i, want: int, used: Array) -> Array:
	var out: Array = []
	var origin := TerrainMap.center(c)
	var ring: Array = []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var cc := c + Vector2i(dx, dy)
			if not t.inside(cc.x, cc.y) or mask[cc.y * t.w + cc.x] == 0:
				continue
			if cc.x < 1 or cc.y < 1 or cc.x > t.w - 2 or cc.y > t.h - 2:
				continue
			ring.append(cc)
	ring.sort_custom(func(a, b): return TerrainMap.center(a).distance_to(origin) < TerrainMap.center(b).distance_to(origin))
	for cc2 in ring:
		if out.size() >= want:
			break
		var p := TerrainMap.center(cc2)
		if p.distance_to(origin) > 3.3 or not t.walkable_m(p):
			continue
		if _far_from(p, out, MIN_SPACING) and _far_from(p, used, MIN_SPACING):
			out.append(p)
	return out


static func _far_from(p: Vector2, pts: Array, d: float) -> bool:
	for q in pts:
		if p.distance_to(q) < d:
			return false
	return true


static func _min_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for q in pts:
		best = minf(best, p.distance_to(q))
	return best


static func _norm(p: Vector2) -> Array:
	return [snappedf(p.x / float(W), 0.0001), snappedf(p.y / float(H), 0.0001)]


static func _meters(a: Variant) -> Vector2:
	if typeof(a) == TYPE_ARRAY and a.size() >= 2:
		return Vector2(float(a[0]) * W, float(a[1]) * H)
	if typeof(a) == TYPE_VECTOR2:
		return Vector2(a.x * W, a.y * H)
	return Vector2(W * 0.6, H * 0.5)


## Cenas de exploração gravadas antes dos mapas: gera o mapa na hora, com semente fixa da cena,
## para quem já tinha uma sala criada não ficar no retângulo liso.
static func ensure(sc: Dictionary, theme_id: String, story: String) -> void:
	if sc.has("map") or sc.get("pois", []).is_empty():
		return
	var seed_v := absi(hash(str(sc.get("art_key", "")) + str(sc.get("id", "")) + str(sc.get("title", ""))))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var text := "%s %s" % [str(sc.get("title", "")), str(sc.get("intro", ""))]
	layout(sc, pick_biome("", theme_id, text, story, rng), [], seed_v)
