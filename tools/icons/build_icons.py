#!/usr/bin/env python3
"""Copia para o projeto os ícones do game-icons.net listados em icon_map.py.

Uso:  python3 tools/icons/build_icons.py <pasta do clone de github.com/game-icons/icons>

Gera (não editar à mão):
  assets/icons/game-icons/<autor>/<nome>.svg   (sem o quadrado preto de fundo; traço branco,
                                                para o jogo tingir com modulate)
  assets/icons/game-icons/CREDITS.txt          (atribuição exigida pela CC BY 3.0)
  data/icons.json                              (id -> arquivo, usado por scripts/core/icon_store.gd)
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icon_map  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "icons", "game-icons")
BG = '<path d="M0 0h512v512H0z"/>'

AUTHORS = {
    "lorc": "Lorc (lorcblog.blogspot.com)",
    "delapouite": "Delapouite (delapouite.com)",
    "skoll": "Skoll",
    "carl-olsen": "Carl Olsen (twitter.com/unstoppableCarl)",
    "john-colburn": "John Colburn (ninmunanmu.com)",
    "darkzaitzev": "DarkZaitzev (darkzaitzev.deviantart.com)",
}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = sys.argv[1]
    groups = {"weapon": icon_map.WEAPONS, "skill": icon_map.SKILLS, "generic": icon_map.GENERIC}
    out_json = {k: {} for k in groups}
    used = set()
    for kind, table in groups.items():
        for key, ref in table.items():
            path = os.path.join(src, ref + ".svg")
            if not os.path.isfile(path):
                print("NÃO ACHEI:", kind, key, ref)
                return 1
            out_json[kind][key] = ref
            used.add(ref)
    for ref in sorted(used):
        svg = open(os.path.join(src, ref + ".svg"), encoding="utf-8").read()
        if BG not in svg:
            print("fundo não reconhecido em", ref)
            return 1
        svg = svg.replace(BG, "")
        svg = re.sub(r'<path (?![^>]*fill=)', '<path fill="#fff" ', svg)
        dst = os.path.join(OUT, ref + ".svg")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
    authors = sorted({r.split("/")[0] for r in used})
    lines = [
        "Ícones de game-icons.net, licença Creative Commons Attribution 3.0 (CC BY 3.0):",
        "https://creativecommons.org/licenses/by/3.0/",
        "Fonte: https://game-icons.net  (repositório github.com/game-icons/icons)",
        "Modificação: removido o quadrado preto de fundo e fixado o traço em branco.",
        "",
        "Icons made by:",
    ]
    for a in authors:
        lines.append("  - " + AUTHORS.get(a, a) + "   [pasta %s/]" % a)
    lines += ["", "Ícone por arquivo:"] + ["  " + r for r in sorted(used)]
    with open(os.path.join(OUT, "CREDITS.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(ROOT, "data", "icons.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(out_json, f, indent=1, sort_keys=True)
        f.write("\n")
    print("ok: %d ícones, %d autores" % (len(used), len(authors)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
