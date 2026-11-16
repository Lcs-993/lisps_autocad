"""Oráculo das partes de cálculo da Classifica.lsp (CLA_*).

1. cl:rumo  - azimute (graus do norte, horário) x atan2 de referência;
2. cl:dentro - ponto em polígono (pares/ímpares) x número de voltas, em
   polígonos aleatórios (côncavos) e pontos aleatórios;
3. cl:area  - shoelace x área de polígonos regulares conhecida;
4. cl:parte - divisão de um código único em CLIENTE/FAZENDA/TALHÃO pelo
   número de caracteres (0 = restante) x fatiamento de referência.

Uso: python -I src/tools/oraculo_classifica.py
"""
import math
import random


def rumo(p0, p1):                                  # espelho de cl:rumo
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0]) % (2 * math.pi)   # angle do AutoLISP: [0, 2pi)
    a = 90.0 - math.degrees(ang)
    while a < 0:
        a += 360
    while a >= 360:
        a -= 360
    return a


def dentro(p, pol):                                # espelho de cl:dentro
    x, y = p
    d = False
    for a, b in zip(pol, pol[1:] + pol[:1]):
        if (a[1] > y) != (b[1] > y) and x < a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]):
            d = not d
    return d


def voltas(p, pol):                                # referência: número de voltas
    w = 0.0
    for a, b in zip(pol, pol[1:] + pol[:1]):
        a1 = math.atan2(a[1] - p[1], a[0] - p[0])
        b1 = math.atan2(b[1] - p[1], b[0] - p[0])
        d = b1 - a1
        while d > math.pi:
            d -= 2 * math.pi
        while d < -math.pi:
            d += 2 * math.pi
        w += d
    return abs(w) > math.pi


def area(pts):
    return abs(sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(pts, pts[1:] + pts[:1])) / 2)


def parte(s, ini, n):                              # espelho de cl:parte (1-based)
    if s is None or ini > len(s):
        return ""
    return (s[ini - 1:ini - 1 + n] if n > 0 else s[ini - 1:]).strip(" ")


if __name__ == "__main__":
    rnd = random.Random(9)
    ok = True
    # 1. rumo
    casos = [((0, 0), (0, 10), 0.0), ((0, 0), (10, 0), 90.0), ((0, 0), (0, -10), 180.0), ((0, 0), (-10, 0), 270.0),
             ((0, 0), (10, 10), 45.0), ((5, 5), (0, 0), 225.0)]
    e1 = max(abs(rumo(a, b) - r) for a, b, r in casos)
    for _ in range(2000):
        a = (rnd.uniform(-1e3, 1e3), rnd.uniform(-1e3, 1e3))
        b = (rnd.uniform(-1e3, 1e3), rnd.uniform(-1e3, 1e3))
        ref = math.degrees(math.atan2(b[0] - a[0], b[1] - a[1])) % 360   # azimute = atan2(dx, dy)
        e1 = max(e1, min(abs(rumo(a, b) - ref), 360 - abs(rumo(a, b) - ref)))
    print(f"1. rumo (norte = 0, horário): erro máx. {e1:.1e} graus")
    ok &= e1 < 1e-9
    # 2. ponto em polígono
    div = tot = 0
    for _ in range(300):
        n = rnd.randint(3, 14)
        c = (rnd.uniform(-50, 50), rnd.uniform(-50, 50))
        angs = sorted(rnd.uniform(0, 2 * math.pi) for _ in range(n))
        pol = [(c[0] + rnd.uniform(5, 40) * math.cos(t), c[1] + rnd.uniform(5, 40) * math.sin(t)) for t in angs]
        for _ in range(60):
            p = (c[0] + rnd.uniform(-45, 45), c[1] + rnd.uniform(-45, 45))
            tot += 1
            div += dentro(p, pol) != voltas(p, pol)
    print(f"2. ponto em polígono (côncavos): {tot} testes, divergências = {div}")
    ok &= div == 0
    # 3. área
    e3 = 0.0
    for n in range(3, 40):
        r = rnd.uniform(1, 100)
        pts = [(r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n)) for k in range(n)]
        e3 = max(e3, abs(area(pts) - 0.5 * n * r * r * math.sin(2 * math.pi / n)) / (r * r))
    print(f"3. área (polígonos regulares): erro relativo máx. {e3:.1e}")
    ok &= e3 < 1e-12
    # 4. código único: ex. "0105T023" com 2 + 2 caracteres -> 01 / 05 / T023
    codigos = [("0105T023", 2, 2, 0, ("01", "05", "T023")), ("ABCDEFGH", 3, 2, 2, ("ABC", "DE", "FG")),
               ("12", 2, 3, 0, ("12", "", "")), ("  X1 Y2 T3", 4, 3, 0, ("X1", "Y2", "T3"))]
    e4 = [(s, (parte(s, 1, c), parte(s, 1 + c, f), parte(s, 1 + c + f, t)), esp) for s, c, f, t, esp in codigos
          if (parte(s, 1, c), parte(s, 1 + c, f), parte(s, 1 + c + f, t)) != esp]
    print(f"4. código único dividido por caracteres: divergências = {len(e4)} {e4 or ''}")
    ok &= not e4
    print("OK" if ok else "FALHOU")
