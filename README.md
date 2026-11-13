# lisps_autocad

Comandos LISP próprios para AutoCAD / Civil 3D e um menu (aba de Ribbon **Lisps** + menu suspenso **Lisps**)
no mesmo formato do menu do AgroCAD.

## Estrutura

```
lisps/TrocaLayer.lsp   rotina genérica de "Troca Rápida de Layer" + comando TR-LE
menu/LISPS.cuix        menu parcial (gerado a partir de menu/src)
menu/LISPS.mnl         carregado junto com o .cuix; carrega todos os .lsp de lisps/
menu/src/              fontes XML do .cuix
menu/build_cuix.ps1    reempacota menu/src -> menu/LISPS.cuix
```

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
