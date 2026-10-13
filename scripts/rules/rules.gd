class_name Rules
extends RefCounted
## Regras do SRD 5.2.1 como funções puras sobre o dicionário de uma criatura.
## Não emite sinais nem anima nada: quem orquestra o turno é o Game.
##
## Formato da criatura (PJ ou monstro): veja CharBuilder e MonsterBuilder.

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const FT_TO_M := 0.3   # 5 pés = 1,5 m (convenção das edições em português)


static func m(ft: float) -> float:
	return ft * FT_TO_M


static func mod(score: int) -> int:
	return floori((score - 10) / 2.0)


static func score(c: Dictionary, ab: String) -> int:
	var form: Dictionary = c.get("form", {})
	if not form.is_empty() and ab in ["str", "dex", "con"]:
		return int(form["scores"][ab])
	return int(c.get("scores", {}).get(ab, 10))


static func amod(c: Dictionary, ab: String) -> int:
	return mod(score(c, ab))


static func pb(c: Dictionary) -> int:
	return int(c.get("pb", 2))


static func tv(c: Dictionary, key: String, default: Variant = false) -> Variant:
	return c.get("traits", {}).get(key, default)


# ---------------------------------------------------------------- condições e efeitos

static func has_condition(c: Dictionary, cid: String) -> bool:
	for cd in c.get("conditions", []):
		if cd["id"] == cid:
			return true
	return false


## Incapacitada: Incapacitated, ou condições que a incluem.
static func incapacitated(c: Dictionary) -> bool:
	for cid in ["incapacitated", "paralyzed", "petrified", "stunned", "unconscious"]:
		if has_condition(c, cid):
			return true
	return false


## Soma de um modificador numérico vindo dos efeitos ativos.
static func eff_sum(c: Dictionary, key: String) -> int:
	var s := 0
	for e in c.get("effects", []):
		s += int(e.get("mods", {}).get(key, 0))
	return s


static func eff_any(c: Dictionary, key: String) -> bool:
	for e in c.get("effects", []):
		if e.get("mods", {}).get(key, false):
			return true
	return false


## Junta listas de um modificador (ex.: "resist", "adv_save").
static func eff_list(c: Dictionary, key: String) -> Array:
	var out: Array = []
	for e in c.get("effects", []):
		for v in e.get("mods", {}).get(key, []):
			if not v in out:
				out.append(v)
	return out


static func eff_dice(c: Dictionary, key: String) -> Array:
	var out: Array = []
	for e in c.get("effects", []):
		var v: String = str(e.get("mods", {}).get(key, ""))
		if v != "":
			out.append(v)
	return out


static func has_effect(c: Dictionary, eid: String) -> bool:
	for e in c.get("effects", []):
		if e["id"] == eid:
			return true
	return false


# ---------------------------------------------------------------- bônus

static func save_prof(c: Dictionary, ab: String) -> bool:
	return ab in c.get("save_prof", [])


static func save_bonus(c: Dictionary, ab: String) -> int:
	var b: int
	var fixed: Dictionary = c.get("saves_fixed", {})
	if fixed.has(ab) and c.get("form", {}).is_empty():
		b = int(fixed[ab])
	else:
		b = amod(c, ab) + (pb(c) if save_prof(c, ab) else 0)
	return b + eff_sum(c, "save_bonus")


static func skill_prof(c: Dictionary, sk: String) -> int:
	## 0 nada, 1 proficiente, 2 especialista
	if sk in c.get("expertise", []):
		return 2
	if sk in c.get("skill_prof", []):
		return 1
	return 0


static func skill_bonus(c: Dictionary, sk: String) -> int:
	var fixed: Dictionary = c.get("skills_fixed", {})
	if fixed.has(sk):
		return int(fixed[sk])
	var ab := Srd.skill_ability(sk)
	var p := skill_prof(c, sk)
	var b := amod(c, ab) + pb(c) * p
	if p == 0 and tv(c, "jack_of_all_trades"):
		b += pb(c) / 2
	return b + eff_sum(c, "check_bonus")


static func check_bonus(c: Dictionary, ab: String) -> int:
	var b := amod(c, ab)
	if tv(c, "jack_of_all_trades"):
		b += pb(c) / 2
	return b


static func passive(c: Dictionary, sk: String) -> int:
	return 10 + skill_bonus(c, sk)


static func initiative_bonus(c: Dictionary) -> int:
	if c.has("initiative_fixed"):
		return int(c["initiative_fixed"])
	var b := amod(c, "dex")
	if tv(c, "alert"):
		b += pb(c)
	return b


static func spell_dc(c: Dictionary) -> int:
	var sc: Dictionary = c.get("spellcasting", {})
	if sc.has("dc_fixed"):
		return int(sc["dc_fixed"])
	return 8 + pb(c) + amod(c, sc.get("ability", "int")) + eff_sum(c, "spell_dc")


