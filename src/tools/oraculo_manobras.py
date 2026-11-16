"""Oráculo do MANOBRAS (GOTUR).

Espelha mn:manobra, mn:ordem-passo, mn:ordem-13524 e mn:ordem-caracol da
lisps/Manobras.lsp e verifica:

1. manobra U (s >= 2R) e ômega (s < 2R), com pontas desencontradas e rumo
   qualquer: começa em P com o rumo h, termina em Q com o rumo -h
   (continuidade de tangente G1), todos os arcos com raio R, e a
   profundidade além da ponta mais avançada = R (U) ou h + R (ômega);
2. ordens: cada linha visitada exatamente uma vez; 1-3-5-2-4 reproduz o
   padrão; no caracol, toda manobra DENTRO de um bloco tem s >= 2R (só U).

Uso: python -I src/tools/oraculo_manobras.py
"""
import math
import random

PI = math.pi


def manobra(p, h, q, r):
    dir_ = (h[1], -h[0])
    v = (q[0] - p[0], q[1] - p[1])
    f = v[0] * h[0] + v[1] * h[1]
    l = v[0] * dir_[0] + v[1] * dir_[1]
    sg = -1.0 if l < 0 else 1.0
    s = abs(l)
    p1 = (p[0] + h[0] * max(f, 0), p[1] + h[1] * max(f, 0))
    if s >= 2 * r:
        loc = [(0, 0), (r, r), (s - r, r), (s, 0)]
        bl = [-math.tan(PI / 8), 0.0, -math.tan(PI / 8)]
        hgt = 0.0
    else:
        hgt = math.sqrt(max(0.0, 4 * r * r - (s / 2 + r) ** 2))
        be = math.atan2(hgt, s / 2 + r)
        loc = [(0, 0), (-r + r * math.cos(be), r * math.sin(be)),
               (s + r - r * math.cos(be), r * math.sin(be)), (s, 0)]
        bl = [math.tan(be / 4), -math.tan((PI + 2 * be) / 4), math.tan(be / 4)]
    pts = [(p1[0] + dir_[0] * sg * x + h[0] * y, p1[1] + dir_[1] * sg * x + h[1] * y) for x, y in loc]
    sb = [sg * b for b in bl]
    return pts, sb, r + hgt, max(f, 0)


def arco(p0, p1, b):
    th = 4 * math.atan(b)
    a = math.atan2(p1[1] - p0[1], p1[0] - p0[0]) + (PI / 2 - th / 2)
    d = math.dist(p0, p1) * (1 + b * b) / (4 * b)
    c = (p0[0] + d * math.cos(a), p0[1] + d * math.sin(a))
    return c, abs(d), th


def tang(p0, p1, b, ini):
    a = math.atan2(p1[1] - p0[1], p1[0] - p0[0]) + (-2 if ini else 2) * math.atan(b)
    return (math.cos(a), math.sin(a))


def angdif(u, v):
    return abs(math.atan2(u[0] * v[1] - u[1] * v[0], u[0] * v[0] + u[1] * v[1]))


def faixa(a, b):
    return list(range(a, b))


def ordem_passo(n, p):
    return [[i for g in range(p) for i in range(n) if i % p == g]]


def ordem_13524(n):
    res = []
    for b in range(0, n, 5):
        blk = faixa(b, min(n, b + 5))
        res += [i for i in blk if (i - b) % 2 == 0] + [i for i in blk if (i - b) % 2 == 1]
    return [res]


def ordem_caracol(n, esp, r, continuo):
    k = max(1, 1 + math.ceil(2 * r / esp - 1e-6))
    res, b = [], 0
    while b < n:
        m = min(2 * k, n - b)
        kk = (m + 1) // 2
        blk = []
        for i in range(kk):
            blk.append(b + i)
            if i + kk < m:
                blk.append(b + i + kk)
        res.append(blk)
        b += m
    return [sum(res, [])] if continuo else res


