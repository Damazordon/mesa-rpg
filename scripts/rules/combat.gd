class_name Combat
extends RefCounted
## Resolução de regras do SRD 5.2.1 durante o jogo: testes de d20, dano, cura, condições,
## efeitos com duração, ataques, magias e características de classe.
## O Game cuida da ordem dos turnos, do movimento e da IA; aqui ficam as regras.
##
## Duração de efeitos e condições ("expire"): {"at": "start"|"end", "of": id, "round": n}
## O efeito termina no começo (ou fim) do turno de `of` na rodada `n`. Sem "expire" = até ser removido.

var g  # o autoload Game


func _init(game) -> void:
	g = game


# ================================================================ utilidades

func note(t: String) -> void:
	g.engine_log(t)


func float_text(c: Dictionary, t: String, kind: String) -> void:
	g.floating_text.emit(c["id"], t, kind)


func changed(c: Dictionary) -> void:
	g.state_changed.emit(c["id"])


func nm(c: Dictionary) -> String:
	return str(c.get("name", "?"))


## Expiração a partir de um código: start_source, end_source_next, start_target, end_target_next,
## end_source (fim do turno atual da fonte) ou um número de rodadas.
func expiry(code: Variant, source_id: String, target_id: String) -> Dictionary:
	if typeof(code) in [TYPE_INT, TYPE_FLOAT]:
		return {"at": "start", "of": source_id, "round": int(g.round_num) + int(code)}
	match str(code):
		"start_source":
			return {"at": "start", "of": source_id, "round": g.next_turn_round(source_id)}
		"end_source_next":
			return {"at": "end", "of": source_id, "round": g.next_turn_round(source_id)}
		"end_source":
			return {"at": "end", "of": source_id, "round": g.round_num if g.current().get("id", "") == source_id else g.next_turn_round(source_id)}
		"start_target":
			return {"at": "start", "of": target_id, "round": g.next_turn_round(target_id)}
		"end_target_next":
			return {"at": "end", "of": target_id, "round": g.next_turn_round(target_id)}
	return {}


# ================================================================ efeitos e condições

func add_effect(c: Dictionary, eff: Dictionary, source: Dictionary, conc := false) -> Dictionary:
	var e := eff.duplicate(true)
	e["source"] = source.get("id", "")
	if not e.has("expire"):
		if e.has("ends"):
			e["expire"] = expiry(e["ends"], e["source"], c["id"])
		elif e.has("rounds"):
			e["expire"] = expiry(int(e["rounds"]), e["source"], c["id"])
	e["concentration"] = conc
	remove_effect(c, e["id"], e["source"])
	c["effects"].append(e)
	if conc:
		_track_conc(source, c["id"])
	changed(c)
	return e


func remove_effect(c: Dictionary, eid: String, source_id := "") -> void:
	var before: int = c["effects"].size()
	c["effects"] = c["effects"].filter(func(e): return not (e["id"] == eid and (source_id == "" or e.get("source", "") == source_id)))
	if c["effects"].size() != before:
		changed(c)


func add_condition(c: Dictionary, cid: String, source: Dictionary, opts := {}) -> bool:
	if cid in c.get("cond_immune", []) or cid in Rules.eff_list(c, "immune_cond"):
		note("%s é imune a %s." % [nm(c), Srd.condition_name(cid)])
		return false
	if c.get("traits", {}).get("mindless_rage", false) and Rules.has_effect(c, "rage") and cid in ["charmed", "frightened"]:
		note("%s está em Fúria Irracional e ignora %s." % [nm(c), Srd.condition_name(cid)])
		return false
	var cd := {"id": cid, "source": source.get("id", "")}
	for k in opts:
		cd[k] = opts[k]
	if opts.has("ends"):
		cd["expire"] = expiry(opts["ends"], cd["source"], c["id"])
	elif opts.has("rounds"):
		cd["expire"] = expiry(int(opts["rounds"]), cd["source"], c["id"])
	c["conditions"] = c["conditions"].filter(func(x): return x["id"] != cid)
	c["conditions"].append(cd)
	if opts.get("concentration", false):
		_track_conc(source, c["id"])
	if cid in ["incapacitated", "paralyzed", "stunned", "unconscious", "petrified"]:
		if c.has("concentration"):
			end_concentration(c, "ficou incapacitado")
		if Rules.has_effect(c, "rage"):
			remove_effect(c, "rage")
		if not c.get("form", {}).is_empty() and cid != "incapacitated":
			leave_form(c)
	if cid == "unconscious" and not Rules.has_condition(c, "prone"):
		c["conditions"].append({"id": "prone", "source": cd["source"]})
	changed(c)
	return true


func remove_condition(c: Dictionary, cid: String) -> void:
	var before: int = c["conditions"].size()
	c["conditions"] = c["conditions"].filter(func(x): return x["id"] != cid)
	if c["conditions"].size() != before:
		changed(c)


## Remove o que expira neste ponto da rodada.
func expire_at(at: String, who_id: String) -> void:
	for c in g.all_combatants():
		var keep: Array = []
		for e in c["effects"]:
			var x: Dictionary = e.get("expire", {})
			if not x.is_empty() and x["at"] == at and x["of"] == who_id and int(x["round"]) <= g.round_num:
				note("%s: %s terminou." % [nm(c), e.get("name", e["id"])])
				if e["id"] == "wild_shape_form":
					leave_form(c)
				continue
			keep.append(e)
		if keep.size() != c["effects"].size():
			c["effects"] = keep
			changed(c)
		var keepc: Array = []
		for cd in c["conditions"]:
			var x: Dictionary = cd.get("expire", {})
			if not x.is_empty() and x["at"] == at and x["of"] == who_id and int(x["round"]) <= g.round_num:
				if cd.has("then"):
					_condition_followup(c, cd)
				else:
					note("%s: %s terminou." % [nm(c), Srd.condition_name(cd["id"])])
				continue
			keepc.append(cd)
		if keepc.size() != c["conditions"].size():
			c["conditions"] = keepc
			changed(c)


## Sono: no fim do próximo turno, novo teste; se falhar, fica inconsciente.
func _condition_followup(c: Dictionary, cd: Dictionary) -> void:
	var then: Dictionary = cd["then"]
	var src: Dictionary = g.by_id.get(cd.get("source", ""), {})
	var r := saving_throw(c, then["save"], int(then["dc"]), {"source": src, "spell": true})
	if not r["success"]:
		add_condition(c, then["condition"], src, {"rounds": int(then.get("rounds", 10)), "ends_on_damage": true, "concentration": true})
		note("%s falhou de novo e fica %s." % [nm(c), Srd.condition_name(then["condition"]).to_lower()])


## Fim do turno: quem tem "repeat_save" testa de novo para se livrar.
func repeat_saves(c: Dictionary) -> void:
	for cd in c["conditions"].duplicate():
		if cd.get("repeat_save", false) and cd.has("save"):
			var src: Dictionary = g.by_id.get(cd.get("source", ""), {})
			var r := saving_throw(c, cd["save"], int(cd["dc"]), {"source": src, "spell": cd.get("spell", false), "condition": cd["id"]})
			if r["success"]:
				remove_condition(c, cd["id"])
				note("%s se livrou de %s." % [nm(c), Srd.condition_name(cd["id"])])
	for e in c["effects"].duplicate():
		if e.get("repeat_save", false) and e.has("save"):
			var src: Dictionary = g.by_id.get(e.get("source", ""), {})
			var r := saving_throw(c, e["save"], int(e["dc"]), {"source": src, "spell": true})
			if r["success"]:
				remove_effect(c, e["id"])
				note("%s se livrou de %s." % [nm(c), e.get("name", e["id"])])


func _track_conc(source: Dictionary, target_id: String) -> void:
	if source.is_empty() or not source.has("concentration"):
		return
	var t: Array = source["concentration"].get("targets", [])
	if not target_id in t:
		t.append(target_id)
	source["concentration"]["targets"] = t


func start_concentration(c: Dictionary, spell_id: String) -> void:
	if c.has("concentration"):
		end_concentration(c, "começou outra magia de concentração")
	c["concentration"] = {"spell_id": spell_id, "name": Srd.label("spell", spell_id), "targets": []}
	changed(c)


func end_concentration(c: Dictionary, why := "") -> void:
	if not c.has("concentration"):
		return
	var conc: Dictionary = c["concentration"]
	c.erase("concentration")
	for t in g.all_combatants():
		var before_e: int = t["effects"].size()
		t["effects"] = t["effects"].filter(func(e): return not (e.get("concentration", false) and e.get("source", "") == c["id"]))
		var before_c: int = t["conditions"].size()
		t["conditions"] = t["conditions"].filter(func(cd): return not (cd.get("concentration", false) and cd.get("source", "") == c["id"]))
		if t["effects"].size() != before_e or t["conditions"].size() != before_c:
			changed(t)
	c.erase("mark")
	note("%s perdeu a concentração em %s%s." % [nm(c), conc["name"], (" (" + why + ")") if why != "" else ""])
	changed(c)


# ================================================================ testes de d20

func _exhaustion(c: Dictionary) -> int:
	return -2 * int(c.get("exhaustion", 0))


func _dice_bonus(c: Dictionary, key: String) -> Array:
	## Soma dados de efeitos (Bênção +1d4, Perdição -1d4). Retorna [total, texto].
	var total := 0
	var parts := PackedStringArray()
	for expr in Rules.eff_dice(c, key):
		var neg: bool = expr.begins_with("-")
		var r := Rules.roll(expr.trim_prefix("-"))
		var v: int = -r["total"] if neg else r["total"]
		total += v
		parts.append("%+d (%s)" % [v, expr])
	return [total, " ".join(parts)]


## Inspiração de Bardo e Inspiração Heroica para transformar falha em sucesso.
func _rescue_roll(c: Dictionary, roll: Dictionary, target: int, label: String) -> Dictionary:
	if roll["total"] >= target or c.get("side", "") != "party":
		return roll
	if c.has("inspiration_die"):
		var r := Rules.roll(str(c["inspiration_die"]))
		if roll["total"] + r["total"] >= target or roll["total"] + Rules.average(str(c["inspiration_die"])) * 2 >= target:
			roll["total"] += r["total"]
			roll["notes"].append("Inspiração de Bardo +%d" % r["total"])
			c.erase("inspiration_die")
			changed(c)
	if roll["total"] < target and c.get("heroic_inspiration", false) and g.settings.get("auto_inspiration", true):
		c["heroic_inspiration"] = false
		var nr := Rules.d20(roll["bonus"], roll["mode"] == "adv", roll["mode"] == "dis", Rules.tv(c, "halfling_luck"))
		nr["notes"] = roll["notes"] + ["Inspiração Heroica: rerrolou %s" % label]
		changed(c)
		return nr
	return roll


func saving_throw(t: Dictionary, ab: String, dc: int, opts := {}) -> Dictionary:
	var src: Dictionary = opts.get("source", {})
	var notes: Array = []
	if ab in ["str", "dex"]:
		for cid in ["paralyzed", "stunned", "unconscious", "petrified"]:
			if Rules.has_condition(t, cid):
				note("%s falha automaticamente na salvaguarda de %s (%s)." % [nm(t), Srd.ability_name(ab), Srd.condition_name(cid)])
				return {"success": false, "total": 0, "nat": 0, "auto": true, "text": "falha automática"}
	var adv := false
	var dis := false
	if opts.get("spell", false) and Rules.tv(t, "magic_resistance"):
		adv = true
		notes.append("Resistência à Magia")
	if ab == "dex" and Rules.tv(t, "danger_sense") and not Rules.incapacitated(t):
		adv = true
		notes.append("Sentido de Perigo")
	if ab in ["int", "wis", "cha"] and Rules.tv(t, "gnomish_cunning"):
		adv = true
		notes.append("Astúcia Gnômica")
	var cond: String = opts.get("condition", "")
	if cond == "poisoned" and Rules.tv(t, "dwarven_resilience"):
		adv = true
	if cond == "charmed" and Rules.tv(t, "fey_ancestry"):
		adv = true
	if cond == "frightened" and Rules.tv(t, "brave"):
		adv = true
	if ab == "str" and Rules.has_effect(t, "rage"):
		adv = true
		notes.append("Fúria")
	if ab == "dex" and Rules.has_effect(t, "dodge") and not Rules.incapacitated(t):
		adv = true
		notes.append("Esquivar")
	if ab in Rules.eff_list(t, "adv_save"):
		adv = true
	if ab == "dex" and Rules.has_condition(t, "restrained"):
		dis = true
	if ab in Rules.eff_list(t, "dis_save") or opts.get("heightened", false):
		dis = true
	if ab == "con" and opts.get("concentration", false) and Rules.tv(t, "eldritch_mind"):
		adv = true
	var bonus := Rules.save_bonus(t, ab) + _exhaustion(t)
	if ab == "dex":
		bonus += Rules.eff_sum(t, "dex_save")
		var cov := int(opts.get("cover", 0))
		if cov > 0 and cov < TerrainMap.COVER_TOTAL:
			bonus += cov
			notes.append("%s +%d" % [TerrainMap.cover_name(cov).capitalize(), cov])
	var aura := aura_bonus(t)
	bonus += aura
	if aura > 0:
		notes.append("Aura de Proteção +%d" % aura)
	var db := _dice_bonus(t, "save_dice")
	bonus += int(db[0])
	if str(db[1]) != "":
		notes.append(str(db[1]))
	var r := Rules.d20(bonus, adv, dis, Rules.tv(t, "halfling_luck"))
	r["notes"] = notes + r["notes"]
	if r["total"] < dc and t.get("side", "") == "party" and Rules.res_left(t, "indomitable") > 0:
		Rules.spend(t, "indomitable")
		var fl := int(Rules.tv(t, "fighter_level", 0))
		var r2 := Rules.d20(bonus + fl, adv, dis, Rules.tv(t, "halfling_luck"))
		r2["notes"] = r["notes"] + ["Indomável: rerrolou com +%d" % fl]
		r = r2
	r = _rescue_roll(t, r, dc, "a salvaguarda")
	var success: bool = r["total"] >= dc
	if not success and Rules.res_left(t, "legendary_resistance") > 0 and t.get("side", "") == "enemy":
		Rules.spend(t, "legendary_resistance")
		success = true
		r["notes"].append("Resistência Lendária")
		note("%s usa Resistência Lendária e transforma a falha em sucesso." % nm(t))
	var title := "%s: salvaguarda de %s" % [nm(t), Srd.ability_name(ab)]
	g.log_dice(t["id"], title, "%d contra CD %d, %s" % [r["total"], dc, "sucesso" if success else "falha"],
		"d20: %s %+d = %d. %s" % [r["dice_text"], bonus, r["total"], ". ".join(r["notes"])], "success" if success else "fail")
	return {"success": success, "total": r["total"], "nat": r["nat"], "text": r["dice_text"]}


