extends Node
## Mestre provisório (autoload "Master").
##
## Faz o mesmo trabalho que o modelo de IA fará, com padrões de frase no lugar da IA:
##   1. entende a intenção do jogador (persuadir, intimidar, enganar, perguntar, esconder...)
##   2. descobre o alvo: o token clicado ou o nome citado na frase
##   3. calcula a dificuldade pelo contexto e explica o motivo
##   4. propõe consequências para sucesso e falha
##
## A proposta segue o formato que a IA vai emitir (JSON):
##   {skill, attr, dc, dc_reason, target, intent, ask, success_text, fail_text,
##    on_success: [efeitos], on_fail: [efeitos], uses_action}
## Efeitos aceitos pelo motor: side, condition, flee, reveal, bible_note, taunt.
## O motor rola o dado e só aplica efeitos válidos. A IA nunca mexe nos números.

const MIN_GAP := 8.0         # intervalo normal entre provocações
const MIN_GAP_FORCED := 3.0  # nem crítico fura esse intervalo, para não cansar
const IDLE_AFTER := 25.0     # segundos parado antes de cutucar

var mood := "neutro"
var _last_taunt := -100.0
var _idle := 0.0
var _idle_fired := false
var _revealed := {}


func _process(delta: float) -> void:
	if Game.is_party_turn() and not Game.busy:
		_idle += delta
		if _idle > IDLE_AFTER and not _idle_fired:
			_idle_fired = true
			react("idle", Game.current(), true)


func on_turn_started(_c: Dictionary) -> void:
	_idle = 0.0
	_idle_fired = false


func notice_activity() -> void:
	_idle = 0.0


func _pick(key: String) -> String:
	var pool: Array = Game.lines.get(key, [])
	if pool.is_empty():
		return ""
	return str(pool.pick_random())


func react(event: String, who: Dictionary = {}, force := false) -> void:
	var pool: Array = Game.lines.get("taunts", {}).get(event, [])
	if pool.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap := now - _last_taunt
	if gap < MIN_GAP_FORCED or (not force and gap < MIN_GAP):
		return
	_last_taunt = now
	var line := str(pool.pick_random()).replace("{nome}", str(who.get("name", "vocês")))
	mood = Game.lines.get("moods", {}).get(event, "neutro")
	Game.taunt_said.emit(line, mood)


func mood_text() -> String:
	return Game.lines.get("mood_text", {}).get(mood, "")


func _fill(text: String, actor: Dictionary, target: Dictionary, dc := 0, skill := "") -> String:
	return text.replace("{nome}", str(actor.get("name", ""))) \
		.replace("{alvo}", str(target.get("name", "ele"))) \
		.replace("{cd}", str(dc)).replace("{pericia}", skill)


# ---------------------------------------------------------------- alvo

## Alvo da frase: primeiro o token clicado; depois um nome citado; "goblin" genérico
## vira o goblin vivo mais próximo de quem fala.
func find_target(actor: Dictionary, low: String) -> Dictionary:
	if Game.selected_target != "":
		var sel: Dictionary = Game.by_id.get(Game.selected_target, {})
		if not sel.is_empty() and Game.is_alive(sel):
			return sel
	var others: Array = Game.enemies.filter(func(e): return Game.is_alive(e))
	# nome completo primeiro ("goblin a"), depois a primeira palavra ("hobgoblin", "goblin")
	for e in others:
		if low.contains(str(e["name"]).to_lower()):
			return e
	var matches: Array = []
	for e in others:
		var word := str(e["name"]).to_lower().split(" ")[0]
		var re := RegEx.new()
		re.compile("\\b%s\\b" % word)
		if re.search(low) != null:
			matches.append(e)
	if matches.is_empty():
		return {}
	matches.sort_custom(func(x, y): return Game.dist_between(actor, x) < Game.dist_between(actor, y))
	return matches[0]


# ---------------------------------------------------------------- interpretação

func interpret(actor: Dictionary, text: String) -> void:
	notice_activity()
	Game._set_busy(true)
	await get_tree().create_timer(0.7).timeout
	Game._set_busy(false)
	var low := text.to_lower()
	for hint in Game.lines.get("hints", []):
		if _matches(hint["match"], low):
			if hint.get("taunt", "") != "":
				react(hint["taunt"], actor, true)
			else:
				Game.narration_added.emit(_fill(hint["say"], actor, {}))
			return
	for intent in Game.lines.get("intents", []):
		if _matches(intent["match"], low):
			_handle_intent(actor, intent, low)
			return
	# Não entendeu: pergunta, em vez de inventar uma regra.
	Game.engine_log("Intenção não reconhecida: o mestre pediu mais detalhes.")
	Game.narration_added.emit(_fill(_pick("clarify"), actor, {}))


func _matches(pattern: String, low: String) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	return re.search(low) != null


