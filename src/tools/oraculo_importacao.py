"""Oráculo dos importadores IMPKML / IMPGEOJSON / IMPSHP (lisps/Imp*.lsp).

Espelha as partes numéricas e binárias das LISPs e confere com referências:
 1. Transversa de Mercator própria (ic:tm-fwd / ic:tm-inv) x pyproj
    (SIRGAS 2000 / UTM 18S-25S e WGS 84) - ida e volta;
 2. double IEEE 754 little-endian (is:f64) x struct; inteiros LE/BE;
 3. UTF-8 (ic:utf8) x Python; detecção UTF-8 (is:utf8-p);
 4. .prj -> EPSG (ic:wkt->epsg) em WKT ESRI e OGC gerados pelo pyproj;
 5. número JSON (ij:numero: mantissa x 10^expoente) x float;
 6. leitor SHP/DBF com os MESMOS deslocamentos da LISP x pyshp, nos
    arquivos de teste gerados (pontos Z, linhas, polígonos com furo,
    atributos C/N/F/D/L com acentos).
Gera os arquivos de teste em data/testes/importacao/.

Requer pyproj e pyshp (só para os testes).
Uso: python src/tools/oraculo_importacao.py
"""
import json
import math
import os
import random
import struct
import zipfile

import shapefile
from pyproj import CRS, Transformer

A, F, K0 = 6378137.0, 1 / 298.257223563, 0.9996


# ------------------------------------------------------- espelho: ic:tm-*
def tm_fwd(lon, lat, zona, sul):
    e2 = F * (2 - F)
    ep2 = e2 / (1 - e2)
    phi, lam0 = math.radians(lat), math.radians(zona * 6.0 - 183.0)
    s, c = math.sin(phi), math.cos(phi)
    N = A / math.sqrt(1 - e2 * s * s)
    T = math.tan(phi) ** 2
    C = ep2 * c * c
    Aa = c * (math.radians(lon) - lam0)
    M = A * ((1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256) * phi
             - (3 * e2 / 8 + 3 * e2 ** 2 / 32 + 45 * e2 ** 3 / 1024) * math.sin(2 * phi)
             + (15 * e2 ** 2 / 256 + 45 * e2 ** 3 / 1024) * math.sin(4 * phi)
             - (35 * e2 ** 3 / 3072) * math.sin(6 * phi))
    x = 500000 + K0 * N * (Aa + (1 - T + C) * Aa ** 3 / 6 + (5 - 18 * T + T * T + 72 * C - 58 * ep2) * Aa ** 5 / 120)
    y = (10000000 if sul else 0) + K0 * (M + N * math.tan(phi) * (
        Aa ** 2 / 2 + (5 - T + 9 * C + 4 * C * C) * Aa ** 4 / 24
        + (61 - 58 * T + T * T + 600 * C - 330 * ep2) * Aa ** 6 / 720))
    return x, y


def tm_inv(x, y, zona, sul):
    e2 = F * (2 - F)
    ep2 = e2 / (1 - e2)
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    M = (y - (10000000 if sul else 0)) / K0
    mu = M / (A * (1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256))
    p1 = (mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * math.sin(2 * mu) + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * math.sin(4 * mu)
          + (151 * e1 ** 3 / 96) * math.sin(6 * mu) + (1097 * e1 ** 4 / 512) * math.sin(8 * mu))
    s, c = math.sin(p1), math.cos(p1)
    C1, T1 = ep2 * c * c, math.tan(p1) ** 2
    N1 = A / math.sqrt(1 - e2 * s * s)
    R1 = A * (1 - e2) / (1 - e2 * s * s) ** 1.5
    D = (x - 500000) / (N1 * K0)
    lon = zona * 6.0 - 183.0 + math.degrees((D - (1 + 2 * T1 + C1) * D ** 3 / 6
                                             + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * ep2 + 24 * T1 * T1) * D ** 5 / 120) / c)
    lat = math.degrees(p1 - (N1 * math.tan(p1) / R1) * (D * D / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * D ** 4 / 24
                                                        + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * ep2 - 3 * C1 * C1) * D ** 6 / 720))
    return lon, lat