## Bônus da Aura de Proteção do paladino aliado mais forte por perto.
func aura_bonus(t: Dictionary) -> int:
	var best := 0
	for p in g.all_combatants():
		var radius: int = int(Rules.tv(p, "aura_of_protection", 0))
		if radius == 0 or not g.is_alive(p) or Rules.incapacitated(p) or g.hostile(p, t):
			continue
		if g.dist_between(p, t) <= Rules.m(radius) + 0.3:
			best = maxi(best, maxi(1, Rules.amod(p, "cha")))
	return best


## Teste de atributo ou perícia. skill pode ser id de perícia ou de atributo.
func ability_check(c: Dictionary, skill: String, dc: int, opts := {}) -> Dictionary:
	var is_skill := skill in Srd.skills()
	var ab: String = Srd.skill_ability(skill) if is_skill else skill
	var bonus: int = Rules.skill_bonus(c, skill) if is_skill else Rules.check_bonus(c, skill)
	bonus += _exhaustion(c)
	var notes: Array = []
	if Rules.tv(c, "thaumaturge") and skill in ["arcana", "religion"]:
		bonus += maxi(1, Rules.amod(c, "wis"))
	if Rules.tv(c, "magician") and skill in ["arcana", "nature"]:
		bonus += maxi(1, Rules.amod(c, "wis"))
	var adv: bool = opts.get("adv", false)
	var dis: bool = opts.get("dis", false)
	if ab == "str" and Rules.has_effect(c, "rage"):
		adv = true
	if skill == "athletics" and Rules.tv(c, "remarkable_athlete"):
		adv = true
	if skill == "stealth":
		var arm: Dictionary = Srd.armor.get(c.get("armor_id", ""), {})
		if arm.get("stealth_dis", false):
			dis = true
			notes.append("armadura barulhenta")
	if Rules.has_condition(c, "poisoned"):
		dis = true
	var db := _dice_bonus(c, "check_dice")
	bonus += int(db[0])
	var reliable: bool = Rules.tv(c, "reliable_talent") and is_skill and Rules.skill_prof(c, skill) > 0
	var r := Rules.d20(bonus, adv, dis, Rules.tv(c, "halfling_luck"), reliable)
	r["notes"] = notes + r["notes"]
	if r["total"] < dc and Rules.tv(c, "tactical_mind") and Rules.res_left(c, "second_wind") > 0 and dc - r["total"] <= 10:
		var extra := Rules.d(10)
		if r["total"] + extra >= dc:
			Rules.spend(c, "second_wind")
			r["total"] += extra
			r["notes"].append("Mente Tática +%d" % extra)
	r = _rescue_roll(c, r, dc, "o teste")
	var label: String = Srd.skill_name(skill) if is_skill else Srd.ability_name(ab)
	var ok: bool = r["total"] >= dc
	g.log_dice(c["id"], "%s: %s%s" % [nm(c), label, opts.get("title_suffix", "")],
		"%d contra CD %d, %s" % [r["total"], dc, "sucesso" if ok else "falha"],
		"d20: %s %+d = %d. %s %s" % [r["dice_text"], bonus, r["total"], ". ".join(r["notes"]), opts.get("dc_reason", "")], "success" if ok else "fail")
	return {"success": ok, "total": r["total"], "nat": r["nat"], "margin": r["total"] - dc}


# ================================================================ dano e cura

## Aplica dano em partes [{amount, dtype}]. Retorna o total que de fato tirou.
func deal_damage(t: Dictionary, parts: Array, src: Dictionary, opts := {}) -> int:
	if t.get("death", {}).get("dead", false):
		return 0
	var total := 0
	var notes: Array = []
	for p in parts:
		var adj := Rules.adjust_damage(t, int(p["amount"]), str(p.get("dtype", "")))
		total += int(adj[0])
		if str(adj[1]) != "":
			notes.append("%s a %s" % [adj[1], Srd.dtype_name(str(p.get("dtype", "")))])
	var reduce := Rules.eff_dice(t, "reduce_damage_dice")
	if not reduce.is_empty() and total > 0 and not t.get("reduced_this_turn", false):
		var r := Rules.roll(reduce[0])
		total = maxi(0, total - r["total"])
		notes.append("Resistência -%d" % r["total"])
		t["reduced_this_turn"] = true
	if total <= 0:
		if not notes.is_empty():
			note("%s não sofre dano (%s)." % [nm(t), ", ".join(notes)])
			float_text(t, "imune", "miss")
		return 0
	# Pontos de vida temporários absorvem primeiro
	var temp: int = int(t.get("temp_hp", 0))
	var absorbed := mini(temp, total)
	t["temp_hp"] = temp - absorbed
	var remaining := total - absorbed
	if absorbed > 0:
		notes.append("%d nos PV temporários" % absorbed)
	if not notes.is_empty():
		note("%s: %s." % [nm(t), ", ".join(notes)])
	float_text(t, "-%d" % total, "crit" if opts.get("crit", false) else "damage")
	# Já caído: falha em teste contra a morte (crítico conta duas)
	if t["kind"] == "pc" and int(t["hp"]) == 0 and remaining > 0:
		if remaining >= int(t["hp_max"]):
			_die(t, "dano massivo")
		else:
			_death_fail(t, 2 if opts.get("crit", false) else 1)
		changed(t)
		return total
	var before: int = t["hp"]
	t["hp"] = maxi(0, before - remaining)
	_end_on_damage(t, src)
	if int(t["hp"]) == 0 and remaining > 0:
		_drop_to_zero(t, remaining - before, src, opts)
	elif t.has("concentration") and remaining > 0:
		var dc := clampi(remaining / 2, 10, 30)
		var r := saving_throw(t, "con", dc, {"concentration": true})
		if not r["success"]:
			end_concentration(t, "falhou no teste de concentração")
	if absorbed > 0 and int(t.get("temp_hp", 0)) == 0 and not t.get("form", {}).is_empty():
		pass
	changed(t)
	return total


func _end_on_damage(t: Dictionary, src: Dictionary) -> void:
	var ended: Array = []
	for cd in t["conditions"]:
		if cd.get("ends_on_damage", false):
			ended.append(cd["id"])
		elif cd["id"] == "charmed" and not src.is_empty() and src.get("id", "") == cd.get("source", "") :
			ended.append(cd["id"])
	for cid in ended:
		remove_condition(t, cid)
		note("%s: %s terminou com o dano." % [nm(t), Srd.condition_name(cid)])
	if Rules.has_condition(t, "invisible"):
		pass


func _drop_to_zero(t: Dictionary, overflow: int, src: Dictionary, opts: Dictionary) -> void:
	if t["kind"] != "pc":
		if Rules.tv(t, "undead_fortitude") and str(opts.get("dtype", "")) != "radiant" and not opts.get("crit", false):
			var r := saving_throw(t, "con", 5 + int(opts.get("total", 5)), {})
			if r["success"]:
				t["hp"] = 1
				note("%s se recusa a cair (Fortitude Morta-Viva)." % nm(t))
				return
		_die(t, "")
		_on_enemy_down(t, src)
		return
	if overflow >= int(t["hp_max"]):
		_die(t, "dano massivo")
		return
	if Rules.tv(t, "relentless_endurance") and Rules.res_left(t, "relentless_endurance") > 0:
		Rules.spend(t, "relentless_endurance")
		t["hp"] = 1
		note("%s cai, mas levanta com 1 PV (Resistência Implacável)." % nm(t))
		float_text(t, "implacável", "heal")
		return
	if Rules.tv(t, "relentless_rage") and Rules.has_effect(t, "rage"):
		var n := int(t.get("relentless_uses", 0))
		var r := saving_throw(t, "con", 10 + 5 * n, {})
		t["relentless_uses"] = n + 1
		if r["success"]:
			t["hp"] = 2 * CharBuilder.class_level(t["choices"], "barbarian")
			note("%s se recusa a cair (Fúria Implacável) e fica com %d PV." % [nm(t), t["hp"]])
			return
	t["death"] = {"success": 0, "fail": 0, "stable": false, "dead": false}
	if not t.get("form", {}).is_empty():
		leave_form(t)
	add_condition(t, "unconscious", src, {"zero_hp": true})
	note("%s caiu a 0 PV e está inconsciente. Testes contra a morte no começo dos turnos." % nm(t))
	Master.react("party_down", t, true)


func _die(t: Dictionary, why: String) -> void:
	t["hp"] = 0
	t["death"]["dead"] = true
	t["conditions"] = []
	if t.has("concentration"):
		end_concentration(t, "morreu")
	t["effects"] = []
	if g.selected_target == t["id"]:
		g.select_target("")
	if t["kind"] == "pc":
		note("%s morreu%s." % [nm(t), (" (" + why + ")") if why != "" else ""])
		float_text(t, "morto", "crit")
	else:
		note("%s caiu." % nm(t))
	changed(t)


func _death_fail(t: Dictionary, n: int) -> void:
	t["death"]["fail"] = int(t["death"]["fail"]) + n
	t["death"]["stable"] = false
	note("%s sofre dano caído: %d falha(s) contra a morte (%d/3)." % [nm(t), n, mini(3, t["death"]["fail"])])
	if int(t["death"]["fail"]) >= 3:
		_die(t, "falhou três testes contra a morte")


func _on_enemy_down(t: Dictionary, src: Dictionary) -> void:
	g.xp_pool += int(t.get("xp", 0))
	Master.react("enemy_down", src)
	# Bênção do Sombrio: PV temporários para o bruxo que derrubou (ou estava perto)
	for w in g.all_combatants():
		if not Rules.tv(w, "dark_ones_blessing") or not g.is_alive(w) or not g.hostile(w, t):
			continue
		if w["id"] == src.get("id", "") or g.dist_between(w, t) <= 3.05:
			var v := maxi(1, Rules.amod(w, "cha") + CharBuilder.class_level(w["choices"], "warlock"))
			if v > int(w.get("temp_hp", 0)):
				w["temp_hp"] = v
				note("%s ganha %d PV temporários (Bênção do Sombrio)." % [nm(w), v])
				changed(w)
	# Marca do Caçador / Maldição podem ser movidas
	for c in g.all_combatants():
		if c.get("mark", {}).get("target", "") == t["id"]:
			c["mark"]["target"] = ""
			c["mark"]["can_move"] = true
			note("%s pode mover %s para outro alvo (Ação Bônus)." % [nm(c), c["mark"]["name"]])


func heal(t: Dictionary, amount: int, src: Dictionary, label := "") -> int:
	if t.get("death", {}).get("dead", false) or amount <= 0:
		return 0
	if Rules.eff_any(t, "no_heal"):
		note("%s não pode recuperar PV agora." % nm(t))
		return 0
	var before: int = t["hp"]
	t["hp"] = mini(int(t["hp_max"]), before + amount)
	var gained: int = t["hp"] - before
	if before == 0 and gained > 0:
		t["conditions"] = t["conditions"].filter(func(cd): return not cd.get("zero_hp", false))
		t["death"] = {"success": 0, "fail": 0, "stable": false, "dead": false}
		note("%s volta a si." % nm(t))
	float_text(t, "+%d" % gained, "heal")
	changed(t)
	return gained


func give_temp_hp(t: Dictionary, amount: int) -> void:
	## PV temporários não somam: fica o maior.
	if amount > int(t.get("temp_hp", 0)):
		t["temp_hp"] = amount
		float_text(t, "+%d temp" % amount, "heal")
		changed(t)


## Teste contra a morte no começo do turno de quem está a 0 PV.
func death_save(c: Dictionary) -> void:
	var d: Dictionary = c["death"]
	if d.get("stable", false) or d.get("dead", false):
		return
	var r := Rules.d20(0, false, false, Rules.tv(c, "halfling_luck"))
	r = _rescue_roll(c, r, 10, "o teste contra a morte")
	var nat: int = r["nat"]
	var res := ""
	if nat == 20:
		c["hp"] = 1
		c["conditions"] = c["conditions"].filter(func(cd): return not cd.get("zero_hp", false))
		c["death"] = {"success": 0, "fail": 0, "stable": false, "dead": false}
		res = "20 natural: volta com 1 PV!"
		float_text(c, "+1", "heal")
	elif nat == 1:
		d["fail"] = int(d["fail"]) + 2
		res = "1 natural: duas falhas"
	elif r["total"] >= 10:
		d["success"] = int(d["success"]) + 1
		res = "sucesso"
	else:
		d["fail"] = int(d["fail"]) + 1
		res = "falha"
	g.log_dice(c["id"], "%s: teste contra a morte" % nm(c), "%s (%d sucessos, %d falhas)" % [res, d.get("success", 0), d.get("fail", 0)],
		"d20: %s = %d. CD 10." % [r["dice_text"], r["total"]], "success" if r["total"] >= 10 else "fail")
	if int(d.get("success", 0)) >= 3:
		d["stable"] = true
		note("%s está estável." % nm(c))
	if int(d.get("fail", 0)) >= 3:
		_die(c, "falhou três testes contra a morte")
	changed(c)


func stabilize(t: Dictionary) -> void:
	if int(t["hp"]) == 0 and not t["death"].get("dead", false):
		t["death"]["stable"] = true
		note("%s está estável." % nm(t))
		changed(t)


# ================================================================ geometria de áreas