func _handle_intent(actor: Dictionary, intent: Dictionary, low: String) -> void:
	var target: Dictionary = {}
	if intent.get("needs_target", false):
		target = find_target(actor, low)
		if target.is_empty():
			Game.engine_log("Intenção %s sem alvo: o mestre perguntou com quem." % intent["id"])
			Game.narration_added.emit(_fill(_pick("ask_target"), actor, {}))
			return
		if Game.dist_between(actor, target) > float(intent.get("max_m", 18.0)):
			Game.narration_added.emit(_fill(_pick("too_far"), actor, target))
			Game.engine_log("Recusado: %s está a %s, longe demais para isso." % [target["name"], Game.fmt_m(Game.dist_between(actor, target))])
			return
	var proposal := _build_proposal(actor, intent, target)
	# Quem já está do lado do grupo responde sem teste.
	if proposal.get("free", false):
		Game.engine_log("Sem teste: %s já coopera." % target["name"])
		Game.apply_effects(proposal["on_success"], actor, target.get("id", ""))
		return
	Game.engine_log("Intenção interpretada: %s%s, CD %d (%s)." % [intent["skill"],
		(" com %s" % target["name"]) if not target.is_empty() else "", proposal["dc"], proposal["dc_reason"]])
	Game.narration_added.emit(proposal["ask"])
	if intent.get("absurd", false):
		react("plan_absurd", actor, true)
	Game.request_check(proposal)


func _build_proposal(actor: Dictionary, intent: Dictionary, target: Dictionary) -> Dictionary:
	var dc := int(intent["dc"])
	var reasons := PackedStringArray(["base %d" % dc])
	var on_success: Array = intent.get("effects_success", []).duplicate(true)
	var on_fail: Array = intent.get("effects_fail", []).duplicate(true)
	var success_text: String = intent.get("success", "")
	if not target.is_empty():
		var wounded: bool = float(target["hp"]) / float(target["hp_max"]) <= 0.5
		if wounded and intent.get("easier_if_wounded", false):
			dc -= 3
			reasons.append("ferido -3")
		if target.get("boss", false):
			dc += 5
			reasons.append("é o chefe +5")
		if Game.has_condition(target, "amedrontado") and intent["id"] != "intimidar":
			dc -= 2
			reasons.append("amedrontado -2")
		if intent.get("harder_with_friends", false):
			var watchers := Game.enemies.filter(func(e): return e["id"] != target["id"] \
				and Game.is_alive(e) and Game.is_foe(e) and Game.dist_between(e, target) <= 9.0)
			if not watchers.is_empty():
				dc += 2 * watchers.size()
				reasons.append("%d companheiro(s) olhando +%d" % [watchers.size(), 2 * watchers.size()])
		if wounded and intent.has("effects_success_wounded"):
			on_success = intent["effects_success_wounded"].duplicate(true)
			success_text = intent.get("success_wounded", success_text)
		if intent["id"] == "interrogar":
			var rumor := _next_rumor()
			on_success = [{"type": "reveal", "text": _fill(rumor.get("text", ""), actor, target)}]
			if rumor.has("bible"):
				on_success.append({"type": "bible_note", "name": rumor["bible"]["name"], "text": rumor["bible"]["text"]})
			if target["side"] != "enemy":
				return {"free": true, "on_success": on_success}
	return {
		"actor": actor["id"], "target": target.get("id", ""), "intent": intent["id"],
		"skill": intent["skill"], "attr": intent["attr"], "dc": dc,
		"dc_reason": ", ".join(reasons),
		"ask": _fill(intent["ask"], actor, target, dc, intent["skill"]),
		"success_text": _fill(success_text, actor, target, dc, intent["skill"]),
		"fail_text": _fill(intent.get("fail", ""), actor, target, dc, intent["skill"]),
		"on_success": on_success, "on_fail": on_fail,
		"uses_action": intent.get("uses_action", true),
	}


func _next_rumor() -> Dictionary:
	for r in Game.lines.get("rumors", []):
		if not _revealed.has(r["text"]):
			_revealed[r["text"]] = true
			return r
	return {"text": _pick("rumor_repeat")}


## Magia ou característica sem automação: o mestre narra. A IA vai decidir o efeito
## (com efeitos da lista permitida); o mestre provisório só descreve.
func on_manual_effect(actor: Dictionary, effect_name: String, rules_text: String) -> void:
	var line := _pick("manual_effect")
	if line == "":
		line = "{nome} usa {efeito}. Descreva o que quer com isso, que eu digo o que acontece."
	Game.narration_added.emit(line.replace("{nome}", str(actor.get("name", ""))).replace("{efeito}", effect_name))
	Game.engine_log("Efeito sem automação (%s): o mestre arbitra. Texto da regra disponível na ficha." % effect_name)


func on_check_result(actor: Dictionary, check: Dictionary, success: bool, d20: int, margin: int) -> void:
	var line: String = check.get("success_text" if success else "fail_text", "")
	if line == "":
		line = _fill(_pick("check_success" if success else "check_fail"), actor, {}, 0, check["skill"])
	Game.narration_added.emit(line)
	if d20 == 20:
		react("player_crit", actor, true)
	elif d20 == 1 or margin <= -8:
		react("player_fumble", actor, true)
