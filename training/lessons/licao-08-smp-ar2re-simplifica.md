# Lição 08 — SMP → SIMPLIFICAPL e AR2RE → SEGMENTARCOS: simplificar curvas e segmentar arcos

> Material de treinamento do GeoIA. Porte por comportamento de duas
> ferramentas do painel "Ajustes" do AgroCAD:
> [lisps/Simplifica.lsp](../../lisps/Simplifica.lsp) +
> [Simplifica.dcl](../../lisps/Simplifica.dcl).
> As duas também servem de **biblioteca** para as outras rotinas (por
> exemplo, o contorno do DESVIAOBS).

## 1. O problema de domínio

Curvas de nível, levantamentos de GPS, contornos importados de shape e
offsets sucessivos acumulam **vértices demais**: arquivos pesados, monitor de
plantio lento, *offset* e interseção lentos. O contrário também acontece:
muitos controladores de máquina (piloto automático, monitores) **não aceitam
arcos** (bulge), e a curva precisa virar segmentos de reta.

| AgroCAD | Nosso comando | O que faz |
| --- | --- | --- |
| `SMP` / `GOSMP` — "Reduzir pontos sem perda de qualidade" | `SIMPLIFICAPL` | remove vértices sem afastar a curva mais que a tolerância A |
| `AR2RE` (diálogo ARC2SEG) — "Converter arcos de polilinhas em segmentos" | `SEGMENTARCOS` | troca cada arco por cordas com os vértices sobre o arco |

Especificação tirada dos textos do AgroCAD (arquivos de idioma):
"Tolerância de Desvio [A] (m)", "Manter Objetos Originais", "Segmentar
Arcos", "Usar Medida Fixa em Metros".

## 2. SIMPLIFICAPL — Douglas-Peucker com garantia

1. Liga as duas pontas de um trecho por uma corda.
2. Acha o vértice **mais distante** do **segmento** (não da reta infinita).
3. Se a distância é maior que A, mantém esse vértice e repete nas duas
   metades. Se não, descarta todos os vértices internos.

A garantia é que **todo vértice removido fica a ≤ A do novo segmento**. O
comando informa o **maior desvio real**, que é sempre ≤ A.

Por que distância ao *segmento*: numa curva em grampo (cabeceira, meandro),
um vértice pode estar perto da reta infinita e longe da corda. Com a reta
infinita, o grampo seria "achatado".

### Regras da porta

- **Fixos**: as pontas das abertas e os vértices vizinhos de **arcos**. Os
  arcos sobrevivem intactos; para simplificá-los, use `SEGMENTARCOS` antes.
- **Fechada só de retas**: fixa o vértice 0 e o mais distante dele (o anel
  vira duas metades abertas). O anel nunca degenera: se sobrarem menos de 3
  vértices, fica como estava.
- A = 0 remove só vértices **repetidos e colineares**.
- `POLYLINE` 3D: desvio medido em 3D (a cota também conta). Curvas fit/spline
  e malhas são ignoradas pelo filtro da seleção.
- LWPOLYLINE é alterada com `entmod`, o que **mantém o handle**. POLYLINE é
  recriada com `entmake` (cabeçalho e xdata copiados), e o handle muda.

### Desempenho: DP iterativo sem copiar listas

O DP clássico é recursivo e copia sublistas. Em AutoLISP isso dá estouro de
pilha (uma espiral com 50 mil vértices tem profundidade 50 mil) e custo
O(n²) de cópia. A porta usa uma **pilha de trechos**:

```text
trecho = (ponteiro-para-o-início  número-de-registros  último-registro)
divide no vértice k:  (ini, k+1, rec_k)  e  (cauda_k, n-k, último)
```

`cauda_k` é o próprio `cdr` da lista original onde o máximo foi achado, então
nada é copiado. Os trechos saem da pilha da esquerda para a direita, e os
vértices mantidos já saem em ordem. O custo é O(n log n) no caso típico,
sem recursão.

## 3. SEGMENTARCOS — arco do bulge e número de cordas

### Do bulge ao arco

Para o arco de p0 a p1 com bulge b e corda c:

```text
θ (ângulo central, com sinal) = 4·atan(b)      b > 0 = anti-horário
r = c(1 + b²) / (4|b|)
centro = meio da corda + h·(normal esquerda),  h = c(1 − b²) / (4b)
flecha = b·c/2, para a DIREITA de p0→p1 quando b > 0
```

### Quantas cordas

