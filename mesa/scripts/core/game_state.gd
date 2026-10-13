extends Node
## Estado da mesa (autoload "Game").
## Nesta fase é uma simulação para testar a interface: os números vêm do RulesEngine
## e as falas vêm do Master provisório. A interface nunca altera o estado direto:
## chama as funções daqui e escuta os sinais.

signal state_changed(id: String)
signal turn_changed(id: String, round_num: int)
signal narration_added(text: String)
signal player_spoke(actor_id: String, text: String)
signal taunt_said(text: String, mood: String)
signal dice_logged(entry: Dictionary)
signal engine_logged(text: String)
signal floating_text(id: String, text: String, kind: String)
signal check_requested(check: Dictionary)
signal check_cleared
signal busy_changed(is_busy: bool)
signal combat_ended(victory: bool)

const DATA_DIR := "res://data/"

var party: Array = []
var enemies: Array = []
var by_id: Dictionary = {}
var conditions: Dictionary = {}
var quests: Array = []
var bible: Dictionary = {}
var lines: Dictionary = {}
var scene_info: Dictionary = {}

var order: Array = []
var turn_index := 0
var round_num := 1
var in_combat := false
var pending_check: Dictionary = {}
var busy := false


func _ready() -> void:
	party = _load("party.json")
	enemies = _load("enemies.json")
	for c in _load("conditions.json"):
		conditions[c["id"]] = c
	quests = _load("quests.json")
	bible = _load("bible.json")
	lines = _load("master_lines.json")
	scene_info = _load("scene.json")
	for c in party:
		_normalize(c, "party")
	for e in enemies:
		_normalize(e, "enemy")


func _load(file: String) -> Variant:
	var f := FileAccess.open(DATA_DIR + file, FileAccess.READ)
	if f == null:
		push_error("Não consegui abrir %s" % file)
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("JSON inválido em %s" % file)
		return []
	return parsed


func _normalize(c: Dictionary, side: String) -> void:
	c["side"] = side
	for k in ["hp", "hp_max", "res", "res_max", "ac", "level", "upgrade_points", "to_hit", "dex"]:
		if c.has(k):
			c[k] = int(c[k])
	if c.has("attrs"):
		for k in c["attrs"].keys():
			c["attrs"][k] = int(c["attrs"][k])
	var p: Array = c.get("pos", [0.5, 0.5])
	c["pos"] = Vector2(float(p[0]), float(p[1]))
	var conds: Array = []
	for cd in c.get("conditions", []):
		conds.append({"id": cd["id"], "rounds": int(cd.get("rounds", -1))})
	c["conditions"] = conds
	by_id[c["id"]] = c


# ---------------------------------------------------------------- consultas

func current() -> Dictionary:
	if order.is_empty():
		return {}
	return by_id[order[turn_index]]


func is_alive(c: Dictionary) -> bool:
	return int(c.get("hp", 0)) > 0


func is_party_turn() -> bool:
	var c := current()
	return in_combat and not c.is_empty() and c["side"] == "party" and is_alive(c)


func dex_mod(c: Dictionary) -> int:
	if c.has("attrs"):
		return RulesEngine.mod(c["attrs"]["des"])
	return int(c.get("dex", 0))


func has_condition(c: Dictionary, cond_id: String) -> bool:
	for cd in c["conditions"]:
		if cd["id"] == cond_id:
			return true
	return false


## Faixa de distância usada no MVP (zonas, sem grid).
func zone_between(a: Dictionary, b: Dictionary) -> String:
	var dist: float = (a["pos"] - b["pos"]).length()
	if dist < 0.2:
		return "perto"
	if dist < 0.42:
		return "médio"
	return "longe"


func health_word(c: Dictionary) -> String:
	var hp: int = c["hp"]
	if hp <= 0:
		return "caído"
	var ratio := float(hp) / float(c["hp_max"])
	if ratio >= 1.0:
		return "intacto"
	if ratio > 0.5:
		return "ferido"
	return "muito ferido"


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


