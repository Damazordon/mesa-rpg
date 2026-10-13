class_name ScreenshotTour
extends RefCounted
## Ferramenta de desenvolvimento: tira prints das telas principais e fecha o jogo.
## Uso: godot --path . -- --shots=/caminho/da/pasta
## Sem esse argumento, não faz nada.


static func maybe_run(main: Control) -> void:
	var out := ""
	var autoplay := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.substr(8)
		elif a == "--autoplay":
			autoplay = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--export-assets="):
			_export_assets(main, a.substr(16))
			return
		if a.begins_with("--fx-shots="):
			_fx_tour(main, a.substr(11))
			return
		if a.begins_with("--dialog-shots="):
			_dialog_tour(main, a.substr(15))
			return
		if a.begins_with("--creator-shots="):
			_creator_tour(main, a.substr(16))
			return
		if a.begins_with("--map-shots="):
			_map_tour(main, a.substr(12))
			return
	if autoplay:
		_autoplay(main, out)
	elif out != "":
		_run(main, out)


## Testa movimento, alcance e diálogo com consequências. Uso: -- --dialog-shots=/pasta
static func _say(text: String) -> void:
	print("jogador: ", text)
	Game.player_free_text(Game.current()["id"], text)


static func _dialog_tour(main: Control, out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var tree := main.get_tree()
	var last := {"narr": ""}
	Game.narration_added.connect(func(t): last["narr"] = t; print("mestre: ", t))
	Game.engine_logged.connect(func(t): print("motor: ", t))
	await tree.create_timer(0.8).timeout
	var guard := 0
	while not Game.is_party_turn() and guard < 80:
		await tree.create_timer(0.25).timeout
		guard += 1
	var a := Game.current()
	print("vez de ", a["name"], " em ", a["pos"])

	# 1. Pedido livre com alvo citado pelo nome
	_say("mestre, quero tentar carisma para transformar o goblin em aliado")
	await tree.create_timer(1.2).timeout
	print("teste pedido: ", Game.pending_check.get("skill"), " alvo=", Game.pending_check.get("target"), " CD=", Game.pending_check.get("dc"), " (", Game.pending_check.get("dc_reason"), ")")
	await _shot(main, out + "/20_pedido_de_teste.png")
	# Força o sucesso para registrar a consequência (o dado de verdade é aleatório).
	var chk := Game.pending_check
	Game.clear_check()
	Game.apply_effects(chk["on_success"], a, chk["target"])
	Game.narration_added.emit(chk["success_text"])
	var ally: Dictionary = Game.by_id[chk["target"]]
	print("lado do alvo agora: ", ally["side"])
	await tree.create_timer(0.6).timeout
	await _shot(main, out + "/21_goblin_aliado.png")

	# 2. Pergunta a quem já é aliado: responde sem teste e atualiza o diário
	Game.select_target(ally["id"])
	_say("onde estão os mineiros?")
	await tree.create_timer(1.2).timeout
	Game.select_target("")
	# 3. Frase sem sentido: o mestre pergunta em vez de inventar
	_say("faço uma dança estranha com o chapéu")
	await tree.create_timer(1.2).timeout
	# 4. Sem alvo: o mestre pergunta com quem
	_say("quero intimidar")
	await tree.create_timer(1.2).timeout
	main.toggle_journal(true)
	main.journal.tabs.select(1)
	await tree.create_timer(0.5).timeout
	await _shot(main, out + "/22_diario_atualizado.png")
	main.toggle_journal(false)

	# 5. Movimento
	main.map_view.begin_move()
	main.map_view.mouse = main.map_view.to_px(a["pos"] + Vector2(0.12, -0.06))
	await tree.create_timer(0.2).timeout
	await _shot(main, out + "/23_modo_mover.png")
	print("mover longe demais: ", Game.move_token(a["id"], Vector2(0.95, 0.1)))
	var dest: Vector2 = a["pos"] + Vector2(0.08, -0.04)
	print("mover perto: '", Game.move_token(a["id"], dest), "' resta ", Game.fmt_m(Game.move_left))
	main.map_view.cancel_move()
	await tree.create_timer(0.8).timeout

	# 6. Mira fora de alcance com ataque corpo a corpo
	var melee: Dictionary = {}
	for ab in Game.available_actions(a):
		if ab["kind"] == "attack" and not ab["ref"].get("ranged", false) and melee.is_empty():
			melee = ab
	main.map_view.begin_targeting(a["id"], melee)
	var far: Dictionary = Game.enemies.filter(func(e): return Game.is_foe(e) and Game.is_alive(e))[0]
	main.map_view.mouse = main.map_view.to_px(far["pos"])
	main.map_view.hovered_id = far["id"]
	main.map_view._click_target()
	await tree.create_timer(0.2).timeout
	await _shot(main, out + "/24_fora_de_alcance.png")
	main.map_view.cancel_targeting()

	# 7. Inimigos se aproximam e o aliado luta do lado do grupo
	var before := {}
	for e in Game.enemies:
		before[e["id"]] = e["pos"]
	Game.end_turn()
	guard = 0
	while guard < 120 and not (Game.is_party_turn() and not Game.busy):
		await tree.create_timer(0.25).timeout
		guard += 1
	for e in Game.enemies:
		print("%s (%s) andou %s" % [e["name"], e["side"], Game.fmt_m(Game.dist_m(before[e["id"]], e["pos"]))])
	await _shot(main, out + "/25_inimigos_avancaram.png")

	# 8. Economia oficial: Esquivar gasta a ação e dá desvantagem a quem ataca
	var b := Game.current()
	guard = 0
	while guard < 200 and Game.in_combat and not (Game.is_party_turn() and not Game.busy):
		await tree.create_timer(0.25).timeout
		guard += 1
	b = Game.current()
	await Game.perform(b["id"], "std:dodge")
	print("economia: %s esquivando=%s, ação gasta=%s, bônus livre=%s" % [b["name"], Rules.has_effect(b, "dodge"), Game.cost_error(b, "action") != "", Game.cost_error(b, "bonus") == ""])
	await tree.create_timer(0.5).timeout
	await _shot(main, out + "/26_economia.png")
	tree.quit()


## Testa importação de arte e as quatro animações. Uso: -- --fx-shots=/pasta
static func _make_test_image(path: String, kind: String) -> void:
	var img := Image.create(400, 300, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 300:
		for x in 400:
			var d := Vector2(x - 200, y - 150).length()
			match kind:
				"portrait":
					var stripe := (x / 25) % 2 == 0
					img.set_pixel(x, y, Color("3e9a8f") if stripe else Color("e3d7b8"))
				"fire":
					if d < 110:
						img.set_pixel(x, y, Color(1.0, 0.85 - d / 200.0, 0.2, 1.0 - d / 110.0))
				"token":
					img.set_pixel(x, y, Color("b8733d") if d < 140 else Color("2a1e18"))
	img.save_png(path)


static func _fx_tour(main: Control, out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var tree := main.get_tree()
	await tree.create_timer(0.8).timeout
	var src := OS.get_user_data_dir() + "/teste_src"
	DirAccess.make_dir_recursive_absolute(src)
	_make_test_image(src + "/retrato.png", "portrait")
	_make_test_image(src + "/fogo.png", "fire")
	_make_test_image(src + "/token.png", "token")
	var sheet: CharacterSheet = main.sheet
	sheet.open_for("lia", 6)
	await tree.create_timer(0.2).timeout
	sheet.import_from_path(src + "/retrato.png", "portraits", "lia")
	sheet.import_from_path(src + "/fogo.png", "fx", "lia_guiding_bolt")
	print("importação: retrato=%s fx=%s" % [ArtStore.portrait("lia") != null, ArtStore.fx_image("lia", "guiding_bolt") != null])
	ArtStore.set_token_same("borin", false)
	print("token separado: ", ArtStore.import_image(src + "/token.png", "tokens", "borin") == "")
	Game.state_changed.emit("borin")
	await tree.create_timer(0.3).timeout
	await _shot(main, out + "/10_aparencia.png")
	var lia: Dictionary = Game.by_id["lia"]
	sheet._preview.play("lia", Game.cb._fx_ability(Srd.spells["guiding_bolt"]))
	await tree.create_timer(0.25).timeout
	await _shot(main, out + "/11_teste_na_ficha.png")
	sheet.close()

	var cases := [
		["lia", Game.cb._fx_ability(Srd.spells["guiding_bolt"]), ["gob_a"], 0.3, "12_projetil_com_imagem"],
		["borin", Game._fx_for_attack(Game.by_id["borin"]["attacks"][0]), ["gob_b"], 0.28, "13_golpe"],
		["seren", Game.cb._fx_ability(Srd.spells["shatter"]), ["gob_a", "gob_b"], 0.3, "14_area"],
		["lia", Game.cb._fx_ability(Srd.spells["cure_wounds"]), ["borin"], 0.35, "15_cura"],
		["seren", Game.cb._fx_ability(Srd.spells["fire_bolt"]), ["hob"], 0.25, "16_projetil_padrao"],
	]
	# Câmera lenta só no teste: a renderização por software é lenta demais para pegar o meio da animação.
	Engine.time_scale = 0.1
	for cs in cases:
		var ab: Dictionary = cs[1]
		Game.fx_requested.emit(cs[0], ab, cs[2])
		await tree.create_timer(cs[3]).timeout
		await _shot(main, out + "/%s.png" % cs[4])
		await tree.create_timer(0.8).timeout
	Engine.time_scale = 1.0
	# Limpa a arte de teste para não sobrar na pasta do usuário.
	ArtStore.remove_image("portraits", "lia")
	ArtStore.remove_image("fx", "lia_guiding_bolt")
	ArtStore.remove_image("tokens", "borin")
	ArtStore.set_token_same("borin", true)
	tree.quit()


## Exporta cada placeholder desenhado por código como PNG, já com o nome final
## que o jogo procura. Uso: godot --path . -- --export-assets=/pasta
static func _render(main: Control, ctrl: Control, px: Vector2i, path: String, transparent := true) -> void:
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ctrl.size = Vector2(px)
	vp.add_child(ctrl)
	main.add_child(vp)
	for i in 4:
		await main.get_tree().process_frame
	vp.get_texture().get_image().save_png(path)
	vp.queue_free()
	print("exportado: ", path)


static func _export_assets(main: Control, out: String) -> void:
	for sub in ["portraits", "master", "scenes", "conditions"]:
		DirAccess.make_dir_recursive_absolute(out + "/" + sub)
	await main.get_tree().create_timer(0.5).timeout
	for c in Game.party + Game.enemies:
		var p := Portrait.new()
		p.setup(c, 512)
		await _render(main, p, Vector2i(512, 512), "%s/portraits/%s.png" % [out, c["id"]])
	for m in ["neutro", "satisfeito", "irritado", "entediado"]:
		var av := MasterAvatar.new()
		av.mood = m
		await _render(main, av, Vector2i(512, 512), "%s/master/%s.png" % [out, m])
	var mv := MapView.new()
	mv.scene_only = true
	await _render(main, mv, Vector2i(1920, 1080), "%s/scenes/%s.png" % [out, Game.scene_info["background"]], false)
	for id in Game.conditions:
		var def: Dictionary = Game.conditions[id]
		var col := UiTheme.kind_color(def.get("kind", "neutral"))
		var icon := PanelContainer.new()
		icon.add_theme_stylebox_override("panel", UiTheme.box(col.darkened(0.55), 22, 6, col, 0))
		var l := UiTheme.label(def["abbr"], 56, col.lightened(0.4), UiTheme.sans_bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_child(l)
		await _render(main, icon, Vector2i(128, 128), "%s/conditions/%s.png" % [out, id])
	main.get_tree().quit()


## Joga o combate inteiro sozinho para testar a resolução de ações.
## Uso: godot --path . -- --autoplay [--shots=/pasta]
static func _autoplay(main: Control, out: String) -> void:
	var tree := main.get_tree()
	await tree.create_timer(0.5).timeout
	var actions := 0
	var guard := 0
	var used: Dictionary = {}
	while Game.in_combat and guard < 4000:
		guard += 1
		await tree.create_timer(0.1).timeout
		if not Game.is_party_turn() or Game.busy:
			continue
		var a := Game.current()
		var did := await _auto_turn_step(a)
		if did != "":
			actions += 1
			used[did] = int(used.get(did, 0)) + 1
			continue
		Game.end_turn()
	print("autoplay: combate terminou=%s, ações=%d, rodada=%d" % [not Game.in_combat, actions, Game.round_num])
	print("autoplay: tipos de ação usados: ", used)
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
		await tree.create_timer(1.0).timeout
		await _shot(main, out + "/08_fim_de_combate.png")
	tree.quit()


## Um passo de decisão simples para o jogador automático. Retorna o tipo do que fez ou "".
static func _auto_turn_step(a: Dictionary) -> String:
	var acts: Array = Game.available_actions(a)
	var foes: Array = Game.all_combatants().filter(func(e): return Game.is_alive(e) and Game.hostile(a, e))
	if foes.is_empty():
		return ""
	foes.sort_custom(func(x, y): return Game.dist_between(a, x) < Game.dist_between(a, y))
	# Cura um aliado caído ou muito ferido
	var hurt: Array = Game.party.filter(func(p): return not p["death"].get("dead", false) and int(p["hp"]) < int(p["hp_max"]) * 0.35)
	if not hurt.is_empty():
		for ab in acts:
			if ab["available"] and ab["kind"] == "spell" and str(Srd.spells[ab["ref"]].get("auto", {}).get("kind", "")) == "heal" and Game.dist_between(a, hurt[0]) <= float(ab["range_m"]) + 0.05:
				await Game.perform(a["id"], ab["id"], [hurt[0]["id"]], Vector2(-1, -1), {"slot": ab.get("slot", 1)})
				return "cura"
	# Recursos de ação bônus úteis
	for ab in acts:
		if ab["available"] and ab["id"] in ["feat:rage", "feat:innate_sorcery"]:
			await Game.perform(a["id"], ab["id"], [a["id"]])
			return str(ab["ref"])
	# Ataque ou magia de dano com alvo no alcance
	var best: Dictionary = {}
	var best_t: Dictionary = {}
	for ab in acts:
		if not ab["available"]:
			continue
		var is_dmg: bool = ab["kind"] == "attack" or (ab["kind"] == "spell" and str(Srd.spells[ab["ref"]].get("auto", {}).get("kind", "")) in ["attack", "auto_hit", "save"] and ab.get("target", "") in ["enemy"])
		if not is_dmg:
			continue
		for f in foes:
			if Game.dist_between(a, f) <= float(ab["range_m"]) + 0.05:
				if best.is_empty() or (ab["kind"] == "spell" and best["kind"] == "attack" and int(ab.get("level", 0)) > 0):
					best = ab
					best_t = f
				break
	if not best.is_empty():
		await Game.perform(a["id"], best["id"], [best_t["id"]], Vector2(-1, -1), {"slot": best.get("slot", 0)})
		return "ataque" if best["kind"] == "attack" else "magia"
	# Área: cone ou ponto que pegue um inimigo
	for ab in acts:
		if ab["available"] and ab["kind"] == "spell" and ab.get("target", "") in ["point", "direction"] and int(ab.get("level", 0)) > 0:
			var f0: Dictionary = foes[0]
			if Game.dist_between(a, f0) <= maxf(float(ab["range_m"]), 4.5):
				await Game.perform(a["id"], ab["id"], [], f0["pos"], {"slot": ab.get("slot", 1)})
				return "área"
	# Andar até o inimigo mais próximo
	var t := Game.turn_of(a)
	if float(t.get("move_left", 0.0)) > 0.3:
		var melee := Game._best_melee(a)
		var reach: float = float(melee.get("reach_m", 1.5)) if not melee.is_empty() else 1.5
		var dest := Game._approach(a, foes[0]["pos"], reach, float(t["move_left"]))
		if dest != a["pos"] and Game.move_token(a["id"], dest) == "":
			await Game.get_tree().create_timer(0.9).timeout
			return "movimento"
	return ""


static func _shot(main: Control, path: String) -> void:
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var img := main.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("print salvo: ", path)


static func _run(main: Control, out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var tree := main.get_tree()
	# Espera alguns turnos de inimigo acontecerem para o histórico ter conteúdo.
	await tree.create_timer(1.0).timeout
	var guard := 0
	while not Game.is_party_turn() and guard < 40:
		await tree.create_timer(0.25).timeout
		guard += 1
	# Uma ação livre para gerar narração e pedido de teste.
	Game.player_free_text(Game.current()["id"], "Quero me esconder atrás do carrinho")
	await tree.create_timer(1.4).timeout
	Master.react("player_crit", Game.current(), true)
	await tree.create_timer(0.4).timeout
	await _shot(main, out + "/01_mesa.png")

	# Mira em área
	var actor: Dictionary = Game.by_id["seren"]
	var area_ab: Dictionary = {}
	for ab in Game.available_actions(actor):
		if ab["id"] == "spell:shatter":
			area_ab = ab
	main.map_view.begin_targeting(actor["id"], area_ab)
	main.map_view.mouse = main.map_view.to_px(Vector2(0.69, 0.47))
	await _shot(main, out + "/02_mira_area.png")
	main.map_view.cancel_targeting()
	for ab in Game.available_actions(actor):
		if ab["id"] == "spell:burning_hands":
			area_ab = ab
	main.map_view.begin_targeting(actor["id"], area_ab)
	main.map_view.mouse = main.map_view.to_px(actor["pos"] + Vector2(0.12, -0.08))
	await _shot(main, out + "/02b_mira_cone.png")
	main.map_view.cancel_targeting()

	# Dano flutuante
	Game.floating_text.emit("gob_a", "-7", "damage")
	Game.floating_text.emit("hob", "12", "crit")
	await tree.create_timer(0.35).timeout
	await _shot(main, out + "/03_dano.png")

	for i in 7:
		main.sheet.open_for("seren" if i == 2 else ("pip" if i == 3 else "lia"), i)
		await tree.create_timer(0.3).timeout
		await _shot(main, out + "/04_ficha_%d.png" % (i + 1))
	main.sheet.close()

	main.toggle_journal(true)
	await tree.create_timer(0.5).timeout
	await _shot(main, out + "/05_diario.png")
	main.journal.tabs.select(1)
	await tree.create_timer(0.2).timeout
	await _shot(main, out + "/06_biblia.png")
	main.toggle_journal(false)

	main.set_streamer(true)
	Game.narration_added.emit("O goblin olha para a câmera como se soubesse que está sendo transmitido.")
	await tree.create_timer(0.5).timeout
	await _shot(main, out + "/07_streamer.png")
	tree.quit()


## Cria um personagem pela tela de criação, sobe de nível e tira prints. Uso: -- --creator-shots=/pasta
static func _creator_tour(main: Control, out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var tree := main.get_tree()
	await tree.create_timer(1.0).timeout
	await _shot(main, out + "/30_preparacao.png")
	var cr: CharacterCreator = main.creator
	cr.open_create()
	cr.ch["name"] = "Kael"
	cr.ch["classes"] = [{"class_id": "paladin", "level": 3, "subclass_id": "oath_of_devotion"}]
	cr.ch["species_id"] = "dragonborn"
	cr.ch["species_choice"] = {"ancestry": "gold"}
	cr.ch["background_id"] = "soldier"
	cr.ch["base_scores"] = {"str": 15, "dex": 10, "con": 13, "int": 8, "wis": 12, "cha": 14}
	cr.ch["bg_bonus"] = {"str": 2, "con": 1}
	cr.ch["skills"] = ["insight", "persuasion"]
	cr.ch["options"] = {"fighting_style": "defense", "weapon_masteries": ["longsword", "javelin"]}
	cr.ch["spells"] = ["bless", "cure_wounds", "command", "shield_of_faith"]
	for i in 6:
		cr._go(i)
		await tree.create_timer(0.35).timeout
		await _shot(main, out + "/31_criacao_%d.png" % (i + 1))
	print("erros de validação: ", CharBuilder.validate(cr.ch))
	cr._on_next()
	await tree.create_timer(0.6).timeout
	var k: Dictionary = Game.by_id.get("kael", {})
	print("criado: %s, %s, PV %d, CA %d, CD %d" % [k.get("name", "?"), k.get("class", "?"), int(k.get("hp_max", 0)), Rules.ac(k) if not k.is_empty() else 0, Rules.spell_dc(k) if not k.is_empty() else 0])
	await _shot(main, out + "/32_grupo_com_kael.png")
	# Experiência para o nível 4 e subida
	k["xp"] = 2700
	main.sheet.open_for("kael", 5)
	await tree.create_timer(0.3).timeout
	await _shot(main, out + "/33_ficha_nivel.png")
	main._on_level_up("kael")
	await tree.create_timer(0.3).timeout
	await _shot(main, out + "/34_subir_nivel_1.png")
	cr._go(1)
	await tree.create_timer(0.3).timeout
	await _shot(main, out + "/35_subir_nivel_2.png")
	cr._on_next()
	await tree.create_timer(0.6).timeout
	var k2: Dictionary = Game.by_id.get("kael", {})
	print("depois da subida: %s, PV %d, FOR %d" % [k2.get("class", "?"), int(k2.get("hp_max", 0)), Rules.score(k2, "str")])
	main.sheet.open_for("kael", 1)
	await tree.create_timer(0.3).timeout
	await _shot(main, out + "/36_kael_caracteristicas.png")
	main.sheet.close()
	Game.remove_character("kael")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://party_%s.json" % Game.adventure.get("id", "")))
	tree.quit()


## Mapas por tema: um print de cada bioma (tudo revelado), a névoa no começo do capítulo, a prévia
## de caminho e um combate com cobertura. Uso: -- --map-shots=/pasta [--biome=<id>]
static func _map_tour(main: Control, out: String) -> void:
	Game.persist = false
	DirAccess.make_dir_recursive_absolute(out)
	var tree := main.get_tree()
	await tree.create_timer(0.5).timeout
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--biome="):
			only = a.substr(8)
	var cfg := {"name": "Tour dos mapas", "theme": "fantasia", "level": 3, "difficulty": "moderate", "chapters": 1,
		"player_count": 4, "players": [], "story": "Uma vila pede ajuda contra bandidos na estrada."}
	var base := AdventureGen.build(cfg, {}, [])
	Game.adventure = base["adventure"]
	Game.quests = base["quests"]
	var mv: MapView = main.map_view
	for biome in MapGen.BIOMES.keys():
		if only != "" and biome != only:
			continue
		var sc: Dictionary = base["adventure"]["scenes"][0].duplicate(true)
		sc.erase("map")
		MapGen.layout(sc, biome, [], 4242)
		_reset_board()
		Game.load_scene(sc)
		mv._build_terrain()
		Game.seen.fill(1)
		Game.visible_now.fill(1)
		mv._refresh_fog()
		await tree.create_timer(0.2).timeout
		await _shot(main, "%s/mapa_%s.png" % [out, biome])
	# Névoa e prévia de caminho, no começo do capítulo
	var sc2: Dictionary = base["adventure"]["scenes"][0].duplicate(true)
	sc2.erase("map")
	MapGen.layout(sc2, only if only != "" else "masmorra", [], 777)
	_reset_board()
	Game.load_scene(sc2)
	mv._build_terrain()
	var hero: Dictionary = Game.party[0]
	mv.explore_sel = hero["id"]
	var far: Vector2 = Game.from_m(Vector2(14.5, 4.5))
	var cell := Game.terrain.nearest_passable(Game.to_m(far), 6)
	mv.mouse = mv.to_px(Game.from_m(TerrainMap.center(cell)))
	await tree.create_timer(0.3).timeout
	await _shot(main, out + "/nevoa_caminho.png")
	# Anda até um ponto obrigatório e mostra o que foi revelado
	for poi in Game.pois:
		if poi["kind"] == "mark":
			print("andar: '", Game.ex.explore_move(hero["id"], poi["pos"]), "'")
			break
	await tree.create_timer(1.8).timeout
	await _shot(main, out + "/nevoa_depois.png")
	# Combate: dispara o primeiro bando e mostra a cobertura na mira
	var grp: Dictionary = Game.groups[0]
	Game.ex._spring(grp)
	await tree.create_timer(0.3).timeout
	var guard := 0
	while not Game.is_party_turn() and guard < 80:
		await tree.create_timer(0.25).timeout
		guard += 1
	var cur := Game.current()
	if not cur.is_empty():
		var foes: Array = Game.enemies.filter(func(e): return Game.is_alive(e))
		if not foes.is_empty():
			for e in foes:
				print("%s → %s: cobertura %d, à vista %s" % [cur["name"], e["name"], Game.cover_between(cur, e), str(Game.sees(cur, e))])
			mv.hovered_id = foes[0]["id"]
			mv.mouse = mv.to_px(foes[0]["pos"])
		await _shot(main, out + "/combate_cobertura.png")
		mv.hovered_id = ""
		mv.begin_move()
		mv.mouse = mv.to_px(Game.from_m(Game.to_m(cur["pos"]) + Vector2(7, -3)))
		await _shot(main, out + "/combate_mover.png")
		mv.cancel_move()
	# Algumas rodadas com o grupo passando a vez: a IA tem de achar caminho e linha de visão.
	var start_pos := {}
	Game.engine_logged.connect(func(tx): print("LOG ", tx))
	for e2 in Game.enemies:
		start_pos[e2["id"]] = Game.to_m(e2["pos"])
	var rounds_guard := 0
	while Game.in_combat and Game.round_num <= 4 and rounds_guard < 400:
		rounds_guard += 1
		if Game.is_party_turn() and not Game.busy:
			Game.end_turn()
		await tree.create_timer(0.1).timeout
	for e3 in Game.enemies:
		var walked: float = Game.to_m(e3["pos"]).distance_to(start_pos.get(e3["id"], Game.to_m(e3["pos"])))
		print("%s andou %.1f m, em parede: %s, PV %d" % [e3["name"], walked, str(not Game.walkable(e3["pos"])), int(e3["hp"])])
	for c3 in Game.party:
		print("%s PV %d" % [c3["name"], int(c3["hp"])])
	await _shot(main, out + "/combate_rodadas.png")
	tree.quit()


static func _reset_board() -> void:
	for e in Game.enemies:
		Game.by_id.erase(e["id"])
	Game.enemies.clear()
	Game.in_combat = false
	Game.order.clear()
	Game.chapter_done = false
	Game.busy = false
