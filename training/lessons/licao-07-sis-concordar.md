# Lição 07 — SIS_CONCORDAR: concordância de eixos de estradas

> Material de treinamento do GeoIA. Ferramenta nova (não é porte do AgroCAD),
> escrita com o conhecimento acumulado nas lições 01–06:
> [lisps/Concordancia.lsp](../../lisps/Concordancia.lsp).

## 1. O problema de domínio

Os eixos das estradas agrícolas (carreadores, estradas internas) formam uma
**rede**. Há dois casos:

- **Cruzamentos** em T, X ou L, onde a máquina faz a curva. Cada quadrante de
  giro (esquerda, direita) recebe um **arco de concordância** de raio R
  tangente às duas vias. Os eixos são **quebrados no nó**, para a rede ter
  topologia (cada trecho liga nó a nó).
- **Praças** (ilhas ou rotatórias): um obstáculo (árvore, caixa d'água,
  bebedouro, sede) no meio da via. O eixo **bifurca** antes da ilha,
  contorna os dois lados pelo **anel** (contorno da ilha + afastamento) e
  **funde** de novo depois. O trecho de eixo dentro do anel é removido, e
  tudo é quebrado nos nós e nas tangências.

## 2. Especificação (prompt do usuário)

- Raio de concordância por `getdist`, com o último valor lembrado (`setenv`).
- Arcos independentes; os eixos não são apagados, apenas quebrados. As novas
  entidades herdam layer, cor, tipo de linha, escala, espessura e
  transparência do eixo.
- `OSMODE`/`CMDECHO` restaurados, tudo num `UNDO` (`StartUndoMark`) com
  `*error*`.
- Decisões tomadas sem perguntar ao usuário: um comando só com
  `[Cruzamentos/Praca]`; anel = ilha deslocada de um **afastamento**
  (0 = a própria ilha é o eixo do anel); nos cruzamentos, a quebra nas
  tangências é opcional (padrão: só no nó, como pede o prompt).

## 3. Um motor só para os dois cenários

```text
curvas (DXF) -> segmentos (reta | arco com bulge)
  -> interseções por varredura em x
  -> nós (agrupados) -> ramos que saem do nó, ordenados pelo ângulo
  -> setores entre ramos vizinhos de curvas diferentes e < 180 graus
     -> concordância de raio R
  -> quebra: reconstrói cada curva em trechos (entmake), herdando as propriedades
```

A **praça** é o mesmo motor com duas regras a mais: só contam interseções
entre eixo e anel, e os ramos e trechos de eixo **dentro** do anel são
descartados. Do nó sobram três ramos (eixo de fora e os dois lados do anel),
o que dá duas concordâncias: a bifurcação na entrada e a fusão na saída.

### Concordância entre dois ramos

O setor vai, no sentido anti-horário, do ramo i até o ramo j. Cada ramo é
uma primitiva (reta ou círculo) **deslocada de R** para dentro do setor:

- reta: paralela à distância R;
- círculo de raio r: raio r − R se o centro está do lado do setor, senão
  r + R.

O **centro** do arco é a interseção das duas primitivas deslocadas. As
**tangências** são a projeção do centro em cada primitiva, e só valem se
caem no segmento do ramo, **à frente do nó**. Se não caem, o raio é grande
demais para aquele segmento, e o comando conta isso como aviso. Entre duas
retas o resultado é o clássico t = R / tan(φ/2).

### Ponto dentro do anel com arcos

O **número de voltas** é exato com arcos: soma-se o ângulo da corda visto do
ponto e corrige-se ±2π quando o ponto está na "lente" entre a corda e o
arco. Não precisa discretizar.

### Quebra com bulge parcial

Um trecho de arco de ângulo θ entre os parâmetros ka e kb tem bulge
tan(θ·(kb − ka)/4). LINE vira LINE, ARC ou CIRCLE vira ARC, e LWPOLYLINE
vira LWPOLYLINE (com elevação, largura e *linetype generation*).

## 4. Desempenho

| Decisão | Ganho |
| --- | --- |
| Geometria lida do DXF e resolvida analiticamente | zero `IntersectWith`, `BREAK` ou `FILLET` por eixo |
| Interseções por varredura em x (merge sort estável) | O((n + k) log n) em vez de O(n²) pares |
| Concordância por primitivas deslocadas | 1 interseção de retas ou círculos por quadrante |
| Quebra = reconstrução por `entmake` | sem comandos nem COM por trecho |
| COM só no `Offset` do anel | 2 chamadas por ilha |

Armadilha registrada: `vl-sort` pode descartar elementos "iguais". Por isso
os segmentos são ordenados com um merge sort próprio, que é estável e
mantém repetidos.

## 5. Oráculo ([src/tools/oraculo_concordar.py](../../src/tools/oraculo_concordar.py))

```text
1. interseções: 424, distância máx. entre os pontos nas duas curvas = 2.6e-12 m
2. concordâncias: 10541 (sem solução no segmento: 1451)
   |dist. centro-eixo - R| máx. = 2.2e-11 m; G1 (cos do ângulo raio x tangente) máx. = 2.5e-12
3. ponto dentro do anel: 8998 pontos, divergências = 0
4. bulge parcial: erro máx. = 9.3e-09 m
```

Os casos "sem solução" foram classificados. Ou a tangência cai fora do
segmento (o raio não cabe), ou as primitivas deslocadas não se cruzam
(curvas que se afastam, ou raio do eixo menor que R do lado côncavo). Entre
duas retas, toda concordância que cabe foi encontrada. Uma busca "ingênua"
com o centro no setor das tangentes acusou alternativas com r + R, mas elas
são falsas: com o eixo côncavo para o setor, o filete tem de ficar
**dentro** do círculo do eixo.

## 6. Regras para o GeoIA

1. Cruzamento: arcos só entre ramos de curvas **diferentes** e em setores
   < 180°. T dá 2 arcos, X dá 4 e L dá 1.
2. Concordância = interseção das primitivas deslocadas de R. Valide sempre se
   a tangência fica no segmento e à frente do nó.
3. Praça = cruzamento entre eixo e anel, descartando o que fica dentro do anel.
4. Topologia de rede: quebre os eixos nos nós (e, se quiser trechos
   nó-a-nó com as curvas, nas tangências).
5. Para lote, evite comandos (`BREAK`/`FILLET`) e COM: leia o DXF, calcule e
   use `entmake`.

## 7. Limitações conhecidas

- A tangência precisa cair no **mesmo segmento** do ramo. Polilinhas com
  vértices redundantes perto do nó podem impedir a concordância (aviso).
- Dois cruzamentos muito próximos podem gerar arcos que se sobrepõem.
  Não há verificação entre nós.
- Pontas que **quase** tocam (folga > 1e-6 do desenho) não viram nó.
  Feche-as antes (por exemplo com `AJUSTALIM` ou `EXTEND`).
- Só entidades com normal (0 0 1). LINE 3D é achatada na cota inicial.
- Arcos de nós entre eixos de layers diferentes herdam do primeiro ramo no
  sentido anti-horário.

## 8. Exercícios

1. T com ângulo de 90° e R = 12 m: a que distância do nó ficam as
   tangências? (t = 12 / tan 45° = 12 m.)
2. Cruzamento em X a 60° com R = 10 m: quanto vale t nos quadrantes de 60° e
   de 120°? (60°: 10 / tan 30° ≈ 17,3 m; 120°: 10 / tan 60° ≈ 5,8 m.)
3. Por que o eixo dentro do anel da praça é removido, e não apenas quebrado?