## Criaturas atingidas por uma área. shape: sphere, cylinder, emanation, cone, cube, line.
## origin: posição do conjurador; point: ponto escolhido (normalizado).
func in_area(caster: Dictionary, shape: String, size_ft: float, point: Vector2, origin_self: bool) -> Array:
	var out: Array = []
	var size := Rules.m(size_ft)
	var o: Vector2 = g.to_m(caster["pos"])
	var p: Vector2 = g.to_m(point)
	var dir := (p - o).normalized() if p.distance_to(o) > 0.01 else Vector2.RIGHT
	for c in g.all_combatants():
		if not g.is_alive(c) and int(c.get("hp", 0)) <= 0 and c.get("kind", "") != "pc":
			continue
		if c.get("death", {}).get("dead", false):
			continue
		var cp: Vector2 = g.to_m(c["pos"])
		var slack := 0.45  # o token ocupa espaço; basta encostar
		var hit := false
		match shape:
			"sphere", "cylinder":
				hit = cp.distance_to(o if origin_self else p) <= size + slack
			"emanation":
				hit = c["id"] != caster["id"] and cp.distance_to(o) <= size + slack
			"cone":
				var v := cp - o
				var along := v.dot(dir)
				if along > 0.05 and along <= size + slack:
					var across := absf(v.cross(dir))
					hit = across <= along * 0.5 + slack
			"cube":
				if origin_self:
					var v2 := cp - o
					var along2 := v2.dot(dir)
					var across2 := absf(v2.cross(dir))
					hit = along2 > 0.05 and along2 <= size + slack and across2 <= size / 2.0 + slack
				else:
					var v3 := cp - p
					hit = absf(v3.x) <= size / 2.0 + slack and absf(v3.y) <= size / 2.0 + slack
			"line":
				var v4 := cp - o
				var along4 := v4.dot(dir)
				var across4 := absf(v4.cross(dir))
				hit = along4 > 0.05 and along4 <= size + slack and across4 <= 0.75 + slack
		# Parede no meio: a área não chega lá (cobertura total a partir da origem).
		if hit and c["id"] != caster["id"] and g.has_terrain():
			if g.cover_from_point(caster["pos"] if origin_self else point, c) >= TerrainMap.COVER_TOTAL:
				hit = false
		if hit and c["id"] != caster["id"]:
			out.append(c)
		elif hit and c["id"] == caster["id"] and not origin_self and shape in ["sphere", "cylinder", "cube"]:
			out.append(c)
	return out


# ================================================================ ataques

## Fontes de vantagem e desvantagem de um ataque. Retorna [vantagens, desvantagens].
func attack_modes(a: Dictionary, t: Dictionary, atk: Dictionary, opts := {}) -> Array:
	var adv: Array = []
	var dis: Array = []
	var d: float = g.dist_between(a, t)
	var ranged: bool = atk.get("ranged", false)
	# Atacante
	if Rules.has_condition(a, "blinded"):
		dis.append("cego")
	if Rules.has_condition(a, "frightened"):
		dis.append("amedrontado")
	if Rules.has_condition(a, "poisoned"):
		dis.append("envenenado")
	if Rules.has_condition(a, "prone"):
		dis.append("caído")
	if Rules.has_condition(a, "restrained"):
		dis.append("contido")
	if Rules.has_condition(a, "invisible"):
		adv.append("invisível")
	if Rules.eff_any(a, "adv_next_attack"):
		adv.append("Mira Firme")
	if Rules.eff_any(a, "dis_next_attack"):
		dis.append("atrapalhado")
	for e in a["effects"]:
		if e["id"] == "vex" and e.get("vs", "") == t["id"]:
			adv.append("Irritar")
		if e["id"] == "studied" and e.get("vs", "") == t["id"]:
			adv.append("Ataques Estudados")
	if atk.get("ability", "") == "str" and Rules.has_effect(a, "reckless"):
		adv.append("Ataque Imprudente")
	if atk.get("kind", "") == "spell" and atk.get("sorcerer", false) and Rules.has_effect(a, "innate_sorcery"):
		adv.append("Feitiçaria Inata")
	if Rules.tv(a, "pack_tactics"):
		for o in g.all_combatants():
			if o["id"] != a["id"] and g.is_alive(o) and not g.hostile(o, a) and o["side"] == a["side"] and not Rules.incapacitated(o) and g.dist_between(o, t) <= 1.55:
				adv.append("Táticas de Matilha")
				break
	if Rules.tv(a, "grappler") and Rules.has_condition(t, "grappled"):
		for cd in t["conditions"]:
			if cd["id"] == "grappled" and cd.get("source", "") == a["id"]:
				adv.append("Agarrador")
	# Alvo
	if Rules.has_condition(t, "blinded"):
		adv.append("alvo cego")
	for cid in ["paralyzed", "stunned", "unconscious", "petrified"]:
		if Rules.has_condition(t, cid):
			adv.append("alvo " + Srd.condition_name(cid).to_lower())
			break
	if Rules.has_condition(t, "restrained"):
		adv.append("alvo contido")
	if Rules.has_condition(t, "prone"):
		if d <= 1.55:
			adv.append("alvo caído e perto")
		else:
			dis.append("alvo caído e longe")
	if Rules.has_condition(t, "invisible") and not Rules.has_effect(t, "faerie_fire"):
		dis.append("alvo invisível")
	if Rules.has_effect(t, "dodge") and not Rules.incapacitated(t):
		dis.append("alvo se esquivando")
	if Rules.eff_any(t, "attacked_dis"):
		dis.append("alvo protegido")
	for types in Rules.eff_list(t, "attacked_dis_by_types"):
		if str(a.get("type_line", "")).to_lower().contains(str(types)):
			dis.append("Proteção contra o Bem e o Mal")
	if Rules.eff_any(t, "attacked_adv"):
		adv.append("alvo exposto")
	if Rules.eff_any(t, "attacked_adv_once"):
		adv.append("Raio Guia / Ajuda")
	if Rules.eff_any(t, "stunned_strike_adv"):
		adv.append("Golpe Atordoante")
	# Distância
	if ranged:
		var rr: Array = atk.get("range_m", [])
		if rr.size() == 2 and d > float(rr[0]) + 0.05:
			dis.append("longo alcance")
		for o in g.all_combatants():
			if g.hostile(o, a) and g.is_alive(o) and not Rules.incapacitated(o) and g.dist_between(o, a) <= 1.55:
				dis.append("inimigo colado")
				break
	if opts.get("forgo_adv", false):
		adv.clear()
	return [adv, dis]


## Pode atingir? Retorna "" ou o motivo.
func attack_range_error(a: Dictionary, atk: Dictionary, t: Dictionary) -> String:
	var d: float = g.dist_between(a, t)
	if atk.get("ranged", false):
		var rr: Array = atk.get("range_m", [])
		var long_r: float = float(rr[1]) if rr.size() == 2 else float(atk.get("range_single", 36.0))
		if d > long_r + 0.05:
			return "%s está a %s; o alcance máximo é %s." % [nm(t), g.fmt_m(d), g.fmt_m(long_r)]
	else:
		var reach: float = float(atk.get("reach_m", 1.5))
		if d > reach + 0.05:
			return "%s está a %s; o alcance corpo a corpo é %s." % [nm(t), g.fmt_m(d), g.fmt_m(reach)]
	if g.has_terrain() and g.cover_between(a, t) >= TerrainMap.COVER_TOTAL:
		return "%s está atrás de cobertura total: sem linha de visão." % nm(t)
	return ""


func _consume_once_effects(a: Dictionary, t: Dictionary) -> void:
	for e in a["effects"].duplicate():
		if e.get("mods", {}).get("adv_next_attack", false) or e.get("mods", {}).get("dis_next_attack", false):
			remove_effect(a, e["id"], e.get("source", ""))
		if e["id"] in ["vex", "studied"] and e.get("vs", "") == t["id"]:
			remove_effect(a, e["id"], e.get("source", ""))
	for e in t["effects"].duplicate():
		if e.get("mods", {}).get("attacked_adv_once", false) or e.get("mods", {}).get("stunned_strike_adv", false):
			remove_effect(t, e["id"], e.get("source", ""))
	# Atacar revela quem está escondido e encerra Invisibilidade
	for cd in a["conditions"].duplicate():
		if cd["id"] == "invisible" and (cd.get("hidden", false) or cd.get("ends_on_attack", false)):
			remove_condition(a, "invisible")
			note("%s revela a posição ao atacar." % nm(a))
	if Rules.has_effect(a, "sanctuary"):
		remove_effect(a, "sanctuary")


## Um ataque completo: rolagem, reações, dano e efeitos extras. Retorna o resultado.
func attack(a: Dictionary, atk: Dictionary, t: Dictionary, opts := {}) -> Dictionary:
	var modes := attack_modes(a, t, atk, opts)
	var adv: bool = not modes[0].is_empty()
	var dis: bool = not modes[1].is_empty()
	var bonus: int = int(atk.get("to_hit", 0)) + _exhaustion(a)
	var notes: Array = []
	var db := _dice_bonus(a, "attack_dice")
	bonus += int(db[0])
	if str(db[1]) != "":
		notes.append("Bênção/Perdição " + str(db[1]))
	if Rules.has_effect(a, "sacred_weapon") and atk.get("kind", "") == "weapon" and not atk.get("ranged", false):
		var cb := maxi(1, Rules.amod(a, "cha"))
		bonus += cb
		notes.append("Arma Sagrada +%d" % cb)
	var tdb := _dice_bonus(t, "attacked_dice")
	bonus += int(tdb[0])
	var ac := Rules.ac(t)
	# Cobertura (SRD 5.2.1): meia +2, três quartos +5 na CA.
	var cov: int = g.cover_between(a, t) if g.has_terrain() else 0
	if cov > 0 and cov < TerrainMap.COVER_TOTAL:
		ac += cov
		notes.append("%s +%d na CA" % [TerrainMap.cover_name(cov).capitalize(), cov])
	var r := Rules.d20(bonus, adv, dis, Rules.tv(a, "halfling_luck"))
	var crit_range: int = int(Rules.tv(a, "crit_range", 20)) if atk.get("kind", "") in ["weapon", "unarmed"] else 20
	var nat: int = r["nat"]
	var crit: bool = nat >= crit_range
	var hit: bool = crit or (nat != 1 and r["total"] >= ac)
	if not hit and nat != 1:
		r = _rescue_roll(a, r, ac, "o ataque")
		nat = r["nat"]
		crit = nat >= crit_range
		hit = crit or (nat != 1 and r["total"] >= ac)
	if not hit and Rules.tv(a, "peerless_aim") and not a.get("peerless_used", false):
		hit = true
		a["peerless_used"] = true
		notes.append("Mira Incomparável")
	# Reação do alvo: Escudo Arcano
	if hit and not crit and r["total"] < ac + 5 and _try_shield(t, a):
		ac += 5
		hit = r["total"] >= ac
		notes.append("Escudo Arcano +5")
	# Palavras Cortantes do bardo aliado do alvo
	if hit and not crit and a.get("side", "") == "enemy":
		var cw := _try_cutting_words(t, a, r["total"] - ac)
		if cw > 0:
			r["total"] -= cw
			notes.append("Palavras Cortantes -%d" % cw)
			hit = r["total"] >= ac
	var auto_crit := false
	if hit and g.dist_between(a, t) <= 1.55 and (Rules.has_condition(t, "paralyzed") or Rules.has_condition(t, "unconscious")):
		crit = true
		auto_crit = true
	_consume_once_effects(a, t)
	if Rules.has_effect(a, "rage") and g.is_foe_of(a, t):
		a["rage_extended"] = true
	var title := "%s: %s em %s" % [nm(a), atk.get("name", "ataque"), nm(t)]
	var mode_txt := ""
	if adv and not dis:
		mode_txt = "Vantagem (%s). " % ", ".join(modes[0])
	elif dis and not adv:
		mode_txt = "Desvantagem (%s). " % ", ".join(modes[1])
	elif adv and dis:
		mode_txt = "Vantagem e desvantagem se anulam. "
	var detail := "%sd20: %s %+d = %d contra CA %d. %s" % [mode_txt, r["dice_text"], bonus, r["total"], ac, ". ".join(notes + r["notes"])]
	var out := {"hit": hit, "crit": crit, "nat": nat, "total": r["total"], "ac": ac, "damage": 0, "adv": adv and not dis}
	if not hit:
		g.log_dice(a["id"], title, "%d contra CA %d, errou" % [r["total"], ac] if nat != 1 else "1 natural, erro automático", detail, "fumble" if nat == 1 else "miss")
		float_text(t, "errou", "miss")
		_on_miss(a, atk, t, out)
		if a.get("side", "") == "party":
			Master.react("player_fumble" if nat == 1 else "player_miss", a, nat == 1)
		return out
	var dmg := damage_for_attack(a, atk, t, crit, out)
	var parts: Array = dmg["parts"]
	var total := 0
	for p in parts:
		total += int(p["amount"])
	# Reações de quem foi atingido
	total = _damage_reactions(t, a, atk, parts, total)
	g.log_dice(a["id"], title, "%s%d contra CA %d, acerto: %d de dano" % ["CRÍTICO! " if crit else "", r["total"], ac, total],
		detail + " Dano: " + dmg["text"] + (" (crítico automático: alvo indefeso e perto)" if auto_crit else ""), "crit" if crit else "hit")
	var dealt := deal_damage(t, parts, a, {"crit": crit, "dtype": atk.get("dtype", ""), "total": total})
	out["damage"] = dealt
	_on_hit(a, atk, t, out)
	if a.get("side", "") == "party" and crit:
		Master.react("player_crit", a, true)
	elif t.get("side", "") == "party" and dealt >= 6:
		Master.react("enemy_hit_hard", t)
	return out


