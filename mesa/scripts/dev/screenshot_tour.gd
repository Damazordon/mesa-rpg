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
	if autoplay:
		_autoplay(main, out)
	elif out != "":
		_run(main, out)


## Joga o combate inteiro sozinho para testar a resolução de ações.
## Uso: godot --path . -- --autoplay [--shots=/pasta]
static func _autoplay(main: Control, out: String) -> void:
	var tree := main.get_tree()
	await tree.create_timer(0.5).timeout
	var actions := 0
	var guard := 0
	while Game.in_combat and guard < 4000:
		guard += 1
		await tree.create_timer(0.1).timeout
		if not Game.is_party_turn() or Game.busy:
			continue
		var a := Game.current()
		var alive := Game.enemies.filter(func(e): return Game.is_alive(e))
		if alive.is_empty():
			break
		var usable: Array = a["abilities"].filter(func(ab): return int(ab.get("cost", 0)) <= a["res"])
		var choice: Dictionary = usable[actions % usable.size()]
		var targets: Array = [a["id"]]
		if choice.get("target", "single") == "single":
			targets = [alive.pick_random()["id"]]
		elif choice.get("target", "") == "area":
			targets = [alive[0]["id"]]
		print("autoplay: %s usa %s" % [a["name"], choice["name"]])
		Game.use_ability(a["id"], choice, targets)
		actions += 1
	print("autoplay: combate terminou=%s, ações=%d, rodada=%d" % [not Game.in_combat, actions, Game.round_num])
	var lia: Dictionary = Game.by_id["lia"]
	if not lia["upgrades"].is_empty():
		var ok := Game.buy_upgrade("lia", lia["upgrades"][-1])
		print("autoplay: compra de upgrade fora de combate=%s" % ok)
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
		await tree.create_timer(1.0).timeout
		await _shot(main, out + "/08_fim_de_combate.png")
	tree.quit()


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
	var actor := Game.current()
	var area_ab: Dictionary = {}
	for ab in actor.get("abilities", []):
		if ab.get("target", "") == "area":
			area_ab = ab
	if area_ab.is_empty():
		area_ab = {"name": "Área de teste", "target": "area", "area": 0.1}
	main.map_view.begin_targeting(actor["id"], area_ab)
	main.map_view.mouse = main.map_view.to_px(Vector2(0.69, 0.47))
	await _shot(main, out + "/02_mira_area.png")
	main.map_view.cancel_targeting()

	# Dano flutuante
	Game.floating_text.emit("gob_a", "-7", "damage")
	Game.floating_text.emit("hob", "12", "crit")
	await tree.create_timer(0.35).timeout
	await _shot(main, out + "/03_dano.png")

	for i in 4:
		main.sheet.open_for("seren" if i == 3 else "lia")
		main.sheet.tabs.select(i)
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
