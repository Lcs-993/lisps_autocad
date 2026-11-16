"""Oráculo do CONECTALINHAS (GOCON).

Espelha em Python cn:pontas / cn:par / cn:candidatos / cn:casa / cn:monta
da lisps/ConectaLinhas.lsp e verifica:

1. a varredura por faixa lateral encontra EXATAMENTE os mesmos pares que a
   força bruta O(n²);
2. num projeto sintético (talhões em sequência separados por carreadores,
   fileiras faltando, talhão com direção ligeiramente diferente, ruído nas
   pontas, referência girada) as cadeias formadas são as esperadas:
   cada fileira vira uma polilinha por trecho contínuo de talhões, sem
   ligar com a fileira vizinha e sem atravessar talhão onde falta a fileira.

Uso: python -I src/tools/oraculo_conectalinhas.py
"""
import math
import random

PI = math.pi


def dang(a, b):
    d = math.fmod(abs(a - b), 2 * PI)
    return 2 * PI - d if d > PI else d


def ang(p, q):
    r = math.atan2(q[1] - p[1], q[0] - p[0])
    return r if r >= 0 else r + 2 * PI


def pontas(linhas):
    res = []
    for i, (p, q) in enumerate(linhas):
        res.append((2 * i, p, ang(p, q) + PI))       # início: para fora = contra a linha
        res.append((2 * i + 1, q, ang(p, q)))
    return res


def par(a, b, amax, meia, dmax):
    if a[0] // 2 == b[0] // 2:
        return None
    l = math.dist(a[1], b[1])
    if l > dmax or dang(a[2], PI + b[2]) > amax:
        return None
    if l < 1e-6:
        return 0.0
    av = ang(a[1], b[1])
    if (dang(a[2], av) <= amax and dang(b[2], av + PI) <= amax
            and l * abs(math.sin(av - a[2])) <= meia and l * abs(math.sin(av - b[2])) <= meia):
        return l
    return None


def dominante(linhas):
    c = s = 0.0
    for p, q in linhas:
        a, l = ang(p, q), math.dist(p, q)
        c += l * math.cos(2 * a)
        s += l * math.sin(2 * a)
    return math.atan2(s, c) / 2


def candidatos_varredura(pts, th0, amax, meia, dmax):
    ux, uy = math.cos(th0), math.sin(th0)
    fmax = max(min(dang(p[2], th0), PI - dang(p[2], th0)) for p in pts)
    w = 1e-6 + dmax * math.sin(min(PI / 2, fmax + amax))
    ps = sorted(((p[1][1] * ux - p[1][0] * uy, p) for p in pts), key=lambda t: (t[0], t[1][0]))
    res, testes = [], 0
    for i in range(len(ps)):
        j = i + 1
        while j < len(ps) and ps[j][0] - ps[i][0] <= w:
            testes += 1
            l = par(ps[i][1], ps[j][1], amax, meia, dmax)
            if l is not None:
                res.append((l, ps[i][1][0], ps[j][1][0]))
            j += 1
    return sorted(res), testes


def candidatos_bruto(pts, amax, meia, dmax):
    res = []
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            l = par(pts[i], pts[j], amax, meia, dmax)
            if l is not None:
                a, b = sorted((pts[i][0], pts[j][0]))
                res.append((l, a, b))
    return sorted(res)


def casa(cands, nlin):
    outra = {k: k ^ 1 for k in range(2 * nlin)}
    usado, lig = set(), {}
    for _, a, b in cands:
        if a in usado or b in usado or outra[a] == b:
            continue
        oa, ob = outra[a], outra[b]
        outra[oa], outra[ob] = ob, oa
        usado |= {a, b}
        lig[a], lig[b] = b, a
    return lig


def cadeias(nlin, lig):
    visit, res = set(), []
    for i in range(nlin):
        if i in visit or (2 * i in lig and 2 * i + 1 in lig):
            continue
        e = 2 * i + 1 if 2 * i in lig else 2 * i
        ch = []
        while e is not None:
            visit.add(e // 2)
            ch.append(e // 2)
            e = lig.get(e ^ 1)
        res.append(ch)
    assert len(visit) == nlin, "linha fora de cadeia (ciclo?)"
    return res


def projeto(seed=3):
    """3 talhões em sequência ao longo da fileira; carreadores de 8 m."""
    rnd = random.Random(seed)
    giro = math.radians(23)
    esp, nfil = 1.5, 60
    # desvio pequeno (°): as pontas derivam < meio espaçamento, como em fileiras
    # traçadas a partir de referências quase paralelas
    talhoes = [(0.0, 180.0, 0.0), (188.0, 420.0, 0.25), (428.0, 600.0, -0.2)]  # x0, x1, desvio
    faltam = {(1, 10), (1, 11), (2, 30)}       # (talhão, fileira) sem linha
    linhas, rotulo = [], []
    for t, (x0, x1, dv) in enumerate(talhoes):
        a = math.radians(dv)
        for f in range(nfil):
            if (t, f) in faltam:
                continue
            y = f * esp
            # fileira do talhão: reta pelo centro do talhão com pequeno desvio
            xc = (x0 + x1) / 2
            p = (x0, y + (x0 - xc) * math.tan(a) + rnd.uniform(-0.05, 0.05))
            q = (x1, y + (x1 - xc) * math.tan(a) + rnd.uniform(-0.05, 0.05))
            if rnd.random() < 0.5:
                p, q = q, p                      # sentido de desenho aleatório
            rot = lambda r: (r[0] * math.cos(giro) - r[1] * math.sin(giro),
                             r[0] * math.sin(giro) + r[1] * math.cos(giro))
            linhas.append((rot(p), rot(q)))
            rotulo.append((t, f))
    return linhas, rotulo, nfil, faltam


def esperado(rotulo, nfil, faltam):
    exp = set()
    for f in range(nfil):
        trecho = []
        for t in range(3):
            if (t, f) in faltam:
                if trecho:
                    exp.add(tuple(trecho))
                trecho = []
            else:
                trecho.append((t, f))
        if trecho:
            exp.add(tuple(trecho))
    return exp


if __name__ == "__main__":
    amax, meia, dmax = math.radians(15), 0.75, 30.0
    linhas, rotulo, nfil, faltam = projeto()
    pts = pontas(linhas)
    th0 = dominante(linhas)
    cv, testes = candidatos_varredura(pts, th0, amax, meia, dmax)
    cb = candidatos_bruto(pts, amax, meia, dmax)
    norm = lambda cs: sorted((round(l, 9), min(a, b), max(a, b)) for l, a, b in cs)
    ok1 = norm(cv) == norm(cb)
    n = len(pts)
    print(f"pontas={n}  pares testados: varredura={testes}  força bruta={n * (n - 1) // 2}")
    print(f"candidatos iguais à força bruta: {ok1} ({len(cv)} pares)")
    cads = cadeias(len(linhas), casa(sorted(cv), len(linhas)))
    obtido = {tuple(sorted(rotulo[i] for i in ch)) for ch in cads}
    exp = esperado(rotulo, nfil, faltam)
    ok2 = obtido == exp
    print(f"linhas={len(linhas)} -> polilinhas={len(cads)} (esperado {len(exp)}); cadeias corretas: {ok2}")
    if not ok2:
        print("faltando:", sorted(exp - obtido)[:5], "\nsobrando:", sorted(obtido - exp)[:5])
    print("OK" if ok1 and ok2 else "FALHOU")