# ------------------------------------------------- espelho: is:f64 etc.
def f64(b, i):
    b6, b7 = b[i + 6], b[i + 7]
    e = (b7 & 127) * 16 + (b6 >> 4)
    m = ((b6 & 15) * 281474976710656.0 + b[i + 5] * 1099511627776.0 + b[i + 4] * 4294967296.0
         + b[i + 3] * 16777216.0 + b[i + 2] * 65536.0 + b[i + 1] * 256.0 + b[i])
    sg = -1.0 if b7 >= 128 else 1.0
    if e == 2047:
        return None
    if e == 0:
        return sg * m * 2.0 ** -1074
    return sg * (1 + m / 4503599627370496.0) * 2.0 ** (e - 1023)


def i32le(b, i):
    return int(b[i] + 256.0 * b[i + 1] + 65536.0 * b[i + 2] + 16777216.0 * (b[i + 3] & 127))


def i32be(b, i):
    return int(b[i + 3] + 256.0 * b[i + 2] + 65536.0 * b[i + 1] + 16777216.0 * (b[i] & 127))


def utf8(bs):
    r, i = [], 0
    while i < len(bs):
        c = bs[i]
        i += 1
        if c < 128:
            r.append(c)
        elif 192 <= c < 224 and i < len(bs):
            r.append((c & 31) * 64 + (bs[i] & 63))
            i += 1
        elif 224 <= c < 240 and i + 1 < len(bs):
            r.append((c & 15) * 4096 + (bs[i] & 63) * 64 + (bs[i + 1] & 63))
            i += 2
        elif c >= 240:
            r.append(63)
            i += 3
        else:
            r.append(c)
    return "".join(chr(x) for x in r)


def utf8_p(bs):
    i = 0
    while i < len(bs):
        c = bs[i]
        i += 1
        n = 0 if c < 128 else 1 if c & 224 == 192 else 2 if c & 240 == 224 else 3 if c & 248 == 240 else -1
        if n < 0:
            return False
        for _ in range(n):
            if i < len(bs) and bs[i] & 192 == 128:
                i += 1
            else:
                return False
    return True


# --------------------------------------------- espelho: ic:wkt->epsg
def wkt_epsg(w):
    import re
    u = w.upper()
    ini = max(0, len(u) - 40)
    i = u.find('AUTHORITY["EPSG","', ini)
    if i >= 0:
        n = int(re.match(r"\d*", u[i + 18:]).group() or 0)
        if n > 0:
            return n
    t = u.replace(" ", "_")
    z = None
    i = t.find("ZONE_")
    if i >= 0:
        dig = re.match(r"\d*", u[i + 5:i + 7]).group()
        z = int(dig) if dig else 0
        tail = u[i + 5:i + 8]
        sul = bool(re.match(r"\d\dS|\dS", tail))
        z = (z if sul else -z) if z > 0 else None
    wc = lambda pat: re.search(pat, u) is not None   # noqa: E731
    if z and z > 0 and wc("SIRGAS"):
        return 31960 + z
    if z and z > 0 and wc(r"SAD.*69|SAD_1969"):
        return 29160 + z
    if z and z > 0 and wc(r"WGS.*84|WGS_1984"):
        return 32700 + z
    if z and z < 0 and wc(r"WGS.*84|WGS_1984"):
        return 32600 - z
    if not u.startswith("PROJCS") and wc("SIRGAS"):
        return 4674
    if not u.startswith("PROJCS") and wc(r"WGS.*84|WGS_1984"):
        return 4326
    return None


def num_json(s):
    e = s.lower().find("e")
    if e >= 0:
        return float(s[:e]) * 10.0 ** int(s[e + 1:].lstrip("+"))
    return float(s)


# ---------------------------------------- espelho: is:shp / is:geom / is:dbf
def le_shp(b):
    assert i32be(b, 0) == 9994
    fim = min(len(b), 2 * i32be(b, 24))
    pos, out = 100, []
    while pos + 12 <= fim:
        clen = 2 * i32be(b, pos + 4)
        out.append(geom(b, pos + 8))
        pos += 8 + clen
    return out


def pontos(b, p, pz, k0, k1):
    return [(f64(b, p + 16 * k), f64(b, p + 16 * k + 8), (f64(b, pz + 8 * k) if pz else 0.0) or 0.0)
            for k in range(k0, k1)]