- **Desvio máximo (flecha)**: a flecha de uma corda de ângulo α é
  r(1 − cos(α/2)). O menor n com r(1 − cos(θ/2n)) ≤ f é
  `n = ceil(θ / (2·acos(1 − f/r)))`. Com f ≥ 2r, basta n = 1.
- **Medida fixa**: `n = ceil(r·θ / L)`, com cordas **iguais**. Cada trecho
  de arco fica ≤ L, e as cordas ficam um pouco menores.

Os vértices novos ficam **sobre o arco**: a curva segmentada é *inscrita*.
As pontas originais são copiadas exatamente (sem erro de arredondamento), e
as larguras por vértice são interpoladas ao longo do arco.

Opcional: `ARC` e `CIRCLE` avulsos viram LWPOLYLINE no mesmo plano (normal
210 e elevação 38 copiadas). Um círculo recebe no mínimo 3 cordas.

## 4. Oráculo ([src/tools/oraculo_simplifica.py](../../src/tools/oraculo_simplifica.py))

```text
1. DP iterativo == recursivo: 400/400
2. desvio real - A: máx. 0.0e+00 m (<= 1e-9); |informado - real| máx. 0.0e+00 m
3. arcos preservados: True; anéis sem degenerar: True; redução média 66%
4. 200000 vértices (limite de recursão 200): 210131 -> 62408
5. arco do bulge: erro máx. 9.1e-13 m (pontas no círculo, meio = flecha à direita, fim = p1)
6. flecha/medida excedida em no máx. 0.0e+00 m; n mínimo: True
7. vértices sobre o arco: erro máx. 1.1e-13 m; pontas preservadas: True; larguras contínuas: True
```

Lição de oráculo: o primeiro "FALHOU" era do **teste**. O vértice repetido
reaproveitava o mesmo objeto de tupla, e a verificação por identidade casava
o vértice errado. Antes de mexer no algoritmo, confira se o oráculo mede o
que diz medir.

## 5. Uso como biblioteca (para o DESVIAOBS e outros)

```lisp
(sp:dp recs tol)                       ; -> (mantidos . maior-desvio)
(sp:simplifica-recs recs fechada tol)  ; fixos em arcos/pontas
(sp:segmenta-recs recs fechada 'FLECHA 0.05)
(sp:arco-geo p0 p1 bulge)              ; -> (centro raio ang0 theta)
(sp:n-arco raio theta 'MEDIDA 5.0)
;; recs = ((ponto largura-ini largura-fim bulge) ...)
```

Usos previstos no DESVIAOBS:
- trocar a "distância mínima entre vértices" do contorno por uma
  **tolerância de desvio**, que é geometricamente garantida;
- segmentar as transições para máquinas que não leem arcos.

## 6. Regras para o GeoIA

1. Simplificar = Douglas-Peucker com distância ao **segmento**. Informe o
   desvio real e não só a tolerância.
2. Preserve o que é exato: pontas, arcos e o anel fechado (≥ 3 vértices).
3. Em AutoLISP, nada de recursão profunda nem cópia de sublistas: use uma
   pilha de (ponteiro, contagem).
4. Arco → cordas: o número de cordas vem da flecha
   (`n = ceil(θ / 2acos(1 − f/r))`) ou da medida (`ceil(rθ/L)`). Os vértices
   ficam sobre o arco, e as pontas são copiadas, não recalculadas.
5. Para manter o handle, edite LWPOLYLINE com `entmod`. POLYLINE pesada
   precisa ser recriada.

## 7. Limitações conhecidas

- O DP não impede **autointerseção** em curvas muito apertadas com
  tolerância grande (é raro com A menor que a largura do grampo).
- Larguras **variáveis** ao longo de vértices removidos não são
  reinterpoladas: cada vértice mantido guarda as suas.
- Na POLYLINE recriada, o handle e a ordem de desenho mudam. Os grupos de
  reatores (102) não são copiados.
- Entidades fora do plano XY funcionam (tudo em OCS), mas o desvio de uma
  LWPOLYLINE é medido no plano dela.

## 8. Exercícios

1. Arco de raio 50 m e 90°, flecha 0,05 m: quantas cordas?
   (acos(1 − 0,001) ≈ 0,04472 rad; θ = 1,5708; n = ceil(1,5708 / 0,08944)
   = ceil(17,56) = 18.)
2. O mesmo arco com medida fixa de 5 m: (78,54 / 5 = 15,7, então 16 cordas
   de arco de 4,91 m.)
3. Por que uma fechada só de retas precisa de dois vértices fixos, e não
   de um?