## Rola o dano com tudo que se soma: dados da arma, Fúria, Furtivo, marcas, Destruição...
func damage_for_attack(a: Dictionary, atk: Dictionary, t: Dictionary, crit: bool, out: Dictionary) -> Dictionary:
	var turn: Dictionary = g.turn_of(a)
	var parts: Array = []
	var texts := PackedStringArray()
	var dtype: String = atk.get("dtype", "")
	var gwf: bool = Rules.tv(a, "gwf") and atk.get("two_handed", false) and not atk.get("ranged", false)
	var base_expr: String = str(atk.get("dice", atk.get("damage", "1")))
	var add_mod: int = int(atk.get("mod", 0)) if atk.has("dice") else 0
	if atk.get("offhand", false) and not Rules.tv(a, "twf") and add_mod > 0:
		add_mod = 0
	var r1 := Rules.roll(base_expr, crit, gwf)
	if Rules.tv(a, "savage_attacker") and atk.get("kind", "") == "weapon" and not turn.get("savage_used", false):
		var r2 := Rules.roll(base_expr, crit, gwf)
		turn["savage_used"] = true
		if r2["total"] > r1["total"]:
			r1 = r2
			texts.append("Atacante Selvagem")
	var base := int(r1["total"]) + add_mod
	if atk.get("kind", "") == "spell" and atk.has("add_damage"):
		base += int(atk["add_damage"])
	texts.append("%s%s = %d %s" % [r1["text"].split(":")[0], (" %+d" % add_mod) if add_mod != 0 else "", base, Srd.dtype_name(dtype)])
	parts.append({"amount": maxi(0, base), "dtype": dtype})
	var str_based: bool = atk.get("ability", "") == "str" and atk.get("kind", "") in ["weapon", "unarmed"]
	# Fúria
	if str_based and Rules.has_effect(a, "rage"):
		var rd := int(Rules.tv(a, "rage_damage", 2))
		parts.append({"amount": rd, "dtype": dtype})
		texts.append("Fúria +%d" % rd)
		# Frenesi: primeiro alvo atingido com Imprudente
		if Rules.tv(a, "frenzy") and Rules.has_effect(a, "reckless") and not turn.get("frenzy_used", false):
			turn["frenzy_used"] = true
			var fr := Rules.roll("%dd6" % rd, crit)
			parts.append({"amount": fr["total"], "dtype": dtype})
			texts.append("Frenesi %d" % fr["total"])
	# Ataque Furtivo
	if Rules.tv(a, "sneak_attack", "") != "" and not turn.get("sneak_used", false) and (atk.get("finesse", false) or atk.get("ranged", false)) and atk.get("kind", "") == "weapon":
		var ok_adv: bool = out.get("adv", false)
		var ally_near := false
		for o in g.all_combatants():
			if o["id"] != a["id"] and g.is_alive(o) and not Rules.incapacitated(o) and not g.hostile(o, a) and g.hostile(o, t) and g.dist_between(o, t) <= 1.55:
				ally_near = true
				break
		var has_dis: bool = not attack_modes(a, t, atk)[1].is_empty() and not out.get("adv", false)
		if ok_adv or (ally_near and not has_dis):
			turn["sneak_used"] = true
			var sa: String = Rules.tv(a, "sneak_attack")
			var cs := _cunning_strike(a, t, sa)
			sa = cs[0]
			var sr := Rules.roll(sa, crit)
			parts.append({"amount": sr["total"], "dtype": dtype})
			texts.append("Ataque Furtivo %s = %d" % [sa, sr["total"]])
			out["cunning"] = cs[1]
	# Marca do Caçador / Maldição
	var mark: Dictionary = a.get("mark", {})
	if mark.get("target", "") == t["id"]:
		var mr := Rules.roll(str(mark["dice"]), crit)
		parts.append({"amount": mr["total"], "dtype": str(mark["dtype"])})
		texts.append("%s %d" % [mark["name"], mr["total"]])
	# Matador de Colossos
	if Rules.tv(a, "hunters_prey", "") == "colossus_slayer" and atk.get("kind", "") == "weapon" and not turn.get("colossus_used", false) and int(t["hp"]) < int(t["hp_max"]):
		turn["colossus_used"] = true
		var cr := Rules.roll("1d8", crit)
		parts.append({"amount": cr["total"], "dtype": dtype})
		texts.append("Matador de Colossos %d" % cr["total"])
	# Golpe Divino (clérigo) / Golpe Primal (druida), uma vez por turno
	if atk.get("kind", "") in ["weapon", "beast"] and not turn.get("blessed_used", false):
		var bs: String = str(Rules.tv(a, "blessed_strikes", ""))
		var ef: String = str(Rules.tv(a, "elemental_fury", ""))
		if bs == "divine_strike" or ef == "primal_strike":
			turn["blessed_used"] = true
			var dice := "2d8" if Rules.tv(a, "improved_blessed_strikes") else "1d8"
			var br := Rules.roll(dice, crit)
			var bt := "radiant" if bs == "divine_strike" else "fire"
			parts.append({"amount": br["total"], "dtype": bt})
			texts.append("%s %d" % ["Golpe Divino" if bs != "" else "Golpe Primal", br["total"]])
	# Golpes Radiantes (paladino 11)
	if Rules.tv(a, "radiant_strikes") and not atk.get("ranged", false) and atk.get("kind", "") in ["weapon", "unarmed"]:
		var rs := Rules.roll("1d8", crit)
		parts.append({"amount": rs["total"], "dtype": "radiant"})
		texts.append("Golpes Radiantes %d" % rs["total"])
	# Destruição Divina armada para o próximo acerto corpo a corpo
	if a.get("smite_armed", false) and not atk.get("ranged", false) and atk.get("kind", "") in ["weapon", "unarmed"] and turn.get("bonus", false):
		var sm := _apply_smite(a, t, crit)
		if not sm.is_empty():
			parts.append(sm["part"])
			texts.append(sm["text"])
	# Dano extra de monstro (ex.: +1d4 com vantagem, +3d4 de veneno)
	if atk.has("extra"):
		var ex: Dictionary = atk["extra"]
		if not ex.get("only_with_advantage", false) or out.get("adv", false):
			var er := Rules.roll(str(ex["damage"]), crit)
			parts.append({"amount": er["total"], "dtype": str(ex["dtype"])})
			texts.append("+%d %s" % [er["total"], Srd.dtype_name(str(ex["dtype"]))])
	# Ancestralidade gigante (golias): fogo e gelo no acerto
	var ga: String = str(Rules.tv(a, "giant_ancestry", ""))
	if ga in ["fire", "frost"] and not turn.get("giant_used", false) and Rules.res_left(a, "giant_ancestry") > 0 and atk.get("kind", "") in ["weapon", "unarmed"]:
		turn["giant_used"] = true
		Rules.spend(a, "giant_ancestry")
		var gd := Rules.roll("1d10" if ga == "fire" else "1d6", crit)
		parts.append({"amount": gd["total"], "dtype": "fire" if ga == "fire" else "cold"})
		texts.append("%s %d" % ["Queimadura do Fogo" if ga == "fire" else "Calafrio do Gelo", gd["total"]])
		if ga == "frost":
			add_effect(t, {"id": "frost_chill", "name": "Calafrio", "mods": {"speed_ft": -10}, "ends": "start_source"}, a)
	return {"parts": parts, "text": ", ".join(texts)}


func _apply_smite(a: Dictionary, t: Dictionary, crit: bool) -> Dictionary:
	var spell_id: String = a.get("smite_spell", "divine_smite")
	var auto: Dictionary = Srd.spells.get(spell_id, {}).get("auto", {})
	var lvl := 1
	var free := Rules.res_left(a, "free_smite") > 0 and spell_id == "divine_smite"
	if free:
		Rules.spend(a, "free_smite")
	else:
		lvl = Rules.lowest_slot(a, 1)
		if lvl == 0:
			a["smite_armed"] = false
			return {}
		Rules.spend_slot(a, lvl)
	var turn: Dictionary = g.turn_of(a)
	turn["bonus"] = false
	turn["slot_spell_cast"] = true
	a["smite_armed"] = false
	var dice := str(auto.get("damage", "2d8"))
	var p := Rules.parse(dice)
	var n: int = p["dice"][0][0] if not p["dice"].is_empty() else 0
	var sides: int = p["dice"][0][1] if not p["dice"].is_empty() else 8
	n += lvl - 1
	if auto.has("vs_fiend_undead") and (t.get("is_undead", false) or t.get("is_fiend", false)):
		n += 1
	var r := Rules.roll("%dd%d" % [n, sides], crit) if n > 0 else {"total": 0}
	if auto.has("save"):
		var sv := saving_throw(t, str(auto["save"]), Rules.spell_dc(a), {"spell": true, "source": a})
		if not sv["success"]:
			start_concentration(a, spell_id)
			for cid in auto.get("conditions", []):
				add_condition(t, cid, a, {"concentration": true})
	changed(a)
	return {"part": {"amount": r["total"], "dtype": str(auto.get("dtype", "radiant"))},
		"text": "%s (nível %d%s) %d" % [Srd.label("spell", spell_id), lvl, ", grátis" if free else "", r["total"]]}


## Golpe Astuto (ladino 5): troca dados do Furtivo por um efeito. Escolha automática simples.
func _cunning_strike(a: Dictionary, t: Dictionary, sa: String) -> Array:
	if not Rules.tv(a, "cunning_strike") or a.get("side", "") != "party" or not g.settings.get("auto_cunning_strike", true):
		return [sa, ""]
	var p := Rules.parse(sa)
	var n: int = p["dice"][0][0]
	if n < 3 or Rules.has_condition(t, "prone") or t.get("size", "medium") in ["huge", "gargantuan"]:
		return [sa, ""]
	return ["%dd6" % (n - 1), "trip"]


func _on_hit(a: Dictionary, atk: Dictionary, t: Dictionary, out: Dictionary) -> void:
	if t.get("death", {}).get("dead", false) and t["kind"] != "pc":
		return
	var dc_attack := 8 + Rules.amod(a, str(atk.get("ability", "str"))) + Rules.pb(a)
	# Maestrias
	match str(atk.get("mastery", "")):
		"vex":
			if out["damage"] > 0:
				add_effect(a, {"id": "vex", "name": "Irritar", "vs": t["id"], "mods": {}, "ends": "end_source_next"}, a)
		"sap":
			add_effect(t, {"id": "sap", "name": "Enfraquecer", "mods": {"dis_next_attack": true}, "ends": "start_source"}, a)
		"slow":
			if out["damage"] > 0:
				add_effect(t, {"id": "slow_mastery", "name": "Lentidão", "mods": {"speed_ft": -10}, "ends": "start_source"}, a)
		"push":
			if t.get("size", "medium") in ["tiny", "small", "medium", "large"]:
				g.push(t, a, 3.0)
				note("%s empurra %s 3 m para longe (Empurrar)." % [nm(a), nm(t)])
		"topple":
			var r := saving_throw(t, "con", dc_attack, {"source": a})
			if not r["success"]:
				add_condition(t, "prone", a)
				note("%s derruba %s (Derrubar)." % [nm(a), nm(t)])
		"cleave":
			_cleave(a, atk, t)
	if out.get("cunning", "") == "trip":
		var r2 := saving_throw(t, "dex", 8 + Rules.amod(a, "dex") + Rules.pb(a), {"source": a})
		if not r2["success"]:
			add_condition(t, "prone", a)
			note("Golpe Astuto: %s cai." % nm(t))
	# Golpe Atordoante (monge)
	if atk.get("monk", false) and Rules.tv(a, "stunning_strike") and not g.turn_of(a).get("stun_used", false) and Rules.res_left(a, "focus_points") > 0 and not Rules.has_condition(t, "stunned") and g.settings.get("auto_stunning_strike", true) and t["kind"] != "pc":
		g.turn_of(a)["stun_used"] = true
		Rules.spend(a, "focus_points")
		var r3 := saving_throw(t, "con", 8 + Rules.amod(a, "wis") + Rules.pb(a), {"source": a})
		if not r3["success"]:
			add_condition(t, "stunned", a, {"ends": "start_source"})
			note("Golpe Atordoante: %s fica atordoado." % nm(t))
		else:
			add_effect(t, {"id": "stunning_strike", "name": "Golpe Atordoante", "mods": {"speed_mult": 0.5, "stunned_strike_adv": true}, "ends": "start_source"}, a)
		changed(a)
	# Técnica da Mão Aberta na Rajada de Golpes
	if atk.get("flurry", false) and Rules.tv(a, "open_hand"):
		if not Rules.has_condition(t, "prone"):
			var r4 := saving_throw(t, "dex", 8 + Rules.amod(a, "wis") + Rules.pb(a), {"source": a})
			if not r4["success"]:
				add_condition(t, "prone", a)
				note("Mão Aberta: %s cai." % nm(t))
		else:
			add_effect(t, {"id": "addle", "name": "Confuso", "mods": {"no_opportunity": true}, "ends": "start_target"}, a)
	# Efeitos de magia no acerto (Raio de Gelo, Raio Guia...)
	if atk.has("on_hit_effect"):
		add_effect(t, atk["on_hit_effect"], a)
	if atk.get("repelling", false) and t.get("size", "medium") in ["tiny", "small", "medium", "large"]:
		g.push(t, a, 3.0)
	if Rules.tv(a, "remarkable_athlete") and out["crit"]:
		g.turn_of(a)["free_move_m"] = float(g.turn_of(a).get("free_move_m", 0.0)) + Rules.speed_m(a) / 2.0


func _on_miss(a: Dictionary, atk: Dictionary, t: Dictionary, out: Dictionary) -> void:
	if str(atk.get("mastery", "")) == "graze":
		var m := Rules.amod(a, str(atk.get("ability", "str")))
		if m > 0:
			note("%s raspa %s mesmo errando (Raspar): %d de dano." % [nm(a), nm(t), m])
			deal_damage(t, [{"amount": m, "dtype": atk.get("dtype", "")}], a)
	if Rules.tv(a, "studied_attacks"):
		add_effect(a, {"id": "studied", "name": "Ataques Estudados", "vs": t["id"], "mods": {}, "ends": "end_source_next"}, a)
	if atk.get("kind", "") == "spell" and atk.get("cantrip", false) and Rules.tv(a, "potent_cantrip"):
		var half: int = Rules.roll(str(atk.get("dice", "1d10")))["total"] / 2
		if half > 0:
			note("Truque Potente: %s sofre metade do dano mesmo com o erro." % nm(t))
			deal_damage(t, [{"amount": half, "dtype": atk.get("dtype", "")}], a)


