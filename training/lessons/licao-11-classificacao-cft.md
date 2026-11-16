# Lição 11 — Classificação para exportação: CFT e tipos de objeto (CLA_*)

> Material de treinamento do GeoIA. Porte por comportamento do grupo de
> classificação do AgroCAD (KLA, CFT, RCFT, CPCFT, CFL, VV, JDBEX, JDBIN,
> JDHBEX, JDHBIN, JDABC, JDABL, JDLIN, CGLE e o filtro por CFT):
> [lisps/Classifica.lsp](../../lisps/Classifica.lsp) +
> [Classifica.dcl](../../lisps/Classifica.dcl).

## 1. Por que classificar

Um monitor de piloto automático não lê "polilinhas". Ele lê **talhões**
(Cliente → Fazenda → Talhão) e, dentro de cada talhão, **funções**:
- limite externo e limites internos (ilhas, passáveis ou não);
- cabeceiras externas e internas, com a largura;
- curvas AB e linhas AB (pistas retas, com o rumo);
- curvas adaptáveis, agrupadas em glebas;
- obstáculos e marcos.

Toda exportação para fabricante (ISOXML, Trimble, SHP AGCO/Topcon…) parte
dessa classificação. Por isso ela vem primeiro.

## 2. Modelo de dados

Tabela de Object Data `LISPS_CFT`, uma por objeto:

| Campo | Conteúdo |
| --- | --- |
| CLIENTE, FAZENDA, TALHAO | o CFT |
| TIPO | LIMITE_EXTERNO, LIMITE_INTERNO, CABECEIRA_EXTERNA, CABECEIRA_INTERNA, CURVA_AB, LINHA_AB, ADAPTAVEL, OBSTACULO, MARCO |
| NOME | grupo/gleba ou nome do objeto |
| PASSAVEL | S/N (limite interno) |
| OFFSET | largura da cabeceira (m) |
| HEADING | rumo da linha AB (graus a partir do norte, sentido horário) |

Sem Map 3D, os mesmos campos vão para XDATA (app `LISPS_CFT`). Os campos
saem como atributos no GEOEXPORTAR (`:CAMPO@LISPS_CFT`). O **cadastro** de
clientes, fazendas e talhões fica no próprio desenho (`vlax-ldata`), como as
listas do diálogo `claexp` do AgroCAD, e é completado com os CFT já usados
nos objetos.

## 3. Comandos

| AgroCAD | Nosso | O que faz |
| --- | --- | --- |
| KLA | CLA_GERENCIAR | tipo, CFT e grupo num diálogo; remover; mapa temático |
| CFT | CLA_CFT | cadastro Cliente/Fazenda/Talhão (Novo/Adicionar/Remover), aplicar, legenda, "manter os outros dados" |
| CFL | CLA_AUTO | CFT por layer, Object Data, texto dentro do polígono ou atributo de bloco; código único dividido por caracteres; nome do objeto; internos pelos limites |
| CPCFT / RCFT | CLA_COPIAR / CLA_REMOVER | copiar de um modelo; remover o CFT ou tudo |
| JDBEX / JDBIN | CLA_LIMEXT / CLA_LIMINT | limites (os internos perguntam se são passáveis) |
| JDHBEX / JDHBIN | CLA_CABEXT / CLA_CABINT | **criar** por offset do limite (para dentro do externo, para fora do interno) ou classificar as existentes; grava OFFSET |
| JDABC / JDABL | CLA_CURVAAB / CLA_LINHAAB | curvas AB; linhas AB com HEADING (ou criadas por A e B) |
| JDLIN / CGLE | CLA_ADAPT / CLA_GLEBA | adaptáveis; grupo pelo nome ou pelo layer, aplicado às selecionadas, ao grupo ou ao layer, com filtro de CFT |
| — | CLA_OBST / CLA_MARCO | obstáculos; marcos (flags) com nome |
| VV | CLA_VER | liga/desliga as cores por tipo, CFT ou grupo; a cor original fica em XDATA `LISPS_VV` e é restaurada |
| TCFT (filtro) | CLA_FILTRO | isola (ISOLATEOBJECTS) ou seleciona por cliente, fazenda ou talhão |

"Classificar objetos internos com base nos limites": tudo cujo ponto
representativo cai dentro de um LIMITE_EXTERNO herda o CFT dele.

## 4. Oráculo ([src/tools/oraculo_classifica.py](../../src/tools/oraculo_classifica.py))

```text
1. rumo (norte = 0, horário): erro máx. 5.7e-14 graus
2. ponto em polígono (côncavos): 18000 testes, divergências = 0
3. área (polígonos regulares): erro relativo máx. 1.0e-15
4. código único dividido por caracteres: divergências = 0
```

## 5. Regras para o GeoIA

1. Classifique antes de exportar: CFT + tipo + nome. É o que o monitor
   entende.
2. Uma tabela só de classificação, separada dos atributos do usuário, e
   exportável como campos.
3. Cabeceira = offset do limite (para dentro do externo, para fora do
   interno), com a largura guardada. Alguns monitores exigem a mesma largura
   em todas as cabeceiras (aviso do AgroCAD para John Deere).
4. O rumo da linha AB é o azimute: norte = 0°, sentido horário, do início
   para o fim.
5. Visualização temática não pode destruir a cor original: guarde a cor e
   restaure.

## 6. Próximo passo

Exportar a classificação para os monitores. Pela escolha do usuário, John
Deere (Gen4) e CNH serão atendidos pelo formato aberto ISOXML
(ISO 11783-10, `TASKDATA.XML`), junto com Fendt e AGCO.
