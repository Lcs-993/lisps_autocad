"""Oráculo do SIMPLIFICAPL (SMP) e do SEGMENTARCOS (AR2RE) - lisps/Simplifica.lsp.

Espelha a lógica da LISP e verifica contra referências independentes:

SIMPLIFICAPL
 1. DP iterativo (pilha de trechos = ponteiro + contagem) == DP recursivo
    clássico, vértice a vértice (polilinhas 2D/3D aleatórias);
 2. garantia: todo vértice original fica a <= A do segmento simplificado que
    o cobre; o resultado é subsequência do original e mantém as pontas;
    o "maior desvio" informado é exatamente o desvio real;
 3. com arcos: todo segmento em arco sobrevive intacto (mesmas pontas e bulge);
    anéis fechados nunca degeneram (>= 3 vértices sem arcos);
 4. 200 mil vértices sem recursão.

SEGMENTARCOS
 5. arco do bulge: p0 e p1 no círculo, ponto médio do arco = meio da corda +
    flecha b.c/2 para a DIREITA de p0->p1 (b > 0, anti-horário), fim em p1;
 6. 'FLECHA: flecha real de cada corda (amostrada) <= tolerância e n mínimo
    (n-1 cordas violaria); 'MEDIDA: arco de cada corda <= medida, n mínimo;
 7. polilinha segmentada: vértices sobre os arcos, pontas originais
    preservadas, larguras contínuas.

Uso: python -I src/tools/oraculo_simplifica.py
"""
import math
import random
import sys


# ---------------------------------------------------------------- geometria
def z(p):
    return p[2] if len(p) > 2 else 0.0


def dseg(p, a, b):
    u = (b[0] - a[0], b[1] - a[1], z(b) - z(a))
    v = [p[0] - a[0], p[1] - a[1], z(p) - z(a)]
    l2 = u[0] ** 2 + u[1] ** 2 + u[2] ** 2
    if l2 > 1e-24:
        k = max(0.0, min(1.0, (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]) / l2))
        v = [v[i] - k * u[i] for i in range(3)]
    return math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)


def arco_p(b):
    return abs(b) > 1e-12


# ------------------------------------------------------ espelho da LISP (DP)
def dp_lisp(recs, tol):
    """sp:dp - pilha de (início, n); devolve (mantidos, maior desvio)."""
    lim = tol + 1e-9
    dout = 0.0
    out = []
    pilha = [(0, len(recs))]
    while pilha:
        ini, n = pilha.pop()
        if n <= 2:
            out.append(recs[ini])
            continue
        a, b = recs[ini][0], recs[ini + n - 1][0]
        dmax, imax = -1.0, None
        for i in range(1, n - 1):
            d = dseg(recs[ini + i][0], a, b)
            if d > dmax:
                dmax, imax = d, i
        if dmax > lim:
            pilha.append((ini + imax, n - imax))      # direita fica embaixo
            pilha.append((ini, imax + 1))             # esquerda sai primeiro
        else:
            out.append(recs[ini])
            dout = max(dout, dmax)
    out.append(recs[-1])
    return out, dout


def dp_recursivo(pts, tol, i=0, j=None):
    """referência: Douglas-Peucker clássico (índices mantidos)."""
    if j is None:
        j = len(pts) - 1
    if j - i < 2:
        return [i, j]
    dmax, k = -1.0, None
    for m in range(i + 1, j):
        d = dseg(pts[m], pts[i], pts[j])
        if d > dmax:
            dmax, k = d, m
    if dmax > tol + 1e-9:
        return dp_recursivo(pts, tol, i, k)[:-1] + dp_recursivo(pts, tol, k, j)
    return [i, j]


