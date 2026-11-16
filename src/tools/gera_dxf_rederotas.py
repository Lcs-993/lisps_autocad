"""Gera os DXF de teste do RA_VALIDAR / RA_CORRIGIR (lisps/RedeRotas.lsp).

Requer ezdxf (só para os testes):  pip install ezdxf
Uso: python src/tools/gera_dxf_rederotas.py [pasta]   (padrão: data/testes/rederotas)

rede_erros.dxf  (SIRGAS 2000 / UTM 23S, EPSG 31983, metros; camadas ESTRADAS e TRILHAS)
  Uma CADEIA de A (x0, y0) até B (x0+800, y0+150): a rota A->B só existe
  depois que TODOS os erros forem corrigidos (cada erro fica no caminho).

  #  erro plantado               onde (relativo a x0, y0)
  1  CRUZAMENTO sem vértice      L1 (0,0)-(100,0) x L2 (50,-30)-(50,60) em (50,0)
  2  T_SEM_VERTICE               L2 termina em (50,60) no meio de L3 (20,60)-(200,60)
  3  PONTA_SOLTA (2 m)           L4 (150,62)-(150,150) para 2 m acima de L3
  4  QUASE_COINCIDENTE (0,5 m)   L5 (150.4,150.3)-(200,150)-(300,150); L4 termina em (150,150)
  5  DUPLICADA                   L6 = cópia de L5 (camada TRILHAS)
  6  SOBREPOSTA                  L7 (250,150)-(350,150) sobre L5 de 250 a 300
  7  SEGMENTO_ZERO               L8 (350,150)(350,150)(400,150)
  8  NAO_SUPORTADA convertível   ARC (400,150)-(450,150), SPLINE (450..500), ELLIPSE (500..560)
  9  Z_VARIAVEL                  3D POLYLINE (560,150,10)-(600,150,12)-(650,150,15)
  10 ARCOS                       LWPOLYLINE (650,150)-(700,150) com bulge 0,3
  11 NAO_SUPORTADA fixa          bloco POSTE em (600,170) e TEXT em (300,170) na camada ESTRADAS
  12 FRAGMENTO                   consequência dos anteriores (antes de corrigir)
  L9 (TRILHAS) (700,150)-(800,150) termina em B.

rede_coord_local.dxf  - COORDENADAS (desenho perto de 0,0) e UNIDADE (INSUNITS = mm).
"""
import os
import sys

import ezdxf

X0, Y0 = 480000.0, 7506000.0


def P(x, y, z=None):
    return (X0 + x, Y0 + y) if z is None else (X0 + x, Y0 + y, z)


def rede_erros(arq):
    doc = ezdxf.new("R2018", setup=True)
    doc.header["$INSUNITS"] = 6
    for nome, cor in (("ESTRADAS", 7), ("TRILHAS", 3), ("OUTROS", 8)):
        doc.layers.add(nome, color=cor)
    msp = doc.modelspace()
    E = {"layer": "ESTRADAS"}
    msp.add_line(P(0, 0), P(100, 0), dxfattribs=E)                                   # L1
    msp.add_line(P(50, -30), P(50, 60), dxfattribs=E)                                # L2  cruza L1
    msp.add_lwpolyline([P(20, 60), P(200, 60)], dxfattribs=E)                        # L3  T de L2
    msp.add_line(P(150, 62), P(150, 150), dxfattribs=E)                              # L4  ponta solta
    msp.add_lwpolyline([P(150.4, 150.3), P(200, 150), P(300, 150)], dxfattribs=E)    # L5  quase
    msp.add_lwpolyline([P(150.4, 150.3), P(200, 150), P(300, 150)],
                       dxfattribs={"layer": "TRILHAS"})                              # L6  duplicada
    msp.add_line(P(250, 150), P(350, 150), dxfattribs=E)                             # L7  sobreposta
    msp.add_lwpolyline([P(350, 150), P(350, 150), P(400, 150)], dxfattribs=E)        # L8  segmento zero
    msp.add_arc(P(425, 150), 25, 0, 180, dxfattribs=E)                               # ARC (450)->(400)
    msp.add_spline([P(450, 150, 0.0), P(475, 165, 0.0), P(500, 150, 0.0)], dxfattribs=E)  # SPLINE
    msp.add_ellipse(P(530, 150, 0.0), major_axis=(30, 0, 0), ratio=0.5,
                    start_param=0.0, end_param=3.141592653589793, dxfattribs=E)      # ELLIPSE (560)->(500)
    msp.add_polyline3d([P(560, 150, 10.0), P(600, 150, 12.0), P(650, 150, 15.0)], dxfattribs=E)  # Z
    msp.add_lwpolyline([(X0 + 650, Y0 + 150, 0, 0, 0.3), (X0 + 700, Y0 + 150, 0, 0, 0)],
                       format="xyseb", dxfattribs=E)                                 # ARCOS
    msp.add_line(P(700, 150), P(800, 150), dxfattribs={"layer": "TRILHAS"})          # L9 -> B
    blk = doc.blocks.new("POSTE")
    blk.add_circle((0, 0), 0.5)
    msp.add_blockref("POSTE", P(600, 170), dxfattribs=E)                             # bloco
    msp.add_text("Estrada", dxfattribs={"layer": "ESTRADAS", "height": 2.0, "insert": P(300, 170)})
    msp.add_line(P(0, 200), P(800, 200), dxfattribs={"layer": "OUTROS"})             # fora da rede
    doc.saveas(arq)


def rede_local(arq):
    doc = ezdxf.new("R2018", setup=True)
    doc.header["$INSUNITS"] = 4                                                      # milímetros
    doc.layers.add("ESTRADAS")
    msp = doc.modelspace()
    msp.add_line((0, 0), (100, 0), dxfattribs={"layer": "ESTRADAS"})
    msp.add_line((100, 0), (100, 80), dxfattribs={"layer": "ESTRADAS"})
    doc.saveas(arq)


if __name__ == "__main__":
    pasta = sys.argv[1] if len(sys.argv) > 1 else os.path.join("data", "testes", "rederotas")
    os.makedirs(pasta, exist_ok=True)
    rede_erros(os.path.join(pasta, "rede_erros.dxf"))
    rede_local(os.path.join(pasta, "rede_coord_local.dxf"))
    print("ok", pasta)