# ---------------------------------------------------------------- turnos

func start_combat() -> void:
	in_combat = true
	var rolls: Array = []
	for c in party + enemies:
		var bonus := dex_mod(c)
		var d20 := RulesEngine.d(20)
		rolls.append({"id": c["id"], "init": d20 + bonus, "d20": d20, "bonus": bonus})
	rolls.sort_custom(func(a, b): return a["init"] > b["init"])
	order = rolls.map(func(r): return r["id"])
	var names := PackedStringArray()
	var details := PackedStringArray()
	for r in rolls:
		var nm: String = by_id[r["id"]]["name"]
		names.append("%s %d" % [nm, r["init"]])
		details.append("%s: d20 [%d] %+d = %d" % [nm, r["d20"], r["bonus"], r["init"]])
	log_dice("", "Iniciativa", ", ".join(names), "\n".join(details), "neutral")
	engine_log("Ordem de iniciativa definida por d20 + Destreza.")
	narration_added.emit(scene_info.get("intro", ""))
	turn_index = 0
	round_num = 1
	_begin_turn()


func _begin_turn() -> void:
	var c := current()
	_tick_conditions(c)
	turn_changed.emit(c["id"], round_num)
	if c["side"] == "party" and not is_alive(c):
		engine_log("%s está inconsciente e perde o turno." % c["name"])
		_set_busy(true)
		await _wait(1.0)
		end_turn()
		return
	if c["side"] == "enemy":
		_set_busy(true)
		await _wait(1.4)
		_enemy_act(c)
	else:
		_set_busy(false)
		Master.on_turn_started(c)


func _tick_conditions(c: Dictionary) -> void:
	var kept: Array = []
	var changed := false
	for cd in c["conditions"]:
		if cd["rounds"] > 0:
			cd["rounds"] -= 1
			changed = true
			if cd["rounds"] == 0:
				engine_log("%s: %s terminou." % [c["name"], conditions[cd["id"]]["name"]])
				continue
		kept.append(cd)
	c["conditions"] = kept
	if changed:
		state_changed.emit(c["id"])


func end_turn() -> void:
	if not in_combat:
		return
	clear_check()
	var n := order.size()
	for i in n:
		turn_index = (turn_index + 1) % n
		if turn_index == 0:
			round_num += 1
		var c := current()
		if c["side"] == "party" or is_alive(c):
			break
	_begin_turn()


func _check_end() -> void:
	if not in_combat:
		return
	if enemies.all(func(e): return not is_alive(e)):
		in_combat = false
		narration_added.emit(scene_info.get("victory", ""))
		Master.react("victory", {}, true)
		combat_ended.emit(true)
	elif party.all(func(p): return not is_alive(p)):
		in_combat = false
		narration_added.emit(scene_info.get("defeat", ""))
		Master.react("defeat", {}, true)
		combat_ended.emit(false)


# ---------------------------------------------------------------- ações do grupo

func use_ability(actor_id: String, ability: Dictionary, target_ids: Array) -> void:
	if busy or not is_party_turn() or current()["id"] != actor_id:
		return
	var a: Dictionary = by_id[actor_id]
	var cost := int(ability.get("cost", 0))
	if cost > a["res"]:
		engine_log("Recusado: %s precisa de %d de %s." % [ability["name"], cost, a["res_name"]])
		return
	_set_busy(true)
	Master.notice_activity()
	if cost > 0:
		a["res"] -= cost
		engine_log("%s gastou %d de %s." % [a["name"], cost, a["res_name"]])
		state_changed.emit(actor_id)
	match ability["kind"]:
		"attack", "spell":
			for t_id in target_ids:
				_resolve_attack(a, ability, by_id[t_id])
				await _wait(0.3)
		"heal":
			_resolve_heal(a, ability)
		"cure":
			_resolve_cure(a, ability)
	_check_end()
	if in_combat:
		await _wait(1.0)
		end_turn()


