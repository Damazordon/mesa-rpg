class_name RulesTests
extends RefCounted
## Testes do motor de regras contra valores conhecidos do SRD 5.2.1.
## Uso: godot --headless --path . -- --rules-tests

static var fails := 0
static var passes := 0


static func check(name: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		passes += 1
	else:
		fails += 1
		print("FALHOU  %s: veio %s, esperado %s" % [name, str(got), str(want)])


static func pc(cls: String, lv: int, extra := {}) -> Dictionary:
	var ch := {
		"name": "Teste", "classes": [{"class_id": cls, "level": lv, "subclass_id": extra.get("sub", "")}],
		"species_id": extra.get("species", "human"), "background_id": extra.get("bg", "soldier"),
		"base_scores": extra.get("scores", {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}),
		"bg_bonus": extra.get("bonus", {"str": 2, "con": 1}), "skills": extra.get("skills", []),
		"equipment_option": extra.get("eq", "A"), "bg_equipment_option": "A",
		"options": extra.get("options", {}), "cantrips": extra.get("cantrips", []), "spells": extra.get("spells", []),
		"species_choice": extra.get("species_choice", {}),
	}
	if extra.has("classes"):
		ch["classes"] = extra["classes"]
	return CharBuilder.build(ch)


static func run() -> void:
	print("== testes de regra (SRD 5.2.1)")
	# Dados
	check("parse 2d6+3", Rules.parse("2d6+3"), {"dice": [[2, 6]], "mod": 3})
	check("parse 1d8 + 1d4 - 1", Rules.parse("1d8 + 1d4 - 1"), {"dice": [[1, 8], [1, 4]], "mod": -1})
	check("média 8d6", Rules.average("8d6"), 28)
	var adv_wins := 0
	for i in 2000:
		var r := Rules.d20(0, true, false)
		if r["nat"] >= 11:
			adv_wins += 1
	check("vantagem acima de 10 em ~75%", adv_wins > 1350 and adv_wins < 1650, true)
	check("vantagem e desvantagem se anulam", Rules.d20(0, true, true)["mode"], "normal")
	check("crítico dobra dados", Rules.roll("1d6", true)["rolls"].size(), 2)
	check("modificador 15", Rules.mod(15), 2)
	check("modificador 8", Rules.mod(8), -1)

	# Guerreiro 1, humano, soldado: For 17, Des 14, Con 14
	var f1 := pc("fighter", 1, {"options": {"fighting_style": "defense", "weapon_masteries": ["greatsword", "flail"]}, "skills": ["acrobatics", "perception"]})
	check("guerreiro 1 For", f1["scores"]["str"], 17)
	check("guerreiro 1 PV (10 + Con 2)", f1["hp_max"], 12)
	check("guerreiro 1 bônus de proficiência", f1["pb"], 2)
	check("guerreiro 1 salvaguarda For", Rules.save_bonus(f1, "str"), 5)
	check("guerreiro 1 salvaguarda Sab", Rules.save_bonus(f1, "wis"), 0)
	check("guerreiro 1 Atletismo (soldado)", Rules.skill_bonus(f1, "athletics"), 5)
	check("guerreiro 1 armadura (cota de malha)", f1["armor_id"], "chain_mail")
	check("guerreiro 1 CA (16 + Defesa)", Rules.ac(f1), 17)
	check("guerreiro 1 Retomar o Fôlego", f1["resources"]["second_wind"]["max"], 2)
	var gs: Array = f1["attacks"].filter(func(a): return a["weapon_id"] == "greatsword")
	check("guerreiro 1 espada grande no inventário", gs.size(), 1)
	if gs.size() > 0:
		check("espada grande acerto (+3 For +2 prof)", gs[0]["to_hit"], 5)
		check("espada grande dano", gs[0]["damage"], "2d6+3")
		check("espada grande maestria", gs[0]["mastery"], "graze")

	# Guerreiro 5: Ataque Extra
	var f5 := pc("fighter", 5)
	check("guerreiro 5 PV (12 + 4x(6+2))", f5["hp_max"], 44)
	check("guerreiro 5 ataque extra", f5["traits"]["extra_attacks"], 1)
	check("guerreiro 5 proficiência", f5["pb"], 3)
	var champ := pc("fighter", 3, {"sub": "champion"})
	check("campeão crítico 19", champ["traits"]["crit_range"], 19)

	# Bárbaro 1 sem armadura: 10 + Des + Con
	var b1 := pc("barbarian", 1, {"scores": {"str": 15, "dex": 14, "con": 13, "int": 8, "wis": 12, "cha": 10}, "bonus": {"str": 2, "con": 1}})
	check("bárbaro sem armadura usa defesa sem armadura", b1["armor_id"], "")
	check("bárbaro CA (10+2+2)", Rules.ac(b1), 14)
	check("bárbaro fúrias", b1["resources"]["rages"]["max"], 2)
	check("bárbaro dano da fúria", b1["traits"]["rage_damage"], 2)

	# Mago 5: espaços 4/3/2, CD 8+3+Int
	var w5 := pc("wizard", 5, {"bg": "sage", "scores": {"str": 8, "dex": 14, "con": 13, "int": 15, "wis": 12, "cha": 10}, "bonus": {"int": 2, "con": 1}})
	check("mago 5 espaços 1", w5["slots"]["1"]["max"], 4)
	check("mago 5 espaços 2", w5["slots"]["2"]["max"], 3)
	check("mago 5 espaços 3", w5["slots"]["3"]["max"], 2)
	check("mago 5 CD de magia (8+3+3)", Rules.spell_dc(w5), 14)
	check("mago 5 ataque mágico", Rules.spell_attack(w5), 6)
	check("mago CA sem armadura (10+2)", Rules.ac(w5), 12)

	# Ladino 5: Ataque Furtivo 3d6
	var r5 := pc("rogue", 5, {"bg": "criminal", "scores": {"str": 8, "dex": 15, "con": 14, "int": 12, "wis": 13, "cha": 10}, "bonus": {"dex": 2, "con": 1}})
	check("ladino 5 furtivo", r5["traits"]["sneak_attack"], "3d6")
	check("ladino 5 esquiva sobrenatural", r5["traits"].get("uncanny_dodge", false), true)
	check("ladino armadura de couro", r5["armor_id"], "leather_armor")
	check("ladino CA (11+3)", Rules.ac(r5), 14)

	# Paladino 5: espaços 4/2
	var p5 := pc("paladin", 5)
	check("paladino 5 espaços 1", p5["slots"]["1"]["max"], 4)
	check("paladino 5 espaços 2", p5["slots"]["2"]["max"], 2)
	check("paladino sempre tem Destruição Divina", "divine_smite" in p5["spellcasting"]["always"], true)
	check("paladino cura pelas mãos 25", p5["resources"]["lay_on_hands"]["max"], 25)

	# Bruxo 5: Magia de Pacto 2 espaços de nível 3
	var k5 := pc("warlock", 5, {"options": {"invocations": ["agonizing_blast", "armor_of_shadows", "pact_of_the_tome"]}})
	check("bruxo 5 espaços de pacto", k5["pact"]["max"], 2)
	check("bruxo 5 nível do pacto", k5["pact"]["level"], 3)

	# Multiclasse guerreiro 2 / mago 3: nível de conjurador 3 -> 4/2
	var mc := pc("fighter", 1, {"classes": [{"class_id": "fighter", "level": 2}, {"class_id": "wizard", "level": 3, "subclass_id": "evoker"}]})
	check("multiclasse nível total", mc["level"], 5)
	check("multiclasse espaços 1", mc["slots"]["1"]["max"], 4)
	check("multiclasse espaços 2", mc["slots"]["2"]["max"], 2)

	# Clérigo vida 3: magias de domínio sempre preparadas
	var cl3 := pc("cleric", 3, {"sub": "life_domain"})
	check("clérigo vida tem Bênção preparada", "bless" in cl3["spellcasting"]["always"], true)
	check("clérigo canalizar divindade 2", cl3["resources"]["channel_divinity"]["max"], 2)

	# Espécies
	var dw := pc("fighter", 3, {"species": "dwarf"})
	check("anão resiste a veneno", "poison" in dw["resist"], true)
	check("anão PV +1 por nível (10+2 + 2x8 + 3)", dw["hp_max"], 31)
	var tf := pc("wizard", 1, {"species": "tiefling", "species_choice": {"lineage": "infernal"}})
	check("tiefling infernal resiste só a fogo", tf["resist"], ["fire"])
	check("tiefling infernal recebe Raio de Fogo", "fire_bolt" in tf["spellcasting"]["cantrips"], true)
	var gol := pc("fighter", 1, {"species": "goliath"})
	check("golias deslocamento 35 pés", Rules.speed_ft(gol), 35)

	# Monstro do SRD
	var g := MonsterBuilder.build("goblin_warrior", "g1")
	check("goblin guerreiro CA", Rules.ac(g), 15)
	check("goblin guerreiro PV", g["hp_max"], 10)
	check("goblin guerreiro ataques", g["attacks"].size(), 2)
	check("goblin cimitarra acerto", g["attacks"][0]["to_hit"], 4)
	check("goblin extra com vantagem", g["attacks"][0]["extra"]["only_with_advantage"], true)
	var ogre := MonsterBuilder.build("ogre", "o1")
	check("ogro existe", ogre.is_empty(), false)
	var dragon := MonsterBuilder.build("adult_red_dragon", "d1")
	check("dragão vermelho adulto imune a fogo", "fire" in dragon["immune"], true)
	check("dragão multiataque", dragon["multiattack"] >= 3, true)
	check("dragão sopro com recarga", dragon["monster_actions"].any(func(a): return a.get("recharge", 0) == 5), true)

	# Dano
	check("resistência corta pela metade", Rules.adjust_damage(dw, 9, "poison"), [4, "resistência"])
	check("imunidade zera", Rules.adjust_damage(dragon, 30, "fire"), [0, "imune"])

	# Tradução pt-BR
	check("meta bola de fogo", Srd.spell_meta("fireball"), "Ação · 45 m · Instantânea")
	check("meta bênção", Srd.spell_meta("bless"), "Ação · 9 m · Concentração, até 1 minuto")
	check("texto bola de fogo traduzido", Srd.spell_text("fireball").begins_with("Um risco brilhante"), true)
	check("todas as magias traduzidas", Srd.spells.keys().all(func(s): return Srd.is_translated("spell", s)), true)
	var wl := pc("warlock", 2, {"options": {"invocations": ["agonizing_blast", "armor_of_shadows"]}})
	var inv_feats: Array = wl["features"].filter(func(f): return f["id"] == "agonizing_blast")
	check("invocação na ficha", inv_feats.size(), 1)
	check("invocação traduzida", inv_feats[0]["translated"] if inv_feats.size() > 0 else false, true)
	var all_pt := true
	for f in pc("barbarian", 5)["features"]:
		if not f.get("translated", false):
			all_pt = false
			print("  sem tradução: ", f["id"])
	check("características do bárbaro traduzidas", all_pt, true)
	# Itens do equipamento inicial que não foram reconhecidos
	var missing: Array = []
	for cid in Srd.classes:
		for opt in Srd.classes[cid]["equipment"]:
			for it in opt["items"]:
				if Srd.find_item(str(it["item"])).is_empty() and not it["item"] in missing:
					missing.append(it["item"])
	for bid in Srd.backgrounds:
		for opt in Srd.backgrounds[bid]["equipment"]:
			for it in opt["items"]:
				if Srd.find_item(str(it["item"])).is_empty() and not it["item"] in missing:
					missing.append(it["item"])
	print("itens iniciais sem correspondência: ", missing)
	print("== %d ok, %d falhas" % [passes, fails])


## Testes de combate com o motor de verdade (sem tela). Usa o grupo pré-gerado da mesa.
static func run_combat() -> void:
	print("== testes de combate")
	var g = Game
	g.load_adventure("vale_cinzento")
	var lia: Dictionary = g.by_id["lia"]
	var borin: Dictionary = g.by_id["borin"]
	var seren: Dictionary = g.by_id["seren"]
	var pip: Dictionary = g.by_id["pip"]
	var gob: Dictionary = g.by_id["gob_a"]
	var hob: Dictionary = g.by_id["hob"]
	check("pré-gerados: Lia é clériga 3", lia["class_id"] + str(lia["level"]), "cleric3")
	check("Borin guerreiro com espada grande", borin["attacks"].any(func(a): return a["weapon_id"] == "greatsword"), true)
	check("Seren tem Mísseis Mágicos", "magic_missile" in CharBuilder.castable_spells(seren), true)
	check("Pip furtivo 2d6", pip["traits"]["sneak_attack"], "2d6")
	check("Hobgoblin do SRD (CA 18)", Rules.ac(hob), 18)

	# Ordem de turnos controlada para os testes
	g.in_combat = true
	g.order = ["pip", "borin", "seren", "lia", "gob_a", "gob_b", "hob"]
	g.turn_index = 0
	g.round_num = 1
	for c in g.all_combatants():
		g._new_turn(c)

	# Ataque Furtivo com aliado colado no alvo
	gob["pos"] = Vector2(0.5, 0.5)
	pip["pos"] = g.from_m(g.to_m(gob["pos"]) + Vector2(-1.5, 0))
	borin["pos"] = g.from_m(g.to_m(gob["pos"]) + Vector2(1.5, 0))
	var ss: Dictionary = pip["attacks"].filter(func(a): return a["weapon_id"] == "shortsword")[0]
	var dmg: Dictionary = g.cb.damage_for_attack(pip, ss, gob, false, {"adv": false})
	check("Furtivo entra com aliado colado", dmg["parts"].size() >= 2, true)
	var dmg2: Dictionary = g.cb.damage_for_attack(pip, ss, gob, false, {"adv": false})
	check("Furtivo só uma vez por turno", dmg2["parts"].size(), 1)
	var ma: Array = g.cb.attack_modes(pip, gob, ss)
	check("sem vantagem/desvantagem em pé e perto", [ma[0].size(), ma[1].size()], [0, 0])
	g.cb.add_condition(gob, "prone", pip)
	ma = g.cb.attack_modes(pip, gob, ss)
	check("alvo caído e perto dá vantagem", ma[0].size() > 0, true)
	var bow: Dictionary = pip["attacks"].filter(func(a): return a["weapon_id"] == "shortbow")[0]
	ma = g.cb.attack_modes(pip, gob, bow)
	check("arco com inimigo colado dá desvantagem", ma[1].has("inimigo colado"), true)
	g.cb.remove_condition(gob, "prone")

	# Economia: Borin nível 3 tem 1 ataque; um guerreiro 5 teria 2
	g.turn_index = 1
	check("ação Atacar começa", g.spend_attack(borin), true)
	check("Borin sem ataques sobrando", g.turn_of(borin)["attacks_left"], 0)
	check("Borin sem ação depois de atacar", g.cost_error(borin, "action") != "", true)
	check("Surto de Ação libera outra ação", await g.cb.use_feature(borin, "action_surge", [], Vector2.ZERO), true)
	check("ação disponível de novo", g.cost_error(borin, "attack"), "")
	check("Surto não serve para Magia", g.cost_error(borin, "magic") != "", true)

	# Fúria: resistência a cortante
	var barb := pc("barbarian", 3)
	barb["side"] = "party"
	barb["pos"] = Vector2(0.1, 0.1)
	g.party.append(barb)
	g.by_id[barb["id"]] = barb
	g.order.append(barb["id"])
	g._new_turn(barb)
	g.cb.add_effect(barb, {"id": "rage", "name": "Fúria", "mods": {"resist": ["bludgeoning", "piercing", "slashing"]}, "rounds": 100}, barb)
	var hp0: int = barb["hp"]
	g.cb.deal_damage(barb, [{"amount": 10, "dtype": "slashing"}], gob)
	check("Fúria: 10 cortante vira 5", hp0 - int(barb["hp"]), 5)
	g.cb.deal_damage(barb, [{"amount": 6, "dtype": "fire"}], gob)
	check("Fúria não resiste a fogo", hp0 - int(barb["hp"]), 11)

	# 0 PV, testes contra a morte, cura
	g.cb.deal_damage(lia, [{"amount": int(lia["hp"]), "dtype": "slashing"}], gob)
	check("Lia a 0 PV fica inconsciente", Rules.has_condition(lia, "unconscious"), true)
	check("inconsciente também fica caída", Rules.has_condition(lia, "prone"), true)
	g.cb.deal_damage(lia, [{"amount": 3, "dtype": "slashing"}], gob, {"crit": true})
	check("crítico em quem está caído conta 2 falhas", lia["death"]["fail"], 2)
	g.cb.heal(lia, 5, borin)
	check("cura levanta quem está a 0 PV", [int(lia["hp"]), Rules.has_condition(lia, "unconscious")], [5, false])
	check("cura zera os testes contra a morte", lia["death"]["fail"], 0)
	var hp_max: int = lia["hp_max"]
	g.cb.deal_damage(lia, [{"amount": 5 + hp_max, "dtype": "slashing"}], gob)
	check("dano massivo mata na hora", lia["death"]["dead"], true)
	lia["death"]["dead"] = false
	lia["hp"] = lia["hp_max"]
	lia["conditions"] = []

	# Concentração quebra com dano alto (CD 25)
	g.cb.start_concentration(seren, "hold_person")
	var held := false
	for i in 5:
		g.cb.start_concentration(seren, "hold_person")
		seren["hp"] = seren["hp_max"]
		g.cb.deal_damage(seren, [{"amount": 50, "dtype": "fire"}], hob)
		if not seren.has("concentration"):
			held = true
			break
		seren["death"]["dead"] = false
	check("50 de dano costuma quebrar concentração", held, true)
	seren["hp"] = seren["hp_max"]
	seren["conditions"] = []
	seren["death"] = {"success": 0, "fail": 0, "stable": false, "dead": false}

	# Geometria: cone de 4,5 m à direita pega quem está na frente, não quem está atrás
	seren["pos"] = Vector2(0.3, 0.5)
	var front: Dictionary = g.by_id["gob_b"]
	front["pos"] = g.from_m(g.to_m(seren["pos"]) + Vector2(3.0, 0.3))
	hob["pos"] = g.from_m(g.to_m(seren["pos"]) + Vector2(-3.0, 0))
	var hits: Array = g.cb.in_area(seren, "cone", 15, g.from_m(g.to_m(seren["pos"]) + Vector2(5, 0)), true)
	check("cone pega quem está na frente", hits.any(func(c): return c["id"] == "gob_b"), true)
	check("cone não pega quem está atrás", hits.any(func(c): return c["id"] == "hob"), false)

	# Mísseis Mágicos: 3 dardos de 1d4+1, sempre acertam
	g.turn_index = 2
	g._new_turn(seren)
	var hob_hp: int = hob["hp"]
	await g.cb.cast(seren, "magic_missile", 1, ["hob"], Vector2.ZERO)
	var lost: int = hob_hp - int(hob["hp"])
	check("Mísseis Mágicos: 6 a 15 de dano", lost >= 6 and lost <= 15, true)
	check("gastou espaço de nível 1", seren["slots"]["1"]["left"], 3)
	check("gastou a ação", g.cost_error(seren, "magic") != "", true)
	check("só um espaço por turno", g.cb.can_cast(seren, "shield", 1).contains("ação") or g.cb.can_cast(seren, "magic_missile", 1) != "", true)

	# Ataque de oportunidade ao sair do alcance sem Desengajar
	g.turn_index = 0
	g._new_turn(pip)
	gob["reaction_used"] = false
	gob["pos"] = Vector2(0.6, 0.5)
	pip["pos"] = g.from_m(g.to_m(gob["pos"]) + Vector2(-1.4, 0))
	var away: Vector2 = g.from_m(g.to_m(gob["pos"]) + Vector2(-6, 0))
	await g._do_move(pip, away, false)
	check("goblin usou a reação no ataque de oportunidade", gob.get("reaction_used", false), true)
	gob["reaction_used"] = false
	pip["pos"] = g.from_m(g.to_m(gob["pos"]) + Vector2(-1.4, 0))
	g.cb.add_effect(pip, {"id": "disengage", "name": "Desengajar", "mods": {}, "ends": "end_source"}, pip)
	await g._do_move(pip, away, false)
	check("Desengajar evita o ataque de oportunidade", gob.get("reaction_used", false), false)

	# Cura de magia
	g.turn_index = 3
	g._new_turn(lia)
	borin["hp"] = 5
	await g.cb.cast(lia, "healing_word", 1, ["borin"], Vector2.ZERO)
	check("Palavra Curativa + Discípulo da Vida curou", int(borin["hp"]) > 5 + 3, true)

	# Lista de ações para a interface
	var acts: Array = g.available_actions(pip)
	check("lista de ações tem ataques", acts.any(func(a): return a["group"] == "attack"), true)
	check("ladino tem Ação Ardilosa", acts.any(func(a): return a["ref"] is String and a["ref"] == "cunning_dash"), true)
	var sacts: Array = g.available_actions(seren)
	check("maga tem magias na lista", sacts.filter(func(a): return a["group"] == "spell").size() >= 8, true)
	g.in_combat = false
	print("== %d ok, %d falhas (total)" % [passes, fails])


## Criação de sala: ficha automática de todas as classes, orçamento de XP e validação do motor
## sobre a resposta da IA.
static func run_room() -> void:
	print("== testes da criação de sala")
	var before_theme: Dictionary = Srd.theme
	Srd.set_theme(RoomBuilder.theme_by_id("fantasia"))
	var p0 := passes
	var f0 := fails

	check("slug sem acento nem símbolo", RoomBuilder.slug("Mesa do Gabriel! Ç"), "mesa_do_gabriel_c")
	check("slug vazio vira mesa", RoomBuilder.slug("!!!"), "mesa")
	var std := {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}
	check("compra de pontos: conjunto padrão custa 27", RoomBuilder.point_cost(std), 27)
	var p := RoomBuilder.default_player(0, 1, 27)
	check("jogador novo começa com 27 pontos livres", RoomBuilder.points_left(p), 27)
	check("não desce abaixo de 8", RoomBuilder.can_step(p, "str", -1), false)
	check("sobe de 8 para 9", RoomBuilder.can_step(p, "str", 1), true)
	p["base_scores"]["str"] = 15
	check("não passa de 15", RoomBuilder.can_step(p, "str", 1), false)
	p["point_budget"] = 10
	check("orçamento menor trava a subida", RoomBuilder.can_step(p, "dex", 1) and RoomBuilder.points_left(p) == 1, true)
	check("bônus do antecedente tem código", RoomBuilder.bonus_code({"bg_bonus": {"str": 2, "con": 1}}), "str2_con1")

	# Toda classe, em vários níveis, tem de gerar uma ficha válida só com o nome e os pontos
	var bad: Array = []
	for cid in Srd.list("class"):
		for lv in [1, 3, 5]:
			var ch := RoomBuilder.default_player(0, lv, 27)
			ch["name"] = "Teste"
			ch["classes"][0]["class_id"] = cid
			ch["base_scores"] = {"str": 15, "dex": 14, "con": 13, "int": 8, "wis": 8, "cha": 8}
			var errs := RoomBuilder.player_errors(ch)
			if not errs.is_empty():
				bad.append("%s nível %d: %s" % [cid, lv, str(errs)])
			elif int(RoomBuilder.preview(ch)["hp_max"]) <= 0:
				bad.append("%s nível %d: sem PV" % [cid, lv])
	check("autofill: todas as classes (níveis 1, 3 e 5) dão ficha válida", bad, [])

	# Aventura gerada sem IA e com resposta da IA misturando coisas válidas e inventadas
	var players: Array = []
	for i in 4:
		var pl := RoomBuilder.default_player(i, 3, 27)
		pl["name"] = "Heroi %d" % (i + 1)
		pl["profile"]["bonds"] = "Proteger o irmão" if i == 0 else ""
		players.append(RoomBuilder.finalize_player(pl))
	var cfg := {"name": "Sala de teste", "theme": "fantasia", "level": 3, "difficulty": "moderate", "chapters": 1, "players": players,
		"story": "Uma vila pede ajuda contra bandidos na estrada. O grupo precisa descobrir quem os lidera."}
	check("orçamento base de XP (nível 3, 4 jogadores, moderado)", AdventureGen.xp_budget(3, 4, "moderate", 1), 900)
	check("capítulo 1 sai reduzido pela curva (70%)", AdventureGen.xp_budget(3, 4, "moderate", 0), 630)
	var out := AdventureGen.build(cfg, {}, [])
	var mons: Array = []
	for grp0 in out["adventure"]["scenes"][0]["groups"]:
		mons.append_array(grp0["monsters"])
	var xp := 0
	var ids := {}
	var inside := true
	for m in mons:
		xp += int(Srd.monsters[m["monster_id"]]["xp"])
		ids[m["id"]] = true
		inside = inside and m["pos"][0] >= 0.02 and m["pos"][0] <= 0.98 and m["pos"][1] >= 0.03 and m["pos"][1] <= 0.97
	check("modelo: encontro tem monstros", mons.size() > 0, true)
	check("modelo: respeita o orçamento de XP", xp <= 900, true)
	check("modelo: ids únicos", ids.size(), mons.size())
	check("modelo: posições dentro do tabuleiro", inside, true)
	check("modelo: aventura começa na cena cap1", out["adventure"]["start_scene"], "cap1")

	var pool := AdventureGen.monster_pool(cfg)
	var raw := {"title": "Estrada Sangrenta", "synopsis": "Bandidos dominam a estrada.",
		"scenes": [{"title": "Emboscada", "intro": "Flechas cortam o ar.", "monsters": [{"monster_id": "deus_dragao"}, {"monster_id": pool[0], "name": "Chefe da Estrada", "boss": true}]}]}
	var notes: Array = []
	var out2 := AdventureGen.build(cfg, raw, notes)
	var sc: Dictionary = out2["adventure"]["scenes"][0]
	var m2: Array = []
	for grp1 in sc["groups"]:
		m2.append_array(grp1["monsters"])
	check("IA: título aproveitado", out2["adventure"]["title"], "Estrada Sangrenta")
	check("IA: capítulo ganha número", sc["title"], "Capítulo 1: Emboscada")
	check("IA: monstro inventado é recusado", m2.any(func(m): return m["monster_id"] == "deus_dragao"), false)
	check("IA: monstro válido é mantido", m2.any(func(m): return m["monster_id"] == pool[0]), true)
	check("IA: motor avisa da recusa", notes.any(func(n): return str(n).contains("recusou")), true)

	Srd.set_theme(RoomBuilder.theme_by_id("realista"))
	var rpool := AdventureGen.monster_pool({"theme": "realista", "level": 3, "difficulty": "moderate", "players": players})
	check("realista: só humanoides e feras", rpool.all(func(id): return str(Srd.monsters[id]["type_line"]).contains("Humanoid") or str(Srd.monsters[id]["type_line"]).contains("Beast")), true)

	Srd.set_theme(before_theme)

	# Experiência: a ficha nunca nasce com XP abaixo do mínimo do próprio nível, senão a faixa
	# de experiência nunca alcança o nível seguinte e o botão "Subir de nível" vira passe livre.
	var lv3 := pc("fighter", 3)
	check("nível 3 nasce com a XP mínima do nível", lv3["xp"], Srd.xp_for_level(3))
	check("nível 3 não pode subir sem XP nova", Game.can_level_up(lv3), false)
	lv3["xp"] = Srd.xp_for_level(4)
	check("nível 3 pode subir com 2700 XP", Game.can_level_up(lv3), true)
	var lv1 := pc("rogue", 1)
	check("nível 1 começa com 0 XP", lv1["xp"], 0)
	check("nível 20 nunca pode subir", Game.can_level_up({"level": 20, "xp": 999999}), false)


	# Progressão de capítulos: curva de dificuldade, objetivos por capítulo e pontos de descanso.
	var cfg3: Dictionary = cfg.duplicate(true)
	cfg3["chapters"] = 3
	check("capítulo 1 pesa menos que o orçamento base", AdventureGen.xp_budget(3, 4, "moderate", 0) < AdventureGen.xp_budget(3, 4, "moderate", 1), true)
	check("capítulo 3 pesa mais que o capítulo 2", AdventureGen.xp_budget(3, 4, "moderate", 2) > AdventureGen.xp_budget(3, 4, "moderate", 1), true)
	var out3 := AdventureGen.build(cfg3, {}, [])
	var adv3: Dictionary = out3["adventure"]
	check("3 capítulos gerados", adv3["scenes"].size(), 3)
	var ids3 := {}
	for sc3 in adv3["scenes"]:
		ids3[sc3["id"]] = true
	check("ids de capítulo únicos", ids3.size(), 3)
	check("missão principal tem um objetivo por capítulo", out3["quests"][0]["objectives"].size(), 3)
	check("missão principal está fixada", out3["quests"][0]["pinned"], true)
	check("aventura tem epílogo", str(adv3.get("epilogue", "")) != "", true)
	check("orçamento cresce entre capítulos", int(out3["stats"][2]["budget"]) > int(out3["stats"][0]["budget"]), true)
	var xp_ok := true
	for i3 in 3:
		if int(out3["stats"][i3]["xp"]) > int(out3["stats"][i3]["budget"]):
			xp_ok = false
	check("nenhum capítulo passa do próprio orçamento", xp_ok, true)
	var bosses := 0
	for i3 in 3:
		for grp3 in adv3["scenes"][i3]["groups"]:
			for m3 in grp3["monsters"]:
				if m3.get("boss", false) and i3 < 2:
					bosses += 1
	check("chefe forçado só no último capítulo", bosses, 0)
	check("pontos de descanso a cada dois capítulos", adv3["rest_points"], [0, 2])

	# Avanço de capítulo no motor, com o desgaste preservado
	var before_adv: Dictionary = Game.adventure
	var before_quests: Array = Game.quests
	var before_ch: int = Game.chapter
	var before_party: Array = Game.party
	var before_by_id: Dictionary = Game.by_id
	var before_enemies: Array = Game.enemies
	var before_mode: String = str(Game.settings.get("rest_mode", "livre"))
	var before_persist: bool = Game.persist
	Game.persist = false
	Game.adventure = adv3
	Game.quests = out3["quests"]
	Game.chapter = 0
	Game.in_combat = false
	Game.settings["rest_mode"] = "aventura"
	check("3 capítulos no motor", Game.chapter_count(), 3)
	check("há capítulo seguinte", Game.has_next_chapter(), true)
	check("descanso longo liberado no capítulo 1", Game.can_long_rest(), true)
	Game.complete_chapter_objective()
	check("objetivo do capítulo 1 marcado", Game.quests[0]["objectives"][0]["done"], true)
	check("objetivo do capítulo 2 ainda aberto", Game.quests[0]["objectives"][1]["done"], false)
	var hurt := pc("fighter", 3)
	hurt["id"] = "ferido"
	hurt["hp"] = 0
	hurt["conditions"] = [{"id": "prone", "source": ""}]
	hurt["death"] = {"success": 0, "fail": 2, "stable": true, "dead": false}
	hurt["pos"] = Vector2(0.2, 0.6)
	Game.party = [hurt]
	Game.by_id = {"ferido": hurt}
	check("avançou de capítulo", Game.advance_chapter(), true)
	check("capítulo agora é o 2", Game.chapter, 1)
	check("caído volta estabilizado com 1 PV", int(Game.party[0]["hp"]), 1)
	check("testes contra a morte zerados", int(Game.party[0]["death"]["fail"]), 0)
	check("condições de combate limpas", Game.party[0]["conditions"], [])
	check("sem descanso longo no capítulo 2", Game.can_long_rest(), false)
	Game.complete_chapter_objective()
	check("objetivo do capítulo 2 marcado", Game.quests[0]["objectives"][1]["done"], true)
	check("avançou para o último capítulo", Game.advance_chapter(), true)
	check("descanso longo de volta no capítulo 3", Game.can_long_rest(), true)
	check("não há capítulo depois do último", Game.has_next_chapter(), false)
	check("avançar do último não faz nada", Game.advance_chapter(), false)
	Game.adventure = before_adv
	Game.quests = before_quests
	Game.chapter = before_ch
	Game.party = before_party
	Game.by_id = before_by_id
	Game.enemies = before_enemies
	Game.order.clear()
	Game.settings["rest_mode"] = before_mode
	Game.persist = before_persist


	# Exploração: pontos de interesse, bandos escondidos, saque e saída.
	var cfgx: Dictionary = cfg.duplicate(true)
	cfgx["chapters"] = 2
	var outx := AdventureGen.build(cfgx, {}, [])
	var scx: Dictionary = outx["adventure"]["scenes"][0]
	check("cena de exploração tem pontos de interesse", scx["pois"].size() > 0, true)
	check("nada visível no início", scx["encounter"]["monsters"], [])
	check("os monstros foram para bandos escondidos", scx["groups"].size() > 0, true)
	var kinds := {}
	for px in scx["pois"]:
		kinds[px["kind"]] = int(kinds.get(px["kind"], 0)) + 1
	check("existe exatamente uma saída", int(kinds.get("exit", 0)), 1)
	check("existe ponto obrigatório", int(kinds.get("mark", 0)) >= 1, true)
	check("existe baú", int(kinds.get("chest", 0)) >= 1, true)
	var in_board := true
	var chest_loot := {}
	for px2 in scx["pois"]:
		if float(px2["pos"][0]) < 0.02 or float(px2["pos"][0]) > 0.98 or float(px2["pos"][1]) < 0.03 or float(px2["pos"][1]) > 0.97:
			in_board = false
		if px2["kind"] == "chest":
			chest_loot = px2["loot"]
	check("pontos dentro do tabuleiro", in_board, true)
	check("baú tem moedas", int(chest_loot.get("coins", 0)) > 0, true)
	var loot_ok := true
	for it in chest_loot.get("items", []):
		if not Srd.gear.has(str(it)):
			loot_ok = false
	check("itens do baú existem no SRD", loot_ok, true)
	var mons_in_groups := 0
	for gx in scx["groups"]:
		mons_in_groups += gx["monsters"].size()
		check("bando tem raio de emboscada", float(gx["radius_m"]) > 0.0, true)
	check("todo monstro ficou em algum bando", mons_in_groups > 0, true)

	# Percurso no motor: descobrir, saquear, emboscar e sair
	var bx_adv: Dictionary = Game.adventure
	var bx_party: Array = Game.party
	var bx_by_id: Dictionary = Game.by_id
	var bx_enemies: Array = Game.enemies
	var bx_quests: Array = Game.quests
	var bx_ch: int = Game.chapter
	var bx_persist: bool = Game.persist
	Game.persist = false
	Game.adventure = outx["adventure"]
	Game.quests = outx["quests"]
	Game.chapter = 0
	Game.in_combat = false
	Game.chapter_done = false
	var hero := pc("fighter", 3)
	hero["id"] = "heroi"
	hero["pos"] = Vector2(0.2, 0.6)
	Game.party = [hero]
	Game.by_id = {"heroi": hero}
	Game.enemies = []
	Game.load_scene(scx)
	check("exploração ativa fora de combate", Game.ex.active(), true)
	check("saída fechada no começo", Game.ex.exit_open(), false)
	var total_req := Game.ex.required_total()
	check("há ponto obrigatório a visitar", total_req >= 1, true)
	var undiscovered := true
	for pz in Game.pois:
		if pz["found"]:
			undiscovered = false
	check("nenhum ponto nasce descoberto longe do grupo", undiscovered, true)
	# Anda até cada ponto obrigatório; o motor revela e marca
	for pz2 in Game.pois:
		if not pz2["required"]:
			continue
		Game.in_combat = false
		Game.enemies = []
		Game.ex.explore_move("heroi", pz2["pos"])
		var near: Dictionary = Game.by_id["heroi"]
		if Game.dist_m(near["pos"], pz2["pos"]) > Exploration.REACH_M:
			near["pos"] = pz2["pos"]
			Game.ex.explore_move("heroi", pz2["pos"])
	check("pontos obrigatórios visitados liberam a saída", Game.ex.exit_open(), true)
	# O baú entra nas escolhas, para sobreviver a salvar e carregar
	var chest_poi := {}
	for pz3 in Game.pois:
		if pz3["kind"] == "chest":
			chest_poi = pz3
	Game.in_combat = false
	Game.enemies = []
	Game.by_id["heroi"]["pos"] = Vector2(clampf(chest_poi["pos"].x - 0.06, 0.05, 0.95), chest_poi["pos"].y)
	Game.ex.explore_move("heroi", chest_poi["pos"])
	check("baú saqueado", chest_poi["taken"], true)
	var after: Dictionary = Game.by_id["heroi"]
	check("saque virou ouro nas escolhas", int(after["choices"].get("gold_extra", 0)) > 0, true)
	check("saque entrou no inventário", after["inventory"].size() > pc("fighter", 3)["inventory"].size(), true)
	check("reconstruir a ficha mantém o id", str(after["id"]), "heroi")
	check("by_id e party não divergem", str(Game.party[0]["id"]), str(after["id"]))
	# Emboscada: andar até o centro de um bando dispara o combate
	Game.chapter_done = false
	var gx2: Dictionary = Game.groups[0]
	Game.by_id["heroi"]["pos"] = Vector2(clampf(gx2["pos"].x - 0.06, 0.05, 0.95), gx2["pos"].y)
	Game.ex.explore_move("heroi", gx2["pos"])
	check("bando disparou", gx2["triggered"], true)
	check("inimigos entraram no tabuleiro", Game.enemies.size() > 0, true)
	check("exploração pausa em combate", Game.ex.active(), false)
	# A saída encerra o capítulo
	Game.in_combat = false
	Game.busy = false
	for e2 in Game.enemies:
		e2["hp"] = 0
	var exit_p: Dictionary = Game.ex.exit_poi()
	Game.by_id["heroi"]["pos"] = Vector2(clampf(exit_p["pos"].x - 0.06, 0.05, 0.95), exit_p["pos"].y)
	Game.ex.explore_move("heroi", exit_p["pos"])
	check("capítulo fechou na saída", Game.chapter_done, true)
	check("objetivo do capítulo marcado", Game.quests[0]["objectives"][0]["done"], true)
	Game.adventure = bx_adv
	Game.quests = bx_quests
	Game.chapter = bx_ch
	Game.party = bx_party
	Game.by_id = bx_by_id
	Game.enemies = bx_enemies
	Game.pois = []
	Game.groups = []
	Game.order.clear()
	Game.chapter_done = false
	Game.persist = bx_persist


	# Lore pública, pedidos de arte sem spoiler e segunda passada com os personagens
	var cfgl := {"name": "Mesa do Teste", "theme": "fantasia", "level": 3, "difficulty": "moderate",
		"chapters": 2, "player_count": 4, "players": [],
		"story": "Uma vila pede ajuda contra bandidos na estrada. O grupo precisa descobrir quem os lidera."}
	check("orçamento usa player_count, sem fichas", AdventureGen.party_size(cfgl), 4)
	check("orçamento igual ao da lista de fichas", AdventureGen.xp_budget(3, AdventureGen.party_size(cfgl), "moderate", 1), 900)
	var rawl := {"title": "A Estrada de Odila", "synopsis": "Bandidos na estrada.",
		"lore": "A estrada corta o vale.\n\nQuem paga é a guilda.",
		"art_maps": [{"assunto": "estrada de terra no vale de Odila no capítulo 2", "ambiente": "pedras e carroças quebradas",
			"luz": "fim de tarde", "paleta": "ocre, verde, cinza"}],
		"npcs": [{"name": "Odila", "role": "guilda", "known": "contratou o grupo"}],
		"scenes": [{"title": "Emboscada", "pois": [{"name": "Carroça de Odila", "kind": "chest", "text": ""}]}]}
	var outl := AdventureGen.build(cfgl, rawl, [])
	var advl: Dictionary = outl["adventure"]
	check("lore pública guardada", str(advl["lore"]).contains("estrada corta o vale"), true)
	check("lore ainda não reescrita", advl["lore_updated"], false)
	check("quantidade de jogadores gravada na aventura", int(advl["player_count"]), 4)
	check("chave de arte por sala, não por id", str(advl["scenes"][0]["art_key"]), "mesa_do_teste_cap1")
	check("nenhuma missão pessoal antes dos personagens", outl["quests"].any(func(q): return str(q["id"]).begins_with("pessoal_")), false)
	# Pedidos de arte: um mapa por capítulo, um retrato por criatura, sem nome próprio nem capítulo
	var artl: Array = outl["art"]
	var maps := artl.filter(func(a): return a["kind"] == "scenes")
	var creats := artl.filter(func(a): return a["kind"] == "monsters")
	check("um pedido de mapa por capítulo", maps.size(), 2)
	check("há pedido de criatura", creats.size() > 0, true)
	var leak := ""
	for a in artl:
		var low := str(a["prompt"]).to_lower()
		for term in ["odila", "capítulo", "capitulo"]:
			if low.contains(term):
				leak = "%s em %s" % [term, a["id"]]
	check("pedido de arte não vaza nome nem capítulo", leak, "")
	var digits := RegEx.create_from_string("\\d")
	var has_digit := false
	for a2 in maps:
		if digits.search(str(a2["prompt"]).replace("16:9", "")) != null:
			has_digit = true
	check("pedido de mapa sem número", has_digit, false)
	var keys_ok := true
	for a3 in artl:
		if str(a3["key"]).strip_edges() == "" or not str(a3["kind"]) in ["scenes", "monsters"]:
			keys_ok = false
	check("todo pedido tem chave e tipo válidos", keys_ok, true)
	# Segunda passada sem IA: a lore ganha o grupo e as missões pessoais aparecem
	var pls: Array = []
	for i4 in 2:
		var pl := RoomBuilder.default_player(i4, 3, 27)
		pl["name"] = "Heroi %d" % (i4 + 1)
		pl["profile"]["background"] = "Filho de ferreiro"
		pl["profile"]["bonds"] = "Achar o irmão desaparecido"
		pls.append(RoomBuilder.finalize_player(pl))
	var genl := AdventureGen.new()
	var outl2: Dictionary = await genl.update_lore(outl, pls, false)
	var advl2: Dictionary = outl2["adventure"]
	check("lore reescrita marcada", advl2["lore_updated"], true)
	check("lore guardou a versão original", str(advl2["lore_base"]).contains("estrada corta o vale"), true)
	check("lore menciona o grupo", str(advl2["lore"]).contains("Heroi 1"), true)
	check("missão pessoal criada", outl2["quests"].any(func(q): return str(q["id"]).begins_with("pessoal_")), true)
	# Reescrever de novo não duplica nem empilha texto
	var before_n: int = outl2["quests"].size()
	var lore_len: int = str(advl2["lore"]).length()
	var outl3: Dictionary = await genl.update_lore(outl2, pls, false)
	check("reescrever duas vezes não duplica missão", outl3["quests"].size(), before_n)
	check("reescrever duas vezes não empilha texto", str(outl3["adventure"]["lore"]).length(), lore_len)
	genl.free()

	print("== sala: %d ok, %d falhas" % [passes - p0, fails - f0])


# ================================================================ terreno e mapas por tema

static func _wall_column(x: int, door_from := -1, door_to := -1) -> TerrainMap:
	var t := TerrainMap.blank(32, 18)
	for y in 18:
		if y < door_from or y > door_to:
			t.set_at(x, y, TerrainMap.WALL)
	return t


static func run_terrain() -> void:
	print("== testes de terreno e mapas")
	var p0 := passes
	var f0 := fails

	# --- grade: passagem, visão, caminho
	var t := _wall_column(10, 15, 16)
	check("chão livre é pisável", t.walkable_m(Vector2(5.5, 5.5)), true)
	check("parede não é pisável", t.walkable_m(Vector2(10.5, 5.5)), false)
	check("encostado demais na parede não é pisável", t.walkable_m(Vector2(9.9, 5.5)), false)
	check("parede tapa a visão", t.line_clear(Vector2(5.5, 5.5), Vector2(15.5, 5.5)), false)
	check("do mesmo lado se enxerga", t.line_clear(Vector2(5.5, 5.5), Vector2(8.5, 12.5)), true)
	var path := t.find_path(Vector2(5.5, 5.5), Vector2(15.5, 5.5))
	check("existe caminho pela porta", path.is_empty(), false)
	check("o caminho contorna a parede (mais longo que a reta)", float(path.get("cost", 0.0)) > 20.0, true)
	var seg_ok := true
	var pts: PackedVector2Array = path.get("points", PackedVector2Array())
	for i in range(1, pts.size()):
		if not t.walk_clear(pts[i - 1], pts[i]):
			seg_ok = false
	check("todo trecho do caminho é andável", seg_ok, true)
	check("parede inteira: sem caminho", _wall_column(10).find_path(Vector2(5.5, 5.5), Vector2(15.5, 5.5)).is_empty(), true)
	var tr := TerrainMap.blank(32, 18)
	for y in 18:
		for x in range(8, 13):
			tr.set_at(x, y, TerrainMap.ROUGH)
	var pr := tr.find_path(Vector2(5.5, 9.5), Vector2(15.5, 9.5))
	check("terreno difícil custa o dobro (10 m com 5 m difíceis = 15)", absf(float(pr["cost"]) - 15.0) < 0.6, true)
	var cut := tr.truncate(pr["points"], 6.0)
	check("cortar o caminho respeita o orçamento", tr.path_cost(cut) <= 6.05, true)
	check("bloqueio por criatura hostil fecha a porta", t.find_path(Vector2(5.5, 5.5), Vector2(15.5, 5.5), {Vector2i(10, 15): true, Vector2i(10, 16): true}).is_empty(), true)
	var vis := t.visible_from(Vector2(5.5, 5.5), 14.0)
	check("visão não atravessa parede", Vector2i(15, 5) in vis, false)
	check("visão alcança o próprio lado", Vector2i(8, 5) in vis, true)
	check("a própria parede é vista", Vector2i(10, 5) in vis, true)

	# --- cobertura (SRD 5.2.1)
	var tl := TerrainMap.blank(32, 18)
	tl.set_at(10, 9, TerrainMap.LOW)
	check("obstáculo baixo: meia cobertura", tl.cover(Vector2(5.5, 9.5), Vector2(12.5, 9.5)), TerrainMap.COVER_HALF)
	check("obstáculo colado no atacante não conta", tl.cover(Vector2(9.6, 9.5), Vector2(16.5, 9.5)), TerrainMap.COVER_NONE)
	check("obstáculo baixo não tapa a visão", tl.line_clear(Vector2(5.5, 9.5), Vector2(12.5, 9.5)), true)
	check("atrás da parede: cobertura total", _wall_column(10).cover(Vector2(5.5, 9.5), Vector2(12.5, 9.5)), TerrainMap.COVER_TOTAL)
	var tc := TerrainMap.blank(32, 18)
	for y2 in 10:
		tc.set_at(10, y2, TerrainMap.WALL)
		tc.set_at(11, y2, TerrainMap.WALL)
	check("colado atrás da quina: cobertura total", tc.cover(Vector2(5.5, 5.5), Vector2(12.5, 9.0)), TerrainMap.COVER_TOTAL)
	check("saindo da quina: três quartos", tc.cover(Vector2(5.5, 5.5), Vector2(12.0, 11.2)), TerrainMap.COVER_THREE_QUARTERS)
	check("mais fora da quina: meia cobertura", tc.cover(Vector2(5.5, 5.5), Vector2(12.0, 11.8)), TerrainMap.COVER_HALF)
	check("longe da quina: sem cobertura", tc.cover(Vector2(5.5, 5.5), Vector2(12.0, 12.4)), TerrainMap.COVER_NONE)
	check("criatura no meio: meia cobertura", TerrainMap.blank(32, 18).cover(Vector2(5.5, 9.5), Vector2(12.5, 9.5), [Vector2(9.0, 9.6)]), TerrainMap.COVER_HALF)
	check("mapa vazio: sem cobertura nem parede", TerrainMap.new().cover(Vector2(1, 1), Vector2(9, 9)), TerrainMap.COVER_NONE)

	# --- briefing da IA: só o que está nas listas
	var br := MapGen.read_brief({"bioma": "Lua", "feicoes": ["rio", "dragão", "Ponte", "lago", "pilares"]})
	check("bioma inventado é recusado", br["biome"], "")
	check("feições fora da lista saem, máximo 3", br["features"], ["rio", "ponte", "lago"])
	check("bioma com acento e maiúscula é aceito", MapGen.read_brief({"bioma": "Pântano"})["biome"], "pantano")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	check("texto da cena puxa o bioma (cripta → masmorra)", MapGen.pick_biome("", "fantasia", "A cripta esquecida", "", rng), "masmorra")
	check("cyberpunk sem pista fica nos biomas do tema", str(MapGen.pick_biome("", "cyberpunk", "", "", rng)) in MapGen.THEME_BIOMES["cyberpunk"], true)

	# --- cada bioma: tudo alcançável, ninguém emboscado no início, mesma semente = mesmo mapa
	var cfg := {"name": "Sala do terreno", "theme": "fantasia", "level": 3, "difficulty": "moderate", "chapters": 2,
		"player_count": 4, "players": [], "story": "Uma vila pede ajuda contra bandidos na estrada."}
	var built := AdventureGen.build(cfg, {}, [])
	var base_sc: Dictionary = built["adventure"]["scenes"][1]
	check("aventura gerada já vem com mapa", built["adventure"]["scenes"][0].has("map"), true)
	check("estatística da sala mostra o bioma", str(built["stats"][0].get("biome", "")) != "", true)
	var bad: Array = []
	for b in MapGen.BIOMES.keys():
		var sc: Dictionary = base_sc.duplicate(true)
		sc.erase("map")
		var tm := MapGen.layout(sc, b, ["rio", "pilares"] if b == "campo" else [], 99)
		var start := tm.nearest_passable(MapGen.START_M, 6)
		var mask := tm.reach_mask(start)
		var spots: Array = []
		for ps in sc["party_start"]:
			spots.append(["grupo", ps])
		for poi in sc["pois"]:
			spots.append([poi["kind"], poi["pos"]])
		var mons: Array = []
		for grp in sc["groups"]:
			spots.append(["bando", grp["pos"]])
			for m in grp["monsters"]:
				spots.append(["monstro", m["pos"]])
				mons.append(Vector2(float(m["pos"][0]) * 32.0, float(m["pos"][1]) * 18.0))
		for sp in spots:
			var pm := Vector2(float(sp[1][0]) * 32.0, float(sp[1][1]) * 18.0)
			var cc := TerrainMap.cell_of(pm)
			if not tm.walkable_m(pm) or mask[cc.y * tm.w + cc.x] == 0:
				bad.append("%s: %s inalcançável" % [b, sp[0]])
		for i2 in mons.size():
			for j2 in range(i2 + 1, mons.size()):
				if mons[i2].distance_to(mons[j2]) < 1.2:
					bad.append("%s: monstros colados" % b)
		for ps2 in sc["party_start"]:
			var pp := Vector2(float(ps2[0]) * 32.0, float(ps2[1]) * 18.0)
			for mp in mons:
				if pp.distance_to(mp) <= MapGen.MIN_SPACING + 4.0 and tm.line_clear(pp, mp):
					bad.append("%s: bando à vista e colado no início" % b)
		var exit_x := 0.0
		for poi2 in sc["pois"]:
			if poi2["kind"] == "exit":
				exit_x = float(poi2["pos"][0]) * 32.0
		if exit_x < 16.0:
			bad.append("%s: saída do lado do início" % b)
		var again: Dictionary = base_sc.duplicate(true)
		again.erase("map")
		MapGen.layout(again, b, ["rio", "pilares"] if b == "campo" else [], 99)
		if again["map"]["rows"] != sc["map"]["rows"] or again["pois"] != sc["pois"]:
			bad.append("%s: mesma semente deu outro mapa" % b)
	check("todos os biomas: posições alcançáveis, sem emboscada no início, determinísticos", bad, [])

	# IA pediu bioma e feição
	var raw := {"scenes": [{"title": "Na mata", "terreno": {"bioma": "floresta", "feicoes": ["rio", "ponte"]}}]}
	var cfg1: Dictionary = cfg.duplicate(true)
	cfg1["chapters"] = 1
	var out_ai := AdventureGen.build(cfg1, raw, [])
	var mp1: Dictionary = out_ai["adventure"]["scenes"][0]["map"]
	check("IA escolheu floresta", mp1["biome"], "floresta")
	check("feição pedida entrou", "rio" in mp1["features"], true)
	check("mapa com rio tem água", TerrainMap.from_rows(mp1["rows"]).count(TerrainMap.GAP) > 0, true)
	check("prompt da IA lista os biomas", AdventureGen.system_prompt(cfg1).contains("masmorra"), true)

	# Sala gravada antes dos mapas ganha um ao carregar, sempre o mesmo
	var old_sc: Dictionary = base_sc.duplicate(true)
	old_sc.erase("map")
	var old2: Dictionary = old_sc.duplicate(true)
	MapGen.ensure(old_sc, "mistico", "Uma floresta antiga")
	MapGen.ensure(old2, "mistico", "Uma floresta antiga")
	check("cena antiga ganhou mapa", old_sc.has("map"), true)
	check("cena antiga: sempre o mesmo mapa", old_sc["map"]["rows"] == old2["map"]["rows"], true)
	var legacy := {"id": "x", "encounter": {"monsters": []}}
	MapGen.ensure(legacy, "fantasia", "")
	check("cena sem exploração continua sem mapa", legacy.has("map"), false)

	# --- motor do jogo com terreno: parede, cobertura, área e emboscada
	var g = Game
	var keep := {"adventure": g.adventure, "party": g.party, "by_id": g.by_id, "enemies": g.enemies, "terrain": g.terrain,
		"pois": g.pois, "groups": g.groups, "in_combat": g.in_combat, "order": g.order.duplicate(), "turn_index": g.turn_index,
		"turns": g.turns, "persist": g.persist, "seen": g.seen, "visible_now": g.visible_now, "chapter_done": g.chapter_done}
	g.persist = false
	g.terrain = _wall_column(10, 15, 16)
	var hero := pc("fighter", 3)
	hero["id"] = "heroi_t"
	hero["side"] = "party"
	hero["pos"] = g.from_m(Vector2(5.5, 5.5))
	var gob := MonsterBuilder.build("goblin_warrior", "gob_t", {}) if Srd.monsters.has("goblin_warrior") else MonsterBuilder.build(str(Srd.monsters.keys()[0]), "gob_t", {})
	gob["side"] = "enemy"
	gob["pos"] = g.from_m(Vector2(15.5, 5.5))
	g.party = [hero]
	g.enemies = [gob]
	g.by_id = {"heroi_t": hero, "gob_t": gob}
	g.pois = []
	g.groups = []
	check("spot_free recusa parede", g.spot_free(g.from_m(Vector2(10.5, 5.5)), "heroi_t"), false)
	check("parede entre os dois: cobertura total", g.cover_between(hero, gob), TerrainMap.COVER_TOTAL)
	check("parede entre os dois: não se enxergam", g.sees(hero, gob), false)
	var bow := {"name": "Arco", "ranged": true, "range_m": [24.0, 96.0], "to_hit": 5, "damage": "1d6"}
	check("ataque à distância sem linha de visão é recusado", g.cb.attack_range_error(hero, bow, gob).contains("linha de visão"), true)
	var hits: Array = g.cb.in_area(hero, "sphere", 20, g.from_m(Vector2(9.4, 5.5)), false)
	check("explosão não atravessa parede", hits.any(func(c): return c["id"] == "gob_t"), false)
	check("explosão pega quem está do mesmo lado", hits.any(func(c): return c["id"] == "heroi_t"), true)
	var plan: Dictionary = g.plan_path(hero, g.from_m(Vector2(15.5, 3.5)))
	check("plano de caminho contorna a parede", float(plan.get("cost", 0.0)) > 20.0, true)
	g.in_combat = true
	g.order = ["heroi_t", "gob_t"]
	g.turn_index = 0
	g.turns = {}
	g._new_turn(hero)
	check("andar para dentro da parede é recusado", g.move_token("heroi_t", g.from_m(Vector2(10.5, 5.5))), "Ali não dá para pisar.")
	check("longe pelo caminho, mesmo perto em linha reta", g.move_token("heroi_t", g.from_m(Vector2(12.5, 5.5))).begins_with("Longe demais"), true)
	# Com a parede tirada, o mesmo ataque vale e a cobertura some
	g.terrain = TerrainMap.blank(32, 18)
	check("sem parede: sem cobertura", g.cover_between(hero, gob), TerrainMap.COVER_NONE)
	g.terrain.set_at(12, 5, TerrainMap.LOW)
	check("caixote no meio: meia cobertura no ataque", g.cover_between(hero, gob), TerrainMap.COVER_HALF)
	# Exploração: bando atrás da parede não nota o grupo; sem parede, nota
	g.in_combat = false
	g.terrain = _wall_column(10, 15, 16)
	var grp_t := {"id": "gt", "pos": g.from_m(Vector2(13.5, 5.5)), "radius_m": 5.5, "intro": "", "triggered": false,
		"monsters": [{"id": "mt", "monster_id": gob.get("monster_id", "goblin_warrior"), "pos": [13.5 / 32.0, 5.5 / 18.0]}]}
	g.groups = [grp_t]
	check("bando atrás da parede não nota quem passa", g.ex._trigger_at(g.from_m(Vector2(9.2, 5.5))).is_empty(), true)
	g.terrain = TerrainMap.blank(32, 18)
	check("sem parede o bando nota", g.ex._trigger_at(g.from_m(Vector2(9.2, 5.5))).is_empty(), false)
	g.terrain = _wall_column(10, 15, 16)
	g.pois = [{"id": "pt", "name": "Altar", "kind": "mark", "pos": g.from_m(Vector2(12.5, 5.5)), "required": true, "text": "", "loot": {}, "found": false, "sensed": false, "taken": false}]
	g.ex._sense_from(g.from_m(Vector2(9.2, 5.5)))
	check("ponto atrás da parede: pressentido, mas sem nome", [g.pois[0]["sensed"], g.pois[0]["found"]], [true, false])
	g.seen = PackedByteArray()
	g.update_vision()
	var ci: int = 5 * int(g.terrain.w) + 15
	check("névoa: o outro lado da parede não foi visto", g.seen[ci], 0)

	for k in keep:
		g.set(k, keep[k])
	print("== terreno: %d ok, %d falhas" % [passes - p0, fails - f0])
