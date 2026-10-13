class_name GameIcons
extends RefCounted
## Ícones de armas e perícias (game-icons.net, CC BY 3.0 — atribuição em
## assets/icons/game-icons/CREDITS.txt e no README).
## A tabela id -> ícone está em data/icons.json, gerada por tools/icons/build_icons.py.
## Os SVG são brancos sobre transparente: tinja com `modulate` (ver `rect`).

const MAP_PATH := "res://data/icons.json"
const DIR := "res://assets/icons/game-icons/"

static var _map: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		push_warning("GameIcons: não achei " + MAP_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_map = parsed


## Referência "autor/nome" do ícone, ou "" se não houver.
static func ref(kind: String, id: String) -> String:
	_ensure()
	return str(_map.get(kind, {}).get(id, ""))


static func has_icon(kind: String, id: String) -> bool:
	return ref(kind, id) != ""


static func weapon_ref(weapon_id: String, ranged := false) -> String:
	var r := ref("weapon", weapon_id)
	if r == "" and weapon_id != "":
		r = ref("generic", "ranged" if ranged else "melee")
	return r


## Ícone de um ataque da ficha (dicionário de `CharBuilder`). Ataque sem arma
## (mordida de monstro, magia) não tem ícone: devolve null.
static func attack_texture(atk: Dictionary) -> Texture2D:
	var wid := str(atk.get("weapon_id", ""))
	if wid != "":
		return load_ref(weapon_ref(wid, bool(atk.get("ranged", false))))
	if str(atk.get("kind", "")) == "unarmed":
		return load_ref(ref("generic", "unarmed"))
	return null


static func weapon_texture(weapon_id: String) -> Texture2D:
	return load_ref(weapon_ref(weapon_id, bool(Srd.weapons.get(weapon_id, {}).get("ranged", false))))


static func skill_texture(skill_id: String) -> Texture2D:
	return load_ref(ref("skill", skill_id))


static func load_ref(r: String) -> Texture2D:
	if r == "":
		return null
	if _cache.has(r):
		return _cache[r]
	var path := DIR + r + ".svg"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		# Sem import (ex.: antes do primeiro `--import`): rasteriza o SVG na hora.
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var img := Image.new()
			if img.load_svg_from_string(f.get_as_text(), 1.0) == OK:
				tex = ImageTexture.create_from_image(img)
	_cache[r] = tex
	return tex


## Pequeno quadrado de ícone tingido, pronto para pôr numa linha ou cartão.
static func rect(tex: Texture2D, size: float, color: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
