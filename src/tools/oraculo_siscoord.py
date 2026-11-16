"""Oráculo do SISCOORD (CSYS).

1. A lista GERADA por cs:embutidos (famílias x zonas) cobre todos os
   códigos da lista do AgroCAD instalada (COORDS-pt-BR.AGROCAD), quando ela
   existe.
2. Os fatores de unidade de *CS-UNID* conferem com as definições exatas
   (1 ac = 4046.8564224 m², 1 ft = 0.3048 m, 1 mi = 1.609344 km,
   1 oz = 28.349523125 g, 1 lb = 0.45359237 kg, 1 short ton = 0.90718474 t,
   1 gal EUA = 3.785411784 L).

Uso: python -I src/tools/oraculo_siscoord.py
"""
import re
from pathlib import Path

LSP = Path(__file__).resolve().parents[2] / "lisps" / "SisCoord.lsp"
AGRO = Path("C:/Tecgraf/AgroCAD/Config/COORDS-pt-BR.AGROCAD")


def faixa(a, b):
    return list(range(a, b + 1))


def familia(pref, sul, norte, dois):
    f = (lambda z: f"{z:02d}") if dois else str
    return [f"{pref}{f(z)}S" for z in sul] + [f"{pref}{f(z)}N" for z in norte]


def gerados():
    """espelho de cs:embutidos."""
    return set(["LL84"]
               + familia("SIRGAS2000.UTM-", faixa(17, 25), faixa(15, 22), False)
               + familia("SA-SIR-", faixa(17, 25), faixa(15, 22), False)
               + familia("UTM84-", faixa(1, 60), faixa(1, 60), True)
               + familia("SAD69.UTM-", faixa(17, 25), faixa(18, 22), False)
               + familia("Corrego.UTM-", faixa(21, 25), [], False))


EXATOS = {  # unidade: fator a partir do SI usado na .lsp
    "ac": 1 / 4046.8564224, "ft": 1 / 0.3048, "mi": 1 / 1.609344, "oz": 1 / 28.349523125,
    "lb": 1 / 0.45359237, "ton (EUA)": 1 / 0.90718474, "gal (EUA)": 1 / 3.785411784,
}

if __name__ == "__main__":
    ok = True
    g = gerados()
    if AGRO.exists():
        txt = AGRO.read_bytes().decode("cp1252")
        agro = set(re.findall(r'\(list "[^"]*" "([^"]+)"\)', txt))
        falta = sorted(agro - g)
        print(f"1. gerados={len(g)}  AgroCAD={len(agro)}  faltando={falta or 'nenhum'}")
        ok &= not falta
    else:
        print(f"1. gerados={len(g)} (AgroCAD não instalado: cobertura não verificada)")
    src = LSP.read_bytes().decode("cp1252", errors="replace")
    pior = 0.0
    for nome, fat in EXATOS.items():
        m = re.search(r'\("' + re.escape(nome) + r'" ([0-9.eE+-]+)\)', src)
        assert m, nome
        pior = max(pior, abs(float(m.group(1)) - fat) / fat)
    print(f"2. fatores de unidade: erro relativo máx. = {pior:.1e}")
    ok &= pior < 1e-12
    print("OK" if ok else "FALHOU")
