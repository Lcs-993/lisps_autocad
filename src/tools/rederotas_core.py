"""Espelho em Python do núcleo de lisps/RedeRotas.lsp (RA_VALIDAR / RA_CORRIGIR / RA_EXPORTAR).

Mesmo modelo e mesma ordem de passos da LISP, para testar o algoritmo fora do
AutoCAD (oraculo_rederotas.py). Registro do modelo:

    {"id", "h" (handle), "tipo", "fech", "pts": [(x, y, z)], "flags": set, "orig"}

Funções principais: analisa(model, X, tolQ), corrige(model, X, tolQ),
geojson(model, epsg).
"""
import math

EPS0 = 1e-6     # mesmo ponto
EPST = 1e-3     # toque (vértice sobre segmento)


# ------------------------------------------------------------------ geometria
def d2(ax, ay, bx, by):
    return math.hypot(bx - ax, by - ay)


def dist(p, q):
    return d2(p[0], p[1], q[0], q[1])


def proj(px, py, ax, ay, bx, by):
    ux, uy = bx - ax, by - ay
    l2 = ux * ux + uy * uy
    u = max(0.0, min(1.0, ((px - ax) * ux + (py - ay) * uy) / l2)) if l2 > 1e-24 else 0.0
    fx, fy = ax + u * ux, ay + u * uy
    return d2(px, py, fx, fy), u, fx, fy


def cross(ax, ay, bx, by, cx, cy):
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)


def cruza(ax, ay, bx, by, cx, cy, dx, dy):
    o1, o2 = cross(ax, ay, bx, by, cx, cy), cross(ax, ay, bx, by, dx, dy)
    o3, o4 = cross(cx, cy, dx, dy, ax, ay), cross(cx, cy, dx, dy, bx, by)
    if o1 * o2 < 0 and o3 * o4 < 0:
        return o3 / (o3 - o4)
    return None


def adjacente(i, j, n, fech):
    return abs(i - j) == 1 or (fech and n > 2 and abs(i - j) == n - 1)


def comprimento(pts, fech):
    L = sum(dist(a, b) for a, b in zip(pts, pts[1:]))
    if fech and len(pts) > 1:
        L += dist(pts[-1], pts[0])
    return L


def menor(a, b):
    """a antes de b: por x (com tolerância), depois por y - pontas normalizadas do segmento."""
    if abs(a[0] - b[0]) > EPS0:
        return a[0] < b[0]
    return a[1] < b[1]


def proximos(pts, fech):
    return pts[1:] + [pts[0] if fech else None]


def ativo(r):
    return "DEL" not in r["flags"]


# --------------------------------------------------------------- grade de pares
def pares(itens, cel, fn):
    """itens: (xmin, ymin, xmax, ymax, ...); fn(a, b) uma vez por par (célula do canto)."""
    if not itens:
        return
    x0 = min(it[0] for it in itens)
    y0 = min(it[1] for it in itens)
    cells = {}
    for it in itens:
        for cx in range(int((it[0] - x0) / cel), int((it[2] - x0) / cel) + 1):
            for cy in range(int((it[1] - y0) / cel), int((it[3] - y0) / cel) + 1):
                cells.setdefault((cx, cy), []).append(it)
    for key, g in cells.items():
        for i, a in enumerate(g):
            for b in g[i + 1:]:
                if a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]:
                    if (int((max(a[0], b[0]) - x0) / cel), int((max(a[1], b[1]) - y0) / cel)) == key:
                        fn(a, b)


class UF:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, i):
        p = self.p
        while p[i] != i:
            p[i] = p[p[i]]
            i = p[i]
        return i

    def une(self, a, b):
        x, y = self.find(a), self.find(b)
        if x != y:
            self.p[max(x, y)] = min(x, y)


# -------------------------------------------------------------------- análise
def cadeia(pts, inicio, X):
    segs = [(k, a[0], a[1], b[0], b[1]) for k, (a, b) in enumerate(zip(pts, pts[1:]))]
    if not inicio:
        segs = segs[::-1]
    res, acc = [], 0.0
    for s in segs:
        if res and acc >= X:
            break
        res.append(s)
        acc += d2(*s[1:])
    return res


