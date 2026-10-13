class_name RoomBuilder
extends RefCounted
## Regras da tela de criação de sala: temas, jogador padrão, compra de pontos, preenchimento
## automático da ficha e validação. Nada aqui mexe na interface nem no estado da mesa.
##
## Configuração da sala (cfg):
##   name, theme, story, level (1 a MAX_LEVEL), budget (pontos de atributo), difficulty,
##   master_level, chapters, players[] (escolhas no mesmo formato do CharacterCreator).

const MAX_PLAYERS := 8
const DEFAULT_BUDGET := 27
const MIN_BUDGET := 10
const MAX_BUDGET := 54
const MAX_LEVEL := 5
const MIN_STORY := 40
const THEME_DIR := "res://data/themes/"
const DIFFICULTIES := [["low", "Leve"], ["moderate", "Moderada"], ["high", "Difícil"]]

## Ideias de história para quem não quer começar do zero. A IA usa o texto como premissa.
const SEEDS := {
	"mistico": [
		"Uma vila costeira acorda sem ouvir o mar. As marés pararam e, nas noites sem lua, algo bate nas portas por dentro das casas. O grupo precisa descobrir quem fez um pacto e o que foi prometido em troca.",
		"Sob uma abadia abandonada existe uma biblioteca que ninguém consegue mapear. Quem entra volta com um nome a mais na memória. O grupo é contratado para trazer de volta um erudito que ainda não saiu.",
		"Uma caravana de peregrinos some numa estrada que todos juram ser reta e curta. Os sobreviventes falam de uma cantiga que muda a direção dos passos. Alguém no grupo reconhece a melodia.",
	],
	"fantasia": [
		"O rei prometeu a mão da filha a quem recuperar a coroa roubada por um bando de goblins. O que ninguém conta é que a coroa já foi devolvida duas vezes e sempre volta para a toca deles.",
		"Uma torre de mago surgiu em uma noite no meio do trigal. A porta está aberta, as luzes acesas e o dono ainda não apareceu. A vila quer saber se é presente ou armadilha.",
		"A estalagem Cinco Chaves recebe, toda semana, um hóspede que paga adiantado e nunca é visto saindo. Desta vez o quarto está vazio e a conta foi paga por um ano inteiro.",
	],
	"cyberpunk": [
		"Uma corporação perdeu o controle de um andar inteiro da torre depois de um apagão de quarenta segundos. Ela paga bem para o grupo entrar, buscar um servidor e não perguntar o que roda nele.",
		"Um netrunner famoso morreu ao vivo, mas sua conta continua postando. As mensagens trazem coordenadas de depósitos pela cidade. Alguém está seguindo o rastro do grupo.",
		"O bairro vai ser demolido em sete dias. Os moradores contratam o grupo para achar a prova de que a corporação comprou o terreno antes de causar o incêndio que o condenou.",
	],
	"realista": [
		"Um comboio de mercadores atravessa um desfiladeiro em plena guerra de sucessão. O grupo foi pago para escoltá-lo, mas metade da carga não consta no manifesto e há quem esteja disposto a matar por ela.",
		"Um vilarejo de fronteira acusa os vizinhos de roubar gado. O grupo é chamado para mediar e logo percebe que alguém dos dois lados está lucrando com o conflito.",
		"Depois de uma cheia, o corpo de um magistrado aparece preso nas raízes de uma figueira, longe de onde deveria estar. O grupo é pago para descobrir o que ele fazia ali antes que o povo escolha um culpado.",
	],
}
const SEEDS_ANY := [
	"Algo foi roubado de quem não podia perder, e o ladrão deixou um bilhete dizendo onde estará. Chegar lá é fácil. Sair, nem tanto.",
]


# ---------------------------------------------------------------- temas e ideias

