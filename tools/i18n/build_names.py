"""Junta os nomes traduzidos em data/i18n/pt_BR/names.json (mantém o que já existe)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from names_spells_items import SPELL, WEAPON, ARMOR, GEAR
from names_features_monsters import FEATURE, MONSTER, dragon_names

path = os.path.join(os.path.dirname(__file__), "..", "..", "data", "i18n", "pt_BR", "names.json")
names = json.load(open(path, encoding="utf-8"))
names["spell"] = SPELL
names["weapon"] = WEAPON
names["armor"] = ARMOR
names["gear"] = GEAR
names["feature"] = {**FEATURE}
m = dict(MONSTER)
m.update(dragon_names())
names["monster"] = m
json.dump(names, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
srd = os.path.join(os.path.dirname(__file__), "..", "..", "data", "srd")
for kind, file in [("spell", "spells"), ("weapon", "weapons"), ("armor", "armor"), ("gear", "gear"), ("monster", "monsters")]:
    ids = [x["id"] for x in json.load(open(os.path.join(srd, file + ".json")))]
    missing = [i for i in ids if i not in names[kind]]
    print(f"{kind:8s} {len(ids) - len(missing)}/{len(ids)} traduzidos", ("faltam: " + ", ".join(missing[:12])) if missing else "")
