"""Gera o catalogo de comandos do AgroCAD a partir do arquivo de menu (.cuix).

O .cuix e um pacote ZIP com XMLs (MenuGroup.cui = macros, RibbonRoot.cui =
abas/paineis/botoes). Este script cruza os dois e produz:

  - <saida>.json : lista completa (aba, painel, comando, macro, descricao)
  - <saida>.md   : tabela por aba/painel, com a coluna "Porte" indicando se a
                   ferramenta ja foi recriada em lisps/ (comando LISPS)

Uso:
  python -I src/tools/agrocad_catalog.py \
      "C:/Tecgraf/AgroCAD/Interface/Languages/pt-BR/MNU/AgroCAD.cuix" \
      references/agrocad/catalogo-comandos
"""
from __future__ import annotations

import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

# comando AgroCAD -> comando LISPS que o substitui (atualizar a cada porte)
PORTADOS = {
    "GOFUR": "CRIALINHAS",
    "TR-SUL": "TR-SU",
    "TR-TAL": "TR-TA",
    "TR-TER": "TR-TE",
    "TR-COL": "TR-CO",
    "COF": "CORTALIM",
    "TOLIM": "ESTENDELIM",
    "ESC": "AJUSTALIM",
    "DELIM": "APAGALIM",
    "GOCON": "CONECTALINHAS",
    "GOROA": "CARREADORES",
    "CSYS": "SISCOORD",
    "GOOBS": "DESVIAOBS",
    "GOTUR": "MANOBRAS",
    "SMP": "SIMPLIFICAPL",
    "GOSMP": "SIMPLIFICAPL",
    "AR2RE": "SEGMENTARCOS",
    "CHECKDWG": "VERIFICAPROJ",
    "RNOS": "REMOVENOS",
    "HME": "PADRONIZAVERT",
    "GOIMP": "GEOIMPORTAR",
    "GOEXP": "GEOEXPORTAR",
    "KLA": "CLA_GERENCIAR",
    "CFT": "CLA_CFT",
    "RCFT": "CLA_REMOVER",
    "CPCFT": "CLA_COPIAR",
    "CFL": "CLA_AUTO",
    "VV": "CLA_VER",
    "JDBEX": "CLA_LIMEXT",
    "JDBIN": "CLA_LIMINT",
    "JDHBEX": "CLA_CABEXT",
    "JDHBIN": "CLA_CABINT",
    "JDABC": "CLA_CURVAAB",
    "JDABL": "CLA_LINHAAB",
    "JDLIN": "CLA_ADAPT",
    "CGLE": "CLA_GLEBA",
}


def _txt(el, tag):
    x = el.find(tag)
    return (x.text or "").strip() if x is not None and x.text else ""


def comando_da_macro(macro: str) -> str:
    """'^C^C_GOFUR;' -> 'GOFUR'. Para macros LISP '(c:xx)' devolve 'XX'."""
    m = macro.replace("^C", "").replace("^P", "").strip()
    lisp = re.match(r"\(\s*c:([\w\-]+)", m, re.I)
    if lisp:
        return lisp.group(1).upper()
    m = m.lstrip("_.'")
    return re.split(r"[\s;]", m, maxsplit=1)[0].upper()


def ler_macros(z: zipfile.ZipFile) -> dict:
    root = ET.fromstring(z.read("MenuGroup.cui"))
    macros = {}
    for mm in root.iter("MenuMacro"):
        mac = mm.find("Macro")
        if mac is None:
            continue
        cmd = _txt(mac, "Command")
        macros[mm.get("UID")] = {
            "nome": _txt(mac, "Name"),
            "macro": cmd,
            "comando": comando_da_macro(cmd),
            "descricao": _txt(mac, "HelpString"),
            "icone": (mac.find("LargeImage").get("Name")
                      if mac.find("LargeImage") is not None else ""),
        }
    return macros


def ler_ribbon(z: zipfile.ZipFile, macros: dict) -> list:
    root = ET.fromstring(z.read("RibbonRoot.cui"))
    paineis = {}
    for ps in root.iter("RibbonPanelSource"):
        nome = _txt(ps, "Name") or ps.get("Text", "")
        botoes = []
        for b in ps.iter():
            mid = b.get("MenuMacroID")
            if mid and mid in macros:
                botoes.append((mid, b.get("Text") or _txt(b, "TooltipTitle")))
        paineis[ps.get("UID")] = (nome, botoes)

    linhas, vistos = [], set()
    for tab in root.iter("RibbonTabSource"):
        aba = _txt(tab, "Name") or tab.get("Text", "")
        for ref in tab.iter("RibbonPanelSourceReference"):
            nome_p, botoes = paineis.get(ref.get("PanelId"), ("?", []))
            for mid, rotulo in botoes:
                m = macros[mid]
                chave = (aba, nome_p, mid)
                if chave in vistos:
                    continue
                vistos.add(chave)
                linhas.append({"aba": aba, "painel": nome_p,
                               "rotulo": rotulo or m["nome"], **m,
                               "porte": PORTADOS.get(m["comando"], "")})
    # macros que nao aparecem no ribbon (menus pop-up, atalhos)
    usados = {l["macro"] for l in linhas}
    for m in macros.values():
        if m["macro"] and m["macro"] not in usados:
            linhas.append({"aba": "(fora do ribbon)", "painel": "", "rotulo": m["nome"],
                           **m, "porte": PORTADOS.get(m["comando"], "")})
            usados.add(m["macro"])
    return linhas


def md_escape(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", " ")


def gravar(linhas: list, saida: Path) -> None:
    saida.parent.mkdir(parents=True, exist_ok=True)
    saida.with_suffix(".json").write_text(
        json.dumps(linhas, ensure_ascii=False, indent=2), encoding="utf-8")

    out = ["# Catalogo de comandos AgroCAD",
           "",
           "Gerado por `src/tools/agrocad_catalog.py` a partir do menu (.cuix) instalado.",
           "Coluna **Porte**: comando equivalente ja recriado no menu LISPS.",
           "",
           f"Total: {len(linhas)} entradas | portados: "
           f"{sum(1 for l in linhas if l['porte'])}",
           ""]
    atual = None
    for l in linhas:
        grupo = (l["aba"], l["painel"])
        if grupo != atual:
            atual = grupo
            out += ["", f"## {l['aba']} > {l['painel'] or '-'}", "",
                    "| Comando | Nome | Porte | Descricao |",
                    "|---|---|---|---|"]
        out.append(f"| `{md_escape(l['comando'])}` | {md_escape(l['rotulo'])} | "
                   f"{l['porte']} | {md_escape(l['descricao'])} |")
    saida.with_suffix(".md").write_text("\n".join(out) + "\n", encoding="utf-8")


def main(argv: list) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    with zipfile.ZipFile(argv[1]) as z:
        macros = ler_macros(z)
        linhas = ler_ribbon(z, macros)
    gravar(linhas, Path(argv[2]))
    print(f"{len(macros)} macros, {len(linhas)} entradas -> {argv[2]}.json/.md")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