def seg_perto(c, s):
    ax, ay, bx, by = c
    cx, cy, dx, dy = s[7:11]
    return (cruza(ax, ay, bx, by, cx, cy, dx, dy) is not None
            or proj(ax, ay, cx, cy, dx, dy)[0] <= EPST or proj(bx, by, cx, cy, dx, dy)[0] <= EPST
            or proj(cx, cy, ax, ay, bx, by)[0] <= EPST or proj(dx, dy, ax, ay, bx, by)[0] <= EPST)


def mesmo_pt(x, y, lst):
    return any(d2(x, y, p[0], p[1]) <= EPS0 for p in lst)


def analisa(model, X, tolQ):
    uf_v = None
    quase, cruz, tees, sob, cand = [], [], [], [], []
    vs, zeros = [], []
    for r in model:
        if not ativo(r):
            continue
        pts, fech, n = r["pts"], r["fech"], len(r["pts"])
        for k, p in enumerate(pts):
            vs.append((len(vs), p[0], p[1], r["id"], k, (not fech) and (k == 0 or k == n - 1), n, fech))
        nxt = proximos(pts, True) if (fech and len(pts) > 1) else pts[1:]
        for k, (a, b) in enumerate(zip(pts, nxt)):
            if b is not None and dist(a, b) <= EPS0:
                zeros.append((a[0], a[1], r["id"], k))
    nv = len(vs)
    uf_v = UF(nv)
    h = tolQ / 2

    def par_vv(a, b):
        va, vb = a[5], b[5]
        d = d2(va[1], va[2], vb[1], vb[2])
        if d <= EPS0:
            uf_v.une(va[0], vb[0])
        elif d >= tolQ:
            pass
        elif va[3] == vb[3] and adjacente(va[4], vb[4], va[6], va[7]):
            pass
        elif d < EPST or va[5] or vb[5]:
            quase.append((d, va, vb))

    pares([(v[1] - h, v[2] - h, v[1] + h, v[2] + h, "V", v) for v in vs], max(4 * tolQ, 1e-3), par_vv)
    cnt = [0] * nv
    for v in vs:
        cnt[uf_v.find(v[0])] += 1
    quase = [(q[0], q[1], q[2], cnt[uf_v.find(q[1][0])], cnt[uf_v.find(q[2][0])]) for q in quase
             if uf_v.find(q[1][0]) != uf_v.find(q[2][0])]

    # componentes
    nent = len(model)
    euf = UF(nent)
    for v in vs:
        euf.une(v[3], vs[uf_v.find(v[0])][3])
    elen = [0.0] * nent
    grupos = {}
    tot = 0.0
    for r in model:
        if ativo(r):
            L = comprimento(r["pts"], r["fech"])
            tot += L
            rt = euf.find(r["id"])
            elen[rt] += L
            grupos.setdefault(rt, []).append(r["id"])
    main = max(grupos, key=lambda g: elen[g]) if grupos else None
    frags = [(elen[g], ids) for g, ids in grupos.items() if g != main]

    # segmentos e sondas
    segs, probes = [], []
    base = 0
    somal, nseg = 0.0, 0
    for r in model:
        if not ativo(r):
            continue
        pts, fech, n, rid = r["pts"], r["fech"], len(r["pts"]), r["id"]
        nxt = proximos(pts, True) if (fech and n > 2) else pts[1:]
        for k, (a, b) in enumerate(zip(pts, nxt)):
            segs.append((min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]),
                         "S", rid, k, a[0], a[1], b[0], b[1], n if fech else n - 1, fech))
            somal += dist(a, b)
            nseg += 1
        if not fech and n > 1:
            for fim, vid, q, inicio in ((0, base, pts[0], True), (1, base + n - 1, pts[-1], False)):
                if cnt[uf_v.find(vid)] == 1:
                    probes.append((q[0] - X, q[1] - X, q[0] + X, q[1] + X, "P", rid, fim, q[0], q[1],
                                   cadeia(pts, inicio, X)))
        base += n

    def toque(px, py, src, dst):
        dd, u, _, _ = proj(px, py, dst[7], dst[8], dst[9], dst[10])
        if dd <= EPST:
            if d2(px, py, dst[7], dst[8]) > EPST and d2(px, py, dst[9], dst[10]) > EPST:
                tees.append((px, py, src[5], dst[5], dst[6], u))
            return True
        return False

    def sobrep(s1, s2):
        ax, ay, bx, by = s1[7:11]
        cx, cy, dx, dy = s2[7:11]
        L = d2(ax, ay, bx, by)
        if L <= EPS0:
            return
        ux, uy = (bx - ax) / L, (by - ay) / L
        if abs(ux * (cy - ay) - uy * (cx - ax)) <= EPST and abs(ux * (dy - ay) - uy * (dx - ax)) <= EPST:
            tc, td = ux * (cx - ax) + uy * (cy - ay), ux * (dx - ax) + uy * (dy - ay)
            lo, hi = max(0.0, min(tc, td)), min(L, max(tc, td))
            m = (lo + hi) / 2
            if hi - lo > EPST:
                sob.append((s1[5], s2[5], hi - lo, ax + ux * m, ay + uy * m))

    def par_ss(s1, s2):
        if s1[5] == s2[5] and adjacente(s1[6], s2[6], s1[11], s1[12]):
            return
        ax, ay, bx, by = s1[7:11]
        cx, cy, dx, dy = s2[7:11]
        toq = False
        for x in ((ax, ay, s1, s2), (bx, by, s1, s2), (cx, cy, s2, s1), (dx, dy, s2, s1)):
            if toque(*x):
                toq = True
        sobrep(s1, s2)
        if not toq:
            u = cruza(ax, ay, bx, by, cx, cy, dx, dy)
            if u is not None:
                cruz.append((ax + u * (bx - ax), ay + u * (by - ay), s1[5], s1[6], u, s2[5], s2[6],
                             cruza(cx, cy, dx, dy, ax, ay, bx, by)))

    def par_sp(s, p):
        if s[5] == p[5] and any(c[0] == s[6] for c in p[9]):
            return
        qx, qy = p[7], p[8]
        dd, u, fx, fy = proj(qx, qy, s[7], s[8], s[9], s[10])
        if EPST < dd <= X and not any(seg_perto(c[1:], s) for c in p[9]):
            cand.append((p[5], p[6], dd, qx, qy, s[5], s[6], fx, fy, s[7], s[8], s[9], s[10]))

    def par_sx(a, b):
        if a[4] == "S" and b[4] == "S":
            par_ss(a, b)
        elif a[4] == "S" and b[4] == "P":
            par_sp(a, b)
        elif a[4] == "P" and b[4] == "S":
            par_sp(b, a)

    pares(segs + probes, max(4 * X, somal / nseg if nseg else 1.0, 1e-3), par_sx)

    ptsq = [(q[1][1], q[1][2]) for q in quase] + [(q[2][1], q[2][2]) for q in quase]
    tees.sort(key=lambda t: (t[3], t[0], t[1]))
    t2, ult = [], None
    for x in tees:
        dup = ult is not None and x[3] == ult[3] and d2(x[0], x[1], ult[0], ult[1]) <= EPS0
        if not (dup or mesmo_pt(x[0], x[1], ptsq)):
            t2.append(x)
        ult = x
    tees = t2
    cand.sort(key=lambda c: (c[0], c[1], c[2]))
    pontas, ult = [], None
    for c in cand:
        if not (ult is not None and c[0] == ult[0] and c[1] == ult[1]):
            if not (mesmo_pt(c[3], c[4], ptsq) or mesmo_pt(c[3], c[4], tees)):
                pontas.append(c)
        ult = c
    agrup = {}
    for s in sob:
        k = (min(s[0], s[1]), max(s[0], s[1]))
        if k in agrup:
            agrup[k][0] += s[2]
        else:
            agrup[k] = [s[2], s[3], s[4]]
    sob2 = []
    for (ea, eb), (L, mx, my) in agrup.items():
        la = comprimento(model[ea]["pts"], model[ea]["fech"])
        lb = comprimento(model[eb]["pts"], model[eb]["fech"])
        sob2.append((ea, eb, L, mx, my, L >= min(la, lb) - EPST))
    comp = (len(grupos), (elen[main] / tot) if tot > 0 else 1.0, frags, tot)
    return {"quase": quase, "cruz": cruz, "tees": tees, "sob": sob2, "pontas": pontas,
            "zeros": zeros, "comp": comp}