def geom(b, c):
    tp = i32le(b, c)
    if tp == 0:
        return []
    if tp in (1, 11, 21):
        return [("PT", [(f64(b, c + 4), f64(b, c + 12), (f64(b, c + 20) or 0.0) if tp == 11 else 0.0)])]
    if tp in (8, 18, 28):
        n = i32le(b, c + 36)
        return [("PT", [p]) for p in pontos(b, c + 40, c + 40 + 16 * n + 16 if tp == 18 else None, 0, n)]
    np_, npt = i32le(b, c + 36), i32le(b, c + 40)
    pp = c + 44 + 4 * np_
    pz = pp + 16 * npt + 16 if tp in (13, 15) else None
    tipo = "AN" if tp in (5, 15, 25) else "LN"
    partes = [i32le(b, c + 44 + 4 * k) for k in range(np_)]
    return [(tipo, pontos(b, pp, pz, a, bb)) for a, bb in zip(partes, partes[1:] + [npt])]


def le_dbf(b, cod):
    nrec, hdr, rlen = i32le(b, 4), b[8] + 256 * b[9], b[10] + 256 * b[11]
    pos, off, campos = 32, 1, []
    while pos < hdr - 1 and b[pos] != 13:
        nome = bytes(x for x in b[pos:pos + 11] if x).split(b"\0")[0]
        campos.append((txt(list(nome), cod), chr(b[pos + 11]), b[pos + 16], b[pos + 17], off))
        off += b[pos + 16]
        pos += 32
    regs = []
    for i in range(nrec):
        base = hdr + i * rlen
        reg = {}
        for c in campos:
            s = txt(list(b[base + c[4]:base + c[4] + c[2]]), cod)
            reg[c[0]] = valor(s, c[1])
        regs.append(reg)
    return campos, regs


def txt(bs, cod):
    bs = [x for x in bs if x]
    if not any(x > 127 for x in bs):
        s = "".join(chr(x) for x in bs)
    elif cod == "UTF8" or (cod is None and utf8_p(bs)):
        s = utf8(bs)
    else:
        s = "".join(chr(x) for x in bs)
    return s.strip(" ")


def valor(s, tp):
    if s == "":
        return None
    if tp in ("N", "F"):                       # ic:num-dbf: asteriscos/lixo -> None
        try:
            return float(s)
        except ValueError:
            return None
    if tp == "D" and s == "00000000":
        return None
    if tp == "D" and len(s) == 8:
        return f"{s[:4]}-{s[4:6]}-{s[6:]}"
    if tp == "L":
        return "true" if s.upper() in ("T", "Y", "S") else "false" if s.upper() in ("F", "N") else None
    return s


# ------------------------------------------------------- arquivos de teste
X0, Y0 = 480000.0, 7506000.0
ESRI_31983 = CRS.from_epsg(31983).to_wkt("WKT1_ESRI")


