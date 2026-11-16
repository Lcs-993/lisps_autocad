# Lição 09 — REDE_VALIDAR / REDE_CORRIGIR: preparar a geometria de uma rede de rotas

> Material de treinamento do GeoIA. Ferramenta nova (não é porte do AgroCAD):
> [lisps/RedeRotas.lsp](../../lisps/RedeRotas.lsp) +
> [RedeRotas.dcl](../../lisps/RedeRotas.dcl). Prepara as linhas do desenho
> para o Routes Analyzer (ou qualquer ferramenta que monte o grafo **por
> vértices**).

> Existe uma outra versão da mesma ideia,
> `routes_analyzer/tools/autocad/RA_REDE.lsp` (comandos `RA_*`, layer
> `RA_ERROS`). Para as duas poderem ser carregadas juntas e comparadas, esta
> versão usa o prefixo `rr:`, os comandos `REDE_*` e o layer `REDE_ERROS`.
> `REDE_CARREGA_RA` (menu "Rede - versão RA_REDE") carrega a outra.

## 1. O problema de domínio

Uma ferramenta de rotas transforma cada vértice num nó e liga linhas
**somente onde elas têm um vértice em comum**. No CAD o desenho "parece"
conectado, mas o grafo fica fragmentado por três erros clássicos:

- **cruzamento sem vértice**: as linhas se cruzam, mas nenhuma tem vértice
  no ponto de encontro (para o grafo, é um viaduto);
- **T sem vértice**: a linha chega no meio do segmento da outra, que não tem
  vértice ali;
- **ponta solta**: a linha termina a poucos metros da outra, sem tocar.

Com isso, paradas ficam "inalcançáveis" e as rotas dão voltas absurdas. A
ferramenta valida e corrige **só a geometria**. O usuário decidiu deixar
fora viadutos (que não devem conectar) e atributos de velocidade e sentido.

## 2. O que o código do Routes Analyzer faz de fato

Antes de escrever a ferramenta, lemos `viewer/js/network.js`, `io.js` e
`geo.js`. Quando o documento e o código divergem, vale o código.

1. **Os nós são células de uma grade em lon/lat**:
   `round(lon·kq), round(lat·kq)`, com kq = 111320 / tolerância. A célula
   tem 1 m na latitude, mas só tol·cos(lat) na longitude. Dois vértices a
   0,1 m podem cair em células diferentes. **Regra: coincidência exata.**
2. "Principal 97%" é a fração de **nós**, não de comprimento.
3. No GeoJSON, o `crs` só funciona para a lista do `epsgDef`: 4326, 4674,
   3857, 5880, UTM WGS 84 e SIRGAS 2000 UTM 31977–31985. Para outros, o
   arquivo é recusado como "coordenadas parecem projetadas".
4. Dois vértices seguidos na mesma célula viram uma aresta descartada
   (`nd === prev`). Um segmento curto é inofensivo para a conectividade.

## 3. Um motor só, sobre um modelo

```text
DWG -> modelo (listas): (id ename tipo fechada pts flags origem)
        bulge -> vértices (sp:segmenta-recs, máx. 5 m); ARC/SPLINE/ELLIPSE -> amostrados
analisa(modelo) -> quase, cruzamentos, T, sobreposições, pontas, zeros, componentes
REDE_VALIDAR  = analisa + marcadores (REDE_ERROS) + CSV
REDE_CORRIGIR = repete { analisa -> corrige o MODELO } ; simulação = não grava
              senão: confirmação -> grava num UNDO -> valida de novo
```

A simulação sai de graça, porque a correção nunca toca o desenho: ela muda o
modelo, e só a etapa de gravação escreve no DWG.

### Desempenho: grade espacial, não varredura em x

Uma estrada reta norte-sul densificada tem todos os segmentos no mesmo
intervalo de x, e a varredura em x vira O(n²). A porta usa uma **grade**:
cada item entra nas células que a caixa dele cobre, e o par é testado **uma
vez só**, na célula do canto (max xmin, max ymin) da interseção das caixas.
O union-find dos nós e das linhas usa `safearray`, que serve de vetor
mutável no AutoLISP.

### Regras de classificação

| Situação | Tolerância | Classe |
| --- | --- | --- |
| vértices a ≤ 1e-6 m | EPS0 | mesmo nó |
| vértice a ≤ 1 mm do interior de outro segmento | EPST | T |
| interiores que se cruzam (sinais das orientações) | — | cruzamento |
| 0 < d < 1 m, com ponta envolvida (ou d < 1 mm) | tolerância | quase coincidente |
| ponta de grau 1 a 1 mm < d ≤ X de outra linha | X = 3 m | ponta solta |
| colinear com sobreposição > 1 mm | EPST | sobreposta (duplicada, se cobre a menor inteira) |

Uma **sobra** depois de um cruzamento (a ponta passou 1 m da outra linha)
não é ponta solta. A cadeia da própria ponta, até X, já toca a linha
vizinha. Essa regra é o que torna a correção **idempotente**.

