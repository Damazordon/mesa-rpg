"""Frases comuns de "Em nível superior" usadas pelos arquivos texts_spells_*.py."""

_P = "\n\nEm nível superior. "


def D(die, base, what="O dano"):
    return _P + "%s aumenta em %s para cada nível de espaço acima de %d." % (what, die, base)


def H(die, base):
    return _P + "A cura aumenta em %s para cada nível de espaço acima de %d." % (die, base)


def T(base, what="uma criatura adicional"):
    return _P + "Você pode escolher %s para cada nível de espaço acima de %d." % (what, base)


def X(text):
    return _P + text