static func spell_attack(c: Dictionary) -> int:
	var sc: Dictionary = c.get("spellcasting", {})
	if sc.has("attack_fixed"):
		return int(sc["attack_fixed"])
	return pb(c) + amod(c, sc.get("ability", "int"))


# ---------------------------------------------------------------- CA e deslocamento

static func ac(c: Dictionary) -> int:
	var form: Dictionary = c.get("form", {})
	var base: int
	if not form.is_empty():
		base = int(form["ac"])
	elif c.has("ac_fixed"):
		base = int(c["ac_fixed"])
	else:
		base = base_ac(c)
	return base + eff_sum(c, "ac")


## CA sem efeitos temporários, a partir do equipamento e das características.
static func base_ac(c: Dictionary) -> int:
	var dex := amod(c, "dex")
	var arm: Dictionary = Srd.armor.get(c.get("armor_id", ""), {})
	var shield := 2 if c.get("shield", false) else 0
	var options: Array = []
	if not arm.is_empty():
		var dx := 0
		if arm.get("dex", false):
			dx = mini(dex, int(arm.get("dex_max", 99)))
		var v := int(arm["ac_base"]) + dx
		if tv(c, "defense_style"):
			v += 1
		options.append(v)
	else:
		options.append(10 + dex)
		if str(tv(c, "unarmored_defense", "")) == "con":
			options.append(10 + dex + amod(c, "con"))
		elif str(tv(c, "unarmored_defense", "")) == "wis" and shield == 0:
			options.append(10 + dex + amod(c, "wis"))
		if tv(c, "draconic_resilience"):
			options.append(10 + dex + amod(c, "cha"))
		if has_effect(c, "mage_armor") or tv(c, "armor_of_shadows_active"):
			options.append(13 + dex)
	var best := 0
	for o in options:
		best = maxi(best, int(o))
	return best + shield


static func speed_ft(c: Dictionary) -> int:
	var form: Dictionary = c.get("form", {})
	var s: int = int(form.get("speed_ft", c.get("speed_ft", 30)))
	if form.is_empty():
		var arm: Dictionary = Srd.armor.get(c.get("armor_id", ""), {})
		if int(arm.get("str_req", 0)) > score(c, "str"):
			s -= 10
		if tv(c, "fast_movement") and arm.get("category", "") != "heavy":
			s += 10
		if arm.is_empty() and not c.get("shield", false):
			s += int(tv(c, "unarmored_movement", 0))
	s -= 5 * int(c.get("exhaustion", 0))
	s += eff_sum(c, "speed_ft")
	if has_condition(c, "grappled") or has_condition(c, "restrained") or eff_any(c, "speed_zero"):
		return 0
	return maxi(0, s)


static func speed_m(c: Dictionary) -> float:
	return m(speed_ft(c))


# ---------------------------------------------------------------- dano

static func resists(c: Dictionary, dtype: String) -> bool:
	return dtype in c.get("resist", []) or dtype in eff_list(c, "resist")


static func immune(c: Dictionary, dtype: String) -> bool:
	return dtype in c.get("immune", [])


static func vulnerable(c: Dictionary, dtype: String) -> bool:
	return dtype in c.get("vuln", [])


## Dano depois de imunidade, resistência e vulnerabilidade. Retorna [valor, nota].
static func adjust_damage(c: Dictionary, amount: int, dtype: String) -> Array:
	if dtype == "" or amount <= 0:
		return [amount, ""]
	if immune(c, dtype):
		return [0, "imune"]
	var v := amount
	var note := ""
	if resists(c, dtype):
		v = v / 2
		note = "resistência"
	if vulnerable(c, dtype):
		v *= 2
		note = "vulnerável"
	return [v, note]


# ---------------------------------------------------------------- dados

static func d(sides: int) -> int:
	return randi_range(1, maxi(1, sides))


static var _dice_re: RegEx


## "2d6+3", "1d8 + 2", "4", "2d6+1d4+3" -> {"dice": [[2,6],[1,4]], "mod": 3}
static func parse(expr: String) -> Dictionary:
	if _dice_re == null:
		_dice_re = RegEx.create_from_string("([+-]?)\\s*(\\d*)d(\\d+)|([+-]?)\\s*(\\d+)")
	var out := {"dice": [], "mod": 0}
	for mm in _dice_re.search_all(expr.replace(" ", "")):
		if mm.get_string(3) != "":
			var n := 1 if mm.get_string(2) == "" else int(mm.get_string(2))
			if mm.get_string(1) == "-":
				n = -n
			out["dice"].append([n, int(mm.get_string(3))])
		elif mm.get_string(5) != "":
			var v := int(mm.get_string(5))
			out["mod"] += -v if mm.get_string(4) == "-" else v
	return out


