#!/usr/bin/env python3
"""Importa o SRD 5.2.1 (markdown CC-BY 4.0) para data/srd/*.json.

Uso:  python3 tools/srd_import.py <pasta-do-markdown> <pasta-de-saida>

Fonte: System Reference Document 5.2.1, Wizards of the Coast, CC-BY-4.0.
Conversão em markdown: github.com/downfallx/dnd-5e-srd-markdown.

O texto original fica em inglês nos campos "text". Os nomes e descrições em
português ficam em data/i18n/pt_BR/*.json, por cima destes dados.
"""
import json
import os
import re
import sys

from bs4 import BeautifulSoup

SRC = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = sys.argv[2] if len(sys.argv) > 2 else "data/srd"
os.makedirs(OUT, exist_ok=True)

ABILITIES = {"strength": "str", "dexterity": "dex", "constitution": "con",
             "intelligence": "int", "wisdom": "wis", "charisma": "cha"}
SKILLS = {
    "Acrobatics": "dex", "Animal Handling": "wis", "Arcana": "int", "Athletics": "str",
    "Deception": "cha", "History": "int", "Insight": "wis", "Intimidation": "cha",
    "Investigation": "int", "Medicine": "wis", "Nature": "int", "Perception": "wis",
    "Performance": "cha", "Persuasion": "cha", "Religion": "int", "Sleight of Hand": "dex",
    "Stealth": "dex", "Survival": "wis",
}
DAMAGE_TYPES = ["Acid", "Bludgeoning", "Cold", "Fire", "Force", "Lightning", "Necrotic",
                "Piercing", "Poison", "Psychic", "Radiant", "Slashing", "Thunder"]
CONDITIONS = ["Blinded", "Charmed", "Deafened", "Exhaustion", "Frightened", "Grappled",
              "Incapacitated", "Invisible", "Paralyzed", "Petrified", "Poisoned", "Prone",
              "Restrained", "Stunned", "Unconscious"]


def slug(s: str) -> str:
    s = s.lower().replace("’", "").replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def read(name: str) -> str:
    with open(os.path.join(SRC, name), encoding="utf-8-sig") as f:
        return f.read()


def clean(md: str) -> str:
    """Tira marcações de markdown/HTML simples, mantendo parágrafos."""
    md = re.sub(r"<br\s*/?>", "\n", md)
    md = re.sub(r"<hr\s*/?>", "", md)
    md = md.replace("**", "").replace("_", "")
    md = re.sub(r"\n{3,}", "\n\n", md)
    return md.strip()


def sections(md: str, level: int):
    """Divide o texto por títulos de um nível. Retorna [(título, corpo)]."""
    pat = re.compile(r"^" + "#" * level + r" (.+)$", re.M)
    out = []
    ms = list(pat.finditer(md))
    for i, m in enumerate(ms):
        end = ms[i + 1].start() if i + 1 < len(ms) else len(md)
        out.append((m.group(1).strip(), md[m.end():end]))
    return out


def tables(md: str):
    """Todas as tabelas HTML do trecho, como listas de linhas (listas de células)."""
    out = []
    for t in re.findall(r"<table>.*?</table>", md, re.S):
        soup = BeautifulSoup(t, "html.parser")
        rows = []
        for tr in soup.find_all("tr"):
            cells = [c.get_text(" ", strip=True) for c in tr.find_all(["td", "th"])]
            rows.append(cells)
        out.append(rows)
    return out


def strip_tables(md: str) -> str:
    return re.sub(r"<table>.*?</table>", "", md, flags=re.S)


def num(s: str, default=0):
    m = re.search(r"-?\d+", s.replace("−", "-").replace("–", "-"))
    return int(m.group()) if m else default


def ft(text: str) -> int:
    m = re.search(r"(\d[\d,]*)\s*(?:feet|foot|ft)", text)
    return int(m.group(1).replace(",", "")) if m else 0


# ------------------------------------------------------------------ magias