## Todos os temas de data/themes/, em ordem alfabética.
static func themes() -> Array:
	var out: Array = []
	var dir := DirAccess.open(THEME_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() != "json":
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(THEME_DIR + f))
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("id"):
			out.append(parsed)
	out.sort_custom(func(a, b): return str(a.get("name", a["id"])) < str(b.get("name", b["id"])))
	return out


static func theme_by_id(id: String) -> Dictionary:
	for t in themes():
		if str(t["id"]) == id:
			return t
	return {}


static func seeds(theme_id: String) -> Array:
	return SEEDS.get(theme_id, SEEDS_ANY)


# ---------------------------------------------------------------- configuração

static func new_config() -> Dictionary:
	var list := themes()
	var tid := "fantasia"
	if not list.is_empty():
		tid = str(list[0]["id"])
		var cur := str(Game.theme.get("id", ""))
		for t in list:
			if str(t["id"]) == cur:
				tid = cur
	return {
		"name": "Nova mesa", "theme": tid, "story": "", "level": 1, "budget": DEFAULT_BUDGET,
		"difficulty": "moderate", "master_level": str(Master.level), "chapters": 3, "seed_i": 0,
		"level_mode": "xp", "rest_mode": "aventura", "player_count": 4, "players": [],
	}


static func config_errors(cfg: Dictionary) -> Array:
	var errs: Array = []
	if str(cfg.get("name", "")).strip_edges() == "":
		errs.append("Dê um nome à sala.")
	if theme_by_id(str(cfg.get("theme", ""))).is_empty():
		errs.append("Escolha um tema.")
	if str(cfg.get("story", "")).strip_edges().length() < MIN_STORY:
		errs.append("Escreva a história com pelo menos %d caracteres. A IA usa este texto para criar a aventura." % MIN_STORY)
	var n := int(cfg.get("player_count", 0))
	if n < 1 or n > MAX_PLAYERS:
		errs.append("A mesa tem de 1 a %d jogadores." % MAX_PLAYERS)
	return errs


## Acerta a lista de fichas para bater com a quantidade de jogadores da sala. Chamado ao entrar
## na etapa dos jogadores — que agora vem depois da aventura, para os personagens nascerem
## sabendo da lore.
static func ensure_players(cfg: Dictionary) -> void:
	var want := clampi(int(cfg.get("player_count", 1)), 1, MAX_PLAYERS)
	var list: Array = cfg.get("players", [])
	while list.size() > want:
		list.pop_back()
	while list.size() < want:
		var p := default_player(list.size(), int(cfg.get("level", 1)), int(cfg.get("budget", DEFAULT_BUDGET)))
		fit_player(p)
		list.append(p)
	cfg["players"] = list


static func slug(s: String) -> String:
	const MAP := {"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "é": "e", "ê": "e", "è": "e", "í": "i", "î": "i",
		"ó": "o", "ô": "o", "õ": "o", "ö": "o", "ú": "u", "ü": "u", "ç": "c"}
	var out := ""
	var last_us := true
	for ch in s.to_lower():
		var c: String = MAP.get(ch, ch)
		var code: int = c.unicode_at(0)
		var ok: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if ok:
			out += c
			last_us = false
		elif not last_us:
			out += "_"
			last_us = true
	out = out.strip_edges().trim_suffix("_")
	if out == "":
		out = "mesa"
	return out.left(24)


# ---------------------------------------------------------------- jogador

static func default_bonus(bid: String) -> Dictionary:
	var abs: Array = Srd.backgrounds[bid]["abilities"]
	return {abs[0]: 2, abs[1]: 1}


