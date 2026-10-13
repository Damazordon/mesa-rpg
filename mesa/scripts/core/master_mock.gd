extends Node
## Mestre provisório (autoload "Master").
## Escolhe falas pré-escritas por evento, a partir de data/master_lines.json.
## Será trocado pelo modelo local; a interface não muda, porque tudo passa
## pelos sinais do Game (narration_added, taunt_said, check_requested).

const MIN_GAP := 8.0         # intervalo normal entre provocações
const MIN_GAP_FORCED := 3.0  # nem crítico fura esse intervalo, para não cansar
const IDLE_AFTER := 25.0     # segundos parado antes de cutucar

var mood := "neutro"
var _last_taunt := -100.0
var _idle := 0.0
var _idle_fired := false


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


## Interpreta texto livre. Versão provisória: palavras-chave em vez de IA.
func interpret(actor: Dictionary, text: String) -> void:
	notice_activity()
	Game._set_busy(true)
	await get_tree().create_timer(0.8).timeout
	Game._set_busy(false)
	var low := text.to_lower()
	for rule in Game.lines.get("checks", []):
		var re := RegEx.new()
		re.compile(rule["match"])
		if re.search(low) != null:
			Game.engine_log("Intenção interpretada: teste de %s, CD %d." % [rule["skill"], int(rule["dc"])])
			Game.narration_added.emit(str(rule["ask"]).replace("{nome}", actor["name"]))
			Game.request_check({"actor": actor["id"], "skill": rule["skill"], "attr": rule["attr"], "dc": int(rule["dc"])})
			if rule.get("absurd", false):
				react("plan_absurd", actor, true)
			return
	if low.contains("injust") or low.contains("roubou") or low.contains("roubado"):
		react("complaint", actor, true)
		return
	Game.engine_log("Sem mecânica: ação apenas narrativa.")
	Game.narration_added.emit(_pick("narration_generic"))


func on_check_result(actor: Dictionary, check: Dictionary, success: bool, d20: int) -> void:
	var line := _pick("check_success" if success else "check_fail")
	Game.narration_added.emit(line.replace("{nome}", actor["name"]).replace("{pericia}", check["skill"]))
	if d20 == 20:
		react("player_crit", actor, true)
	elif d20 == 1:
		react("player_fumble", actor, true)
