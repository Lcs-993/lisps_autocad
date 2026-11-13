# lisps_autocad

Este repositório funciona como base de treinamento para o GeoIA, com foco em conhecimento técnico de projetos agrícolas, AutoCAD, geoprocessamento, desenho técnico e operação em campo.

A ideia central não é manter um agente executável, mas construir um conjunto organizado de conhecimento, documentação, exemplos e referências que possam ser usados para treinar e evoluir a IA especialista em projetos agrícolas.

## Objetivo do repositório

- registrar o conhecimento adquirido em ferramentas CAD e automação;
- organizar exemplos de projetos e rotinas de desenho;
- documentar práticas de projeto agrícola e de pilotagem automática;
- servir como base de referência para treinamento e aprendizado do GeoIA;
- conectar domínio técnico, documentação e materiais de apoio.

## Estrutura do repositório

```
.claude/agents/geoai.md            visão conceitual do GeoIA
artifacts/geoia/README.md         artefatos e entregáveis do projeto
project-structure.md              visão geral da arquitetura do projeto

data/                             dados e amostras para treinamento
  README.md
  schema/
    geoia-dataset-schema.json
  raw/                            materiais brutos e fontes iniciais
  samples/
    case-01-soja-gleba.json
    case-02-cafe-declividade.json
  annotations/                    metadados e anotações

docs/                             documentação técnica e de domínio
  geoia/
    README.md
    training-plan.md
    knowledge-model.md
    knowledge-base.md

lisps/                            rotinas AutoLISP e ferramentas CAD
menu/                             arquivos do menu do AutoCAD

prompts/                          prompts-base e materiais de referência
  geoia-agent.md

references/                       referências de domínio e materiais de apoio
  README.md
  agriculture/
    project-patterns.md
  cad/
    autocad-patterns.md
  domain/
    geoia-domain-overview.md

src/                              fontes e materiais técnicos do projeto
  README.md
  autocad/
  templates/

training/                         notas, lições e checklists
  README.md
  geoia-learning-notes.md
  dataset-index.md
  lessons/
  checklists/
```

A estrutura está completa e organizada para servir como base de treinamento do GeoIA, unindo conhecimento técnico, documentação de domínio, exemplos estruturados e materiais de apoio.

## Dataset inicial

O repositório já inclui um dataset inicial com exemplos de projetos agrícolas em formato JSON, bem como um schema-base para validação e organização dos registros. Esse conjunto serve como base inicial para treinamento e evolução do GeoIA no domínio agrícola.

## Como usar este repositório

- `docs/`: documentação conceitual e técnica do domínio.
- `data/`: material bruto e exemplos para alimentar treinamento.
- `references/`: referências externas, padrões, conceitos e materiais de apoio.
- `training/`: observações, notas e organização de aprendizado.
- `src/`: fontes e materiais técnicos do projeto original.

## Escopo de domínio

O conteúdo aqui reunido cobre:

- automação de desenho em AutoCAD;
- geoprocessamento e análise espacial;
- topografia e organização da gleba;
- planejamento agrícola e operação em campo;
- pilotagem automática e lógica operacional de máquinas;
- documentação técnica e decisões de projeto.

## Visão de longo prazo

Este repositório deve ser tratado como um repositório de conhecimento para treinamento do GeoIA, permitindo evoluir de um conjunto de ferramentas CAD para uma base de domínio mais rica, organizada e útil para inteligência artificial aplicada à agricultura.

## Comandos

| Comando | Faz | Layer |
|---|---|---|
| `TR-LE` | Troca rapidamente o layer dos objetos selecionados para o de limite externo | `LIMITE_EXTERNO` (cor 1, Continuous) |

Funciona como o TR-SUL / TR-TAL / TR-TER / TR-COL do AgroCAD: usa a seleção prévia ou pede para
selecionar; cria o layer se não existir (e garante que ele esteja ligado, descongelado e destravado);
move os objetos para ele. Com `*TR-PROPS-BYLAYER*` = `T` (padrão), cor, tipo de linha e espessura
passam para ByLayer. Tudo em um único passo de desfazer (um `U` desfaz).

### Criar outro comando TR-xx

Em `lisps/TrocaLayer.lsp`:

```lisp
(defun c:TR-XX ()
  (tr:troca-layer "NOME_DO_LAYER" 3 "Continuous" "Descricao")
)
```

Depois adicione um `MenuMacro` em `menu/src/MenuGroup.cui`, um botão no split button de
`menu/src/RibbonRoot.cui` e um item em `menu/src/PopMenuRoot.cui`, e rode `menu/build_cuix.ps1`.

## Instalação (uma vez)

1. No AutoCAD: `CUILOAD` → **Procurar** → `menu\LISPS.cuix` → **Carregar**.
   O `.mnl` carrega os LISPs automaticamente a cada sessão.
2. Se o AutoCAD avisar sobre local não confiável: `OPTIONS` → **Arquivos** → **Locais confiáveis**
   → adicione a pasta `lisps_autocad\...` (com `\...` para incluir subpastas).
3. A aba **Lisps** aparece no Ribbon (painel **Ajustes** → **Troca Rápida de Layer**).

Para atualizar o menu: `CUIUNLOAD` → LISPS, rode `pwsh -File menu\build_cuix.ps1`, depois `CUILOAD` de novo.

## Comandos

| Comando | Faz | Layer |
|---|---|---|
| `TR-LE` | Troca rapidamente o layer dos objetos selecionados para o de limite externo | `LIMITE_EXTERNO` (cor 1, Continuous) |

Funciona como o TR-SUL / TR-TAL / TR-TER / TR-COL do AgroCAD: usa a seleção prévia ou pede para
selecionar; cria o layer se não existir (e garante que ele esteja ligado, descongelado e destravado);
move os objetos para ele. Com `*TR-PROPS-BYLAYER*` = `T` (padrão), cor, tipo de linha e espessura
passam para ByLayer. Tudo em um único passo de desfazer (um `U` desfaz).

### Criar outro comando TR-xx

Em `lisps/TrocaLayer.lsp`:

```lisp
(defun c:TR-XX ()
  (tr:troca-layer "NOME_DO_LAYER" 3 "Continuous" "Descricao")
)
```

Depois adicione um `MenuMacro` em `menu/src/MenuGroup.cui`, um botão no split button de
`menu/src/RibbonRoot.cui` e um item em `menu/src/PopMenuRoot.cui`, e rode `menu/build_cuix.ps1`.

## Instalação (uma vez)

1. No AutoCAD: `CUILOAD` → **Procurar** → `menu\LISPS.cuix` → **Carregar**.
   O `.mnl` carrega os LISPs automaticamente a cada sessão.
2. Se o AutoCAD avisar sobre local não confiável: `OPTIONS` → **Arquivos** → **Locais confiáveis**
   → adicione a pasta `lisps_autocad\...` (com `\...` para incluir subpastas).
3. A aba **Lisps** aparece no Ribbon (painel **Ajustes** → **Troca Rápida de Layer**).

Para atualizar o menu: `CUIUNLOAD` → LISPS, rode `pwsh -File menu\build_cuix.ps1`, depois `CUILOAD` de novo.
