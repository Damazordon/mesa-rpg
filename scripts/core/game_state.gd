extends Node
## Estado da mesa (autoload "Game"): aventura carregada, grupo, inimigos, ordem de turnos.
## As regras ficam no Combat (scripts/rules/combat.gd) e os números saem de Rules/Srd.
## A interface nunca altera o estado direto: chama as funções daqui e escuta os sinais.
##
## Tabuleiro: um retângulo 16:9 com 18 m de altura (32 m de largura). 5 pés = 1,5 m.
## Posições ficam normalizadas (0 a 1); distâncias de regra são sempre em metros.
##
## Lados: "party" (jogadores), "enemy" (hostil), "ally" (NPC do lado do grupo),
## "neutral" (rendido ou fora da luta; não age e não é alvo).
##
## Turno (economia oficial do SRD 5.2.1): uma ação, uma ação bônus, uma reação (por rodada),
## deslocamento divisível e uma interação com objeto.

signal state_changed(id: String)
signal turn_changed(id: String, round_num: int)
signal turn_resources_changed
signal narration_added(text: String)
signal player_spoke(actor_id: String, text: String)
signal taunt_said(text: String, mood: String)
signal dice_logged(entry: Dictionary)
signal engine_logged(text: String)
signal floating_text(id: String, text: String, kind: String)
signal fx_requested(actor_id: String, ability: Dictionary, target_ids: Array)
signal token_moved(id: String, from: Vector2, to: Vector2, duration: float)
signal check_requested(check: Dictionary)
signal check_cleared
signal target_selected(id: String)
signal bible_changed
signal quests_changed
signal pois_changed
## A névoa mudou (o grupo viu células novas).
signal vision_changed
signal chapter_ready(index: int, total: int)
signal chapter_cleared(index: int, total: int)
signal adventure_finished
signal busy_changed(is_busy: bool)
signal combat_ended(victory: bool)
signal party_changed
signal level_up_available(id: String)

const DATA_DIR := "res://data/"
const BOARD_H_M := 18.0
const BOARD_ASPECT := 16.0 / 9.0
const TOKEN_RADIUS_M := 0.65
const MIN_GAP_M := 1.2
const MELEE_M := 1.5
const SETTINGS_PATH := "user://mesa.json"

## Efeitos que o motor aceita do mestre. Qualquer outro é recusado e registrado.
const EFFECTS := ["side", "condition", "flee", "reveal", "bible_note", "taunt", "damage", "heal", "save"]
const OLD_CONDITION_IDS := {"amedrontado": "frightened", "rendido": "surrendered", "escondido": "invisible",
	"caido": "prone", "incapacitado": "incapacitated", "envenenado": "poisoned", "agarrado": "grappled",
	"contido": "restrained", "cego": "blinded", "atordoado": "stunned"}

var adventure := {}
var theme := {}
var party: Array = []
var enemies: Array = []
var by_id: Dictionary = {}
var conditions: Dictionary = {}
var quests: Array = []
var bible: Dictionary = {}
var lines: Dictionary = {}
var scene_info: Dictionary = {}

## Capítulo atual da aventura (índice em adventure["scenes"]) e se o encontro dele já foi vencido.
var chapter := 0
var chapter_done := false
var order: Array = []
var turn_index := 0
var round_num := 1
var in_combat := false
var pending_check: Dictionary = {}
var busy := false
var selected_target := ""
var turns := {}
var xp_pool := 0
var settings := {"auto_reactions": true, "auto_inspiration": true, "auto_stunning_strike": true,
	"auto_cunning_strike": true, "adventure": "vale_cinzento", "theme": "", "level_mode": "xp"}
var cb: Combat
var ex: Exploration
## Exploração do capítulo: pontos de interesse e grupos de inimigos escondidos (ver exploration.gd).
var pois: Array = []
var groups: Array = []
## Terreno do capítulo (paredes, obstáculos, terreno difícil). Vazio nas cenas antigas: tudo livre.
var terrain := TerrainMap.new()
## Névoa: células já vistas e as vistas agora (1 byte por célula, w*h). Vazias sem terreno.
var seen := PackedByteArray()
var visible_now := PackedByteArray()
## Trajeto do último movimento, por id (posições normalizadas), para a animação seguir o caminho.
var move_paths := {}
## Testes automáticos desligam a gravação do grupo em user://.
var persist := true
## Depois de criar uma sala a tela principal é recarregada; esta marca evita abrir a criação de sala de novo.
var skip_room_once := false

## Compatibilidade com a interface antiga
var move_left: float:
	get:
		return float(turn_of(current()).get("move_left", 0.0))
var action_used: bool:
	get:
		var t := turn_of(current())
		return not t.get("action", false) and int(t.get("surge", 0)) == 0 and int(t.get("attacks_left", 0)) == 0
var item_used: bool:
	get:
		return false


func _ready() -> void:
	cb = Combat.new(self)
	ex = Exploration.new(self)
	lines = _load("master_lines.json", {})
	for c in _load("conditions.json", []):
		conditions[c["id"]] = c
	_load_settings()
	load_adventure(str(settings.get("adventure", "vale_cinzento")), str(settings.get("theme", "")))


func _load(file: String, fallback: Variant) -> Variant:
	var path := file if file.begins_with("res://") or file.begins_with("user://") else DATA_DIR + file
	if not FileAccess.file_exists(path):
		return fallback
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("JSON inválido em %s" % path)
		return fallback
	return parsed


func _load_settings() -> void:
	var s: Dictionary = _load(SETTINGS_PATH, {})
	for k in s:
		settings[k] = s[k]


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "  "))


# ---------------------------------------------------------------- aventura

## Pasta da aventura: as geradas pela tela de sala ficam em user://adventures/, as de exemplo em res://data/.
func adventure_dir(adv_id: String) -> String:
	var user_dir := "user://adventures/%s/" % adv_id
	if FileAccess.file_exists(user_dir + "adventure.json"):
		return user_dir
	return DATA_DIR + "adventures/%s/" % adv_id


## Carrega uma mesa: tema, grupo, cena inicial e encontro.
func load_adventure(adv_id: String, theme_override := "") -> void:
	var dir := adventure_dir(adv_id)
	adventure = _load(dir + "adventure.json", {})
	if adventure.is_empty():
		push_error("Aventura não encontrada: %s" % adv_id)
		return
	var theme_id := theme_override if theme_override != "" else str(adventure.get("theme", "fantasia"))
	theme = _load(DATA_DIR + "themes/%s.json" % theme_id, {})
	Srd.set_theme(theme)
	quests = _load(dir + "quests.json", [])
	bible = _load(dir + "bible.json", {})
	party.clear()
	enemies.clear()
	by_id.clear()
	var saved: Array = _load("user://party_%s.json" % adv_id, [])
	var choices_list: Array = saved if not saved.is_empty() else _load(dir + "party.json", [])
	for ch in choices_list:
		_add_pc(ch)
	# Retoma o capítulo onde o grupo parou; se não houver registro, começa pela cena inicial.
	var scenes: Array = adventure.get("scenes", [])
	var saved_ch := int(settings.get("chapter_%s" % adv_id, -1))
	chapter = clampi(saved_ch, 0, maxi(0, scenes.size() - 1)) if saved_ch >= 0 else 0
	if saved_ch < 0:
		var scene_id := str(adventure.get("start_scene", ""))
		for i in scenes.size():
			if scenes[i]["id"] == scene_id:
				chapter = i
				break
	if not scenes.is_empty():
		load_scene(scenes[chapter])
		chapter_ready.emit(chapter, scenes.size())


## Cria a mesa a partir da tela de sala: grava a aventura gerada e o grupo, e carrega tudo.
## cfg["players"] já vem completo (RoomBuilder.finalize_player). Devolve false se não conseguiu gravar.
func create_room(cfg: Dictionary, result: Dictionary) -> bool:
	if not AdventureGen.save(result):
		return false
	var adv_id := str(result["adventure"]["id"])
	var arr: Array = []
	var used := {}
	for p in cfg.get("players", []):
		var ch: Dictionary = p.duplicate(true)
		var base_id := str(ch.get("name", "pc")).to_lower().strip_edges().replace(" ", "_")
		if base_id == "":
			base_id = "pc"
		var id := base_id
		var n := 2
		while used.has(id):
			id = "%s_%d" % [base_id, n]
			n += 1
		used[id] = true
		ch["id"] = id
		ch["xp"] = Srd.xp_for_level(CharBuilder.level_of(ch))
		arr.append(ch)
	var f := FileAccess.open("user://party_%s.json" % adv_id, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(arr, "  "))
	f.close()
	settings["adventure"] = adv_id
	settings["theme"] = ""
	settings["level_mode"] = str(cfg.get("level_mode", "xp"))
	settings["rest_mode"] = str(cfg.get("rest_mode", "aventura"))
	settings["chapter_%s" % adv_id] = 0
	chapter = 0
	save_settings()
	Master.set_level(str(cfg.get("master_level", "normal")))
	load_adventure(adv_id)
	party_changed.emit()
	return true


