extends "res://scripts/core/master_mock.gd"
## Mestre com IA local (autoload "Master").
##
## Estende o mestre provisório: tudo que a IA não cobre (provocações, ociosidade, humor,
## efeitos manuais) continua vindo do mock. A IA só faz o que o mock faz com padrões de frase:
## ler o que o jogador disse, escolher UMA intenção do catálogo (master_lines.json) e escrever
## o texto (pergunta, sucesso, falha). CD, alvo, distância e efeitos continuam sendo calculados
## pelo motor (_build_proposal). A IA nunca mexe nos números.
##
## Se o Ollama estiver fechado, demorar demais ou devolver lixo, cai no mock.
## Níveis do mestre (Game.settings["master_level"]): calmo, normal, cinico.

signal level_changed(level: String)

const URL := "http://127.0.0.1:11434/api/chat"
const MODEL := "qwen3.5:4b"
const TIMEOUT_S := 25.0
## Janela de contexto ÚNICA para todas as chamadas (mestre, aventura, lore). O Ollama recarrega o
## modelo na VRAM quando o num_ctx muda entre chamadas; com valores diferentes (4096 aqui e 8192
## na geração) cada troca custava uma recarga inteira. Também mantém o cache de prefixo valendo.
const NUM_CTX := 8192
## Quanto tempo o Ollama mantém o modelo na memória depois da última chamada (padrão dele: 5 min).
const KEEP_ALIVE := "30m"
## Teto de tokens de saída do mestre (a resposta JSON normal tem ~150). Só corta texto descontrolado.
const MASTER_MAX_TOKENS := 450

## Perfil de cada nível: tom (prompt), ajuste de CD (motor), temperatura e punição na falha.
const LEVELS := {
	"calmo": {
		"label": "Calmo",
		"dc_mod": -2,
		"temp": 0.7,
		"tone": "Você é um mestre paciente e acolhedor. Incentive o grupo, dê dicas sutis, trate falhas como complicações leves e divertidas. Nunca humilhe ninguém.",
		"fail_damage": "",
	},
	"normal": {
		"label": "Normal",
		"dc_mod": 0,
		"temp": 0.7,
		"tone": "Você é um mestre neutro e justo. Narre com clareza, sem favorecer nem atrapalhar o grupo.",
		"fail_damage": "",
	},
	"cinico": {
		"label": "Cínico",
		"dc_mod": 2,
		"temp": 0.8,
		"tone": "Você é um mestre cínico, sarcástico e implacável. Cada erro do grupo tem um preço, e você faz questão de comentar. Seja ácido, mas sempre justo: nunca invente regras nem trapaceie nos números.",
		"fail_damage": "1d4",
	},
}

var level := "normal"
var _http: HTTPRequest
var _warm: HTTPRequest
var _pending := false


func _ready() -> void:
	level = str(Game.settings.get("master_level", "normal"))
	if not LEVELS.has(level):
		level = "normal"
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	add_child(_http)
	# Requisição própria para o aquecimento: o HTTPRequest atende um pedido por vez.
	_warm = HTTPRequest.new()
	_warm.timeout = 180.0
	add_child(_warm)
	warm_up.call_deferred()


## Carrega o modelo na VRAM em segundo plano (mensagens vazias = só carregar, o Ollama não gera
## nada). Assim o primeiro pedido de verdade não paga a carga do disco. Ignora a resposta:
## se o Ollama estiver fechado, nada acontece. Não roda nos testes sem janela.
func warm_up() -> void:
	if DisplayServer.get_name() == "headless" or _warm == null:
		return
	if _warm.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var body := {"model": MODEL, "messages": [], "stream": false, "keep_alive": KEEP_ALIVE,
		"options": {"num_ctx": NUM_CTX}}
	_warm.request(URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))


## Corpo padrão das chamadas ao Ollama, para mestre, aventura e lore usarem os MESMOS parâmetros
## de carga (modelo, num_ctx, keep_alive). Mudar um deles em uma chamada só força recarga.
func chat_body(system: String, user: String, temp: float, max_tokens: int) -> Dictionary:
	return {
		"model": MODEL,
		"stream": false,
		"think": false,
		"format": "json",
		"keep_alive": KEEP_ALIVE,
		"options": {"temperature": temp, "num_ctx": NUM_CTX, "num_predict": max_tokens},
		"messages": [
			{"role": "system", "content": system},
			{"role": "user", "content": user},
		],
	}


func set_level(new_level: String) -> void:
	if not LEVELS.has(new_level) or new_level == level:
		return
	level = new_level
	Game.settings["master_level"] = level
	Game.save_settings()
	Game.engine_log("Nível do mestre: %s." % LEVELS[level]["label"])
	level_changed.emit(level)


# ---------------------------------------------------------------- interpretação com IA

func interpret(actor: Dictionary, text: String) -> void:
	if _pending:
		return
	notice_activity()
	# Frases que o mock já trata como dica/provocação não precisam de IA.
	var low := text.to_lower()
	for hint in Game.lines.get("hints", []):
		if _matches(hint["match"], low):
			super.interpret(actor, text)
			return
	_pending = true
	Game._set_busy(true)
	var answer := await _ask_model(actor, text)
	Game._set_busy(false)
	_pending = false
	if answer.is_empty():
		Game.engine_log("IA indisponível ou resposta inválida: usando o mestre provisório.")
		super.interpret(actor, text)
		return
	_apply_answer(actor, answer)


