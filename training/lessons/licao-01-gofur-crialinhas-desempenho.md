# Lição 01 — GOFUR → CRIALINHAS v2.1: recriar uma ferramenta CAD com foco em desempenho

> Material de treinamento do GeoIA. Registra *como* a ferramenta de linhas de
> sulcação/plantio do AgroCAD (comando `GOFUR`) foi recriada como
> `CRIALINHAS` e,
> principalmente, *por que* a versão 2.1 é mais rápida.
>
> **Situação (2026-11-14):** a pedido do usuário, o menu voltou a usar o
> CRIALINHAS **v1** ([lisps/CriaLinhas.lsp](../../lisps/CriaLinhas.lsp)). A v2.1
> descrita aqui está arquivada em
> [lisps/legado/CriaLinhas_v2.lsp](../../lisps/legado/CriaLinhas_v2.lsp) e
> não é carregada; a lição continua válida como material de treinamento.

## 1. O problema de domínio

Em cana-de-açúcar (e outras culturas em linha), o projeto de sistematização
desenha, para cada talhão:

| Elemento | O que é | Layer padrão |
| --- | --- | --- |
| Linha de referência | reta ou curva que orienta o plantio (ex.: maior lado do talhão, nível, carreador) | — |
| Linhas guias (sulcação) | passadas da máquina; offsets da referência numa **sequência de espaçamentos** (ex.: 1× 3,0 m, (R)epetir) | `GUIDELINES` (cor 2) |
| Linhas de plantio | N linhas por guia, espaçadas entre si (ex.: 2 × 1,5 m — plantio em linha dupla/"W") | `CROPLINES` (cor 3) |
| Cabeceira | N passadas que acompanham o contorno, para dentro ou para fora | layer da guia |

Regras operacionais:

- as linhas terminam **exatamente** no limite do talhão; a máquina não pode
  receber uma linha que invade o carreador;
- não pode haver linhas duplicadas; uma linha de plantio que cai sobre uma
  guia, ou sobre o plantio da guia vizinha, é eliminada;
- a 1ª passada de cabeceira pode ficar a meio espaçamento do contorno (recuar);
- as linhas ficam ByLayer, para que a exportação para o piloto automático
  seja por layer.

## 2. Como recriar sem o código-fonte

O AgroCAD é distribuído compilado (`Core.fas`). A recriação foi feita **pelo
comportamento**, e não por descompilação:

1. **Catálogo de comandos**: `src/tools/agrocad_catalog.py` lê o `.cuix` do
   AgroCAD e lista as 389 macros
   ([references/agrocad/catalogo-comandos.md](../../references/agrocad/catalogo-comandos.md)).
   `GOFUR` aparece como "NOVO Criar Linhas".
2. **Diálogo (DCL) e textos de ajuda**: dão os parâmetros (sequência
   Quantidade × Distância, Repetir, plantio, cabeceira, predefinições `.OFV`).
3. **Comportamento observado** no Civil 3D: o que é criado, em que layer, como
   as pontas tocam o limite.
4. **Formato de arquivos**: o `.OFV` do AgroCAD é lido pelo `CRIALINHAS`, o que
   permite migrar as predefinições.