func _add_pc(ch: Dictionary) -> Dictionary:
	var c := CharBuilder.build(ch)
	var p: Array = ch.get("pos", [0.3, 0.6])
	c["pos"] = Vector2(float(p[0]), float(p[1]))
	c["side"] = "party"
	party.append(c)
	by_id[c["id"]] = c
	return c


func load_scene(sc: Dictionary) -> void:
	# Salas criadas antes dos mapas ganham um na hora (semente fixa da cena: sempre o mesmo).
	MapGen.ensure(sc, str(adventure.get("theme", "fantasia")), str(adventure.get("story", "")))
	terrain = TerrainMap.from_scene(sc)
	move_paths.clear()
	# Posição inicial do grupo: a da cena, senão uma formação no lado esquerdo.
	var starts: Array = sc.get("party_start", [])
	for i in party.size():
		var p: Array = starts[i] if i < starts.size() else [0.2 + 0.07 * (i % 3), 0.55 + 0.1 * (i / 3)]
		party[i]["pos"] = Vector2(float(p[0]), float(p[1]))
	scene_info = {
		"id": sc["id"], "campaign": adventure.get("title", ""), "chapter": sc.get("title", ""),
		"background": sc.get("background", ""), "art_key": sc.get("art_key", ""), "intro": sc.get("intro", ""),
		"victory": sc.get("victory", ""), "defeat": sc.get("defeat", ""), "pins": sc.get("pins", []),
	}
	for e in enemies:
		by_id.erase(e["id"])
	enemies.clear()
	for m in sc.get("encounter", {}).get("monsters", []):
		var over: Dictionary = m.get("overrides", {}).duplicate()
		if m.has("name"):
			over["name"] = m["name"]
		var c := MonsterBuilder.build(str(m["monster_id"]), str(m["id"]), over)
		if c.is_empty():
			continue
		var p: Array = m.get("pos", [0.7, 0.5])
		c["pos"] = Vector2(float(p[0]), float(p[1]))
		c["side"] = str(m.get("side", "enemy"))
		c["color"] = m.get("color", c["color"])
		c["boss"] = m.get("boss", false)
		for cid in m.get("conditions", []):
			c["conditions"].append({"id": cid, "source": ""})
		enemies.append(c)
		by_id[c["id"]] = c
	# Pontos de interesse e grupos escondidos. Cenas sem "pois" seguem no fluxo antigo.
	ex.setup(sc)


# ---------------------------------------------------------------- capítulos

func chapter_count() -> int:
	return adventure.get("scenes", []).size()


func chapter_title(i := -1) -> String:
	var scenes: Array = adventure.get("scenes", [])
	var idx: int = chapter if i < 0 else i
	if idx < 0 or idx >= scenes.size():
		return ""
	return str(scenes[idx].get("title", ""))


func has_next_chapter() -> bool:
	return chapter + 1 < chapter_count()


## Descanso longo: só nos pontos marcados pela aventura ("aventura") ou sempre ("livre").
## É o freio do desgaste: descansar depois de toda luta tira a tensão da aventura inteira.
func can_long_rest() -> bool:
	if in_combat:
		return false
	if str(settings.get("rest_mode", "livre")) != "aventura":
		return true
	for p in adventure.get("rest_points", []):
		if int(p) == chapter:
			return true
	return false


func _save_chapter() -> void:
	if not persist or adventure.is_empty():
		return
	settings["chapter_%s" % str(adventure.get("id", "mesa"))] = chapter
	save_settings()


## Fecha o capítulo: narra a vitória, marca o objetivo no diário e avisa a interface.
## Chamado ao limpar o encontro (cenas sem exploração) ou ao alcançar a saída (com exploração).
func clear_chapter() -> void:
	if chapter_done:
		return
	chapter_done = true
	narration_added.emit(str(scene_info.get("victory", "")))
	complete_chapter_objective()
	chapter_cleared.emit(chapter, chapter_count())
	combat_ended.emit(true)
	if not has_next_chapter():
		narration_added.emit(str(adventure.get("epilogue", "")))
		adventure_finished.emit()


## Marca no diário o objetivo do capítulo que acabou de ser vencido.
func complete_chapter_objective() -> void:
	var main_q: Dictionary = {}
	for q in quests:
		if q.get("pinned", false):
			main_q = q
			break
	if main_q.is_empty() and not quests.is_empty():
		main_q = quests[0]
	var objs: Array = main_q.get("objectives", [])
	if chapter < objs.size() and not bool(objs[chapter].get("done", false)):
		objs[chapter]["done"] = true
		engine_log("Objetivo concluído: %s" % str(objs[chapter]["text"]))
		quests_changed.emit()


## Passa para o capítulo seguinte. Os PV e os recursos gastos continuam como estão: o desgaste
## acumulado é a dificuldade da aventura. Quem estava caído volta estabilizado com 1 PV.
func advance_chapter() -> bool:
	if in_combat or not has_next_chapter():
		return false
	chapter += 1
	chapter_done = false
	for c in party:
		if c.get("death", {}).get("dead", false):
			continue
		c["conditions"] = []
		c["death"] = {"success": 0, "fail": 0, "stable": false, "dead": false}
		if int(c["hp"]) <= 0:
			c["hp"] = 1
			engine_log("%s é estabilizado e segue com 1 PV." % c["name"])
	# Iniciativa, alvo e teste pendente eram do encontro anterior: a cena nova recria tudo.
	# Deixar a ordem antiga em pé faz a interface procurar inimigos que já saíram do tabuleiro.
	order.clear()
	turn_index = 0
	turns.clear()
	select_target("")
	if not pending_check.is_empty():
		pending_check = {}
		check_cleared.emit()
	load_scene(adventure["scenes"][chapter])
	_save_chapter()
	party_changed.emit()
	chapter_ready.emit(chapter, chapter_count())
	narration_added.emit("Novo capítulo: %s" % chapter_title())
	return true


