# Prompt: ícones do menu FarmTools (AutoCAD) no estilo do WebGIS

> Para o agente **web designer**. Copie a partir de "Contexto".

---

## Contexto

O **FarmTools** é o nosso menu de ferramentas LISP para AutoCAD: aba do ribbon e menu suspenso, para
sistematização agrícola (talhões, linhas de plantio, carreadores, rede de estradas). Hoje ele usa ícones
nativos do AutoCAD, que não dizem nada sobre as ferramentas.

Queremos ícones próprios com **a mesma linguagem visual dos ícones do nosso WebGIS**. As duas ferramentas
são da mesma família e precisam parecer isso.

## Referência de estilo (leia antes de desenhar)

Pasta: `E:\GitHub\web_gis\assets\icons\ui\` (54 SVGs + `sprite.svg`).

Abra pelo menos estes, que são os mais próximos do nosso tema:
`ic-camadas.svg`, `ic-adicionar-camada.svg`, `ic-desenho.svg`, `ic-medir.svg`, `ic-dispersao.svg`,
`ic-analise.svg`, `ic-localizacao.svg`, `ic-exportar.svg`, `ic-configuracoes.svg`, `ic-informacao.svg`,
`ic-editar.svg`, `ic-filtro.svg`.

Características do estilo, que devem ser mantidas:
- `viewBox="0 0 24 24"`, `fill="none"`, `stroke-width="1.6"`, `stroke-linecap="round"`,
  `stroke-linejoin="round"`.
- Desenho só de linha, geométrico e limpo, com área útil entre 3.5 e 20.5 e respiro nas bordas.
- Pontos/vértices: `circle r="1"` preenchido (`fill` = cor do traço, `stroke="none"`), como em `ic-dispersao.svg`.
- Preenchimento suave opcional para planos, como em `ic-camadas.svg` (`#e6f0f9` no tema claro). Use pouco.
- Metáforas simples, com no máximo 3–4 elementos por ícone.
- Cores do WebGIS (`E:\GitHub\web_gis\css\style.css`): acento verde `#5cb83f` (escuro) e `#3b7a2c` (claro).

## Restrições do AutoCAD (diferenças em relação ao WebGIS)

1. **Sem `currentColor` nem variáveis CSS.** O AutoCAD usa imagens rasterizadas, então as cores precisam ser fixas.
2. **Dois tamanhos:** 16×16 px (botões pequenos, itens de split button, menu suspenso) e 32×32 px (botões grandes do ribbon).
3. **PNG com fundo transparente.** BMP só se o PNG der problema.
4. **Legibilidade em 16 px.** O traço de 1.6 em 24 vira cerca de 1 px em 16. Alinhe as linhas à grade de pixel
   (coordenadas em .5 para traço de 1 px). Se o ícone 24 tiver detalhe demais, faça uma **versão simplificada para
   16 px** (`-16.svg`) em vez de só reduzir.
5. **Tema escuro é o principal.** O AutoCAD é usado no **tema escuro** (fundo do ribbon ≈ `#3B4453`, menu
   suspenso ≈ `#2B303A`), e é o conjunto `dark` que vai para o menu. Desenhe e confira primeiro no fundo escuro.
   O conjunto `light` (fundo ≈ `#F0F0F0`) é secundário: entregue também, porque é só trocar as cores, mas não
   comprometa o escuro por causa dele.

   | Tema | Traço principal | Acento (verde) | Preenchimento suave |
   |---|---|---|---|
   | claro (`light`) | `#2C2C2E` | `#3B7A2C` | `#E6F0F9` |
   | escuro (`dark`) | `#E8EAEE` | `#5CB83F` | `#4A5568` (ou nenhum) |

6. **Uso do acento verde.** Use em **um** elemento por ícone, o que mostra a ação ou o resultado (a linha
   criada, o trecho estendido, a conexão feita). O resto fica na cor do traço principal.
7. **Cores de layer (só nos TR-\*).** Um pequeno "selo" pode usar a cor do layer de destino:
   Limite Externo = vermelho `#E53935`, Limite Interno = azul `#1E63D6`. Os outros TR-\* se diferenciam pelo desenho.