def simplifica_recs(recs, fech, tol):
    """sp:simplifica-recs."""
    n = len(recs)
    bs = [r[3] for r in recs]
    ant = ([bs[-1]] + bs[:-1]) if fech else ([0.0] + bs[:-1])
    if not fech:
        bs = bs[:-1] + [0.0]
    fix = [arco_p(bs[i]) or arco_p(ant[i]) or (not fech and i in (0, n - 1)) for i in range(n)]
    if not any(fix):
        p0 = recs[0][0]
        k = max(range(n), key=lambda i: (math.dist(recs[i][0][:2], p0[:2]) if len(p0) == 2
                                         else math.dist(recs[i][0], p0), -i))
        fix = [i in (0, k) for i in range(n)]
    pares = list(zip(fix, recs))
    if fech:
        k = fix.index(True)
        pares = pares[k:] + pares[:k]
        pares.append(pares[0])
    run = [pares[0][1]]
    res, dout = [], 0.0
    for f, r in pares[1:]:
        run.append(r)
        if f:
            kept, d = dp_lisp(run, tol)
            res += kept[:-1]
            dout = max(dout, d)
            run = [r]
    if not fech:
        res += run
    if fech and len(res) < 3 and not any(arco_p(r[3]) for r in res):
        return recs, 0.0
    return res, dout


# --------------------------------------------------- espelho da LISP (arcos)
def arco_geo(p0, p1, b):
    c = math.dist(p0[:2], p1[:2])
    ux, uy = (p1[0] - p0[0]) / c, (p1[1] - p0[1]) / c
    h = c * (1 - b * b) / (4 * b)
    cen = ((p0[0] + p1[0]) / 2 - h * uy, (p0[1] + p1[1]) / 2 + h * ux)
    return cen, c * (1 + b * b) / (4 * abs(b)), math.atan2(p0[1] - cen[1], p0[0] - cen[0]), 4 * math.atan(b)


def ceil_lisp(x):
    f = int(x)
    return max(1, f + 1 if x > f + 1e-9 else f)


def n_arco(r, th, modo, val):
    th = abs(th)
    if modo == "MEDIDA":
        x = r * th / val
    else:
        x = 0.0 if val >= 2 * r else th / (2 * math.acos(1 - val / r))
    return ceil_lisp(min(x, 10000.0))


def ponto_arco(geo, k, n, pz):
    a = geo[2] + geo[3] * k / n
    q = (geo[0][0] + geo[1] * math.cos(a), geo[0][1] + geo[1] * math.sin(a))
    return q + (pz[2],) if len(pz) > 2 else q


def segmenta_recs(recs, fech, modo, val):
    prox = [r[0] for r in recs[1:]] + [recs[0][0] if fech else None]
    res, na = [], 0
    for r, q in zip(recs, prox):
        if q is not None and arco_p(r[3]) and math.dist(r[0][:2], q[:2]) > 1e-9:
            geo = arco_geo(r[0], q, r[3])
            m = n_arco(geo[1], geo[3], modo, val)
            sw, dw = r[1], (r[2] - r[1]) / m
            na += 1
            for k in range(m):
                res.append((r[0] if k == 0 else ponto_arco(geo, k, m, r[0]), sw + dw * k, sw + dw * (k + 1), 0.0))
        else:
            res.append(r)
    return res, na


# ------------------------------------------------------------- geradores
def caminho(rnd, n, d3=False):
    x = y = zz = 0.0
    ang = 0.0
    pts = []
    for _ in range(n):
        ang += rnd.gauss(0, 0.4)
        passo = rnd.uniform(0.05, 3.0)
        x += passo * math.cos(ang)
        y += passo * math.sin(ang)
        zz += rnd.gauss(0, 0.2)
        pts.append((x, y, zz) if d3 else (x, y))
        if rnd.random() < 0.05:
            pts.append(tuple(list(pts[-1])))              # vértice repetido (outro objeto)
    return pts


