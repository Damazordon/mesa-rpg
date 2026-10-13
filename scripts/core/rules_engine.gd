class_name RulesEngine
extends RefCounted
## Motor de regras. Único lugar do jogo que rola dados e calcula resultados.
## A IA mestre nunca inventa números: ela só pode citar o que sai daqui.

static var _dice_re: RegEx


static func d(sides: int) -> int:
	return randi_range(1, sides)


static func mod(score: int) -> int:
	return floori((score - 10) / 2.0)


static func proficiency(level: int) -> int:
	return 2 + floori((level - 1) / 4.0)


## Converte "2d6+3" em {count: 2, sides: 6, mod: 3}.
static func parse(expr: String) -> Dictionary:
	if _dice_re == null:
		_dice_re = RegEx.new()
		_dice_re.compile("^\\s*(\\d*)d(\\d+)\\s*(?:([+-])\\s*(\\d+))?\\s*$")
	var m := _dice_re.search(expr)
	if m == null:
		return {"count": 0, "sides": 0, "mod": int(expr)}
	var count := 1
	if m.get_string(1) != "":
		count = int(m.get_string(1))
	var bonus := 0
	if m.get_string(3) != "":
		bonus = int(m.get_string(4))
		if m.get_string(3) == "-":
			bonus = -bonus
	return {"count": count, "sides": int(m.get_string(2)), "mod": bonus}


## Rola uma expressão. Em crítico, a quantidade de dados dobra (regra 5e).
static func roll(expr: String, crit := false) -> Dictionary:
	var p := parse(expr)
	var count: int = p["count"]
	if crit:
		count *= 2
	var sides: int = p["sides"]
	var bonus: int = p["mod"]
	var rolls: Array[int] = []
	var sum := 0
	for i in count:
		var r := d(sides)
		rolls.append(r)
		sum += r
	var total := maxi(0, sum + bonus)
	var shown := expr
	if crit:
		shown += " (dados dobrados)"
	var text := "%s: %s" % [shown, str(rolls)]
	if bonus != 0:
		text += " %+d" % bonus
	text += " = %d" % total
	return {"total": total, "rolls": rolls, "text": text}


## Resolve um ataque contra uma classe de armadura.
static func attack(to_hit: int, ac: int, damage: String, auto_hit := false) -> Dictionary:
	var out := {
		"auto": auto_hit, "d20": 0, "total": 0, "hit": false,
		"crit": false, "fumble": false, "dmg": 0, "dmg_text": ""
	}
	if auto_hit:
		out["hit"] = true
	else:
		var d20 := d(20)
		out["d20"] = d20
		out["total"] = d20 + to_hit
		out["crit"] = d20 == 20
		out["fumble"] = d20 == 1
		out["hit"] = d20 == 20 or (d20 != 1 and d20 + to_hit >= ac)
	if out["hit"]:
		var dr := roll(damage, out["crit"])
		out["dmg"] = dr["total"]
		out["dmg_text"] = dr["text"]
	return out
