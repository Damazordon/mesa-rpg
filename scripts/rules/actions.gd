class_name Actions
extends RefCounted
## Lista do que a criatura da vez pode fazer agora, para a barra de ações e para a IA.
##
## Cada atividade:
## {id, name, group, cost, target, range_m, area{shape,size_ft,origin}, count, available, why,
##  sub, desc, kind: "attack"|"spell"|"feature", ref}
## group: attack, spell, action, bonus, special
## cost: action, magic, bonus, reaction, attack (um dos ataques da ação Atacar), free, move
## target: enemy, ally, creature, self, point, none


static func for_creature(g, c: Dictionary) -> Array:
	var out: Array = []
	var turn: Dictionary = g.turn_of(c)
	# ---------- ataques
	var atks: Array = c.get("form", {}).get("attacks", []) if not c.get("form", {}).is_empty() else c.get("attacks", [])
	for atk in atks:
		var a := {
			"id": "atk:" + str(atk["id"]), "name": atk["name"], "group": "attack", "cost": "attack",
			"target": "enemy", "range_m": _atk_range(atk), "kind": "attack", "ref": atk,
			"sub": "%+d, %s %s" % [int(atk.get("to_hit", 0)), atk.get("damage", ""), Srd.dtype_name(str(atk.get("dtype", "")))],
			"desc": _atk_desc(atk),
		}
		_avail(g, c, a)
		out.append(a)
	# Ataque com a segunda arma leve (Ação Bônus, ou parte do Atacar com Corte Rápido)
	var light_id: String = str(turn.get("light_attacked", ""))
	if light_id != "" and c.get("form", {}).is_empty():
		for atk in c.get("attacks", []):
			if atk.get("light", false) and atk["weapon_id"] != light_id and not atk.get("ranged", false):
				var off: Dictionary = atk.duplicate()
				off["offhand"] = true
				off["name"] = str(atk["name"]) + " (segunda arma)"
				var nick := false
				for a2 in c.get("attacks", []):
					if a2["weapon_id"] == light_id and a2.get("mastery", "") == "nick":
						nick = true
				var a := {"id": "atk:off_" + str(atk["id"]), "name": off["name"], "group": "bonus" if not nick else "attack",
					"cost": "free_nick" if nick and not turn.get("nick_used", false) else "bonus", "target": "enemy",
					"range_m": float(atk["reach_m"]), "kind": "attack", "ref": off, "sub": "sem modificador no dano" if not Rules.tv(c, "twf") else "com modificador",
					"desc": "Propriedade Leve: um ataque extra com outra arma leve."}
				_avail(g, c, a)
				out.append(a)
				break
	# ---------- magias
	if not c.get("spellcasting", {}).is_empty():
		var cast: Array = CharBuilder.castable_spells(c)
		cast.sort_custom(func(x, y): return _spell_key(x) < _spell_key(y))
		for sid in cast:
			out.append(spell_activity(g, c, sid))
	# ---------- ações padrão
	for std in [["dash", "Disparada", "action", "none"], ["disengage", "Desengajar", "action", "none"],
			["dodge", "Esquivar", "action", "none"], ["help", "Ajudar", "action", "enemy"],
			["hide", "Esconder", "action", "none"], ["ready", "Preparar ataque", "action", "none"],
			["grapple", "Agarrar", "attack", "enemy"], ["shove", "Derrubar/Empurrar", "attack", "enemy"]]:
		var a := {"id": "std:" + std[0], "name": Srd.label("action", std[0], std[1]), "group": "action", "cost": std[2],
			"target": std[3], "range_m": 1.5, "kind": "feature", "ref": std[0], "sub": "", "desc": Srd.text("glossary", std[0])}
		_avail(g, c, a)
		out.append(a)
	if Rules.has_condition(c, "prone"):
		var a := {"id": "std:stand_up", "name": "Levantar", "group": "action", "cost": "move", "target": "none", "kind": "feature", "ref": "stand_up",
			"sub": "metade do deslocamento", "desc": "Levantar de Caído custa metade do deslocamento."}
		a["available"] = float(turn.get("move_left", 0.0)) >= Rules.speed_m(c) / 2.0
		a["why"] = "" if a["available"] else "Sem deslocamento suficiente."
		out.append(a)
	if Rules.has_condition(c, "grappled"):
		var a := {"id": "std:escape_grapple", "name": "Escapar", "group": "action", "cost": "action", "target": "none", "kind": "feature", "ref": "escape_grapple", "sub": "Atletismo ou Acrobacia", "desc": ""}
		_avail(g, c, a)
		out.append(a)
	# ---------- características
	for f in _features(c):
		_avail(g, c, f)
		out.append(f)
	return out