static func default_player(index: int, level: int, budget: int) -> Dictionary:
	var classes := Srd.list("class")
	var cid := "fighter" if "fighter" in classes else str(classes[0])
	var sps := Srd.list("species")
	var sid := "human" if "human" in sps else str(sps[0])
	var bgs := Srd.list("background")
	var bid := "soldier" if "soldier" in bgs else str(bgs[0])
	var base := {}
	for ab in Rules.ABILITIES:
		base[ab] = 8
	return {
		"name": "", "player": "Jogador %d" % (index + 1), "color": CharacterCreator.COLORS[index % CharacterCreator.COLORS.size()],
		"classes": [{"class_id": cid, "level": level, "subclass_id": ""}], "species_id": sid, "species_choice": {},
		"background_id": bid, "method": "point_buy", "point_budget": budget, "base_scores": base, "bg_bonus": default_bonus(bid),
		"skills": [], "expertise": [], "equipment_option": "A", "bg_equipment_option": "A",
		"cantrips": [], "spells": [], "options": {}, "feats": [], "hp_rolls": [],
		"profile": {"background": "", "traits": "", "bonds": "", "bio": ""}, "alignment": "",
	}


static func reset_class_picks(ch: Dictionary) -> void:
	ch["classes"][0]["subclass_id"] = ""
	ch["skills"] = []
	ch["expertise"] = []
	ch["cantrips"] = []
	ch["spells"] = []
	ch["options"] = {}
	ch["feats"] = []


static func set_level(ch: Dictionary, level: int) -> void:
	ch["classes"][0]["level"] = clampi(level, 1, MAX_LEVEL)
	reset_class_picks(ch)


## Depois de trocar o tema (ex.: realista só tem humanos), volta o que ficou proibido ao primeiro permitido.
static func fit_player(ch: Dictionary) -> void:
	var classes := Srd.list("class")
	var first: Dictionary = ch["classes"][0]
	if not str(first["class_id"]) in classes and not classes.is_empty():
		first["class_id"] = classes[0]
		reset_class_picks(ch)
	var sps := Srd.list("species")
	if not str(ch["species_id"]) in sps and not sps.is_empty():
		ch["species_id"] = sps[0]
		ch["species_choice"] = {}
	var bgs := Srd.list("background")
	if not str(ch["background_id"]) in bgs and not bgs.is_empty():
		ch["background_id"] = bgs[0]
		ch["bg_bonus"] = default_bonus(str(bgs[0]))
		ch["skills"] = []


# ---------------------------------------------------------------- pontos de atributo

static func cost_of(score: int) -> int:
	return int(Srd.tables["point_buy"].get(str(clampi(score, 8, 15)), 0))


static func point_cost(base: Dictionary) -> int:
	var total := 0
	for ab in base:
		total += cost_of(int(base[ab]))
	return total


static func points_left(ch: Dictionary) -> int:
	return int(ch.get("point_budget", DEFAULT_BUDGET)) - point_cost(ch["base_scores"])


## Pode subir (+1) ou descer (-1) este atributo respeitando 8..15 e o orçamento?
static func can_step(ch: Dictionary, ab: String, dir: int) -> bool:
	var v: int = int(ch["base_scores"].get(ab, 8))
	var nv := v + dir
	if nv < 8 or nv > 15:
		return false
	if dir > 0:
		return cost_of(nv) - cost_of(v) <= points_left(ch)
	return true


static func reset_scores(ch: Dictionary) -> void:
	ch["method"] = "point_buy"
	var base := {}
	for ab in Rules.ABILITIES:
		base[ab] = 8
	ch["base_scores"] = base


## Bônus do antecedente: opções [código, texto] como no criador de personagem.
static func bonus_options(bid: String) -> Array:
	var a3: Array = Srd.backgrounds[bid]["abilities"]
	var opts: Array = []
	for i in 3:
		for j in 3:
			if i != j:
				opts.append(["%s2_%s1" % [a3[i], a3[j]], "+2 %s, +1 %s" % [Srd.ability_abbr(a3[i]), Srd.ability_abbr(a3[j])]])
	opts.append(["all1", "+1 em %s, %s e %s" % [Srd.ability_abbr(a3[0]), Srd.ability_abbr(a3[1]), Srd.ability_abbr(a3[2])]])
	return opts