## 4. Correção (ordem importa)

1. **Segmentos zero**: remove os vértices repetidos.
2. **Unir quase coincidentes**: cada grupo vai para o vértice com mais linhas
   no nó (depois, o que não é ponta). O **nó inteiro** é movido, então todos
   os vértices naquela coordenada vão juntos e nada se desconecta.
3. **Pontas soltas**:
   - se a reta da ponta corta a linha vizinha a ≤ X, **estende** a ponta
     (a geometria continua colinear);
   - senão, **liga** a ponta ao ponto mais próximo;
   - nos dois casos, cria o vértice na linha vizinha.
4. **Cruzamentos e T**: insere a **mesma** coordenada nas duas linhas, em
   lote por linha (ordenado por segmento e parâmetro).
5. Unir de novo.
6. **Duplicados**: depois de inserir os vértices, as sobreposições viram
   segmentos idênticos. Fica o primeiro, e os outros são removidos, dividindo
   a linha se preciso.
7. Segmentos zero. **Repete até não mudar nada** (até 6 passes).

O sentido de digitalização nunca é invertido: só se inserem, movem ou
removem vértices.

## 5. Oráculo ([src/tools/oraculo_rederotas.py](../../src/tools/oraculo_rederotas.py))

O núcleo foi espelhado em Python
([rederotas_core.py](../../src/tools/rederotas_core.py)) e testado com o
DXF de teste ([gera_dxf_rederotas.py](../../src/tools/gera_dxf_rederotas.py)).
O grafo do viewer é emulado: reprojeção, grade e densificação de 25 m.

```text
1. validação: 25 erros/avisos; plantados não encontrados: nenhum; componentes = 7
2. correção: 15 alterações; depois: erros de topologia = 0; componentes = 1
3. viewer: 13 feições, 94 nós, componentes conexos = 1
4. rota A->B: existe; passa por 13/13 antigos pontos de erro
5. 2ª correção: 0 alterações
6. aleatório (300 redes): erro depois = 0; 2ª correção não vazia = 0;
   vértices originais a > 1 m da rede corrigida = 0 (maior 0.959 m)
```

O teste aleatório achou três falhas reais que o DXF de teste não pegava:
1. **Duplicado invisível.** Três linhas passavam pelo mesmo ponto com ruído
   de 1e-13. Na ordenação, um segmento de outra linha caía entre os dois
   duplicados, e a comparação só com o vizinho falhava. A solução foi uma
   janela em x, com as pontas normalizadas com tolerância.
2. **Grupo de quase coincidentes com mais de 1 m de extensão.** O grupo era
   ignorado inteiro. A solução foi unir só quem está até a tolerância do
   alvo; o resto fica para o passe seguinte.
3. **Convergência em 4 passes**, quando o limite era 3.

## 6. Regras para o GeoIA

1. Antes de validar para uma ferramenta, **leia como ela monta o grafo**. A
   grade de conexão não é um círculo de 1 m. Busque coincidência exata.
2. Separe núcleo e interface: o modelo em memória dá simulação, teste fora
   do CAD e gravação num UNDO único.
3. Pares de geometria em lote: use **grade** com a regra do canto, não
   varredura em x.
4. Inserir o vértice nas duas linhas com **a mesma** coordenada (a mesma
   lista), nunca recalculada.
5. Uma correção precisa ser idempotente. Teste "corrigir duas vezes" e use
   redes aleatórias, não só o caso montado à mão.

## 7. Limitações conhecidas

- Viadutos não são tratados: **todo** cruzamento sem vértice é corrigido
  (decisão do usuário). Para manter uma passagem em desnível, tire uma das
  linhas da seleção de camadas antes de corrigir.
- Bloco, texto e outros objetos nas camadas da rede só são **apontados**.
  Não viram linha nem são exportados.
- Larguras por vértice das polilinhas são descartadas nas linhas alteradas.
  Uma POLYLINE (2D/3D) alterada é recriada, e o handle muda.
- Só entidades no espaço do modelo e com normal (0 0 1).
- A faixa de coordenadas é conferida para UTM, 3857, 5880 e geográficas.
  Outros EPSG só recebem o aviso de "não reconhecido".

## 8. Exercícios

1. Duas linhas se cruzam em (10, 10) e uma terceira termina a 0,5 m desse
   ponto. O que o REDE_CORRIGIR faz, e em que ordem? (Insere o vértice
   (10, 10) nas duas linhas e, no passo de unir, leva a ponta da terceira até
   ele.)
2. Por que estender a ponta pela própria direção é melhor que ligá-la ao
   ponto mais próximo, quando a reta corta a linha vizinha?
3. Um vértice a 0,4 m de outro, com tolerância de 1 m, conecta no viewer?
   (Normalmente sim, mas não é garantido: depende da célula da grade. Por
   isso a ferramenta une os dois.)
