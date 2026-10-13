class_name MonsterBuilder
extends RefCounted
## Transforma um bloco de estatísticas do SRD em criatura do motor.
## Aventuras podem sobrescrever qualquer campo (nome, PV, ações) em "overrides".

const CR_XP := {"0": 10, "1/8": 25, "1/4": 50, "1/2": 100}


static func build(monster_id: String, instance_id: String, overrides := {}) -> Dictionary:
	var m: Dictionary = Srd.monsters.get(monster_id, {})
	if m.is_empty():
		push_error("Monstro desconhecido: %s" % monster_id)
		return {}
	var c := {
		"id": instance_id, "kind": "monster", "monster_id": monster_id,
		"name": Srd.label("monster", monster_id, m["name"]),
		"side": "enemy", "color": "#a55",
		"scores": m.get("abilities", {}).duplicate(), "pb": int(m.get("pb", 2)),
		"saves_fixed": m.get("saves", {}).duplicate(), "skills_fixed": m.get("skills_map", {}).duplicate(),
		"ac_fixed": int(m["ac"]), "hp_max": int(m["hp"]), "hp": int(m["hp"]), "temp_hp": 0,
		"hp_dice": m.get("hp_dice", ""), "initiative_fixed": int(m.get("initiative", 0)),
		"speed_ft": int(m.get("speed_ft", 30)), "speed_text": m.get("speed_text", ""),
		"cr": str(m.get("cr", "0")), "xp": int(m.get("xp", 0)),
		"type_line": m.get("type_line", ""), "senses": m.get("senses", ""),
		"conditions": [], "effects": [], "exhaustion": 0, "traits": {}, "resources": {},
		"resist": _dtypes(m.get("resistances", "")), "vuln": _dtypes(m.get("vulnerabilities", "")),
		"immune": _dtypes(m.get("immunities", "")), "cond_immune": _conds(m.get("immunities", "")),
		"death": {"dead": false},
		"features": [], "attacks": [], "monster_actions": [], "bonus_actions": [], "reactions": [],
		"multiattack": 0, "multiattack_text": "",
	}
	c["size"] = _size(c["type_line"])
	c["is_undead"] = c["type_line"].contains("Undead")
	c["is_fiend"] = c["type_line"].contains("Fiend")
	for tr in m.get("traits", []):
		c["features"].append({"id": tr["id"], "name": tr["name"], "text": tr["text"], "source": "Traço"})
		_trait_hooks(c, tr)
	for a in m.get("actions", []):
		if a.has("multiattack"):
			c["multiattack"] = int(a["multiattack"])
			c["multiattack_text"] = a["text"]
			c["features"].append({"id": a["id"], "name": a["name"], "text": a["text"], "source": "Ação"})
			continue
		var act := _action(a)
		c["monster_actions"].append(act)
		if act.has("to_hit"):
			c["attacks"].append(act)
	for a in m.get("bonus_actions", []):
		c["bonus_actions"].append(_action(a))
	for a in m.get("reactions", []):
		c["reactions"].append(_action(a))
	for k in overrides:
		c[k] = overrides[k]
	return c


static func _action(a: Dictionary) -> Dictionary:
	var act := {"id": a["id"], "name": a["name"], "text": a["text"], "kind": "monster"}
	if a.has("usage"):
		act["usage"] = a["usage"]
		var rm := RegEx.create_from_string("Recharge (\\d)").search(str(a["usage"]))
		if rm:
			act["recharge"] = int(rm.get_string(1))
			act["charged"] = true
		var dm := RegEx.create_from_string("(\\d+)/Day").search(str(a["usage"]))
		if dm:
			act["per_day"] = int(dm.get_string(1))
			act["uses_left"] = int(dm.get_string(1))
	if a.has("attack"):
		var at: Dictionary = a["attack"]
		act["to_hit"] = int(at["bonus"])
		act["ranged"] = at["type"] == "ranged"
		act["reach_m"] = Rules.m(maxi(5, int(at.get("reach_ft", 5)))) if at["type"] != "ranged" else 0.0
		var rr: Array = at.get("range_ft", [])
		act["range_m"] = [Rules.m(rr[0]), Rules.m(rr[1])] if rr.size() == 2 else []
		if at["type"] == "melee or ranged":
			act["ranged"] = false
	if a.has("damage"):
		act["damage"] = a["damage"]
		act["dtype"] = a.get("dtype", "")
	if a.has("extra"):
		act["extra"] = a["extra"]
	if a.has("save"):
		act["save"] = a["save"]
		act["half_on_save"] = a.get("half_on_save", false)
		var area := RegEx.create_from_string("(\\d+)-foot(?:-long)? (Cone|Line|Sphere|Emanation|Cube)").search(a["text"])
		if area:
			act["area"] = {"shape": area.get_string(2).to_lower(), "size_ft": int(area.get_string(1))}
		var cond := RegEx.create_from_string("(?:has|have) the (Blinded|Charmed|Deafened|Frightened|Grappled|Incapacitated|Paralyzed|Poisoned|Prone|Restrained|Stunned|Unconscious) condition").search(a["text"])
		if cond:
			act["condition"] = cond.get_string(1).to_lower()
	return act


static func _trait_hooks(c: Dictionary, tr: Dictionary) -> void:
	var t: Dictionary = c["traits"]
	var txt: String = tr["text"]
	if tr["id"] == "pack_tactics":
		t["pack_tactics"] = true
	if tr["id"].begins_with("magic_resistance"):
		t["magic_resistance"] = true
	if tr["id"].begins_with("legendary_resistance"):
		var n := RegEx.create_from_string("(\\d)/Day").search(tr["name"])
		c["resources"]["legendary_resistance"] = {"name": "Resistência Lendária", "max": int(n.get_string(1)) if n else 3, "left": int(n.get_string(1)) if n else 3, "recharge": "long"}
	if tr["id"] == "undead_fortitude":
		t["undead_fortitude"] = true
	if txt.contains("Sunlight Sensitivity") or tr["id"] == "sunlight_sensitivity":
		t["sunlight_sensitivity"] = true


static func _dtypes(txt: String) -> Array:
	var out: Array = []
	var part := txt.split(";")[0].to_lower()
	for dt in Srd.tables.get("damage_types", []):
		if part.contains(dt):
			out.append(dt)
	return out


static func _conds(txt: String) -> Array:
	var out: Array = []
	var parts := txt.split(";")
	var part := parts[parts.size() - 1].to_lower() if parts.size() > 1 else ""
	for cd in Srd.tables.get("conditions", []):
		if part.contains(cd):
			out.append(cd)
	return out


static func _size(type_line: String) -> String:
	for s in ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]:
		if type_line.begins_with(s):
			return s.to_lower()
	return "medium"
