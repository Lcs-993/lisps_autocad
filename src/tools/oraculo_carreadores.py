"""Oráculo das partes em LISP puro do CARREADORES (GOROA).

As booleanas (REGION/ACIS) só rodam no AutoCAD; aqui se testa o que a
lisps/Carreadores.lsp calcula sozinha:

1. cr:faixa  - montagem da faixa (lado A + volta pelo lado B, bulges
   invertidos e com sinal trocado, tampas retas). Oráculo: para um eixo
   suave (raio de curvatura > largura/2) a área da faixa é exatamente
   comprimento × largura (teorema de Pappus-Guldin para faixas).
2. cr:lacos  - encadeamento das arestas explodidas em laços fechados, com
   arestas embaralhadas e invertidas. Oráculo: área e perímetro de cada
   laço reconstruído = os do laço original.
3. ARC -> bulge (cr:arestas): tan(varredura/4), com sinal pela normal.

Uso: python -I src/tools/oraculo_carreadores.py
"""
import math
import random

PI = math.pi


def polar(p, a, d):
    return (p[0] + d * math.cos(a), p[1] + d * math.sin(a))


def ang(p, q):
    return math.atan2(q[1] - p[1], q[0] - p[0])


def arco(p0, p1, b):
    """centro, raio, ângulo inicial e varredura do segmento de bulge b."""
    th = 4 * math.atan(b)
    c = polar(p0, ang(p0, p1) + (PI / 2 - th / 2), math.dist(p0, p1) * (1 + b * b) / (4 * b))
    return c, math.dist(c, p0), ang(c, p0), th


def area(pts, buls):
    """área com sinal de polígono com bulges (corda + segmentos circulares)."""
    a = 0.0
    n = len(pts)
    for i in range(n):
        p, q, b = pts[i], pts[(i + 1) % n], buls[i]
        a += (p[0] * q[1] - q[0] * p[1]) / 2
        if abs(b) > 1e-12:
            _, r, _, th = arco(p, q, b)
            a += r * r * (th - math.sin(th)) / 2      # segmento circular com sinal
    return a


def comprimento(pts, buls, fechada=False):
    s = 0.0
    m = len(pts) if fechada else len(pts) - 1
    for i in range(m):
        p, q, b = pts[i], pts[(i + 1) % len(pts)], buls[i]
        if abs(b) < 1e-12:
            s += math.dist(p, q)
        else:
            _, r, _, th = arco(p, q, b)
            s += r * abs(th)
    return s


def offset_suave(pts, buls, d):
    """offset de uma polilinha SUAVE (tangente contínua): segmentos retos
    deslocados pela normal, arcos concêntricos (mesmo bulge)."""
    out = []
    for i, p in enumerate(pts):
        if i < len(pts) - 1:
            q, b = pts[i + 1], buls[i]
            t = ang(p, q) - 2 * math.atan(b)            # tangente no início do segmento
        else:
            q0, b0 = pts[i - 1], buls[i - 1]
            t = ang(q0, p) + 2 * math.atan(b0)          # tangente no fim
        out.append(polar(p, t + PI / 2, d))
    return out, list(buls)


def faixa(pts, buls, w):
    """espelho de cr:faixa (caso aberto)."""
    a, ba = offset_suave(pts, buls, w / 2)
    b, bb = offset_suave(pts, buls, -w / 2)
    p = a + b[::-1]
    bl = ba[:-1] + [0.0] + [-x for x in bb[::-1][1:]] + [0.0]
    return p, bl


def eixo_suave(rnd):
    """reta, arco tangente, reta, arco tangente... (sem quinas)."""
    pts, buls = [(0.0, 0.0)], []
    t = rnd.uniform(0, 2 * PI)
    for _ in range(6):
        if rnd.random() < 0.5:
            q = polar(pts[-1], t, rnd.uniform(30, 120))
            buls.append(0.0)
        else:
            r, th = rnd.uniform(40, 200), rnd.uniform(-1.2, 1.2)
            c = polar(pts[-1], t + (PI / 2 if th > 0 else -PI / 2), r)
            a0 = ang(c, pts[-1])
            q = polar(c, a0 + th, r)
            buls.append(math.tan(th / 4))
            t += th
        pts.append(q)
    buls.append(0.0)
    return pts, buls