func _cleave(a: Dictionary, atk: Dictionary, t: Dictionary) -> void:
	var turn: Dictionary = g.turn_of(a)
	if turn.get("cleave_used", false):
		return
	for o in g.all_combatants():
		if o["id"] != t["id"] and g.is_alive(o) and g.hostile(a, o) and g.dist_between(o, t) <= 1.55 and g.dist_between(a, o) <= float(atk.get("reach_m", 1.5)) + 0.05:
			turn["cleave_used"] = true
			var second := atk.duplicate()
			second["mastery"] = ""
			second["mod"] = mini(0, int(atk.get("mod", 0)))
			second["name"] = str(atk["name"]) + " (Trespassar)"
			note("%s trespassa e ataca %s também." % [nm(a), nm(o)])
			attack(a, second, o)
			return


## Escudo Arcano automático quando ele faria o ataque errar.
func _try_shield(t: Dictionary, attacker: Dictionary) -> bool:
	if t.get("kind", "") != "pc" or t.get("reaction_used", false) or not g.settings.get("auto_reactions", true):
		return false
	if not "shield" in CharBuilder.castable_spells(t) or Rules.lowest_slot(t, 1) == 0 or Rules.incapacitated(t):
		return false
	var lvl := Rules.lowest_slot(t, 1)
	Rules.spend_slot(t, lvl)
	t["reaction_used"] = true
	add_effect(t, Srd.spells["shield"]["auto"]["effect"], t)
	note("%s conjura Escudo Arcano como reação (+5 de CA até o próximo turno)." % nm(t))
	float_text(t, "Escudo!", "heal")
	return true


func _try_cutting_words(target: Dictionary, attacker: Dictionary, margin: int) -> int:
	for b in g.all_combatants():
		if not Rules.tv(b, "cutting_words") or b.get("reaction_used", false) or not g.is_alive(b) or Rules.incapacitated(b):
			continue
		if g.hostile(b, attacker) and g.dist_between(b, attacker) <= 18.05 and Rules.res_left(b, "bardic_inspiration") > 0:
			var die: String = Rules.tv(b, "bardic_die", "1d6")
			if margin >= Rules.parse(die)["dice"][0][1]:
				continue
			Rules.spend(b, "bardic_inspiration")
			b["reaction_used"] = true
			var v: int = Rules.roll(die)["total"]
			note("%s usa Palavras Cortantes contra %s (-%d)." % [nm(b), nm(attacker), v])
			changed(b)
			return v
	return 0


## Reações que reduzem o dano de um acerto: Esquiva Sobrenatural, Desviar Ataques, Resistência da Pedra.
func _damage_reactions(t: Dictionary, a: Dictionary, atk: Dictionary, parts: Array, total: int) -> int:
	if t.get("reaction_used", false) or Rules.incapacitated(t) or not g.settings.get("auto_reactions", true) or t.get("kind", "") != "pc":
		return total
	if Rules.tv(t, "deflect_attacks") and atk.get("dtype", "") in ["bludgeoning", "piercing", "slashing"]:
		var red: int = Rules.roll("1d10")["total"] + Rules.amod(t, "dex") + CharBuilder.class_level(t["choices"], "monk")
		t["reaction_used"] = true
		note("%s desvia o ataque e reduz %d de dano (Desviar Ataques)." % [nm(t), red])
		return _reduce_parts(parts, red)
	if Rules.tv(t, "uncanny_dodge"):
		t["reaction_used"] = true
		note("%s usa Esquiva Sobrenatural e corta o dano pela metade." % nm(t))
		var half := total / 2
		return _reduce_parts(parts, total - half)
	if str(Rules.tv(t, "giant_ancestry", "")) == "stone" and Rules.res_left(t, "giant_ancestry") > 0 and total >= 8:
		Rules.spend(t, "giant_ancestry")
		t["reaction_used"] = true
		var red2: int = Rules.roll("1d12")["total"] + Rules.amod(t, "con")
		note("%s usa Resistência da Pedra e reduz %d de dano." % [nm(t), red2])
		return _reduce_parts(parts, red2)
	return total


func _reduce_parts(parts: Array, amount: int) -> int:
	var left := amount
	for p in parts:
		var take := mini(left, int(p["amount"]))
		p["amount"] = int(p["amount"]) - take
		left -= take
	var total := 0
	for p in parts:
		total += int(p["amount"])
	return total


# ================================================================ magias

func spell_cost(sp: Dictionary) -> String:
	var ct: String = sp.get("casting_time", "Action")
	if ct.begins_with("Bonus Action"):
		return "bonus"
	if ct.begins_with("Reaction"):
		return "reaction"
	if ct.begins_with("Action"):
		return "magic"
	return "long"


func spell_range_m(a: Dictionary, sp: Dictionary, opts := {}) -> float:
	var auto: Dictionary = sp.get("auto", {})
	var ft: float = float(auto.get("range_ft", sp.get("range_ft", 0)))
	if sp.get("range", "").begins_with("Touch"):
		ft = 5
	if "distant_spell" in opts.get("metamagic", []):
		ft = 30.0 if ft <= 5 else ft * 2
	return Rules.m(ft)


## Pode conjurar agora? "" ou o motivo.
func can_cast(a: Dictionary, spell_id: String, slot: int, opts := {}) -> String:
	var sp: Dictionary = Srd.spells.get(spell_id, {})
	if sp.is_empty():
		return "Magia desconhecida."
	if not spell_id in CharBuilder.castable_spells(a):
		return "%s não está preparada." % Srd.label("spell", spell_id)
	if Rules.has_effect(a, "rage"):
		return "Em Fúria não dá para conjurar magias."
	if not a.get("form", {}).is_empty():
		return "Em Forma Selvagem não dá para conjurar magias."
	var lvl: int = int(sp["level"])
	var free := _free_cast_resource(a, spell_id)
	if lvl > 0 and free == "":
		if slot < lvl:
			return "Precisa de um espaço de nível %d ou maior." % lvl
		if Rules.slot_left(a, slot) <= 0:
			return "Sem espaços de nível %d." % slot
	if g.in_combat:
		var cost := spell_cost(sp)
		if "quickened_spell" in opts.get("metamagic", []) and cost == "magic":
			cost = "bonus"
		if cost == "long":
			return "%s leva %s para conjurar; não dá em combate." % [Srd.label("spell", spell_id), Srd.spell_meta(spell_id).split(" · ")[0].to_lower()]
		if cost == "reaction" and spell_id == "shield":
			return "Escudo Arcano é usado sozinho, como reação, quando um ataque acertaria."
		var why: String = g.cost_error(a, cost)
		if why != "":
			return why
		if lvl > 0 and free == "" and g.turn_of(a).get("slot_spell_cast", false):
			return "Só dá para gastar um espaço de magia por turno."
	return ""


func _free_cast_resource(a: Dictionary, spell_id: String) -> String:
	var res: String = a.get("spellcasting", {}).get("free", {}).get(spell_id, "")
	if res != "" and Rules.res_left(a, res) > 0:
		return res
	return ""


## Conjura. targets: ids escolhidos; point: centro da área (normalizado).
func cast(a: Dictionary, spell_id: String, slot: int, targets: Array, point: Vector2, opts := {}) -> bool:
	var why := can_cast(a, spell_id, slot, opts)
	if why != "":
		note("Recusado: " + why)
		return false
	var sp: Dictionary = Srd.spells[spell_id]
	var auto: Dictionary = sp.get("auto", {})
	var lvl: int = int(sp["level"])
	var meta: Array = opts.get("metamagic", [])
	# Linha de visão: alvo atrás de parede não pode ser escolhido, nem ponto que não se vê.
	if g.has_terrain():
		for tid in targets:
			var tt: Dictionary = g.by_id.get(tid, {})
			if not tt.is_empty() and tt["id"] != a["id"] and g.cover_between(a, tt) >= TerrainMap.COVER_TOTAL:
				note("Recusado: sem linha de visão até %s." % nm(tt))
				return false
		var self_origin: bool = auto.get("origin", "point") == "self" or str(auto.get("area", {}).get("shape", "")) == "emanation"
		if point.x >= 0.0 and not self_origin and not g.line_clear(a["pos"], point):
			note("Recusado: o ponto escolhido está fora da linha de visão.")
			return false
	# Metamagia: paga antes
	var sp_cost := 0
	for mm in meta:
		sp_cost += _metamagic_cost(mm, lvl)
	if sp_cost > 0:
		if Rules.res_left(a, "sorcery_points") < sp_cost:
			note("Recusado: faltam pontos de feitiçaria (%d)." % sp_cost)
			return false
		Rules.spend(a, "sorcery_points", sp_cost)
	# Economia de ações
	var cost := spell_cost(sp)
	if "quickened_spell" in meta and cost == "magic":
		cost = "bonus"
	if g.in_combat:
		g.spend_cost(a, cost)
	# Espaço de magia
	var used_slot := 0
	if lvl > 0:
		var free := _free_cast_resource(a, spell_id)
		if free != "" and (slot <= lvl or Rules.slot_left(a, slot) <= 0):
			Rules.spend(a, free)
			used_slot = lvl
			note("%s conjura %s sem gastar espaço (%s)." % [nm(a), Srd.label("spell", spell_id), a["resources"][free]["name"]])
		else:
			Rules.spend_slot(a, slot)
			used_slot = slot
			if g.in_combat:
				g.turn_of(a)["slot_spell_cast"] = true
	if sp.get("concentration", false) and auto.get("kind", "") != "smite":
		start_concentration(a, spell_id)
	# Conjurar revela quem estava escondido e quebra Invisibilidade/Santuário
	for cd in a["conditions"].duplicate():
		if cd["id"] == "invisible" and (cd.get("hidden", false) or cd.get("ends_on_attack", false)):
			remove_condition(a, "invisible")
	var title := "%s conjura %s%s" % [nm(a), Srd.label("spell", spell_id), (" (nível %d)" % used_slot) if used_slot > lvl else ""]
	note(title + ("" if meta.is_empty() else " com " + ", ".join(meta.map(func(m): return Srd.label("feature", m, m)))))
	g.fx_requested.emit(a["id"], _fx_ability(sp), targets)
	await g._wait(ArtStore.fx_duration(ArtStore.template_for(a["id"], _fx_ability(sp))) * 0.85)
	var ctx := {"a": a, "sp": sp, "auto": auto, "lvl": lvl, "slot": used_slot if used_slot > 0 else lvl,
		"targets": targets, "point": point, "meta": meta, "opts": opts}
	match str(auto.get("kind", "manual")):
		"attack":
			await _spell_attack(ctx)
		"auto_hit":
			_spell_auto_hit(ctx)
		"save":
			_spell_save(ctx)
		"heal":
			_spell_heal(ctx)
		"buff", "condition":
			_spell_buff(ctx)
		"temp_hp":
			var tr := Rules.roll(str(auto.get("temp_hp", "1d4")))
			give_temp_hp(a, tr["total"] + int(auto.get("upcast_flat", 0)) * (ctx["slot"] - lvl))
		"mark":
			_spell_mark(ctx)
		"smite":
			a["smite_armed"] = true
			a["smite_spell"] = spell_id
			note("%s prepara %s: o próximo acerto corpo a corpo neste turno recebe o dano." % [nm(a), Srd.label("spell", spell_id)])
		"teleport":
			var dest: Vector2 = point
			if g.dist_m(a["pos"], dest) <= Rules.m(float(auto.get("range_ft", 30))) + 0.1 and g.spot_free(dest, a["id"]) and g.line_clear(a["pos"], dest):
				g.teleport(a, dest)
			else:
				note("Destino fora do alcance ou ocupado; %s não se move." % nm(a))
		"revive":
			for tid in targets:
				var t: Dictionary = g.by_id[tid]
				if t.get("death", {}).get("dead", false):
					t["death"] = {"success": 0, "fail": 0, "stable": false, "dead": false}
					t["hp"] = 1
					t["conditions"] = []
					note("%s volta à vida com 1 PV." % nm(t))
					float_text(t, "+1", "heal")
					changed(t)
		"stabilize":
			for tid in targets:
				stabilize(g.by_id[tid])
		"cure":
			for tid in targets:
				var t2: Dictionary = g.by_id[tid]
				for cid in auto.get("cures", []):
					if Rules.has_condition(t2, cid):
						remove_condition(t2, cid)
						note("%s não está mais %s." % [nm(t2), Srd.condition_name(cid).to_lower()])
						break
		_:
			note("Efeito narrativo: o mestre descreve o resultado de %s." % Srd.label("spell", spell_id))
			Master.on_manual_effect(a, Srd.label("spell", spell_id), sp.get("text", ""))
	changed(a)
	return true


func _metamagic_cost(mm: String, lvl: int) -> int:
	for o in Srd.classes["sorcerer"].get("options", {}).get("metamagic", []):
		if o["id"] == mm:
			return int(o.get("cost", 1))
	return 1


func _fx_ability(sp: Dictionary) -> Dictionary:
	var auto: Dictionary = sp.get("auto", {})
	var t := "single"
	if auto.has("area"):
		t = "area"
	elif auto.get("kind", "") in ["heal", "buff", "temp_hp"]:
		t = "self" if auto.get("target", "") == "self" else "ally"
	return {"id": sp["id"], "name": Srd.label("spell", sp["id"]), "kind": "heal" if auto.get("kind", "") == "heal" else "spell",
		"target": t, "dtype": auto.get("dtype", ""), "range": "spell", "area_m": Rules.m(float(auto.get("area", {}).get("size_ft", 10)))}


func _cantrip_tier(a: Dictionary) -> int:
	var lv: int = int(a.get("level", 1))
	return 1 + int(lv >= 5) + int(lv >= 11) + int(lv >= 17)