static func _spell_key(sid: String) -> String:
	return "%d %s" % [int(Srd.spells[sid]["level"]), Srd.label("spell", sid)]


static func spell_activity(g, c: Dictionary, sid: String) -> Dictionary:
	var sp: Dictionary = Srd.spells[sid]
	var auto: Dictionary = sp.get("auto", {})
	var lvl: int = int(sp["level"])
	var cost: String = g.cb.spell_cost(sp)
	var target := str(auto.get("target", ""))
	if target == "":
		if auto.has("area"):
			target = "point"
		elif auto.get("kind", "") in ["heal", "buff"]:
			target = "ally"
		elif auto.get("kind", "") in ["attack", "save", "auto_hit", "mark"]:
			target = "enemy"
		elif sp.get("range", "").begins_with("Self"):
			target = "self"
		else:
			target = "creature"
	if auto.has("area") and auto.get("origin", "point") == "self":
		target = "direction" if auto["area"]["shape"] in ["cone", "line", "cube"] else "self"
	var area: Dictionary = auto.get("area", {}).duplicate()
	if not area.is_empty():
		area["origin"] = auto.get("origin", "point")
	var count := int(auto.get("targets", 1))
	if auto.has("rays"):
		count = int(auto["rays"])
	if auto.has("darts"):
		count = int(auto["darts"])
	var sub := "truque" if lvl == 0 else "nível %d" % lvl
	if auto.has("damage") and str(auto["damage"]) != "0":
		sub += ", " + g.cb.spell_damage_expr(c, sp, maxi(1, lvl))
	elif auto.has("heal"):
		sub += ", cura " + str(auto["heal"])
	if sp.get("concentration", false):
		sub += ", conc."
	var a := {
		"id": "spell:" + sid, "name": Srd.label("spell", sid), "group": "spell", "cost": cost,
		"target": target, "range_m": g.cb.spell_range_m(c, sp), "area": area, "count": count,
		"kind": "spell", "ref": sid, "level": lvl, "sub": sub, "school": sp.get("school", ""),
		"automated": auto.get("kind", "manual") != "manual",
		"desc": "%s\n%s\n\n%s" % [Srd.label("spell", sid), Srd.spell_meta(sid), Srd.spell_text(sid)],
	}
	var slot := Rules.lowest_slot(c, lvl) if lvl > 0 else 0
	var why: String = g.cb.can_cast(c, sid, slot)
	a["available"] = why == "" and g.is_my_turn(c) if g.in_combat else why == ""
	a["why"] = why
	a["slot"] = slot
	return a


static func _atk_range(atk: Dictionary) -> float:
	if atk.get("ranged", false):
		var rr: Array = atk.get("range_m", [])
		return float(rr[1]) if rr.size() == 2 else float(atk.get("range_single", 24.0))
	return float(atk.get("reach_m", 1.5))


static func _atk_desc(atk: Dictionary) -> String:
	var lines := PackedStringArray([str(atk["name"])])
	lines.append("Acerto %+d. Dano %s %s." % [int(atk.get("to_hit", 0)), atk.get("damage", ""), Srd.dtype_name(str(atk.get("dtype", "")))])
	if atk.get("ranged", false):
		var rr: Array = atk.get("range_m", [])
		if rr.size() == 2:
			lines.append("Alcance %s (até %s com desvantagem)." % [_m(float(rr[0])), _m(float(rr[1]))])
	else:
		lines.append("Corpo a corpo, alcance %s." % _m(float(atk.get("reach_m", 1.5))))
	if atk.get("mastery", "") != "":
		lines.append("Maestria: %s." % Srd.label("property", atk["mastery"]))
	if not atk.get("proficient", true):
		lines.append("Sem proficiência: não soma o bônus de proficiência.")
	return "\n".join(lines)


static func _m(v: float) -> String:
	return ("%.1f m" % v).replace(".", ",")


static func _f(id: String, name: String, group: String, cost: String, target: String, sub := "", range_m := 0.0, extra := {}) -> Dictionary:
	var d := {"id": "feat:" + id, "name": name, "group": group, "cost": cost, "target": target, "range_m": range_m,
		"kind": "feature", "ref": id, "sub": sub, "desc": Srd.text("feature", id)}
	d.merge(extra, true)
	return d


