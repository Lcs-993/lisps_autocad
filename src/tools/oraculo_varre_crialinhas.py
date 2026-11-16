"""Oráculo do caminho rápido do CRIALINHAS v2.1.

Espelha em Python ln:trechos + ln:varre (mesma matemática da .lsp) e compara o
comprimento recortado de cada reta v=d com um recorte por força bruta sobre o
contorno densificado (arcos com 2000 subdivisões). Polígonos de teste com
arcos (convexos e côncavos), vértices exatamente sobre as retas e referência
em ângulo qualquer.
"""
import math
import random

PI = math.pi


def polar(p, a, d):
    return (p[0] + d * math.cos(a), p[1] + d * math.sin(a))


def ang(a, b):
    r = math.atan2(b[1] - a[1], b[0] - a[0])
    return r if r >= 0 else r + 2 * PI


def trechos(pts, bul):
    res = []
    pts = pts + [pts[0]]
    for i in range(len(pts) - 1):
        p0, p1, bu = pts[i], pts[i + 1], bul[i]
        v0, v1 = p0[1], p1[1]
        if math.dist(p0, p1) < 1e-9:
            continue
        if abs(bu) < 1e-9:
            if v0 != v1:
                res.append((min(v0, v1), max(v0, v1), 0, p0[0], v0, (p1[0] - p0[0]) / (v1 - v0)))
            continue
        th = 4 * math.atan(bu)
        c = polar(p0, ang(p0, p1) + (PI / 2 - th / 2), math.dist(p0, p1) * (1 + bu * bu) / (4 * bu))
        r = math.dist(c, p0)
        a0 = ang(c, p0)
        a1 = a0 + th
        amin, amax = min(a0, a1), max(a0, a1)
        vmin, vmax = (v0, v1) if th > 0 else (v1, v0)
        angs = [(amin, vmin)]
        x = (amin - PI / 2) / PI
        k = 1 + int(x)                      # fix = truncamento
        if amin - PI / 2 < 0:
            k = int(x)
        while (e := PI / 2 + k * PI) < amax - 1e-12:
            if e > amin + 1e-12:
                angs.append((e, c[1] + r * math.sin(e)))
            k += 1
        angs.append((amax, vmax))
        for (as_, vs), (ae, ve) in zip(angs, angs[1:]):
            if vs != ve:
                s = -1.0 if math.cos((as_ + ae) / 2) < 0 else 1.0
                res.append((min(vs, ve), max(vs, ve), 1, c[0], c[1], r, s))
    return res


def varre(trs, ds):
    hits = {}
    for tr in trs:
        for i, d in enumerate(ds):
            if tr[0] <= d < tr[1]:
                if tr[2] == 0:
                    u = tr[3] + (d - tr[4]) * tr[5]
                else:
                    u = tr[3] + tr[6] * math.sqrt(max(0.0, tr[5] ** 2 - (d - tr[4]) ** 2))
                hits.setdefault(i, []).append(u)
    out = {}
    for i, us in hits.items():
        us.sort()
        out[i] = sum(us[j + 1] - us[j] for j in range(0, len(us) - 1, 2) if us[j + 1] - us[j] > 1e-6)
    return out


def densifica(pts, bul, n=2000):
    res = []
    for i in range(len(pts)):
        p0, p1, bu = pts[i], pts[(i + 1) % len(pts)], bul[i]
        res.append(p0)
        if abs(bu) > 1e-9:
            th = 4 * math.atan(bu)
            c = polar(p0, ang(p0, p1) + (PI / 2 - th / 2), math.dist(p0, p1) * (1 + bu * bu) / (4 * bu))
            r, a0 = math.dist(c, p0), ang(c, p0)
            for j in range(1, n):
                res.append(polar(c, a0 + th * j / n, r))
    return res


def bruto(poly, d):
    xs = []
    for i in range(len(poly)):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
        if (y0 > d) != (y1 > d):
            xs.append(x0 + (d - y0) * (x1 - x0) / (y1 - y0))
    xs.sort()
    return sum(xs[j + 1] - xs[j] for j in range(0, len(xs) - 1, 2))


def local(pts, o, ang_ref):
    dx, dy = math.cos(ang_ref), math.sin(ang_ref)
    return [((p[0] - o[0]) * dx + (p[1] - o[1]) * dy, (p[1] - o[1]) * dx - (p[0] - o[0]) * dy) for p in pts]


def caso(nome, pts, bul, ang_ref=0.0, passo=3.0):
    loc = local(pts, (0.0, 0.0), ang_ref)
    trs = trechos(loc, bul)
    vmin, vmax = min(t[0] for t in trs), max(t[1] for t in trs)
    ds = [k * passo for k in range(math.floor(vmin / passo), math.ceil(vmax / passo) + 1)]
    ds += [p[1] for p in loc]                                  # retas exatamente nos vértices
    ds = sorted(set(round(d, 9) for d in ds))
    rap = varre(trs, ds)
    den = densifica(loc, bul)
    pior = 0.0
    for i, d in enumerate(ds):
        ref = bruto(den, d)
        got = rap.get(i, 0.0)
        pior = max(pior, abs(ref - got) / max(1.0, ref))
    print(f"{nome:<34} retas={len(ds):4d} trechos={len(trs):4d} erro_rel_max={pior:.2e}")
    return pior


if __name__ == "__main__":
    random.seed(7)
    piores = []
    quad = [(0, 0), (300, 0), (300, 200), (0, 200)]
    piores.append(caso("retângulo, ref horizontal", quad, [0, 0, 0, 0]))
    piores.append(caso("retângulo, ref 17°", quad, [0, 0, 0, 0], math.radians(17)))
    piores.append(caso("arcos convexos (bulge +)", quad, [0.4, 0, 0.6, 0], math.radians(5)))
    piores.append(caso("arcos côncavos (bulge -)", quad, [-0.3, 0, -0.5, 0.2], math.radians(31)))
    piores.append(caso("semicírculo + arco > 180°", [(0, 0), (200, 0)], [1.0, 1.7], math.radians(12)))
    piores.append(caso("forma L", [(0, 0), (400, 0), (400, 150), (150, 150), (150, 400), (0, 400)],
                       [0] * 6, math.radians(45)))
    for n in range(5):
        k = 40
        pts = [(math.cos(2 * PI * i / k) * random.uniform(300, 600),
                math.sin(2 * PI * i / k) * random.uniform(300, 600)) for i in range(k)]
        bul = [random.choice([0, 0, random.uniform(-0.4, 0.4)]) for _ in range(k)]
        piores.append(caso(f"aleatório estrelado #{n}", pts, bul, random.uniform(0, 2 * PI), 2.5))
    print("OK" if max(piores) < 1e-4 else "FALHOU")
