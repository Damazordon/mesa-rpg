class_name AdventureGen
extends Node
## Gera a aventura de uma sala a partir do tema e da história escritos pelo mestre humano.
##
## Fluxo ("a IA narra, o motor decide"):
##   1. A IA local (Ollama, mesmo modelo do mestre) recebe o tema, a história, o grupo e uma lista
##      de monstros do SRD, e devolve só texto estruturado: título, sinopse, cena, missões, NPCs.
##   2. O motor confere tudo em `build`: só aceita monstros que existem no SRD e estão na lista,
##      respeita o orçamento de XP do encontro, posiciona os tokens e dá ids únicos.
##   3. Se a IA estiver fechada, demorar ou devolver lixo, `build` monta um modelo equivalente
##      com o que o mestre escreveu. A sala sempre sai jogável.
## O resultado é gravado em user://adventures/<id>/ e carregado por Game.create_room.

signal status(text: String)

const TIMEOUT_S := 180.0

## Orçamento de XP por personagem (Leve, Moderado, Difícil), tabela do Guia do Mestre 2024
## escrita de memória para os níveis 1 a 5. Conferir no livro antes de publicar.
const XP_BUDGET := {1: [50, 75, 100], 2: [100, 150, 200], 3: [150, 225, 400], 4: [250, 375, 500], 5: [500, 750, 1100]}
const DIFF_INDEX := {"low": 0, "moderate": 1, "high": 2}
const MAX_CHAPTERS := 5
## O primeiro capítulo é mais leve e o clímax é o mais pesado: é esta curva que dá a sensação
## de que a aventura aperta. Multiplica o orçamento de XP do encontro.
const CHAPTER_RAMP := [0.7, 1.0, 1.15, 1.3, 1.5]
const POOL_MAX := 70
const MAX_MONSTERS := 8
const BOSS_SLOT := [0.86, 0.45]
const SLOTS := [[0.64, 0.42], [0.71, 0.56], [0.78, 0.36], [0.83, 0.62], [0.68, 0.7], [0.74, 0.24], [0.9, 0.55]]
const PIN_SLOTS := [[0.5, 0.5], [0.72, 0.1], [0.13, 0.2], [0.45, 0.85]]
## Exploração: centros dos bandos escondidos, pontos de interesse, saídas e o aglomerado de
## cada bando em volta do próprio centro. Tudo em coordenadas normalizadas do tabuleiro.
const GROUP_SLOTS := [[0.63, 0.5], [0.84, 0.28], [0.8, 0.74], [0.52, 0.2]]
const GROUP_RADIUS_M := 5.5
const POI_SLOTS := [[0.42, 0.24], [0.55, 0.74], [0.7, 0.16], [0.48, 0.48], [0.74, 0.84], [0.86, 0.5], [0.36, 0.8], [0.62, 0.36]]
const EXIT_SLOTS := [[0.94, 0.5], [0.92, 0.14], [0.92, 0.86]]
const CLUSTER := [[0.0, 0.0], [-0.035, 0.055], [0.04, -0.05], [-0.05, -0.045], [0.05, 0.05], [0.0, 0.09], [0.015, -0.09], [0.07, 0.01]]
## Equipamento mundano do SRD que faz sentido num baú. Filtrado contra o que existe de fato.
const LOOT_GEAR := ["healers_kit", "thieves_tools", "rope", "grappling_hook", "crowbar", "climbers_kit",
	"lantern_hooded", "caltrops", "ball_bearings", "acid", "holy_water", "hunting_trap", "manacles",
	"mirror", "net", "bedroll", "shovel", "spikes_iron", "block_and_tackle", "disguise_kit",
	"forgery_kit", "herbalism_kit", "navigators_tools", "explorers_pack", "dungeoneers_pack",
	"lock", "chain", "bell", "map", "vial"]
const PARTY_START := [[0.27, 0.62], [0.34, 0.7], [0.2, 0.72], [0.38, 0.55], [0.24, 0.82], [0.31, 0.48], [0.15, 0.6], [0.42, 0.78]]
const COLORS := ["#7d8a3a", "#9a4a34", "#6f7a2a", "#7a5a8c", "#4f7a8c", "#a8873a", "#8c4f5f", "#5f8c6a"]

var busy := false
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	add_child(_http)


## Gera a aventura. use_ai = false pula a IA e usa só o modelo do motor.
## Devolve {adventure, quests, bible, source ("ia" ou "modelo"), notes[], stats[]}.
func generate(cfg: Dictionary, use_ai := true) -> Dictionary:
	busy = true
	var raw := {}
	var notes: Array = []
	var source := "modelo"
	if use_ai:
		status.emit("Pedindo a aventura à IA local (%s)." % Master.MODEL)
		raw = await _ask_model(cfg)
		if raw.is_empty():
			notes.append("A IA não respondeu ou devolveu algo inválido (o Ollama está aberto?). Usei o gerador de modelo com o que você escreveu.")
		else:
			source = "ia"
	status.emit("Conferindo monstros, orçamento de XP e posições.")
	var out := build(cfg, raw, notes)
	out["source"] = source
	busy = false
	return out


# ---------------------------------------------------------------- IA

