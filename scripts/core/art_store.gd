class_name ArtStore
extends RefCounted
## Arte enviada pelos jogadores: retrato, token do mapa e imagem de cada ataque.
##
## Ordem de busca de cada imagem:
##   1. user://art/...  (o que o jogador importou; fica na pasta de dados do usuário)
##   2. res://assets/art/...  (arte que vem com o jogo)
##   3. nada: o jogo desenha o placeholder
##
## As escolhas (token igual ao retrato, modelo de animação de cada ataque)
## ficam em user://aparencia.json.

const USER_DIR := "user://art/"
const SETTINGS := "user://aparencia.json"
## "scenes" é o fundo do mapa: não entra no corte quadrado, porque o tabuleiro é 16:9.
const MAX_SIDE := {"portraits": 512, "tokens": 256, "fx": 256, "monsters": 512, "scenes": 1920}
const WIDE_KINDS := ["scenes"]

## Modelos de animação. O motor escolhe um automaticamente pelo tipo da habilidade.
const TEMPLATES := ["projetil", "golpe", "area", "cura"]
const TEMPLATE_NAMES := {
	"projetil": "Projétil (voa até o alvo)",
	"golpe": "Golpe (avança e risca o alvo)",
	"area": "Explosão em área",
	"cura": "Cura e reforço (brilho subindo)",
}

const FX_DURATION := {"projetil": 0.55, "golpe": 0.45, "area": 0.7, "cura": 0.75}

static var _cache := {}
static var _settings := {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(SETTINGS):
		var f := FileAccess.open(SETTINGS, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_settings = parsed


static func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_settings, "  "))


static func _char_settings(char_id: String) -> Dictionary:
	_ensure_loaded()
	if not _settings.has(char_id):
		_settings[char_id] = {"token_same": true, "fx": {}}
	return _settings[char_id]


# ---------------------------------------------------------------- busca

static func _find(kind: String, key: String) -> Texture2D:
	var cache_key := kind + "/" + key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var tex: Texture2D = null
	var user_path := USER_DIR + "%s/%s.png" % [kind, key]
	var res_path := "res://assets/art/%s/%s.png" % [kind, key]
	if FileAccess.file_exists(user_path):
		var img := Image.load_from_file(user_path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(res_path):
		tex = load(res_path)
	_cache[cache_key] = tex
	return tex


static func portrait(char_id: String) -> Texture2D:
	return _find("portraits", char_id)


static func token(char_id: String) -> Texture2D:
	if not token_same(char_id):
		var t := _find("tokens", char_id)
		if t != null:
			return t
	return portrait(char_id)


static func fx_image(char_id: String, ability_id: String) -> Texture2D:
	return _find("fx", "%s_%s" % [char_id, ability_id])


## Fundo do mapa de uma cena, importado pelo jogador. key: "<id da aventura>_<id da cena>".
static func scene_image(key: String) -> Texture2D:
	return _find("scenes", key)


## Retrato de uma criatura, pelo id do monstro no SRD.
static func monster_image(monster_id: String) -> Texture2D:
	return _find("monsters", monster_id)


static func has_image(kind: String, key: String) -> bool:
	return FileAccess.file_exists(USER_DIR + "%s/%s.png" % [kind, key]) or ResourceLoader.exists("res://assets/art/%s/%s.png" % [kind, key])


static func token_same(char_id: String) -> bool:
	return bool(_char_settings(char_id).get("token_same", true))


static func set_token_same(char_id: String, same: bool) -> void:
	_char_settings(char_id)["token_same"] = same
	_save_settings()


# ---------------------------------------------------------------- modelo de animação

## Escolha automática a partir da própria habilidade (sem IA).
static func auto_template(ability: Dictionary) -> String:
	var kind: String = ability.get("kind", "attack")
	if kind == "heal" or kind == "cure":
		return "cura"
	if ability.get("target", "single") == "area":
		return "area"
	if ability.get("range", "") == "melee":
		return "golpe"
	if ability.get("range", "") == "ranged" or kind == "spell":
		return "projetil"
	return "golpe"


static func template_for(char_id: String, ability: Dictionary) -> String:
	var chosen: String = _char_settings(char_id)["fx"].get(ability.get("id", ""), "")
	return chosen if chosen in TEMPLATES else auto_template(ability)


static func set_template(char_id: String, ability_id: String, template: String) -> void:
	var fx: Dictionary = _char_settings(char_id)["fx"]
	if template == "" or template == "auto":
		fx.erase(ability_id)
	else:
		fx[ability_id] = template
	_save_settings()


static func fx_duration(template: String) -> float:
	return FX_DURATION.get(template, 0.5)


static func is_auto(char_id: String, ability_id: String) -> bool:
	return not _char_settings(char_id)["fx"].has(ability_id)


## Cor padrão do efeito pelo tipo de dano. Violeta fica fora: é a cor do mestre.
static func dtype_color(dtype: String) -> Color:
	match dtype:
		"fogo":
			return Color("ff8a3d")
		"trovejante":
			return Color("9fd8ff")
		"energia":
			return Color("8ff0ff")
		"psíquico":
			return Color("f08fc8")
		"gelo", "frio":
			return Color("bfe9ff")
		"ácido", "veneno":
			return Color("a6e05a")
		"radiante":
			return Color("ffe08a")
		"necrótico":
			return Color("8a9a7a")
	return Color("e8e2d6")  # armas: aço


# ---------------------------------------------------------------- importação

## Importa uma imagem do computador do jogador. Retorna "" se deu certo ou a mensagem de erro.
## kind: "portraits", "tokens", "fx", "monsters" (quadrado) ou "scenes" (mapa, mantém a proporção).
## key: id do personagem, do monstro, ou "<aventura>_<cena>" no caso do mapa.
static func import_image(source_path: String, kind: String, key: String) -> String:
	var img := Image.load_from_file(source_path)
	if img == null or img.is_empty():
		return "Não consegui ler essa imagem. Use PNG, JPG ou WEBP."
	var max_side: int = MAX_SIDE.get(kind, 512)
	if kind in WIDE_KINDS:
		# Mapa: mantém a imagem inteira, só limita a largura.
		if img.get_width() > max_side:
			img.resize(max_side, int(round(float(img.get_height()) * float(max_side) / float(img.get_width()))), Image.INTERPOLATE_LANCZOS)
	else:
		# Corta no quadrado central: retrato e token são mostrados em quadrado ou círculo.
		var side := mini(img.get_width(), img.get_height())
		var x := (img.get_width() - side) / 2
		var y := (img.get_height() - side) / 2
		img = img.get_region(Rect2i(x, y, side, side))
		if side > max_side:
			img.resize(max_side, max_side, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(USER_DIR + kind)
	var dest := USER_DIR + "%s/%s.png" % [kind, key]
	var err := img.save_png(dest)
	if err != OK:
		return "Não consegui salvar a imagem (erro %d)." % err
	_cache.erase(kind + "/" + key)
	return ""


static func remove_image(kind: String, key: String) -> void:
	var path := USER_DIR + "%s/%s.png" % [kind, key]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_cache.erase(kind + "/" + key)
