"""Oráculo do RA_VALIDAR / RA_CORRIGIR / RA_EXPORTAR (lisps/RedeRotas.lsp).

Usa o espelho do núcleo (rederotas_core.py) sobre os DXF de teste
(gera_dxf_rederotas.py) e emula como o Routes Analyzer monta o grafo
(viewer/js/network.js + io.js, só lendo a lógica - nada no viewer muda):
reprojeção EPSG -> WGS 84, nó = célula de round(lon*kq), round(lat*kq),
kq = 111320 / tolerância, densificação a cada 25 m sem ligar nós internos.

Aceite:
 1. a validação encontra todos os erros plantados;
 2. a correção resolve todos (sobram só bloco e texto, que não são linhas);
 3. a rede exportada tem "Componentes conexos = 1" no grafo do viewer;
 4. a rota A->B atravessa os antigos pontos de erro;
 5. corrigir de novo não muda nada (log vazio).
Mais: rede aleatória (300 casos) - depois da correção não sobra erro de
topologia, a 2ª correção é vazia e todo vértice original fica a <= tolerância
da geometria corrigida.

Requer ezdxf e pyproj (só para os testes).
Uso: python src/tools/oraculo_rederotas.py [--salva-geojson]
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ezdxf                                    # noqa: E402
from pyproj import Transformer                  # noqa: E402

import rederotas_core as rc                     # noqa: E402
from oraculo_simplifica import segmenta_recs    # noqa: E402
import gera_dxf_rederotas as gd                 # noqa: E402

DENS, X, TOLQ = 5.0, 3.0, 1.0
CAMADAS = {"ESTRADAS", "TRILHAS"}


# --------------------------------------------------- leitura do DXF (= ra:le-rede)
def amostra(pts_densos, fech, dens):
    """pontos a cada <= dens ao longo da polilinha densa (como vlax-curve-getPointAtDist)."""
    acc = [0.0]
    for a, b in zip(pts_densos, pts_densos[1:]):
        acc.append(acc[-1] + math.dist(a[:2], b[:2]))
    L = acc[-1]
    n = max(1, math.ceil(L / dens - 1e-9))
    if fech:
        n = max(n, 3)
    out, j = [], 0
    for k in range(n if fech else n + 1):
        if k == 0:
            out.append(pts_densos[0])
            continue
        if k == n:
            out.append(pts_densos[-1])
            continue
        s = L * k / n
        while acc[j + 1] < s:
            j += 1
        t = (s - acc[j]) / (acc[j + 1] - acc[j])
        a, b = pts_densos[j], pts_densos[j + 1]
        out.append(tuple(a[i] + t * (b[i] - a[i]) for i in range(3)))
    return out


def le_dxf(arq, converte):
    doc = ezdxf.readfile(arq)
    model, naosup = [], []

    def reg(e, tipo, fech, pts, flags):
        model.append({"id": len(model), "h": e.dxf.handle, "tipo": tipo, "fech": fech, "pts": pts,
                      "flags": set(flags), "orig": e.dxf.handle, "layer": e.dxf.layer})

    def zvar(pts):
        return any(abs(p[2] - pts[0][2]) > 1e-6 for p in pts)

    for e in doc.modelspace():
        if e.dxf.layer.upper() not in CAMADAS:
            continue
        t = e.dxftype()
        if t == "LINE":
            pts = [tuple(e.dxf.start), tuple(e.dxf.end)]
            reg(e, "LINE", False, pts, ["ZVAR"] if zvar(pts) else [])
        elif t == "LWPOLYLINE":
            fech = e.closed
            recs = [((p[0], p[1]), 0.0, 0.0, p[4]) for p in e.get_points("xyseb")]
            segb = recs if fech else recs[:-1]
            flags = []
            if any(abs(r[3]) > 1e-12 for r in segb):
                recs = segmenta_recs(recs, fech, "MEDIDA", DENS)[0]
                flags = ["ARCOS"]
            z = e.dxf.elevation
            reg(e, "LWPOLYLINE", fech, [(r[0][0], r[0][1], z) for r in recs], flags)
        elif t == "POLYLINE" and e.is_3d_polyline:
            pts = [tuple(v.dxf.location) for v in e.vertices]
            reg(e, "POLYLINE3D", e.is_closed, pts, ["ZVAR"] if zvar(pts) else [])
        elif t in ("ARC", "CIRCLE", "SPLINE", "ELLIPSE"):
            fech = t == "CIRCLE" or (t == "SPLINE" and e.closed)
            if t == "ARC":
                a0, a1 = math.radians(e.dxf.start_angle), math.radians(e.dxf.end_angle)
                th = (a1 - a0) % (2 * math.pi) or 2 * math.pi
                c, r = e.dxf.center, e.dxf.radius
                densos = [(c[0] + r * math.cos(a0 + th * k / 4000), c[1] + r * math.sin(a0 + th * k / 4000), c[2])
                          for k in range(4001)]
            elif t == "SPLINE":
                densos = [tuple(v) for v in e.construction_tool().approximate(4000)]
            else:
                densos = [tuple(v) for v in e.construction_tool().vertices(
                    [e.dxf.start_param + (e.dxf.end_param - e.dxf.start_param) * k / 4000 for k in range(4001)])]
            pts = amostra(densos, fech, DENS)
            if converte:
                reg(e, t, fech, pts, ["CONV"])
            else:
                naosup.append({"tipo": t, "pt": pts[0], "conv": True})
        else:
            p = e.dxf.insert if e.dxf.hasattr("insert") else (0, 0, 0)
            naosup.append({"tipo": t, "pt": tuple(p), "conv": False})
    return model, naosup


# ------------------------------------------------------- emulação do viewer
def js_round(x):
    return math.floor(x + 0.5)


def grafo_viewer(gj, snap_tol=1.0, spacing=25.0):
    """network.js: nós por grade em lon/lat, densificação, union-find por arestas."""
    code = gj["crs"]["properties"]["name"].split("EPSG::")[-1]
    tr = Transformer.from_crs(int(code), 4326, always_xy=True)
    kq = 111320 / max(0.01, snap_tol)
    lon, lat, keymap, edges = [], [], {}, []

    def node_for(c):
        key = (js_round(c[0] * kq), js_round(c[1] * kq))
        if key not in keymap:
            keymap[key] = len(lon)
            lon.append(c[0])
            lat.append(c[1])
        return keymap[key]

    def new_node(x, y):
        lon.append(x)
        lat.append(y)
        return len(lon) - 1

    def hav(a0, b0, a1, b1):
        R = 6371008.8
        dl, dp = math.radians(a1 - a0), math.radians(b1 - b0)
        s = math.sin(dp / 2) ** 2 + math.cos(math.radians(b0)) * math.cos(math.radians(b1)) * math.sin(dl / 2) ** 2
        return 2 * R * math.asin(min(1, math.sqrt(s)))

    for f in gj["features"]:
        line = [tr.transform(c[0], c[1]) for c in f["geometry"]["coordinates"]]
        if len(line) < 2:
            continue
        prev = node_for(line[0])
        for a, b in zip(line, line[1:]):
            L = hav(a[0], a[1], b[0], b[1])
            nsub = max(1, math.ceil(L / spacing))
            for j in range(1, nsub + 1):
                nd = node_for(b) if j == nsub else new_node(a[0] + (b[0] - a[0]) * j / nsub,
                                                           a[1] + (b[1] - a[1]) * j / nsub)
                if nd == prev:
                    continue
                edges.append((prev, nd))
                prev = nd
    uf = rc.UF(len(lon))
    for a, b in edges:
        uf.une(a, b)
    comps = len({uf.find(i) for i in range(len(lon))})
    return {"lon": lon, "lat": lat, "edges": edges, "comps": comps, "hav": hav, "tr": tr}


def rota(g, a_xy, b_xy):
    """BFS entre os nós mais próximos de A e B (coordenadas do desenho)."""
    def snap(xy):
        lo, la = g["tr"].transform(*xy)
        return min(range(len(g["lon"])), key=lambda i: g["hav"](lo, la, g["lon"][i], g["lat"][i]))
    adj = {}
    for a, b in g["edges"]:
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    s, t = snap(a_xy), snap(b_xy)
    pred, fila = {s: None}, [s]
    for u in fila:
        if u == t:
            break
        for v in adj.get(u, []):
            if v not in pred:
                pred[v] = u
                fila.append(v)
    if t not in pred:
        return None
    path, v = [], t
    while v is not None:
        path.append(v)
        v = pred[v]
    return path[::-1]


def perto_da_rota(g, path, xy, tol=1.5):
    lo, la = g["tr"].transform(*xy)
    return min(g["hav"](lo, la, g["lon"][i], g["lat"][i]) for i in path) <= tol


# --------------------------------------------------------------- casos
def corrige_tudo(model, achata=True):
    rc.prepara_correcao(model, achata)
    c = rc.Corretor(X, TOLQ)
    model = c.corrige(model)
    return rc.reindexa(model), c.log


def topo_erros(model):
    an = rc.analisa(model, X, TOLQ)
    return an, [e for e in rc.erros(model, an) if e[0] not in ("NAO_SUPORTADA", "ARCOS", "Z_VARIAVEL")]


def caso_dxf(pasta, salva):
    ok = True
    arq = os.path.join(pasta, "rede_erros.dxf")
    model, naosup = le_dxf(arq, converte=False)
    an = rc.analisa(model, X, TOLQ)
    er = rc.erros(model, an, naosup)
    P = lambda x, y: (gd.X0 + x, gd.Y0 + y)                                    # noqa: E731

    def achou(tipo, x=None, y=None, tol=1.0):
        return any(e[0] == tipo and (x is None or math.dist(e[1:3], P(x, y)) <= tol) for e in er)

    esperados = [("CRUZAMENTO", 50, 0), ("T_SEM_VERTICE", 50, 60), ("PONTA_SOLTA", 150, 62),
                 ("QUASE_COINCIDENTE", None, None), ("DUPLICADA", None, None), ("SOBREPOSTA", None, None),
                 ("T_SEM_VERTICE", 250, 150), ("T_SEM_VERTICE", 300, 150), ("SEGMENTO_ZERO", 350, 150),
                 ("Z_VARIAVEL", 560, 150), ("ARCOS", 650, 150), ("FRAGMENTO", None, None)]
    falta = [e for e in esperados if not achou(*e)]
    ns = sorted(x["tipo"] for x in naosup)
    ns_ok = ns == ["ARC", "ELLIPSE", "INSERT", "SPLINE", "TEXT"]
    cont = {}
    for e in er:
        cont[e[0]] = cont.get(e[0], 0) + 1
    print(f"1. validação: {len(er)} erros/avisos {dict(sorted(cont.items()))}; "
          f"componentes = {an['comp'][0]}")
    print(f"   plantados não encontrados: {falta or 'nenhum'}; não suportados = {ns}")
    ok &= not falta and ns_ok

    # coordenadas locais (verificação feita na LISP por faixa do EPSG; aqui a mesma regra)
    m2, _ = le_dxf(os.path.join(pasta, "rede_coord_local.dxf"), False)
    fx = (100000.0, 1000000.0, 900000.0, 10000000.0)
    fora = [r for r in m2 if any(p[0] < fx[0] or p[1] < fx[1] or p[0] > fx[2] or p[1] > fx[3] for p in r["pts"])]
    ins = ezdxf.readfile(os.path.join(pasta, "rede_coord_local.dxf")).header["$INSUNITS"]
    print(f"   rede_coord_local.dxf: {len(fora)}/{len(m2)} linhas fora da faixa do EPSG 31983, INSUNITS = {ins}")
    ok &= len(fora) == len(m2) and ins != 6

    # 2. correção
    model, naosup2 = le_dxf(arq, converte=True)
    model, log = corrige_tudo(model)
    an2, er2 = topo_erros(model)
    ops = {}
    for l in log:
        ops[l[0]] = ops.get(l[0], 0) + 1
    print(f"2. correção: {len(log)} alterações {dict(sorted(ops.items()))}")
    print(f"   depois: erros de topologia = {len(er2)} {[e[0] for e in er2]}; componentes = {an2['comp'][0]}; "
          f"sobram não suportados: {sorted(x['tipo'] for x in naosup2)}")
    ok &= not er2 and an2["comp"][0] == 1

    # 3-4. exportação e grafo do viewer
    gj = json.loads(json.dumps(rc.geojson(model, 31983)))
    if salva:
        with open(os.path.join(pasta, "rede_corrigida_esperada.geojson"), "w", encoding="utf-8") as f:
            json.dump(gj, f)
    g = grafo_viewer(gj)
    print(f"3. viewer: {len(gj['features'])} feições, {len(g['lon'])} nós, componentes conexos = {g['comps']}")
    ok &= g["comps"] == 1
    path = rota(g, P(0, 0), P(800, 150))
    pontos = [(50, 0), (50, 60), (150, 60), (150, 150), (250, 150), (300, 150), (350, 150), (400, 150),
              (450, 150), (500, 150), (560, 150), (650, 150), (700, 150)]
    passa = [pt for pt in pontos if path and perto_da_rota(g, path, P(*pt))]
    print(f"4. rota A->B: {'existe' if path else 'NÃO existe'}; passa por {len(passa)}/{len(pontos)} antigos pontos de erro")
    ok &= path is not None and len(passa) == len(pontos)

    # 5. idempotência
    c = rc.Corretor(X, TOLQ)
    c.corrige(model)
    print(f"5. 2ª correção: {len(c.log)} alterações")
    ok &= not c.log
    return ok


def rede_aleatoria(rnd):
    """linhas e polilinhas com T, quase-coincidentes, pontas soltas, duplicadas e cruzamentos."""
    model = []

    def add(pts, fech=False, tipo="LWPOLYLINE"):
        model.append({"id": len(model), "h": f"H{len(model)}", "tipo": tipo, "fech": fech,
                      "pts": [(p[0], p[1], 0.0) for p in pts], "flags": set(), "orig": None})

    for _ in range(rnd.randint(3, 12)):
        n = rnd.randint(2, 5)
        x, y = rnd.uniform(0, 200), rnd.uniform(0, 200)
        pts = [(x, y)]
        for _ in range(n - 1):
            x, y = x + rnd.uniform(-60, 60), y + rnd.uniform(-60, 60)
            pts.append((x, y))
        add(pts, fech=(n >= 3 and rnd.random() < 0.1))
    for _ in range(rnd.randint(1, 8)):
        r = rnd.choice(model)
        k = rnd.randrange(len(r["pts"]) - 1)
        a, b = r["pts"][k], r["pts"][k + 1]
        u = rnd.uniform(0.2, 0.8)
        q = (a[0] + u * (b[0] - a[0]), a[1] + u * (b[1] - a[1]))
        modo = rnd.random()
        if modo < 0.35:                                     # T exato
            add([q, (q[0] + rnd.uniform(-50, 50), q[1] + rnd.uniform(-50, 50))])
        elif modo < 0.6:                                    # ponta solta perto
            ang = rnd.uniform(0, 2 * math.pi)
            dd = rnd.uniform(1.2, 2.8)
            add([(q[0] + dd * math.cos(ang), q[1] + dd * math.sin(ang)),
                 (q[0] + 40 * math.cos(ang), q[1] + 40 * math.sin(ang))])
        elif modo < 0.8:                                    # quase coincidente com um vértice
            v = rnd.choice(r["pts"])
            add([(v[0] + rnd.uniform(-0.6, 0.6), v[1] + rnd.uniform(-0.6, 0.6)),
                 (v[0] + rnd.uniform(-50, 50), v[1] + rnd.uniform(-50, 50))])
        else:                                               # duplicada / sobreposta
            add([a, b] if rnd.random() < 0.5 else [a, q])
    if rnd.random() < 0.3:
        r = rnd.choice(model)
        r["pts"].insert(1, r["pts"][1])                     # segmento zero
    return model


def caso_aleatorio(n=300):
    rnd = random.Random(7)
    sobra = nao_idem = desvio = 0
    pior = 0.0
    for _ in range(n):
        model = rede_aleatoria(rnd)
        orig = [p for r in model for p in r["pts"]]
        model, log = corrige_tudo(model)
        an, er = topo_erros(model)
        er = [e for e in er if e[0] != "FRAGMENTO"]
        sobra += bool(er)
        c = rc.Corretor(X, TOLQ)
        c.corrige(model)
        nao_idem += bool(c.log)
        segs = [(a, b) for r in model for a, b in zip(r["pts"], rc.proximos(r["pts"], r["fech"])) if b is not None]
        for p in orig:
            d = min(rc.proj(p[0], p[1], a[0], a[1], b[0], b[1])[0] for a, b in segs) if segs else 0.0
            pior = max(pior, d)
            desvio += d > TOLQ + 1e-9
    print(f"6. aleatório ({n} redes): com erro de topologia depois = {sobra}; 2ª correção não vazia = {nao_idem}; "
          f"vértices originais longe (> {TOLQ} m) = {desvio}, maior distância {pior:.3f} m")
    return sobra == 0 and nao_idem == 0 and desvio == 0


if __name__ == "__main__":
    pasta = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "testes", "rederotas")
    pasta = os.path.normpath(pasta)
    os.makedirs(pasta, exist_ok=True)
    gd.rede_erros(os.path.join(pasta, "rede_erros.dxf"))
    gd.rede_local(os.path.join(pasta, "rede_coord_local.dxf"))
    ok = caso_dxf(pasta, "--salva-geojson" in sys.argv)
    ok = caso_aleatorio() and ok
    print("OK" if ok else "FALHOU")