## Rola uma expressão. crit dobra os dados; gwf trata 1 e 2 como 3 (Great Weapon Fighting).
static func roll(expr: String, crit := false, gwf := false) -> Dictionary:
	var p := parse(expr)
	var rolls: Array = []
	var total: int = p["mod"]
	for dd in p["dice"]:
		var count: int = absi(dd[0]) * (2 if crit else 1)
		var sign := -1 if dd[0] < 0 else 1
		for i in count:
			var r := d(dd[1])
			if gwf and r < 3:
				r = 3
			rolls.append(r * sign)
			total += r * sign
	var text := "%s%s: %s" % [expr, " (crítico, dados dobrados)" if crit else "", str(rolls)]
	if p["mod"] != 0:
		text += " %+d" % p["mod"]
	text += " = %d" % maxi(0, total)
	return {"total": maxi(0, total), "rolls": rolls, "text": text}


static func average(expr: String) -> int:
	var p := parse(expr)
	var t: float = p["mod"]
	for dd in p["dice"]:
		t += dd[0] * (dd[1] + 1) / 2.0
	return floori(t)


## Teste de d20. adv/dis se anulam. luck: rerrola 1 natural (Halfling).
## min10: trata 9 ou menos como 10 (Reliable Talent). Retorna o detalhe para o histórico.
static func d20(bonus: int, adv: bool, dis: bool, luck := false, min10 := false) -> Dictionary:
	var mode := "normal"
	if adv and not dis:
		mode = "adv"
	elif dis and not adv:
		mode = "dis"
	var a := d(20)
	var b := d(20)
	var notes: Array = []
	if luck and a == 1:
		a = d(20)
		notes.append("Sorte: rerrolou o 1")
	if luck and mode != "normal" and b == 1:
		b = d(20)
	var nat := a
	if mode == "adv":
		nat = maxi(a, b)
	elif mode == "dis":
		nat = mini(a, b)
	var used := nat
	if min10 and used < 10:
		used = 10
		notes.append("Talento Confiável: conta como 10")
	var dice_text := "[%d]" % a if mode == "normal" else "[%d, %d] %s" % [a, b, "vantagem" if mode == "adv" else "desvantagem"]
	return {"nat": nat, "total": used + bonus, "mode": mode, "dice_text": dice_text, "notes": notes, "bonus": bonus}


# ---------------------------------------------------------------- recursos

static func res_left(c: Dictionary, rid: String) -> int:
	return int(c.get("resources", {}).get(rid, {}).get("left", 0))


static func spend(c: Dictionary, rid: String, n := 1) -> bool:
	var r: Dictionary = c.get("resources", {}).get(rid, {})
	if r.is_empty() or int(r["left"]) < n:
		return false
	r["left"] = int(r["left"]) - n
	return true


## Menor espaço de magia disponível de nível >= lvl. 0 se não houver. Inclui Magia de Pacto.
static func lowest_slot(c: Dictionary, lvl: int) -> int:
	for l in range(maxi(1, lvl), 10):
		if slot_left(c, l) > 0:
			return l
	return 0


static func slot_left(c: Dictionary, lvl: int) -> int:
	var n := int(c.get("slots", {}).get(str(lvl), {}).get("left", 0))
	var pact: Dictionary = c.get("pact", {})
	if not pact.is_empty() and int(pact["level"]) == lvl:
		n += int(pact["left"])
	return n


static func spend_slot(c: Dictionary, lvl: int) -> bool:
	var pact: Dictionary = c.get("pact", {})
	if not pact.is_empty() and int(pact["level"]) == lvl and int(pact["left"]) > 0:
		pact["left"] = int(pact["left"]) - 1
		return true
	var s: Dictionary = c.get("slots", {}).get(str(lvl), {})
	if s.is_empty() or int(s["left"]) <= 0:
		return false
	s["left"] = int(s["left"]) - 1
	return true


## Recurso principal para a barra azul do painel do grupo: [nome, atual, máximo].
static func main_resource(c: Dictionary) -> Array:
	var total_max := 0
	var total_left := 0
	for l in c.get("slots", {}):
		total_max += int(c["slots"][l]["max"])
		total_left += int(c["slots"][l]["left"])
	var pact: Dictionary = c.get("pact", {})
	if not pact.is_empty():
		total_max += int(pact["max"])
		total_left += int(pact["left"])
	if total_max > 0:
		return ["espaços de magia", total_left, total_max]
	for rid in ["rages", "focus_points", "second_wind", "sorcery_points", "bardic_inspiration"]:
		var r: Dictionary = c.get("resources", {}).get(rid, {})
		if not r.is_empty():
			return [str(r["name"]).to_lower(), int(r["left"]), int(r["max"])]
	return ["", 0, 0]
