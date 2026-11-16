"""Oráculo do DESVIAOBS (GOOBS) - v2: folga exata = Afastamento.

Regra da lisps/Obstaculos.lsp (v2):

  M      = folga do contorno antes do deslocamento
           círculo de raio ro : max(A, R - ro)  (contorno de raio ro + M >= R)
           polilinha          : max(A, R)       (cantos com raio >= R)
  desl   = M - A  (deslocamento do contorno PARA LONGE do lado do desvio)
  contorno da linha i = obstáculo dilatado de M + d_i, fechado por R e
                        transladado de -desl·w (w = lado do desvio),
                        d_i = |y_top - y_i|           (contornos aninhados)
  transição: centro = (linha deslocada de R) ∩ (contorno dilatado de R)

Do lado do desvio, a folga da 1ª linha é EXATAMENTE A (antes era max(A, R)):
cada disco B(p, A) do obstáculo dilatado cabe em B(p - desl·w, M), então o
contorno transladado contém a folga A e toca nela na direção w.

Verifica (obstáculo circular, linhas horizontais, desvio por cima):
1. G1 nas 4 junções;
2. raio de curvatura >= R em todo o caminho;
3. folga mínima do caminho ao obstáculo (amostrando os arcos): >= A sempre e
   = A na 1ª linha;
4. aninhamento: no topo, os caminhos vizinhos distam exatamente e;
5. contorno de polígono convexo aleatório: folga mínima = A na direção w e
   >= A em todo o contorno.

Uso: python -I src/tools/oraculo_desviaobs.py
"""
import math
import random


def caminho(y, ro, rc, oy, R):
    """desvio por cima da linha y em volta do círculo (0, oy) de raio rc."""
    yc = y + R - oy                               # linha deslocada de R, relativa ao centro
    d = rc + R
    if abs(yc) >= d:
        return None
    xc = math.sqrt(d * d - yc * yc)
    cin, cout = (-xc, yc + oy), (xc, yc + oy)
    tli, tlo = (-xc, y), (xc, y)
    k = rc / d
    tci, tco = (-xc * k, yc * k + oy), (xc * k, yc * k + oy)
    return cin, cout, tli, tlo, tci, tco


def tangente_circulo(c, p, ccw):
    vx, vy = p[0] - c[0], p[1] - c[1]
    t = (-vy, vx) if ccw else (vy, -vx)
    n = math.hypot(*t)
    return (t[0] / n, t[1] / n)


def ang(a, b):
    return abs(math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1]))


def arco_pts(c, p, q, ccw, n=400):
    a0 = math.atan2(p[1] - c[1], p[0] - c[0])
    a1 = math.atan2(q[1] - c[1], q[0] - c[0])
    s = (a1 - a0) % (2 * math.pi) if ccw else -((a0 - a1) % (2 * math.pi))
    r = math.dist(c, p)
    return [(c[0] + r * math.cos(a0 + s * j / n), c[1] + r * math.sin(a0 + s * j / n)) for j in range(n + 1)]


def dist_seg(p, a, b):
    ab = (b[0] - a[0], b[1] - a[1])
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / (ab[0] ** 2 + ab[1] ** 2)))
    return math.dist(p, (a[0] + ab[0] * t, a[1] + ab[1] * t))


def hull(pts):
    pts = sorted(set(pts))
    def cr(o, a, b): return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cr(lo[-2], lo[-1], p) <= 0: lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cr(up[-2], up[-1], p) <= 0: up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


