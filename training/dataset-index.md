# Índice do dataset GeoIA

## Objetivo

Este material organiza exemplos iniciais de projetos agrícolas para treinamento do GeoIA. O foco está em experiências realistas e em padrões que conectam domínio agrícola, desenho técnico e operação em campo.

## Estrutura do dataset

- `data/schema/geoia-dataset-schema.json`: schema-base para registros de projetos.
- `data/samples/`: exemplos de projetos agrícolas em formato JSON.
- `data/annotations/`: descrições e metadados complementares.

## Casos de exemplo

### Caso 1 - Soja em gleba de relevo suave

- área: 240,5 ha
- cultura: soja
- sistema: operação com trator e GNSS RTK
- objetivo: organizar talhões e rotas eficientes com mínima intervenção manual

### Caso 2 - Café em área de maior declividade

- área: 86,2 ha
- cultura: café
- sistema: pulverização guiada e operação em contorno
- objetivo: reduzir risco de erosão e melhorar a eficiência da operação

## Como usar

1. validar os registros contra o schema;
2. comparar diferentes layouts e estratégias operacionais;
3. usar como base para instrução, geração de padrões e treinamento de IA.