if __name__ == "__main__":
    rnd = random.Random(9)
    pior_g1 = pior_r = pior_fim = pior_prof = 0.0
    nu = no = 0
    for _ in range(2000):
        r = rnd.uniform(2, 15)
        a = rnd.uniform(0, 2 * PI)
        h = (math.cos(a), math.sin(a))
        p = (rnd.uniform(-1e5, 1e5), rnd.uniform(-1e5, 1e5))
        s = rnd.uniform(0.3, 6 * r) * rnd.choice([1, -1])
        f = rnd.uniform(-20, 20)
        right = (h[1], -h[0])
        q = (p[0] + h[0] * f + right[0] * s, p[1] + h[1] * f + right[1] * s)
        pts, sb, prof, ext = manobra(p, h, q, r)
        if max(f, 0) > 0:                         # prolongamento reto em P
            pts, sb = [p] + pts, [0.0] + sb
        if max(-f, 0) > 0:
            pts, sb = pts + [q], sb + [0.0]
        if abs(s) >= 2 * r:
            nu += 1
        else:
            no += 1
        pior_fim = max(pior_fim, math.dist(pts[0], p), math.dist(pts[-1], q))
        # G1 entre segmentos consecutivos e com os rumos de P e Q
        tans_in = [tang(pts[i], pts[i + 1], sb[i], True) for i in range(len(sb))]
        tans_out = [tang(pts[i], pts[i + 1], sb[i], False) for i in range(len(sb))]
        g = [angdif(h, tans_in[0]), angdif(tans_out[-1], (-h[0], -h[1]))]
        g += [angdif(tans_out[i], tans_in[i + 1]) for i in range(len(sb) - 1)]
        pior_g1 = max(pior_g1, max(g))
        for i, b in enumerate(sb):
            if abs(b) > 1e-12:
                pior_r = max(pior_r, abs(arco(pts[i], pts[i + 1], b)[1] - r) / r)
        # profundidade além da ponta mais avançada
        amostra = list(pts)                       # o arco maior passa acima dos vértices
        for i, b in enumerate(sb):
            if abs(b) > 1e-12:
                c, rr, th = arco(pts[i], pts[i + 1], b)
                a0 = math.atan2(pts[i][1] - c[1], pts[i][0] - c[0])
                amostra += [(c[0] + rr * math.cos(a0 + th * j / 2000), c[1] + rr * math.sin(a0 + th * j / 2000))
                            for j in range(2001)]
        frente = max((x - p[0]) * h[0] + (y - p[1]) * h[1] for x, y in amostra)
        pior_prof = max(pior_prof, abs(frente - max(f, 0) - prof))
    print(f"1. manobras: {nu} em U, {no} em ômega")
    print(f"   G1 (quebra de tangente máx.) = {pior_g1:.1e} rad; raio: erro rel. máx. = {pior_r:.1e}")
    print(f"   pontas: erro máx. = {pior_fim:.1e} m; profundidade: erro máx. = {pior_prof:.1e} m")
    ok = pior_g1 < 1e-8 and pior_r < 1e-9 and pior_fim < 1e-6 and pior_prof < 1e-6

    ok2 = True
    for n in range(1, 40):
        for p in range(1, 6):
            ok2 &= sorted(ordem_passo(n, p)[0]) == list(range(n))
        ok2 &= sorted(ordem_13524(n)[0]) == list(range(n))
        for cont in (True, False):
            ok2 &= sorted(sum(ordem_caracol(n, 3.0, 6.0, cont), [])) == list(range(n))
    ok2 &= ordem_13524(5)[0] == [0, 2, 4, 1, 3]
    pior_s = math.inf
    for esp in (0.9, 1.5, 3.0, 4.5):
        for r in (3.0, 6.0, 9.0):
            for blk in ordem_caracol(200, esp, r, False):
                if len(blk) == 2 * (1 + math.ceil(2 * r / esp - 1e-6)):     # bloco completo
                    for a, b in zip(blk, blk[1:]):
                        pior_s = min(pior_s, abs(b - a) * esp / (2 * r))
    print(f"2. ordens: cada linha uma vez = {ok2}; caracol: menor s/(2R) dentro do bloco = {pior_s:.3f}")
    ok2 &= pior_s >= 1 - 1e-9
    print("OK" if ok and ok2 else "FALHOU")
