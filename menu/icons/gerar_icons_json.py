#!/usr/bin/env python3
"""Regenera icons.json a partir dos UIDs reais de ../src/MenuGroup.cui.
Uso (dentro de menu/icons):  python gerar_icons_json.py
Lê cada MenuMacro, identifica o comando na macro (^C^CCOMANDO) e grava UID -> id do ícone.
Não altera o .cui."""
import json, re, os, xml.etree.ElementTree as ET
AQUI=os.path.dirname(os.path.abspath(__file__))
CUI=os.path.join(AQUI,'..','src','MenuGroup.cui')
CMD={
 "SISCOORD": "siscoord",
 "VERIFICAPROJ": "verificaproj",
 "VERIFICAPROJ_LIMPA": "ra-limpar",
 "TR-LE": "tr-le",
 "TR-LI": "tr-li",
 "TR-SU": "tr-su",
 "TR-TA": "tr-ta",
 "TR-TE": "tr-te",
 "TR-CO": "tr-co",
 "TR-GL": "tr-su",
 "TR-FI": "tr-co",
 "CRIALAYERS": "crialayers",
 "CORTALIM": "cortalim",
 "ESTENDELIM": "estendelim",
 "AJUSTALIM": "ajustalim",
 "APAGALIM": "apagalim",
 "SIMPLIFICAPL": "simplificapl",
 "SEGMENTARCOS": "segmentarcos",
 "REMOVENOS": "removenos",
 "PADRONIZAVERT": "padronizavert",
 "CRIALINHAS": "crialinhas",
 "CRIALINHASCFG": "crialinhas",
 "CONECTALINHAS": "conectalinhas",
 "CARREADORES": "carreadores",
 "SIS_CONCORDAR": "concordar",
 "REDE_VALIDAR": "rede-validar",
 "REDE_CORRIGIR": "rede-corrigir",
 "REDE_PROXIMO": "rede-proximo",
 "REDE_EXPORTAR": "rede-exportar",
 "REDE_CARREGA_RA": "ra-carregar",
 "RA_VERIFICAR": "rede-validar",
 "RA_CORRIGIR": "rede-corrigir",
 "RA_QUEBRAR": "ra-quebrar",
 "RA_PONTAS": "ra-pontas",
 "RA_JUNTAR": "ra-juntar",
 "RA_SEMCONEXAO": "ra-semconexao",
 "RA_PROXIMO": "rede-proximo",
 "RA_LIMPAR": "ra-limpar",
 "RA_DESENHAR": "ra-desenhar",
 "RA_CONFIG": "ra-config",
 "REDE_CONFIG": "ra-config",
 "RA_AJUDA": "ra-ajuda"
}
SPLIT={
 "RBN_FT_SPLIT_TR": "troca-layer",
 "RBN_FT_SPLIT_LIM": "limites",
 "RBN_FT_SPLIT_GEOM": "simplificapl",
 "RBN_FT_SPLIT_RAREDE": "ra-rede"
}
res={}; sem=[]
for el in ET.parse(CUI).getroot().iter():
    uid=el.get('UID') or el.get('UniqueId') or ''
    if not uid.startswith('MM_'): continue
    txt=' '.join(t for t in el.itertext())
    m=re.findall(r'\^C\^C_?([A-Za-z0-9_\-]+)',txt) or re.findall(r'\(c:([A-Za-z0-9_\-]+)\)',txt)
    cmd=next((c.upper() for c in m if c.upper() in CMD),None)
    if cmd: res[uid]=CMD[cmd]
    else: sem.append(uid)
res.update(SPLIT)
json.dump(res,open(os.path.join(AQUI,'icons.json'),'w'),indent=2,ensure_ascii=False)
print(len(res),'entradas gravadas em icons.json')
if sem: print('Macros sem ícone mapeado:',', '.join(sem))