def parse_spells():
    md = read("spells.md")
    start = md.index("## Spell Descriptions")
    body = md[start:]
    spells = []
    for name, sec in sections(body, 4):
        head = re.search(r"^_(.+?)_\s*$", sec, re.M)
        if not head:
            continue
        h = head.group(1)
        m = re.match(r"(?:Level (\d) (\w+)|(\w+) Cantrip) \((.+)\)", h)
        if not m:
            continue
        level = int(m.group(1)) if m.group(1) else 0
        school = m.group(2) or m.group(3)
        classes = [c.strip() for c in m.group(4).split(",")]

        def field(label):
            fm = re.search(r"\*\*" + label + r":\*\*\s*(.+)", sec)
            return fm.group(1).strip() if fm else ""

        cast = field("Casting Time")
        rng = field("Range")
        comp = field("Components")
        dur = field("Duration")
        after = sec[sec.index(dur) + len(dur):] if dur else sec
        paras = [p.strip() for p in after.strip().split("\n\n") if p.strip()]
        text_parts, higher, upgrade = [], "", ""
        for p in paras:
            if p.startswith("_Using a Higher-Level Spell Slot._"):
                higher = clean(p.split("._", 1)[1])
            elif p.startswith("_Cantrip Upgrade._"):
                upgrade = clean(p.split("._", 1)[1])
            else:
                text_parts.append(p)
        text = clean(strip_tables("\n\n".join(text_parts)))
        sp = {
            "id": slug(name), "name": name, "level": level, "school": school,
            "classes": classes,
            "casting_time": re.sub(r" or Ritual", "", cast),
            "ritual": "Ritual" in cast,
            "range": rng, "range_ft": parse_range(rng),
            "components": {"v": bool(re.search(r"\bV\b", comp)), "s": bool(re.search(r"\bS\b", comp)),
                           "m": (re.search(r"M \((.+)\)", comp).group(1) if "M (" in comp else "")},
            "duration": dur, "concentration": dur.startswith("Concentration"),
            "text": text, "higher_level": higher, "cantrip_upgrade": upgrade,
        }
        sp["auto"] = spell_automation(sp)
        spells.append(sp)
    return spells


def parse_range(r: str) -> int:
    if r.startswith("Self"):
        inner = ft(r)
        return 0 if not inner else inner
    if r.startswith("Touch"):
        return 5
    if "mile" in r:
        return 5280 * num(r)
    return ft(r)


def spell_automation(sp) -> dict:
    """Deriva do texto oficial o que o motor consegue resolver sozinho."""
    t = sp["text"]
    a = {"kind": "manual"}
    m_att = re.search(r"(melee|ranged) spell attack", t)
    m_save = re.search(r"(?:makes?|make|succeed on) an? (Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) saving throw", t)
    m_dmg = re.findall(r"(\d+d\d+(?: \+ \d+)?)(?: plus your spellcasting ability modifier)? (" + "|".join(DAMAGE_TYPES) + r") damage", t)
    m_heal = re.search(r"regains? (?:a number of )?Hit Points equal to (\d+d\d+) plus your spellcasting ability modifier", t)
    m_heal2 = re.search(r"regains? (\d+d\d+|\d+) Hit Points", t)
    m_area = re.search(r"(\d+)-foot(?:-radius|-long|-wide)?(?:,? \d+-foot-(?:high|wide|tall))? (Sphere|Cone|Cube|Line|Cylinder|Emanation)", t)
    m_cond = re.findall(r"(?:has|have) the (" + "|".join(CONDITIONS) + r") condition", t)
    m_up = re.search(r"(?:damage|healing) increases by (\d+d\d+) for each spell slot level above (\d)", sp["higher_level"])
    m_up_t = re.search(r"one additional (?:creature|target)", sp["higher_level"])
    m_cu = re.search(r"increases by (\d+d\d+) when you reach levels 5", sp["cantrip_upgrade"])
    m_n = re.search(r"up to (two|three|four|five|six) (?:creatures|targets)", t)
    if m_att:
        a = {"kind": "attack", "attack": m_att.group(1)}
    elif m_save:
        a = {"kind": "save", "save": ABILITIES[m_save.group(1).lower()]}
    elif m_heal or m_heal2:
        a = {"kind": "heal"}
    elif m_cond:
        a = {"kind": "condition"}
    if m_dmg and a["kind"] in ("attack", "save"):
        a["damage"] = m_dmg[0][0].replace(" ", "")
        a["dtype"] = m_dmg[0][1].lower()
        if "plus your spellcasting ability modifier" in t.split(m_dmg[0][0], 1)[1][:45]:
            a["add_mod"] = True
        if a["kind"] == "save":
            a["half_on_save"] = "half as much damage" in t
    if a["kind"] == "heal":
        if m_heal:
            a["heal"] = m_heal.group(1)
            a["add_mod"] = True
        else:
            a["heal"] = m_heal2.group(1)
    if m_cond and a["kind"] in ("save", "attack", "condition"):
        a["conditions"] = sorted({c.lower() for c in m_cond})
    if m_area:
        a["area"] = {"shape": m_area.group(2).lower(), "size_ft": int(m_area.group(1))}
    if m_up:
        a["upcast_dice"] = m_up.group(1)
    if m_up_t:
        a["upcast_targets"] = 1
    if m_cu:
        a["cantrip_dice"] = m_cu.group(1)
    if m_n:
        a["targets"] = {"two": 2, "three": 3, "four": 4, "five": 5, "six": 6}[m_n.group(1)]
    return a


