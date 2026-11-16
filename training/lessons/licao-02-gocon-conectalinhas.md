# Lição 02 — GOCON → CONECTALINHAS: conectar linhas entre talhões

> Material de treinamento do GeoIA. Mostra como a ferramenta "Conectar Linhas
> entre Talhões" do AgroCAD (`GOCON`) foi recriada como `CONECTALINHAS`
> ([lisps/ConectaLinhas.lsp](../../lisps/ConectaLinhas.lsp)), com foco em
> desempenho. Continua a [lição 01](licao-01-gofur-crialinhas-desempenho.md).

## 1. O problema de domínio

Depois do `GOFUR`/`CRIALINHAS`, cada talhão tem as suas linhas guias e de
plantio, recortadas no limite. Entre dois talhões vizinhos há um
**carreador** (estrada interna de 5 a 15 m). Se a fileira continua do outro
lado, a máquina pode atravessar o carreador sem manobrar.

Unir essas linhas numa **polilinha contínua** traz três ganhos:

- **menos manobras**: cada ligação elimina um fim de linha, ou seja, uma
  manobra de cabeceira (no AgroCAD aparece nas estatísticas `GOSTS` como
  "Linhas Conectadas — Número de Manobras");
- **arquivos de guia menores e mais limpos** para o piloto automático (`GOEXP`);
- continuidade da fileira, que ajuda o alinhamento do plantio entre talhões.

## 2. Especificação (pelo comportamento, não pelo código)

Fontes usadas, todas de interface ou de dados:

- tooltip do menu: "Conectar Linhas entre Talhões (GOCON)";
- strings do diálogo `@CONNECT_*` em
  `Interface/Languages/pt-BR/STR/pt-BR.txt`: "Critérios", "Ângulo Mínimo"
  (em inglês: **"Maximum Angle"**, o que mostra que o pt-BR estava trocado),
  "Espaçamento (m)", "Apagar Linhas Originais", "Selecionar Linhas para
  Otimizar";
- decisão do usuário: unir numa polilinha só; critério = ângulo + desvio
  lateral, ficando com a ponta mais próxima.

Lição para o GeoIA: quando os rótulos traduzidos se contradizem, compare os
idiomas. O arquivo en-US resolveu "Mínimo × Máximo".

### Critérios de ligação de uma ponta A (linha a) com uma ponta B (linha b)

| Critério | Regra | Por quê |
| --- | --- | --- |
| Linhas diferentes | a ≠ b | não fecha a própria linha |
| Distância | \|AB\| ≤ Distância Máxima | não atravessa um talhão onde falta a fileira |
| Direções | ângulo(dir. de saída em A, oposto da dir. de saída em B) ≤ Ângulo Máximo | as duas linhas seguem o mesmo rumo |
| Deflexão | ângulo(saída A, AB) ≤ Ângulo Máximo e ângulo(saída B, BA) ≤ Ângulo Máximo | a máquina não faz curva fechada no carreador |
| Desvio lateral | \|AB\|·\|sen(AB − saída)\| ≤ Espaçamento/2, nas duas pontas | não liga com a fileira vizinha |
| Escolha | pares mais curtos primeiro, uma ligação por ponta, sem ciclo | "vale a ponta mais próxima" |

A **Distância Máxima** foi acrescentada à interface original pelos dois
motivos da tabela. Sem ela, se a fileira faltar no talhão do meio, a linha
do 1º talhão seria ligada à do 3º, atravessando o 2º. Ela também limita a
busca, o que é a base do desempenho.

## 3. Algoritmo e desempenho

Ingênuo: comparar cada ponta com todas as outras custa O(n²). São 2 pontas
por linha, então 2 500 linhas viram 5 000 pontas e 12,5 milhões de pares,
o que leva dezenas de segundos em AutoLISP.

`CONECTALINHAS`:

1. **Dados DXF puros**: `entget` de cada linha (vértices, bulges, layer),
   direção de saída de cada ponta por fórmula, com tangente de arco = corda
   ± 2·atan(bulge). Nenhuma chamada COM.
2. **Direção dominante** θ₀: média axial (ângulo dobrado) ponderada pelo
   comprimento, que não depende do sentido em que as linhas foram desenhadas.
