# Checklist — recriar uma ferramenta AgroCAD com foco em desempenho

Usado no porte GOFUR → CRIALINHAS v2.1 ([lição 01](../lessons/licao-01-gofur-crialinhas-desempenho.md)).

## Especificação (sem descompilar)

- [ ] Comando localizado no catálogo (`references/agrocad/catalogo-comandos.md`), com o texto de ajuda anotado.
- [ ] Diálogo DCL / opções levantadas: parâmetros, valores padrão, layers e cores (`CONFIG.AGROCAD`).
- [ ] Formatos de arquivo (predefinições) identificados e lidos pela versão nova.
- [ ] Nome de comando **diferente** do AgroCAD (os dois menus carregam juntos).

## Correção

- [ ] Oráculo independente definido (força bruta, densificação, caso analítico), não "igual à versão antiga".
- [ ] Casos de borda: reta passando por vértice, arcos convexos e côncavos, arco maior que 180°, talhão côncavo (L), referência na borda do talhão.
- [ ] Sem linhas duplicadas (tolerância 1e-4 m) e pontas exatas no limite.
- [ ] Queda para o método robusto quando uma premissa do caminho rápido falha.

## Desempenho

- [ ] Contadas as chamadas COM **por linha criada**; a meta é 0 no caso típico.
- [ ] Nada é gerado fora da extensão real do talhão (por lado).
- [ ] Entidades nascem no layer certo e ByLayer (`entmake` com grupo 8, ou cópia-base).
- [ ] Nenhum `nth` dentro de laço sobre listas grandes; `entget` uma vez por entidade.
- [ ] Layers e tabelas garantidos uma vez por comando.
- [ ] Tempo da ação impresso (`MILLISECS`) para comparação manual.

## Entrega

- [ ] `.lsp` em cp1252 + CRLF, parênteses balanceados, todas as funções `ln:*` definidas.
- [ ] Menu (`menu/src/*.cui`) aponta para o comando; `.cuix` recompilado se mudou.
- [ ] Teste no Civil 3D feito **pelo usuário**, com lista curta de cenários.
- [ ] Lição e notas do GeoIA atualizadas.