# ------------------------------------------------------------------ classes

def parse_classes():
    md = read("classes.md")
    classes = []
    for cname, csec in sections(md, 2):
        cid = slug(cname)
        core = tables(csec)[0]
        traits = {r[0]: r[1] for r in core if len(r) >= 2}
        hd = num(traits.get("Hit Point Die", "d8").split("per")[0].replace("D", ""))
        saves = [ABILITIES[w.lower()] for w in re.findall(r"\w+", traits.get("Saving Throw Proficiencies", "")) if w.lower() in ABILITIES]
        sk_text = traits.get("Skill Proficiencies", "")
        sk_n = num(sk_text, 2)
        sk_opts = [s for s in SKILLS if s in sk_text] if "any" not in sk_text.lower() else list(SKILLS)
        primary = [ABILITIES[w.lower()] for w in re.findall(r"\w+", traits.get("Primary Ability", "")) if w.lower() in ABILITIES]
        cls = {
            "id": cid, "name": cname, "hit_die": hd, "primary": primary, "saves": saves,
            "skills": {"choose": sk_n, "from": [slug(s) for s in sk_opts]},
            "weapons": traits.get("Weapon Proficiencies", ""),
            "tools": traits.get("Tool Proficiencies", ""),
            "armor": traits.get("Armor Training", ""),
            "equipment": parse_equipment_choice(traits.get("Starting Equipment", "")),
            "multiclass": "",
            "levels": [], "features": [], "subclasses": [], "spell_list": {},
        }
        mc = re.search(r"#### As a Multiclass Character\s*\n(.+?)(?=\n###)", csec, re.S)
        if mc:
            cls["multiclass"] = clean(mc.group(1))
        # Tabela de níveis
        feats_sec = re.search(r"### " + re.escape(cname) + r" Class Features(.+?)(?=\n### (?!" + re.escape(cname) + r" Class Features))", csec, re.S)
        fsec = feats_sec.group(1) if feats_sec else csec
        lt = tables(fsec)
        if lt:
            head = lt[0][0]
            rows = lt[0][1:]
            # Cabeçalho em duas linhas: "Spell Slots per Spell Level" + 1..9
            if rows and rows[0] and rows[0][0] == "":
                slot_labels = ["slot_" + x for x in rows[0] if x]
                head = [h for h in head if "Spell Slots" not in h] + slot_labels
                rows = rows[1:]
            for row in rows:
                while len(row) > len(head) and row[-1] == "":
                    row = row[:-1]
                if len(row) != len(head) or not row[0].isdigit():
                    continue
                lv = {"level": int(row[0])}
                for h, v in zip(head[1:], row[1:]):
                    key = slug(h)
                    if key == "class_features":
                        lv["features"] = [x.strip() for x in v.split(",") if x.strip() and x.strip() != "—"]
                    elif key == "proficiency_bonus":
                        continue
                    else:
                        lv[key] = v
                cls["levels"].append(lv)
            # tabela extra de espaços de magia (meio conjuradores têm em outra tabela)
        for title, body in sections(fsec, 4):
            m = re.match(r"Level (\d+): (.+)", title)
            if not m:
                continue
            feat = {"level": int(m.group(1)), "name": m.group(2).strip(),
                    "id": slug(m.group(2)), "text": clean(strip_tables(body))}
            tb = tables(body)
            if tb:
                feat["tables"] = tb
            cls["features"].append(feat)
        # Listas de opções (Metamagia, Invocações...)
        cls["options"] = {}
        for title, body in sections(csec, 3):
            om = re.match(r"(.+) Options$", title)
            if not om:
                continue
            opts = []
            for t2, b2 in sections(body, 4):
                pre = re.search(r"^_Prerequisite: (.+?)_\s*$", b2, re.M)
                cost = re.search(r"Cost: (\d+) Sorcery Points?", b2)
                opts.append({"id": slug(t2), "name": t2, "prerequisite": pre.group(1) if pre else "",
                             "cost": int(cost.group(1)) if cost else 0,
                             "text": clean(re.sub(r"^_Prerequisite: .+?_\s*$", "", b2, flags=re.M))})
            cls["options"][slug(om.group(1))] = opts
        # Lista de magias
        sl = re.search(r"### " + re.escape(cname) + r" Spell List(.+?)(?=\n### )", csec, re.S)
        if sl:
            for title, body in sections(sl.group(1), 4):
                lvm = re.search(r"Level (\d)", title)
                lvl = 0 if "Cantrip" in title else (int(lvm.group(1)) if lvm else -1)
                t = tables(body)
                names = [r[0] for r in t[0][1:]] if t else []
                cls["spell_list"][str(lvl)] = [slug(n) for n in names if n]
        # Subclasses
        for title, body in sections(csec, 3):
            m = re.match(re.escape(cname) + r" Subclass: (.+)", title)
            if not m:
                continue
            intro = body.split("\n####")[0]
            sub = {"id": slug(m.group(1)), "name": m.group(1).strip(), "text": clean(strip_tables(intro)), "features": []}
            for t2, b2 in sections(body, 4):
                m2 = re.match(r"Level (\d+): (.+)", t2)
                if m2:
                    sf = {"level": int(m2.group(1)), "name": m2.group(2).strip(),
                          "id": slug(m2.group(2)), "text": clean(strip_tables(b2))}
                    tb = tables(b2)
                    if tb:
                        sf["tables"] = tb
                    sub["features"].append(sf)
            cls["subclasses"].append(sub)
        classes.append(cls)
    return classes