static func bonus_code(ch: Dictionary) -> String:
	var b: Dictionary = ch["bg_bonus"]
	var two := ""
	var one := ""
	for k in b:
		if int(b[k]) == 2:
			two = str(k)
		elif int(b[k]) == 1:
			one = str(k)
	if two != "" and one != "":
		return "%s2_%s1" % [two, one]
	return "all1"


static func apply_bonus(ch: Dictionary, code: String) -> void:
	var a3: Array = Srd.backgrounds[ch["background_id"]]["abilities"]
	if code == "all1":
		ch["bg_bonus"] = {a3[0]: 1, a3[1]: 1, a3[2]: 1}
	else:
		var parts := code.split("_")
		ch["bg_bonus"] = {parts[0].substr(0, 3): 2, parts[1].substr(0, 3): 1}


# ---------------------------------------------------------------- preenchimento automático

static func _def(d: Dictionary, key: String, value: Variant) -> void:
	if not d.has(key):
		d[key] = value


static func expertise_count(ch: Dictionary) -> int:
	var n := 0
	for k in ch["classes"]:
		var lv := int(k["level"])
		match str(k["class_id"]):
			"rogue":
				n += 2 + (2 if lv >= 6 else 0)
			"bard":
				n += (2 if lv >= 2 else 0) + (2 if lv >= 9 else 0)
			"ranger":
				n += (1 if lv >= 2 else 0) + (2 if lv >= 9 else 0)
			"wizard":
				n += 1 if lv >= 2 else 0
	return n


## Completa o que a ficha exige e o jogador não escolheu na tela de sala (perícias, magias,
## estilo de luta...). São padrões razoáveis; o botão "Ficha completa" permite ajustar tudo.
## Mantém as escolhas já feitas quando continuam válidas.
static func autofill(ch: Dictionary) -> void:
	var first: Dictionary = ch["classes"][0]
	var cid := str(first["class_id"])
	var lv := int(first["level"])
	var cls: Dictionary = Srd.classes[cid]
	var bg: Dictionary = Srd.backgrounds.get(str(ch["background_id"]), {})
	var o: Dictionary = ch["options"]

	if lv >= 3 and str(first.get("subclass_id", "")) == "":
		var subs: Array = cls.get("subclasses", [])
		if not subs.is_empty():
			first["subclass_id"] = str(subs[0]["id"])

	# Perícias da classe (as do antecedente já vêm de graça)
	var locked: Array = bg.get("skills", [])
	var skill_pool: Array = cls["skills"]["from"]
	var need := int(cls["skills"]["choose"])
	var picked: Array = []
	for s in ch.get("skills", []):
		if s in skill_pool and not s in locked and not s in picked and picked.size() < need:
			picked.append(s)
	for s in skill_pool:
		if picked.size() >= need:
			break
		if not s in picked and not s in locked:
			picked.append(s)
	ch["skills"] = picked

	var ex_n := expertise_count(ch)
	var ex: Array = []
	if ex_n > 0:
		var profs: Array = locked.duplicate()
		for s in picked:
			if not s in profs:
				profs.append(s)
		for s in ch.get("expertise", []):
			if s in profs and not s in ex and ex.size() < ex_n:
				ex.append(s)
		for s in profs:
			if ex.size() >= ex_n:
				break
			if not s in ex:
				ex.append(s)
	ch["expertise"] = ex

	var sc: Dictionary = ch["species_choice"]
	match str(ch["species_id"]):
		"dragonborn":
			_def(sc, "ancestry", "red")
		"elf":
			_def(sc, "lineage", "high")
			_def(sc, "keen_senses", "perception")
		"gnome":
			_def(sc, "lineage", "rock")
		"goliath":
			_def(sc, "ancestry", "stone")
		"tiefling":
			_def(sc, "lineage", "infernal")
		"human":
			_def(sc, "skillful", "perception")
			_def(o, "versatile_feat", "alert")

	match cid:
		"fighter":
			_def(o, "fighting_style", "defense")
		"paladin":
			if lv >= 2:
				_def(o, "fighting_style", "defense")
		"ranger":
			if lv >= 2:
				_def(o, "fighting_style", "archery")
			if lv >= 3:
				_def(o, "hunters_prey", "colossus_slayer")
		"cleric":
			_def(o, "divine_order", "protector")
		"druid":
			_def(o, "primal_order", "warden")
			if lv >= 2:
				_def(o, "beast_forms", ["wolf", "rat", "spider", "riding_horse"].filter(func(b): return Srd.monsters.has(b)))
			if lv >= 3 and str(first.get("subclass_id", "")) == "circle_of_the_land":
				_def(o, "land_type", "temperate")
		"sorcerer":
			if lv >= 2 and not o.has("metamagic"):
				var mm: Array = Srd.classes["sorcerer"]["options"]["metamagic"].map(func(x): return x["id"])
				o["metamagic"] = mm.slice(0, 2)
		"warlock":
			if not o.has("invocations"):
				var n_inv := Srd.class_value("warlock", lv, "eldritch_invocations")
				var inv: Array = []
				for x in Srd.classes["warlock"]["options"]["eldritch_invocation"]:
					if str(x["prerequisite"]) == "" and inv.size() < n_inv:
						inv.append(x["id"])
				o["invocations"] = inv

	if CharBuilder.CASTER.has(cid):
		_fill_spells(ch, cid, lv, o)