def erros(model, an, naosup=()):
    """lista (tipo, x, y, id1, id2) - mesmos tipos de ra:erros (sem CRS/unidade)."""
    er = []
    for c in an["cruz"]:
        er.append(("CRUZAMENTO", c[0], c[1], c[2], c[5]))
    for t in an["tees"]:
        er.append(("T_SEM_VERTICE", t[0], t[1], t[3], t[2]))
    for p in an["pontas"]:
        er.append(("PONTA_SOLTA", p[3], p[4], p[0], p[5]))
    for q in an["quase"]:
        er.append(("QUASE_COINCIDENTE", q[1][1], q[1][2], q[1][3], q[2][3]))
    for s in an["sob"]:
        er.append(("DUPLICADA" if s[5] else "SOBREPOSTA", s[3], s[4], s[0], s[1]))
    for z in an["zeros"]:
        er.append(("SEGMENTO_ZERO", z[0], z[1], z[2], None))
    for x in naosup:
        er.append(("NAO_SUPORTADA", x["pt"][0], x["pt"][1], x["tipo"], None))
    for r in model:
        if ativo(r) and "ZVAR" in r["flags"]:
            er.append(("Z_VARIAVEL", r["pts"][0][0], r["pts"][0][1], r["id"], None))
        if ativo(r) and "ARCOS" in r["flags"]:
            er.append(("ARCOS", r["pts"][0][0], r["pts"][0][1], r["id"], None))
    for L, ids in an["comp"][2]:
        p = model[ids[0]]["pts"][0]
        er.append(("FRAGMENTO", p[0], p[1], ids[0], None))
    return er