static func _features(c: Dictionary) -> Array:
	var out: Array = []
	var res: Dictionary = c.get("resources", {})
	var t: Dictionary = c.get("traits", {})
	var left := func(rid: String) -> String:
		return "%d/%d" % [int(res[rid]["left"]), int(res[rid]["max"])] if res.has(rid) else ""
	if res.has("second_wind"):
		out.append(_f("second_wind", "Retomar o Fôlego", "bonus", "bonus", "self", "1d10+%d PV · %s" % [int(t.get("fighter_level", 1)), left.call("second_wind")]))
	if res.has("action_surge"):
		out.append(_f("action_surge", "Surto de Ação", "special", "free", "self", left.call("action_surge")))
	if res.has("rages"):
		out.append(_f("rage", "Fúria", "bonus", "bonus", "self", left.call("rages")))
	if t.get("reckless_attack", false):
		out.append(_f("reckless_attack", "Ataque Imprudente", "special", "free", "self", "antes do 1º ataque"))
	if res.has("bardic_inspiration"):
		out.append(_f("bardic_inspiration", "Inspiração de Bardo", "bonus", "bonus", "ally", "%s · %s" % [t.get("bardic_die", "1d6"), left.call("bardic_inspiration")], 18.0))
	if res.has("lay_on_hands"):
		out.append(_f("lay_on_hands", "Cura pelas Mãos", "bonus", "bonus", "ally", "reserva %s" % left.call("lay_on_hands"), 1.5))
	if res.has("channel_divinity_paladin") and t.get("sacred_weapon", false):
		out.append(_f("sacred_weapon", "Arma Sagrada", "special", "free", "self", left.call("channel_divinity_paladin")))
	if res.has("channel_divinity"):
		out.append(_f("divine_spark_heal", "Centelha Divina (cura)", "action", "magic", "ally", "%s+Sab · %s" % [t.get("divine_spark", "1d8"), left.call("channel_divinity")], 9.0))
		out.append(_f("divine_spark_harm", "Centelha Divina (dano)", "action", "magic", "enemy", "%s+Sab, Con" % t.get("divine_spark", "1d8"), 9.0))
		out.append(_f("turn_undead", "Expulsar Mortos-Vivos", "action", "magic", "none", "9 m", 9.0))
		if t.get("disciple_of_life", false):
			out.append(_f("preserve_life", "Preservar a Vida", "action", "magic", "none", "%d PV" % (5 * int(c.get("level", 1))), 9.0))
	if res.has("wild_shape"):
		if c.get("form", {}).is_empty():
			for b in t.get("beast_forms", []):
				if Srd.monsters.has(b):
					out.append(_f("wild_shape", "Forma Selvagem: %s" % Srd.label("monster", b), "bonus", "bonus", "self", left.call("wild_shape"), 0.0, {"opts": {"beast": b}, "id": "feat:wild_shape:" + b}))
			if t.has("lands_aid"):
				out.append(_f("lands_aid", "Auxílio da Terra", "action", "magic", "point", "%s, Con" % t["lands_aid"], 18.0, {"area": {"shape": "sphere", "size_ft": 10, "origin": "point"}}))
		else:
			out.append(_f("leave_wild_shape", "Sair da forma", "bonus", "bonus", "self"))
	if t.get("cunning_action", false):
		out.append(_f("cunning_dash", "Ação Ardilosa: Disparada", "bonus", "bonus", "none"))
		out.append(_f("cunning_disengage", "Ação Ardilosa: Desengajar", "bonus", "bonus", "none"))
		out.append(_f("cunning_hide", "Ação Ardilosa: Esconder", "bonus", "bonus", "none"))
	if t.get("steady_aim", false):
		out.append(_f("steady_aim", "Mira Firme", "bonus", "bonus", "self", "vantagem, sem mover"))
	if t.get("martial_arts", "") != "":
		out.append(_f("martial_arts_strike", "Golpe Desarmado bônus", "bonus", "bonus", "enemy", t["martial_arts"], 1.5))
		if res.has("focus_points"):
			out.append(_f("flurry_of_blows", "Rajada de Golpes", "bonus", "bonus", "enemy", "1 foco · %s" % left.call("focus_points"), 1.5))
			out.append(_f("patient_defense", "Defesa Paciente", "bonus", "bonus", "none", "Desengajar (+Esquivar com 1 foco)"))
			out.append(_f("step_of_the_wind", "Passo do Vento", "bonus", "bonus", "none", "Disparada (+Desengajar com 1 foco)"))
	if res.has("wholeness_of_body"):
		out.append(_f("wholeness_of_body", "Plenitude do Corpo", "bonus", "bonus", "self", left.call("wholeness_of_body")))
	if res.has("innate_sorcery"):
		out.append(_f("innate_sorcery", "Feitiçaria Inata", "bonus", "bonus", "self", left.call("innate_sorcery")))
	if res.has("sorcery_points"):
		for l in [1, 2, 3]:
			out.append(_f("create_slot", "Criar espaço nível %d" % l, "bonus", "bonus", "self", "%d pontos" % [2, 3, 5][l - 1], 0.0, {"opts": {"level": l}, "id": "feat:create_slot:%d" % l}))
	if res.has("adrenaline_rush"):
		out.append(_f("adrenaline_rush", "Fúria de Adrenalina", "bonus", "bonus", "none", left.call("adrenaline_rush")))
	if res.has("breath_weapon"):
		out.append(_f("breath_weapon", "Arma de Sopro (cone)", "attack", "attack", "direction", "%s %s · %s" % [t["breath_weapon"]["dice"], Srd.dtype_name(t["breath_weapon"]["dtype"]), left.call("breath_weapon")], 4.5, {"area": {"shape": "cone", "size_ft": 15, "origin": "self"}, "opts": {"shape": "cone"}}))
		out.append(_f("breath_weapon", "Arma de Sopro (linha)", "attack", "attack", "direction", "linha de 9 m", 9.0, {"area": {"shape": "line", "size_ft": 30, "origin": "self"}, "opts": {"shape": "line"}, "id": "feat:breath_weapon:line"}))
	for it in c.get("inventory", []):
		if it.get("id", "") == "potion_of_healing" and int(it.get("qty", 0)) > 0:
			out.append(_f("potion_of_healing", "Poção de Cura (%d)" % int(it["qty"]), "bonus", "bonus", "ally", "2d4+2 PV", 1.5,
				{"desc": "Beber ou dar a alguém a 1,5 m: Ação Bônus. Recupera 2d4 + 2 PV."}))
		if it.get("id", "") == "healers_kit" and int(it.get("qty", 0)) > 0:
			out.append(_f("healers_kit", "Kit de Curandeiro", "action", "action", "ally", "estabiliza", 1.5,
				{"desc": "Usar Objeto: estabiliza uma criatura a 0 PV sem teste de Medicina."}))
	if c.get("mark", {}).get("can_move", false):
		out.append(_f("move_mark", "Mover %s" % c["mark"]["name"], "bonus", "bonus", "enemy", "", 27.0))
	if Rules.has_effect(c, "rage"):
		out.append(_f("extend_rage", "Manter a Fúria", "bonus", "bonus", "self"))
	return out