def parse_equipment_choice(s: str):
    opts = re.findall(r"\(([A-C])\) (.+?)(?=;\s*(?:or\s+)?\([A-C]\)|$)", s)
    out = []
    for letter, items in opts:
        items = items.strip().rstrip(".")
        parts = [p.strip() for p in re.split(r",\s*(?:and\s+)?|\s+and\s+", items) if p.strip()]
        gp = 0
        lst = []
        for p in parts:
            g = re.match(r"(\d+) GP$", p)
            if g:
                gp += int(g.group(1))
                continue
            q = re.match(r"(\d+) (.+)", p)
            lst.append({"qty": int(q.group(1)), "item": q.group(2)} if q else {"qty": 1, "item": p})
        out.append({"option": letter, "items": lst, "gp": gp})
    return out


# ------------------------------------------------------------------ origens e talentos

def parse_origins():
    md = read("character-origins.md")
    bg_md = md[md.index("### Background Descriptions"):md.index("## Character Species")]
    backgrounds = []
    for name, sec in sections(bg_md, 4):
        def f(label):
            m = re.search(r"\*\*" + label + r":\*\*\s*(.+)", sec)
            return m.group(1).strip() if m else ""
        feat = f("Feat")
        fm = re.match(r"(.+?)(?: \((\w+)\))?(?: \(see .+\))?$", feat)
        backgrounds.append({
            "id": slug(name), "name": name,
            "abilities": [ABILITIES[w.lower()] for w in re.findall(r"\w+", f("Ability Scores")) if w.lower() in ABILITIES],
            "feat": slug(fm.group(1)) if fm else "", "feat_option": (fm.group(2) or "").lower() if fm else "",
            "skills": [slug(s) for s in SKILLS if s in f("Skill Proficiencies")],
            "tool": clean(f("Tool Proficiency")),
            "equipment": parse_equipment_choice(clean(f("Equipment"))),
        })
    sp_md = md[md.index("### Species Descriptions"):]
    species = []
    for name, sec in sections(sp_md, 4):
        def f(label):
            m = re.search(r"\*\*" + label + r":\*\*\s*(.+)", sec)
            return m.group(1).strip() if m else ""
        traits = []
        for m in re.finditer(r"^_(.+?)\._ (.+?)(?=\n_[A-Z][^_]+\._ |\Z)", strip_tables(sec), re.S | re.M):
            traits.append({"id": slug(m.group(1)), "name": m.group(1), "text": clean(m.group(2))})
        sp = {"id": slug(name), "name": name, "type": f("Creature Type"),
              "size": f("Size"), "speed_ft": ft(f("Speed")), "traits": traits,
              "darkvision_ft": 0, "resistances": []}
        dv = re.search(r"Darkvision with a range of (\d+) feet", sec)
        if dv:
            sp["darkvision_ft"] = int(dv.group(1))
        for d in DAMAGE_TYPES:
            if re.search(r"Resistance to " + d + " damage", sec):
                sp["resistances"].append(d.lower())
        t = tables(sec)
        if t:
            sp["table"] = t[0]
        species.append(sp)
    return backgrounds, species