## Ícones a criar

Os nomes de arquivo usam o `id` da tabela. "Reusa" quer dizer que não precisa desenhar: o comando usa o ícone indicado.

### Painel Ajustes

| id | Comando | O que faz | Sugestão de metáfora |
|---|---|---|---|
| `siscoord` | SISCOORD | Define o sistema de coordenadas do projeto (SIRGAS 2000, WGS84, SAD69…) e as unidades | eixos X/Y com globo/graticule pequeno |
| `troca-layer` | (split) Troca Rápida de Layer | Grupo dos TR-\* | pilha de layers (como `ic-camadas`) + seta de troca |
| `tr-le` | TR-LE | Move objetos para o layer LIMITE_EXTERNO | `troca-layer` + contorno externo grosso, selo vermelho |
| `tr-li` | TR-LI | … LIMITE_INTERNO | `troca-layer` + contorno interno tracejado, selo azul |
| `tr-su` | TR-SU | … sulcação (SULCOS MESTRES) | `troca-layer` + linha-mestra com marcas de sulco |
| `tr-ta` | TR-TA | … talhão (TALHÕES) | `troca-layer` + polígono de talhão |
| `tr-te` | TR-TE | … terraço (TERRAÇOS) | `troca-layer` + 2 curvas de nível paralelas |
| `tr-co` | TR-CO | … colheita (LINHAS DE CANA) | `troca-layer` + 3 linhas de plantio paralelas |
| `limites` | (split) Limites do Talhão | Grupo dos *LIM | polígono com linhas tocando a borda |
| `cortalim` | CORTALIM | Corta as linhas que passam do limite do talhão | linhas saindo do polígono, ponta externa cortada (tesoura ou marca de corte) |
| `estendelim` | ESTENDELIM | Estende as pontas das linhas até o limite | linhas curtas dentro do polígono, prolongamento em verde até a borda |
| `ajustalim` | AJUSTALIM | Estende e corta ao mesmo tempo | combinação dos dois: uma linha estendida, outra cortada |
| `apagalim` | APAGALIM | Apaga objetos dentro ou fora de um polígono | polígono + borracha (ou X) |
| `geometria` | (split) Geometria | Grupo de simplificação | reusa `simplificapl` |
| `simplificapl` | SIMPLIFICAPL | Reduz vértices de polilinhas (Douglas-Peucker) | polilinha com muitos pontos → mesma forma com poucos pontos |
| `segmentarcos` | SEGMENTARCOS | Converte arcos em segmentos de reta | arco tracejado + poligonal de 3–4 segmentos por cima, vértices em pontos |

### Painel Sistematização

| id | Comando | O que faz | Sugestão de metáfora |
|---|---|---|---|
| `crialinhas` | CRIALINHAS | Cria linhas guia, de plantio e de cabeceira dentro dos talhões | polígono de talhão com linhas paralelas (a guia em verde) |
| `conectalinhas` | CONECTALINHAS | Liga as linhas da mesma fileira em talhões vizinhos, atravessando o carreador | dois blocos de linhas separados por faixa, curva verde unindo uma fileira |
| `carreadores` | CARREADORES | Corta os talhões por faixas de carreador ao longo de eixos e desenha os carreadores | talhão dividido por estrada (faixa de 2 linhas paralelas) |
| `concordar` | SIS_CONCORDAR | Concordância de eixos de estradas: arco de raio R nos cruzamentos (T, X, L) | dois eixos em T/L com arco de concordância verde no canto |
| `rede` | (split) Rede de Rotas | Grupo dos REDE_\* | grafo: 4–5 nós ligados por arestas |
| `rede-validar` | REDE_VALIDAR | Valida a topologia da rede (só leitura) | `rede` + check |
| `rede-corrigir` | REDE_CORRIGIR | Corrige a topologia (vértices nos cruzamentos, pontas soltas) | `rede` + chave/varinha |
| `rede-proximo` | REDE_PROXIMO | Zoom no próximo erro | `rede` com um nó destacado + seta "próximo" |
| `rede-exportar` | REDE_EXPORTAR | Exporta a rede em GeoJSON | `rede` + seta de exportar (como `ic-exportar`) |