## Marca disponibilidade e motivo.
static func _avail(g, c: Dictionary, a: Dictionary) -> void:
	var why := ""
	if g.in_combat and not g.is_my_turn(c):
		why = "Não é a sua vez."
	elif g.in_combat:
		why = g.cost_error(c, str(a["cost"]))
	var ref: String = str(a.get("ref", "")) if typeof(a.get("ref")) == TYPE_STRING else ""
	var res: Dictionary = c.get("resources", {})
	var rid: String = {"second_wind": "second_wind", "action_surge": "action_surge", "rage": "rages", "bardic_inspiration": "bardic_inspiration",
		"lay_on_hands": "lay_on_hands", "sacred_weapon": "channel_divinity_paladin", "divine_spark_heal": "channel_divinity",
		"divine_spark_harm": "channel_divinity", "turn_undead": "channel_divinity", "preserve_life": "channel_divinity",
		"wild_shape": "wild_shape", "lands_aid": "wild_shape", "flurry_of_blows": "focus_points", "wholeness_of_body": "wholeness_of_body",
		"innate_sorcery": "innate_sorcery", "adrenaline_rush": "adrenaline_rush", "breath_weapon": "breath_weapon"}.get(ref, "")
	if why == "" and rid != "" and Rules.res_left(c, rid) <= 0:
		why = "Sem usos restantes."
	if why == "" and ref == "reckless_attack" and int(g.turn_of(c).get("attacks_made", 0)) > 0:
		why = "Só antes do primeiro ataque do turno."
	if why == "" and ref == "rage" and Rules.has_effect(c, "rage"):
		why = "Já está em Fúria."
	if why == "" and ref == "action_surge" and g.turn_of(c).get("surged", false):
		why = "Já usou neste turno."
	a["available"] = why == ""
	a["why"] = why