func _resolve_attack(a: Dictionary, ab: Dictionary, t: Dictionary) -> void:
	var res := RulesEngine.attack(int(ab.get("to_hit", 0)), int(t["ac"]), str(ab["damage"]), bool(ab.get("auto_hit", false)))
	var title := "%s: %s em %s" % [a["name"], ab["name"], t["name"]]
	var summary := ""
	var detail := ""
	var result := "hit"
	if res["auto"]:
		summary = "acerto automático, %d de dano" % res["dmg"]
		detail = "Não rola ataque. Dano %s %s." % [res["dmg_text"], ab["dtype"]]
	else:
		detail = "d20: [%d] %+d de ataque = %d contra CA %d." % [res["d20"], ab.get("to_hit", 0), res["total"], t["ac"]]
		if res["crit"]:
			result = "crit"
			summary = "20 natural, crítico: %d de dano" % res["dmg"]
		elif res["fumble"]:
			result = "fumble"
			summary = "1 natural, erro automático"
		elif res["hit"]:
			summary = "%d contra CA %d, acerto: %d de dano" % [res["total"], t["ac"], res["dmg"]]
		else:
			result = "miss"
			summary = "%d contra CA %d, errou" % [res["total"], t["ac"]]
		if res["hit"]:
			detail += " Dano %s %s." % [res["dmg_text"], ab["dtype"]]
	log_dice(a["id"], title, summary, detail, result)

	if res["hit"]:
		_apply_damage(t, res["dmg"], "crit" if res["crit"] else "damage")
		if res["crit"]:
			Master.react("player_crit", a, true)
		if not is_alive(t) and t["side"] == "enemy":
			Master.react("enemy_down", a)
		elif not is_alive(t) and t["side"] == "party":
			Master.react("party_down", t, true)
	else:
		floating_text.emit(t["id"], "errou", "miss")
		if res["fumble"]:
			Master.react("player_fumble", a, true)
		else:
			Master.react("player_miss", a)


func _apply_damage(t: Dictionary, amount: int, kind: String) -> void:
	t["hp"] = maxi(0, t["hp"] - amount)
	floating_text.emit(t["id"], "-%d" % amount, kind)
	if t["hp"] == 0:
		if t["side"] == "enemy":
			engine_log("%s caiu." % t["name"])
		elif not has_condition(t, "inconsciente"):
			t["conditions"].append({"id": "inconsciente", "rounds": -1})
			engine_log("%s está inconsciente." % t["name"])
	state_changed.emit(t["id"])


func _resolve_heal(a: Dictionary, ab: Dictionary) -> void:
	var r := RulesEngine.roll(str(ab["damage"]))
	var before: int = a["hp"]
	a["hp"] = mini(a["hp_max"], a["hp"] + r["total"])
	var gained: int = a["hp"] - before
	if before == 0 and a["hp"] > 0:
		a["conditions"] = a["conditions"].filter(func(cd): return cd["id"] != "inconsciente")
	log_dice(a["id"], "%s: %s" % [a["name"], ab["name"]], "recuperou %d PV" % gained, r["text"] + ".", "heal")
	floating_text.emit(a["id"], "+%d" % gained, "heal")
	state_changed.emit(a["id"])


func _resolve_cure(a: Dictionary, ab: Dictionary) -> void:
	var cond_id: String = ab.get("cures", "")
	var had := has_condition(a, cond_id)
	a["conditions"] = a["conditions"].filter(func(cd): return cd["id"] != cond_id)
	var cname: String = conditions.get(cond_id, {}).get("name", cond_id)
	if had:
		engine_log("%s usou %s: %s removido." % [a["name"], ab["name"], cname])
		floating_text.emit(a["id"], "curado", "heal")
	else:
		engine_log("%s usou %s, mas não estava %s." % [a["name"], ab["name"], cname.to_lower()])
	state_changed.emit(a["id"])


