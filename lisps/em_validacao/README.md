# Ferramentas em validação

Estas lisps ainda **não foram validadas** e por isso ficam fora do menu FarmTools.
O `FarmTools.mnl` não carrega esta pasta. Para testar uma delas, use `APPLOAD` no `.lsp`.

| Arquivo | Comandos |
|---|---|
| Obstaculos.lsp / .dcl | DESVIAOBS |
| Manobras.lsp / .dcl | MANOBRAS |
| Classifica.lsp / .dcl | CLA_* (18 comandos) |
| GeoImpExp.lsp / .dcl | GEOIMPORTAR, GEOEXPORTAR, GEOCALIBRA |
| ImpKML.lsp, ImpGeoJSON.lsp, ImpSHP.lsp, ImpComum.lsp, Importar.dcl | IMPKML, IMPGEOJSON, IMPSHP |

## Pasta dos DCL

Aqui as rotinas procuram os `.dcl` em `*FT-DEV-DIR*` (definida pelo `FarmTools.mnl` como
`lisps\em_validacao`), e não em `*LISPS-DIR*`. Sem o FarmTools carregado, elas usam `findfile`.

## Promover para o FarmTools (quando validar)

1. Mover `.lsp` e `.dcl` de volta para `lisps\`.
2. Trocar `*FT-DEV-DIR*` por `*LISPS-DIR*` no arquivo.
3. Adicionar `MenuMacro`, item do menu e botão do ribbon em `menu\src\*.cui` (copiar de `menu\legado\src`
   e trocar `_LISPS_` por `_FT_`).
4. Ícone: PNGs `ft-<id>-16/32.png` em `menu\icons\png\dark` (e `light`), mapeamento em
   `menu\icons\gerar_icons_json.py`, depois `python menu\icons\gerar_icons_json.py` e `python menu\aplicar_icones.py`.
5. Rodar `menu\build_cuix.ps1`.

## Atenção: conflito de nomes (Classifica × CriaLinhas)

`Classifica.lsp` e `CriaLinhas.lsp` definem funções com o mesmo nome e assinaturas diferentes:
`cl:amostra`, `cl:dentro` e `cl:cabeceira`. A última carregada sobrescreve a outra.
Antes de promover o Classifica, renomeie o prefixo dele (ex.: `cla:`), senão CRIALINHAS ou os
comandos CLA_* quebram. Também não carregue o Classifica numa sessão em que vá usar o CRIALINHAS.
