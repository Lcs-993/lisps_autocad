# Lição 03 — GOROA → CARREADORES: criar carreadores e juntar talhões

> Material de treinamento do GeoIA. Recriação da ferramenta "Criar
> Carreadores" do AgroCAD (`GOROA`) como `CARREADORES`
> ([lisps/Carreadores.lsp](../../lisps/Carreadores.lsp)). Continua as lições
> [01](licao-01-gofur-crialinhas-desempenho.md) e [02](licao-02-gocon-conectalinhas.md).

## 1. O problema de domínio

**Carreadores** são as estradas internas da lavoura (em cana, tipicamente de
5 a 15 m). Eles dividem a gleba em talhões, dão acesso a plantio, tratos e
colheita (transbordo) e funcionam como aceiros. No projeto:

1. desenha-se o **eixo** de cada carreador (linha, arco ou polilinha, aberto
   ou em anel);
2. a ferramenta **corta** os talhões por uma faixa de Largura em volta do eixo;
3. o **polígono do carreador** fica no layer `CARREADORES` (cor 7), para as
   estatísticas ("Carreadores — Área Total / Média" no `GOSTS`).

O inverso, **Juntar Talhões**, desfaz carreadores: une talhões que se
encostam ou que estão separados por vãos de até a Largura. É usado ao
redesenhar o arruamento.

Os carreadores vêm **antes** das linhas: o `CRIALINHAS` sulca dentro de cada
talhão já cortado, e o `CONECTALINHAS` atravessa os carreadores de volta
quando a fileira continua do outro lado.

## 2. Especificação

- Tooltip: "Criar Carreadores (GOROA)". Diálogo `@ROADS_*` (pt-BR/en-US):
  "Largura (m)", "Criar Carreadores", "Juntar Talhões" (*Merge Fields*),
  "Manter os talhões originais", "Apagar Linhas de Eixos"; prompts
  "Selecione os talhões" e "Selecione os eixos dos carreadores".
- `CONFIG.AGROCAD`: `COR_LAY_CARREADORES 7`; layer `CARREADORES`.
- Decisões do usuário: **também desenhar o polígono do carreador**
  (recortado à área dos talhões); Juntar Talhões **fecha vãos de até a
  Largura**.

## 3. Algoritmo

### Criar Carreadores

1. **Faixa por eixo** (uma vez): eixo → LWPOLYLINE temporária, com LINE e ARC
   convertidos (bulge = tan(varredura/4)). Dois offsets ±L/2. Polígono =
   lado A + tampa + lado B invertido (bulges em ordem inversa e com sinal
   trocado) + tampa, e região ACIS. Eixo fechado: anel = região(externo) −
   região(interno).
2. **Para cada talhão**: são separadas as faixas cujo retângulo envolvente
   toca o do talhão. Se nenhuma toca, o talhão não é tocado. Se alguma toca:
   região(talhão) − união(cópias das faixas relevantes). Se a área não mudou,
   o talhão fica como estava (não é recriado).
3. **Polígono do carreador** = união(talhões cortados) ∩ união(todas as faixas).
4. **Região → polilinhas**: explode (recursivo, porque regiões compostas
   explodem em regiões), lê as arestas por `entget` (LINE e ARC, com o ARC
   convertido do OCS pela normal) e encadeia em laços fechados.

### Juntar Talhões: fechamento morfológico

```text
talhões --offset para fora (L/2 + 1 mm)--> união --offset para dentro (L/2 + 1 mm)--> talhão único
```

Com `OFFSETGAPTYPE = 0` (padrão), offsets de polilinha prolongam os cantos.
Fora e depois dentro devolvem as quinas originais, e só os vãos ≤ L se
fecham. Um laço contido em outro é **furo**, e o offset dele vai no sentido
de aumentar o furo.

## 4. Desempenho

| Decisão | Ganho |
| --- | --- |
| Booleanas no ACIS (nativo) em vez de recorte de polígonos em LISP | robustez com arcos, talhões côncavos e cruzamentos, e velocidade de código C++ |
| Faixa montada uma vez por eixo e copiada (`vla-Copy`) para cada talhão | 2 offsets por eixo, não por par talhão × eixo |
| Filtro por retângulo envolvente | cada booleana só vê as faixas próximas; talhão sem carreador custa uma comparação |
| Talhão não cortado não é recriado | sem `entmake`/`entdel` inútil |
| Arestas lidas por `entget`; encadeamento O(n) quando vêm em ordem | contornos GPS com milhares de arestas sem busca O(n²) |

## 5. Oráculo ([src/tools/oraculo_carreadores.py](../../src/tools/oraculo_carreadores.py))

As booleanas ACIS só rodam no AutoCAD; o oráculo testa o que é LISP puro:

```text
1. faixa: 200 eixos suaves, erro relativo máx. da área = 6.2e-15
2. laços: 100 casos (238 laços, arestas invertidas/embaralhadas), erro máx. = 1.6e-15
3. ARC -> bulge: 500 arcos, erro máx. (centro/raio/varredura) = 5.8e-10
```

O oráculo da faixa usa o **teorema de Pappus–Guldin para faixas**: se o raio
de curvatura do eixo for maior que L/2, a área da faixa de tampas retas é
exatamente **comprimento do eixo × largura**, qualquer que seja a curva. É um
resultado analítico independente da implementação, que pega erro de bulge,
de sentido ou de tampa.

## 6. Regras que o GeoIA deve reter

1. Carreador é parte do projeto de talhões: defina os eixos e a largura antes
   de sulcar.
2. Área de carreador = comprimento do eixo × largura (enquanto o raio for maior
   que L/2), uma checagem rápida de estatística.
3. Booleanas de polígonos: use o motor geométrico do CAD (ACIS/REGION) e
   reduza o que entra nele (filtro por retângulo envolvente, uma faixa por eixo).
4. "Juntar com tolerância" = fechamento morfológico (dilatar → unir → erodir).
5. Um eixo com raio de curva menor que L/2 gera faixa que se sobrepõe a si
   mesma (o offset interno falha). Nesse caso o comando avisa "eixo sem faixa
   válida", e o eixo deve ser suavizado.

## 7. Exercícios

1. Um eixo reto de 850 m com Largura 8 m: qual a área do carreador dentro de
   uma gleba que ele atravessa inteira? (Resposta: 6 800 m² = 0,68 ha.)
2. Por que o offset para fora usa L/2 + 1 mm, e não L/2?
3. Dois talhões separados por 10 m, Juntar com Largura 8 m: o que acontece?
4. Um eixo em curva com raio de 3 m e Largura 8 m: por que falha, e como
   corrigir?
