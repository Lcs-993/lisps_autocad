# lisps_autocad

Este repositório é uma base de conhecimento e treinamento para o GeoIA, não um agente em execução. O foco principal é registrar e organizar o aprendizado obtido no desenvolvimento de ferramentas para AutoCAD / Civil 3D, com a intenção de usar esse material como referência para treinar uma IA especialista em projetos agrícolas.

A estrutura do projeto reúne práticas, rotinas, padrões e conceitos de desenho técnico, automação e operação agrícola, a fim de alimentar o treinamento e a evolução do GeoIA.

## Estrutura

```
.claude/agents/geoai.md       visão conceitual do agente GeoIA
artifacts/geoia/README.md    artefatos e materiais de referência para treinamento
docs/geoia/README.md        documentação do contexto do projeto e do GeoIA
lisps/TrocaLayer.lsp        rotina genérica de "Troca Rápida de Layer" + comando TR-LE
menu/LISPS.cuix            menu parcial (gerado a partir de menu/src)
menu/LISPS.mnl             carregado junto com o .cuix; carrega todos os .lsp de lisps/
menu/src/                  fontes XML do .cuix
menu/build_cuix.ps1        reempacota menu/src -> menu/LISPS.cuix
prompts/geoia-agent.md     material de referência e prompt-base para treinamento
```

## Como este repositório deve ser entendido

O objetivo central aqui não é entregar um agente funcional pronto para uso. O foco é o seguinte:

- registrar o conhecimento adquirido em ferramentas CAD e automação;
- documentar a lógica de projetos agrícolas e de pilotagem automática;
- servir como base de treinamento para o GeoIA;
- manter exemplos, padrões e referências que possam ser reutilizados em IA, CAD e geoprocessamento.

Em outras palavras, o projeto funciona como corpus técnico e referência de domínio para a formação do GeoIA.

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
