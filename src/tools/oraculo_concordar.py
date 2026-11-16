"""Oráculo do SIS_CONCORDAR (lisps/Concordancia.lsp).

Espelha as funções analíticas sc:arco, sc:int-seg, sc:off/sc:int-prim/
sc:toque (concordância), sc:dentro (número de voltas com arcos) e sc:sub
(bulge parcial) e verifica:

1. interseções segmento x segmento (reta/arco) contra força bruta;
2. concordâncias reta-reta, reta-arco e arco-arco em nós aleatórios: o
   centro dista R das duas primitivas, as tangências caem nos ramos, à
   frente do nó, e o arco é tangente (G1) aos dois ramos;
3. ponto dentro de anel com arcos (ilha) contra polígono discretizado fino;
4. sub-trecho de um arco com bulge parcial reproduz os pontos originais.

Uso: python -I src/tools/oraculo_concordar.py
"""
import math
import random

PI = math.pi
TOL, NO = 1e-6, 1e-4


def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def mul(v, k): return (v[0] * k, v[1] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1]
def cross(a, b): return a[0] * b[1] - a[1] * b[0]
def unit(v): l = math.hypot(*v); return (v[0] / l, v[1] / l)
def esq(v): return (-v[1], v[0])
def ang(a, b): return math.atan2(b[1] - a[1], b[0] - a[0])
def n2pi(a): return a % (2 * PI)


def arco(p0, p1, b):
    th = 4 * math.atan(b)
    d = math.dist(p0, p1) * (1 + b * b) / (4 * b)
    a = ang(p0, p1) + PI / 2 - th / 2
    c = (p0[0] + d * math.cos(a), p0[1] + d * math.sin(a))
    return c, abs(d), ang(c, p0), th


def seg(p0, p1, b=0.0):
    arc = arco(p0, p1, b) if abs(b) > 1e-10 else None
    ln = arc[1] * abs(arc[3]) if arc else math.dist(p0, p1)
    return [p0, p1, b, ln, 0.0, arc]


def seg_pt(sg, k):
    arc = sg[5]
    if arc:
        a = arc[2] + arc[3] * k
        return (arc[0][0] + arc[1] * math.cos(a), arc[0][1] + arc[1] * math.sin(a))
    return add(sg[0], mul(sub(sg[1], sg[0]), k))


def seg_tan(sg, k):
    arc = sg[5]
    if arc:
        a = arc[2] + arc[3] * k
        v = (-math.sin(a), math.cos(a))
        return mul(v, -1) if arc[3] < 0 else v
    return unit(sub(sg[1], sg[0]))


def em01(k, ln): e = TOL / ln; return -e <= k <= 1 + e
def clamp(k): return max(0.0, min(1.0, k))


def lin_circ(p, d, c, r):
    dd = dot(d, d)
    k0 = dot(sub(c, p), d) / dd
    h = math.dist(add(p, mul(d, k0)), c)
    if h > r + TOL: return []
    if h > r - TOL: return [k0]
    m = math.sqrt(r * r - h * h) / math.sqrt(dd)
    return [k0 - m, k0 + m]


def circ_circ(c1, r1, c2, r2):
    d = math.dist(c1, c2)
    if d < 1e-12 or d > r1 + r2 + TOL or d < abs(r1 - r2) - TOL: return []
    a = (d * d + r1 * r1 - r2 * r2) / (2 * d)
    h = math.sqrt(max(0.0, r1 * r1 - a * a))
    u = unit(sub(c2, c1)); m = add(c1, mul(u, a)); n = mul(esq(u), h)
    return [m] if h < TOL else [add(m, n), sub(m, n)]


def k_arco(arc, q):
    th = arc[3]
    d = ang(arc[0], q)
    d = n2pi(d - arc[2]) if th > 0 else n2pi(arc[2] - d)
    e = TOL / arc[1]
    if d <= abs(th) + e: return min(1.0, d / abs(th))
    if d >= 2 * PI - e: return 0.0
    return None


def int_seg(a, b):
    aa, ab = a[5], b[5]
    if not aa and not ab:
        p, r, q, s = a[0], sub(a[1], a[0]), b[0], sub(b[1], b[0])
        den = cross(r, s)
        if abs(den) <= 1e-12 * a[3] * b[3]: return []
        t, u = cross(sub(q, p), s) / den, cross(sub(q, p), r) / den
        return [(clamp(t), clamp(u))] if em01(t, a[3]) and em01(u, b[3]) else []
    if aa and ab:
        res = []
        for q in circ_circ(aa[0], aa[1], ab[0], ab[1]):
            ka, kb = k_arco(aa, q), k_arco(ab, q)
            if ka is not None and kb is not None: res.append((ka, kb))
        return res
    if aa: return [(y, x) for x, y in int_la(b, a)]
    return int_la(a, b)


