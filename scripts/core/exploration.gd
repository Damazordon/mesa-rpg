class_name Exploration
extends RefCounted
## Exploração do capítulo: o grupo anda pelo mapa, descobre pontos de interesse e topa com os
## inimigos conforme avança. Vencer as lutas não encerra o capítulo — achar a saída encerra.
##
## Estados de um ponto de interesse, por distância de qualquer personagem do grupo:
##   longe        → não aparece no mapa
##   HINT_M       → aparece como "?" (sentiram algo ali)
##   DISCOVER_M   → aparece com nome
##   REACH_M      → visitado: baú é saqueado, marco é riscado, saída encerra o capítulo
##
## Os grupos de inimigos ficam escondidos até alguém entrar no raio deles, e então o combate
## começa de onde todo mundo está — por isso furar na frente sozinho é arriscado.
##
## A saída só abre depois de visitar os pontos obrigatórios, e ela própria precisa ser descoberta.
##
## Com terreno (cenas com "map"), quem anda segue o caminho de verdade (contorna parede, paga o
## dobro no terreno difícil) e tudo que depende de ver pede linha de visão: descobrir um ponto com
## nome, visitar, e o bando notar o grupo. O "?" continua sem precisar ver: é barulho, cheiro,
## luz por baixo da porta — é o que evita andar às cegas.

const HINT_M := 9.0
const DISCOVER_M := 4.5
const REACH_M := 1.7
const STEP_M := 0.5
const KINDS := ["chest", "mark", "exit"]

var g: Node


func _init(game: Node) -> void:
	g = game


# ---------------------------------------------------------------- preparação

## Lê os pontos de interesse e os grupos da cena. Cenas sem "pois" (aventuras antigas, como a
## vale_cinzento) continuam no fluxo antigo: tudo visível e "Iniciar encontro" na mão.
func setup(sc: Dictionary) -> void:
	g.pois = []
	g.groups = []
	for p in sc.get("pois", []):
		var pos: Array = p.get("pos", [0.5, 0.5])
		g.pois.append({
			"id": str(p.get("id", "p%d" % (g.pois.size() + 1))), "name": str(p.get("name", "Algo")),
			"kind": str(p.get("kind", "mark")), "pos": Vector2(float(pos[0]), float(pos[1])),
			"required": bool(p.get("required", false)), "text": str(p.get("text", "")),
			"loot": p.get("loot", {}), "found": false, "sensed": false, "taken": false,
		})
	for grp in sc.get("groups", []):
		var gp: Array = grp.get("pos", [0.7, 0.5])
		g.groups.append({
			"id": str(grp.get("id", "g%d" % (g.groups.size() + 1))), "pos": Vector2(float(gp[0]), float(gp[1])),
			"radius_m": float(grp.get("radius_m", 6.0)), "intro": str(grp.get("intro", "")),
			"monsters": grp.get("monsters", []), "triggered": false,
		})
	g.seen = PackedByteArray()
	g.update_vision()
	if active():
		_sense_all()
		g.pois_changed.emit()


## Vale a pena explorar esta cena? Falso em combate e em cenas sem pontos de interesse.
func active() -> bool:
	return not g.pois.is_empty() and not g.in_combat


func has_exploration() -> bool:
	return not g.pois.is_empty()


# ---------------------------------------------------------------- consultas

func required_total() -> int:
	var n := 0
	for p in g.pois:
		if p["required"]:
			n += 1
	return n


func required_left() -> int:
	var n := 0
	for p in g.pois:
		if p["required"] and not p["taken"]:
			n += 1
	return n


func exit_open() -> bool:
	return required_left() == 0


func exit_poi() -> Dictionary:
	for p in g.pois:
		if p["kind"] == "exit":
			return p
	return {}


func groups_left() -> int:
	var n := 0
	for grp in g.groups:
		if not grp["triggered"]:
			n += 1
	return n


## Resumo para a barra do topo.
func progress_text() -> String:
	var total := required_total()
	if total == 0:
		return "Explorando"
	var done := total - required_left()
	if not exit_open():
		return "Pontos: %d de %d" % [done, total]
	var ex_p := exit_poi()
	if ex_p.is_empty():
		return "Pontos: %d de %d" % [done, total]
	return "Saída liberada" if ex_p["found"] else "Saída liberada — encontrem o caminho"