## Salva as escolhas do grupo (personagens criados pelos jogadores) para esta mesa.
func save_party() -> void:
	if not persist:
		return
	var arr: Array = []
	for c in party:
		var ch: Dictionary = c["choices"].duplicate(true)
		ch.erase("pos")
		ch["xp"] = c.get("xp", 0)
		arr.append(ch)
	var f := FileAccess.open("user://party_%s.json" % adventure.get("id", "mesa"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(arr, "  "))


## Adiciona um personagem recém-criado ao grupo (fora de combate).
func add_character(ch: Dictionary) -> Dictionary:
	if not ch.has("pos"):
		ch["pos"] = [0.22 + 0.05 * party.size(), 0.62 + 0.04 * (party.size() % 3)]
	var base_id := str(ch.get("name", "pc")).to_lower().replace(" ", "_")
	var id := base_id
	var n := 2
	while by_id.has(id):
		id = "%s_%d" % [base_id, n]
		n += 1
	ch["id"] = id
	var c := _add_pc(ch)
	save_party()
	party_changed.emit()
	return c


func remove_character(id: String) -> void:
	if in_combat:
		return
	party = party.filter(func(c): return c["id"] != id)
	by_id.erase(id)
	save_party()
	party_changed.emit()


## Reconstrói a ficha depois de mudar as escolhas (subida de nível, troca de magias).
func rebuild(id: String, new_choices: Dictionary) -> Dictionary:
	var old: Dictionary = by_id[id]
	var lost: int = int(old["hp_max"]) - int(old["hp"])
	var c := CharBuilder.build(new_choices)
	# A ficha reconstruída mantém o id que recebeu. Sem isto, o CharBuilder deriva o id do nome
	# e o `party` passa a ter um id diferente do que está no `by_id`: qualquer busca por id
	# quebra depois, longe daqui (foi o que aconteceu no `start_combat` após um saque).
	c["id"] = id
	c["choices"]["id"] = id
	for k in ["pos", "side", "xp", "conditions", "effects", "exhaustion", "temp_hp", "death"]:
		if old.has(k):
			c[k] = old[k]
	# Nível liberado por marco de história pode chegar antes da experiência; a faixa acompanha o nível.
	c["xp"] = maxi(int(c.get("xp", 0)), Srd.xp_for_level(int(c["level"])))
	c["hp"] = maxi(0 if old["hp"] == 0 else 1, int(c["hp_max"]) - lost)
	# Mantém os recursos já gastos
	for rid in c["resources"]:
		if old.get("resources", {}).has(rid):
			var spent: int = int(old["resources"][rid]["max"]) - int(old["resources"][rid]["left"])
			c["resources"][rid]["left"] = maxi(0, int(c["resources"][rid]["max"]) - spent)
	var idx := party.find(old)
	party[idx] = c
	by_id[id] = c
	save_party()
	state_changed.emit(id)
	party_changed.emit()
	return c


# ---------------------------------------------------------------- consultas

func all_combatants() -> Array:
	return party + enemies


func current() -> Dictionary:
	if order.is_empty() or turn_index >= order.size():
		return {}
	return by_id.get(order[turn_index], {})


func turn_of(c: Dictionary) -> Dictionary:
	if c.is_empty():
		return {}
	if not turns.has(c["id"]):
		turns[c["id"]] = {}
	return turns[c["id"]]


func is_alive(c: Dictionary) -> bool:
	return int(c.get("hp", 0)) > 0 and not c.get("death", {}).get("dead", false)


func is_party_turn() -> bool:
	var c := current()
	return in_combat and not c.is_empty() and c["side"] == "party" and is_alive(c)


func is_my_turn(c: Dictionary) -> bool:
	return in_combat and current().get("id", "") == c.get("id", "-") and not busy


func is_hero(c: Dictionary) -> bool:
	return c["side"] == "party" or c["side"] == "ally"


func is_foe(c: Dictionary) -> bool:
	return c["side"] == "enemy"


## Lados opostos: heróis contra inimigos. Neutros não são hostis a ninguém.
func hostile(a: Dictionary, b: Dictionary) -> bool:
	return (is_hero(a) and is_foe(b)) or (is_foe(a) and is_hero(b))


func is_foe_of(a: Dictionary, b: Dictionary) -> bool:
	return hostile(a, b)


func has_condition(c: Dictionary, cond_id: String) -> bool:
	return Rules.has_condition(c, OLD_CONDITION_IDS.get(cond_id, cond_id))


func add_condition(c: Dictionary, cond_id: String, rounds: int) -> void:
	cb.add_condition(c, OLD_CONDITION_IDS.get(cond_id, cond_id), {}, {"rounds": rounds} if rounds > 0 else {})


func remove_condition(c: Dictionary, cond_id: String) -> void:
	cb.remove_condition(c, OLD_CONDITION_IDS.get(cond_id, cond_id))


func ac_of(c: Dictionary) -> int:
	return Rules.ac(c)


func dex_mod(c: Dictionary) -> int:
	return Rules.amod(c, "dex")


func health_word(c: Dictionary) -> String:
	var hp: int = c["hp"]
	if c.get("death", {}).get("dead", false):
		return "morto"
	if hp <= 0:
		return "caído"
	var ratio := float(hp) / float(c["hp_max"])
	if ratio >= 1.0:
		return "intacto"
	if ratio > 0.5:
		return "ferido"
	return "muito ferido (sangrando)"


func side_word(c: Dictionary) -> String:
	match c["side"]:
		"ally":
			return "aliado do grupo"
		"neutral":
			return "rendido" if Rules.has_condition(c, "surrendered") else "fora da luta"
		"enemy":
			return "hostil"
	return ""


# ---------------------------------------------------------------- geometria (metros)

static func to_m(p: Vector2) -> Vector2:
	return Vector2(p.x * BOARD_ASPECT * BOARD_H_M, p.y * BOARD_H_M)


static func from_m(mm: Vector2) -> Vector2:
	return Vector2(mm.x / (BOARD_ASPECT * BOARD_H_M), mm.y / BOARD_H_M)


static func dist_m(a: Vector2, b: Vector2) -> float:
	return to_m(a).distance_to(to_m(b))


func dist_between(a: Dictionary, b: Dictionary) -> float:
	return dist_m(a["pos"], b["pos"])


static func fmt_m(v: float) -> String:
	return ("%.1f m" % v).replace(".", ",")


## Alcance de uma atividade (ataque, magia, característica) em metros.
func ability_range(ab: Dictionary) -> float:
	if ab.has("range_m") and typeof(ab["range_m"]) in [TYPE_FLOAT, TYPE_INT]:
		return float(ab["range_m"])
	return MELEE_M


func in_range(actor: Dictionary, ab: Dictionary, target: Dictionary) -> bool:
	return dist_between(actor, target) <= ability_range(ab) + 0.05


static func is_item(ab: Dictionary) -> bool:
	return bool(ab.get("item", false))


func spot_free(p: Vector2, ignore_id: String) -> bool:
	if p.x < 0.02 or p.x > 0.98 or p.y < 0.03 or p.y > 0.97:
		return false
	if not terrain.walkable_m(to_m(p)):
		return false
	for c in all_combatants():
		if c["id"] != ignore_id and (is_alive(c) or c["kind"] == "pc") and not c.get("death", {}).get("dead", false) and dist_m(p, c["pos"]) < MIN_GAP_M:
			return false
	return true


func _spot_free(p: Vector2, ignore_id: String) -> bool:
	return spot_free(p, ignore_id)


# ---------------------------------------------------------------- terreno (posições normalizadas)

func has_terrain() -> bool:
	return not terrain.is_empty()


## Dá para um token ficar em p (sem contar as outras criaturas)?
func walkable(p: Vector2) -> bool:
	return terrain.walkable_m(to_m(p))


func line_clear(a: Vector2, b: Vector2) -> bool:
	return terrain.line_clear(to_m(a), to_m(b))


## a enxerga b? Parede e coluna tapam; obstáculo baixo e vão não.
func sees(a: Dictionary, b: Dictionary) -> bool:
	return a["id"] == b["id"] or line_clear(a["pos"], b["pos"])


## Cobertura de t contra um ataque de a (TerrainMap.COVER_*). Criaturas no meio dão meia cobertura.
func cover_between(a: Dictionary, t: Dictionary) -> int:
	if not has_terrain() or a["id"] == t["id"]:
		return TerrainMap.COVER_NONE
	var others: Array = []
	for c in all_combatants():
		if c["id"] != a["id"] and c["id"] != t["id"] and is_alive(c):
			others.append(to_m(c["pos"]))
	return terrain.cover(to_m(a["pos"]), to_m(t["pos"]), others)


## Cobertura de t contra uma área que nasce em `origin` (normalizado). Sem se inclinar: é a explosão.
func cover_from_point(origin: Vector2, t: Dictionary) -> int:
	if not has_terrain():
		return TerrainMap.COVER_NONE
	return terrain.cover(to_m(origin), to_m(t["pos"]))


## Células por onde c não pode passar: as de criaturas hostis em pé.
func blocked_cells_for(c: Dictionary, except_id := "") -> Dictionary:
	var out := {}
	if not has_terrain():
		return out
	for o in all_combatants():
		if o["id"] == c["id"] or o["id"] == except_id or not is_alive(o) or not hostile(c, o):
			continue
		out[TerrainMap.cell_of(to_m(o["pos"]))] = true
	return out


## Caminho andando até dest: {"points": PackedVector2Array normalizado, "cost": metros com terreno
## difícil em dobro, "length": metros andados}, ou {} se não há caminho.
func plan_path(c: Dictionary, dest: Vector2, except_id := "") -> Dictionary:
	var res := terrain.find_path(to_m(c["pos"]), to_m(dest), blocked_cells_for(c, except_id))
	if res.is_empty():
		return {}
	var pts := PackedVector2Array()
	for p in res["points"]:
		pts.append(from_m(p))
	return {"points": pts, "cost": float(res["cost"]), "length": TerrainMap.length_of(res["points"])}


## Ajusta um destino clicado colado numa parede para o centro da célula.
func settle(p: Vector2) -> Vector2:
	return from_m(terrain.settle_m(to_m(p)))


## Recalcula a névoa a partir de quem está em pé no grupo.
func update_vision() -> void:
	if not has_terrain():
		seen = PackedByteArray()
		visible_now = PackedByteArray()
		return
	var n := terrain.w * terrain.h
	if seen.size() != n:
		seen.resize(n)
		seen.fill(0)
	visible_now.resize(n)
	visible_now.fill(0)
	var radius := float(MapGen.biome(terrain.biome).get("vision_m", 12.0))
	for c in party:
		if not is_alive(c) and int(c.get("hp", 0)) <= 0 and c.get("death", {}).get("dead", false):
			continue
		for cell in terrain.visible_from(to_m(c["pos"]), radius):
			var i: int = cell.y * terrain.w + cell.x
			visible_now[i] = 1
			seen[i] = 1
	vision_changed.emit()


func _step_toward(c: Dictionary, toward: Vector2, travel: float) -> Vector2:
	if has_terrain():
		return _walk_toward(c, toward, travel, "")
	var start := to_m(c["pos"])
	var goal := to_m(toward)
	var dir := (goal - start).normalized()
	var t := travel
	while t > 0.05:
		var dest := from_m(start + dir * t)
		if spot_free(dest, c["id"]):
			return dest
		for ang in [0.5, -0.5, 1.0, -1.0]:
			var alt := from_m(start + dir.rotated(ang) * t)
			if spot_free(alt, c["id"]) and dist_m(alt, toward) < dist_m(c["pos"], toward):
				return alt
		t -= 0.5
	return c["pos"]


## Ponto livre em volta do alvo, dentro do alcance, que dê para alcançar andando.
func _approach(c: Dictionary, toward: Vector2, reach: float, speed: float) -> Vector2:
	if has_terrain():
		return _approach_terrain(c, toward, reach, speed)
	var start := to_m(c["pos"])
	var goal := to_m(toward)
	var ring := maxf(MIN_GAP_M + 0.05, reach - 0.1)
	var best := Vector2(-1, -1)
	var best_d := INF
	for i in 24:
		var p := goal + Vector2.RIGHT.rotated(TAU * i / 24.0) * ring
		var d := start.distance_to(p)
		if d <= speed and d < best_d:
			var n := from_m(p)
			if spot_free(n, c["id"]):
				best = n
				best_d = d
	if best.x >= 0.0:
		return best
	return _step_toward(c, toward, minf(speed, start.distance_to(goal) - reach + 0.2))


## Dá para chegar ao alcance corpo a corpo de t neste turno?
func _reach_test(n: Dictionary, t: Dictionary, reach: float, speed: float) -> bool:
	if not has_terrain():
		return dist_between(n, t) <= speed + reach
	if dist_between(n, t) <= reach + 0.05 and sees(n, t):
		return true
	if dist_between(n, t) > speed + reach + 0.05:
		return false
	var p := _approach_terrain(n, t["pos"], reach, speed)
	return dist_m(p, t["pos"]) <= reach + 0.05 and line_clear(p, t["pos"])


## Lugar de onde dá para atirar em t: à vista, dentro do alcance e alcançável neste turno.
## Prefere não ficar colado num inimigo (desvantagem) e andar pouco.
func _find_shot(n: Dictionary, t: Dictionary, speed: float, max_range: float) -> Vector2:
	var field := terrain.cost_field(to_m(n["pos"]), speed, blocked_cells_for(n))
	var goal := to_m(t["pos"])
	var best: Vector2 = n["pos"]
	var best_s := INF
	for cell in field:
		var p := TerrainMap.center(cell)
		if p.distance_to(goal) > max_range or not terrain.walkable_m(p) or not terrain.line_clear(p, goal):
			continue
		var np := from_m(p)
		if not spot_free(np, n["id"]):
			continue
		var s: float = float(field[cell])
		for o in all_combatants():
			if hostile(n, o) and is_alive(o) and dist_m(np, o["pos"]) <= 1.6:
				s += 20.0
		if s < best_s:
			best_s = s
			best = np
	if best == n["pos"]:
		return _walk_toward(n, t["pos"], speed, t["id"])
	return best


## Com terreno: anda pelo caminho até onde der (travel em metros de custo) e para num lugar livre.
func _walk_toward(c: Dictionary, toward: Vector2, travel: float, except_id: String) -> Vector2:
	var goal := toward
	if not walkable(goal):
		var gc := terrain.nearest_passable(to_m(goal), 4)
		if gc.x < 0:
			return c["pos"]
		goal = from_m(TerrainMap.center(gc))
	var res := terrain.find_path(to_m(c["pos"]), to_m(goal), blocked_cells_for(c, except_id))
	if res.is_empty():
		return c["pos"]
	var cut := terrain.truncate(res["points"], travel)
	var probe := TerrainMap.samples(cut, 0.25)
	for i in range(probe.size() - 1, -1, -1):
		var p := from_m(probe[i])
		if spot_free(p, c["id"]) and dist_m(p, toward) < dist_m(c["pos"], toward):
			return p
	return c["pos"]


## Com terreno: o lugar mais barato de alcançar, dentro do alcance do alvo e com o alvo à vista.
## Se não der para chegar neste turno, anda o que puder pelo caminho.
func _approach_terrain(c: Dictionary, toward: Vector2, reach: float, speed: float) -> Vector2:
	var except := ""
	for o in all_combatants():
		if o["pos"] == toward:
			except = o["id"]
	var start := to_m(c["pos"])
	var goal := to_m(toward)
	if start.distance_to(goal) <= reach + 0.05 and terrain.line_clear(start, goal):
		return c["pos"]
	var field := terrain.cost_field(start, speed + 1.5, blocked_cells_for(c, except))
	var best := Vector2(-1, -1)
	var best_cost := INF
	var radii: Array = [maxf(MIN_GAP_M + 0.05, reach - 0.1)]
	if reach > 2.0:
		radii.append(MIN_GAP_M + 0.2)
	for ring in radii:
		for i in 24:
			var p: Vector2 = goal + Vector2.RIGHT.rotated(TAU * i / 24.0) * float(ring)
			var cell := TerrainMap.cell_of(p)
			if not field.has(cell) or not terrain.walkable_m(p):
				continue
			var cost: float = float(field[cell]) + terrain.segment_cost(TerrainMap.center(cell), p)
			if cost > speed + 0.05 or cost >= best_cost:
				continue
			if not terrain.line_clear(p, goal) or not terrain.walk_clear(TerrainMap.center(cell), p):
				continue
			var n := from_m(p)
			if spot_free(n, c["id"]):
				best = n
				best_cost = cost
	if best.x >= 0.0:
		return best
	return _walk_toward(c, toward, speed, except)


## Rodada em que o próximo turno de `id` começa (estritamente depois de agora).
func next_turn_round(id: String) -> int:
	var idx := order.find(id)
	if idx < 0:
		return round_num + 1
	if idx > turn_index:
		return round_num
	return round_num + 1


# ---------------------------------------------------------------- registros

func engine_log(text: String) -> void:
	engine_logged.emit(text)


func log_dice(actor_id: String, title: String, summary: String, detail: String, result: String) -> void:
	dice_logged.emit({
		"actor": actor_id, "title": title, "summary": summary,
		"detail": detail, "result": result, "round": round_num
	})


func _set_busy(v: bool) -> void:
	busy = v
	busy_changed.emit(v)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func select_target(id: String) -> void:
	selected_target = id
	target_selected.emit(id)


# ---------------------------------------------------------------- economia de ações

func _new_turn(c: Dictionary) -> void:
	turns[c["id"]] = {
		"action": true, "bonus": true, "object": true, "move_left": Rules.speed_m(c),
		"attacks_left": 0, "attacks_made": 0, "surge": 0, "moved_m": 0.0,
	}


## "" se o custo pode ser pago agora, senão o motivo.
func cost_error(c: Dictionary, cost: String) -> String:
	var t := turn_of(c)
	if Rules.incapacitated(c) and cost != "free":
		return "Incapacitado: não pode agir."
	match cost:
		"action":
			if not t.get("action", false) and int(t.get("surge", 0)) == 0:
				return "A ação deste turno já foi usada."
		"magic":
			if not t.get("action", false):
				return "A ação deste turno já foi usada (o Surto de Ação não serve para Magia)." if int(t.get("surge", 0)) > 0 else "A ação deste turno já foi usada."
		"bonus":
			if not t.get("bonus", false):
				return "A ação bônus deste turno já foi usada."
		"reaction":
			if c.get("reaction_used", false):
				return "A reação desta rodada já foi usada."
		"attack":
			if int(t.get("attacks_left", 0)) == 0 and not t.get("action", false) and int(t.get("surge", 0)) == 0:
				return "Sem ataques restantes neste turno."
		"free_nick":
			if not t.get("attack_action", false) or t.get("nick_used", false):
				return "Só durante a ação Atacar, uma vez por turno."
		"move":
			if float(t.get("move_left", 0.0)) <= 0.05:
				return "Sem deslocamento."
		"long":
			return "Leva tempo demais para fazer em combate."
	return ""


func spend_cost(c: Dictionary, cost: String) -> void:
	var t := turn_of(c)
	match cost:
		"action":
			if int(t.get("surge", 0)) > 0:
				t["surge"] = int(t["surge"]) - 1
			else:
				t["action"] = false
		"magic":
			t["action"] = false
		"bonus":
			t["bonus"] = false
		"reaction":
			c["reaction_used"] = true
		"attack":
			spend_attack(c)
		"free_nick":
			t["nick_used"] = true
	turn_resources_changed.emit()


## Gasta um dos ataques da ação Atacar (começa a ação se ainda não começou).
func spend_attack(c: Dictionary) -> bool:
	if not in_combat:
		return true
	var t := turn_of(c)
	if int(t.get("attacks_left", 0)) == 0:
		if cost_error(c, "action") != "":
			return false
		spend_cost(c, "action")
		var n: int = 1 + int(Rules.tv(c, "extra_attacks", 0))
		if c["kind"] == "monster":
			n = maxi(1, int(c.get("multiattack", 0)))
		t["attacks_left"] = n
		t["attack_action"] = true
	t["attacks_left"] = int(t["attacks_left"]) - 1
	t["attacks_made"] = int(t.get("attacks_made", 0)) + 1
	turn_resources_changed.emit()
	return true


## Resumo para a barra: [ação, bônus, reação, deslocamento, ataques restantes].
func turn_summary(c: Dictionary) -> Dictionary:
	var t := turn_of(c)
	return {"action": t.get("action", false) or int(t.get("surge", 0)) > 0, "bonus": t.get("bonus", false),
		"reaction": not c.get("reaction_used", false), "move_left": float(t.get("move_left", 0.0)),
		"speed": Rules.speed_m(c), "attacks_left": int(t.get("attacks_left", 0)), "surge": int(t.get("surge", 0))}


func available_actions(c: Dictionary) -> Array:
	return Actions.for_creature(self, c)


# ---------------------------------------------------------------- combate: turnos

## intro: narração de abertura. Vazio usa a da cena (fora da exploração, é a do capítulo).
func start_combat(intro := "") -> void:
	in_combat = true
	chapter_done = false
	round_num = 1
	xp_pool = 0
	var rolls: Array = []
	for c in all_combatants():
		if c.get("death", {}).get("dead", false):
			continue
		var bonus := Rules.initiative_bonus(c)
		var adv: bool = Rules.tv(c, "feral_instinct") or Rules.tv(c, "remarkable_athlete")
		var r := Rules.d20(bonus, adv, false, Rules.tv(c, "halfling_luck"))
		rolls.append({"id": c["id"], "init": r["total"], "dex": Rules.score(c, "dex")})
		# Metabolismo Sobrenatural do monge
		if Rules.res_left(c, "uncanny_metabolism") > 0 and (Rules.res_left(c, "focus_points") < int(c["resources"]["focus_points"]["max"]) or int(c["hp"]) < int(c["hp_max"])):
			Rules.spend(c, "uncanny_metabolism")
			c["resources"]["focus_points"]["left"] = c["resources"]["focus_points"]["max"]
			cb.heal(c, CharBuilder.class_level(c["choices"], "monk") + Rules.roll(str(Rules.tv(c, "martial_arts", "1d6")))["total"], c)
			engine_log("%s recupera o foco (Metabolismo Sobrenatural)." % c["name"])
	rolls.sort_custom(func(a, b): return a["init"] > b["init"] or (a["init"] == b["init"] and a["dex"] > b["dex"]))
	order = rolls.map(func(r): return r["id"])
	var names := PackedStringArray()
	for r in rolls:
		names.append("%s %d" % [by_id[r["id"]]["name"], r["init"]])
	log_dice("", "Iniciativa", ", ".join(names), "d20 + iniciativa de cada um (Destreza; Alerta soma a proficiência).", "neutral")
	engine_log("Ordem de iniciativa definida por d20 + bônus de iniciativa.")
	narration_added.emit(intro if intro != "" else str(scene_info.get("intro", "")))
	turn_index = 0
	_begin_turn()


func _begin_turn() -> void:
	var c := current()
	if c.is_empty():
		return
	_new_turn(c)
	cb.on_turn_start(c)
	turn_changed.emit(c["id"], round_num)
	turn_resources_changed.emit()
	# A 0 PV: teste contra a morte
	if c["kind"] == "pc" and int(c["hp"]) == 0 and not c["death"].get("dead", false):
		_set_busy(true)
		await _wait(0.6)
		cb.death_save(c)
		await _wait(0.9)
		if int(c["hp"]) == 0:
			end_turn()
			return
		_new_turn(c)
		turn_resources_changed.emit()
	if not is_alive(c) or c["side"] == "neutral" or Rules.incapacitated(c):
		var why := "está inconsciente" if int(c["hp"]) == 0 else ("está fora da luta" if c["side"] == "neutral" else "está incapacitado e perde a vez")
		engine_log("%s %s." % [c["name"], why])
		_set_busy(true)
		await _wait(0.9)
		end_turn()
		return
	if c["side"] == "party":
		_set_busy(false)
		Master.on_turn_started(c)
	else:
		_set_busy(true)
		await _wait(0.9)
		await _npc_act(c)
		_check_end()
		if in_combat:
			await _wait(0.6)
			end_turn()


func end_turn() -> void:
	if not in_combat:
		return
	var c := current()
	if not c.is_empty():
		cb.on_turn_end(c)
	clear_check()
	var n := order.size()
	for i in n:
		turn_index = (turn_index + 1) % n
		if turn_index == 0:
			round_num += 1
		var nx := current()
		if not nx.is_empty() and not nx.get("death", {}).get("dead", false) and (nx["side"] == "party" or (is_alive(nx) and nx["side"] != "neutral")):
			break
	_begin_turn()


## Depois de uma ação do jogador: encerra sozinho se não sobrou nada útil.
func _after_party_action() -> void:
	_set_busy(false)
	turn_resources_changed.emit()
	if not in_combat or not is_party_turn():
		return
	var c := current()
	var t := turn_of(c)
	var nothing_left: bool = not t.get("action", false) and int(t.get("surge", 0)) == 0 and int(t.get("attacks_left", 0)) == 0 and float(t.get("move_left", 0.0)) <= 0.05
	if nothing_left and t.get("bonus", false):
		nothing_left = not Actions.for_creature(self, c).any(func(a): return a["cost"] == "bonus" and a["available"])
	if nothing_left:
		await _wait(1.0)
		if is_party_turn() and not busy and current() == c:
			end_turn()


func _check_end() -> void:
	if not in_combat:
		return
	if not enemies.any(func(e): return is_alive(e) and is_foe(e)):
		in_combat = false
		_cleanup_after_combat()
		Master.react("victory", {}, true)
		_award_xp()
		order.clear()
		turn_index = 0
		# Na exploração, derrubar um grupo só libera o caminho: o capítulo fecha ao achar a saída.
		if ex.has_exploration():
			narration_added.emit("O caminho fica livre." if ex.groups_left() > 0 else "Nada mais se move por aqui. Resta achar a saída.")
			combat_ended.emit(true)
			pois_changed.emit()
			return
		clear_chapter()
	elif party.all(func(p): return not is_alive(p)):
		in_combat = false
		narration_added.emit(scene_info.get("defeat", ""))
		Master.react("defeat", {}, true)
		combat_ended.emit(false)


func _cleanup_after_combat() -> void:
	for c in all_combatants():
		c["effects"] = c["effects"].filter(func(e): return e.get("expire", {}).is_empty() or int(e["expire"]["round"]) - round_num > 100)
		cb.remove_effect(c, "rage")
		cb.remove_effect(c, "dodge")
		c["reaction_used"] = false
		state_changed.emit(c["id"])
	turns.clear()


func _award_xp() -> void:
	var alive: Array = party.filter(func(p): return not p.get("death", {}).get("dead", false))
	if alive.is_empty() or xp_pool <= 0:
		return
	var each := xp_pool / alive.size()
	engine_log("O grupo ganha %d XP (%d para cada)." % [xp_pool, each])
	for p in alive:
		var before := Srd.level_for_xp(int(p.get("xp", 0)))
		p["xp"] = int(p.get("xp", 0)) + each
		if Srd.level_for_xp(int(p["xp"])) > before or Srd.level_for_xp(int(p["xp"])) > int(p["level"]):
			level_up_available.emit(p["id"])
			engine_log("%s pode subir de nível." % p["name"])
	xp_pool = 0
	save_party()


func can_level_up(c: Dictionary) -> bool:
	return int(c.get("level", 1)) < 20 and Srd.level_for_xp(int(c.get("xp", 0))) > int(c["level"])


# ---------------------------------------------------------------- ações do jogador

## Ponto único de entrada da interface. act_id vem de available_actions().
func perform(actor_id: String, act_id: String, target_ids: Array = [], point := Vector2(-1, -1), opts := {}) -> void:
	var a: Dictionary = by_id.get(actor_id, {})
	if a.is_empty() or busy:
		return
	if in_combat and not is_my_turn(a):
		return
	var act: Dictionary = {}
	for x in Actions.for_creature(self, a):
		if x["id"] == act_id:
			act = x
			break
	if act.is_empty():
		engine_log("Ação desconhecida: %s." % act_id)
		return
	if not act["available"]:
		engine_log("Recusado: %s" % act["why"])
		return
	Master.notice_activity()
	_set_busy(true)
	match str(act["kind"]):
		"attack":
			await _perform_attack(a, act, target_ids)
		"spell":
			var slot: int = int(opts.get("slot", act.get("slot", 0)))
			await cb.cast(a, str(act["ref"]), slot, target_ids, point, opts)
		"feature":
			var fo: Dictionary = act.get("opts", {}).duplicate()
			fo.merge(opts, true)
			await cb.use_feature(a, str(act["ref"]), target_ids, point, fo)
	_check_end()
	if in_combat:
		_after_party_action()
	else:
		_set_busy(false)


func _perform_attack(a: Dictionary, act: Dictionary, target_ids: Array) -> void:
	if target_ids.is_empty():
		return
	var t: Dictionary = by_id.get(target_ids[0], {})
	if t.is_empty() or not is_alive(t):
		engine_log("Recusado: alvo inválido.")
		return
	var atk: Dictionary = act["ref"]
	var err := cb.attack_range_error(a, atk, t)
	if err != "":
		engine_log("Recusado: " + err)
		return
	if atk.get("offhand", false):
		spend_cost(a, str(act["cost"]))
	elif not spend_attack(a):
		return
	fx_requested.emit(a["id"], _fx_for_attack(atk), [t["id"]])
	await _wait(ArtStore.fx_duration(ArtStore.template_for(a["id"], _fx_for_attack(atk))) * 0.85)
	if Rules.has_condition(t, "surrendered") or t["side"] == "neutral":
		t["side"] = "enemy"
		cb.remove_condition(t, "surrendered")
		engine_log("%s foi atacado depois de se render e volta a lutar." % t["name"])
	cb.attack(a, atk, t)
	if atk.get("light", false) and not atk.get("offhand", false) and not atk.get("ranged", false):
		turn_of(a)["light_attacked"] = atk["weapon_id"]


func _fx_for_attack(atk: Dictionary) -> Dictionary:
	return {"id": str(atk.get("id", "")), "name": atk.get("name", ""), "kind": "attack",
		"target": "single", "dtype": atk.get("dtype", ""), "range": "ranged" if atk.get("ranged", false) else "melee"}


## Compatibilidade: a interface antiga chamava use_ability com o dicionário da atividade.
func use_ability(actor_id: String, ability: Dictionary, target_ids: Array, center := Vector2(-1, -1)) -> void:
	await perform(actor_id, str(ability.get("id", "")), target_ids, center, ability.get("opts_extra", {}))


func can_act() -> bool:
	return is_party_turn() and not busy


func why_not(ab: Dictionary) -> String:
	return "" if ab.get("available", true) else str(ab.get("why", ""))


func move_slot_spent() -> bool:
	return move_left <= 0.05


func defend(actor_id: String) -> void:
	await perform(actor_id, "std:dodge")


# ---------------------------------------------------------------- movimento

## Move o personagem da vez. Retorna "" se aceitou ou o motivo da recusa.
## O movimento em si (e ataques de oportunidade) acontece em seguida, sem bloquear a interface.
func move_token(actor_id: String, dest: Vector2) -> String:
	if busy or not is_party_turn() or current()["id"] != actor_id:
		return "Não é a sua vez."
	var c: Dictionary = by_id[actor_id]
	if Rules.speed_m(c) <= 0.0:
		return "Deslocamento 0 (%s)." % ("agarrado" if Rules.has_condition(c, "grappled") else "impedido")
	dest = settle(dest)
	if not walkable(dest):
		return "Ali não dá para pisar."
	if not spot_free(dest, actor_id):
		return "Esse lugar está ocupado."
	var plan := plan_path(c, dest)
	if plan.is_empty():
		return "Não há caminho até lá."
	var d: float = float(plan["cost"])
	var cost := d * (2.0 if Rules.has_condition(c, "prone") else 1.0)
	var t := turn_of(c)
	var left := float(t.get("move_left", 0.0))
	if cost > left + 0.05:
		var why := " rastejando (custa o dobro)" if Rules.has_condition(c, "prone") else ""
		if d > float(plan["length"]) + 0.1:
			why += " pelo caminho, com terreno difícil contando em dobro"
		elif float(plan["length"]) > dist_m(c["pos"], dest) + 0.3:
			why += " contornando o que está no caminho"
		return "Longe demais: %s%s; você ainda pode andar %s." % [fmt_m(d), why, fmt_m(left)]
	Master.notice_activity()
	t["move_left"] = maxf(0.0, left - cost)
	t["moved_m"] = float(t.get("moved_m", 0.0)) + float(plan["length"])
	_do_move(c, dest, true, plan["points"])
	return ""


## Executa o movimento com ataques de oportunidade de quem perde o alcance.
func _do_move(c: Dictionary, dest: Vector2, by_player: bool, route := PackedVector2Array()) -> void:
	if by_player:
		_set_busy(true)
	var start: Vector2 = c["pos"]
	if route.size() < 2 and has_terrain():
		var plan := plan_path(c, dest)
		route = plan["points"] if not plan.is_empty() else PackedVector2Array([start, dest])
	if route.size() < 2:
		route = PackedVector2Array([start, dest])
	if not Rules.has_effect(c, "disengage"):
		for h in all_combatants():
			if not hostile(h, c) or not is_alive(h) or Rules.incapacitated(h) or h.get("reaction_used", false) or Rules.eff_any(h, "no_reactions") or Rules.eff_any(h, "no_opportunity"):
				continue
			if h["kind"] == "pc" and not settings.get("auto_reactions", true):
				continue
			var melee := _best_melee(h)
			if melee.is_empty():
				continue
			var reach: float = float(melee.get("reach_m", 1.5)) + 0.05
			if _leaves_reach(route, h["pos"], reach):
				h["reaction_used"] = true
				engine_log("%s sai do alcance de %s: ataque de oportunidade!" % [c["name"], h["name"]])
				fx_requested.emit(h["id"], _fx_for_attack(melee), [c["id"]])
				await _wait(0.5)
				cb.attack(h, melee, c)
				await _wait(0.4)
				if not is_alive(c) or Rules.incapacitated(c):
					engine_log("%s cai antes de terminar o movimento." % c["name"])
					_check_end()
					if by_player:
						_after_party_action()
					return
	var dur := _animate_move(c, dest, route)
	var walked := 0.0
	for i in range(1, route.size()):
		walked += dist_m(route[i - 1], route[i])
	engine_log("%s andou %s." % [c["name"], fmt_m(walked)])
	if c["side"] == "party":
		update_vision()
	await _wait(dur)
	_readied_reactions(c)
	turn_resources_changed.emit()
	if by_player:
		_after_party_action()


## Ataques preparados (ação Preparar) de quem vê um inimigo entrar no alcance.
func _readied_reactions(mover: Dictionary) -> void:
	for h in all_combatants():
		if not h.get("readied", false) or not hostile(h, mover) or h.get("reaction_used", false) or not is_alive(h):
			continue
		var melee := _best_melee(h)
		if not melee.is_empty() and dist_between(h, mover) <= float(melee.get("reach_m", 1.5)) + 0.05:
			h["readied"] = false
			h["reaction_used"] = true
			engine_log("%s dispara o ataque preparado contra %s." % [h["name"], mover["name"]])
			cb.attack(h, melee, mover)


## O trajeto sai do alcance de quem está em `hp`? (Passar ao lado e seguir também provoca.)
func _leaves_reach(route: PackedVector2Array, hp: Vector2, reach: float) -> bool:
	var pts := PackedVector2Array()
	for p in route:
		pts.append(to_m(p))
	var center := to_m(hp)
	var was_in := pts[0].distance_to(center) <= reach
	for p2 in TerrainMap.samples(pts, 0.25):
		var inside := p2.distance_to(center) <= reach
		if was_in and not inside:
			return true
		was_in = inside
	return false


func _best_melee(c: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var atks: Array = c.get("form", {}).get("attacks", []) if not c.get("form", {}).is_empty() else c.get("attacks", [])
	for a in atks:
		if a.get("ranged", false):
			continue
		if best.is_empty() or Rules.average(str(a.get("damage", "1"))) > Rules.average(str(best.get("damage", "1"))):
			best = a
	return best


func _animate_move(c: Dictionary, dest: Vector2, route := PackedVector2Array()) -> float:
	var from: Vector2 = c["pos"]
	if route.size() < 2 and has_terrain():
		var plan := plan_path(c, dest)
		if not plan.is_empty():
			route = plan["points"]
	var length := dist_m(from, dest)
	if route.size() > 2:
		length = 0.0
		for i in range(1, route.size()):
			length += dist_m(route[i - 1], route[i])
		move_paths[c["id"]] = route
	else:
		move_paths.erase(c["id"])
	var duration := 0.2 + length * 0.045
	c["pos"] = dest
	token_moved.emit(c["id"], from, dest, duration)
	state_changed.emit(c["id"])
	return duration


func teleport(c: Dictionary, dest: Vector2) -> void:
	var from: Vector2 = c["pos"]
	c["pos"] = dest
	token_moved.emit(c["id"], from, dest, 0.15)
	state_changed.emit(c["id"])
	engine_log("%s se teleporta." % c["name"])


## Empurra `t` para longe de `src` (maestria Empurrar, Onda Trovejante...).
func push(t: Dictionary, src: Dictionary, meters: float) -> void:
	var dir := (to_m(t["pos"]) - to_m(src["pos"])).normalized()
	# Parede no meio: empurra só até onde dá.
	var dist := meters
	while dist > 0.25:
		var dest := from_m(to_m(t["pos"]) + dir * dist)
		dest = Vector2(clampf(dest.x, 0.03, 0.97), clampf(dest.y, 0.04, 0.96))
		if spot_free(dest, t["id"]) and terrain.walk_clear(to_m(t["pos"]), to_m(dest)):
			_animate_move(t, dest, PackedVector2Array([t["pos"], dest]))
			return
		dist -= 0.5


# ---------------------------------------------------------------- NPCs

func _npc_act(n: Dictionary) -> void:
	if Rules.has_condition(n, "prone") and Rules.speed_m(n) > 0:
		cb.remove_condition(n, "prone")
		turn_of(n)["move_left"] = float(turn_of(n)["move_left"]) - Rules.speed_m(n) / 2.0
		engine_log("%s se levanta." % n["name"])
	var pool: Array = all_combatants().filter(func(c): return is_alive(c) and hostile(n, c) and not (Rules.has_condition(c, "invisible") and c.get("conditions", []).any(func(cd): return cd.get("hidden", false))))
	if pool.is_empty():
		engine_log("%s não encontra alvo." % n["name"])
		return
	if Rules.has_condition(n, "frightened"):
		engine_log("%s está amedrontado e não avança." % n["name"])
	var speed := float(turn_of(n).get("move_left", Rules.speed_m(n)))
	# 1) Habilidade em área carregada (ex.: sopro) se pegar alguém
	for act in n.get("monster_actions", []):
		if act.has("save") and act.has("area") and act.get("charged", true) and int(act.get("uses_left", 1)) > 0:
			var tgt: Dictionary = pool[0]
			var area_m := Rules.m(float(act["area"]["size_ft"]))
			pool.sort_custom(func(x, y): return dist_between(n, x) < dist_between(n, y))
			tgt = pool[0]
			if dist_between(n, tgt) <= area_m + 0.5 and sees(n, tgt):
				await _monster_area(n, act, tgt)
				return
	# 2) Ataques: corpo a corpo se tiver, senão à distância
	var melee := _best_melee(n)
	var ranged: Dictionary = {}
	for a in n.get("attacks", []):
		if a.get("ranged", false) or a.get("range_m", []).size() == 2:
			ranged = a
	var reach: float = float(melee.get("reach_m", 1.5)) if not melee.is_empty() else 0.0
	var reachable := pool.filter(func(c): return _reach_test(n, c, reach, speed))
	var t: Dictionary
	var use_ranged := false
	if not melee.is_empty() and not reachable.is_empty() and not Rules.has_condition(n, "frightened"):
		reachable.sort_custom(func(x, y): return int(x["hp"]) < int(y["hp"]))
		t = reachable[0]
		engine_log("%s mira %s (alcançável e com menos PV)." % [n["name"], t["name"]])
	elif not ranged.is_empty():
		pool.sort_custom(func(x, y): return int(x["hp"]) < int(y["hp"]))
		t = pool[0]
		# Com terreno, prefere quem está à vista; quem está atrás de parede fica para depois.
		var in_sight := pool.filter(func(c): return cover_between(n, c) < TerrainMap.COVER_TOTAL)
		if not in_sight.is_empty():
			t = in_sight[0]
		use_ranged = true
	else:
		pool.sort_custom(func(x, y): return dist_between(n, x) < dist_between(n, y))
		t = pool[0]
		engine_log("%s avança na direção de %s." % [n["name"], t["name"]])
	if use_ranged:
		# Atirador colado em alguém: se puder, desengaja e se afasta antes de atirar
		var adjacent := pool.any(func(c): return dist_between(n, c) <= 1.55)
		if adjacent and n.get("bonus_actions", []).any(func(b): return str(b.get("text", "")).contains("Disengage")):
			cb.add_effect(n, {"id": "disengage", "name": "Fuga Ágil", "mods": {}, "ends": "end_source"}, n)
			engine_log("%s usa Fuga Ágil para se desengajar." % n["name"])
			var away: Vector2 = n["pos"] + (n["pos"] - t["pos"]).normalized() * 0.12
			var dest := _step_toward(n, away, minf(speed, 6.0))
			if dest != n["pos"]:
				await _do_move(n, dest, false)
		# Sem linha de visão: procura de onde atirar.
		if has_terrain() and is_alive(n) and cover_between(n, t) >= TerrainMap.COVER_TOTAL:
			var rr: Array = ranged.get("range_m", [])
			var long_r: float = float(rr[1]) if rr.size() == 2 else float(ranged.get("range_single", 36.0))
			var spot := _find_shot(n, t, float(turn_of(n).get("move_left", speed)), long_r)
			if spot != n["pos"]:
				await _do_move(n, spot, false)
				if not is_alive(n):
					return
	elif not melee.is_empty() and dist_between(n, t) > reach and not Rules.has_condition(n, "frightened"):
		var dest2 := _approach(n, t["pos"], reach, speed)
		if dest2 != n["pos"]:
			await _do_move(n, dest2, false)
			if not is_alive(n):
				return
	var n_attacks: int = maxi(1, int(n.get("multiattack", 0)))
	for i in n_attacks:
		if not is_alive(n) or Rules.incapacitated(n):
			return
		if not is_alive(t) or t.get("death", {}).get("dead", false):
			var near: Array = all_combatants().filter(func(c): return is_alive(c) and hostile(n, c) and dist_between(n, c) <= (reach if not use_ranged else 999.0) + 0.05)
			if near.is_empty():
				return
			t = near[0]
		var atk: Dictionary = ranged if use_ranged or melee.is_empty() or dist_between(n, t) > reach + 0.05 else melee
		if atk.is_empty() or cb.attack_range_error(n, atk, t) != "":
			engine_log("%s não chegou ao alcance de %s (%s)." % [n["name"], t["name"], fmt_m(dist_between(n, t))])
			return
		fx_requested.emit(n["id"], _fx_for_attack(atk), [t["id"]])
		await _wait(ArtStore.fx_duration(ArtStore.template_for(n["id"], _fx_for_attack(atk))) * 0.85)
		cb.attack(n, atk, t)
		await _wait(0.35)


func _monster_area(n: Dictionary, act: Dictionary, tgt: Dictionary) -> void:
	var shape: String = str(act["area"]["shape"])
	var origin_self: bool = shape in ["cone", "line", "emanation"]
	engine_log("%s usa %s!" % [n["name"], act["name"]])
	fx_requested.emit(n["id"], {"id": act["id"], "name": act["name"], "kind": "spell", "target": "area", "dtype": act.get("dtype", ""), "area_m": Rules.m(float(act["area"]["size_ft"]))}, [tgt["id"]])
	await _wait(0.7)
	if act.has("recharge"):
		act["charged"] = false
	if act.has("uses_left"):
		act["uses_left"] = int(act["uses_left"]) - 1
	var dmg: int = Rules.roll(str(act.get("damage", "0")))["total"] if act.has("damage") else 0
	for c in cb.in_area(n, shape, float(act["area"]["size_ft"]), tgt["pos"], origin_self):
		if not hostile(n, c):
			continue
		var r := cb.saving_throw(c, str(act["save"]["ability"]), int(act["save"]["dc"]), {"source": n, "cover": cover_from_point(n["pos"] if origin_self else tgt["pos"], c)})
		var evasion: bool = Rules.tv(c, "evasion") and str(act["save"]["ability"]) == "dex"
		var amount := 0
		if dmg > 0:
			if r["success"]:
				amount = 0 if evasion or not act.get("half_on_save", false) else dmg / 2
			else:
				amount = dmg / 2 if evasion else dmg
			if amount > 0:
				cb.deal_damage(c, [{"amount": amount, "dtype": str(act.get("dtype", ""))}], n)
		if not r["success"] and act.has("condition"):
			cb.add_condition(c, str(act["condition"]), n, {"rounds": 10})


# ---------------------------------------------------------------- texto livre, testes e consequências

func player_free_text(actor_id: String, text: String) -> void:
	if busy:
		return
	if in_combat and not is_party_turn():
		return
	player_spoke.emit(actor_id, text)
	Master.interpret(by_id[actor_id], text)


func request_check(check: Dictionary) -> void:
	pending_check = check
	check_requested.emit(check)


func clear_check() -> void:
	if not pending_check.is_empty():
		pending_check = {}
		check_cleared.emit()


## Converte o nome em português da perícia (ex.: "Persuasão") no id do SRD.
func skill_id(name_or_id: String) -> String:
	if name_or_id in Srd.skills():
		return name_or_id
	var low := name_or_id.to_lower()
	for sk in Srd.skills():
		if Srd.skill_name(sk).to_lower() == low:
			return sk
	for ab in Rules.ABILITIES:
		if Srd.ability_name(ab).to_lower() == low:
			return ab
	return "persuasion"


func skill_bonus(a: Dictionary, skill: String, _attr := "") -> Array:
	var sk := skill_id(skill)
	if sk in Srd.skills():
		return [Rules.skill_bonus(a, sk), "de perícia" if Rules.skill_prof(a, sk) > 0 else "de atributo"]
	return [Rules.check_bonus(a, sk), "de atributo"]


func resolve_check() -> void:
	if pending_check.is_empty() or busy:
		return
	var chk := pending_check
	var a: Dictionary = by_id[chk["actor"]]
	var uses_action: bool = chk.get("uses_action", true)
	if in_combat and uses_action and cost_error(a, "action") != "":
		engine_log("Recusado: a ação deste turno já foi usada.")
		return
	var target_name := ""
	if chk.get("target", "") != "":
		target_name = " com %s" % by_id[chk["target"]]["name"]
	var r := cb.ability_check(a, skill_id(str(chk["skill"])), int(chk["dc"]), {"title_suffix": target_name, "dc_reason": chk.get("dc_reason", "")})
	floating_text.emit(a["id"], "sucesso" if r["success"] else "falhou", "heal" if r["success"] else "miss")
	clear_check()
	if in_combat and uses_action:
		spend_cost(a, "action")
	Master.on_check_result(a, chk, r["success"], r["nat"], r["margin"])
	apply_effects(chk.get("on_success", []) if r["success"] else chk.get("on_fail", []), a, chk.get("target", ""))
	_check_end()
	if in_combat and is_party_turn():
		_after_party_action()


## Aplica as consequências propostas pelo mestre. Só efeitos conhecidos e válidos passam.
func apply_effects(effects: Array, actor: Dictionary, target_id: String) -> void:
	var t: Dictionary = by_id.get(target_id, {})
	for e in effects:
		var kind: String = e.get("type", "")
		if not kind in EFFECTS:
			engine_log("Efeito desconhecido recusado: %s." % kind)
			continue
		match kind:
			"side":
				if t.is_empty() or not is_alive(t) or t["side"] == "party":
					engine_log("Recusado: mudança de lado sem alvo válido.")
					continue
				var v: String = e.get("value", "neutral")
				t["side"] = v
				cb.remove_condition(t, "frightened")
				if v == "neutral":
					cb.add_condition(t, "surrendered", actor)
					floating_text.emit(t["id"], "rendido", "heal")
				elif v == "ally":
					cb.remove_condition(t, "surrendered")
					floating_text.emit(t["id"], "aliado!", "heal")
				engine_log("%s agora está %s." % [t["name"], side_word(t)])
				state_changed.emit(t["id"])
			"condition":
				var who: Dictionary = actor if e.get("who", "target") == "actor" else t
				var cid: String = OLD_CONDITION_IDS.get(str(e.get("id", "")), str(e.get("id", "")))
				if who.is_empty() or not conditions.has(cid):
					engine_log("Recusado: condição inválida (%s)." % cid)
					continue
				var opts := {"rounds": int(e.get("rounds", 1))}
				if cid == "invisible":
					opts["hidden"] = true
				cb.add_condition(who, cid, actor, opts)
				floating_text.emit(who["id"], conditions[cid]["name"].to_lower(), "miss")
				engine_log("%s: %s por %d rodada(s)." % [who["name"], conditions[cid]["name"], int(e.get("rounds", 1))])
			"flee":
				if t.is_empty() or not is_alive(t):
					continue
				t["side"] = "neutral"
				cb.add_condition(t, "surrendered", actor)
				var away: Vector2 = t["pos"] + (t["pos"] - actor["pos"]).normalized() * 0.5
				away = Vector2(clampf(away.x, 0.04, 0.96), clampf(away.y, 0.05, 0.95))
				var dest := _step_toward(t, away, Rules.speed_m(t))
				if dest != t["pos"]:
					_animate_move(t, dest)
				floating_text.emit(t["id"], "fugiu", "miss")
				engine_log("%s foge e sai da luta." % t["name"])
			"reveal":
				narration_added.emit(str(e.get("text", "")))
				engine_log("Informação revelada ao grupo.")
			"bible_note":
				_bible_note(str(e.get("name", "")), str(e.get("text", "")))
			"taunt":
				Master.react(str(e.get("event", "")), actor, true)
			"damage":
				var who2: Dictionary = actor if e.get("who", "target") == "actor" else t
				if not who2.is_empty():
					var r := Rules.roll(str(e.get("dice", "1d6")))
					cb.deal_damage(who2, [{"amount": r["total"], "dtype": str(e.get("dtype", ""))}], actor)
			"heal":
				var who3: Dictionary = actor if e.get("who", "target") == "actor" else t
				if not who3.is_empty():
					cb.heal(who3, Rules.roll(str(e.get("dice", "1d6")))["total"], actor)
			"save":
				var who4: Dictionary = t if not t.is_empty() else actor
				var rr := cb.saving_throw(who4, str(e.get("ability", "dex")), int(e.get("dc", 12)), {})
				apply_effects(e.get("on_fail", []) if not rr["success"] else e.get("on_success", []), actor, who4["id"])


func _bible_note(entry_name: String, text: String) -> void:
	for sec in bible.keys():
		for entry in bible[sec]:
			if entry["name"] == entry_name:
				if not str(entry["known"]).contains(text):
					entry["known"] = str(entry["known"]) + " " + text
					engine_log("Diário atualizado: %s." % entry_name)
					bible_changed.emit()
				return


func free_roll(actor_id: String, sides: int) -> void:
	var r := Rules.d(sides)
	var who: String = by_id[actor_id]["name"] if by_id.has(actor_id) else "Mesa"
	log_dice(actor_id, "%s: rolagem livre" % who, "d%d: %d" % [sides, r], "Rolagem sem efeito no jogo.", "neutral")
	Master.notice_activity()


# ---------------------------------------------------------------- descansos (fora de combate)

func short_rest(dice_by_id: Dictionary) -> void:
	if in_combat:
		engine_log("Recusado: não dá para descansar em combate.")
		return
	for c in party:
		cb.short_rest(c, int(dice_by_id.get(c["id"], 0)))
	save_party()


func long_rest() -> void:
	if in_combat:
		engine_log("Recusado: não dá para descansar em combate.")
		return
	if not can_long_rest():
		engine_log("Recusado: esta aventura só permite descanso longo nos pontos de descanso.")
		return
	for c in party:
		cb.long_rest(c)
	save_party()
	narration_added.emit("O grupo descansa por oito horas.")


func buy_upgrade(_actor_id: String, _upgrade: Dictionary) -> bool:
	engine_log("Upgrades foram substituídos pela subida de nível do SRD.")
	return false
