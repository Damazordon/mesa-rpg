"""Tabela id do jogo -> ícone do game-icons.net ("autor/nome").

Para trocar um ícone: edite aqui e rode
    python3 tools/icons/build_icons.py <pasta do clone de github.com/game-icons/icons>
Os ids de arma são os de data/srd/weapons.json; os de perícia, os de data/srd/tables.json.
"""

WEAPONS = {
    "club": "delapouite/wood-club",
    "dagger": "lorc/plain-dagger",
    "greatclub": "skoll/spiked-bat",
    "handaxe": "delapouite/hatchet",
    "javelin": "delapouite/spear-feather",
    "light_hammer": "lorc/flat-hammer",
    "mace": "delapouite/flanged-mace",
    "quarterstaff": "delapouite/wood-stick",
    "sickle": "delapouite/sickle",
    "spear": "lorc/stone-spear",
    "dart": "delapouite/dart",
    "light_crossbow": "carl-olsen/crossbow",
    "shortbow": "delapouite/bow-arrow",
    "sling": "delapouite/sling",
    "battleaxe": "lorc/battle-axe",
    "flail": "delapouite/flail",
    "glaive": "delapouite/glaive",
    "greataxe": "delapouite/war-axe",
    "greatsword": "delapouite/two-handed-sword",
    "halberd": "lorc/halberd",
    "lance": "lorc/spear-hook",
    "longsword": "lorc/broadsword",
    "maul": "lorc/hammer-drop",
    "morningstar": "lorc/spiked-mace",
    "pike": "lorc/spears",
    "rapier": "lorc/piercing-sword",
    "scimitar": "lorc/sparkling-sabre",
    "shortsword": "skoll/gladius",
    "trident": "lorc/trident",
    "warhammer": "delapouite/warhammer",
    "war_pick": "delapouite/war-pick",
    "whip": "lorc/whip",
    "blowgun": "delapouite/straight-pipe",
    "hand_crossbow": "carl-olsen/crossbow",
    "heavy_crossbow": "carl-olsen/crossbow",
    "longbow": "lorc/high-shot",
    "musket": "skoll/musket",
    "pistol": "john-colburn/pistol-gun",
}

SKILLS = {
    "acrobatics": "darkzaitzev/acrobatic",
    "animal_handling": "lorc/paw-print",
    "arcana": "delapouite/spell-book",
    "athletics": "lorc/muscle-up",
    "deception": "delapouite/carnival-mask",
    "history": "delapouite/ancient-columns",
    "insight": "delapouite/all-seeing-eye",
    "intimidation": "delapouite/angry-eyes",
    "investigation": "lorc/magnifying-glass",
    "medicine": "delapouite/stethoscope",
    "nature": "lorc/pine-tree",
    "perception": "delapouite/eye-target",
    "performance": "delapouite/pan-flute",
    "persuasion": "delapouite/shaking-hands",
    "religion": "lorc/holy-symbol",
    "sleight_of_hand": "delapouite/lockpicks",
    "stealth": "darkzaitzev/hooded-figure",
    "survival": "lorc/campfire",
}

# Usados quando a arma não tem ícone próprio (arma sob medida, ataque desarmado...).
GENERIC = {
    "melee": "lorc/crossed-swords",
    "ranged": "delapouite/bow-arrow",
    "unarmed": "lorc/punch",
}