# ---------------------------------------------------------------- movimento

## Move um personagem do grupo até onde deu, revelando e disparando o que houver no caminho.
## Devolve "" ou o motivo de não ter andado.
func explore_move(id: String, to: Vector2) -> String:
	if not active():
		return "Não é hora de explorar."
	var c: Dictionary = g.by_id.get(id, {})
	if c.is_empty() or c.get("side", "") != "party":
		return "Escolha alguém do grupo."
	if not g.is_alive(c):
		return "%s não está em pé." % c["name"]
	if g.busy:
		return ""
	var from: Vector2 = c["pos"]
	to = g.settle(to)
	var dist: float = g.dist_m(from, to)
	if dist < 0.25:
		return ""
	if not g.walkable(to):
		return "Ali não dá para pisar."
	var plan: Dictionary = g.plan_path(c, to)
	if plan.is_empty():
		return "Não há caminho até lá."
	# Anda pelo caminho em passos curtos: revela o que aparece e para se um bando notar o grupo.
	var route: PackedVector2Array = plan["points"]
	var probe := PackedVector2Array()
	for p0 in route:
		probe.append(g.to_m(p0))
	var final := from
	var walked := PackedVector2Array([from])
	var trig := {}
	for pm in TerrainMap.samples(probe, STEP_M):
		var p: Vector2 = g.from_m(pm)
		if not g.spot_free(p, id):
			# Alguém do grupo no meio do caminho: passa por ele, mas não para em cima.
			continue
		final = p
		walked.append(p)
		_sense_from(p)
		trig = _trigger_at(p)
		if not trig.is_empty():
			break
	if final == from:
		return "Caminho bloqueado."
	c["pos"] = final
	var length := 0.0
	for i in range(1, walked.size()):
		length += g.dist_m(walked[i - 1], walked[i])
	if walked.size() > 2 and g.has_terrain():
		g.move_paths[id] = _simplify(walked)
	g.token_moved.emit(id, from, final, clampf(length / 7.0, 0.15, 1.6))
	g.update_vision()
	g.state_changed.emit(id)
	_visit_reached(c["id"])
	g.pois_changed.emit()
	if not trig.is_empty():
		_spring(trig)
	return ""


