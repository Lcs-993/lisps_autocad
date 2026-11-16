# Lição 10 — IMPKML / IMPGEOJSON / IMPSHP: importar arquivos GIS com atributos

> Material de treinamento do GeoIA. Ferramenta nova:
> [lisps/ImpComum.lsp](../../lisps/ImpComum.lsp) (biblioteca comum) +
> [ImpKML.lsp](../../lisps/ImpKML.lsp), [ImpGeoJSON.lsp](../../lisps/ImpGeoJSON.lsp) e
> [ImpSHP.lsp](../../lisps/ImpSHP.lsp), um por formato, +
> [Importar.dcl](../../lisps/Importar.dcl).
> Fica no menu **Lisps → Importação** e no painel **Importação** da faixa de
> opções.

## 1. O problema de domínio

Os dados do campo chegam em formatos de GIS:
- limites e pontos do Google Earth, em **KML/KMZ**;
- exportações web e de APIs, em **GeoJSON**;
- dados de órgãos públicos, de máquinas e de taxa variável, em **SHP**.

Importar com qualidade exige três coisas:
1. **o sistema certo**: KML é sempre WGS 84, e o desenho está em UTM;
2. **os atributos** junto com cada entidade (nome do talhão, código, área);
3. **a geometria fiel**: polígonos com furo, multipartes, cota Z.

## 2. Arquitetura: um leitor por formato, uma biblioteca comum

```text
leitor (só lê o arquivo)  ->  (feições campos epsg-origem info)
   feição = (geoms props) ; geoms = ((PT|LN|AN pts) ...) ; props = (("campo" . valor) ...)
ic:importa: escolher arquivo -> ler -> diálogo (com os campos lidos) -> criar num UNDO
```

O diálogo só abre **depois** da leitura. Assim ele já mostra os campos reais
(para "uma camada por valor do campo" e para o rótulo) e o sistema detectado.

| Formato | Como lê | Sistema de origem |
| --- | --- | --- |
| KML | MSXML (DOM); `coordinates` classificado pelo elemento pai (Point, LineString, LinearRing) | sempre WGS 84 |
| KMZ | copia como .zip, `Expand-Archive` (síncrono via WScript.Shell), lê `doc.kml` | WGS 84 |
| GeoJSON | leitor JSON próprio, **por índice** no texto (`vl-string-elt`), sem lista de caracteres | membro `crs`; sem ele, WGS 84 (RFC 7946) |
| SHP | bytes por ADODB.Stream (safearray); inteiros LE/BE e **double IEEE 754 decodificado à mão** | `.prj`: AUTHORITY EPSG ou o nome (SIRGAS / WGS 84 / SAD 69 UTM) |

Atributos do KML: `nome`, `descricao`, `pasta` (o caminho das Folders) e os
campos de ExtendedData (`Data` e `SimpleData`). Do DBF: C, N, F, D
(AAAA-MM-DD) e L. O texto segue o `.cpg`; sem ele, vale UTF-8 se for válido,
senão Latin-1.

## 3. Conversão de coordenadas

1. **Map 3D** (incluído no Civil 3D): `ade_projsetsrc` / `ade_projsetdest` /
   `ade_projptforward`. O EPSG vira o código do Map, o mesmo do SISCOORD.
2. **Sem o Map**: fórmulas próprias de Transversa de Mercator (séries de
   Snyder) entre geográfico e UTM. WGS 84 e SIRGAS 2000 são tratados como
   iguais (diferença menor que 1 m). SAD 69 exige o Map, por causa da
   mudança de datum.
3. **Sem sistema conhecido**: as coordenadas ficam como estão, com aviso.

## 4. Atributos: Object Data (como o AgroCAD) ou XDATA

O AgroCAD trabalha sobre o Object Data dos SHP importados (ETQ, AJEL, LSHP),
por isso esse é o padrão:
- `ade_oddefinetab` cria uma tabela com o nome do arquivo. Uma tabela
  existente é reaproveitada se tiver os mesmos campos; se não tiver, ganha
  sufixo `_2`.
- `ade_odaddrecord` e `ade_odsetfield` gravam os valores.
- Os nomes de campos são limpos (letras, dígitos e `_`) e ficam únicos.
- O tipo vem do DBF ou é deduzido dos valores: inteiros → Integer, números →
  Real, o resto → Character.

Sem o Map, os atributos vão para **XDATA** (app `LISPS_ATRIB`), em pares
(1000 campo, 1000 valor) até cerca de 15 KB por entidade.

## 5. Entidades

- Ponto → POINT. Linha → LWPOLYLINE, ou POLYLINE 3D se "Usar Z" estiver
  ligado e a cota variar.
- Polígono → **uma polilinha fechada por anel**, furos incluídos. Cada uma
  recebe os atributos da feição.
- O ponto final repetido do anel é removido; um anel degenerado vira linha.
- Camada: nome do arquivo, ou "prefixo-valor" de um campo (ex.: a `pasta` do
  KML ou o `TALHAO` do SHP).
- Rótulo opcional com o valor de um campo: no ponto, no vértice do meio da
  linha ou na média do anel.

## 6. Oráculo ([src/tools/oraculo_importacao.py](../../src/tools/oraculo_importacao.py))