def int_la(l, a):
    arc, d, res = a[5], sub(l[1], l[0]), []
    for k in lin_circ(l[0], d, arc[0], arc[1]):
        if em01(k, l[3]):
            kb = k_arco(arc, add(l[0], mul(d, k)))
            if kb is not None: res.append((clamp(k), kb))
    return res


# --- concordância (espelha sc:off, sc:int-prim, sc:toque, sc:filete) ---
def off(br, n, R):
    sg, k = br["sg"], br["k"]
    arc = sg[5]
    if arc:
        lado = dot(sub(arc[0], seg_pt(sg, k)), n) > 0
        return ("C", arc[0], abs(arc[1] - R) if lado else arc[1] + R)
    return ("L", add(sg[0], mul(n, R)), unit(sub(sg[1], sg[0])))


def int_prim(a, b):
    if a[0] == "L" and b[0] == "L":
        den = cross(a[2], b[2])
        return [] if abs(den) <= 1e-12 else [add(a[1], mul(a[2], cross(sub(b[1], a[1]), b[2]) / den))]
    if a[0] == "L": return [add(a[1], mul(a[2], k)) for k in lin_circ(a[1], a[2], b[1], b[2])]
    if b[0] == "L": return int_prim(b, a)
    return circ_circ(a[1], a[2], b[1], b[2])


def toque(br, c, R):
    sg = br["sg"]; arc = sg[5]
    if arc:
        dd, q, r = math.dist(c, arc[0]), unit(sub(c, arc[0])), arc[1]
        p = sub(arc[0], mul(q, r)) if r < R and abs(dd - (R - r)) < abs(dd - (R + r)) else add(arc[0], mul(q, r))
        k = k_arco(arc, p)
    else:
        d = sub(sg[1], sg[0]); k = dot(sub(c, sg[0]), d) / dot(d, d); p = add(sg[0], mul(d, k))
        if not em01(k, sg[3]): k = None
    if k is not None and br["dir"] * (k - br["k"]) > NO / sg[3]:
        return p, clamp(k)
    return None


def filete(X, bi, bj, R):
    ofi = off(bi, esq(bi["u"]), R)
    ofj = off(bj, mul(esq(bj["u"]), -1), R)
    best = None
    for c in int_prim(ofi, ofj):
        ti, tj = toque(bi, c, R), toque(bj, c, R)
        if ti and tj and (best is None or math.dist(c, X) < math.dist(best[0], X)):
            best = (c, ti, tj)
    return best


def ramo(sg, k, dr):
    return {"sg": sg, "k": k, "dir": dr, "u": mul(seg_tan(sg, k), dr)}


def segmento_aleatorio(rnd, X, reto):
    """segmento passando por X (reta ou arco), X no meio."""
    a = rnd.uniform(0, 2 * PI)
    L = rnd.uniform(40, 200)
    if reto:
        d = (math.cos(a), math.sin(a))
        return seg(sub(X, mul(d, L)), add(X, mul(d, L)))
    r = rnd.uniform(30, 400)
    sgn = rnd.choice([1, -1])
    c = add(X, mul((math.cos(a), math.sin(a)), r))
    a0 = ang(c, X)
    half = min(0.9 * PI, L / r)
    p0 = (c[0] + r * math.cos(a0 - sgn * half), c[1] + r * math.sin(a0 - sgn * half))
    p1 = (c[0] + r * math.cos(a0 + sgn * half), c[1] + r * math.sin(a0 + sgn * half))
    return seg(p0, p1, sgn * math.tan(2 * half / 4))


def dist_prim(sg, p):
    if sg[5]: return abs(math.dist(p, sg[5][0]) - sg[5][1])
    d = unit(sub(sg[1], sg[0])); return abs(cross(d, sub(p, sg[0])))