## Tira os pontos intermediários que estão em linha reta, para a animação não tremer.
func _simplify(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var a: Vector2 = out[out.size() - 1]
		var d1 := (pts[i] - a).normalized()
		var d2 := (pts[i + 1] - pts[i]).normalized()
		if d1.dot(d2) < 0.999:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


# ---------------------------------------------------------------- descoberta

func _sense_all() -> void:
	for c in g.party:
		if g.is_alive(c):
			_sense_from(c["pos"])


## Revela o que está perto de um ponto do caminho.
func _sense_from(p: Vector2) -> void:
	for poi in g.pois:
		if poi["found"]:
			continue
		var d: float = g.dist_m(p, poi["pos"])
		if d <= DISCOVER_M and g.line_clear(p, poi["pos"]):
			poi["found"] = true
			poi["sensed"] = true
			g.narration_added.emit(_found_line(poi))
		elif d <= HINT_M and not poi["sensed"]:
			poi["sensed"] = true
			g.engine_log("Alguma coisa chama atenção adiante.")


func _found_line(poi: Dictionary) -> String:
	if str(poi["text"]) != "":
		return str(poi["text"])
	match str(poi["kind"]):
		"chest":
			return "Vocês encontram %s." % poi["name"]
		"exit":
			return "Vocês encontram o caminho adiante: %s." % poi["name"]
	return "Vocês chegam em %s." % poi["name"]


# ---------------------------------------------------------------- visita

## Visita todo ponto já descoberto ao alcance de quem acabou de andar.
func _visit_reached(id: String) -> void:
	var c: Dictionary = g.by_id.get(id, {})
	if c.is_empty():
		return
	for poi in g.pois:
		if poi["taken"] or not poi["found"]:
			continue
		if g.dist_m(c["pos"], poi["pos"]) > REACH_M or not g.line_clear(c["pos"], poi["pos"]):
			continue
		match str(poi["kind"]):
			"exit":
				_try_exit(poi)
			"chest":
				poi["taken"] = true
				_loot(poi, c["id"])
			_:
				poi["taken"] = true
				g.engine_log("%s: ponto de interesse visitado." % poi["name"])
				if required_left() == 0:
					g.narration_added.emit("Vocês já viram o que precisavam aqui. Falta achar a saída.")
		# A ficha pode ter sido reconstruída pelo saque; busca de novo antes de seguir.
		c = g.by_id.get(id, {})
		if c.is_empty():
			return


func _try_exit(poi: Dictionary) -> void:
	if not exit_open():
		g.narration_added.emit("A saída está aqui, mas o grupo ainda não viu tudo que importa neste lugar (faltam %d ponto(s))." % required_left())
		return
	poi["taken"] = true
	g.engine_log("O grupo alcança a saída: %s." % poi["name"])
	g.clear_chapter()


# ---------------------------------------------------------------- saque

## Moedas e equipamento mundano. Entra pelas escolhas do personagem (equipment_extra/gold_extra)
## e a ficha é reconstruída, para o saque sobreviver a salvar e carregar.
func _loot(poi: Dictionary, id: String) -> void:
	var c: Dictionary = g.by_id.get(id, {})
	if c.is_empty():
		return
	var loot: Dictionary = poi.get("loot", {})
	var coins := int(loot.get("coins", 0))
	var items: Array = loot.get("items", [])
	if coins <= 0 and items.is_empty():
		g.narration_added.emit("%s está vazio." % poi["name"])
		return
	var choices: Dictionary = c.get("choices", {}).duplicate(true)
	var parts := PackedStringArray()
	if coins > 0:
		choices["gold_extra"] = int(choices.get("gold_extra", 0)) + coins
		parts.append("%d %s" % [coins, Srd.currency()])
	var extra: Array = choices.get("equipment_extra", []).duplicate()
	for item_id in items:
		var item: Dictionary = Srd.gear.get(str(item_id), {})
		if item.is_empty():
			continue
		# equipment_extra é resolvido por nome em inglês (Srd.find_item).
		extra.append({"item": str(item["name"]), "qty": 1})
		parts.append(Srd.label("gear", str(item_id), str(item["name"])))
	choices["equipment_extra"] = extra
	g.narration_added.emit("%s: %s." % [poi["name"], ", ".join(parts)])
	g.engine_log("%s guarda: %s." % [c["name"], ", ".join(parts)])
	g.rebuild(id, choices)


# ---------------------------------------------------------------- emboscada

## Um bando nota quem passa no raio dele E à vista de alguém do bando. Parede no meio esconde.
func _trigger_at(p: Vector2) -> Dictionary:
	for grp in g.groups:
		if grp["triggered"]:
			continue
		if g.dist_m(p, grp["pos"]) > float(grp["radius_m"]) + 3.5:
			continue
		var eyes: Array = [grp["pos"]]
		for m in grp.get("monsters", []):
			var mp: Array = m.get("pos", [])
			if mp.size() == 2:
				eyes.append(Vector2(float(mp[0]), float(mp[1])))
		for e in eyes:
			if g.dist_m(p, e) <= float(grp["radius_m"]) and g.line_clear(e, p):
				return grp
	return {}


## Coloca o grupo de inimigos no tabuleiro e começa o combate de onde todos estão.
func _spring(grp: Dictionary) -> void:
	grp["triggered"] = true
	var placed := 0
	for m in grp.get("monsters", []):
		var over: Dictionary = m.get("overrides", {}).duplicate()
		if m.has("name"):
			over["name"] = m["name"]
		var c := MonsterBuilder.build(str(m["monster_id"]), str(m["id"]), over)
		if c.is_empty():
			continue
		var p: Array = m.get("pos", [grp["pos"].x, grp["pos"].y])
		c["pos"] = Vector2(float(p[0]), float(p[1]))
		c["side"] = str(m.get("side", "enemy"))
		c["color"] = m.get("color", c["color"])
		c["boss"] = m.get("boss", false)
		for cid in m.get("conditions", []):
			c["conditions"].append({"id": cid, "source": ""})
		g.enemies.append(c)
		g.by_id[c["id"]] = c
		placed += 1
	g.pois_changed.emit()
	if placed == 0:
		return
	g.start_combat(str(grp["intro"]))
