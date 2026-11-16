# Lição 05 — GOOBS → DESVIAOBS: desviar linhas de obstáculos

> Material de treinamento do GeoIA. Recriação do "Desviar de Obstáculos" do
> AgroCAD (`GOOBS`) como `DESVIAOBS` ([lisps/Obstaculos.lsp](../../lisps/Obstaculos.lsp)).

## 1. O problema de domínio

Dentro do talhão há **obstáculos** que a máquina não pode atravessar:
árvores isoladas, postes e torres, afloramentos de rocha, cupinzeiros,
lagoas, marcos. As linhas guias precisam **contorná-los** com:

- **afastamento**: folga mínima entre o obstáculo e a máquina/implemento;
- **raio mínimo**: nenhuma curva mais fechada que o raio de giro da máquina
  com o implemento;
- **espaçamento preservado**: se várias linhas paralelas passam pelo
  obstáculo, os desvios ficam **aninhados**, um por fora do outro, à mesma
  distância das linhas, sem sobreposição (para não haver falha nem dupla
  aplicação).

Alternativa: **apenas interromper** as linhas no afastamento (a máquina
levanta o implemento e passa), ou **contornar todo o obstáculo** (a linha dá
a volta completa e segue, o que serve para aplicar em volta dele).

## 2. Especificação

Diálogo `@OBSTACLES_*` (pt-BR/en-US): Raio Mínimo (m), Afastamento (m),
Distância Mínima entre Vértices (m), Apenas Interromper as Linhas,
Contornar Todo o Obstáculo (*Go All the Way Around*), Indicar Lado
Preferencial, Selecionar as Linhas Manualmente; prompts "Selecione os
obstáculos" e "Selecione as linhas a serem desviadas". Decisão do usuário:
**contornos aninhados**.

## 3. Geometria

Para cada obstáculo O, com as linhas que cruzam a folga-base:

1. **Lado do desvio**: o clicado, ou aquele em que a soma dos deslocamentos
   laterais das linhas é menor.
2. **Aninhamento**: a linha mais perto do lado do desvio (y_top) recebe o
   contorno a `base`. A linha i recebe `base + |y_top − y_i|`, preservando o
   espaçamento original.
3. **Folga = Afastamento, exata (v2).** A v1 usava folga-base
   max(Afastamento, Raio), o que corrigia a sobreposição das linhas
   aninhadas. Só que, com A = 3 m e R = 6 m, a linha passava a **6 m** do
   obstáculo, e não aos 3 m configurados (achado nos testes no Civil 3D).
   A v2 dilata o obstáculo de M = max(A, R), ou max(A, R − ro) num círculo
   de raio ro, para nenhuma curva ficar mais fechada que R. Depois
   **translada** o contorno de M − A para longe do lado do desvio. Como
   B(p, A) ⊂ B(p − (M − A)·w, M), o contorno contém a folga A e a toca na
   direção do desvio: a folga real é A, com raio ≥ R e aninhamento exato
   (todos os contornos têm a mesma translação).
4. **Contorno suavizado**: dilatação de O de M + d_i com cantos
   arredondados (`OFFSETGAPTYPE = 1`), seguida de fechamento por R (cantos
   côncavos também com raio R) e da translação do item 3.
5. **Transições de raio R**: o centro do arco fica na interseção da linha
   deslocada de R (lado do desvio) com o contorno dilatado de R. As
   tangências são a projeção do centro na linha e o ponto do contorno mais
   perto do centro. O sentido de giro (horário ou anti-horário) depende do
   lado do desvio **em relação ao sentido de desenho da linha**, e não ao
   eixo global, porque linhas vizinhas podem ter sido desenhadas em sentidos
   opostos.

6. **Pontas** (v2):
   - Se a tangência da concordância passa da ponta, a linha é **prolongada
     temporariamente** pelas tangentes das pontas. O resultado começa (ou
     termina) no ponto de tangência, e quanto a linha cresceu é informado.
   - Se a ponta está **dentro da folga**, o desvio é impossível: a linha é
     interrompida na folga. `ob:interrompe` agora trata 1, 2 ou mais
     cruzamentos pelo ponto médio de cada trecho, com teste exato de ponto
     dentro (número de voltas com arcos).
7. **Diagnóstico** (v2): cada falha ou ajuste deixa uma cópia da linha e
   um texto com o motivo no layer `DESVIAOBS_AVISOS` (vermelho, não plota),
   e eles ficam selecionados ao final. Motivos: ponta dentro do
   afastamento, prolongada X m, raio incompatível (a concordância não
   alcança o contorno), tangência inválida (entrada e saída se sobrepõem,
   ou um toque fora da distância R do centro), falta de extensão, falha
   no contorno.

## 4. Desempenho

| Decisão | Ganho |
| --- | --- |
| Candidatos por retângulo envolvente lido do DXF | sem COM por linha e **sem depender da vista** (`ssget "_C"` só acha o que está na tela) |
| `IntersectWith` só nos candidatos do obstáculo | O(candidatos), não O(todas as linhas) |
| Contorno só para as linhas que cruzam | 3 offsets por linha desviada |
| Linha nova montada em listas, 1 `entmake` | sem `PEDIT`/`JOIN` |

## 5. Oráculo ([src/tools/oraculo_desviaobs.py](../../src/tools/oraculo_desviaobs.py))

Caso analítico (obstáculo circular, linhas paralelas, 300 combinações de R,
A, e e raio do obstáculo):

```text
casos=3054
1. G1 nas junções: maior quebra de tangente = 5.6e-16 rad
2. raio mínimo respeitado: True
3. folga < Afastamento em no máx. 8.9e-15 m; 1ª linha: |folga - A| máx. = 8.9e-15 m
4. espaçamento entre caminhos aninhados (topo): erro máx. = 1.2e-14 m
5. polígono: folga < A em no máx. 0.0e+00 m; folga na direção do desvio - A = 4.1e-06 m
```

A v1 do oráculo só verificava folga ≥ A, e por isso não pegou a folga de
6 m. A v2 exige folga **igual** a A na 1ª linha. Lição: o oráculo tem de
testar o que o usuário especificou ("a folga informada"), e não só um
limite que a implementação já satisfaz.

## 6. Regras para o GeoIA

1. Desvio de obstáculo = afastamento + raio mínimo + espaçamento preservado
   (contornos aninhados).
2. Se o raio de giro for maior que o afastamento, **não** aumente a folga.
   Dilate de R e translade o contorno de R − A para longe do lado do
   desvio: a folga continua A e nenhuma curva fica mais fechada que R.
5. Concordância que não cabe na linha: prolongue temporariamente pelas
   tangentes das pontas. Ponta dentro da folga: interrompa. Em qualquer
   falha, marque a linha e diga o motivo.
3. Sentido de giro de uma curva depende do sentido de percurso da linha.
4. Seleções por janela (`_C`/`_W`) dependem da vista; para processamento em
   lote use os dados do DXF.

## 7. Exercícios

1. Afastamento 3 m, raio 6 m, linhas a 3 m: a que distância do obstáculo
   passam a 1ª, a 2ª e a 3ª linha? (v2: 3, 6 e 9 m, com o contorno transladado 3 m para longe; na v1 eram 6, 9 e 12 m.)
2. Por que não deixar todas as linhas no mesmo contorno?
3. Quando é melhor apenas interromper as linhas?