## Expressão de dano da magia já com truque escalado e nível acima.
func spell_damage_expr(a: Dictionary, sp: Dictionary, slot: int, key := "damage") -> String:
	var auto: Dictionary = sp.get("auto", {})
	var expr := str(auto.get(key, "0"))
	var p := Rules.parse(expr)
	if p["dice"].is_empty():
		return expr
	var n: int = p["dice"][0][0]
	var sides: int = p["dice"][0][1]
	var lvl: int = int(sp["level"])
	if lvl == 0 and auto.has("cantrip_dice"):
		n *= _cantrip_tier(a)
	if lvl > 0 and auto.has("upcast_dice") and slot > lvl:
		var up := Rules.parse(str(auto["upcast_dice"]))
		if not up["dice"].is_empty() and up["dice"][0][1] == sides:
			n += up["dice"][0][0] * (slot - lvl)
	var out := "%dd%d" % [n, sides]
	if p["mod"] != 0:
		out += "%+d" % p["mod"]
	return out


func _spell_mod_bonus(a: Dictionary, sp: Dictionary) -> int:
	var auto: Dictionary = sp.get("auto", {})
	var b := 0
	if auto.get("add_mod", false):
		b += Rules.amod(a, a.get("spellcasting", {}).get("ability", "int"))
	if auto.get("eldritch", false) and Rules.tv(a, "agonizing_blast"):
		b += Rules.amod(a, "cha")
	if int(sp["level"]) == 0:
		var cid: String = a.get("spellcasting", {}).get("class_id", "")
		if Rules.tv(a, "blessed_strikes", "") == "potent_spellcasting" and "Cleric" in sp.get("classes", []):
			b += Rules.amod(a, "wis")
		if Rules.tv(a, "elemental_fury", "") == "potent_spellcasting" and "Druid" in sp.get("classes", []):
			b += Rules.amod(a, "wis")
	if Rules.tv(a, "empowered_evocation") and sp.get("school", "") == "Evocation":
		b += Rules.amod(a, "int")
	var aff: String = str(Rules.tv(a, "elemental_affinity", ""))
	if aff != "" and auto.get("dtype", "") == aff:
		b += Rules.amod(a, "cha")
	return b


func _sorcerer_spell(a: Dictionary, sp: Dictionary) -> bool:
	return CharBuilder.class_level(a.get("choices", {}), "sorcerer") > 0 and "Sorcerer" in sp.get("classes", [])


func spell_dc_for(a: Dictionary, sp: Dictionary) -> int:
	var dc := Rules.spell_dc(a)
	if _sorcerer_spell(a, sp) and Rules.has_effect(a, "innate_sorcery"):
		dc += 1
	return dc


func _spell_attack(ctx: Dictionary) -> void:
	var a: Dictionary = ctx["a"]
	var sp: Dictionary = ctx["sp"]
	var auto: Dictionary = ctx["auto"]
	var count := 1
	if auto.has("rays"):
		count = int(auto["rays"]) + int(auto.get("upcast_rays", 0)) * (int(ctx["slot"]) - int(ctx["lvl"]))
	if auto.has("beams_by_level"):
		for k in auto["beams_by_level"]:
			if int(a["level"]) >= int(k):
				count = maxi(count, int(auto["beams_by_level"][k]))
	var targets: Array = ctx["targets"]
	if targets.is_empty():
		note("Sem alvo.")
		return
	var dtype: String = str(ctx["opts"].get("dtype", auto.get("dtype", "")))
	var rng := spell_range_m(a, sp, ctx["opts"])
	var atk := {
		"name": Srd.label("spell", sp["id"]), "kind": "spell", "to_hit": Rules.spell_attack(a),
		"dice": spell_damage_expr(a, sp, ctx["slot"]), "mod": 0, "add_damage": _spell_mod_bonus(a, sp),
		"dtype": dtype, "ranged": auto.get("attack", "ranged") == "ranged", "reach_m": maxf(1.5, rng),
		"range_m": [], "range_single": rng, "cantrip": int(sp["level"]) == 0, "sorcerer": _sorcerer_spell(a, sp),
		"ability": a.get("spellcasting", {}).get("ability", "int"),
	}
	if auto.has("on_hit_effect"):
		atk["on_hit_effect"] = auto["on_hit_effect"]
	if auto.get("eldritch", false) and Rules.tv(a, "repelling_blast"):
		atk["repelling"] = true
	for i in count:
		var tid: String = targets[mini(i, targets.size() - 1)]
		var t: Dictionary = g.by_id.get(tid, {})
		if t.is_empty() or not g.is_alive(t):
			var alt: Array = g.all_combatants().filter(func(c): return g.is_alive(c) and g.hostile(a, c) and g.dist_between(a, c) <= rng + 0.05 and g.sees(a, c))
			if alt.is_empty():
				break
			t = alt[0]
		var out := attack(a, atk, t, {})
		if auto.has("then_area_save"):
			var tas: Dictionary = auto["then_area_save"]
			var dmg: int = Rules.roll(str(tas["damage"]))["total"]
			for c in in_area(a, "sphere", float(tas["size_ft"]), t["pos"], false):
				var r := saving_throw(c, str(tas["save"]), spell_dc_for(a, sp), {"spell": true, "source": a})
				if not r["success"]:
					deal_damage(c, [{"amount": dmg, "dtype": str(tas["dtype"])}], a)
		if count > 1:
			await g._wait(0.25)


func _spell_auto_hit(ctx: Dictionary) -> void:
	var a: Dictionary = ctx["a"]
	var auto: Dictionary = ctx["auto"]
	var darts := int(auto.get("darts", 3)) + int(auto.get("upcast_darts", 0)) * (int(ctx["slot"]) - int(ctx["lvl"]))
	var targets: Array = ctx["targets"]
	if targets.is_empty():
		return
	var per := {}
	for i in darts:
		var tid: String = targets[i % targets.size()]
		per[tid] = int(per.get(tid, 0)) + 1
	for tid in per:
		var t: Dictionary = g.by_id[tid]
		if Rules.has_effect(t, "shield"):
			note("%s está sob Escudo Arcano: os dardos não causam dano." % nm(t))
			continue
		var total := 0
		for i in int(per[tid]):
			total += Rules.roll(str(auto["damage"]))["total"]
		total += _spell_mod_bonus(a, ctx["sp"])
		g.log_dice(a["id"], "%s: %s em %s" % [nm(a), Srd.label("spell", ctx["sp"]["id"]), nm(t)], "%d dardo(s), %d de dano" % [per[tid], total], "Acerto automático. %s por dardo." % auto["damage"], "hit")
		deal_damage(t, [{"amount": total, "dtype": str(auto.get("dtype", "force"))}], a)


func _spell_targets_in_area(ctx: Dictionary) -> Array:
	var a: Dictionary = ctx["a"]
	var auto: Dictionary = ctx["auto"]
	var area: Dictionary = auto.get("area", {})
	if area.is_empty():
		var out: Array = []
		var n := int(auto.get("targets", 1)) + int(auto.get("upcast_targets", 0)) * (int(ctx["slot"]) - int(ctx["lvl"]))
		if "twinned_spell" in ctx["meta"]:
			n += 1
		for tid in ctx["targets"]:
			if out.size() < n and g.by_id.has(tid):
				out.append(g.by_id[tid])
		return out
	var origin_self: bool = auto.get("origin", "point") == "self" or area.get("shape", "") == "emanation"
	var hits := in_area(a, str(area["shape"]), float(area["size_ft"]), ctx["point"], origin_self)
	if auto.has("targets"):
		hits = hits.slice(0, int(auto["targets"]))
	return hits


func _spell_save(ctx: Dictionary) -> void:
	var a: Dictionary = ctx["a"]
	var sp: Dictionary = ctx["sp"]
	var auto: Dictionary = ctx["auto"]
	var ab: String = str(auto.get("save", "dex"))
	var dc := spell_dc_for(a, sp)
	var targets := _spell_targets_in_area(ctx)
	if targets.is_empty():
		note("Ninguém foi atingido.")
		return
	var dmg_expr := spell_damage_expr(a, sp, ctx["slot"])
	var has_dmg: bool = dmg_expr != "0" and str(auto.get("damage", "0")) != "0"
	var dmg_roll := Rules.roll(dmg_expr) if has_dmg else {"total": 0, "text": ""}
	var dmg: int = int(dmg_roll["total"]) + (_spell_mod_bonus(a, sp) if has_dmg else 0)
	var dtype: String = str(ctx["opts"].get("dtype", auto.get("dtype", "")))
	var sculpt: int = (1 + int(sp["level"])) if Rules.tv(a, "sculpt_spells") and sp.get("school", "") == "Evocation" else 0
	var careful: bool = "careful_spell" in ctx["meta"]
	if has_dmg:
		note("%s: dano %s = %d %s (CD %d de %s)." % [Srd.label("spell", sp["id"]), dmg_roll["text"].split(":")[0], dmg, Srd.dtype_name(dtype), dc, Srd.ability_name(ab)])
	var failed: Array = []
	var no_effect: bool = not has_dmg and auto.get("conditions", []).is_empty() and not auto.has("on_fail_effect")
	for t in targets:
		if not g.is_alive(t) and t["kind"] != "pc":
			continue
		if auto.get("humanoid_only", false) and t["kind"] == "monster" and not str(t.get("type_line", "")).contains("Humanoid"):
			note("%s não é humanoide; %s não o afeta." % [nm(t), Srd.label("spell", sp["id"])])
			continue
		var friendly: bool = not g.hostile(a, t)
		if friendly and (careful or sculpt > 0):
			if sculpt > 0:
				sculpt -= 1
			note("%s é poupado pela magia." % nm(t))
			continue
		var adv_fight: bool = auto.get("adv_if_fighting", false) and g.in_combat
		var cover_origin: Vector2 = a["pos"] if (auto.get("origin", "point") == "self" or ctx["point"].x < 0.0) else ctx["point"]
		var r := saving_throw(t, ab, dc, {"spell": true, "source": a, "heightened": "heightened_spell" in ctx["meta"] and t == targets[0], "condition": (auto.get("conditions", [""])[0] if auto.has("conditions") else ""),
			"cover": g.cover_from_point(cover_origin, t) if t["id"] != a["id"] else 0})
		if adv_fight and not r["success"]:
			var r2 := saving_throw(t, ab, dc, {"spell": true, "source": a})
			r = r2
		if has_dmg:
			var amount := 0
			var evasion: bool = Rules.tv(t, "evasion") and ab == "dex" and auto.get("half_on_save", false) and not Rules.incapacitated(t)
			if r["success"]:
				if auto.get("half_on_save", false) and not evasion:
					amount = dmg / 2
				elif int(sp["level"]) == 0 and Rules.tv(a, "potent_cantrip"):
					amount = dmg / 2
			else:
				amount = dmg / 2 if evasion else dmg
			if amount > 0:
				deal_damage(t, [{"amount": amount, "dtype": dtype}], a, {"dtype": dtype})
		if not r["success"] and (g.is_alive(t) or t["kind"] == "pc"):
			_apply_spell_fail_effects(ctx, t, ab, dc)
			failed.append(nm(t))
		if Rules.has_effect(a, "rage"):
			a["rage_extended"] = true
	# Magia que só pede salvaguarda (efeito descritivo): o mestre aplica o resultado.
	if no_effect:
		var who := ", ".join(PackedStringArray(failed)) if not failed.is_empty() else "ninguém"
		Master.on_manual_effect(a, "%s (falharam: %s)" % [Srd.label("spell", sp["id"]), who], sp.get("text", ""))


func _apply_spell_fail_effects(ctx: Dictionary, t: Dictionary, ab: String, dc: int) -> void:
	var a: Dictionary = ctx["a"]
	var sp: Dictionary = ctx["sp"]
	var auto: Dictionary = ctx["auto"]
	var conc: bool = sp.get("concentration", false)
	var rounds: int = int(auto.get("rounds", 10))
	if "extended_spell" in ctx["meta"]:
		rounds *= 2
	for cid in auto.get("conditions", []):
		var copts := {"concentration": conc, "spell": true}
		if auto.has("cond_ends"):
			copts["ends"] = auto["cond_ends"]
		elif not conc and rounds > 0:
			copts["rounds"] = rounds
		if auto.get("repeat_save", false):
			copts["repeat_save"] = true
			copts["save"] = ab
			copts["dc"] = dc
		if auto.get("ends_on_damage", false):
			copts["ends_on_damage"] = true
		if auto.has("then_save_condition"):
			copts["then"] = {"save": ab, "dc": dc, "condition": auto["then_save_condition"], "rounds": rounds}
		if add_condition(t, cid, a, copts):
			note("%s fica %s." % [nm(t), Srd.condition_name(cid).to_lower()])
	if auto.has("on_fail_effect"):
		var e: Dictionary = auto["on_fail_effect"].duplicate(true)
		if auto.get("repeat_save", false):
			e["repeat_save"] = true
			e["save"] = ab
			e["dc"] = dc
		add_effect(t, e, a, conc)
	if auto.has("push_ft") and t.get("size", "medium") in ["tiny", "small", "medium", "large"]:
		g.push(t, a, Rules.m(float(auto["push_ft"])))


func _spell_heal(ctx: Dictionary) -> void:
	var a: Dictionary = ctx["a"]
	var sp: Dictionary = ctx["sp"]
	var auto: Dictionary = ctx["auto"]
	var targets := _spell_targets_in_area(ctx)
	var expr := spell_damage_expr(a, sp, ctx["slot"], "heal")
	var healed_others := false
	for t in targets:
		var r := Rules.roll(expr)
		var amount: int = r["total"]
		if Rules.tv(a, "supreme_healing"):
			amount = int(Rules.parse(expr)["dice"][0][0]) * int(Rules.parse(expr)["dice"][0][1]) + int(Rules.parse(expr)["mod"])
		if auto.get("add_mod", false):
			amount += Rules.amod(a, a.get("spellcasting", {}).get("ability", "wis"))
		if Rules.tv(a, "disciple_of_life") and int(sp["level"]) > 0:
			amount += 2 + int(ctx["slot"])
		var got := heal(t, amount, a)
		g.log_dice(a["id"], "%s: %s em %s" % [nm(a), Srd.label("spell", sp["id"]), nm(t)], "recuperou %d PV" % got, r["text"], "heal")
		if t["id"] != a["id"]:
			healed_others = true
	if healed_others and Rules.tv(a, "blessed_healer") and int(sp["level"]) > 0:
		heal(a, 2 + int(ctx["slot"]), a)