def desvio_real(orig, kept_pts):
    """maior distância de um vértice original ao segmento simplificado que o cobre."""
    pos = []
    j = 0
    for i, p in enumerate(orig):
        if j < len(kept_pts) and orig[i] is kept_pts[j]:
            pos.append(i)
            j += 1
    assert j == len(kept_pts), "resultado não é subsequência"
    pior = 0.0
    for a, b in zip(pos, pos[1:]):
        for m in range(a + 1, b):
            pior = max(pior, dseg(orig[m], orig[a], orig[b]))
    return pior, pos


if __name__ == "__main__":
    rnd = random.Random(11)
    ok = True

    # 1-2. DP iterativo == recursivo; garantia de desvio; desvio informado
    iguais = casos = 0
    pior_exc = pior_info = 0.0
    for _ in range(400):
        d3 = rnd.random() < 0.3
        pts = caminho(rnd, rnd.randint(3, 400), d3)
        tol = rnd.choice([0.0, rnd.uniform(0.01, 2.0)])
        recs = [(p, 0.0, 0.0, 0.0) for p in pts]
        kept, dinfo = dp_lisp(recs, tol)
        ref = dp_recursivo(pts, tol)
        casos += 1
        iguais += [r[0] for r in kept] == [pts[i] for i in ref]
        real, pos = desvio_real(pts, [r[0] for r in kept])
        pior_exc = max(pior_exc, real - tol)
        pior_info = max(pior_info, abs(real - dinfo))
        ok &= pos[0] == 0 and pos[-1] == len(pts) - 1
    print(f"1. DP iterativo == recursivo: {iguais}/{casos}")
    print(f"2. desvio real - A: máx. {pior_exc:.1e} m (<= 1e-9); |informado - real| máx. {pior_info:.1e} m")
    ok &= iguais == casos and pior_exc <= 1e-9 and pior_info < 1e-12

    # 3. com arcos e fechadas
    arcos_ok = aneis_ok = True
    reducao = []
    for _ in range(300):
        fech = rnd.random() < 0.5
        pts = caminho(rnd, rnd.randint(4, 150))
        bs = [rnd.uniform(-1.5, 1.5) if rnd.random() < 0.08 else 0.0 for _ in pts]
        recs = [(p, 0.0, 0.0, b) for p, b in zip(pts, bs)]
        tol = rnd.uniform(0.0, 3.0)
        res, d = simplifica_recs(recs, fech, tol)
        n = len(recs)
        idx = {id(r): i for i, r in enumerate(recs)}
        ri = [idx[id(r)] for r in res]
        segs = n if fech else n - 1
        for i in range(segs):                              # cada arco intacto
            if arco_p(recs[i][3]):
                if i not in ri or ((i + 1) % n) not in ri:
                    arcos_ok = False
                else:
                    j = ri.index(i)
                    arcos_ok &= ri[(j + 1) % len(ri)] == (i + 1) % n
        if fech:
            aneis_ok &= len(res) >= 3 or any(arco_p(r[3]) for r in res)
        reducao.append(1 - len(res) / n)
    print(f"3. arcos preservados: {arcos_ok}; anéis sem degenerar: {aneis_ok}; "
          f"redução média {100 * sum(reducao) / len(reducao):.0f}%")
    ok &= arcos_ok and aneis_ok

    # 4. 200 mil vértices sem recursão
    sys.setrecursionlimit(200)
    big = caminho(random.Random(3), 200000)
    kept, _ = dp_lisp([(p, 0.0, 0.0, 0.0) for p in big], 0.5)
    print(f"4. 200000 vértices (limite de recursão 200): {len(big)} -> {len(kept)}")
    sys.setrecursionlimit(10000)

    # 5-6. geometria do arco e número de cordas
    pior5 = pior6 = 0.0
    minimo = True
    for _ in range(3000):
        p0 = (rnd.uniform(-100, 100), rnd.uniform(-100, 100))
        p1 = (rnd.uniform(-100, 100), rnd.uniform(-100, 100))
        b = rnd.choice([-1, 1]) * rnd.uniform(0.01, 3.0)
        c = math.dist(p0, p1)
        cen, r, a0, th = arco_geo(p0, p1, b)
        ux, uy = (p1[0] - p0[0]) / c, (p1[1] - p0[1]) / c
        s = b * c / 2                                       # flecha com sinal
        meio = ((p0[0] + p1[0]) / 2 + s * uy, (p0[1] + p1[1]) / 2 - s * ux)
        fim = ponto_arco((cen, r, a0, th), 1, 1, p0)
        pior5 = max(pior5, abs(math.dist(cen, p0) - r), abs(math.dist(cen, p1) - r),
                    math.dist(ponto_arco((cen, r, a0, th), 1, 2, p0), meio), math.dist(fim, p1))
        for modo in ("FLECHA", "MEDIDA"):
            val = rnd.uniform(0.001, 2.5 * r) if modo == "FLECHA" else rnd.uniform(0.05, r * abs(th))
            n = n_arco(r, th, modo, val)
            if n >= 10000:
                continue
            pts = [ponto_arco((cen, r, a0, th), k, n, p0) for k in range(n + 1)]
            if modo == "FLECHA":
                # flecha real amostrada: arco x corda
                for k in range(min(n, 30)):
                    for t in (0.25, 0.5, 0.75):
                        q = ponto_arco((cen, r, a0, th), k + t, n, p0)
                        pior6 = max(pior6, dseg(q, pts[k], pts[k + 1]) - val)
                if n > 1:
                    minimo &= r * (1 - math.cos(abs(th) / (2 * (n - 1)))) > val - 1e-9
            else:
                pior6 = max(pior6, r * abs(th) / n - val)
                if n > 1:
                    minimo &= r * abs(th) / (n - 1) > val - 1e-9
    print(f"5. arco do bulge: erro máx. {pior5:.1e} m (pontas no círculo, meio = flecha à direita, fim = p1)")
    print(f"6. flecha/medida excedida em no máx. {pior6:.1e} m; n mínimo: {minimo}")
    ok &= pior5 < 1e-9 and pior6 < 1e-9 and minimo

    # 7. polilinha segmentada
    pior7 = 0.0
    pontas = larg = True
    for _ in range(300):
        fech = rnd.random() < 0.5
        pts = caminho(rnd, rnd.randint(2, 40))
        pts = [p for i, p in enumerate(pts) if i == 0 or math.dist(p, pts[i - 1]) > 1e-6]
        if len(pts) < 2:
            continue
        recs = [(p, rnd.uniform(0, 1), rnd.uniform(0, 1), rnd.uniform(-2, 2) if rnd.random() < 0.5 else 0.0)
                for p in pts]
        res, na = segmenta_recs(recs, fech, "FLECHA", rnd.uniform(0.01, 0.5))
        ids = [id(r[0]) for r in res]
        pontas &= all(id(r[0]) in ids for r in recs)          # vértices originais preservados
        n = len(recs)
        for i, r in enumerate(recs):
            q = recs[(i + 1) % n][0] if (fech or i < n - 1) else None
            if q is None or not arco_p(r[3]) or math.dist(r[0], q) <= 1e-9:
                continue
            cen, rr, _, _ = arco_geo(r[0], q, r[3])
            j = ids.index(id(r[0]))
            k = j
            while True:
                pior7 = max(pior7, abs(math.dist(res[k][0], cen) - rr))
                k = (k + 1) % len(res)
                if res[k][0] is q:
                    break
                larg &= abs(res[k][1] - res[(k - 1) % len(res)][2]) < 1e-12   # largura contínua
            larg &= abs(res[(k - 1) % len(res)][2] - r[2]) < 1e-12           # termina na largura final
    print(f"7. vértices sobre o arco: erro máx. {pior7:.1e} m; pontas preservadas: {pontas}; larguras contínuas: {larg}")
    ok &= pior7 < 1e-9 and pontas and larg

    print("OK" if ok else "FALHOU")
