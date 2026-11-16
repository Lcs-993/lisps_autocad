# Base de conhecimento GeoIA

## Introdução

A base de conhecimento do GeoIA conecta três grandes pilares: geoprocessamento, desenho técnico e operação agrícola. Esse conjunto é a fonte de referência para entender como transformar dados de campo em projetos consistentes, operáveis e prontos para a agricultura moderna.

## Domínios principais

### 1. Projeto agrícola

O projeto agrícola envolve:

- organização da gleba;
- definição de talhões;
- orientação de linhas de plantio;
- distribuição de acessos e manobras;
- controle de declividade, drenagem e riscos ambientais.

### 2. Geometria e desenho técnico

A partir da experiência em AutoCAD e automação de desenho, o GeoIA deve reconhecer:

- padronização de layers, blocos e convenções;
- geração de geometria a partir de critérios;
- relação entre desenho e execução no campo;
- documentação técnica como parte do projeto.

### 3. Operação e pilotagem automática

A operação em campo depende de:

- largura de implementos;
- raio de giro;
- orientação de linhas;
- manobra em áreas com restrições;
- sistema de navegação e guiagem.

## Regras práticas

- áreas com maior declividade exigem cuidado especial em tráfego e erosão;
- a organização dos talhões deve considerar acessos, bordaduras e regras ambientais;
- a linha de cultivo deve ser compatível com a máquina e com o implemento;
- o desenho técnico deve ser legível, coerente e utilizável por humanos e sistemas.

## Saída esperada do GeoIA

O sistema deve ser capaz de produzir, ao menos, os seguintes elementos:

- mapa de área e limites;
- proposta de layout e talhões;
- rota ou linha de guia principal;
- avaliação de viabilidade operacional;
- documentação técnica resumida.

## Relação com AutoCAD

A experiência acumulada em ferramentas para AutoCAD oferece um conjunto de padrões importantes para o GeoIA:

- lógica de geometria;
- padronização de representação;
- automação de tarefas repetitivas;
- revisão visual de traçados e layouts.

Esses conhecimentos permitem que o GeoIA não trate o projeto apenas como dados, mas como uma solução técnica integrada e validada.

## Ferramentas CAD recriadas (referência técnica)

| Ferramenta AgroCAD | Comando LISPS | Arquivo | Documentação |
| --- | --- | --- | --- |
| GOFUR (Criar Linhas) | `CRIALINHAS` (v1, em uso) | `lisps/CriaLinhas.lsp` | — |
| GOFUR + OFVA/CPV (versão otimizada, arquivada) | `CRIALINHAS` v2.1 | `lisps/legado/CriaLinhas_v2.lsp` | [lição 01](../../training/lessons/licao-01-gofur-crialinhas-desempenho.md) |
| GOCON (Conectar Linhas entre Talhões) | `CONECTALINHAS` | `lisps/ConectaLinhas.lsp` | [lição 02](../../training/lessons/licao-02-gocon-conectalinhas.md) |
| GOROA (Criar Carreadores / Juntar Talhões) | `CARREADORES` | `lisps/Carreadores.lsp` | [lição 03](../../training/lessons/licao-03-goroa-carreadores.md) |
| CSYS (Coordenadas e Unidades) | `SISCOORD` | `lisps/SisCoord.lsp` | [lição 04](../../training/lessons/licao-04-csys-siscoord.md) |
| GOOBS (Desviar de Obstáculos) | `DESVIAOBS` | `lisps/Obstaculos.lsp` | [lição 05](../../training/lessons/licao-05-goobs-desviaobs.md) |
| GOTUR (Criar Manobras) | `MANOBRAS` | `lisps/Manobras.lsp` | [lição 06](../../training/lessons/licao-06-gotur-manobras.md) |
| — (ferramenta nova) | `SIS_CONCORDAR` | `lisps/Concordancia.lsp` | [lição 07](../../training/lessons/licao-07-sis-concordar.md) |
| SMP / GOSMP (Reduzir pontos sem perda de qualidade) | `SIMPLIFICAPL` | `lisps/Simplifica.lsp` | [lição 08](../../training/lessons/licao-08-smp-ar2re-simplifica.md) |
| AR2RE (Converter arcos de polilinhas em segmentos) | `SEGMENTARCOS` | `lisps/Simplifica.lsp` | [lição 08](../../training/lessons/licao-08-smp-ar2re-simplifica.md) |
| — (ferramenta nova, rede de rotas) | `REDE_VALIDAR` / `REDE_CORRIGIR` / `REDE_PROXIMO` / `REDE_EXPORTAR` | `lisps/RedeRotas.lsp` | [lição 09](../../training/lessons/licao-09-rede-rotas.md) |
| — (ferramenta nova, importação) | `IMPKML` / `IMPGEOJSON` / `IMPSHP` | `lisps/ImpComum.lsp` + `ImpKML.lsp` / `ImpGeoJSON.lsp` / `ImpSHP.lsp` | [lição 10](../../training/lessons/licao-10-importacao.md) |
| GOIMP / GOEXP (Importação / Exportação Avançada) | `GEOIMPORTAR` / `GEOEXPORTAR` | `lisps/GeoImpExp.lsp` | [lição 10](../../training/lessons/licao-10-importacao.md) |
| KLA, CFT, RCFT, CPCFT, CFL, VV, JDBEX, JDBIN, JDHBEX, JDHBIN, JDABC, JDABL, JDLIN, CGLE | `CLA_*` | `lisps/Classifica.lsp` | [lição 11](../../training/lessons/licao-11-classificacao-cft.md) |

Regra geral: em linhas guias e de plantio, as pontas terminam no limite do
talhão, sem duplicatas, ByLayer, nos layers `GUIDELINES` / `CROPLINES`.