# ------------------------------------------------------------------- correção
class Corretor:
    def __init__(self, X, tolQ):
        self.X, self.tolQ, self.log = X, tolQ, []

    def lg(self, op, r, x, y, antes="", depois=""):
        self.log.append((op, r["h"] if r else "", x, y, antes, depois))

    @staticmethod
    def limpa(pts, fech):
        res = []
        for p in pts:
            if not (res and dist(p, res[-1]) <= EPS0):
                res.append(p)
        if fech and len(res) > 1 and dist(res[0], res[-1]) <= EPS0:
            res.pop()
        return res

    def zeros(self, model):
        for r in model:
            if not ativo(r):
                continue
            p2 = self.limpa(r["pts"], r["fech"])
            if len(p2) < 2:
                self.lg("APAGAR_ENTIDADE", r, *r["pts"][0][:2])
                r["flags"].add("DEL")
            elif len(p2) < len(r["pts"]):
                self.lg("REMOVER_SEGMENTO_ZERO", r, *p2[0][:2])
                r["pts"], r["fech"] = p2, r["fech"] and len(p2) > 2
                r["flags"].add("MOD")
        return model

    @staticmethod
    def mover(model, moves):
        for r in model:
            mud = False
            novo = []
            for p in r["pts"]:
                m = next((m for m in moves if d2(p[0], p[1], m[0], m[1]) <= EPS0), None)
                if m:
                    mud = True
                    novo.append((m[2], m[3], p[2]))
                else:
                    novo.append(p)
            if mud and ativo(r):
                r["pts"] = novo
                r["flags"].add("MOD")
        return model

    def unir(self, model):
        an = analisa(model, self.X, self.tolQ)
        grupos = []
        for q in an["quase"]:
            ma, mb = (q[1][0], q[1], q[3]), (q[2][0], q[2], q[4])
            ga = next((g for g in grupos if any(m[0] == ma[0] for m in g)), None)
            gb = next((g for g in grupos if any(m[0] == mb[0] for m in g)), None)
            grupos = [g for g in grupos if g is not ga and g is not gb]
            novo = (ga if ga else [ma]) + (gb if (gb and gb is not ga) else ([] if gb else [mb]))
            grupos.append(novo)
        moves = []
        for g in grupos:
            g = sorted(g, key=lambda m: m[0])
            alvo = g[0]
            for m in g[1:]:
                if m[2] > alvo[2] or (m[2] == alvo[2] and alvo[1][5] and not m[1][5]):
                    alvo = m
            ax, ay = alvo[1][1], alvo[1][2]
            # só quem está a < tolerância do alvo; o resto fica para o próximo passo
            for m in g:
                dd = d2(m[1][1], m[1][2], ax, ay)
                if EPS0 < dd < self.tolQ:
                    moves.append((m[1][1], m[1][2], ax, ay))
                    self.lg("UNIR_VERTICE", model[m[1][3]], ax, ay)
        return self.mover(model, moves) if moves else model

    @staticmethod
    def ins_ponto(pts, fech, x, y):
        best, bk = 1e99, None
        for k, (a, b) in enumerate(zip(pts, proximos(pts, fech))):
            if b is not None:
                dd, u, _, _ = proj(x, y, a[0], a[1], b[0], b[1])
                if dd < best:
                    best, bk = dd, (k, u, a, b)
        if bk and best <= EPST:
            k, u, a, b = bk
            z = a[2] + u * (b[2] - a[2])
            return pts[:k + 1] + [(x, y, z)] + pts[k + 1:]
        return pts

    @staticmethod
    def conectado(model, q):
        return sum(1 for r in model if ativo(r) for p in r["pts"] if dist(p, q) <= EPS0) > 1

    def pontas(self, model):
        an = analisa(model, self.X, self.tolQ)
        for c in an["pontas"]:
            ra = model[c[0]]
            pts = ra["pts"]
            q = pts[0] if c[1] == 0 else pts[-1]
            if self.conectado(model, q):
                continue
            nb = pts[1] if c[1] == 0 else pts[-2]
            L = dist(q, nb)
            modo, px, py = "LIGAR_PONTA", c[7], c[8]
            if L > EPS0:
                wx, wy = (q[0] - nb[0]) / L, (q[1] - nb[1]) / L
                cx, cy, ex, ey = c[9], c[10], c[11] - c[9], c[12] - c[10]
                den = wx * ey - wy * ex
                if abs(den) > 1e-12:
                    s = ((cx - q[0]) * ey - (cy - q[1]) * ex) / den
                    v = ((cx - q[0]) * wy - (cy - q[1]) * wx) / den
                    if 0 < s <= self.X + EPST and -1e-9 <= v <= 1 + 1e-9:
                        modo, px, py = "ESTENDER_PONTA", q[0] + s * wx, q[1] + s * wy
            rb = model[c[5]]
            pv = next((p for p in rb["pts"] if d2(px, py, p[0], p[1]) <= EPST), None)
            if pv:
                px, py = pv[0], pv[1]
            novo = (px, py, q[2])
            if modo == "ESTENDER_PONTA":
                pts = [novo] + pts[1:] if c[1] == 0 else pts[:-1] + [novo]
            else:
                pts = [novo] + pts if c[1] == 0 else pts + [novo]
            ra["pts"] = pts
            ra["flags"].add("MOD")
            self.lg(modo, ra, px, py)
            if not pv:
                rb = model[c[5]]
                rb["pts"] = self.ins_ponto(rb["pts"], rb["fech"], px, py)
                rb["flags"].add("MOD")
                self.lg("INSERIR_VERTICE", rb, px, py)
        return model

    def inserir(self, model):
        an = analisa(model, self.X, self.tolQ)
        reqs = []
        for c in an["cruz"]:
            reqs.append((c[2], c[3], c[4], c[0], c[1]))
            reqs.append((c[5], c[6], c[7], c[0], c[1]))
        for t in an["tees"]:
            reqs.append((t[3], t[4], t[5], t[0], t[1]))
        reqs.sort(key=lambda r: (r[0], r[1], r[2]))
        por = {}
        for q in reqs:
            por.setdefault(q[0], []).append(q)
        for r in model:
            meus = por.get(r["id"])
            if not meus:
                continue
            res = []
            for k, (p, q) in enumerate(zip(r["pts"], proximos(r["pts"], r["fech"]))):
                res.append(p)
                for g in [m for m in meus if m[1] == k]:
                    if q is not None and d2(g[3], g[4], res[-1][0], res[-1][1]) > EPS0 \
                            and d2(g[3], g[4], q[0], q[1]) > EPS0:
                        res.append((g[3], g[4], p[2] + g[2] * (q[2] - p[2])))
                        self.lg("INSERIR_VERTICE", r, g[3], g[4])
            r["pts"] = res
            r["flags"].add("MOD")
        return model

    @staticmethod
    def divide(pts, fech, rems):
        n = len(pts)
        if fech:
            i = min(rems) + 1
            rot = pts[i % n:] + pts[:i % n]
            pts = rot + [rot[0]]
            rems = [(k - i + 2 * n) % n for k in rems]
        runs, cur = [], None
        for k, (a, b) in enumerate(zip(pts, pts[1:])):
            if k in rems:
                if cur:
                    runs.append(cur)
                cur = None
            else:
                cur = (cur if cur else [a]) + [b]
        if cur:
            runs.append(cur)
        return runs

    def sobrep(self, model):
        segs = []
        for r in model:
            if not ativo(r):
                continue
            pts = r["pts"]
            nxt = proximos(pts, True) if (r["fech"] and len(pts) > 2) else pts[1:]
            for k, (a, b) in enumerate(zip(pts, nxt)):
                if b is None:
                    continue
                if menor(a, b):
                    segs.append((a[0], a[1], b[0], b[1], r["id"], k))
                else:
                    segs.append((b[0], b[1], a[0], a[1], r["id"], k))
        segs.sort()
        remov, fora = [], set()
        for i, g in enumerate(segs):
            if i in fora:
                continue
            j = i + 1
            while j < len(segs) and segs[j][0] - g[0] <= 2 * EPS0:
                s = segs[j]
                if j not in fora and d2(g[0], g[1], s[0], s[1]) <= EPS0 and d2(g[2], g[3], s[2], s[3]) <= EPS0:
                    fora.add(j)
                    remov.append((s[4], s[5], g))
                j += 1
        if not remov:
            return model
        novos = []
        nid = len(model)
        for r in model:
            meus = [x[1] for x in remov if x[0] == r["id"]]
            if not meus:
                continue
            for x in remov:
                if x[0] == r["id"]:
                    self.lg("REMOVER_SOBREPOSICAO", r, x[2][0], x[2][1])
            runs = self.divide(r["pts"], r["fech"], meus)
            if not runs:
                self.lg("APAGAR_ENTIDADE", r, *r["pts"][0][:2])
                r["flags"].add("DEL")
                continue
            for p in runs[1:]:
                novos.append({"id": nid + len(novos), "h": r["h"] + "+nova", "tipo": r["tipo"], "fech": False,
                              "pts": p, "flags": (r["flags"] - {"DEL"}) | {"NOVO", "MOD"}, "orig": r["orig"]})
            if len(runs) > 1:
                self.lg("DIVIDIR", r, *runs[0][0][:2])
            r["pts"], r["fech"] = runs[0], False
            r["flags"].add("MOD")
        return model + novos

    def corrige(self, model):
        model = self.zeros(model)
        model = self.unir(model)
        passo, n0 = 0, -1
        while passo < 6 and n0 != len(self.log):
            n0 = len(self.log)
            model = self.pontas(model)
            model = self.inserir(model)
            model = self.unir(model)
            model = self.sobrep(model)
            model = self.zeros(model)
            passo += 1
        return model