static func _fill_spells(ch: Dictionary, cid: String, lv: int, o: Dictionary) -> void:
	var n_cantrips := Srd.class_value(cid, lv, "cantrips")
	if (cid == "cleric" and str(o.get("divine_order", "")) == "thaumaturge") or (cid == "druid" and str(o.get("primal_order", "")) == "magician"):
		n_cantrips += 1
	var n_prep := Srd.class_value(cid, lv, "prepared_spells")
	var max_lvl := 0
	for l in range(1, 10):
		if Srd.class_value(cid, lv, "slot_%d" % l) > 0:
			max_lvl = l
	if cid == "warlock":
		max_lvl = Srd.class_value(cid, lv, "slot_level")
	var cants := Srd.spells_for_class(cid, 0)
	cants.sort_custom(func(a, b): return Srd.label("spell", a) < Srd.label("spell", b))
	var cp: Array = []
	for s in ch.get("cantrips", []):
		if s in cants and not s in cp and cp.size() < n_cantrips:
			cp.append(s)
	for s in cants:
		if cp.size() >= n_cantrips:
			break
		if not s in cp:
			cp.append(s)
	ch["cantrips"] = cp
	var always: Array = CharBuilder.build(ch).get("spellcasting", {}).get("always", [])
	var pool: Array = []
	for l in range(1, max_lvl + 1):
		pool += Srd.spells_for_class(cid, l).filter(func(x): return not x in always)
	pool.sort_custom(func(a, b): return _spell_key(a) < _spell_key(b))
	var sp: Array = []
	if max_lvl > 0:
		for s in ch.get("spells", []):
			if s in pool and not s in sp and sp.size() < n_prep:
				sp.append(s)
		for s in pool:
			if sp.size() >= n_prep:
				break
			if not s in sp:
				sp.append(s)
	ch["spells"] = sp


static func _spell_key(s: String) -> String:
	return "%d %s" % [int(Srd.spells[s]["level"]), Srd.label("spell", s)]


## Cópia pronta para o motor: ficha completa, sem pendências.
static func finalize_player(ch: Dictionary) -> Dictionary:
	var out: Dictionary = ch.duplicate(true)
	autofill(out)
	return out


static func player_errors(ch: Dictionary) -> Array:
	return CharBuilder.validate(finalize_player(ch))


## Ficha calculada (PV, CA...) para a prévia da tela.
static func preview(ch: Dictionary) -> Dictionary:
	return CharBuilder.build(finalize_player(ch))