Lição para o GeoIA: em ferramentas proprietárias, a especificação vem da
interface, dos arquivos de dados e da observação, e não do binário. O
repositório [morluto/rea](https://github.com/morluto/rea) foi avaliado. Ele é
um MCP de engenharia reversa de binários nativos, não lê AutoLISP `.fas`, e o
próprio aviso de uso responsável dele exclui "reproduzir código protegido". O
que se aproveitou dele foi a **metodologia de otimização** (seção 3).

## 3. Metodologia de desempenho (adaptada do skill `rea-analysis-optimization`)

1. **Fixar a pergunta e o oráculo de correção**, independente da
   implementação: a saída correta é "para cada distância d, o trecho da reta
   v = d dentro do polígono". O oráculo é um recorte por força bruta sobre o
   contorno densificado
   ([src/tools/oraculo_varre_crialinhas.py](../../src/tools/oraculo_varre_crialinhas.py)).
2. **Achar o trabalho desnecessário mais cedo**: rastrear uma execução e
   contar operações caras por linha criada.
3. **Aplicar a menor correção estrutural** no dono do custo, sem cache
   genérico nem camada nova.
4. **Medir**: cada ação imprime o tempo, por exemplo `[0.42 s]`.

### 3.1 Onde estava o custo (v2.0)

Para **cada** linha criada dentro de um talhão, a v2.0 fazia:

| Operação | Tipo | Custo relativo |
| --- | --- | --- |
| `Offset` da referência prolongada | COM, cria entidade | alto |
| `IntersectWith` com o talhão | COM | alto |
| `getClosestPointTo` + `getParamAtPoint` por interseção | COM | médio |
| `entget` da curva **uma vez por trecho** | DXF | médio |
| teste ponto-no-polígono do ponto médio de cada trecho, O(nº de vértices da amostra) | LISP | alto em talhões com milhares de vértices (contorno GPS) |
| `entmake` do trecho + `Delete` do offset | DXF + COM | alto |
| linhas geradas até a maior distância **nos dois lados**, mesmo onde não há talhão | desperdício | até 2× |

Fora do talhão (cabeceira, sem talhão, selecionar), havia ainda **3 puts COM
por linha** (Layer, Color, Linetype). Além disso, `nth` dentro de laços
deixava a amostragem do contorno O(n²).

### 3.2 Correções aplicadas (v2.1)

| # | Correção | Ideia geométrica / técnica | Efeito |
| --- | --- | --- | --- |
| 1 | **Varredura analítica** quando a referência é reta (LINE ou LWPOLYLINE colinear sem arcos), que é o caso típico do GOFUR | No sistema local (u ao longo da referência, v perpendicular), toda linha é `v = d`. O contorno é quebrado em trechos **monótonos em v** (arcos partidos em v máx./mín.). Cada trecho visita só as distâncias da sua faixa `[vmin, vmax)` (busca binária na lista ordenada) e calcula `u` por fórmula. Os cruzamentos ordenados formam os pares (u1,u2), (u3,u4)… (regra par/ímpar). | **Zero chamadas COM por linha**: só `entmake` dos trechos internos. O(lados + cruzamentos). As pontas caem exatas, inclusive em arcos. |
| 2 | Referência curva: extensão **por lado** | Distância com sinal (produto vetorial com a tangente) de cada ponto do contorno; só gera offsets até a extensão do lado, mais a folga da flecha dos arcos amostrados. | até ~2× menos offsets quando a referência está na borda do talhão |
| 3 | Recorte por **paridade** | Curva aberta com as duas pontas fora e número par de cruzamentos: os trechos alternam fora/dentro. Com tangência (ímpar) ou curva fechada, volta ao teste do ponto médio. | elimina o teste O(contorno) por trecho |
| 4 | **Cópia-base por layer** | Copia a curva de origem uma vez por layer, já ByLayer, e tira os offsets dela; offsets herdam as propriedades. | elimina 3 puts COM por linha |
| 5 | `entget` uma vez por curva, e percurso de lista em vez de `nth` | — | O(n) |
| 6 | Layers garantidos uma vez por comando | — | menos `tblsearch`/COM por talhão |

### 3.3 Por que a faixa semiaberta importa

Uma reta `v = d` que passa **exatamente** por um vértice (caso comum: a
referência começa num vértice do talhão) seria contada duas vezes, uma em cada
lado que chega no vértice, e isso quebraria a regra par/ímpar. Com a faixa
`[vmin, vmax)` cada vértice conta uma vez. Nas pontas dos arcos usa-se o `v`
**exato do vértice**, e não `cv + R·sin(α)`, para que o arco e o segmento
vizinho concordem bit a bit. O oráculo testa retas exatamente sobre todos os
vértices.

## 4. Resultado do oráculo

```text
retângulo, ref horizontal          erro_rel_max=0.00e+00
retângulo, ref 17°                 erro_rel_max=2.37e-15
arcos convexos (bulge +)           erro_rel_max=1.67e-05   (erro do próprio oráculo densificado)
arcos côncavos (bulge -)           erro_rel_max=1.70e-05
semicírculo + arco > 180°          erro_rel_max=2.52e-05
forma L (côncava)                  erro_rel_max=5.10e-16
5 polígonos aleatórios c/ arcos    erro_rel_max<=4.1e-06
```

O teste dentro do Civil 3D (tempo `[x s]` impresso ao fim de cada ação,
comparado com o `GOFUR`) é feito manualmente pelo usuário.

## 5. Regras que o GeoIA deve reter

1. **Geometria analítica antes de API**: se a família de curvas tem forma
   fechada (retas paralelas, círculos concêntricos), calcule as interseções em
   vez de criar e destruir entidades via COM.
2. **Não gerar o que será descartado**: limite a geração pela extensão real do
   talhão em cada lado.
3. **Propriedades na origem**: crie a entidade já no layer certo (`entmake`
   com o grupo 8, ou offset de uma cópia-base), em vez de ajustar depois.
4. **Robustez numérica explícita**: faixas semiabertas, valores exatos nos
   vértices, chave única ao ordenar (o `vl-sort` pode eliminar elementos
   iguais) e queda para o método lento quando a premissa falha (tangência).
5. **Oráculo independente** antes de otimizar: comparar com força bruta, não
   com a versão antiga.
6. **Medir sempre**: exibir o tempo da ação para o usuário comparar.

## 6. Exercícios para o GeoIA

1. Dada uma referência a 30° e um talhão em L, descreva quantas linhas de 3 m
   cada lado recebe e por que o lado vazio não gera offsets.
2. Explique por que uma reta que passa por um vértice de "bico" (vértice
   máximo local em v) deve gerar 0 ou 2 cruzamentos, nunca 1.
3. Proponha a extensão do caminho rápido para referência em **arco**: as
   linhas são círculos concêntricos; qual é a variável local equivalente a v?
   (Resposta: o raio. Os trechos seriam monótonos em distância ao centro.)