func _catalog() -> Array:
	var out := []
	for it in Game.lines.get("intents", []):
		out.append({"id": it["id"], "skill": it["skill"], "needs_target": it.get("needs_target", false)})
	return out


func _scene_context(actor: Dictionary) -> String:
	var foes := []
	for e in Game.enemies:
		if Game.is_alive(e):
			foes.append("%s (a %s)" % [e["name"], Game.fmt_m(Game.dist_between(actor, e))])
	var allies := []
	for p in Game.party:
		if Game.is_alive(p):
			allies.append(str(p["name"]))
	# Premissa da sala (tela de criação de sala): tema, tom e a história escrita pelo mestre humano.
	var premise := ""
	var story := str(Game.adventure.get("story", "")).strip_edges()
	if story != "":
		premise = "Tema: %s (tom: %s).\nPremissa da aventura: %s\n" % [str(Game.theme.get("name", "")), str(Game.theme.get("tone", "")), story.left(500)]
	return "%sCena: %s. %s\nQuem fala: %s.\nGrupo: %s.\nInimigos vivos: %s.\nEm combate: %s." % [
		premise, str(Game.scene_info.get("chapter", "")), str(Game.scene_info.get("description", "")),
		actor["name"], ", ".join(allies), ", ".join(foes) if not foes.is_empty() else "nenhum",
		"sim" if Game.in_combat else "não"]


func _system_prompt() -> String:
	var ids := []
	for it in _catalog():
		ids.append(it["id"])
	var t := "{tone}\n\nVocê é o mestre de uma mesa de D&D 5.2 (SRD). Responda SEMPRE em português do Brasil.\n"
	t += "O jogador escreve o que seu personagem tenta fazer. Escolha UMA intenção do catálogo que melhor "
	t += "representa a tentativa, ou \"nenhuma\" se for só conversa ou algo impossível.\n"
	t += "Catálogo de intenções: {ids}\n"
	t += "Responda APENAS com JSON neste formato:\n"
	t += "{\"intent\": \"<id ou nenhuma>\", \"target\": \"<nome do inimigo citado ou vazio>\", "
	t += "\"ask\": \"<1-2 frases pedindo o teste, sem citar CD>\", \"success_text\": \"<1-2 frases se der certo>\", "
	t += "\"fail_text\": \"<1-2 frases se der errado>\", \"say\": \"<resposta curta do mestre se a intenção for nenhuma>\"}\n"
	t += "Regras: nunca cite números, CD, dano ou resultado de dados. Não invente criaturas nem itens que não estão na cena. "
	t += "Frases curtas."
	return t.format({"tone": LEVELS[level]["tone"], "ids": ", ".join(ids)})


func _ask_model(actor: Dictionary, text: String) -> Dictionary:
	var body := chat_body(_system_prompt(), "%s\n\nJogador diz: %s" % [_scene_context(actor), text],
		float(LEVELS[level]["temp"]), MASTER_MAX_TOKENS)
	var err := _http.request(URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		return {}
	var res: Array = await _http.request_completed
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return {}
	var outer: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(outer) != TYPE_DICTIONARY:
		return {}
	var content := str(outer.get("message", {}).get("content", ""))
	var inner: Variant = JSON.parse_string(content)
	if typeof(inner) != TYPE_DICTIONARY:
		return {}
	return inner


# ---------------------------------------------------------------- validação e aplicação

func _apply_answer(actor: Dictionary, a: Dictionary) -> void:
	var intent_id := str(a.get("intent", "nenhuma")).strip_edges().to_lower()
	var intent := {}
	for it in Game.lines.get("intents", []):
		if it["id"] == intent_id:
			intent = it
			break
	if intent.is_empty():
		var say := str(a.get("say", "")).strip_edges()
		if say == "":
			super.interpret(actor, "")
			return
		Game.narration_added.emit(say.left(280))
		return
	# Copia a intenção e troca só os textos que a IA escreveu (limitados em tamanho).
	var custom: Dictionary = intent.duplicate(true)
	for pair in [["ask", "ask"], ["success_text", "success"], ["fail_text", "fail"]]:
		var s := str(a.get(pair[0], "")).strip_edges()
		if s != "":
			custom[pair[1]] = s.left(280)
	if not custom["ask"].contains("{cd}"):
		custom["ask"] = custom["ask"] + " {nome}, role %s, CD {cd}." % intent["skill"]
	# Alvo: o motor resolve pelo nome citado (ou pelo token clicado).
	var low := (str(a.get("target", "")) + " " + str(a.get("ask", ""))).to_lower()
	_handle_intent(actor, custom, low)


## O motor monta a proposta; aqui só aplicamos o nível (CD e punição). Sem sobrescrever
## a lógica de contexto do mock.
func _build_proposal(actor: Dictionary, intent: Dictionary, target: Dictionary) -> Dictionary:
	var p := super._build_proposal(actor, intent, target)
	if p.get("free", false):
		return p
	var prof: Dictionary = LEVELS[level]
	var mod := int(prof["dc_mod"])
	if mod != 0:
		p["dc"] = clampi(int(p["dc"]) + mod, 5, 30)
		p["dc_reason"] = "%s, mestre %s %+d" % [p["dc_reason"], str(prof["label"]).to_lower(), mod]
	if str(prof["fail_damage"]) != "":
		var on_fail: Array = p.get("on_fail", [])
		on_fail.append({"type": "damage", "who": "actor", "dice": prof["fail_damage"], "dtype": ""})
		on_fail.append({"type": "taunt", "event": "player_miss"})
		p["on_fail"] = on_fail
	return p