if __name__ == "__main__":
    rnd = random.Random(5)
    pior_g1 = pior_folga = pior_folga1 = pior_esp = 0.0
    raio_ok = True
    casos = 0
    for _ in range(300):
        R, A, e, ro = rnd.uniform(3, 12), rnd.uniform(0.0, 6), rnd.uniform(1.5, 4), rnd.uniform(0.3, 20)
        M = max(A, R - ro)
        desl = M - A
        ys = [k * e for k in range(-20, 21)]
        cruz = [y for y in ys if abs(y) < ro + A]  # cruzam a folga A
        if not cruz:
            continue
        ytop = max(cruz)
        topos = []
        for i, y in enumerate(sorted(cruz, reverse=True)):
            rc = ro + M + (ytop - y)                # contorno (círculo) da linha
            oy = -desl                              # transladado para longe (para baixo)
            r = caminho(y, ro, rc, oy, R)
            if r is None:
                continue
            casos += 1
            cin, cout, tli, tlo, tci, tco = r
            oc = (0.0, oy)
            g = [ang((1, 0), tangente_circulo(cin, tli, True)),
                 ang(tangente_circulo(cin, tci, True), tangente_circulo(oc, tci, False)),
                 ang(tangente_circulo(oc, tco, False), tangente_circulo(cout, tco, True)),
                 ang(tangente_circulo(cout, tlo, True), (1, 0))]
            pior_g1 = max(pior_g1, max(g))
            raio_ok &= rc >= R - 1e-12
            pts = arco_pts(cin, tli, tci, True) + arco_pts(oc, tci, tco, False) + arco_pts(cout, tco, tlo, True)
            folga = min(math.hypot(*p) for p in pts) - ro
            pior_folga = max(pior_folga, A - folga)
            if i == 0:
                pior_folga1 = max(pior_folga1, abs(folga - A))
            topos.append(rc + oy)
        for a, b in zip(topos, topos[1:]):
            pior_esp = max(pior_esp, abs((b - a) - e))
    print(f"casos={casos}")
    print(f"1. G1 nas junções: maior quebra de tangente = {pior_g1:.1e} rad")
    print(f"2. raio mínimo respeitado: {raio_ok}")
    print(f"3. folga < Afastamento em no máx. {pior_folga:.1e} m; 1ª linha: |folga - A| máx. = {pior_folga1:.1e} m")
    print(f"4. espaçamento entre caminhos aninhados (topo): erro máx. = {pior_esp:.1e} m")
    ok = pior_g1 < 1e-9 and raio_ok and pior_folga < 1e-6 and pior_folga1 < 2e-4 and pior_esp < 1e-9

    # 5. polígono convexo: contorno = dilatação de R (cantos de raio R) transladada de -(R - A)·w
    pior5 = pior5w = 0.0
    for _ in range(200):
        R, A = rnd.uniform(3, 12), rnd.uniform(0.0, 6)
        if A >= R:
            continue
        P = hull([(rnd.uniform(-30, 30), rnd.uniform(-30, 30)) for _ in range(8)])
        w = (0.0, 1.0)
        cont = []
        n = len(P)
        for k in range(n):                          # fronteira da dilatação (cantos em arco de raio R)
            a, b, c = P[k - 1], P[k], P[(k + 1) % n]
            n1 = (a[1] - b[1], b[0] - a[0]); n1 = (-n1[0] / math.hypot(*n1), -n1[1] / math.hypot(*n1))
            n2 = (b[1] - c[1], c[0] - b[0]); n2 = (-n2[0] / math.hypot(*n2), -n2[1] / math.hypot(*n2))
            a1, a2 = math.atan2(n1[1], n1[0]), math.atan2(n2[1], n2[0])
            s = (a2 - a1) % (2 * math.pi)
            for j in range(1201):
                t = a1 + s * j / 1200
                cont.append((b[0] + R * math.cos(t), b[1] + R * math.sin(t) - (R - A)))
        dmin = min(min(dist_seg(p, P[k], P[(k + 1) % n]) for k in range(n)) for p in cont)
        topo = max(p[1] for p in cont) - max(p[1] for p in P)
        pior5 = max(pior5, A - dmin)
        pior5w = max(pior5w, abs(topo - A))
    print(f"5. polígono: folga < A em no máx. {pior5:.1e} m; folga na direção do desvio - A = {pior5w:.1e} m")
    ok = ok and pior5 < 1e-6 and pior5w < 1e-4
    print("OK" if ok else "FALHOU")