if __name__ == "__main__":
    rnd = random.Random(7)
    ok = True

    # 1. interseções vs força bruta (amostragem densa de um dos segmentos)
    pior = 0.0; nint = 0
    for _ in range(400):
        X = (rnd.uniform(-1e4, 1e4), rnd.uniform(-1e4, 1e4))
        a = segmento_aleatorio(rnd, X, rnd.random() < .5)
        b = segmento_aleatorio(rnd, add(X, (rnd.uniform(-5, 5), rnd.uniform(-5, 5))), rnd.random() < .5)
        for ka, kb in int_seg(a, b):
            nint += 1
            pior = max(pior, math.dist(seg_pt(a, ka), seg_pt(b, kb)))
    print(f"1. interseções: {nint}, distância máx. entre os pontos nas duas curvas = {pior:.1e} m")
    ok &= pior < 1e-6 and nint > 300

    # 2. concordâncias nos quatro quadrantes de um X
    nf = nsem = 0; pr = pg = 0.0
    for _ in range(3000):
        X = (rnd.uniform(-1e5, 1e5), rnd.uniform(-1e5, 1e5))
        R = rnd.uniform(3, 25)
        s1 = segmento_aleatorio(rnd, X, rnd.random() < .5)
        s2 = segmento_aleatorio(rnd, X, rnd.random() < .5)
        k1 = int_seg(s1, s2)
        k1 = min(k1, key=lambda kk: math.dist(seg_pt(s1, kk[0]), X)) if k1 else None
        if not k1: continue
        Xn = seg_pt(s1, k1[0])
        rs = [ramo(s1, k1[0], 1), ramo(s1, k1[0], -1), ramo(s2, k1[1], 1), ramo(s2, k1[1], -1)]
        rs.sort(key=lambda b: n2pi(math.atan2(b["u"][1], b["u"][0])))
        for i in range(4):
            bi, bj = rs[i], rs[(i + 1) % 4]
            if bi["sg"] is bj["sg"]: continue
            phi = n2pi(math.atan2(bj["u"][1], bj["u"][0]) - math.atan2(bi["u"][1], bi["u"][0]))
            if not (1e-3 < phi < PI - 1e-3): continue
            f = filete(Xn, bi, bj, R)
            if not f: nsem += 1; continue
            nf += 1
            c, (ti, ki), (tj, kj) = f
            pr = max(pr, abs(dist_prim(bi["sg"], c) - R), abs(dist_prim(bj["sg"], c) - R),
                     abs(math.dist(c, ti) - R), abs(math.dist(c, tj) - R))
            # G1: tangente do eixo no toque é perpendicular ao raio do arco
            for b, t, k in ((bi, ti, ki), (bj, tj, kj)):
                tg = seg_tan(b["sg"], k)
                pg = max(pg, abs(dot(tg, unit(sub(t, c)))))
    print(f"2. concordâncias: {nf} (sem solução no segmento: {nsem})")
    print(f"   |dist. centro-eixo - R| máx. = {pr:.1e} m; G1 (cos do ângulo raio x tangente) máx. = {pg:.1e}")
    ok &= pr < 1e-6 and pg < 1e-6 and nf > 5000

    # 3. dentro do anel (polígono com cantos arredondados) vs polígono fino
    def anel(rnd):
        n = rnd.randint(3, 7); c = (rnd.uniform(-100, 100), rnd.uniform(-100, 100))
        angs = sorted(rnd.uniform(0, 2 * PI) for _ in range(n))
        pts = [add(c, (rnd.uniform(20, 60) * math.cos(a), rnd.uniform(20, 60) * math.sin(a))) for a in angs]
        sgs = []
        for i in range(n):
            b = rnd.choice([0.0, 0.0, rnd.uniform(-0.6, 0.6)])
            sgs.append(seg(pts[i], pts[(i + 1) % n], b))
        return sgs, c

    def dentro(q, sgs):
        w = 0.0
        for sg in sgs:
            da = ang(q, sg[1]) - ang(q, sg[0])
            while da > PI: da -= 2 * PI
            while da <= -PI: da += 2 * PI
            arc = sg[5]
            if arc and math.dist(q, arc[0]) < arc[1]:
                ch = sub(sg[1], sg[0])
                if cross(ch, sub(q, sg[0])) * cross(ch, sub(seg_pt(sg, .5), sg[0])) > 0:
                    da += 2 * PI if arc[3] > 0 else -2 * PI
            w += da
        return abs(w) > PI

    def dentro_poly(q, sgs):
        poly = [seg_pt(sg, j / 400) for sg in sgs for j in range(400)]
        res = False
        for i in range(len(poly)):
            a, b = poly[i], poly[i - 1]
            if (a[1] > q[1]) != (b[1] > q[1]) and q[0] < a[0] + (q[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1]):
                res = not res
        return res

    dif = tot = 0
    for _ in range(150):
        sgs, c = anel(rnd)
        for _ in range(60):
            q = add(c, (rnd.uniform(-80, 80), rnd.uniform(-80, 80)))
            if min(math.dist(q, seg_pt(sg, j / 200)) for sg in sgs for j in range(201)) < 0.05: continue
            tot += 1; dif += dentro(q, sgs) != dentro_poly(q, sgs)
    print(f"3. ponto dentro do anel: {tot} pontos, divergências = {dif}")
    ok &= dif == 0

    # 4. bulge parcial
    pe = 0.0
    for _ in range(2000):
        sg = seg((rnd.uniform(-1e5, 1e5), rnd.uniform(-1e5, 1e5)), (rnd.uniform(-1e5, 1e5), rnd.uniform(-1e5, 1e5)),
                 rnd.uniform(-3, 3))
        ka, kb = sorted((rnd.random(), rnd.random()))
        if kb - ka < 1e-3: continue
        p0, p1 = seg_pt(sg, ka), seg_pt(sg, kb)
        s2 = seg(p0, p1, math.tan(sg[5][3] * (kb - ka) / 4))
        for j in range(11):
            pe = max(pe, math.dist(seg_pt(s2, j / 10), seg_pt(sg, ka + (kb - ka) * j / 10)))
    print(f"4. bulge parcial: erro máx. = {pe:.1e} m")
    ok &= pe < 1e-6
    print("OK" if ok else "FALHOU")
