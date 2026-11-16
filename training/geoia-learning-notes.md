# Notas de aprendizado GeoIA

## Principais aprendizados

- automação de desenho reduz esforço repetitivo;
- regras de projeto são mais valiosas do que desenhos isolados;
- dados geoespaciais precisam estar conectados a lógica operacional;
- o conhecimento de CAD pode ser reutilizado para domínios agrícolas;
- a IA precisa de domínio, contexto e padrões para ser útil em projetos reais.

## Aplicação prática

Esses aprendizados devem guiar a construção do conjunto de conhecimento usado para treinar o GeoIA.

## Aprendizados do porte GOFUR → CRIALINHAS v2.1 (2026-11-14)

- uma família de linhas paralelas a uma referência reta é `v = d` num sistema
  local: as interseções com o talhão saem por fórmula, sem criar e apagar
  entidades via COM;
- o custo de uma ferramenta CAD está nas operações **por linha criada**
  (Offset, IntersectWith, puts de propriedade); a meta é zero no caso típico;
- só gerar linhas até a extensão real do talhão em cada lado da referência;
- robustez numérica é parte do projeto: faixa semiaberta nos vértices, valor
  exato nas pontas de arcos e queda para o método lento quando a premissa falha;
- validar com um oráculo independente (força bruta) antes de medir velocidade.

Detalhes: [lição 01](lessons/licao-01-gofur-crialinhas-desempenho.md).

## Aprendizados do porte GOCON → CONECTALINHAS (2026-11-14)

- conectar linhas da mesma fileira através dos carreadores elimina uma
  manobra por ligação e gera arquivos de guia menores;
- busca de vizinhos só é rápida com um limite derivado dos critérios (faixa
  lateral `Dmax·sen(desvio+ângulo)`), o que evita O(n²) sem perder pares;
- "a mesma fileira" em talhões vizinhos só existe se a deriva nas pontas for
  menor que meio espaçamento: o oráculo mostrou ligações com a fileira
  vizinha quando um talhão tinha 1° de desvio;
- rótulos traduzidos podem se contradizer ("Ângulo Mínimo" em pt-BR,
  "Maximum Angle" em en-US): compare os idiomas.

Detalhes: [lição 02](lessons/licao-02-gocon-conectalinhas.md).

## Aprendizados do porte GOROA → CARREADORES (2026-11-14)

- carreadores (estradas internas, 5 a 15 m) dividem a gleba em talhões e
  vêm antes da sulcação;
- área do carreador = comprimento do eixo × largura, enquanto o raio de curva
  for maior que meia largura (Pappus–Guldin para faixas), o que serve de checagem
  rápida e de oráculo de teste;
- booleanas de polígonos: use o motor geométrico do CAD (REGION/ACIS) e
  reduza a entrada (uma faixa por eixo, filtro por retângulo envolvente);
- juntar talhões com tolerância = fechamento morfológico (dilatar, unir,
  erodir).

Detalhes: [lição 03](lessons/licao-03-goroa-carreadores.md).

## Aprendizados do porte CSYS → SISCOORD (2026-11-14)

- todo projeto georreferenciado precisa do sistema de coordenadas definido
  antes de importar ou exportar dados de campo; no Brasil, SIRGAS 2000 / UTM;
- zona UTM = floor((longitude + 180) / 6) + 1;
- áreas e distâncias só em sistema projetado; unidades de exibição (ha, ac)
  são convertidas a partir do SI;
- listas regulares (famílias × zonas) podem ser geradas em vez de lidas.

Detalhes: [lição 04](lessons/licao-04-csys-siscoord.md).

## Aprendizados dos portes GOOBS → DESVIAOBS e GOTUR → MANOBRAS (2026-11-14)

- desvio de obstáculo = afastamento + raio mínimo + espaçamento preservado
  (contornos aninhados); se R > A, dilate de R e translade o contorno de
  R − A para longe do lado do desvio (folga exata A). A v1 usava folga
  max(A, R) e passava a 6 m com A = 3; o usuário pegou isso no Civil 3D,
  porque o oráculo só testava folga ≥ A;
- pontas: prolongue temporariamente para a concordância caber; ponta
  dentro da folga, interrompa; marque cada falha num layer de avisos com
  o motivo;