func _spell_buff(ctx: Dictionary) -> void:
	var a: Dictionary = ctx["a"]
	var sp: Dictionary = ctx["sp"]
	var auto: Dictionary = ctx["auto"]
	var conc: bool = sp.get("concentration", false)
	var targets: Array
	if auto.get("target", "") == "self":
		targets = [a]
	else:
		targets = _spell_targets_in_area(ctx)
		if targets.is_empty():
			targets = [a]
	var rounds: int = int(auto.get("rounds", 10))
	for t in targets:
		if auto.has("effect"):
			var e: Dictionary = auto["effect"].duplicate(true)
			if not e.has("ends") and not e.has("rounds"):
				e["rounds"] = rounds
			if e.get("mods", {}).get("temp_hp_each_turn", "") == "mod":
				e["mods"]["temp_hp_each_turn"] = Rules.amod(a, a.get("spellcasting", {}).get("ability", "cha"))
			if e.get("mods", {}).has("hp_max"):
				var extra: int = int(e["mods"]["hp_max"]) + int(auto.get("upcast_hp", 0)) * (int(ctx["slot"]) - int(ctx["lvl"]))
				e["mods"]["hp_max"] = extra
				t["hp_max"] = int(t["hp_max"]) + extra
				t["hp"] = int(t["hp"]) + extra
			add_effect(t, e, a, conc)
			note("%s recebe %s." % [nm(t), e.get("name", sp["name"])])
		for cid in auto.get("conditions", []):
			add_condition(t, cid, a, {"concentration": conc, "rounds": rounds, "ends_on_attack": auto.get("ends_on_attack", false)})
			note("%s fica %s." % [nm(t), Srd.condition_name(cid).to_lower()])


func _spell_mark(ctx: Dictionary) -> void:
	var a: Dictionary = ctx["a"]
	var sp: Dictionary = ctx["sp"]
	var auto: Dictionary = ctx["auto"]
	if ctx["targets"].is_empty():
		return
	var t: Dictionary = g.by_id[ctx["targets"][0]]
	a["mark"] = {"target": t["id"], "dice": auto.get("extra", "1d6"), "dtype": auto.get("dtype", "force"),
		"name": Srd.label("spell", sp["id"]), "spell_id": sp["id"], "can_move": false}
	note("%s marca %s com %s." % [nm(a), nm(t), a["mark"]["name"]])
	float_text(t, "marcado", "miss")


## Move a marca (Marca do Caçador, Maldição) depois que o alvo caiu. Ação Bônus.
func move_mark(a: Dictionary, t: Dictionary) -> bool:
	var mark: Dictionary = a.get("mark", {})
	if not mark.get("can_move", false) or not a.has("concentration"):
		return false
	g.spend_cost(a, "bonus")
	mark["target"] = t["id"]
	mark["can_move"] = false
	note("%s move %s para %s." % [nm(a), mark["name"], nm(t)])
	return true


# ================================================================ ações padrão e características

## Executa uma característica ou ação padrão. fid ex.: "dash", "rage", "second_wind".
func use_feature(a: Dictionary, fid: String, targets: Array, point: Vector2, opts := {}) -> bool:
	var t: Dictionary = g.by_id.get(targets[0], {}) if not targets.is_empty() else {}
	var turn: Dictionary = g.turn_of(a)
	match fid:
		# ---------- ações do glossário
		"dash", "cunning_dash", "step_of_the_wind":
			g.spend_cost(a, "bonus" if fid != "dash" else "action")
			if fid == "step_of_the_wind" and Rules.res_left(a, "focus_points") > 0 and opts.get("focus", true):
				Rules.spend(a, "focus_points")
				add_effect(a, {"id": "disengage", "name": "Desengajar", "mods": {}, "ends": "end_source"}, a)
			turn["move_left"] = float(turn.get("move_left", 0.0)) + Rules.speed_m(a)
			note("%s dispara (+%s de movimento)." % [nm(a), g.fmt_m(Rules.speed_m(a))])
		"disengage", "cunning_disengage", "patient_defense":
			g.spend_cost(a, "bonus" if fid != "disengage" else "action")
			add_effect(a, {"id": "disengage", "name": "Desengajar", "mods": {}, "ends": "end_source"}, a)
			if fid == "patient_defense" and Rules.res_left(a, "focus_points") > 0 and opts.get("focus", true):
				Rules.spend(a, "focus_points")
				add_effect(a, {"id": "dodge", "name": "Esquivar", "mods": {}, "ends": "start_source"}, a)
			note("%s se desengaja: pode se mover sem provocar ataques de oportunidade." % nm(a))
		"dodge":
			g.spend_cost(a, "action")
			add_effect(a, {"id": "dodge", "name": "Esquivar", "mods": {}, "ends": "start_source"}, a)
			note("%s se esquiva: ataques contra ele têm desvantagem até o próximo turno." % nm(a))
		"help":
			if t.is_empty():
				return false
			if g.dist_between(a, t) > 1.55:
				note("Recusado: para ajudar contra %s, precisa estar a 1,5 m dele." % nm(t))
				return false
			g.spend_cost(a, "action")
			add_effect(t, {"id": "helped", "name": "Ajuda", "mods": {"attacked_adv_once": true}, "ends": "start_source"}, a)
			note("%s distrai %s: o próximo ataque de um aliado contra ele tem vantagem." % [nm(a), nm(t)])
		"hide", "cunning_hide":
			g.spend_cost(a, "bonus" if fid == "cunning_hide" else "action")
			var seen := false
			for o in g.all_combatants():
				if g.hostile(o, a) and g.is_alive(o) and not Rules.incapacitated(o) and g.dist_between(o, a) <= 1.55:
					seen = true
			if seen:
				note("%s não consegue se esconder com um inimigo colado." % nm(a))
				return true
			var r := ability_check(a, "stealth", 15)
			if r["success"]:
				add_condition(a, "invisible", a, {"hidden": true, "find_dc": r["total"]})
				note("%s se esconde (CD %d para ser encontrado)." % [nm(a), r["total"]])
		"ready":
			g.spend_cost(a, "action")
			a["readied"] = true
			note("%s prepara um ataque: reage ao primeiro inimigo que entrar no alcance." % nm(a))
		"stand_up":
			var half := Rules.speed_m(a) / 2.0
			if float(turn.get("move_left", 0.0)) < half:
				note("Recusado: levantar custa metade do deslocamento.")
				return false
			turn["move_left"] = float(turn["move_left"]) - half
			remove_condition(a, "prone")
			note("%s se levanta." % nm(a))
		"escape_grapple":
			g.spend_cost(a, "action")
			var dc := 10
			for cd in a["conditions"]:
				if cd["id"] == "grappled":
					dc = int(cd.get("escape_dc", 10))
			var sk := "athletics" if Rules.skill_bonus(a, "athletics") >= Rules.skill_bonus(a, "acrobatics") else "acrobatics"
			if ability_check(a, sk, dc)["success"]:
				remove_condition(a, "grappled")
				note("%s se solta." % nm(a))
		"grapple", "shove":
			if t.is_empty() or g.dist_between(a, t) > 1.55:
				note("Recusado: o alvo precisa estar ao alcance (1,5 m).")
				return false
			if not g.spend_attack(a):
				return false
			var abm := "dex" if Rules.tv(a, "martial_arts", "") != "" and Rules.amod(a, "dex") > Rules.amod(a, "str") else "str"
			var dc2 := 8 + Rules.amod(a, abm) + Rules.pb(a)
			var save_ab := "str" if Rules.save_bonus(t, "str") >= Rules.save_bonus(t, "dex") else "dex"
			var r2 := saving_throw(t, save_ab, dc2, {"source": a})
			if not r2["success"]:
				if fid == "grapple":
					add_condition(t, "grappled", a, {"escape_dc": dc2})
					note("%s agarra %s." % [nm(a), nm(t)])
				elif opts.get("push", false):
					g.push(t, a, 1.5)
					note("%s empurra %s." % [nm(a), nm(t)])
				else:
					add_condition(t, "prone", a)
					note("%s derruba %s." % [nm(a), nm(t)])
		# ---------- guerreiro
		"second_wind":
			if not Rules.spend(a, "second_wind"):
				return false
			g.spend_cost(a, "bonus")
			var r3 := Rules.roll("1d10+%d" % int(Rules.tv(a, "fighter_level", 1)))
			heal(a, r3["total"], a)
			g.log_dice(a["id"], "%s: Retomar o Fôlego" % nm(a), "recuperou %d PV" % r3["total"], r3["text"], "heal")
			if Rules.tv(a, "tactical_shift"):
				turn["move_left"] = float(turn.get("move_left", 0.0)) + Rules.speed_m(a) / 2.0
				add_effect(a, {"id": "disengage", "name": "Mudança Tática", "mods": {}, "ends": "end_source"}, a)
		"action_surge":
			if turn.get("surged", false) or not Rules.spend(a, "action_surge"):
				return false
			turn["surged"] = true
			turn["surge"] = int(turn.get("surge", 0)) + 1
			note("%s usa Surto de Ação: uma ação extra neste turno (não vale para Magia)." % nm(a))
		# ---------- bárbaro
		"rage":
			if Srd.armor.get(a.get("armor_id", ""), {}).get("category", "") == "heavy":
				note("Recusado: não dá para entrar em Fúria de armadura pesada.")
				return false
			if not Rules.spend(a, "rages"):
				return false
			g.spend_cost(a, "bonus")
			if a.has("concentration"):
				end_concentration(a, "entrou em Fúria")
			add_effect(a, {"id": "rage", "name": "Fúria", "mods": {"resist": ["bludgeoning", "piercing", "slashing"]}, "rounds": 100}, a)
			a["rage_extended"] = true
			if Rules.tv(a, "mindless_rage"):
				remove_condition(a, "charmed")
				remove_condition(a, "frightened")
			if CharBuilder.class_level(a["choices"], "barbarian") >= 7:
				turn["move_left"] = float(turn.get("move_left", 0.0)) + Rules.speed_m(a) / 2.0
			note("%s entra em Fúria." % nm(a))
			float_text(a, "FÚRIA", "crit")
		"end_rage":
			remove_effect(a, "rage")
		"extend_rage":
			g.spend_cost(a, "bonus")
			a["rage_extended"] = true
			note("%s mantém a Fúria." % nm(a))
		"reckless_attack":
			add_effect(a, {"id": "reckless", "name": "Ataque Imprudente", "mods": {"attacked_adv": true}, "ends": "start_source"}, a)
			note("%s ataca de forma imprudente: vantagem com Força, mas fica exposto." % nm(a))
		# ---------- bardo
		"bardic_inspiration":
			if t.is_empty() or t["id"] == a["id"] or g.dist_between(a, t) > 18.05:
				note("Recusado: escolha outro aliado a até 18 m.")
				return false
			if not Rules.spend(a, "bardic_inspiration"):
				return false
			g.spend_cost(a, "bonus")
			t["inspiration_die"] = Rules.tv(a, "bardic_die", "1d6")
			note("%s inspira %s (%s para uma falha em teste de d20)." % [nm(a), nm(t), t["inspiration_die"]])
			changed(t)
		# ---------- paladino
		"lay_on_hands":
			if t.is_empty() or g.dist_between(a, t) > 1.55:
				note("Recusado: precisa tocar o alvo (1,5 m).")
				return false
			var pool := Rules.res_left(a, "lay_on_hands")
			if opts.get("cure_poison", false) and Rules.has_condition(t, "poisoned") and pool >= 5:
				g.spend_cost(a, "bonus")
				Rules.spend(a, "lay_on_hands", 5)
				remove_condition(t, "poisoned")
				note("%s remove o veneno de %s." % [nm(a), nm(t)])
			else:
				var need: int = int(t["hp_max"]) - int(t["hp"])
				var amount := mini(pool, need if need > 0 else 0)
				if int(opts.get("amount", 0)) > 0:
					amount = mini(amount, int(opts["amount"]))
				if amount <= 0:
					note("%s já está com os PV cheios." % nm(t))
					return false
				g.spend_cost(a, "bonus")
				Rules.spend(a, "lay_on_hands", amount)
				heal(t, amount, a)
				note("%s cura %d PV de %s pelas mãos (sobram %d)." % [nm(a), amount, nm(t), pool - amount])
		"sacred_weapon":
			if not Rules.spend(a, "channel_divinity_paladin"):
				return false
			add_effect(a, {"id": "sacred_weapon", "name": "Arma Sagrada", "mods": {}, "rounds": 100}, a)
			note("%s consagra a arma: soma Carisma aos ataques corpo a corpo." % nm(a))
		"divine_sense":
			if not Rules.spend(a, "channel_divinity_paladin"):
				return false
			g.spend_cost(a, "bonus")
			Master.on_manual_effect(a, "Sentido Divino", "Detecta celestiais, corruptores e mortos-vivos a até 18 m por 10 minutos.")
		# ---------- clérigo
		"divine_spark_heal", "divine_spark_harm":
			if t.is_empty() or g.dist_between(a, t) > 9.05:
				note("Recusado: alvo a até 9 m.")
				return false
			if not Rules.spend(a, "channel_divinity"):
				return false
			g.spend_cost(a, "magic")
			var r4 := Rules.roll(str(Rules.tv(a, "divine_spark", "1d8")))
			var v: int = r4["total"] + Rules.amod(a, "wis")
			if fid == "divine_spark_heal":
				heal(t, v, a)
				g.log_dice(a["id"], "%s: Centelha Divina" % nm(a), "%s recupera %d PV" % [nm(t), v], r4["text"], "heal")
			else:
				var sv := saving_throw(t, "con", Rules.spell_dc(a), {"source": a})
				deal_damage(t, [{"amount": v / 2 if sv["success"] else v, "dtype": "radiant"}], a)
		"turn_undead":
			if not Rules.spend(a, "channel_divinity"):
				return false
			g.spend_cost(a, "magic")
			var sear := 0
			if Rules.tv(a, "sear_undead"):
				sear = Rules.roll("%dd8" % maxi(1, Rules.amod(a, "wis")))["total"]
			for u in g.all_combatants():
				if u.get("is_undead", false) and g.is_alive(u) and g.dist_between(a, u) <= 9.05:
					var sv2 := saving_throw(u, "wis", Rules.spell_dc(a), {"source": a})
					if not sv2["success"]:
						# O dano de Calcinar Mortos-Vivos não encerra a expulsão: aplica antes.
						if sear > 0:
							deal_damage(u, [{"amount": sear, "dtype": "radiant"}], a)
						add_condition(u, "frightened", a, {"rounds": 10, "ends_on_damage": true})
						add_condition(u, "incapacitated", a, {"rounds": 10, "ends_on_damage": true})
			note("%s expulsa os mortos-vivos." % nm(a))
		"preserve_life":
			if not Rules.spend(a, "channel_divinity"):
				return false
			g.spend_cost(a, "magic")
			var pool2 := 5 * CharBuilder.class_level(a["choices"], "cleric")
			var hurt: Array = g.all_combatants().filter(func(c): return not g.hostile(a, c) and g.is_alive(c) and int(c["hp"]) < int(c["hp_max"]) / 2 and g.dist_between(a, c) <= 9.05)
			for c in hurt:
				var cap: int = int(c["hp_max"]) / 2 - int(c["hp"])
				var give := mini(cap, pool2)
				if give > 0:
					heal(c, give, a)
					pool2 -= give
			note("%s preserva a vida dos aliados." % nm(a))
		# ---------- druida
		"wild_shape":
			var beast: String = str(opts.get("beast", ""))
			if beast == "" or not Rules.spend(a, "wild_shape"):
				return false
			g.spend_cost(a, "bonus")
			enter_form(a, beast)
		"leave_wild_shape":
			g.spend_cost(a, "bonus")
			leave_form(a)
		"lands_aid":
			if not Rules.spend(a, "wild_shape"):
				return false
			g.spend_cost(a, "magic")
			var dice: String = str(Rules.tv(a, "lands_aid", "2d6"))
			var d: int = Rules.roll(dice)["total"]
			for c in in_area(a, "sphere", 10, point, false):
				if g.hostile(a, c):
					var sv3 := saving_throw(c, "con", Rules.spell_dc(a), {"source": a})
					deal_damage(c, [{"amount": d / 2 if sv3["success"] else d, "dtype": "necrotic"}], a)
			var allies: Array = in_area(a, "sphere", 10, point, false).filter(func(c): return not g.hostile(a, c))
			if not allies.is_empty():
				allies.sort_custom(func(x, y): return int(x["hp"]) < int(y["hp"]))
				heal(allies[0], Rules.roll(dice)["total"], a)
		# ---------- ladino
		"steady_aim":
			if turn.get("moved_m", 0.0) > 0.05:
				note("Recusado: Mira Firme só antes de se mover no turno.")
				return false
			g.spend_cost(a, "bonus")
			add_effect(a, {"id": "steady_aim", "name": "Mira Firme", "mods": {"adv_next_attack": true}, "ends": "end_source"}, a)
			turn["move_left"] = 0.0
			note("%s mira com calma (vantagem no próximo ataque; não se move mais neste turno)." % nm(a))
		# ---------- monge
		"martial_arts_strike", "flurry_of_blows":
			if t.is_empty():
				return false
			var n := 1
			if fid == "flurry_of_blows":
				if not Rules.spend(a, "focus_points"):
					return false
				n = 3 if CharBuilder.class_level(a["choices"], "monk") >= 10 else 2
			g.spend_cost(a, "bonus")
			var ua: Dictionary = CharBuilder.unarmed_attack(a).duplicate()
			ua["flurry"] = fid == "flurry_of_blows"
			for i in n:
				var tgt := t
				if not g.is_alive(tgt):
					var near: Array = g.all_combatants().filter(func(c): return g.is_alive(c) and g.hostile(a, c) and g.dist_between(a, c) <= 1.55)
					if near.is_empty():
						break
					tgt = near[0]
				if g.dist_between(a, tgt) > 1.55:
					note("%s está longe demais para o golpe." % nm(tgt))
					break
				attack(a, ua, tgt)
				await g._wait(0.3)
		"wholeness_of_body":
			if not Rules.spend(a, "wholeness_of_body"):
				return false
			g.spend_cost(a, "bonus")
			heal(a, maxi(1, Rules.roll(str(Rules.tv(a, "martial_arts", "1d6")))["total"] + Rules.amod(a, "wis")), a)
		# ---------- feiticeiro
		"innate_sorcery":
			if not Rules.spend(a, "innate_sorcery"):
				return false
			g.spend_cost(a, "bonus")
			add_effect(a, {"id": "innate_sorcery", "name": "Feitiçaria Inata", "mods": {}, "rounds": 10}, a)
			note("%s libera a Feitiçaria Inata (+1 CD e vantagem nos ataques de magia de feiticeiro)." % nm(a))
		"create_slot":
			var lvl := int(opts.get("level", 1))
			var cost := {1: 2, 2: 3, 3: 5, 4: 6, 5: 7}.get(lvl, 99) as int
			if Rules.res_left(a, "sorcery_points") < cost:
				note("Recusado: criar espaço de nível %d custa %d pontos." % [lvl, cost])
				return false
			g.spend_cost(a, "bonus")
			Rules.spend(a, "sorcery_points", cost)
			var s: Dictionary = a["slots"].get(str(lvl), {"max": 0, "left": 0})
			s["left"] = int(s["left"]) + 1
			a["slots"][str(lvl)] = s
			note("%s cria um espaço de magia de nível %d." % [nm(a), lvl])
		"convert_slot":
			var lvl2 := int(opts.get("level", 1))
			if not Rules.spend_slot(a, lvl2):
				return false
			var r5: Dictionary = a["resources"]["sorcery_points"]
			r5["left"] = mini(int(r5["max"]), int(r5["left"]) + lvl2)
			note("%s converte um espaço de nível %d em %d pontos de feitiçaria." % [nm(a), lvl2, lvl2])
		# ---------- espécies
		"adrenaline_rush":
			if not Rules.spend(a, "adrenaline_rush"):
				return false
			g.spend_cost(a, "bonus")
			turn["move_left"] = float(turn.get("move_left", 0.0)) + Rules.speed_m(a)
			give_temp_hp(a, Rules.pb(a))
			note("%s dispara com Fúria de Adrenalina." % nm(a))
		"breath_weapon":
			if not g.spend_attack(a) or not Rules.spend(a, "breath_weapon"):
				return false
			var bw: Dictionary = Rules.tv(a, "breath_weapon", {})
			var shape: String = opts.get("shape", "cone")
			var dc3 := 8 + Rules.amod(a, "con") + Rules.pb(a)
			var dmg: int = Rules.roll(str(bw.get("dice", "1d10")))["total"]
			for c in in_area(a, shape, 15 if shape == "cone" else 30, point, true):
				var sv4 := saving_throw(c, "dex", dc3, {"source": a})
				deal_damage(c, [{"amount": dmg / 2 if sv4["success"] else dmg, "dtype": str(bw.get("dtype", "fire"))}], a)
		"move_mark":
			if t.is_empty():
				return false
			return move_mark(a, t)
		# ---------- itens
		"potion_of_healing", "healers_kit":
			if t.is_empty() or g.dist_between(a, t) > 1.55:
				note("Recusado: o alvo precisa estar a 1,5 m.")
				return false
			var item: Dictionary = {}
			for it in a.get("inventory", []):
				if it.get("id", "") == fid and int(it.get("qty", 0)) > 0:
					item = it
			if item.is_empty():
				return false
			g.spend_cost(a, "bonus" if fid == "potion_of_healing" else "action")
			if fid == "potion_of_healing":
				item["qty"] = int(item["qty"]) - 1
				var r6 := Rules.roll("2d4+2")
				heal(t, r6["total"], a)
				g.log_dice(a["id"], "%s: Poção de Cura em %s" % [nm(a), nm(t)], "recuperou %d PV" % r6["total"], r6["text"], "heal")
			else:
				stabilize(t)
		_:
			note("Característica sem automação: %s. O mestre resolve." % fid)
			return false
	changed(a)
	return true


