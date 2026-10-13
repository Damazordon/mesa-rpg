"""Junta as traduções de texto em data/i18n/pt_BR/texts.json."""
import glob, importlib.util, json, os

here = os.path.dirname(os.path.abspath(__file__))
out = {"glossary": {}, "feature": {}, "feat": {}, "spell": {}}
for path in sorted(glob.glob(os.path.join(here, "texts_*.py"))):
    spec = importlib.util.spec_from_file_location(os.path.basename(path)[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for attr, kind in [("GLOSSARY", "glossary"), ("SPECIES_TRAIT", "feature"), ("FEATURE", "feature"), ("FEAT", "feat"), ("SPELL", "spell")]:
        out[kind].update(getattr(mod, attr, {}))
dest = os.path.join(here, "..", "..", "data", "i18n", "pt_BR", "texts.json")
json.dump(out, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
srd = os.path.join(here, "..", "..", "data", "srd")
spells = [s["id"] for s in json.load(open(os.path.join(srd, "spells.json")))]
classes = json.load(open(os.path.join(srd, "classes.json")))
feat_keys = set()
for c in classes:
    for f in c["features"]:
        feat_keys.add((c["id"], f["id"]))
    for s in c["subclasses"]:
        for f in s["features"]:
            feat_keys.add(("", f["id"]))
done = sum(1 for (cid, fid) in feat_keys if f"{cid}:{fid}" in out["feature"] or fid in out["feature"])
print({k: len(v) for k, v in out.items()})
print(f"características de classe traduzidas: {done}/{len(feat_keys)}; magias: {sum(1 for s in spells if s in out['spell'])}/{len(spells)}")