- manobra: s ≥ 2R dá U (profundidade R); s < 2R dá ômega (profundidade
  h + R); caracol com k = ⌈2R/esp⌉ + 1 só faz U dentro do bloco;
- cabeceira necessária = afastamento + profundidade da maior manobra;
- teste também o oráculo: medir só os vértices subestima curvas com arcos.

Detalhes: [lição 05](lessons/licao-05-goobs-desviaobs.md), [lição 06](lessons/licao-06-gotur-manobras.md).

## Aprendizados do SIS_CONCORDAR (ferramenta nova, 2026-11-14)

- concordância = interseção das primitivas deslocadas de R (reta paralela;
  círculo r ± R conforme o lado do centro); a tangência tem de cair no
  segmento e à frente do nó;
- cruzamento e praça usam o mesmo motor (nós, ramos ordenados, setores
  < 180° entre curvas diferentes); praça = eixo x anel, descartando o que
  fica dentro do anel (número de voltas exato com arcos);
- quebra sem `BREAK`: reconstruir com `entmake` e bulge parcial
  tan(θ·Δk/4);
- `vl-sort` pode descartar elementos: para ordenar registros, use um merge
  sort estável;
- desconfie de um "contraexemplo" do oráculo. As alternativas r + R que
  apareceram eram inválidas, e o critério de busca é que estava frouxo.

Detalhes: [lição 07](lessons/licao-07-sis-concordar.md).

## Aprendizados dos portes SMP → SIMPLIFICAPL e AR2RE → SEGMENTARCOS (2026-11-14)

- simplificar = Douglas-Peucker com distância ao **segmento**; informe o
  desvio real (≤ A), não só a tolerância;
- pontas, arcos e anéis fechados (≥ 3 vértices) são preservados: o que é
  exato não passa pelo DP;
- AutoLISP sem recursão profunda: pilha de (ponteiro para a lista,
  contagem, último), sem copiar sublistas — 200 mil vértices sem problema;
- arco → cordas: n = ceil(θ / 2acos(1 − f/r)) pela flecha ou ceil(rθ/L)
  pela medida; vértices sobre o arco, pontas copiadas e não recalculadas;
- `entmod` mantém o handle da LWPOLYLINE; POLYLINE pesada precisa de
  `entmake` (o handle muda);
- quando o oráculo falha mas cada verificação passa, suspeite do teste (aqui:
  identidade de objeto em vértices repetidos).

Detalhes: [lição 08](lessons/licao-08-smp-ar2re-simplifica.md).

## Aprendizados da ferramenta de rede de rotas REDE_* (2026-11-14)

- antes de validar para outra ferramenta, leia como ela monta o grafo: no
  Routes Analyzer a conexão é uma grade em lon/lat (não um raio de 1 m) →
  exigir coincidência exata;
- núcleo sobre um modelo em memória: a mesma análise serve para validar,
  corrigir, simular e testar fora do CAD;
- pares de geometria em lote por grade espacial com a regra do canto (cada
  par uma vez); a varredura em x degenera em estradas retas norte-sul;
- correção idempotente: sobra depois de cruzamento não é ponta solta; repetir
  os passos até estabilizar; testar "corrigir duas vezes";
- redes aleatórias acham o que o caso montado à mão não acha (ruído de 1e-13
  entre vértices "iguais", grupos de quase coincidentes > tolerância).

Detalhes: [lição 09](lessons/licao-09-rede-rotas.md).

## Aprendizados dos importadores IMPKML / IMPGEOJSON / IMPSHP (2026-11-14)

- um leitor por formato devolve feições num formato comum; diálogo, sistema,
  camadas, atributos e criação ficam numa biblioteca única (ImpComum.lsp);
- o diálogo abre depois da leitura, para mostrar os campos reais e o sistema
  detectado (KML e GeoJSON sem crs = WGS 84; SHP pelo .prj);
- atributos em Object Data do Map 3D (padrão do AgroCAD), com XDATA de reserva;
- binário em AutoLISP: ADODB.Stream + safearray, double IEEE 754 decodificado
  à mão e validado contra struct; texto grande percorrido por índice;
- DBF real tem "vazios" disfarçados (`****` em número, `00000000` em data).

Detalhes: [lição 10](lessons/licao-10-importacao.md).