# ================================================================ Forma Selvagem

func enter_form(c: Dictionary, beast_id: String) -> void:
	var m: Dictionary = Srd.monsters.get(beast_id, {})
	if m.is_empty():
		return
	if not c.get("form", {}).is_empty():
		leave_form(c)
	var mb := MonsterBuilder.build(beast_id, c["id"] + "_form")
	c["form"] = {"beast_id": beast_id, "name": mb["name"], "ac": mb["ac_fixed"], "speed_ft": mb["speed_ft"],
		"scores": {"str": m["abilities"].get("str", 10), "dex": m["abilities"].get("dex", 10), "con": m["abilities"].get("con", 10)},
		"attacks": mb["attacks"].map(func(x): var y: Dictionary = x.duplicate(); y["kind"] = "beast"; return y)}
	give_temp_hp(c, CharBuilder.class_level(c["choices"], "druid"))
	note("%s assume a forma de %s." % [nm(c), mb["name"]])
	float_text(c, mb["name"], "heal")
	changed(c)


func leave_form(c: Dictionary) -> void:
	if c.get("form", {}).is_empty():
		return
	note("%s volta à forma normal." % nm(c))
	c["form"] = {}
	changed(c)


# ================================================================ turnos e descansos

func on_turn_start(c: Dictionary) -> void:
	expire_at("start", c["id"])
	c["reaction_used"] = false
	c["reduced_this_turn"] = false
	c["peerless_used"] = false
	for e in c["effects"]:
		var thp: int = int(e.get("mods", {}).get("temp_hp_each_turn", 0))
		if thp > 0:
			give_temp_hp(c, thp)
		var dot: Dictionary = e.get("mods", {}).get("dot_start", {})
		if not dot.is_empty():
			deal_damage(c, [{"amount": Rules.roll(str(dot["dice"]))["total"], "dtype": str(dot["dtype"])}], g.by_id.get(e.get("source", ""), {}))
	# Recarga de habilidades de monstro
	for act in c.get("monster_actions", []):
		if act.has("recharge") and not act.get("charged", true):
			var r := Rules.d(6)
			if r >= int(act["recharge"]):
				act["charged"] = true
				note("%s recarregou %s (d6: %d)." % [nm(c), act["name"], r])


func on_turn_end(c: Dictionary) -> void:
	repeat_saves(c)
	# Fúria só continua se foi mantida neste turno
	if Rules.has_effect(c, "rage"):
		if not c.get("rage_extended", false) and not Rules.tv(c, "persistent_rage"):
			remove_effect(c, "rage")
			note("A Fúria de %s termina." % nm(c))
		c["rage_extended"] = false
	expire_at("end", c["id"])
	remove_effect(c, "disengage")


## Descanso curto: gasta Dados de Vida e recupera o que volta no descanso curto.
func short_rest(c: Dictionary, dice_to_spend: int) -> void:
	var con := Rules.amod(c, "con")
	var healed := 0
	var spent := 0
	var dice: Array = c.get("hit_dice", {}).keys()
	dice.sort_custom(func(x, y): return int(x.substr(1)) > int(y.substr(1)))
	for die in dice:
		while spent < dice_to_spend and int(c["hit_dice"][die]["left"]) > 0 and int(c["hp"]) < int(c["hp_max"]):
			c["hit_dice"][die]["left"] = int(c["hit_dice"][die]["left"]) - 1
			var v := maxi(1, Rules.d(int(die.substr(1))) + con)
			healed += heal(c, v, c)
			spent += 1
	for rid in c.get("resources", {}):
		var r: Dictionary = c["resources"][rid]
		match str(r.get("recharge", "long")):
			"short":
				r["left"] = r["max"]
			"long_one_short":
				r["left"] = mini(int(r["max"]), int(r["left"]) + 1)
	if not c.get("pact", {}).is_empty():
		c["pact"]["left"] = c["pact"]["max"]
	if Rules.res_left(c, "arcane_recovery") > 0:
		_recover_slots(c, ceili(int(Rules.tv(c, "wizard_level", 1)) / 2.0))
		Rules.spend(c, "arcane_recovery")
	c["relentless_uses"] = 0
	note("%s descansa: gastou %d Dado(s) de Vida e recuperou %d PV." % [nm(c), spent, healed])
	changed(c)


func _recover_slots(c: Dictionary, budget: int) -> void:
	for l in range(mini(5, budget), 0, -1):
		while budget >= l:
			var s: Dictionary = c["slots"].get(str(l), {})
			if s.is_empty() or int(s["left"]) >= int(s["max"]):
				break
			s["left"] = int(s["left"]) + 1
			budget -= l
	note("%s recupera espaços de magia (Recuperação Arcana)." % nm(c))


func long_rest(c: Dictionary) -> void:
	if c.get("death", {}).get("dead", false):
		return
	c["hp"] = c["hp_max"]
	c["temp_hp"] = 0
	for die in c.get("hit_dice", {}):
		c["hit_dice"][die]["left"] = c["hit_dice"][die]["max"]
	for l in c.get("slots", {}):
		c["slots"][l]["left"] = c["slots"][l]["max"]
	if not c.get("pact", {}).is_empty():
		c["pact"]["left"] = c["pact"]["max"]
	for rid in c.get("resources", {}):
		c["resources"][rid]["left"] = c["resources"][rid]["max"]
	c["exhaustion"] = maxi(0, int(c.get("exhaustion", 0)) - 1)
	c["conditions"] = []
	c["effects"] = c["effects"].filter(func(e): return int(e.get("expire", {}).get("round", 0)) - g.round_num > 4800)
	c["death"] = {"success": 0, "fail": 0, "stable": false, "dead": false}
	c["relentless_uses"] = 0
	if Rules.tv(c, "resourceful"):
		c["heroic_inspiration"] = true
	c.erase("concentration")
	c.erase("mark")
	c["form"] = {}
	note("%s termina um descanso longo." % nm(c))
	changed(c)
