extends Node
## Conteúdo do SRD 5.2.1 (autoload "Srd").
##
## Camadas de nome, da mais forte para a mais fraca:
##   1. tema da mesa (data/themes/<id>.json, "rename")    ex.: Wizard -> "Netrunner"
##   2. tradução (data/i18n/pt_BR/*.json)                  ex.: Wizard -> "Mago"
##   3. texto original do SRD (inglês)
## O tema também pode esconder conteúdo ("allow"/"deny"), sem mudar nenhuma regra.
##
## Inclui material do System Reference Document 5.2.1 (Wizards of the Coast, CC-BY-4.0).

const SRD_DIR := "res://data/srd/"
const I18N_DIR := "res://data/i18n/pt_BR/"

var spells := {}
var classes := {}
var species := {}
var backgrounds := {}
var feats := {}
var weapons := {}
var armor := {}
var weapon_properties := {}
var gear := {}
var glossary := {}
var monsters := {}
var tables := {}

var names := {}       # tradução: {tipo: {id: nome}}
var texts := {}       # tradução: {tipo: {id: texto}}
var theme := {}       # tema ativo
var rules_auto := {}  # automação curada (data/rules/*.json)


func _ready() -> void:
	for kind in ["spells", "classes", "species", "backgrounds", "feats", "weapons", "armor", "gear", "glossary", "monsters"]:
		var arr: Array = _load(SRD_DIR + kind + ".json", [])
		var d := {}
		for e in arr:
			d[e["id"]] = e
		set(kind, d)
	weapon_properties = _load(SRD_DIR + "weapon_properties.json", {})
	tables = _load(SRD_DIR + "tables.json", {})
	names = _load(I18N_DIR + "names.json", {})
	texts = _load(I18N_DIR + "texts.json", {})
	rules_auto = {
		"spells": _load("res://data/rules/spells_auto.json", {}),
		"features": _load("res://data/rules/features_auto.json", {}),
	}
	# A automação curada tem prioridade sobre a derivada do texto.
	for id in rules_auto["spells"]:
		if spells.has(id):
			var a: Dictionary = spells[id].get("auto", {}).duplicate(true)
			a.merge(rules_auto["spells"][id], true)
			spells[id]["auto"] = a