3. **Varredura por faixa lateral**: cada ponta recebe y = coordenada
   perpendicular a θ₀, e as pontas são ordenadas por y. Um par válido satisfaz
   \|Δy\| ≤ w = Dmax·sen(desvio_máx + Ângulo Máximo), então cada ponta só é
   comparada com as seguintes até y + w. Como esse limite é **garantido** pelos
   critérios, nenhum par válido se perde.
4. **Casamento guloso sem union-find**: para cada ponta livre, guarda-se a
   "outra ponta livre da sua cadeia". Ligar A–B só fecha ciclo se
   outra(A) = B. Depois da ligação, outra(outra(A)) = outra(B) e vice-versa,
   em O(1) por ligação.
5. **Montagem**: percorre cada cadeia a partir de uma ponta livre, invertendo
   as linhas percorridas ao contrário (vértices invertidos e bulges com sinal
   trocado), e insere um segmento reto (bulge 0) em cada carreador. Se as
   pontas já se tocam, não duplica o vértice. Um único `entmake` por cadeia,
   com layer, cor, tipo e espessura da 1ª linha. As originais saem com `entdel`.

### Oráculo ([src/tools/oraculo_conectalinhas.py](../../src/tools/oraculo_conectalinhas.py))

Projeto sintético: 3 talhões em sequência, carreadores de 8 m, 60 fileiras a
1,5 m, fileiras faltando (inclusive duas seguidas no talhão do meio),
pequenos desvios de direção entre talhões, ruído de ±5 cm nas pontas, sentido
de desenho aleatório e referência girada 23°.

```text
pontas=354  pares testados: varredura=10352  força bruta=62481
candidatos iguais à força bruta: True (115 pares)
linhas=177 -> polilinhas=62 (esperado 62); cadeias corretas: True
```

A varredura testa ~6× menos pares e encontra **exatamente** os mesmos
candidatos. A diferença cresce com o projeto: com o dobro de fileiras, a
força bruta testa 4× mais pares e a varredura só 2×.

| Fileiras | Pontas | Pares (varredura) | Pares (força bruta) | Redução |
| --- | --- | --- | --- | --- |
| 60 | 354 | 10 352 | 62 481 | 6× |
| 120 | 714 | 21 564 | 254 541 | 12× |
| 240 | 1 434 | 44 002 | 1 027 461 | 23× |

**Caso real que o oráculo revelou**: no primeiro cenário de teste, um talhão
tinha fileiras 1° tortas em 232 m. As pontas se deslocavam 2 m, mais que um
espaçamento, e o algoritmo ligou cada fileira à **vizinha**, que estava
alinhada. Pelos critérios isso está correto. A lição de domínio é que
fileiras de talhões vizinhos só são "a mesma fileira" se a deriva nas pontas
for menor que meio espaçamento. Quando os talhões foram traçados com
referências diferentes, é preciso conferir o resultado ou redesenhar com a
mesma referência.

## 4. Regras que o GeoIA deve reter

1. Conectar linhas entre talhões reduz manobras: conte as ligações como
   "manobras evitadas" nas estatísticas.
2. Toda busca de vizinhos precisa de um limite **derivado dos critérios**
   (faixa lateral, distância máxima). Sem limite, o custo é O(n²).
3. Um limite de distância também é regra de projeto: não ligar através de
   talhão sem a fileira.
4. Direção de linha é **axial**: use média de ângulo dobrado, porque o sentido
   do desenho é arbitrário.
5. Para juntar pares sem formar ciclos, basta guardar a outra ponta livre de
   cada cadeia, sem union-find.
6. Valide contra força bruta antes de confiar na otimização, e desconfie
   também do cenário de teste: ele pode estar errado, e não o código.

## 5. Exercícios

1. Com Espaçamento 1,5 m, uma ligação de 10 m com desvio lateral de 0,6 m é
   aceita? E com 0,9 m? (Resposta: sim, pois 0,6 ≤ 0,75; não, pois 0,9 > 0,75.)
2. Por que a faixa w usa o desvio máximo das linhas em relação a θ₀, além do
   ângulo máximo?
3. Uma fileira falta no talhão do meio, com 230 m de comprimento. Com
   Distância Máxima 30 m, o que acontece com as fileiras dos talhões 1 e 3?
4. Proponha uma extensão: conectar com **manobra** (arco de giro) as pontas
   vizinhas do **mesmo** talhão (o `GOTUR` do AgroCAD). Que critério
   substitui o desvio lateral?