def gera(pasta):
    os.makedirs(pasta, exist_ok=True)
    ll = Transformer.from_crs(31983, 4326, always_xy=True)
    L = lambda x, y: ll.transform(X0 + x, Y0 + y)          # noqa: E731

    # SHP: pontos Z, linhas, polígonos com furo; UTF-8 com .cpg
    def campos(w):
        w.field("NOME", "C", 40)
        w.field("CODIGO", "N", 8, 0)
        w.field("AREA_HA", "N", 12, 3)
        w.field("DATA", "D")
        w.field("ATIVO", "L")
    with shapefile.Writer(os.path.join(pasta, "pontos_utm23s"), shapeType=shapefile.POINTZ, encoding="utf-8") as w:
        campos(w)
        for k, (nome, z) in enumerate([("Poço Açude", 812.5), ("Sede São João", 805.0), ("Porteira Nº 3", 799.25)]):
            w.pointz(X0 + 40 * k, Y0 + 15 * k, z)
            w.record(nome, k + 1, None, "20261114", k % 2 == 0)
    with shapefile.Writer(os.path.join(pasta, "linhas_utm23s"), shapeType=shapefile.POLYLINE, encoding="utf-8") as w:
        campos(w)
        w.line([[(X0, Y0), (X0 + 100, Y0 + 20), (X0 + 180, Y0)]])
        w.record("Estrada Principal", 10, None, "20250101", True)
        w.line([[(X0, Y0 + 50), (X0 + 60, Y0 + 70)], [(X0 + 80, Y0 + 70), (X0 + 150, Y0 + 90)]])
        w.record("Carreador (2 partes)", 11, None, None, False)
    with shapefile.Writer(os.path.join(pasta, "talhoes_utm23s"), shapeType=shapefile.POLYGON, encoding="utf-8") as w:
        campos(w)
        w.poly([[(X0, Y0 + 120), (X0, Y0 + 220), (X0 + 120, Y0 + 220), (X0 + 120, Y0 + 120), (X0, Y0 + 120)],
                [(X0 + 40, Y0 + 150), (X0 + 80, Y0 + 150), (X0 + 80, Y0 + 190), (X0 + 40, Y0 + 190), (X0 + 40, Y0 + 150)]])
        w.record("Talhão 01 (com reserva)", 1, 1.04, "20240310", True)
        w.poly([[(X0 + 150, Y0 + 120), (X0 + 150, Y0 + 200), (X0 + 260, Y0 + 160), (X0 + 150, Y0 + 120)]])
        w.record("Talhão 02", 2, 0.44, "20240310", False)
    for b in ("pontos_utm23s", "linhas_utm23s", "talhoes_utm23s"):
        open(os.path.join(pasta, b + ".prj"), "w").write(ESRI_31983)
        open(os.path.join(pasta, b + ".cpg"), "w").write("UTF-8")
    # SHP em WGS 84, Latin-1 sem .cpg
    with shapefile.Writer(os.path.join(pasta, "pontos_wgs84_latin1"), shapeType=shapefile.POINT, encoding="latin1") as w:
        w.field("NOME", "C", 30)
        w.field("VALOR", "F", 12, 4)
        for k, nome in enumerate(["Coração", "Ribeirão Preto"]):
            w.point(*L(30 * k, 260))
            w.record(nome, 3.1416 * (k + 1))
    open(os.path.join(pasta, "pontos_wgs84_latin1.prj"), "w").write(CRS.from_epsg(4326).to_wkt("WKT1_ESRI"))

    # GeoJSON WGS 84 (sem crs) com todos os tipos
    feats = [
        {"type": "Feature", "properties": {"nome": "Ponto \"aspas\" e ç", "codigo": 1, "area": 1.5e2, "ok": True,
                                           "obs": None, "meta": {"a": [1, 2]}},
         "geometry": {"type": "Point", "coordinates": [*L(0, 300), 801.5]}},
        {"type": "Feature", "properties": {"nome": "Linha", "codigo": 2},
         "geometry": {"type": "LineString", "coordinates": [list(L(0, 320)), list(L(100, 340)), list(L(200, 320))]}},
        {"type": "Feature", "properties": {"nome": "Polígono com furo", "codigo": 3},
         "geometry": {"type": "Polygon", "coordinates": [
             [list(L(0, 360)), list(L(100, 360)), list(L(100, 440)), list(L(0, 440)), list(L(0, 360))],
             [list(L(30, 380)), list(L(60, 380)), list(L(60, 410)), list(L(30, 410)), list(L(30, 380))]]}},
        {"type": "Feature", "properties": {"nome": "Multi", "codigo": 4},
         "geometry": {"type": "MultiPolygon", "coordinates": [
             [[list(L(150, 360)), list(L(200, 360)), list(L(200, 400)), list(L(150, 360))]],
             [[list(L(220, 360)), list(L(260, 360)), list(L(260, 400)), list(L(220, 360))]]]}},
        {"type": "Feature", "properties": {"nome": "Coleção", "codigo": 5},
         "geometry": {"type": "GeometryCollection", "geometries": [
             {"type": "MultiPoint", "coordinates": [list(L(300, 300)), list(L(310, 300))]},
             {"type": "MultiLineString", "coordinates": [[list(L(300, 320)), list(L(340, 330))]]}]}},
        {"type": "Feature", "properties": {"nome": "Sem geometria", "codigo": 6}, "geometry": None},
    ]
    json.dump({"type": "FeatureCollection", "features": feats},
              open(os.path.join(pasta, "feicoes_wgs84.geojson"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # GeoJSON em UTM com membro crs
    json.dump({"type": "FeatureCollection", "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:EPSG::31983"}},
               "features": [{"type": "Feature", "properties": {"id": 1, "talhao": "T-10"},
                             "geometry": {"type": "LineString", "coordinates": [[X0, Y0 + 460], [X0 + 200, Y0 + 460]]}}]},
              open(os.path.join(pasta, "linha_utm23s.geojson"), "w", encoding="utf-8"))

    # KML com pastas, ExtendedData, Point/LineString/Polygon com furo, MultiGeometry
    def cc(pts):
        return " ".join(f"{x:.8f},{y:.8f},0" for x, y in pts)
    kml = f"""<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document><name>Fazenda Teste</name>
 <Folder><name>Infraestrutura</name>
  <Placemark><name>Sede São José</name><description><![CDATA[<b>Casa</b> principal]]></description>
   <ExtendedData><Data name="tipo"><value>edificação</value></Data><Data name="area_m2"><value>350.5</value></Data></ExtendedData>
   <Point><coordinates>{cc([L(0, 520)])}</coordinates></Point></Placemark>
  <Folder><name>Estradas</name>
   <Placemark><name>Estrada 1</name>
    <ExtendedData><SchemaData schemaUrl="#s"><SimpleData name="largura">6</SimpleData></SchemaData></ExtendedData>
    <LineString><coordinates>
     {cc([L(0, 540), L(100, 560), L(200, 540)])}
    </coordinates></LineString></Placemark>
  </Folder>
 </Folder>
 <Folder><name>Talhões</name>
  <Placemark><name>Talhão A</name>
   <Polygon><outerBoundaryIs><LinearRing><coordinates>{cc([L(0, 580), L(120, 580), L(120, 680), L(0, 680), L(0, 580)])}</coordinates></LinearRing></outerBoundaryIs>
   <innerBoundaryIs><LinearRing><coordinates>{cc([L(40, 610), L(80, 610), L(80, 650), L(40, 650), L(40, 610)])}</coordinates></LinearRing></innerBoundaryIs></Polygon></Placemark>
  <Placemark><name>Talhão B (multi)</name><MultiGeometry>
   <Polygon><outerBoundaryIs><LinearRing><coordinates>{cc([L(150, 580), L(200, 580), L(200, 630), L(150, 580)])}</coordinates></LinearRing></outerBoundaryIs></Polygon>
   <Point><coordinates>{cc([L(175, 600)])}</coordinates></Point>
  </MultiGeometry></Placemark>
 </Folder>
</Document></kml>
"""
    open(os.path.join(pasta, "fazenda.kml"), "w", encoding="utf-8").write(kml)
    with zipfile.ZipFile(os.path.join(pasta, "fazenda.kmz"), "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("doc.kml", kml)


if __name__ == "__main__":
    rnd = random.Random(3)
    ok = True

    # 1. TM x pyproj
    pior_f = pior_i = 0.0
    for _ in range(3000):
        zona = rnd.randint(18, 25)
        lon = zona * 6 - 183 + rnd.uniform(-3.2, 3.2)
        lat = rnd.uniform(-33.8, 5.0)
        epsg = 31960 + zona
        tr = Transformer.from_crs(4326, epsg, always_xy=True)
        x, y = tr.transform(lon, lat)
        if lat > 0:                               # zona sul com latitude norte: y < 10e6
            pass
        mx, my = tm_fwd(lon, lat, zona, True)
        pior_f = max(pior_f, math.hypot(mx - x, my - y))
        lo2, la2 = tm_inv(x, y, zona, True)
        pior_i = max(pior_i, math.hypot((lo2 - lon) * 111320 * math.cos(math.radians(lat)), (la2 - lat) * 110574))
    print(f"1. TM própria x pyproj (SIRGAS 2000 UTM 18S-25S, 3000 pontos): ida {pior_f * 1000:.2f} mm, volta {pior_i * 1000:.2f} mm")
    ok &= pior_f < 0.01 and pior_i < 0.01

    # 2. double / inteiros
    pior = 0
    vals = [0.0, -0.0, 1.0, -1.5, 480123.456789, 7506123.987654321, 1e-310, -2.5e-320, 1.7e308, -123456789.0]
    vals += [rnd.uniform(-1e7, 1e7) for _ in range(5000)] + [rnd.uniform(-1, 1) * 10 ** rnd.randint(-300, 300) for _ in range(2000)]
    erros_f = sum(1 for v in vals if f64(struct.pack("<d", v), 0) != v)
    erros_i = 0
    for _ in range(2000):
        n = rnd.randint(0, 2 ** 31 - 1)
        erros_i += i32le(struct.pack("<i", n), 0) != n or i32be(struct.pack(">i", n), 0) != n
    nan = f64(struct.pack("<d", float("nan")), 0) is None
    print(f"2. double: {len(vals)} valores, divergências = {erros_f} (NaN -> nil: {nan}); inteiros LE/BE: divergências = {erros_i}")
    ok &= erros_f == 0 and erros_i == 0 and nan

    # 3. UTF-8
    textos = ["Talhão", "Açaí ção", "São Paulo — ok", "Nº 3 °C", "plain", "€ 10", "日本"]
    e3 = sum(1 for t in textos if utf8(list(t.encode("utf-8"))) != t)
    det = all(utf8_p(list(t.encode("utf-8"))) for t in textos) and not utf8_p(list("Coração".encode("latin1")))
    print(f"3. UTF-8: divergências = {e3}; detecção UTF-8 x Latin-1 correta: {det}")
    ok &= e3 == 0 and det

    # 4. .prj -> EPSG
    casos = [31982, 31983, 31984, 31985, 32722, 32723, 32621, 4326, 4674, 29193]
    falhas = []
    for c in casos:
        for fmt in ("WKT1_ESRI", "WKT1_GDAL"):
            w = CRS.from_epsg(c).to_wkt(fmt)
            # SAD69 23S: com AUTHORITY sai 29193; pelo nome sai 29183 (código antigo) - os dois são a mesma zona
            esperado = (29183, 29193) if c == 29193 else (c,)
            if wkt_epsg(w) not in esperado:
                falhas.append((c, fmt, wkt_epsg(w)))
    print(f"4. .prj -> EPSG: {2 * len(casos) - len(falhas)}/{2 * len(casos)} (falhas: {falhas or 'nenhuma'})")
    ok &= not falhas

    # 5. números JSON
    nums = ["0", "-12", "3.14159265358979", "-46.123456789012", "1e5", "1.5E-7", "-2.5e+3", "480123.4567"]
    e5 = max(abs(num_json(s) - float(s)) / max(1.0, abs(float(s))) for s in nums)
    print(f"5. números JSON: erro relativo máx. {e5:.1e}")
    ok &= e5 < 1e-15

    # 6. arquivos de teste + leitor SHP/DBF espelhado x pyshp
    pasta = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "testes", "importacao"))
    gera(pasta)
    diverg = 0
    total = 0
    for base, cod in (("pontos_utm23s", "UTF8"), ("linhas_utm23s", "UTF8"), ("talhoes_utm23s", "UTF8"),
                      ("pontos_wgs84_latin1", None)):
        b = open(os.path.join(pasta, base + ".shp"), "rb").read()
        gs = le_shp(b)
        r = shapefile.Reader(os.path.join(pasta, base), encoding="utf-8" if cod else "latin1")
        for g, s in zip(gs, r.shapes()):
            total += 1
            pts_ref = [tuple(p) for p in s.points]
            pts = [p[:2] for parte in g for p in parte[1]]
            if pts != pts_ref:
                diverg += 1
            if hasattr(s, "z") and s.z and [p[2] for parte in g for p in parte[1]] != list(s.z):
                diverg += 1
            if len(g) != max(1, len(getattr(s, "parts", [0]) or [0])) and s.shapeType not in (1, 11, 21):
                diverg += 1
        campos, regs = le_dbf(open(os.path.join(pasta, base + ".dbf"), "rb").read(), cod)
        for reg, ref in zip(regs, r.records()):
            d = ref.as_dict()
            for k, v in reg.items():
                rv = d[k]
                if hasattr(rv, "isoformat"):
                    rv = rv.isoformat()
                elif isinstance(rv, bool):
                    rv = "true" if rv else "false"
                elif isinstance(rv, int):
                    rv = float(rv)
                if rv != v and not (rv in (None, "") and v is None):
                    diverg += 1
                    print("   dbf", base, k, repr(v), repr(rv))
        wk = wkt_epsg(open(os.path.join(pasta, base + ".prj")).read())
        print(f"   {base}: {len(gs)} registros, campos {[c[0] + ':' + c[1] for c in campos]}, .prj -> EPSG {wk}")
    print(f"6. SHP/DBF espelhado x pyshp: {total} geometrias + atributos, divergências = {diverg}")
    ok &= diverg == 0
    print(f"   arquivos de teste em {pasta}")
    print("OK" if ok else "FALHOU")