func _ask_model(cfg: Dictionary) -> Dictionary:
	var body := {
		"model": Master.MODEL,
		"stream": false,
		"think": false,
		"format": "json",
		"options": {"temperature": 0.9, "num_ctx": 8192},
		"messages": [
			{"role": "system", "content": system_prompt(cfg)},
			{"role": "user", "content": user_prompt(cfg)},
		],
	}
	var err := _http.request(Master.URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		return {}
	var res: Array = await _http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return {}
	var outer: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(outer) != TYPE_DICTIONARY:
		return {}
	var inner: Variant = JSON.parse_string(str(outer.get("message", {}).get("content", "")))
	if typeof(inner) != TYPE_DICTIONARY:
		return {}
	return inner


static func system_prompt(cfg: Dictionary) -> String:
	var ids := PackedStringArray()
	for id in monster_pool(cfg):
		ids.append("%s (ND %s)" % [id, str(Srd.monsters[id].get("cr", "0"))])
	var t := "Você é o roteirista de uma mesa de D&D 5.2 (SRD). Responda SEMPRE em português do Brasil e APENAS com JSON válido.\n"
	t += "Crie uma aventura curta, com UM encontro de combate, a partir do tema e da história do mestre humano. "
	t += "Respeite o tom do tema. Use os personagens do grupo (nomes, origens e objetivos) em ganchos, pistas, NPCs e missões pessoais.\n"
	t += "Monstros: use SOMENTE ids desta lista, no máximo %d por cena, e no máximo um chefe: %s\n" % [MAX_MONSTERS, ", ".join(ids)]
	var n := clampi(int(cfg.get("chapters", 1)), 1, MAX_CHAPTERS)
	t += "A aventura tem %d capítulo(s), cada um com um encontro de combate. " % n
	if n > 1:
		t += "Eles formam um arco: o primeiro apresenta a ameaça, os do meio revelam quem está por trás e o último é o confronto final, onde fica o chefe. "
		t += "Cada capítulo tem um objetivo curto, que o grupo cumpre ao vencer aquele encontro, e um deve puxar o seguinte. "
	t += "O grupo EXPLORA cada capítulo: anda pelo mapa, descobre pontos de interesse e topa com os bandos escondidos. "
	t += "Por capítulo, escreva: UMA saída (kind \"exit\"), 1 ou 2 pontos obrigatórios (kind \"mark\", required true) que "
	t += "revelam algo da história, e 1 ou 2 baús (kind \"chest\"). Não escreva posição nem coordenada de nada: o motor coloca no mapa.\n"
	t += "O MAPA de cada capítulo é desenhado pelo motor. Você só escolhe, em \"terreno\", UM bioma desta lista: %s; " % ", ".join(PackedStringArray(MapGen.BIOMES.keys()))
	t += "e até 3 feições desta lista: %s. Nada fora das listas, nada de coordenada.\n" % ", ".join(PackedStringArray(MapGen.FEATURES.keys()))
	t += "A \"lore\" é lida pelos JOGADORES antes de criarem os personagens: só o que qualquer um saberia "
	t += "ao aceitar o trabalho. NÃO conte segredo, reviravolta, traidor nem o que há no fim. Os segredos "
	t += "vão em \"npcs\", \"places\" e \"factions\", que só o mestre lê.\n"
	t += "Em \"art_maps\", um pedido de imagem por capítulo, na ordem, em campos curtos e só visuais. "
	t += "Quem gera a imagem não pode descobrir a trama: nada de nome próprio, de capítulo ou de acontecimento.\n"
	t += """
Formato exato:
{"title": "<título curto>", "synopsis": "<2 a 3 frases>", "epilogue": "<2 frases fechando a aventura depois do último capítulo>",
 "lore": "<3 a 5 parágrafos curtos, separados por uma linha vazia: o mundo, o lugar, o tom, quem contrata e o que todos sabem. Sem segredos.>",
 "art_maps": [{"assunto": "<o lugar em 4 a 8 palavras>", "ambiente": "<materiais e elementos visíveis>", "luz": "<de onde vem a luz>", "paleta": "<3 cores>"}],
 "scenes": [{"title": "<nome do capítulo>", "objective": "<objetivo curto deste capítulo, em uma linha>",
   "terreno": {"bioma": "<um bioma da lista>", "feicoes": ["<feição da lista>"]},
   "intro": "<2 a 3 frases que abrem o capítulo, antes de qualquer luta>", "victory": "<1 a 2 frases; se houver capítulo seguinte, aponte para ele>", "defeat": "<1 a 2 frases>",
   "pois": [{"name": "<ponto de interesse>", "kind": "exit|mark|chest", "required": true, "text": "<1 frase do que o grupo vê ao chegar>"}],
   "groups": ["<1 a 2 frases de quando este bando nota o grupo>", "<idem para o bando seguinte>"],
   "monsters": [{"monster_id": "<id da lista>", "name": "<nome opcional>", "boss": false}]}],
 "quests": [{"title": "<missão secundária>", "giver": "<quem pediu>", "summary": "<1 frase>", "objectives": ["<objetivo>"]}],
 "npcs": [{"name": "<nome>", "role": "<papel>", "known": "<o que o grupo sabe>"}],
 "places": [{"name": "<lugar>", "role": "<tipo>", "known": "<o que o grupo sabe>"}],
 "factions": [{"name": "<grupo>", "role": "<papel>", "known": "<o que o grupo sabe>"}]}
Regras: frases curtas; não cite números de regra, CD, dano nem dados; não invente ids de monstro; no máximo 2 missões secundárias, 4 NPCs, 3 lugares e 2 facções."""
	return t


static func user_prompt(cfg: Dictionary) -> String:
	var theme: Dictionary = RoomBuilder.theme_by_id(str(cfg.get("theme", "")))
	var t := "Sala: %s\n" % str(cfg.get("name", ""))
	t += "Tema: %s. %s Tom: %s.\n" % [str(theme.get("name", "")), str(theme.get("description", "")), str(theme.get("tone", ""))]
	t += "História do mestre humano:\n%s\n\n" % str(cfg.get("story", "")).strip_edges().left(1200)
	t += "O grupo tem %d pessoa(s) de nível %d. Os personagens ainda não existem: eles vão ser criados\n" % [party_size(cfg), int(cfg.get("level", 1))]
	t += "depois de ler a sua lore, então não invente nomes nem fichas para eles.\n"
	var n := clampi(int(cfg.get("chapters", 1)), 1, MAX_CHAPTERS)
	var parts := PackedStringArray()
	for i in n:
		parts.append("capítulo %d: até %d XP" % [i + 1, xp_budget(int(cfg.get("level", 1)), party_size(cfg), str(cfg.get("difficulty", "moderate")), i)])
	t += "\nEncontros (soma de XP dos monstros): " + "; ".join(parts) + "."
	return t


# ---------------------------------------------------------------- orçamento e monstros

## Quantas pessoas vão jogar. Na nova ordem a aventura nasce antes dos personagens, então o
## número vem da sala (cfg["player_count"]); só caímos na lista de fichas se ele não vier.
static func party_size(cfg: Dictionary) -> int:
	var n := int(cfg.get("player_count", 0))
	if n <= 0:
		n = cfg.get("players", []).size()
	return maxi(1, n)


static func xp_budget(level: int, players: int, difficulty: String, chapter := 0) -> int:
	var row: Array = XP_BUDGET[clampi(level, 1, 5)]
	var base := int(row[int(DIFF_INDEX.get(difficulty, 1))]) * maxi(1, players)
	return int(base * float(CHAPTER_RAMP[clampi(chapter, 0, CHAPTER_RAMP.size() - 1)]))


## Monstros que a IA pode usar: permitidos pelo tema, que cabem no orçamento e não são triviais.
## Usa o orçamento do último capítulo, para o chefe do clímax estar disponível na lista.
static func monster_pool(cfg: Dictionary) -> Array:
	var last := clampi(int(cfg.get("chapters", 1)), 1, MAX_CHAPTERS) - 1
	var budget := xp_budget(int(cfg.get("level", 1)), party_size(cfg), str(cfg.get("difficulty", "moderate")), last)
	var tid := str(cfg.get("theme", ""))
	var ids: Array = []
	var cheapest := ""
	for id in Srd.list("monster"):
		var m: Dictionary = Srd.monsters[id]
		var xp := int(m.get("xp", 0))
		var tl := str(m.get("type_line", ""))
		if tid == "realista":
			if not (tl.contains("Humanoid") or tl.contains("Beast")):
				continue
		elif str(m.get("source", "")) == "animals":
			continue
		if xp > 0 and (cheapest == "" or xp < int(Srd.monsters[cheapest].get("xp", 0))):
			cheapest = id
		if xp > budget or xp * 20 < budget:
			continue
		ids.append(id)
	ids.sort()
	if ids.size() > POOL_MAX:
		var sampled: Array = []
		var stride := float(ids.size()) / float(POOL_MAX)
		for i in POOL_MAX:
			sampled.append(ids[int(i * stride)])
		ids = sampled
	if ids.is_empty() and cheapest != "":
		ids.append(cheapest)
	return ids


static func _pick_monsters(wanted: Array, budget: int, pool: Array, rng: RandomNumberGenerator, notes: Array) -> Array:
	var out: Array = []
	var total := 0
	var dropped := 0
	for w in wanted:
		var id := ""
		var hint := ""
		var boss := false
		if typeof(w) == TYPE_DICTIONARY:
			id = _s(w.get("monster_id", w.get("id", "")), 60).to_lower()
			hint = _s(w.get("name", ""), 40)
			boss = bool(w.get("boss", false))
		elif typeof(w) == TYPE_STRING:
			id = _s(w, 60).to_lower()
		if not id in pool:
			dropped += 1
			continue
		var xp := int(Srd.monsters[id].get("xp", 0))
		if out.size() >= MAX_MONSTERS or total + xp > budget:
			dropped += 1
			continue
		out.append({"monster_id": id, "hint": hint, "boss": boss, "xp": xp})
		total += xp
	if dropped > 0:
		notes.append("O motor recusou %d monstro(s) sugerido(s) pela IA (fora da lista do SRD, do tema ou do orçamento de XP)." % dropped)
	var filled := false
	var guard := 0
	while out.size() < MAX_MONSTERS and total < int(budget * 0.7) and guard < 40:
		guard += 1
		var left := budget - total
		var fits: Array = pool.filter(func(pid): return int(Srd.monsters[pid].get("xp", 0)) <= left)
		if fits.is_empty():
			break
		var pick: String = fits[rng.randi() % fits.size()]
		var pxp := int(Srd.monsters[pick].get("xp", 0))
		out.append({"monster_id": pick, "hint": "", "boss": false, "xp": pxp})
		total += pxp
		filled = true
	if filled:
		notes.append("O motor completou o encontro com monstros do SRD até chegar perto do orçamento de XP.")
	return out


# ---------------------------------------------------------------- montagem (validação do motor)

## Transforma a resposta da IA (raw, pode estar vazia) na aventura jogável. Determinística:
## a mesma sala e a mesma resposta dão o mesmo resultado.
static func build(cfg: Dictionary, raw: Dictionary, notes: Array) -> Dictionary:
	var level := clampi(int(cfg.get("level", 1)), 1, RoomBuilder.MAX_LEVEL)
	var n_players := party_size(cfg)
	var theme: Dictionary = RoomBuilder.theme_by_id(str(cfg.get("theme", "")))
	var story := str(cfg.get("story", "")).strip_edges()
	var difficulty := str(cfg.get("difficulty", "moderate"))
	var pool := monster_pool(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(story + str(cfg.get("name", "")))
	var from_ai := not raw.is_empty()

	var title := _s(raw.get("title", ""), 70)
	if title == "":
		title = "%s: %s" % [str(theme.get("name", "Aventura")), " ".join(PackedStringArray(story.split(" ", false).slice(0, 5)))]
	var synopsis := _s(raw.get("synopsis", ""), 400)
	if synopsis == "":
		synopsis = story.left(300)

	var chapters := clampi(int(cfg.get("chapters", 1)), 1, MAX_CHAPTERS)
	var raw_scenes := _arr(raw.get("scenes", []))
	var scenes: Array = []
	var stats: Array = []
	var objectives: Array = []
	for i in chapters:
		var rs: Dictionary = raw_scenes[i] if i < raw_scenes.size() and typeof(raw_scenes[i]) == TYPE_DICTIONARY else {}
		var budget_i := xp_budget(level, n_players, difficulty, i)
		var built := _scene(i, rs, story, budget_i, pool, rng, notes, i == chapters - 1, chapters, level)
		stats.append({"title": built["title"], "xp": built["xp_total"], "budget": budget_i})
		objectives.append(built["objective"])
		built.erase("xp_total")
		built.erase("objective")
		scenes.append(built)

	# Mapa de cada capítulo: a IA deu bioma e feições (ou nada); o motor gera, confere e posiciona.
	var theme_id := str(cfg.get("theme", "fantasia"))
	for k in scenes.size():
		var rsk: Dictionary = raw_scenes[k] if k < raw_scenes.size() and typeof(raw_scenes[k]) == TYPE_DICTIONARY else {}
		var brief := MapGen.read_brief(rsk.get("terreno", {}))
		var names := PackedStringArray([str(scenes[k]["title"]), str(scenes[k]["intro"])])
		for poi in scenes[k]["pois"]:
			names.append(str(poi["name"]))
		var bid := MapGen.pick_biome(str(brief["biome"]), theme_id, " ".join(names), story, rng)
		if from_ai and str(brief["biome"]) == "" and typeof(rsk.get("terreno", null)) != TYPE_NIL:
			notes.append("Capítulo %d: o bioma pedido pela IA não está na lista; usei %s." % [k + 1, str(MapGen.biome(bid)["name"]).to_lower()])
		MapGen.layout(scenes[k], bid, brief["features"], rng.randi())
		stats[k]["biome"] = str(MapGen.biome(bid)["name"])

	# Chave da arte por sala e capítulo, não pelo id da aventura: regerar não órfã as imagens.
	var room_slug := RoomBuilder.slug(str(cfg.get("name", "")))
	for sc_i in scenes:
		sc_i["art_key"] = "%s_%s" % [room_slug, str(sc_i["id"])]
	var epilogue := _s(raw.get("epilogue", ""), 400)
	if epilogue == "":
		epilogue = "A aventura se encerra. O que o grupo fez aqui vai ser contado de outras maneiras por quem não estava presente."
	var lore := _s(raw.get("lore", ""), 2200)
	if lore == "":
		lore = "%s\n\n%s" % [story, synopsis]
	var bible := _bible(raw, scenes)
	var adv_id := "%s_%d" % [RoomBuilder.slug(str(cfg.get("name", ""))), int(Time.get_unix_time_from_system()) % 1000000]
	var adventure := {
		"id": adv_id, "title": title, "theme": str(cfg.get("theme", "fantasia")), "synopsis": synopsis, "story": story,
		"room": str(cfg.get("name", "")), "level_range": [level, level], "start_scene": "cap1", "scenes": scenes,
		"epilogue": epilogue, "rest_points": range(0, chapters, 2), "player_count": n_players,
		# Lore é o que os JOGADORES leem: sem segredo. Os segredos ficam na bíblia, que é do mestre.
		"lore": lore, "lore_updated": false,
		"generated": {"source": "ia" if from_ai else "modelo", "model": Master.MODEL if from_ai else "", "at": Time.get_datetime_string_from_system()},
	}
	return {
		"adventure": adventure, "quests": _quests(raw, title, synopsis, objectives), "bible": bible,
		"art": _art_requests(raw, adventure, bible, title), "notes": notes, "stats": stats,
		"source": "ia" if from_ai else "modelo",
	}


static func _scene(i: int, rs: Dictionary, story: String, budget: int, pool: Array, rng: RandomNumberGenerator, notes: Array, is_last: bool, total: int, level: int) -> Dictionary:
	var title := _s(rs.get("title", ""), 80)
	if title == "":
		title = "Capítulo %d" % (i + 1)
	elif not title.to_lower().begins_with("cap"):
		title = "Capítulo %d: %s" % [i + 1, title]
	var objective := _s(rs.get("objective", ""), 140)
	if objective == "":
		objective = "Vencer o confronto final" if is_last and total > 1 else "Superar o capítulo %d" % (i + 1)
	var intro := _s(rs.get("intro", ""), 420)
	if intro == "":
		intro = "Tudo começa aqui. %s" % _first_sentence(story) if i == 0 else "O grupo segue adiante, e o caminho não fica mais fácil."
	var victory := _s(rs.get("victory", ""), 320)
	if victory == "":
		if is_last:
			victory = "O último inimigo cai e, desta vez, não há mais nada se movendo no escuro."
		else:
			victory = "O último inimigo cai. O grupo respira fundo e olha para o que ainda falta resolver."
	var defeat := _s(rs.get("defeat", ""), 320)
	if defeat == "":
		defeat = "As luzes se apagam. O que ameaçava o grupo continua lá, esperando a próxima tentativa."

	var picked := _pick_monsters(_arr(rs.get("monsters", [])), budget, pool, rng, notes)
	var has_boss := false
	for m in picked:
		if m["boss"]:
			has_boss = true
	# O chefe é do clímax: numa aventura de vários capítulos, só o último promove alguém.
	if not has_boss and picked.size() >= 3 and (is_last or total == 1):
		var top := 0
		for k in picked.size():
			if int(picked[k]["xp"]) > int(picked[top]["xp"]):
				top = k
		picked[top]["boss"] = true

	var counts := {}
	for m in picked:
		counts[m["monster_id"]] = int(counts.get(m["monster_id"], 0)) + 1
	var seen := {}
	var xp_total := 0
	# Bandos escondidos: cada um só aparece quando alguém do grupo chega perto.
	var n_groups := 1 if picked.size() <= 2 else (2 if picked.size() <= 5 else 3)
	var lines := _arr(rs.get("groups", []))
	var groups: Array = []
	for gi in n_groups:
		var g_intro := _s(lines[gi] if gi < lines.size() else "", 320)
		if g_intro == "":
			g_intro = "Eles notam vocês antes que dê tempo de recuar." if gi > 0 else intro
		groups.append({"id": "g%d" % (gi + 1), "pos": GROUP_SLOTS[gi % GROUP_SLOTS.size()],
			"radius_m": GROUP_RADIUS_M, "intro": g_intro, "monsters": []})
	for idx in picked.size():
		var m: Dictionary = picked[idx]
		var mid := str(m["monster_id"])
		xp_total += int(m["xp"])
		var nm := Srd.label("monster", mid, str(Srd.monsters[mid]["name"]))
		if int(counts[mid]) > 1:
			seen[mid] = int(seen.get(mid, 0)) + 1
			nm = "%s %s" % [nm, char(64 + int(seen[mid]))]
		elif str(m["hint"]).length() >= 3:
			nm = str(m["hint"])
		# O chefe guarda o último bando; os outros se distribuem.
		var gi2: int = (n_groups - 1) if m["boss"] else (idx % n_groups)
		var grp: Dictionary = groups[gi2]
		var off: Array = CLUSTER[grp["monsters"].size() % CLUSTER.size()]
		var center: Array = grp["pos"]
		var entry := {"id": "m%d" % (idx + 1), "monster_id": mid, "name": nm,
			"pos": [snappedf(clampf(center[0] + off[0], 0.05, 0.95), 0.01), snappedf(clampf(center[1] + off[1], 0.06, 0.94), 0.01)],
			"color": COLORS[absi(hash(mid)) % COLORS.size()]}
		if m["boss"]:
			entry["boss"] = true
		grp["monsters"].append(entry)
	var kept: Array = []
	for grp2 in groups:
		if not grp2["monsters"].is_empty():
			kept.append(grp2)
	groups = kept

	var pins: Array = []
	for p in _arr(rs.get("pins", [])):
		var pn := _s(p.get("name", "") if typeof(p) == TYPE_DICTIONARY else p, 40)
		if pn != "" and pins.size() < PIN_SLOTS.size():
			pins.append({"name": pn, "pos": PIN_SLOTS[pins.size()]})
	return {
		"id": "cap%d" % (i + 1), "title": title, "background": "", "pins": pins, "intro": intro, "victory": victory, "defeat": defeat,
		"encounter": {"monsters": []}, "groups": groups, "pois": _pois(rs, groups, level, rng, is_last),
		"party_start": PARTY_START, "xp_total": xp_total, "objective": objective,
	}


## Pontos de interesse. A IA dá nome e texto; o motor escolhe as posições (longe dos bandos, para
## ninguém cair numa emboscada só por ir atrás de um baú) e o conteúdo. Sempre há uma saída, pelo
## menos um ponto obrigatório e pelo menos um baú.
static func _pois(rs: Dictionary, groups: Array, level: int, rng: RandomNumberGenerator, is_last: bool) -> Array:
	var exit_name := ""
	var exit_text := ""
	var marks: Array = []
	var chests: Array = []
	for p in _arr(rs.get("pois", [])):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var nm := _s(p.get("name", ""), 50)
		if nm == "":
			continue
		var kind := _s(p.get("kind", "mark"), 10).to_lower()
		var txt := _s(p.get("text", ""), 240)
		if kind == "exit" and exit_name == "":
			exit_name = nm
			exit_text = txt
		elif kind == "chest" and chests.size() < 2:
			chests.append({"name": nm, "text": txt})
		elif marks.size() < 2:
			marks.append({"name": nm, "text": txt})
	if exit_name == "":
		exit_name = "O caminho de volta" if is_last else "A passagem adiante"
	if marks.is_empty():
		marks.append({"name": "Sinal de que alguém passou por aqui", "text": ""})
	if chests.is_empty():
		chests.append({"name": "Um fardo esquecido", "text": ""})
	var slots: Array = []
	for s in POI_SLOTS:
		var ok := true
		for grp in groups:
			if Game.dist_m(Vector2(float(s[0]), float(s[1])), Vector2(float(grp["pos"][0]), float(grp["pos"][1]))) < 3.0:
				ok = false
		if ok:
			slots.append(s)
	if slots.is_empty():
		slots = POI_SLOTS.duplicate()
	var out: Array = []
	for mk in marks:
		out.append({"id": "poi%d" % (out.size() + 1), "name": mk["name"], "kind": "mark",
			"required": true, "text": mk["text"], "pos": slots[out.size() % slots.size()]})
	for ch in chests:
		out.append({"id": "poi%d" % (out.size() + 1), "name": ch["name"], "kind": "chest",
			"required": false, "text": ch["text"], "pos": slots[out.size() % slots.size()],
			"loot": _loot_for(level, rng)})
	out.append({"id": "saida", "name": exit_name, "kind": "exit", "required": false,
		"text": exit_text, "pos": EXIT_SLOTS[rng.randi() % EXIT_SLOTS.size()]})
	return out


## Conteúdo de um baú: moedas e equipamento mundano que exista de fato no SRD.
static func _loot_for(level: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = LOOT_GEAR.filter(func(id): return Srd.gear.has(id))
	var lv := clampi(level, 1, 5)
	var coins := 10 + 8 * lv + (rng.randi() % (10 * lv))
	var items: Array = []
	if not pool.is_empty():
		items.append(pool[rng.randi() % pool.size()])
		if rng.randf() < 0.45:
			var second: String = pool[rng.randi() % pool.size()]
			if second != str(items[0]):
				items.append(second)
	return {"coins": coins, "items": items}


## A missão principal tem exatamente um objetivo por capítulo, na ordem: o motor marca o objetivo
## pelo índice do capítulo vencido (Game.complete_chapter_objective). Missões da IA entram como
## secundárias, para não quebrar essa correspondência.
static func _quests(raw: Dictionary, title: String, synopsis: String, objectives: Array) -> Array:
	var out: Array = []
	var objs: Array = []
	for t in objectives:
		objs.append({"text": str(t), "done": false})
	if objs.is_empty():
		objs.append({"text": "Sobreviver ao primeiro encontro", "done": false})
	out.append({"id": "principal", "title": title, "pinned": true, "giver": "", "summary": synopsis, "objectives": objs})
	for q in _arr(raw.get("quests", [])):
		if typeof(q) != TYPE_DICTIONARY:
			continue
		var qt := _s(q.get("title", ""), 80)
		if qt == "" or out.size() >= 3:
			continue
		var sub: Array = []
		for o in _arr(q.get("objectives", [])):
			var txt := _s(o.get("text", "") if typeof(o) == TYPE_DICTIONARY else o, 140)
			if txt != "" and sub.size() < 5:
				sub.append({"text": txt, "done": false})
		if sub.is_empty():
			sub.append({"text": "Descobrir o que está por trás disso", "done": false})
		out.append({"id": "q%d" % out.size(), "title": qt, "pinned": false, "giver": _s(q.get("giver", ""), 60),
			"summary": _s(q.get("summary", ""), 240), "objectives": sub})
	return out


## Missões pessoais: entram na segunda passada, quando os personagens já existem.
## hooks mapeia nome do personagem -> gancho escrito pela IA; sem ele, usa o vínculo da ficha.
static func add_personal_quests(quests: Array, players: Array, hooks: Dictionary) -> void:
	for p in players:
		var nm := str(p.get("name", "")).strip_edges()
		if nm == "":
			continue
		var text := _s(hooks.get(nm, ""), 240)
		if text == "":
			text = str(p.get("profile", {}).get("bonds", "")).strip_edges().left(240)
		if text == "":
			continue
		quests.append({"id": "pessoal_%d" % quests.size(), "title": "%s: objetivo pessoal" % nm, "pinned": false,
			"giver": "pessoal", "summary": text, "objectives": [{"text": text.left(120), "done": false}]})


static func _bible(raw: Dictionary, scenes: Array) -> Dictionary:
	var places := _entries(raw.get("places", []), 3)
	if places.is_empty():
		for sc in scenes:
			for pin in sc.get("pins", []):
				places.append({"name": str(pin["name"]), "role": "Cena", "known": ""})
	return {"npcs": _entries(raw.get("npcs", []), 4), "factions": _entries(raw.get("factions", []), 2), "places": places}


# ---------------------------------------------------------------- pedidos de arte

## Pedidos de imagem para o jogador gerar por fora e importar: um mapa por capítulo e um retrato
## por criatura. Os campos são só visuais e passam por um filtro que apaga nome próprio, nome de
## lugar e menção a capítulo, para quem gera a arte não descobrir a trama. A ordem é embaralhada
## (por hash) para não dar nem a sequência dos capítulos.
static func _art_requests(raw: Dictionary, adventure: Dictionary, bible: Dictionary, title: String) -> Array:
	var banned := _banned_words(adventure, bible, title)
	var out: Array = []
	var maps := _arr(raw.get("art_maps", []))
	var scenes: Array = adventure["scenes"]
	for i in scenes.size():
		var rm: Dictionary = maps[i] if i < maps.size() and typeof(maps[i]) == TYPE_DICTIONARY else {}
		var assunto := _clean(rm.get("assunto", ""), banned, 90)
		if assunto == "":
			assunto = "um lugar fechado e usado, com marcas de quem passou antes"
		var ambiente := _clean(rm.get("ambiente", ""), banned, 140)
		var luz := _clean(rm.get("luz", ""), banned, 80)
		var paleta := _clean(rm.get("paleta", ""), banned, 80)
		var tone := str(Srd.theme.get("tone", ""))
		var parts := PackedStringArray([assunto])
		var bmap: Dictionary = scenes[i].get("map", {})
		if not bmap.is_empty():
			parts.append("cenário: " + str(MapGen.biome(str(bmap.get("biome", ""))).get("name", "")).to_lower())
		if ambiente != "":
			parts.append(ambiente)
		if luz != "":
			parts.append("luz: " + luz)
		if paleta != "":
			parts.append("paleta: " + paleta)
		if tone != "":
			parts.append("tom " + tone)
		parts.append("vista de cima, mapa de batalha, proporção 16:9, sem texto, sem personagens")
		out.append({
			"id": "mapa_%s" % str(scenes[i]["id"]), "kind": "scenes",
			"key": str(scenes[i].get("art_key", "%s_%s" % [str(adventure["id"]), str(scenes[i]["id"])])),
			"label": "Mapa de um lugar desta aventura", "prompt": ". ".join(parts) + ".",
		})
	for mid in _creature_ids(adventure):
		var m: Dictionary = Srd.monsters.get(mid, {})
		if m.is_empty():
			continue
		var nm := Srd.label("monster", mid, str(m["name"]))
		var kind_txt := str(m.get("type_line", "")).split(",")[0].strip_edges()
		var cp := PackedStringArray(["%s" % nm])
		if kind_txt != "":
			cp.append(kind_txt.to_lower())
		if str(Srd.theme.get("tone", "")) != "":
			cp.append("tom " + str(Srd.theme.get("tone", "")))
		cp.append("retrato de corpo inteiro, fundo neutro, sem texto")
		out.append({
			"id": "bicho_%s" % mid, "kind": "monsters", "key": mid,
			"label": "Criatura que aparece em algum momento", "prompt": ". ".join(cp) + ".",
		})
	out.sort_custom(func(a, b): return hash(a["id"]) < hash(b["id"]))
	return out


## Ids distintos de monstro que aparecem na aventura, em qualquer capítulo.
static func _creature_ids(adventure: Dictionary) -> Array:
	var seen := {}
	for sc in adventure.get("scenes", []):
		for grp in sc.get("groups", []):
			for m in grp.get("monsters", []):
				seen[str(m["monster_id"])] = true
		for m2 in sc.get("encounter", {}).get("monsters", []):
			seen[str(m2["monster_id"])] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## O que não pode escapar num pedido de arte.
##
## Pessoas e facções somem até palavra por palavra ("Mestra Odila" tira "odila"): é com nome de
## gente que se descobre trama. Títulos de aventura e de capítulo saem como frase inteira, porque
## costumam anunciar o que acontece. Nome de LUGAR fica: é justamente o que o mapa tem de mostrar,
## e o grupo vai ver aquele lugar de qualquer jeito.
static func _banned_words(adventure: Dictionary, bible: Dictionary, title: String) -> Array:
	var out: Array = []
	for sec in ["npcs", "factions"]:
		for e in bible.get(sec, []):
			var nm := str(e.get("name", "")).strip_edges().to_lower()
			if nm.length() >= 3 and not nm in out:
				out.append(nm)
			for w in nm.split(" ", false):
				var wl := str(w).strip_edges()
				if wl.length() >= 4 and not wl in out:
					out.append(wl)
	var phrases: Array = [title]
	for sc in adventure.get("scenes", []):
		phrases.append(str(sc.get("title", "")))
	for ph in phrases:
		var p := str(ph).strip_edges().to_lower()
		if p.length() >= 3 and not p in out:
			out.append(p)
	return out


## Apaga do texto o que for segredo e corta no tamanho.
static func _clean(v: Variant, banned: Array, limit: int) -> String:
	var s := _s(v, limit * 2).to_lower()
	for b in banned:
		s = s.replace(str(b), " ")
	var caps := RegEx.create_from_string("cap[ií]tulo\\s*\\d*")
	s = caps.sub(s, " ", true)
	var digits := RegEx.create_from_string("\\d+")
	s = digits.sub(s, " ", true)
	var spaces := RegEx.create_from_string("\\s{2,}")
	s = spaces.sub(s, " ", true)
	return s.strip_edges().left(limit)


# ---------------------------------------------------------------- segunda passada (lore)

## A lore é reescrita com os personagens dentro, depois de criados. Só texto: encontros, monstros
## e orçamento de XP ficam como estavam, para a validação da primeira passada continuar valendo.
func update_lore(result: Dictionary, players: Array, use_ai := true) -> Dictionary:
	busy = true
	var adv: Dictionary = result["adventure"]
	# Guarda a lore original: reescrever duas vezes (o grupo mudou) parte sempre dela, não da
	# versão já reescrita, e as missões pessoais antigas saem para não duplicar.
	if not adv.has("lore_base"):
		adv["lore_base"] = str(adv.get("lore", ""))
	adv["lore"] = str(adv["lore_base"])
	var kept: Array = []
	for q in result.get("quests", []):
		if not str(q.get("id", "")).begins_with("pessoal_"):
			kept.append(q)
	result["quests"] = kept
	var answer := {}
	if use_ai:
		status.emit("Reescrevendo a lore com o grupo dentro dela.")
		answer = await _ask_lore(adv, players)
	var lore := _s(answer.get("lore", ""), 2600)
	var hooks := {}
	for h in _arr(answer.get("hooks", [])):
		if typeof(h) == TYPE_DICTIONARY:
			var hn := _s(h.get("name", ""), 60)
			if hn != "":
				hooks[hn] = _s(h.get("hook", ""), 240)
	if lore == "":
		lore = _lore_fallback(adv, players)
		result["lore_source"] = "modelo"
	else:
		result["lore_source"] = "ia"
	adv["lore"] = lore
	adv["lore_updated"] = true
	add_personal_quests(result["quests"], players, hooks)
	busy = false
	return result


func _ask_lore(adv: Dictionary, players: Array) -> Dictionary:
	var who := ""
	for p in players:
		var pr: Dictionary = p.get("profile", {})
		who += "- %s: %s %s" % [str(p.get("name", "")), Srd.label("species", str(p["species_id"])), Srd.label("class", str(p["classes"][0]["class_id"]))]
		for k in [["background", "origem"], ["bio", "história"], ["bonds", "objetivo"]]:
			var v := str(pr.get(k[0], "")).strip_edges()
			if v != "":
				who += "; %s: %s" % [k[1], v.left(300)]
		who += "\n"
	var sys := "Você é o mestre de uma mesa de D&D. Responda em português do Brasil e APENAS com JSON.\n"
	sys += "Vou te dar a lore pública de uma aventura e o grupo que acabou de ser criado. Reescreva a lore "
	sys += "amarrando estes personagens ao lugar e ao trabalho: como chegaram, quem já ouviu falar de quem, "
	sys += "o que cada um tem a ganhar. Mantenha os fatos da lore original e NÃO revele segredo nem reviravolta.\n"
	sys += "Depois, um gancho pessoal curto para cada personagem, usando o objetivo dele.\n"
	sys += "Formato: {\"lore\": \"<3 a 6 parágrafos curtos separados por linha vazia>\", "
	sys += "\"hooks\": [{\"name\": \"<nome exato do personagem>\", \"hook\": \"<1 frase>\"}]}"
	var body := {
		"model": Master.MODEL, "stream": false, "think": false, "format": "json",
		"options": {"temperature": 0.85, "num_ctx": 8192},
		"messages": [
			{"role": "system", "content": sys},
			{"role": "user", "content": "Lore atual:\n%s\n\nGrupo:\n%s" % [str(adv.get("lore", "")).left(2000), who]},
		],
	}
	var err := _http.request(Master.URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		return {}
	var res: Array = await _http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return {}
	var outer: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(outer) != TYPE_DICTIONARY:
		return {}
	var inner: Variant = JSON.parse_string(str(outer.get("message", {}).get("content", "")))
	return inner if typeof(inner) == TYPE_DICTIONARY else {}


## Sem IA, o motor acrescenta o grupo à lore com o que os jogadores escreveram.
static func _lore_fallback(adv: Dictionary, players: Array) -> String:
	var base := str(adv.get("lore", ""))
	var names := PackedStringArray()
	var lines := PackedStringArray()
	for p in players:
		var nm := str(p.get("name", "")).strip_edges()
		if nm == "":
			continue
		names.append(nm)
		var line := "%s, %s %s" % [nm, Srd.label("species", str(p["species_id"])), Srd.label("class", str(p["classes"][0]["class_id"]))]
		var orig := str(p.get("profile", {}).get("background", "")).strip_edges()
		if orig != "":
			line += " — %s" % orig
		lines.append(line)
	if names.is_empty():
		return base
	var tail := "\n\nQuem aceitou o trabalho: %s.\n\n%s" % [", ".join(names), "\n".join(lines)]
	return base + tail


static func _entries(v: Variant, limit: int) -> Array:
	var out: Array = []
	for e in _arr(v):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var nm := _s(e.get("name", ""), 50)
		if nm != "" and out.size() < limit:
			out.append({"name": nm, "role": _s(e.get("role", ""), 60), "known": _s(e.get("known", ""), 220)})
	return out


# ---------------------------------------------------------------- utilitários

static func _s(v: Variant, limit: int) -> String:
	if v == null:
		return ""
	return str(v).strip_edges().left(limit)


static func _arr(v: Variant) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


static func _first_sentence(s: String) -> String:
	var cut := s.find(". ")
	var out := s if cut < 0 else s.left(cut + 1)
	return out.left(220)


## Grava adventure.json, quests.json e bible.json em user://adventures/<id>/.
static func save(result: Dictionary) -> bool:
	var adv: Dictionary = result["adventure"]
	var dir := "user://adventures/%s/" % str(adv["id"])
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var files := {"adventure.json": adv, "quests.json": result["quests"], "bible.json": result["bible"]}
	for fname in files:
		var f := FileAccess.open(dir + fname, FileAccess.WRITE)
		if f == null:
			return false
		f.store_string(JSON.stringify(files[fname], "  "))
	return true
