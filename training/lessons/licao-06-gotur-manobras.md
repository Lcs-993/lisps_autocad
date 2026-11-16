# Lição 06 — GOTUR → MANOBRAS: manobras de cabeceira

> Material de treinamento do GeoIA. Recriação do "Criar Manobras" do AgroCAD
> (`GOTUR`) como `MANOBRAS` ([lisps/Manobras.lsp](../../lisps/Manobras.lsp)).

## 1. O problema de domínio

No fim de cada linha a máquina **manobra** na cabeceira para entrar na
próxima. A forma da manobra depende da **separação s** entre as linhas e do
**raio de giro R** do conjunto máquina + implemento:

| Situação | Manobra | Profundidade na cabeceira |
| --- | --- | --- |
| s ≥ 2R | **U**: arco 90° + reta (s − 2R) + arco 90° | R |
| s < 2R | **ômega/bulbo**: sai para fora, volta pelo arco maior e entra | h + R, com h = √(4R² − (s/2 + R)²) |

O ômega gasta mais cabeceira e mais tempo. Por isso existem **padrões de
visita** que só fazem manobras largas:

- **a cada N**: g, g+N, g+2N…, depois o próximo grupo;
- **1-3-5-2-4**: em blocos de 5;
- **caracol** (*snail*/racetrack): em blocos de 2k, i → i+k → i+1 → i+k+1…,
  com k = ⌈2R/esp⌉ + 1, de modo que toda manobra dentro do bloco tenha
  s ≥ 2R (só U). As ligações entre blocos podem ser contínuas ou não.

A **bordadura** (contorno do talhão) com **afastamento A** limita a
cabeceira: as linhas são cortadas a A + profundidade da maior manobra, para
as manobras caberem dentro do talhão.

## 2. Especificação

Diálogo `@TURNS_*`: Raio de Giro Mínimo ou Ideal [R], Afastamento [A]
(*Boundary Gap*), Distância Máxima entre Vértices, Juntar Trechos
Conectados, Conectar Linhas com Manobra a Cada, Apagar Linhas Originais,
Cortar Linhas para Criar Afastamento, Manobras em Caracol, Manobras em
1-3-5-2-4. Prompts: bordadura, "Curvas na Ordem" e ponto de início. A
pergunta "manobras em caracol contínuas?" aparece em tempo de execução.
Decisão do usuário: U ou ômega pelo raio, com arcos exatos.

## 3. Geometria (local: x = lado da próxima linha, y = à frente)

- Pontas desencontradas: a linha que termina antes é prolongada em reta até
  a altura da outra (P′, Q′).
- U: (0,0) → (R,R) → (s−R,R) → (s,0), com bulges −tan(π/8), 0, −tan(π/8).
- Ômega: β = atan2(h, s/2 + R). Pontos (0,0), (−R + R·cosβ, R·senβ),
  (s + R − R·cosβ, R·senβ), (s,0), com bulges +tan(β/4),
  −tan((π + 2β)/4), +tan(β/4).
- Lado esquerdo: espelha x e troca o sinal dos bulges.
- Sentido alternado: a m-ésima linha do trajeto anda em sg·(−1)^m.

## 4. Desempenho

| Decisão | Ganho |
| --- | --- |
| Manobras 100% analíticas (bulges exatos) | sem `FILLET`/offset via COM; arcos exatos e arquivo leve |
| Vértices só se "Distância Máxima" > 0 | discretiza só quando a exportação exige |
| Ordem por coordenada lateral (vl-sort-i) | O(n log n) |
| Trajeto inteiro num `entmake` | sem `JOIN` |
| COM só no corte (1 `IntersectWith` por linha) | — |

## 5. Oráculo ([src/tools/oraculo_manobras.py](../../src/tools/oraculo_manobras.py))

```text
1. manobras: 1381 em U, 619 em ômega
   G1 (quebra de tangente máx.) = 1.9e-09 rad; raio: erro rel. máx. = 7.1e-11
   pontas: erro máx. = 1.8e-15 m; profundidade: erro máx. = 3.3e-11 m
2. ordens: cada linha uma vez = True; caracol: menor s/(2R) dentro do bloco = 1.000
```

O teste de profundidade falhou na 1ª versão do **oráculo**, que media só os
vértices: o arco maior do ômega passa acima deles. Corrigido o teste, a
fórmula h + R (usada no corte pela bordadura) confere.

## 6. Regras para o GeoIA

1. s ≥ 2R → U; s < 2R → ômega (gasta h + R de cabeceira).
2. Para evitar ômegas, use caracol com k = ⌈2R/esp⌉ + 1, ou pule linhas
   (a cada N, 1-3-5-2-4).
3. Cabeceira necessária = afastamento + profundidade da maior manobra.
4. Para medir a extensão de uma curva com arcos, amostre os arcos, e não só
   os vértices.

## 7. Exercícios

1. R = 6 m, linhas a 3 m: qual a manobra entre linhas vizinhas e a
   profundidade? (Ômega; h = √(144 − 56,25) ≈ 9,37 m, profundidade ≈ 15,37 m.)
2. Mesmo caso em caracol: qual k? (k = ⌈12/3⌉ + 1 = 5.) Qual a menor
   separação dentro do bloco? (4 × 3 = 12 m = 2R, ou seja, U.)
3. Quantas manobras há num talhão com 40 linhas num trajeto contínuo? (39.)