# ---------------------------------------------------------------- inimigos

func _enemy_act(e: Dictionary) -> void:
	var targets := party.filter(func(p): return is_alive(p))
	if targets.is_empty():
		_check_end()
		return
	# Inimigos jogam com inteligência: focam quem está mais fraco.
	targets.sort_custom(func(x, y): return x["hp"] < y["hp"])
	var t: Dictionary = targets[0]
	engine_log("%s mira %s (o alvo com menos PV)." % [e["name"], t["name"]])
	var res := RulesEngine.attack(e["to_hit"], t["ac"], e["damage"])
	var title := "%s ataca %s" % [e["name"], t["name"]]
	var detail := "d20: [%d] %+d de ataque = %d contra CA %d." % [res["d20"], e["to_hit"], res["total"], t["ac"]]
	if res["hit"]:
		detail += " Dano %s %s." % [res["dmg_text"], e["dtype"]]
		var result := "crit" if res["crit"] else "hit"
		log_dice(e["id"], title, "%d contra CA %d, acerto: %d de dano" % [res["total"], t["ac"], res["dmg"]], detail, result)
		_apply_damage(t, res["dmg"], "crit" if res["crit"] else "damage")
		if not is_alive(t):
			Master.react("party_down", t, true)
		elif res["dmg"] >= 6:
			Master.react("enemy_hit_hard", t)
	else:
		log_dice(e["id"], title, "%d contra CA %d, errou" % [res["total"], t["ac"]], detail, "miss")
		floating_text.emit(t["id"], "errou", "miss")
	_check_end()
	if in_combat:
		await _wait(1.0)
		end_turn()


# ---------------------------------------------------------------- texto livre e testes

func player_free_text(actor_id: String, text: String) -> void:
	if not is_party_turn() or busy:
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


func resolve_check() -> void:
	if pending_check.is_empty() or busy:
		return
	var chk := pending_check
	var a: Dictionary = by_id[chk["actor"]]
	var bonus := RulesEngine.mod(a["attrs"][chk["attr"]])
	var source := "de atributo"
	for s in a.get("skills", []):
		if s["name"] == chk["skill"]:
			bonus = int(s["bonus"])
			source = "de perícia"
	var d20 := RulesEngine.d(20)
	var total := d20 + bonus
	var ok := total >= int(chk["dc"])
	log_dice(a["id"], "%s: teste de %s" % [a["name"], chk["skill"]],
		"%d contra CD %d, %s" % [total, chk["dc"], "sucesso" if ok else "falha"],
		"d20: [%d] %+d %s = %d." % [d20, bonus, source, total], "success" if ok else "fail")
	floating_text.emit(a["id"], "sucesso" if ok else "falhou", "heal" if ok else "miss")
	clear_check()
	Master.on_check_result(a, chk, ok, d20)


func free_roll(actor_id: String, sides: int) -> void:
	var r := RulesEngine.d(sides)
	var who: String = by_id[actor_id]["name"] if by_id.has(actor_id) else "Mesa"
	log_dice(actor_id, "%s: rolagem livre" % who, "d%d: %d" % [sides, r], "Rolagem sem efeito no jogo.", "neutral")
	Master.notice_activity()


# ---------------------------------------------------------------- upgrades

func buy_upgrade(actor_id: String, upgrade: Dictionary) -> bool:
	var a: Dictionary = by_id[actor_id]
	if in_combat:
		engine_log("Recusado: upgrades só fora de combate.")
		return false
	if int(upgrade["cost"]) > a["upgrade_points"]:
		engine_log("Recusado: pontos insuficientes.")
		return false
	a["upgrade_points"] -= int(upgrade["cost"])
	a["upgrades_owned"].append(upgrade["name"])
	a["upgrades"].erase(upgrade)
	engine_log("%s comprou %s." % [a["name"], upgrade["name"]])
	state_changed.emit(actor_id)
	return true