### Submenu RA_REDE (versão alternativa da rede, para comparação)

| id | Comando | Sugestão / reuso |
|---|---|---|
| `ra-rede` | (split) Rede (RA_REDE) | `rede` com selo "alt" (pequeno losango ou "2") |
| `ra-carregar` | REDE_CARREGA_RA | `ra-rede` + seta circular de recarregar |
| — | RA_VERIFICAR | reusa `rede-validar` |
| — | RA_CORRIGIR | reusa `rede-corrigir` |
| `ra-quebrar` | RA_QUEBRAR | linha quebrada num entroncamento em T (pequeno vão no nó) |
| `ra-pontas` | RA_PONTAS | ponta solta sendo ligada à linha mais próxima (trecho verde) |
| `ra-juntar` | RA_JUNTAR | duas linhas colineares emendadas num pseudo-nó |
| — | RA_SEGMENTAR | reusa `segmentarcos` |
| `ra-semconexao` | RA_SEMCONEXAO | cruzamento em X tipo viaduto (uma linha passa "por baixo", com vão) |
| — | RA_PROXIMO | reusa `rede-proximo` |
| `ra-limpar` | RA_LIMPAR | marcador (alfinete/flag) + borracha |
| `ra-desenhar` | RA_DESENHAR | lápis desenhando uma aresta da rede (como `ic-desenho`) |
| `ra-config` | RA_CONFIG | engrenagem (adaptar `ic-configuracoes`) |
| `ra-ajuda` | RA_AJUDA | "i" ou "?" (adaptar `ic-informacao`) |

Total: **35 ícones desenhados** (os outros reusam).

## Entregáveis

Salvar em `E:\GitHub\lisps_autocad\menu\icons\`:

```
menu/icons/
  svg/            <id>.svg            mestre 24×24, estilo WebGIS (currentColor, para referência e reuso no WebGIS)
                  <id>-16.svg         (só quando houver versão simplificada para 16 px)
  png/light/      ft-<id>-16.png, ft-<id>-32.png
  png/dark/       ft-<id>-16.png, ft-<id>-32.png
  icons.json      mapa comando → id (formato abaixo)
  preview.html    folha de conferência
```

- **`svg/`** é obrigatório. Se você não conseguir rasterizar, entregue os SVGs com as cores dos dois temas já
  aplicadas (`svg/light/`, `svg/dark/`) que eu converto para PNG.
- **`icons.json`**: `{ "MM_FT_CRIALINHAS": "crialinhas", "MM_FT_ALT_RAVERIFICAR": "rede-validar", ... }`,
  mais as chaves dos split buttons (`RBN_FT_SPLIT_TR`, `RBN_FT_SPLIT_LIM`, `RBN_FT_SPLIT_GEOM`, `RBN_FT_SPLIT_RA`,
  `RBN_FT_SPLIT_RAREDE`). Os UIDs dos comandos estão em `E:\GitHub\lisps_autocad\menu\src\MenuGroup.cui`.
- **`preview.html`**: todos os ícones em 16 e 32 px, lado a lado, sobre fundo `#3B4453` e `#2B303A` (escuro, principal) e `#F0F0F0` (claro), com o nome do
  comando embaixo. Inclua também uma linha com alguns ícones do WebGIS para comparar o estilo.

## Critérios de aceite

- Na folha de preview, o conjunto parece da mesma família dos ícones do WebGIS.
- Todos os ícones ficam legíveis e distinguíveis em **16 px** no fundo escuro (`#3B4453` e `#2B303A`). Os 6 TR-\* precisam se distinguir entre si.
- Há só um elemento em verde por ícone, e só quando faz sentido.
- Os PNG têm exatamente 16×16 e 32×32, fundo transparente, sem borda borrada (traços alinhados ao pixel).
- Nenhum ícone imita marca ou ícone de terceiros (AgroCAD, Autodesk etc.).

## Fora do escopo

Não altere os arquivos `.cui`, `.cuix` nem `.lsp`. A integração no menu fica com o agente do projeto lisps_autocad.