def parse_feats():
    md = read("feats.md")
    feats = []
    for cat, csec in sections(md, 3):
        if "Feats" not in cat:
            continue
        category = slug(cat.replace(" Feats", ""))
        for name, sec in sections(csec, 4):
            pre = re.search(r"_(.+?Feat.*?)_", sec)
            rep = "Repeatable" in sec
            body = re.sub(r"^_.+?_\s*$", "", sec, count=1, flags=re.M)
            feats.append({"id": slug(name), "name": name, "category": category,
                          "header": pre.group(1) if pre else "", "repeatable": rep,
                          "text": clean(body)})
    return feats


# ------------------------------------------------------------------ equipamento

def parse_equipment():
    md = read("equipment.md")
    weapons, armor = [], []
    wmd = md[md.index("**Weapons**"):md.index("## Armor")]
    cat = ""
    for row in tables(wmd)[0][1:]:
        if len(row) == 1:
            cat = row[0]
            continue
        name, dmg, props, mastery, weight, cost = row[:6]
        dm = re.match(r"(\d+d\d+|\d+) (\w+)", dmg)
        props_l = [p.strip() for p in props.split(",") if p.strip() and p.strip() != "—"]
        w = {"id": slug(name), "name": name, "category": "martial" if "Martial" in cat else "simple",
             "ranged": "Ranged" in cat, "damage": dm.group(1) if dm else "0", "dtype": dm.group(2).lower() if dm else "",
             "properties": [slug(re.sub(r"\s*\(.*", "", p)) for p in props_l], "properties_text": props_l,
             "mastery": slug(mastery), "weight": weight, "cost": cost}
        for p in props_l:
            r = re.search(r"Range (\d+)/(\d+)", p)
            if r:
                w["range_ft"] = [int(r.group(1)), int(r.group(2))]
            v = re.search(r"Versatile \((\d+d\d+)\)", p)
            if v:
                w["versatile"] = v.group(1)
        weapons.append(w)
    amd = md[md.index("**Armor**"):md.index("## Tools")]
    cat = ""
    for row in tables(amd)[0][1:]:
        if len(row) == 1:
            cat = row[0].split(" ")[0].lower()
            continue
        name, ac, strength, stealth, weight, cost = row[:6]
        a = {"id": slug(name), "name": name, "category": cat, "weight": weight, "cost": cost,
             "stealth_dis": "Disadvantage" in stealth, "str_req": num(strength) if strength != "—" else 0}
        if cat == "shield":
            a["ac_bonus"] = num(ac)
        else:
            a["ac_base"] = num(ac)
            a["dex"] = "Dex" in ac
            mx = re.search(r"max (\d)", ac)
            a["dex_max"] = int(mx.group(1)) if mx else (99 if "Dex" in ac else 0)
        armor.append(a)
    props = {}
    for m in re.finditer(r"^\*\*([A-Z][\w ]+)\.\*\* (.+)$", md[md.index("### Properties"):md.index("**Weapons**")], re.M):
        props[slug(m.group(1))] = {"name": m.group(1), "text": clean(m.group(2))}
    gear = []
    tmd = md[md.index("## Tools"):md.index("## Adventuring Gear")]
    for m in re.finditer(r"^\*\*([^*\n]+?) \((\d[\d,]* [GSC]P|Varies)\)\*\*\s*\n(.+?)(?=\n\*\*[^*]+ \(\d|\n####|\Z)", tmd, re.S | re.M):
        gear.append({"id": slug(m.group(1)), "name": m.group(1), "cost": m.group(2), "kind": "tool",
                     "text": clean(m.group(3))})
    gstart = md.index("## Adventuring Gear")
    gend = md.find("\n## ", gstart + 5)
    gmd = md[gstart:gend if gend > 0 else len(md)]
    for name, sec in sections(gmd, 4):
        m = re.match(r"(.+?) \((.+)\)$", name)
        gear.append({"id": slug(m.group(1) if m else name), "name": m.group(1) if m else name,
                     "cost": m.group(2) if m else "", "text": clean(strip_tables(sec))})
    return weapons, armor, props, gear


