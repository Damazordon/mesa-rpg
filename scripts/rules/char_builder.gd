class_name CharBuilder
extends RefCounted
## Monta a ficha completa de um personagem do SRD 5.2.1 a partir das escolhas da criação.
## A ficha é recalculada inteira a cada mudança (subida de nível, troca de equipamento).
##
## Escolhas (o que a tela de criação salva):
## {
##   name, player, color, alignment, profile{},
##   classes: [{class_id, level, subclass_id}],      # a primeira é a classe inicial
##   species_id, species_choice: {lineage, ancestry},
##   background_id,
##   base_scores: {str..cha},  method: "standard" | "point_buy" | "roll",
##   bg_bonus: {ab: +2/+1},
##   skills: [...]  (da classe e extras), expertise: [...],
##   equipment_option: "A"|"B", bg_equipment_option: "A"|"B", equipment_extra: [{item, qty}],
##   cantrips: [...], spells: [...]  (preparadas),
##   options: {fighting_style, divine_order, primal_order, weapon_masteries[], metamagic[],
##             invocations[], hunters_prey, blessed_strikes, elemental_fury, elemental_affinity,
##             land_type, beast_forms[], keen_senses, skillful, versatile_feat, magic_initiate{}},
##   feats: [{id, level, scores{}}],     # ASI e talentos ganhos nos níveis 4, 8...
##   hp_rolls: [],                         # vazio = média fixa
## }

const CASTER := {
	"bard": ["cha", "full"], "cleric": ["wis", "full"], "druid": ["wis", "full"],
	"sorcerer": ["cha", "full"], "wizard": ["int", "full"], "paladin": ["cha", "half"],
	"ranger": ["wis", "half"], "warlock": ["cha", "pact"],
}

## Tabela de espaços do conjurador multiclasse (nível de conjurador -> espaços 1..9).
const MULTICLASS_SLOTS := [
	[], [2], [3], [4, 2], [4, 3], [4, 3, 2], [4, 3, 3], [4, 3, 3, 1], [4, 3, 3, 2],
	[4, 3, 3, 3, 1], [4, 3, 3, 3, 2], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1],
	[4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1],
	[4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1, 1], [4, 3, 3, 3, 3, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 3, 2, 2, 1, 1],
]

const ASI_LEVELS := {"fighter": [4, 6, 8, 12, 14, 16], "rogue": [4, 8, 10, 12, 16]}


static func level_of(ch: Dictionary) -> int:
	var t := 0
	for k in ch.get("classes", []):
		t += int(k["level"])
	return maxi(1, t)


static func class_level(ch: Dictionary, class_id: String) -> int:
	for k in ch.get("classes", []):
		if k["class_id"] == class_id:
			return int(k["level"])
	return 0


static func subclass_of(ch: Dictionary, class_id: String) -> String:
	for k in ch.get("classes", []):
		if k["class_id"] == class_id:
			return str(k.get("subclass_id", ""))
	return ""


## Níveis da classe em que se ganha Aumento de Atributo ou talento.
static func asi_levels(class_id: String) -> Array:
	var lv: Array = ASI_LEVELS.get(class_id, [4, 8, 12, 16])
	return lv + [19]


# ---------------------------------------------------------------- montagem

static func build(ch: Dictionary) -> Dictionary:
	var c := {
		"id": ch.get("id", ch.get("name", "pc").to_lower().replace(" ", "_")),
		"kind": "pc", "name": ch.get("name", "Sem nome"), "player": ch.get("player", ""),
		"color": ch.get("color", "#7aa"), "side": "party", "choices": ch.duplicate(true),
		"profile": ch.get("profile", {}), "alignment": ch.get("alignment", ""),
		"conditions": [], "effects": [], "exhaustion": 0, "temp_hp": 0,
		"death": {"success": 0, "fail": 0, "stable": false, "dead": false},
		"traits": {}, "resources": {}, "slots": {}, "pact": {}, "features": [],
		"skill_prof": [], "expertise": [], "save_prof": [], "resist": [], "immune": [], "vuln": [],
		"cond_immune": [], "languages": ["common"], "tool_prof": [], "inventory": [], "coins": {},
		"xp": int(ch.get("xp", 0)), "heroic_inspiration": false,
	}
	var level := level_of(ch)
	c["level"] = level
	# A experiência nunca fica abaixo do mínimo do próprio nível. Sem isto, um personagem que
	# começa no nível 3 fica com 0 XP e a faixa de experiência nunca alcança o nível seguinte
	# (era o caso dos grupos de exemplo e de qualquer ficha salva antes da tela de sala).
	c["xp"] = maxi(int(c["xp"]), Srd.xp_for_level(level))
	c["pb"] = Srd.proficiency(level)
	var first: Dictionary = ch["classes"][0]
	var cls: Dictionary = Srd.classes[first["class_id"]]
	c["class_id"] = first["class_id"]
	c["subclass_id"] = first.get("subclass_id", "")
	c["class"] = _class_line(ch)
	var sp: Dictionary = Srd.species.get(ch.get("species_id", "human"), {})
	c["species_id"] = sp.get("id", "human")
	c["species"] = Srd.label("species", c["species_id"])
	c["background_id"] = ch.get("background_id", "")

	_scores(c, ch)
	c["save_prof"] = cls.get("saves", []).duplicate()
	_skills(c, ch)
	_species(c, ch, sp)
	_class_features(c, ch)
	_feats(c, ch)
	_equipment(c, ch)
	_hp(c, ch)
	_spellcasting(c, ch)
	_attacks(c)
	c["hp"] = c["hp_max"]
	c["hit_dice"] = _hit_dice(ch)
	return c