func _load(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("JSON inválido em %s" % path)
		return fallback
	return parsed


func set_theme(t: Dictionary) -> void:
	theme = t


# ---------------------------------------------------------------- nomes e textos

## Nome para mostrar. kind: class, subclass, species, background, feat, spell, weapon, armor,
## gear, monster, feature, skill, ability, condition, dtype, school, property, action, currency.
func label(kind: String, id: String, fallback := "") -> String:
	var r: Dictionary = theme.get("rename", {}).get(kind, {})
	if r.has(id):
		return str(r[id])
	var n: Dictionary = names.get(kind, {})
	if n.has(id):
		return str(n[id])
	if fallback != "":
		return fallback
	var src := _source(kind, id)
	if src.has("name"):
		return str(src["name"])
	return id.replace("_", " ").capitalize()


## Texto de regra: tradução se houver, senão o original. Temas podem trocar o texto de sabor.
func text(kind: String, id: String, original := "") -> String:
	var r: Dictionary = theme.get("flavor", {}).get(kind, {})
	if r.has(id):
		return str(r[id])
	var t: Dictionary = texts.get(kind, {})
	if t.has(id):
		return themed(str(t[id]))
	if original != "":
		return original
	return str(_source(kind, id).get("text", ""))


## Texto completo da magia, com "Em nível superior"/"Melhoria de truque".
## A tradução já traz essas partes; o original em inglês recebe as dele.
func spell_text(sid: String) -> String:
	var sp: Dictionary = spells.get(sid, {})
	var t: Dictionary = texts.get("spell", {})
	var r: Dictionary = theme.get("flavor", {}).get("spell", {})
	if r.has(sid):
		return str(r[sid])
	if t.has(sid):
		return themed(str(t[sid]))
	var s := str(sp.get("text", ""))
	if str(sp.get("higher_level", "")) != "":
		s += "\n\nUsing a Higher-Level Spell Slot. " + str(sp["higher_level"])
	if str(sp.get("cantrip_upgrade", "")) != "":
		s += "\n\nCantrip Upgrade. " + str(sp["cantrip_upgrade"])
	return s


const _TIME := {"Action": "Ação", "Bonus Action": "Ação Bônus", "Reaction": "Reação", "minute": "minuto", "minutes": "minutos",
	"hour": "hora", "hours": "horas", "round": "rodada", "rounds": "rodadas", "day": "dia", "days": "dias"}


static func _pt_span(s: String) -> String:
	var out := PackedStringArray()
	for w in s.split(" "):
		out.append(str(_TIME.get(w, w)))
	return " ".join(out)


## "Ação · 45 m · Instantânea" — tempo de conjuração, alcance e duração em pt-BR.
func spell_meta(sid: String) -> String:
	var sp: Dictionary = spells.get(sid, {})
	var ct := str(sp.get("casting_time", ""))
	var ctp := ""
	if ct.begins_with("Reaction"):
		ctp = "Reação (gatilho)"
	elif ct.begins_with("Bonus Action,"):
		ctp = "Ação Bônus (após acertar)"
	elif ct.begins_with("Action ("):
		ctp = "Ação ou 8 horas"
	else:
		ctp = _pt_span(ct)
	if sp.get("ritual", false):
		ctp += " ou ritual"
	var rg := str(sp.get("range", ""))
	var rgp := ""
	match rg:
		"Self": rgp = "Pessoal"
		"Touch": rgp = "Toque"
		"Sight": rgp = "Visão"
		"Unlimited": rgp = "Ilimitado"
		"Special": rgp = "Especial"
		_:
			if rg.ends_with(" feet"):
				rgp = "%s m" % str(snappedf(float(rg.split(" ")[0]) * 0.3, 0.1)).trim_suffix(".0").replace(".", ",")
			elif rg.ends_with("mile") or rg.ends_with("miles"):
				rgp = "%s km" % str(snappedf(float(rg.split(" ")[0]) * 1.5, 0.1)).trim_suffix(".0").replace(".", ",")
			else:
				rgp = rg
	var du := str(sp.get("duration", ""))
	var dup := ""
	match du:
		"Instantaneous": dup = "Instantânea"
		"Until dispelled": dup = "Até ser dissipada"
		"Until dispelled or triggered": dup = "Até ser dissipada ou ativada"
		"Special": dup = "Especial"
		_:
			if du.begins_with("Concentration, up to "):
				dup = "Concentração, até " + _pt_span(du.trim_prefix("Concentration, up to "))
			elif du.begins_with("Up to "):
				dup = "Até " + _pt_span(du.trim_prefix("Up to "))
			else:
				dup = _pt_span(du)
	return "%s · %s · %s" % [ctp, rgp, dup]


## Troca nos textos traduzidos os nomes de classe pelos do tema da mesa
## ("truques de Clérigo" vira "truques de Sacerdote" no tema místico).
func themed(s: String) -> String:
	var r: Dictionary = theme.get("rename", {}).get("class", {})
	for cid in r:
		var pt := str(names.get("class", {}).get(cid, ""))
		if pt != "" and pt != str(r[cid]):
			var re := RegEx.create_from_string("\\b%s\\b" % pt)
			s = re.sub(s, str(r[cid]), true)
	return s


func is_translated(kind: String, id: String) -> bool:
	return texts.get(kind, {}).has(id)


func _source(kind: String, id: String) -> Dictionary:
	match kind:
		"class":
			return classes.get(id, {})
		"species":
			return species.get(id, {})
		"background":
			return backgrounds.get(id, {})
		"feat":
			return feats.get(id, {})
		"spell":
			return spells.get(id, {})
		"weapon":
			return weapons.get(id, {})
		"armor":
			return armor.get(id, {})
		"gear":
			return gear.get(id, {})
		"monster":
			return monsters.get(id, {})
		"glossary", "condition", "action":
			return glossary.get(id, {})
		"property":
			return weapon_properties.get(id, {})
	return {}


func ability_name(ab: String) -> String:
	return label("ability", ab, ab.to_upper())


func ability_abbr(ab: String) -> String:
	return str(names.get("ability_abbr", {}).get(ab, ab.to_upper()))


func skill_name(sk: String) -> String:
	return label("skill", sk, str(tables.get("skills", {}).get(sk, {}).get("name", sk)))


func skill_ability(sk: String) -> String:
	return str(tables.get("skills", {}).get(sk, {}).get("ability", "str"))


func skills() -> Array:
	return tables.get("skills", {}).keys()


func dtype_name(dt: String) -> String:
	return label("dtype", dt, dt)


func condition_name(cid: String) -> String:
	return label("condition", cid, cid.capitalize())


func currency() -> String:
	return str(theme.get("currency", "PO"))


# ---------------------------------------------------------------- filtros do tema

func allowed(kind: String, id: String) -> bool:
	var allow: Dictionary = theme.get("allow", {})
	if allow.has(kind):
		return id in allow[kind]
	var deny: Dictionary = theme.get("deny", {})
	if deny.has(kind):
		return not id in deny[kind]
	return true


func list(kind: String) -> Array:
	var src: Dictionary
	match kind:
		"class":
			src = classes
		"species":
			src = species
		"background":
			src = backgrounds
		"feat":
			src = feats
		"spell":
			src = spells
		"monster":
			src = monsters
		_:
			return []
	return src.keys().filter(func(id): return allowed(kind, id))


# ---------------------------------------------------------------- consultas de conteúdo

func proficiency(level: int) -> int:
	return 2 + (clampi(level, 1, 20) - 1) / 4


func xp_for_level(level: int) -> int:
	return int(tables.get("xp_by_level", {}).get(str(clampi(level, 1, 20)), 0))


func level_for_xp(xp: int) -> int:
	var lv := 1
	for l in range(2, 21):
		if xp >= xp_for_level(l):
			lv = l
	return lv


## Linha da tabela de níveis da classe.
func class_row(class_id: String, level: int) -> Dictionary:
	var c: Dictionary = classes.get(class_id, {})
	for row in c.get("levels", []):
		if int(row["level"]) == level:
			return row
	return {}


## Valor numérico de uma coluna da tabela ("—" vira 0, "+2" vira 2, "D6" vira 6).
func class_value(class_id: String, level: int, column: String) -> int:
	var v := str(class_row(class_id, level).get(column, "0"))
	var re := RegEx.create_from_string("-?\\d+")
	var m := re.search(v)
	return int(m.get_string()) if m else 0


func class_text(class_id: String, level: int, column: String) -> String:
	return str(class_row(class_id, level).get(column, ""))


## Acha arma, armadura ou item pelo nome que aparece no equipamento inicial.
## Entende plural, "Arcane Focus (Quarterstaff)", "Book (prayers)" e "Traveler's Clothes".
const ITEM_ALIASES := {"arrows": "ammunition", "bolts": "ammunition", "spellbook": "book",
	"traveler's clothes": "clothes, traveler's", "fine clothes": "clothes, fine",
	"musical instrument of your choice": "", "gaming set (same as above)": ""}


func find_item(item_name: String) -> Dictionary:
	var n := item_name.to_lower().strip_edges()
	if ITEM_ALIASES.has(n):
		n = ITEM_ALIASES[n]
		if n == "":
			return {}
	var tries: Array = [n]
	var paren := RegEx.create_from_string("^(.+?) \\((.+)\\)$").search(n)
	if paren:
		# "Arcane Focus (Quarterstaff)" é a arma; "Book (prayers)" é o livro
		tries.append(paren.get_string(2))
		tries.append(paren.get_string(1))
	for t in tries:
		for coll in [weapons, armor, gear]:
			for id in coll:
				var nm := str(coll[id]["name"]).to_lower()
				if nm == t or nm + "s" == t or nm + "es" == t:
					return coll[id]
	return {}


func item_kind(item: Dictionary) -> String:
	var id: String = item.get("id", "")
	if weapons.has(id):
		return "weapon"
	if armor.has(id):
		return "armor"
	return "gear"


func spells_for_class(class_id: String, level: int) -> Array:
	var c: Dictionary = classes.get(class_id, {})
	var out: Array = []
	for id in c.get("spell_list", {}).get(str(level), []):
		if spells.has(id) and allowed("spell", id):
			out.append(id)
	return out


func _enter_tree() -> void:
	if "--rules-tests" in OS.get_cmdline_user_args():
		_run_tests.call_deferred()


func _run_tests() -> void:
	RulesTests.run()
	await RulesTests.run_combat()
	await RulesTests.run_room()
	await RulesTests.run_terrain()
	RulesTests.run_icons()
	get_tree().quit(1 if RulesTests.fails > 0 else 0)