```text
1. TM própria x pyproj (SIRGAS 2000 UTM 18S-25S, 3000 pontos): ida 0.17 mm, volta 0.43 mm
2. double: 7010 valores, divergências = 0 (NaN -> nil); inteiros LE/BE: divergências = 0
3. UTF-8: divergências = 0; detecção UTF-8 x Latin-1 correta
4. .prj -> EPSG: 20/20 (WKT ESRI e OGC)
5. números JSON: erro relativo máx. 0
6. SHP/DBF com os mesmos deslocamentos da LISP x pyshp: 9 geometrias + atributos, divergências = 0
```

O oráculo pegou dois casos reais de DBF:
- número vazio gravado como `************`, que viraria 0;
- data vazia gravada como `00000000`.

Os dois agora viram vazio. Também mostrou que SAD69 23S pode vir como 29193
(código novo) ou 29183 (o que o Map e o Routes Analyzer conhecem); os dois
são aceitos.

## 7. Regras para o GeoIA

1. Ao importar, resolva o sistema de origem **sempre**: o KML é WGS 84 por
   definição, o GeoJSON sem `crs` também, e o SHP depende do `.prj`. Nunca
   cole coordenadas geográficas num desenho em UTM.
2. Os atributos acompanham **cada** entidade criada, inclusive cada anel e
   cada parte de multigeometria.
3. Polígono com furo é mais de uma polilinha fechada. Não descarte os furos.
4. Arquivos binários em AutoLISP: ADODB.Stream + safearray e decodificação
   IEEE 754 manual. Valide contra `struct`.
5. Arquivos grandes de texto: percorra por índice; não converta em lista de
   caracteres.

## 8. Limitações conhecidas

- Arquivos muito grandes: um GeoJSON de dezenas de MB ou um SHP com milhões
  de vértices fica lento no AutoLISP. Para esses, prefira o MAPIMPORT.
- O KML ignora `gx:Track`, `NetworkLink`, estilos e ícones. Um KMZ com
  vários .kml lê só o `doc.kml`, ou o primeiro.
- Os campos de Object Data são limitados a 254 caracteres; a descrição HTML
  do KML é cortada.
- Sem o Map, só há conversão entre geográfico WGS 84/SIRGAS e UTM WGS
  84/SIRGAS.

## 9. Exercícios

1. Um SHP sem `.prj`, com coordenadas como 480000, 7506000: qual EPSG você
   informa? (31983, SIRGAS 2000 / UTM 23S, se a fazenda estiver nessa zona.)
2. Por que `pasta` é um bom campo para "uma camada por valor" num KML do
   Google Earth?
3. Como um polígono com dois furos aparece no desenho, e onde ficam os
   atributos?

## 10. Importação e Exportação Avançada (GOIMP / GOEXP → GEOIMPORTAR / GEOEXPORTAR)

Os perfis em `C:\Tecgraf\AgroCAD\Config\IPF` e `EPF` mostram que o GOIMP e o
GOEXP do AgroCAD rodam sobre o **MAPIMPORT/MAPEXPORT do Map 3D**, guiados por
perfis XML. A porta ([lisps/GeoImpExp.lsp](../../lisps/GeoImpExp.lsp)) faz o
mesmo. Ela gera o perfil e roda o comando em linha de comando, na sequência
documentada no tutorial de script do Map:

```text
_-MAPIMPORT / _-MAPEXPORT  formato  arquivo  _Yes (Load Profile?)  perfil  _Proceed
```

- **GEOIMPORTAR**:
  - formatos do Map: SHP, KML/KMZ (código `OGCKML`), MIF, TAB, GML, DGN, SDF,
    SQLite…; o GeoJSON vai para os leitores próprios desta lição;
  - pergunta "Importar Atributos – deseja trazer também os dados dos
    objetos?";
  - camada pelo nome do arquivo ou por campo (`LayerNameType=Indirect`);
  - conversão para o sistema do desenho; polígonos como polilinhas fechadas.
- **Object Data do SHP**: segue o padrão do `TAXAS.ipf` do AgroCAD. Um
  `ProfileColumn` por campo do .dbf com `ColumnMappingType=MappedToOD` e
  `OutputTableName`, sobre uma tabela criada antes com os mesmos campos. Nos
  outros formatos, o nome da opção não está documentado. O comando confere o
  Object Data nas entidades novas, e o `GEOCALIBRA` copia os valores de um
  .ipf salvo no diálogo do MAPIMPORT.
- **GEOEXPORTAR**:
  - exporta por camadas, ou só os objetos selecionados. Neste caso usa
    cópias numa camada temporária, como o AgroCAD faz com a camada TEMP, e
    guarda a camada original num Object Data `LISPS_EXP`;
  - SHP, SDF, MIF e GML saem pelo MAPEXPORT, um arquivo por tipo de
    geometria;
  - os campos usam `:CAMPO@TABELA` com `CharacterDataType`,
    `IntegerDataType` e `DoubleDataType`, e a camada vai em `.LAYER`. Os
    nomes do DBF ficam com até 10 caracteres e únicos;
  - KML e GeoJSON saem por escritores próprios, em WGS 84.

As tags geradas foram conferidas contra os perfis reais do AgroCAD: o `.epf`
é idêntico, e o `.ipf` tem as mesmas tags.

Regra para o GeoIA: antes de reescrever um conversor de formatos, veja se a
plataforma já tem um motor (aqui, o Map 3D) e qual configuração ele aceita
(perfis XML). Isso cobre dezenas de formatos com a mesma qualidade da
ferramenta original.