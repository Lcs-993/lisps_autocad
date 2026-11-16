#!/usr/bin/env python3
"""Aplica os icones de menu/icons/icons.json nos fontes do menu FarmTools (menu/src).

- MenuGroup.cui: <SmallImage>/<LargeImage> de cada MenuMacro.
- RibbonRoot.cui: atributos SmallImage/LargeImage dos split buttons.

Os nomes gravados (ft-<id>-16.png / ft-<id>-32.png) sao os arquivos que o build_cuix.ps1
copia de menu/icons/png/<tema>/ para a raiz do FarmTools.cuix. E idempotente.
Uso:  python menu/aplicar_icones.py
"""
import json, re, sys
from pathlib import Path

MENU = Path(__file__).resolve().parent
ICONS = json.loads((MENU / "icons" / "icons.json").read_text(encoding="utf-8"))
PNG = MENU / "icons" / "png" / "dark"

def nomes(icon_id):
    s, l = f"ft-{icon_id}-16.png", f"ft-{icon_id}-32.png"
    for n in (s, l):
        if not (PNG / n).exists():
            sys.exit(f"Falta o arquivo {PNG / n}")
    return s, l

def edita(arquivo, func):
    p = MENU / "src" / arquivo
    txt = p.read_text(encoding="utf-8-sig")
    novo, n = func(txt)
    p.write_text(novo, encoding="utf-8-sig")
    print(f"{arquivo}: {n} elementos com icone")
    return novo

usados = set()

def menugroup(txt):
    n = 0
    def troca(m):
        nonlocal n
        uid, bloco = m.group(1), m.group(0)
        if uid not in ICONS:
            return bloco
        s, l = nomes(ICONS[uid]); usados.add(uid); n += 1
        if "<SmallImage" not in bloco:   # macro nova: cria as tags depois do HelpString
            m2 = re.search(r'\n(\s*)<HelpString[^\n]*\n', bloco)
            ind = m2.group(1)
            bloco = (bloco[:m2.end()] + f'{ind}<SmallImage Name="{s}" />\n{ind}<LargeImage Name="{l}" />\n'
                     + bloco[m2.end():])
        bloco = re.sub(r'<SmallImage Name="[^"]*"', f'<SmallImage Name="{s}"', bloco)
        return re.sub(r'<LargeImage Name="[^"]*"', f'<LargeImage Name="{l}"', bloco)
    return re.sub(r'<MenuMacro UID="([^"]+)">.*?</MenuMacro>', troca, txt, flags=re.S), n

def ribbon(txt):
    n = 0
    def troca(m):
        nonlocal n
        tag = m.group(0)
        uid = re.search(r'UID="([^"]+)"', tag).group(1)
        if uid not in ICONS:
            return tag
        s, l = nomes(ICONS[uid]); usados.add(uid); n += 1
        tag = re.sub(r'SmallImage="[^"]*"', f'SmallImage="{s}"', tag)
        return re.sub(r'LargeImage="[^"]*"', f'LargeImage="{l}"', tag)
    return re.sub(r'<RibbonSplitButton [^>]*>', troca, txt), n

mg = edita("MenuGroup.cui", menugroup)
edita("RibbonRoot.cui", ribbon)

faltando = set(ICONS) - usados
sem_icone = set(re.findall(r'<MenuMacro UID="([^"]+)"', mg)) - set(ICONS)
if faltando: print("Chaves do icons.json sem elemento no menu:", ", ".join(sorted(faltando)))
if sem_icone: print("Macros sem icone no icons.json:", ", ".join(sorted(sem_icone)))