# ------------------------------------------------------------------ glossário

def parse_glossary():
    md = read("rules-glossary.md")
    entries = []
    for name, sec in sections(md, 4):
        m = re.match(r"(.+?)(?: \[(.+)\])?$", name)
        entries.append({"id": slug(m.group(1)), "name": m.group(1), "tag": (m.group(2) or "").lower(),
                        "text": clean(strip_tables(sec))})
    return entries


# ------------------------------------------------------------------ monstros

def parse_monsters():
    out = []
    for fname in ["monsters-A-Z.md", "animals.md"]:
        md = read(fname)
        for name, sec in sections(md, 2 if fname == "animals.md" else 3):
            if "**AC**" not in sec:
                continue
            mon = parse_statblock(name, sec)
            if mon:
                mon["source"] = "animals" if fname == "animals.md" else "monsters"
                out.append(mon)
    return out


def parse_statblock(name, sec):
    head = re.search(r"^_(.+?)_\s*$", sec, re.M)
    m = {"id": slug(name), "name": name, "type_line": head.group(1) if head else ""}
    acm = re.search(r"\*\*AC\*\* (\d+)", sec)
    m["ac"] = int(acm.group(1)) if acm else 10
    ini = re.search(r"\*\*Initiative\*\* ([+−-]\d+)", sec)
    m["initiative"] = num(ini.group(1)) if ini else 0
    hp = re.search(r"\*\*HP\*\* (\d+)(?: \((.+?)\))?", sec)
    m["hp"] = int(hp.group(1)) if hp else 1
    m["hp_dice"] = hp.group(2) if hp and hp.group(2) else ""
    spd = re.search(r"\*\*Speed\*\* (.+?)(?:<br>|\n)", sec)
    m["speed_text"] = spd.group(1).strip() if spd else "30 ft."
    m["speed_ft"] = ft(m["speed_text"]) or 30
    t = tables(sec)
    m["abilities"] = {}
    m["saves"] = {}
    if t:
        for row in t[0][1:]:
            for i in range(0, len(row) - 3, 4):
                ab = row[i].lower()
                if ab in ABILITIES.values():
                    m["abilities"][ab] = num(row[i + 1], 10)
                    m["saves"][ab] = num(row[i + 3])
    for label in ["Skills", "Resistances", "Vulnerabilities", "Immunities", "Gear", "Senses", "Languages"]:
        fm = re.search(r"\*\*" + label + r"\*\* (.+?)(?:<br>|\n)", sec)
        m[slug(label)] = fm.group(1).strip() if fm else ""
    cr = re.search(r"\*\*CR\*\* ([\d/]+)(?: \(XP ([\d,]+)(?:, or [\d,]+ in lair)?; PB \+(\d+)\))?", sec)
    m["cr"] = cr.group(1) if cr else "0"
    m["xp"] = int(cr.group(2).replace(",", "")) if cr and cr.group(2) else 0
    m["pb"] = int(cr.group(3)) if cr and cr.group(3) else 2
    m["skills_map"] = {slug(s): num(v) for s, v in re.findall(r"([A-Z][a-z]+(?: [a-zA-Z]+)*) ([+−-]\d+)", m["skills"])}
    for blk in ["Traits", "Actions", "Bonus Actions", "Reactions", "Legendary Actions"]:
        bm = re.search(r"#{3,4} " + blk + r"\s*\n(.+?)(?=\n#{2,4} |\Z)", sec, re.S)
        items = []
        if bm:
            for im in re.finditer(r"\*\*_(.+?)\._\*\* (.+?)(?=\n\s*\*\*_|\Z)", bm.group(1), re.S):
                items.append(parse_monster_action(im.group(1), clean(im.group(2))))
        m[slug(blk)] = items
    return m


