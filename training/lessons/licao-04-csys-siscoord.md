# Lição 04 — CSYS → SISCOORD: sistema de coordenadas e unidades do projeto

> Material de treinamento do GeoIA. Recriação do "Configurar coordenadas e
> unidades" do AgroCAD (`CSYS`) como `SISCOORD`
> ([lisps/SisCoord.lsp](../../lisps/SisCoord.lsp)).

## 1. Por que importa

Todo projeto agrícola georreferenciado precisa de um **sistema de
coordenadas** definido no desenho:

- a importação de dados de campo (GNSS, KML, shapefile) converte as
  coordenadas para a projeção do projeto;
- a exportação para o piloto automático (`GOEXP`) e para Lat/Long precisa
  saber de onde converter ("É necessário configurar o sistema de coordenadas
  deste projeto antes de exportá-lo");
- áreas e distâncias só valem em sistema **projetado** (UTM, em metros).

No Brasil, o padrão oficial é **SIRGAS 2000** (IBGE), com UTM por zona
(18 a 25; a maior parte das áreas agrícolas fica nas zonas 21 a 24 Sul).
SAD69 e Córrego Alegre são datums antigos, que aparecem em mapas e projetos
legados.

## 2. Especificação (pelo comportamento)

- Catálogo: `CSYS`, "Configura o sistema de coordenadas do projeto atual e
  permite alterar as unidades utilizadas".
- DCL `csys` / `add_csys` do AgroCAD: popup de sistemas, Excluir/Novo
  ("Código (Civil)" + "Descrição"), "Utilizar este sistema como padrão",
  "Unidades do Projeto" com 8 grupos e "Definir essas unidades padrão para
  novos projetos".
- Dados: `Config/COORDS-pt-BR.AGROCAD` (descrição + código da biblioteca
  Autodesk) e `Config/Units/*.txt` (uma unidade por arquivo:
  AG, LM, LG, SG, WP, WM, WG, VM).

## 3. Implementação

| Parte | Como |
| --- | --- |
| Lista de sistemas | **gerada**: LL84 + SIRGAS2000.UTM-zz{S,N} + SA-SIR-zz + UTM84-zz (1–60) + SAD69.UTM-zz + Corrego.UTM-zz, somada à lista do AgroCAD (se instalado) e aos sistemas do usuário (`config/COORDS_USUARIO.lsd`) |
| Aplicar | `ade_projsetwscode` (Map 3D, o mesmo CS de Configurações do Desenho do Civil 3D). Reserva: COM do Civil 3D `UnitZoneSettings.CoordinateSystemCode` (ProgID pela chave `CurVer` do registro, sem fixar a versão do Civil) |
| Unidades | gravadas **no desenho** (`vlax-ldata "LISPS" "UNIDADES"`); padrão em `config/UNIDADES_PADRAO.lsd`; API `lisps:unidade` / `lisps:converte` para as próximas rotinas (estatísticas) |
| INSUNITS | 6 (metros) ao aplicar um sistema projetado |

**Desempenho**: a lista (174 sistemas) é gerada uma vez por sessão, a partir
de padrões, e não lida de arquivo a cada abertura. O diálogo não carrega
imagem nem slide.

**Oráculo** ([src/tools/oraculo_siscoord.py](../../src/tools/oraculo_siscoord.py)):

```text
1. gerados=174  AgroCAD=141  faltando=nenhum
2. fatores de unidade: erro relativo máx. = 2.0e-16
```

Os fatores conferem com as definições exatas: 1 ac = 4046,8564224 m²,
1 ft = 0,3048 m, 1 mi = 1,609344 km, 1 lb = 0,45359237 kg, 1 short ton =
0,90718474 t, 1 gal EUA = 3,785411784 L.

## 4. Regras que o GeoIA deve reter

1. Antes de importar ou exportar dados de campo, confirme o sistema de
   coordenadas do projeto. No Brasil, use SIRGAS 2000 / UTM da zona da área.
2. Zona UTM: zona = floor((longitude + 180) / 6) + 1. Ex.: −48° dá
   floor(132/6) + 1 = 23, logo SIRGAS2000.UTM-23S.
3. Áreas e distâncias de projeto só em sistema projetado (metros), nunca em
   Lat/Long.
4. Unidades de exibição (ha, ac, km/h...) são separadas da unidade do desenho
   (m): guarde o valor no SI e converta só na saída.
5. "tons" é ambíguo (tonelada métrica × short ton americana). Rotule
   explicitamente.

## 5. Exercícios

1. Uma fazenda em Rio Verde (GO), longitude ≈ −50,9°: qual o código SIRGAS
   2000 UTM? (Resposta: zona 22, `SIRGAS2000.UTM-22S`.)
2. Um talhão de 312 400 m² em ha e em ac? (31,24 ha; 77,20 ac.)
3. Por que um projeto em SAD69 e outro em SIRGAS 2000 não se sobrepõem
   corretamente no desenho, mesmo na mesma zona?