static func _class_line(ch: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in ch["classes"]:
		parts.append("%s %d" % [Srd.label("class", k["class_id"]), int(k["level"])])
	return " / ".join(parts)


static func _scores(c: Dictionary, ch: Dictionary) -> void:
	var s := {}
	for ab in Rules.ABILITIES:
		s[ab] = int(ch.get("base_scores", {}).get(ab, 10)) + int(ch.get("bg_bonus", {}).get(ab, 0))
	for f in ch.get("feats", []):
		for ab in f.get("scores", {}):
			s[ab] = int(s[ab]) + int(f["scores"][ab])
	var cap := 20
	for ab in s:
		s[ab] = mini(int(s[ab]), cap if int(ch.get("epic_cap", 0)) == 0 else 30)
	c["scores"] = s


static func _skills(c: Dictionary, ch: Dictionary) -> void:
	var bg: Dictionary = Srd.backgrounds.get(ch.get("background_id", ""), {})
	var sk: Array = []
	for s in bg.get("skills", []) + ch.get("skills", []):
		if not s in sk:
			sk.append(s)
	c["skill_prof"] = sk
	c["expertise"] = ch.get("expertise", []).duplicate()
	if bg.get("tool", "") != "":
		c["tool_prof"].append(bg["tool"])


static func _species(c: Dictionary, ch: Dictionary, sp: Dictionary) -> void:
	var t: Dictionary = c["traits"]
	var choice: Dictionary = ch.get("species_choice", {})
	var level: int = c["level"]
	c["speed_ft"] = int(sp.get("speed_ft", 30))
	c["darkvision_ft"] = int(sp.get("darkvision_ft", 0))
	c["size"] = "small" if str(sp.get("size", "")).begins_with("Small") or (sp.get("id") in ["gnome", "halfling"]) else "medium"
	if str(sp.get("size", "")).contains("Small or Medium"):
		c["size"] = str(choice.get("size", "medium"))
	for tr in sp.get("traits", []):
		var skey := "%s:%s" % [sp.get("id", ""), tr["id"]]
		c["features"].append({"id": tr["id"], "name": Srd.label("feature", tr["id"], tr["name"]),
			"source": c["species"], "text": Srd.text("feature", skey, Srd.text("feature", tr["id"], tr["text"])), "level": 1,
			"translated": Srd.is_translated("feature", skey) or Srd.is_translated("feature", tr["id"])})
	match sp.get("id", ""):
		"dragonborn":
			var anc := str(choice.get("ancestry", "red"))
			var dtype := str({"black": "acid", "blue": "lightning", "brass": "fire", "bronze": "lightning",
				"copper": "acid", "gold": "fire", "green": "poison", "red": "fire", "silver": "cold",
				"white": "cold"}.get(anc, "fire"))
			c["resist"].append(dtype)
			t["breath_weapon"] = {"dtype": dtype, "dice": "%dd10" % _tier(level)}
			_res(c, "breath_weapon", "Arma de Sopro", c["pb"], "long")
		"dwarf":
			c["resist"].append("poison")
			t["dwarven_resilience"] = true
			t["hp_per_level"] = int(t.get("hp_per_level", 0)) + 1
		"elf":
			t["fey_ancestry"] = true
			var lin := str(choice.get("lineage", "high"))
			if lin == "drow":
				c["darkvision_ft"] = 120
			elif lin == "wood":
				c["speed_ft"] = 35
			var ks := str(choice.get("keen_senses", "perception"))
			if not ks in c["skill_prof"]:
				c["skill_prof"].append(ks)
			var lin_cantrip := {"drow": "dancing_lights", "high": "prestidigitation", "wood": "druidcraft"}
			t["species_cantrips"] = [lin_cantrip.get(lin, "")]
			t["species_spells"] = {"drow": [["faerie_fire", 3], ["darkness", 5]], "high": [["detect_magic", 3], ["misty_step", 5]],
				"wood": [["longstrider", 3], ["pass_without_trace", 5]]}.get(lin, [])
		"gnome":
			t["gnomish_cunning"] = true
			if choice.get("lineage", "rock") == "forest":
				t["species_cantrips"] = ["minor_illusion"]
				t["species_spells"] = [["speak_with_animals", 1]]
			else:
				t["species_cantrips"] = ["mending", "prestidigitation"]
		"goliath":
			var g := str(choice.get("ancestry", "stone"))
			t["giant_ancestry"] = g
			_res(c, "giant_ancestry", "Ancestralidade Gigante", c["pb"], "long")
		"halfling":
			t["brave"] = true
			t["halfling_luck"] = true
		"human":
			c["heroic_inspiration"] = true
			t["resourceful"] = true
			var skl := str(choice.get("skillful", ""))
			if skl != "" and not skl in c["skill_prof"]:
				c["skill_prof"].append(skl)
		"orc":
			t["relentless_endurance"] = true
			_res(c, "relentless_endurance", "Resistência Implacável", 1, "long")
			_res(c, "adrenaline_rush", "Fúria de Adrenalina", c["pb"], "short")
		"tiefling":
			var leg := str(choice.get("lineage", "infernal"))
			c["resist"].append({"abyssal": "poison", "chthonic": "necrotic", "infernal": "fire"}.get(leg, "fire"))
			t["species_cantrips"] = [{"abyssal": "poison_spray", "chthonic": "chill_touch", "infernal": "fire_bolt"}.get(leg, "fire_bolt"), "thaumaturgy"]
			t["species_spells"] = {"abyssal": [["ray_of_sickness", 3], ["hold_person", 5]], "chthonic": [["false_life", 3], ["ray_of_enfeeblement", 5]],
				"infernal": [["hellish_rebuke", 3], ["darkness", 5]]}.get(leg, [])


static func _tier(level: int) -> int:
	if level >= 17:
		return 4
	if level >= 11:
		return 3
	if level >= 5:
		return 2
	return 1


static func _res(c: Dictionary, rid: String, name: String, mx: int, recharge: String) -> void:
	c["resources"][rid] = {"name": name, "max": mx, "left": mx, "recharge": recharge}


## Características de classe e subclasse até o nível atual, com os efeitos automatizados.
static func _class_features(c: Dictionary, ch: Dictionary) -> void:
	var t: Dictionary = c["traits"]
	var o: Dictionary = ch.get("options", {})
	var extra_attacks := 0
	for k in ch["classes"]:
		var cid: String = k["class_id"]
		var lv := int(k["level"])
		var cls: Dictionary = Srd.classes[cid]
		var sub_id := str(k.get("subclass_id", ""))
		for f in cls["features"]:
			if int(f["level"]) <= lv and not _skip_feature(f["id"]):
				var key := "%s:%s" % [cid, f["id"]]
				c["features"].append({"id": f["id"], "name": Srd.label("feature", f["id"], f["name"]),
					"source": Srd.label("class", cid), "level": f["level"],
					"text": Srd.text("feature", key, Srd.text("feature", f["id"], f["text"])),
					"translated": Srd.is_translated("feature", key) or Srd.is_translated("feature", f["id"])})
		for s in cls["subclasses"]:
			if s["id"] == sub_id:
				for f in s["features"]:
					if int(f["level"]) <= lv:
						c["features"].append({"id": f["id"], "name": Srd.label("feature", f["id"], f["name"]),
							"source": Srd.label("subclass", sub_id, s["name"]), "level": f["level"],
							"text": Srd.text("feature", f["id"], f["text"]), "translated": Srd.is_translated("feature", f["id"])})
		match cid:
			"barbarian":
				_res(c, "rages", "Fúria", Srd.class_value(cid, lv, "rages"), "long_one_short")
				t["rage_damage"] = Srd.class_value(cid, lv, "rage_damage")
				t["unarmored_defense"] = "con"
				if lv >= 2:
					t["danger_sense"] = true
					t["reckless_attack"] = true
				if lv >= 5:
					extra_attacks = maxi(extra_attacks, 1)
					t["fast_movement"] = true
				if lv >= 7:
					t["feral_instinct"] = true
				if lv >= 9:
					t["brutal_strike"] = "1d10" if lv < 17 else "2d10"
				if lv >= 11:
					t["relentless_rage"] = true
				if lv >= 15:
					t["persistent_rage"] = true
				if lv >= 18:
					t["indomitable_might"] = true
				if lv >= 20:
					t["primal_champion"] = true
				if sub_id == "path_of_the_berserker":
					t["frenzy"] = true
					if lv >= 6:
						t["mindless_rage"] = true
				t["masteries_n"] = int(t.get("masteries_n", 0)) + Srd.class_value(cid, lv, "weapon_mastery")
			"bard":
				_res(c, "bardic_inspiration", "Inspiração de Bardo", maxi(1, Rules.mod(int(c["scores"]["cha"]))), "short" if lv >= 5 else "long")
				t["bardic_die"] = "1d%d" % Srd.class_value(cid, lv, "bardic_die")
				if lv >= 2:
					t["jack_of_all_trades"] = true
				if sub_id == "college_of_lore" and lv >= 3:
					t["cutting_words"] = true
			"cleric":
				if lv >= 2:
					_res(c, "channel_divinity", "Canalizar Divindade", Srd.class_value(cid, lv, "channel_divinity"), "long_one_short")
					t["divine_spark"] = "%dd8" % (1 + int(lv >= 7) + int(lv >= 13) + int(lv >= 18))
				if lv >= 5:
					t["sear_undead"] = true
				if lv >= 7:
					t["blessed_strikes"] = str(o.get("blessed_strikes", "divine_strike"))
				if lv >= 14:
					t["improved_blessed_strikes"] = true
				if o.get("divine_order", "") == "protector":
					t["martial_weapons"] = true
					t["heavy_armor"] = true
				elif o.get("divine_order", "") == "thaumaturge":
					t["thaumaturge"] = true
				if sub_id == "life_domain":
					t["disciple_of_life"] = true
					if lv >= 6:
						t["blessed_healer"] = true
					if lv >= 17:
						t["supreme_healing"] = true
			"druid":
				if lv >= 2:
					_res(c, "wild_shape", "Forma Selvagem", Srd.class_value(cid, lv, "wild_shape"), "long_one_short")
					t["beast_forms"] = o.get("beast_forms", ["wolf", "rat", "spider", "riding_horse"])
					t["beast_cr"] = "1/4" if lv < 4 else ("1/2" if lv < 8 else "1")
				if lv >= 7:
					t["elemental_fury"] = str(o.get("elemental_fury", "primal_strike"))
				if o.get("primal_order", "") == "warden":
					t["martial_weapons"] = true
					t["medium_armor"] = true
				elif o.get("primal_order", "") == "magician":
					t["magician"] = true
				if sub_id == "circle_of_the_land":
					t["lands_aid"] = "%dd6" % (2 + int(lv >= 10) + int(lv >= 14))
			"fighter":
				_res(c, "second_wind", "Retomar o Fôlego", Srd.class_value(cid, lv, "second_wind"), "long_one_short")
				t["fighter_level"] = lv
				if lv >= 2:
					_res(c, "action_surge", "Surto de Ação", 2 if lv >= 17 else 1, "short")
					t["tactical_mind"] = true
				if lv >= 5:
					extra_attacks = maxi(extra_attacks, 1)
					t["tactical_shift"] = true
				if lv >= 9:
					_res(c, "indomitable", "Indomável", 1 + int(lv >= 13) + int(lv >= 17), "long")
				if lv >= 11:
					extra_attacks = maxi(extra_attacks, 2)
				if lv >= 13:
					t["studied_attacks"] = true
				if lv >= 20:
					extra_attacks = maxi(extra_attacks, 3)
				if sub_id == "champion":
					t["crit_range"] = 18 if lv >= 15 else 19
					t["remarkable_athlete"] = true
					if lv >= 18:
						t["survivor"] = true
				t["masteries_n"] = int(t.get("masteries_n", 0)) + Srd.class_value(cid, lv, "weapon_mastery")
			"monk":
				t["martial_arts"] = Srd.class_text(cid, lv, "martial_arts").to_lower()
				t["unarmored_defense"] = "wis"
				if lv >= 2:
					_res(c, "focus_points", "Pontos de Foco", Srd.class_value(cid, lv, "focus_points"), "short")
					t["unarmored_movement"] = Srd.class_value(cid, lv, "unarmored_movement")
					_res(c, "uncanny_metabolism", "Metabolismo Sobrenatural", 1, "long")
				if lv >= 3:
					t["deflect_attacks"] = true
				if lv >= 5:
					extra_attacks = maxi(extra_attacks, 1)
					t["stunning_strike"] = true
				if lv >= 6:
					t["empowered_strikes"] = true
				if lv >= 7:
					t["evasion"] = true
				if sub_id == "warrior_of_the_open_hand":
					t["open_hand"] = true
					if lv >= 6:
						_res(c, "wholeness_of_body", "Plenitude do Corpo", maxi(1, Rules.mod(int(c["scores"]["wis"]))), "long")
			"paladin":
				_res(c, "lay_on_hands", "Cura pelas Mãos", 5 * lv, "long")
				if lv >= 2:
					_res(c, "free_smite", "Destruição Divina gratuita", 1, "long")
				if lv >= 3:
					_res(c, "channel_divinity_paladin", "Canalizar Divindade", 2 + int(lv >= 11), "long_one_short")
				if lv >= 5:
					extra_attacks = maxi(extra_attacks, 1)
				if lv >= 6:
					t["aura_of_protection"] = 30 if lv >= 18 else 10
				if lv >= 10:
					t["aura_of_courage"] = true
				if lv >= 11:
					t["radiant_strikes"] = true
				if sub_id == "oath_of_devotion":
					t["sacred_weapon"] = true
				t["masteries_n"] = int(t.get("masteries_n", 0)) + 2
			"ranger":
				_res(c, "favored_enemy", "Inimigo Favorito", Srd.class_value(cid, lv, "favored_enemy"), "long")
				if lv >= 5:
					extra_attacks = maxi(extra_attacks, 1)
				if lv >= 6:
					t["roving"] = true
				if lv >= 7 and sub_id == "hunter":
					t["defensive_tactics"] = true
				if sub_id == "hunter":
					t["hunters_prey"] = str(o.get("hunters_prey", "colossus_slayer"))
				t["masteries_n"] = int(t.get("masteries_n", 0)) + 2
			"rogue":
				t["sneak_attack"] = Srd.class_text(cid, lv, "sneak_attack").to_lower()
				if lv >= 2:
					t["cunning_action"] = true
				if lv >= 3:
					t["steady_aim"] = true
				if lv >= 5:
					t["cunning_strike"] = true
					t["uncanny_dodge"] = true
				if lv >= 7:
					t["evasion"] = true
					t["reliable_talent"] = true
				if lv >= 15 and not "wis" in c["save_prof"]:
					c["save_prof"].append("wis")
				if lv >= 18:
					t["elusive"] = true
				if sub_id == "thief":
					t["fast_hands"] = true
				t["masteries_n"] = int(t.get("masteries_n", 0)) + 2
			"sorcerer":
				_res(c, "innate_sorcery", "Feitiçaria Inata", 2, "long")
				if lv >= 2:
					_res(c, "sorcery_points", "Pontos de Feitiçaria", Srd.class_value(cid, lv, "sorcery_points"), "long")
					t["metamagic"] = o.get("metamagic", ["quickened_spell", "twinned_spell"])
					_option_features(c, "sorcerer", "metamagic", t["metamagic"])
				if sub_id == "draconic_sorcery" and lv >= 3:
					t["draconic_resilience"] = true
					t["hp_bonus"] = int(t.get("hp_bonus", 0)) + lv
					if lv >= 6:
						var aff := str(o.get("elemental_affinity", "fire"))
						t["elemental_affinity"] = aff
						if not aff in c["resist"]:
							c["resist"].append(aff)
			"warlock":
				t["invocations"] = o.get("invocations", ["pact_of_the_tome"]) if lv >= 1 else []
				_option_features(c, "warlock", "eldritch_invocation", t["invocations"])
				if "agonizing_blast" in t["invocations"]:
					t["agonizing_blast"] = true
				if "repelling_blast" in t["invocations"]:
					t["repelling_blast"] = true
				if "armor_of_shadows" in t["invocations"]:
					t["armor_of_shadows"] = true
				if "eldritch_mind" in t["invocations"]:
					t["eldritch_mind"] = true
				if "devils_sight" in t["invocations"]:
					t["devils_sight"] = true
				if "pact_of_the_blade" in t["invocations"]:
					t["pact_of_the_blade"] = true
				if "thirsting_blade" in t["invocations"]:
					extra_attacks = maxi(extra_attacks, 1)
				if lv >= 2:
					_res(c, "magical_cunning", "Astúcia Mágica", 1, "long")
				if sub_id == "fiend_patron" and lv >= 3:
					t["dark_ones_blessing"] = true
					if lv >= 6:
						_res(c, "dark_ones_luck", "Sorte do Sombrio", maxi(1, Rules.mod(int(c["scores"]["cha"]))), "long")
			"wizard":
				_res(c, "arcane_recovery", "Recuperação Arcana", 1, "long")
				t["wizard_level"] = lv
				if sub_id == "evoker":
					if lv >= 3:
						t["potent_cantrip"] = true
					if lv >= 6:
						t["sculpt_spells"] = true
					if lv >= 10:
						t["empowered_evocation"] = true
	t["extra_attacks"] = extra_attacks
	t["masteries"] = o.get("weapon_masteries", [])
	if o.has("fighting_style"):
		_fighting_style(c, str(o["fighting_style"]))
	if o.has("fighting_style_2"):
		_fighting_style(c, str(o["fighting_style_2"]))


static func _skip_feature(fid: String) -> bool:
	return fid in ["ability_score_improvement", "epic_boon"]


static func _fighting_style(c: Dictionary, fs: String) -> void:
	var t: Dictionary = c["traits"]
	match fs:
		"archery":
			t["archery"] = true
		"defense":
			t["defense_style"] = true
		"great_weapon_fighting":
			t["gwf"] = true
		"two_weapon_fighting":
			t["twf"] = true
	var f: Dictionary = Srd.feats.get(fs, {})
	if not f.is_empty():
		c["features"].append({"id": fs, "name": Srd.label("feat", fs, f["name"]), "source": "Estilo de Luta",
			"level": 1, "text": Srd.text("feat", fs, f["text"]), "translated": Srd.is_translated("feat", fs)})


static func _feats(c: Dictionary, ch: Dictionary) -> void:
	var t: Dictionary = c["traits"]
	var feat_ids: Array = []
	var bg: Dictionary = Srd.backgrounds.get(ch.get("background_id", ""), {})
	if bg.get("feat", "") != "":
		feat_ids.append(bg["feat"])
	var vf := str(ch.get("options", {}).get("versatile_feat", ""))
	if c["species_id"] == "human" and vf != "":
		feat_ids.append(vf)
	for f in ch.get("feats", []):
		feat_ids.append(f["id"])
	for fid in feat_ids:
		var f: Dictionary = Srd.feats.get(fid, {})
		if f.is_empty() or fid == "ability_score_improvement":
			continue
		c["features"].append({"id": fid, "name": Srd.label("feat", fid, f["name"]), "source": "Talento",
			"level": 1, "text": Srd.text("feat", fid, f["text"]), "translated": Srd.is_translated("feat", fid)})
		match fid:
			"alert":
				t["alert"] = true
			"savage_attacker":
				t["savage_attacker"] = true
			"grappler":
				t["grappler"] = true
			"archery", "defense", "great_weapon_fighting", "two_weapon_fighting":
				_fighting_style(c, fid)
			"boon_of_combat_prowess":
				t["peerless_aim"] = true
			"boon_of_fate":
				t["boon_of_fate"] = true
			"boon_of_irresistible_offense":
				t["irresistible_offense"] = true
	t["feats"] = feat_ids


# ---------------------------------------------------------------- equipamento

static func _equipment(c: Dictionary, ch: Dictionary) -> void:
	var first: Dictionary = Srd.classes[ch["classes"][0]["class_id"]]
	var items: Array = []
	var gp := 0
	for opt in first.get("equipment", []):
		if opt["option"] == ch.get("equipment_option", "A"):
			items += opt["items"]
			gp += int(opt["gp"])
	var bg: Dictionary = Srd.backgrounds.get(ch.get("background_id", ""), {})
	for opt in bg.get("equipment", []):
		if opt["option"] == ch.get("bg_equipment_option", "A"):
			items += opt["items"]
			gp += int(opt["gp"])
	items += ch.get("equipment_extra", [])
	var inv: Array = []
	for it in items:
		var found := Srd.find_item(str(it["item"]))
		inv.append({"id": found.get("id", ""), "name": Srd.label(Srd.item_kind(found), found["id"], found["name"]) if not found.is_empty() else str(it["item"]),
			"qty": int(it.get("qty", 1)), "kind": Srd.item_kind(found) if not found.is_empty() else "gear"})
	c["inventory"] = inv
	c["coins"] = {"gp": gp + int(ch.get("gold_extra", 0))}
	# Veste a melhor armadura em que tem treino e usa escudo se puder.
	var best_ac := -1
	c["armor_id"] = ""
	c["shield"] = false
	for it in inv:
		if it["kind"] != "armor":
			continue
		var a: Dictionary = Srd.armor[it["id"]]
		if a["category"] == "shield":
			if armor_trained(c, "shield"):
				c["shield"] = true
			continue
		if not armor_trained(c, a["category"]):
			continue
		var v := int(a["ac_base"])
		if v > best_ac:
			best_ac = v
			c["armor_id"] = a["id"]
	if ch.has("armor_override"):
		c["armor_id"] = ch["armor_override"]
	c["weapons"] = inv.filter(func(it): return it["kind"] == "weapon").map(func(it): return it["id"])


static func armor_trained(c: Dictionary, category: String) -> bool:
	var txt := ""
	for k in c["choices"]["classes"]:
		var cls: Dictionary = Srd.classes[k["class_id"]]
		txt += " " + (cls["armor"] if k == c["choices"]["classes"][0] else _multiclass_armor(k["class_id"]))
	txt = txt.to_lower()
	match category:
		"light":
			return txt.contains("light") or Rules.tv(c, "medium_armor") or Rules.tv(c, "heavy_armor")
		"medium":
			return txt.contains("medium") or Rules.tv(c, "medium_armor") or Rules.tv(c, "heavy_armor")
		"heavy":
			return txt.contains("heavy") or Rules.tv(c, "heavy_armor")
		"shield":
			return txt.contains("shield")
	return false


static func _multiclass_armor(class_id: String) -> String:
	var mc: String = Srd.classes[class_id].get("multiclass", "")
	return mc


static func weapon_proficient(c: Dictionary, w: Dictionary) -> bool:
	if w.get("category", "simple") == "simple":
		return true
	if Rules.tv(c, "martial_weapons"):
		return true
	for k in c["choices"]["classes"]:
		var txt: String = Srd.classes[k["class_id"]]["weapons"]
		if k != c["choices"]["classes"][0]:
			txt = Srd.classes[k["class_id"]].get("multiclass", "")
		if txt.contains("Martial weapons that have the Finesse or Light"):
			if "finesse" in w["properties"] or "light" in w["properties"]:
				return true
		elif txt.contains("Martial weapons that have the Light"):
			if "light" in w["properties"]:
				return true
		elif txt.contains("Martial weapons") or txt.contains("Martial Weapons"):
			return true
	return false


# ---------------------------------------------------------------- pontos de vida

static func _hp(c: Dictionary, ch: Dictionary) -> void:
	var con := Rules.mod(int(c["scores"]["con"]))
	var rolls: Array = ch.get("hp_rolls", [])
	var total := 0
	var idx := 0
	var first := true
	for k in ch["classes"]:
		var hd := int(Srd.classes[k["class_id"]]["hit_die"])
		for i in int(k["level"]):
			var gain: int
			if first:
				gain = hd
				first = false
			elif idx < rolls.size():
				gain = int(rolls[idx])
				idx += 1
			else:
				gain = hd / 2 + 1
			total += maxi(1, gain + con)
	total += int(Rules.tv(c, "hp_per_level", 0)) * int(c["level"])
	total += int(Rules.tv(c, "hp_bonus", 0))
	c["hp_max"] = total


static func _hit_dice(ch: Dictionary) -> Dictionary:
	var out := {}
	for k in ch["classes"]:
		var die := "d%d" % int(Srd.classes[k["class_id"]]["hit_die"])
		out[die] = {"max": int(out.get(die, {}).get("max", 0)) + int(k["level"]), "left": 0}
	for die in out:
		out[die]["left"] = out[die]["max"]
	return out


# ---------------------------------------------------------------- magia

static func _spellcasting(c: Dictionary, ch: Dictionary) -> void:
	var casters: Array = []
	var caster_level := 0.0
	for k in ch["classes"]:
		var cid: String = k["class_id"]
		if CASTER.has(cid):
			casters.append(k)
			match CASTER[cid][1]:
				"full":
					caster_level += int(k["level"])
				"half":
					caster_level += ceili(int(k["level"]) / 2.0)
	if casters.is_empty() and ch.get("cantrips", []).is_empty() and Rules.tv(c, "species_cantrips", []).is_empty():
		return
	var main: Dictionary = casters[0] if not casters.is_empty() else {}
	var cid_main: String = main.get("class_id", "")
	var ability: String = CASTER[cid_main][0] if cid_main != "" else str(ch.get("options", {}).get("magic_initiate", {}).get("ability", ch.get("species_choice", {}).get("ability", "cha")))
	var sc := {"ability": ability, "class_id": cid_main, "cantrips": ch.get("cantrips", []).duplicate(),
		"prepared": ch.get("spells", []).duplicate(), "always": [], "free": {}}
	# Espaços
	var non_pact := casters.filter(func(k): return CASTER[k["class_id"]][1] != "pact")
	if non_pact.size() == 1 and casters.size() == 1:
		var k: Dictionary = non_pact[0]
		for l in range(1, 10):
			var n := Srd.class_value(k["class_id"], int(k["level"]), "slot_%d" % l)
			if n > 0:
				c["slots"][str(l)] = {"max": n, "left": n}
	elif non_pact.size() > 0:
		var row: Array = MULTICLASS_SLOTS[clampi(int(caster_level), 0, 20)]
		for i in row.size():
			c["slots"][str(i + 1)] = {"max": row[i], "left": row[i]}
	for k in casters:
		if CASTER[k["class_id"]][1] == "pact":
			var lv := int(k["level"])
			var n := Srd.class_value("warlock", lv, "spell_slots")
			c["pact"] = {"level": Srd.class_value("warlock", lv, "slot_level"), "max": n, "left": n}
	# Magias sempre preparadas
	var always: Array = sc["always"]
	var t: Dictionary = c["traits"]
	for sc_id in t.get("species_cantrips", []):
		if sc_id != "" and not sc_id in sc["cantrips"]:
			sc["cantrips"].append(sc_id)
	# Magias da linhagem (elfo, gnomo da floresta, tiefling): sempre preparadas, 1 uso grátis por descanso longo
	for pair in t.get("species_spells", []):
		if int(c["level"]) >= int(pair[1]) and Srd.spells.has(pair[0]):
			always.append(pair[0])
			var rid := "species_" + str(pair[0])
			var uses := Rules.pb(c) if pair[0] == "speak_with_animals" else 1
			_res(c, rid, Srd.label("spell", pair[0]) + " (linhagem)", uses, "long")
			sc["free"][pair[0]] = rid
	for k in ch["classes"]:
		var cid: String = k["class_id"]
		var lv := int(k["level"])
		if cid == "ranger":
			always.append("hunters_mark")
			sc["free"]["hunters_mark"] = "favored_enemy"
		if cid == "paladin" and lv >= 2:
			always.append("divine_smite")
			sc["free"]["divine_smite"] = "free_smite"
		if cid == "paladin" and lv >= 5:
			always.append("find_steed")
		var sub := str(k.get("subclass_id", ""))
		for s in Srd.classes[cid]["subclasses"]:
			if s["id"] != sub:
				continue
			for f in s["features"]:
				if not f.has("tables") or int(f["level"]) > lv:
					continue
				if not (f["id"].ends_with("_spells")):
					continue
				var tables: Array = f["tables"]
				var tbl: Array = tables[0]
				if f["id"] == "circle_of_the_land_spells":
					var land := str(ch.get("options", {}).get("land_type", "temperate"))
					var idx := ["arid", "polar", "temperate", "tropical"].find(land)
					tbl = tables[maxi(0, idx)]
				for row in tbl.slice(1):
					if int(row[0]) <= lv:
						for nm in str(row[1]).split(","):
							var sid := _spell_id(nm.strip_edges())
							if sid != "" and not sid in always:
								always.append(sid)
	var mi: Dictionary = ch.get("options", {}).get("magic_initiate", {})
	if not mi.is_empty():
		for cn in mi.get("cantrips", []):
			if not cn in sc["cantrips"]:
				sc["cantrips"].append(cn)
		if mi.get("spell", "") != "":
			always.append(mi["spell"])
			_res(c, "magic_initiate", "Iniciado em Magia", 1, "long")
			sc["free"][mi["spell"]] = "magic_initiate"
	c["spellcasting"] = sc


static func _spell_id(spell_name: String) -> String:
	var id := spell_name.to_lower().replace("'", "").replace("’", "")
	var re := RegEx.create_from_string("[^a-z0-9]+")
	id = re.sub(id, "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	return id if Srd.spells.has(id) else ""


## Todas as magias que o personagem pode conjurar agora.
static func castable_spells(c: Dictionary) -> Array:
	var sc: Dictionary = c.get("spellcasting", {})
	var out: Array = []
	for id in sc.get("cantrips", []) + sc.get("prepared", []) + sc.get("always", []):
		if Srd.spells.has(id) and not id in out:
			out.append(id)
	return out


# ---------------------------------------------------------------- ataques

static func _attacks(c: Dictionary) -> void:
	var out: Array = []
	var shield: bool = c.get("shield", false)
	for wid in c.get("weapons", []):
		if out.any(func(a): return a["weapon_id"] == wid):
			continue
		var w: Dictionary = Srd.weapons.get(wid, {})
		if w.is_empty():
			continue
		out.append(weapon_attack(c, w, false, shield))
		if "thrown" in w["properties"] and not w["ranged"]:
			out.append(weapon_attack(c, w, true, shield))
	out.append(unarmed_attack(c))
	c["attacks"] = out


## Monta o ataque com uma arma, já com bônus de acerto e dano.
static func weapon_attack(c: Dictionary, w: Dictionary, thrown := false, shield := false) -> Dictionary:
	var props: Array = w["properties"]
	var ab := "dex" if w["ranged"] else "str"
	var monk_w: bool = Rules.tv(c, "martial_arts", "") != "" and not w["ranged"] and (w["category"] == "simple" or "light" in props) and c.get("armor_id", "") == "" and not shield
	if "finesse" in props or monk_w:
		ab = "dex" if Rules.amod(c, "dex") >= Rules.amod(c, "str") else "str"
	var prof := weapon_proficient(c, w)
	var to_hit := Rules.amod(c, ab) + (Rules.pb(c) if prof else 0)
	if w["ranged"] and Rules.tv(c, "archery"):
		to_hit += 2
	var dice: String = w["damage"]
	var two_handed := false
	if w.has("versatile") and not shield:
		dice = w["versatile"]
		two_handed = true
	if "two_handed" in props:
		two_handed = true
	if monk_w:
		var ma: String = Rules.tv(c, "martial_arts", "1d6")
		if Rules.average(ma) > Rules.average(dice):
			dice = ma
	var mod := Rules.amod(c, ab)
	var reach_ft := 10 if "reach" in props else 5
	var a := {
		"id": w["id"] + ("_thrown" if thrown else ""), "weapon_id": w["id"],
		"name": Srd.label("weapon", w["id"], w["name"]) + (" (arremesso)" if thrown else ""),
		"kind": "weapon", "ability": ab, "to_hit": to_hit, "dice": dice, "mod": mod,
		"damage": "%s%+d" % [dice, mod] if mod != 0 else dice, "dtype": w["dtype"],
		"ranged": w["ranged"] or thrown, "reach_m": Rules.m(reach_ft),
		"range_m": [], "properties": props, "proficient": prof,
		"mastery": w["mastery"] if w["id"] in Rules.tv(c, "masteries", []) else "",
		"light": "light" in props, "finesse": "finesse" in props, "two_handed": two_handed,
		"heavy": "heavy" in props, "monk": monk_w,
	}
	if w["ranged"] or thrown:
		var rr: Array = w.get("range_ft", [20, 60])
		if thrown:
			for p in w.get("properties_text", []):
				var mm := RegEx.create_from_string("Range (\\d+)/(\\d+)").search(p)
				if mm:
					rr = [int(mm.get_string(1)), int(mm.get_string(2))]
		a["range_m"] = [Rules.m(rr[0]), Rules.m(rr[1])]
	return a


static func unarmed_attack(c: Dictionary) -> Dictionary:
	var ma: String = Rules.tv(c, "martial_arts", "")
	var ab := "str"
	if ma != "" and Rules.amod(c, "dex") > Rules.amod(c, "str"):
		ab = "dex"
	var mod := Rules.amod(c, ab)
	var dice := ma if ma != "" else "1"
	return {"id": "unarmed_strike", "weapon_id": "", "name": Srd.label("action", "unarmed_strike", "Golpe Desarmado"),
		"kind": "unarmed", "ability": ab, "to_hit": mod + Rules.pb(c), "dice": dice, "mod": mod,
		"damage": "%s%+d" % [dice, mod] if mod != 0 else dice, "dtype": "bludgeoning", "ranged": false,
		"reach_m": 1.5, "range_m": [], "properties": [], "proficient": true, "mastery": "",
		"light": false, "finesse": false, "two_handed": false, "heavy": false, "monk": ma != ""}


# ---------------------------------------------------------------- validação (tela de criação)

## Lista de problemas nas escolhas. Vazia = pode criar.
static func validate(ch: Dictionary) -> Array:
	var errs: Array = []
	if str(ch.get("name", "")).strip_edges() == "":
		errs.append("Dê um nome ao personagem.")
	if ch.get("classes", []).is_empty():
		errs.append("Escolha uma classe.")
		return errs
	var bonus: Dictionary = ch.get("bg_bonus", {})
	var vals: Array = bonus.values().map(func(v): return int(v))
	vals.sort()
	if not (vals == [1, 2] or vals == [1, 1, 1]):
		errs.append("Distribua +2 e +1, ou +1 em três atributos, entre os atributos do antecedente.")
	var bg: Dictionary = Srd.backgrounds.get(ch.get("background_id", ""), {})
	for ab in bonus:
		if not ab in bg.get("abilities", []):
			errs.append("O antecedente não permite aumentar %s." % Srd.ability_name(ab))
	var method := str(ch.get("method", "standard"))
	var base: Dictionary = ch.get("base_scores", {})
	if method == "standard":
		var arr: Array = base.values().map(func(v): return int(v))
		arr.sort()
		if arr != [8, 10, 12, 13, 14, 15]:
			errs.append("No conjunto padrão, use 15, 14, 13, 12, 10 e 8 uma vez cada.")
	elif method == "point_buy":
		var cost := 0
		for ab in base:
			var v := int(base[ab])
			if v < 8 or v > 15:
				errs.append("Na compra de pontos, cada atributo fica entre 8 e 15.")
				break
			cost += int(Srd.tables["point_buy"][str(v)])
		# A sala pode mudar o orçamento (ch["point_budget"]); o padrão do livro é 27.
		var budget := int(ch.get("point_budget", 27))
		if cost > budget:
			errs.append("A compra de pontos passou de %d (gastou %d)." % [budget, cost])
	var cls: Dictionary = Srd.classes[ch["classes"][0]["class_id"]]
	var need := int(cls["skills"]["choose"])
	var picked: Array = ch.get("skills", []).filter(func(s): return s in cls["skills"]["from"])
	if picked.size() < need:
		errs.append("Escolha %d perícia(s) da classe." % need)
	return errs


## Opções escolhidas (Metamagia, Invocações) entram na ficha como características.
static func _option_features(c: Dictionary, cid: String, group: String, picked: Array) -> void:
	for x in Srd.classes[cid].get("options", {}).get(group, []):
		if x["id"] in picked:
			c["features"].append({"id": x["id"], "name": Srd.label("feature", x["id"], x.get("name", x["id"])),
				"source": Srd.label("feature", "metamagic" if cid == "sorcerer" else "eldritch_invocations"), "level": 1,
				"text": Srd.text("feature", x["id"], x.get("text", "")), "translated": Srd.is_translated("feature", x["id"])})