def prepara_correcao(model, achata=True):
    """o que o c:RA_CORRIGIR faz antes de ra:corrige (conversões já estão no modelo)."""
    log = []
    for r in model:
        if "CONV" in r["flags"]:
            log.append(("CONVERTER", r["h"]))
            r["flags"].add("MOD")
        elif "ZVAR" in r["flags"] and achata:
            r["pts"] = [(p[0], p[1], 0.0) for p in r["pts"]]
            r["flags"] = (r["flags"] - {"ZVAR"}) | {"MOD"}
            log.append(("ACHATAR_Z", r["h"]))
        elif "ARCOS" in r["flags"]:
            r["flags"] = (r["flags"] - {"ARCOS"}) | {"MOD"}
            log.append(("DENSIFICAR_ARCOS", r["h"]))
    return log


def reindexa(model):
    """depois de gravar e reler: só os ativos, ids densos, sem flags de edição."""
    out = []
    for r in model:
        if ativo(r):
            out.append({**r, "id": len(out), "flags": set(f for f in r["flags"] if f in ("ZVAR", "ARCOS")),
                        "pts": list(r["pts"])})
    return out


# ----------------------------------------------------------------- exportação
def geojson(model, epsg):
    """igual ao ra:exporta: LineString 2D com rtos 4 casas, crs urn:ogc:def:crs:EPSG::n."""
    feats = []
    for r in model:
        if not ativo(r) or "CONV" in r["flags"] and "MOD" not in r["flags"]:
            continue
        if len(Corretor.limpa(r["pts"], r["fech"])) < 2:
            continue
        pts = r["pts"] + ([r["pts"][0]] if r["fech"] else [])
        coords = [[float(f"{p[0]:.4f}"), float(f"{p[1]:.4f}")] for p in pts]
        feats.append({"type": "Feature", "properties": {"handle": r["h"], "layer": r.get("layer", "")},
                      "geometry": {"type": "LineString", "coordinates": coords}})
    return {"type": "FeatureCollection", "name": "rede",
            "crs": {"type": "name", "properties": {"name": f"urn:ogc:def:crs:EPSG::{epsg}"}},
            "features": feats}