def lacos(ars, tol=1e-4):
    """espelho de cr:lacos."""
    res = []
    ars = list(ars)
    while ars:
        a = ars.pop(0)
        ini, fim, pts, bl, parou = a[0], a[1], [a[0]], [a[2]], False
        while ars and not parou and math.dist(fim, ini) > tol:
            a, ach = ars[0], None
            if math.dist(a[0], fim) < tol:
                ach = ars.pop(0)
            elif math.dist(a[1], fim) < tol:
                ach = (a[1], a[0], -a[2]); ars.pop(0)
            else:
                resto = []
                while ars and not ach:
                    a = ars.pop(0)
                    if math.dist(a[0], fim) < tol:
                        ach = a
                    elif math.dist(a[1], fim) < tol:
                        ach = (a[1], a[0], -a[2])
                    else:
                        resto.append(a)
                ars = resto + ars
            if ach:
                pts.append(ach[0]); bl.append(ach[2]); fim = ach[1]
            else:
                parou = True
        if len(pts) > 1 and math.dist(fim, ini) <= tol:
            res.append((pts, bl))
    return res


def poligono(rnd, cx, cy):
    k = rnd.randint(5, 30)
    pts = [(cx + math.cos(2 * PI * i / k) * rnd.uniform(80, 200),
            cy + math.sin(2 * PI * i / k) * rnd.uniform(80, 200)) for i in range(k)]
    buls = [rnd.choice([0.0, 0.0, rnd.uniform(-0.3, 0.3)]) for _ in range(k)]
    return pts, buls


if __name__ == "__main__":
    rnd = random.Random(11)
    ok = True

    pior = 0.0
    for _ in range(200):
        pts, buls = eixo_suave(rnd)
        w = rnd.uniform(4, 15)
        p, bl = faixa(pts, buls, w)
        esperado = comprimento(pts, buls) * w
        pior = max(pior, abs(abs(area(p, bl)) - esperado) / esperado)
    print(f"1. faixa: 200 eixos suaves, erro relativo máx. da área = {pior:.1e}")
    ok &= pior < 1e-9

    pior, nlac = 0.0, 0
    for _ in range(100):
        polis = [poligono(rnd, rnd.uniform(-2000, 2000), rnd.uniform(-2000, 2000)) for _ in range(rnd.randint(1, 4))]
        ars = []
        for pts, buls in polis:
            n = len(pts)
            for i in range(n):
                e = (pts[i], pts[(i + 1) % n], buls[i])
                ars.append(e if rnd.random() < 0.6 else (e[1], e[0], -e[2]))   # invertidas
        if rnd.random() < 0.5:
            rnd.shuffle(ars)                                                    # fora de ordem
        got = lacos(ars)
        nlac += len(got)
        if len(got) != len(polis):
            pior = 1.0
            continue
        ea = sorted(abs(area(*q)) for q in polis)
        ga = sorted(abs(area(*q)) for q in got)
        ep = sorted(comprimento(*q, fechada=True) for q in polis)
        gp = sorted(comprimento(*q, fechada=True) for q in got)
        pior = max(pior, max(abs(a - b) / a for a, b in zip(ea + ep, ga + gp)))
    print(f"2. laços: 100 casos ({nlac} laços, arestas invertidas/embaralhadas), erro máx. = {pior:.1e}")
    ok &= pior < 1e-9

    pior = 0.0
    for _ in range(500):
        c, r = (rnd.uniform(-1e6, 1e6), rnd.uniform(-1e6, 1e6)), rnd.uniform(1, 500)
        a0, a1 = rnd.uniform(0, 2 * PI), rnd.uniform(0, 2 * PI)
        s = math.fmod(a1 - a0 + 4 * PI, 2 * PI)
        b = math.tan(s / 4)
        p0, p1 = polar(c, a0, r), polar(c, a1, r)
        c2, r2, _, th = arco(p0, p1, b)
        pior = max(pior, math.dist(c, c2) / r, abs(r - r2) / r, abs(th - s))
    print(f"3. ARC -> bulge: 500 arcos, erro máx. (centro/raio/varredura) = {pior:.1e}")
    ok &= pior < 1e-6

    print("OK" if ok else "FALHOU")