def parse_monster_action(name, text):
    a = {"id": slug(re.sub(r"\s*\(.*\)", "", name)), "name": name, "text": text}
    usage = re.search(r"\((Recharge [\d–-]+|\d+/Day[^)]*)\)", name)
    if usage:
        a["usage"] = usage.group(1)
    at = re.search(r"(Melee|Ranged|Melee or Ranged) Attack Roll: ([+−-]\d+), (?:reach (\d+) ft\.)?(?:(?: or )?range (\d+)/(\d+) ft\.)?", text)
    if at:
        a["attack"] = {"type": at.group(1).lower(), "bonus": num(at.group(2)),
                       "reach_ft": int(at.group(3)) if at.group(3) else 0,
                       "range_ft": [int(at.group(4)), int(at.group(5))] if at.group(4) else []}
    hit = re.search(r"Hit: (\d+) \((\d+d\d+(?: [+−-] \d+)?)\) (\w+) damage", text)
    if hit:
        a["damage"] = hit.group(2).replace("−", "-").replace(" ", "")
        a["dtype"] = hit.group(3).lower()
    ex = re.search(r"plus (\d+) \((\d+d\d+(?: [+−-] \d+)?)\) (\w+) damage( if the attack roll had Advantage)?", text)
    if ex and "damage" in a:
        a["extra"] = {"damage": ex.group(2).replace("−", "-").replace(" ", ""), "dtype": ex.group(3).lower(),
                      "only_with_advantage": bool(ex.group(4))}
    sv = re.search(r"(Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) Saving Throw: DC (\d+)", text)
    if sv:
        a["save"] = {"ability": ABILITIES[sv.group(1).lower()], "dc": int(sv.group(2))}
        fd = re.search(r"Failure: (\d+) \((\d+d\d+(?: [+−-] \d+)?)\) (\w+) damage", text)
        if fd:
            a["damage"] = fd.group(2).replace("−", "-").replace(" ", "")
            a["dtype"] = fd.group(3).lower()
        a["half_on_save"] = "Success: Half damage" in text
    ma = re.search(r"makes (two|three|four|five) (?:attacks|\w+ attacks)", text)
    if name.startswith("Multiattack") and ma:
        a["multiattack"] = {"two": 2, "three": 3, "four": 4, "five": 5}[ma.group(1)]
    return a


# ------------------------------------------------------------------ tabelas gerais

def static_tables():
    return {
        "proficiency_by_level": {str(l): 2 + (l - 1) // 4 for l in range(1, 21)},
        "xp_by_level": {"1": 0, "2": 300, "3": 900, "4": 2700, "5": 6500, "6": 14000, "7": 23000,
                        "8": 34000, "9": 48000, "10": 64000, "11": 85000, "12": 100000, "13": 120000,
                        "14": 140000, "15": 165000, "16": 195000, "17": 225000, "18": 265000,
                        "19": 305000, "20": 355000},
        "skills": {slug(k): {"name": k, "ability": v} for k, v in SKILLS.items()},
        "point_buy": {"8": 0, "9": 1, "10": 2, "11": 3, "12": 4, "13": 5, "14": 7, "15": 9},
        "standard_array": [15, 14, 13, 12, 10, 8],
        "damage_types": [d.lower() for d in DAMAGE_TYPES],
        "conditions": [c.lower() for c in CONDITIONS],
    }


def main():
    spells = parse_spells()
    classes = parse_classes()
    backgrounds, species = parse_origins()
    feats = parse_feats()
    weapons, armor, props, gear = parse_equipment()
    glossary = parse_glossary()
    monsters = parse_monsters()
    data = {
        "spells": spells, "classes": classes, "backgrounds": backgrounds, "species": species,
        "feats": feats, "weapons": weapons, "armor": armor, "weapon_properties": props,
        "gear": gear, "glossary": glossary, "monsters": monsters, "tables": static_tables(),
    }
    for k, v in data.items():
        with open(os.path.join(OUT, k + ".json"), "w", encoding="utf-8") as f:
            json.dump(v, f, ensure_ascii=False, indent=1)
    with open(os.path.join(OUT, "LICENSE.txt"), "w", encoding="utf-8") as f:
        f.write(ATTRIBUTION)
    for k, v in data.items():
        print(f"{k:18s} {len(v)}")


ATTRIBUTION = """This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1")
by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is
licensed under the Creative Commons Attribution 4.0 International License, available at
https://creativecommons.org/licenses/by/4.0/legalcode.
"""

if __name__ == "__main__":
    main()
