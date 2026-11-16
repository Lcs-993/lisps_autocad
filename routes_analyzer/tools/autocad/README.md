# RA_REDE.lsp: rede de rotas no AutoCAD

Rotina AutoLISP para desenhar e corrigir a camada da rede de rotas, deixando-a pronta para o
Routes Analyzer. Ela garante as regras de [docs/REQUISITOS_REDE.md](../../docs/REQUISITOS_REDE.md):

- todas as linhas **conectadas** por vértice em comum;
- linhas **quebradas em todos os entroncamentos e cruzamentos**;
- **sem pseudo-nós**, ou seja, sem duas linhas iguais emendadas no meio de um trecho sem motivo;
- **sem pontas soltas** que quase tocam outra linha (*undershoot* e *overshoot*);
- sem linhas duplicadas.

Funciona no AutoCAD completo e no **AutoCAD LT 2024 ou mais novo**, porque não usa ActiveX. O desenho
deve estar em **metros**.

## Instalação

1. No AutoCAD: `APPLOAD` → selecione `RA_REDE.lsp` → **Carregar**.
2. Para carregar sempre: em `APPLOAD`, clique em **Conteúdo...** no "Pacote de inicialização" e adicione o arquivo.
3. Digite `RA_AJUDA` para ver os comandos.

## Comandos

| Atalho | Comando | O que faz |
|---|---|---|
| `RD` | `RA_DESENHAR` | Desenha uma linha da rede na camada `REDE_ROTAS` com os snaps **fim, interseção e próximo** ligados. Ao terminar, **quebra automaticamente** as linhas que ela toca ou cruza. |
| `RV` | `RA_VERIFICAR` | Verifica a rede inteira, coloca círculos coloridos na camada `RA_ERROS` e mostra um resumo. Não altera as linhas. |
| `RN` | `RA_PROXIMO` | Dá zoom no próximo marcador e diz qual é o problema. |
| `RL` | `RA_LIMPAR` | Apaga os marcadores. |
| `RC` | `RA_CORRIGIR` | Corrige tudo de uma vez: apaga duplicadas → liga pontas soltas → quebra nos entroncamentos → emenda pseudo-nós → verifica de novo. |
| `RQ` | `RA_QUEBRAR` | Só quebra as linhas em todos os entroncamentos e cruzamentos. |
| `RF` | `RA_PONTAS` | Leva cada ponta solta até a linha ou vértice mais próximo (a menos de 2 m) e quebra. |
| `RJ` | `RA_JUNTAR` | Emenda as linhas que se encontram em pseudo-nós. |
| `RS` | `RA_SEGMENTAR` | Converte arcos (`ARC` e polilinhas com arco) em segmentos retos de até 5 m. |
| `RX` | `RA_SEMCONEXAO` | Marca um cruzamento que **não** deve ser ligado, como viaduto ou passagem em desnível. |
| | `RA_CONFIG` | Muda o filtro de camadas, as tolerâncias e o tamanho dos marcadores. |

Cada comando é um único passo de desfazer: **`U` desfaz tudo o que ele fez**.

### Cores dos marcadores (`RV`)

| Cor | Problema |
|---|---|
| Vermelho | Cruzamento sem quebra: duas linhas se cruzam e nenhuma está quebrada ali |
| Laranja | Entroncamento em T sem quebra: uma linha chega no meio da outra, e a outra não está quebrada |
| Amarelo | Pseudo-nó: só duas linhas, com as mesmas propriedades, se encontram |
| Magenta | Ponta solta suspeita: termina a menos de 2 m de outra linha sem tocar |
| Azul | Sobreposição ou linha duplicada |
| Ciano | Entidade que a rede não aceita (arco, spline, elipse, malha) |
| Verde | Pedaço desconectado da rede principal |

## Fluxo de trabalho sugerido

1. Desenhe com `RD`, ou desenhe normalmente com os snaps **Fim** e **Interseção** ligados.
2. De tempos em tempos, rode `RV` e use `RN` para conferir cada marcador.
3. Rode `RC` para corrigir o que for automático e confira o resumo. O ideal é tudo zero e
   **"Partes desconectadas = 0"**.
4. Para os viadutos, marque antes com `RX`; assim `RQ` e `RC` não ligam aquele cruzamento.

## Configuração (`RA_CONFIG`)

| Parâmetro | Padrão | Uso |
|---|---|---|
| Filtro de camadas | `REDE*` | Quais camadas formam a rede (curingas do AutoCAD; separe vários por vírgula) |
| Camada de desenho | `REDE_ROTAS` | Camada usada pelo `RD`; precisa entrar no filtro |
| Tolerância de ponto igual | 0,001 m | Pontos mais próximos que isso são o mesmo nó |
| Distância de ponta solta | 2 m | Até onde uma ponta é considerada "quase tocando" e é ligada pelo `RF` |
| Raio dos marcadores | 2 m | Tamanho dos círculos de erro |
| Segmento máximo de arco | 5 m | Usado pelo `RS` |

Os valores valem até fechar o AutoCAD. Para mudar o padrão, edite o topo do arquivo `.lsp`.

## Regras e cuidados

- **Pseudo-nó só é emendado** quando as duas linhas têm a mesma camada, cor, tipo de linha e XDATA. Se
  forem diferentes (por exemplo, a velocidade muda ali), o nó é mantido de propósito.
- **Mão única:** uma emenda que inverteria o sentido de uma linha **não é feita** quando a linha tem XDATA
  ou está numa camada de mão única (padrão `*MAO*UNICA*,*_MU`). Confira o sentido com setas antes.
- **Quebrar** gera linhas novas, que mantêm camada, cor, tipo de linha e XDATA. *Object Data* do Map 3D
  **não é copiado**.
- Polilinhas 3D e linhas com Z diferente nas pontas viram 2D na cota do primeiro vértice. O Routes
  Analyzer ignora o Z e usa o MDT.
- `RF` move só a **ponta** da linha até o alvo. Revise pontas soltas maiores que 2 m à mão: podem ser fim
  de via de verdade.
- Polilinhas com arco e `ARC` devem ser convertidos com `RS` antes. `SPLINE` precisa ser convertida com
  `SPLINEDIT` → *Converter em polilinha*.

## Como foi testado

A lógica foi testada fora do AutoCAD, num interpretador de AutoLISP simplificado com um desenho
simulado. O desenho tinha cruzamento, T, pseudo-nó, undershoot, overshoot, duplicada, viaduto
marcado, fragmento isolado e arco. Resultados:

- depois de `RC`, todos os erros foram zerados e o viaduto continuou sem conexão;
- rodar `RC` de novo não alterou nada;
- a emenda de mão única que exigiria inversão foi recusada.

**Ainda não foi rodada dentro do AutoCAD.** Faça o primeiro uso numa cópia do desenho.
