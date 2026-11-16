# Catalogo de comandos AgroCAD

Gerado por `src/tools/agrocad_catalog.py` a partir do menu (.cuix) instalado.
Coluna **Porte**: comando equivalente ja recriado no menu LISPS.

Total: 406 entradas | portados: 33


## AgroCAD > NOCONNECTION

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `AGKUPDATEPND2` | NO CONNECTION |  |  |

## AgroCAD > Updated

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `AGKUPDATEOFF2` | UPDATED |  |  |

## AgroCAD > Update

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `AGKUPDATE` | UPDATE DISPONÍVEL |  | UPDATE |
| `AGKUPDATE` | DOWNLOAD |  |  |

## AgroCAD > Config

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `CSYS` | Configurar o sistema de coordenadas. | SISCOORD | Configura o sistema de coordenadas do projeto atual e permite alterar as unidades utilizadas. |
| `CFG` | Configurações Gerais |  | Configura parâmetros básicos como sistemas de coordenadas de entrada e saída de dados, tempo médio de manobra, layers e pastas padrões, espaçamentos entre linhas de cana etc. |
| `ABOUTEC` | Sobre / Help |  | Ajuda online e informações do produto |
| `DESLOGAGK` | Liberar Licença (Deslogar) |  | Libera o AgroCAD para uso em outra máquina. |
| `AGKMD` | Dados Cadastrais |  | Cadastra o desenho, informando dados básicos, como Cliente, Fazenda e Talhão |
| `AGKLANG` | Trocar idioma |  | Troca o idioma da interface do AgroCAD |

## AgroCAD > MDT

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `SUP` | Criar superfície a partir de pontos |  | Gera uma superfície que pode ser posteriormente definida a partir de pontos coletados em campo e importados. Através deste modelo, é possível visualizar e alterar as curvas de nível, triangulações e mapas de elevação e declividade. |
| `DTM` | Criar superfície a partir de arquivo DEM |  | Cria uma superfície interpolada por triangulação, utilizando arquivos em grade, como  DEM, TIF e TXT |
| `AGKS3DF` | Criar superfície a partir de 3D faces |  | Cria terreno a partir de 3D Faces geradas por outro software GIS |
| `AGKCRLIM` | Recortar Superfície |  | A partir de uma polilinha fechada representando o contorno de uma área, o comando recorta a superfície, definindo seus novos limites. |
| `AGKSMRND` | Suavizar por pontos aleatórios |  | Gera pontos aleatórios na superfície, reinterpolando e suavizando-a |
| `AGKSMGRD` | Suavizar por pontos em grade |  | Gera pontos em forma de grade sobre a superfície, reinterpolando e suavizando-a |
| `AGKSMCNT` | Suavizar por pontos nos centróides |  | Cria pontos adicionais nos centróides dos triângulos da superfície, suavizando-a |
| `AGKSMEDG` | Suavizar por pontos nos meios das arestas dos triângulos |  | Cria pontos nos vértices de cada um dos triângulos e gera mais triângulos, reinterpolando a superfície e gerando curvas mais suaves |
| `AGKGG` | Suavizar por Krigagem |  | Suaviza a superfície, adicionando pontos com base no algortitimo de krigagem |
| `AGKSIMP` | Simplificar a superfície |  | Filtra os pontos, eliminando até 5% deles a cada execução com o objetivo de simplificar a superfície |
| `AGKTRI` | Mostrar/Esconder Triângulos |  | Mostra ou esconde os triângulos da superfície |
| `AGKMXTRI` | Definir tamanho máximo dos triângulos |  | Define o tamanho máximo dos triângulos nas superfícies existentes no projeto |
| `RPTS` | Preencher região por reinterpolação |  | Apaga vértices de uma região delimitada e preenche o espaço por interpolação dos pontos vizinhos |
| `AGKEXV` | Exagerar elevação da superfície |  | Exagera a elevação da superfície, possibilitando melhor observação de sua topografia |
| `AGKALTDV` | Ajustar espaçamento de curvas |  | Ajusta o espaçamento entre as curvas de nível da superfície |
| `AGKSUPG` | Criar superfície a partir de amostragem em grade |  | Cria uma nova superfície a partir de outra, utilizando somente pontos amostrais em grade, com espaçamento configurado pelo usuário |
| `AGKDESRECO` | Revelar superfície |  | Elimina todos os limites, mostrando a superfície original |

## AgroCAD > Ajustes

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `TR-SUL` | Transformar em Sulcação | TR-SU | Troca rapidamente o layer dos objetos selecionados para o de sulcação |
| `TR-COL` | Transformar em Sulcação | TR-CO | Troca rapidamente o layer dos objetos selecionados para o de colheita |
| `TR-TAL` | Transformar em Talhão | TR-TA | Troca rapidamente o layer dos objetos selecionados para o de talhão |
| `TR-TER` | Transformar em Terraço | TR-TE | Troca rapidamente o layer dos objetos selecionados para o de terraço |
| `AECCSURFACEEXTRACTOBJECTS` | Extrair objetos da superfície |  | A partir da superfície do terreno, este comando extrai as curvas de nível, transformando-as em polilinhas que servirão como referências para o estabelecimento de terraços. Os dados obtidos são automaticamente organizados em layers, facilitando o seu manuseio. |
| `CVAR` | Extrair curvas com DV variável |  | Extrai curvas de nível do terreno em forma de polilinhas, com espaçamento vertical variável de acordo com as faixas de elevações das mesmas |
| `ECV` | Extrair curvas em cotas específicas |  | Extrai curvas de nível para polilinhas em cotas especificadas pelo usuário |
| `STER` | Criar terraço 3D |  | Cria um terraço em três dimensões sobre o terreno |
| `AGKQ` | Extrair parte de uma polilinha |  | Extrai parte de uma polilinha para utilizá-la em operações como a geração de linhas de sulcação |
| `GOBND` | Criar limites baseados em pontos |  |  |
| `RDV` | Extrair terraços com critérios metodológicos |  | Tomando como referência o tipo de solo, cultura e outros critérios agronômicos este comando sugere um espaçamento ideal entre terraços |
| `EDV` | Extrair terraços com espaçamento arbitrário |  | Permite que o usuário determine o espaçamento desejado entre terraços e faz cálculos de vazão |
| `CVL` | Converter Coverages em Linhas |  | Converte um conjunto de coverages selecionados em linhas. |
| `FCVL` | Converter Pseudo-Coverages em Linhas |  | Converte coverages sem espessura, que se assemelham a linhas, em linhas verdadeiras. |
| `TOD` | Converter pontos em coverages |  | Transforma pontos obtidos em sequência em shapefiles |
| `L2CV` | Converter curvas em coverages |  | Converte as curvas selecionadas em coverages |
| `AR2RE` | Conveter arcos de polilinhas em segmentos | SEGMENTARCOS | Converte todos os arcos dentro de uma polilinha em segmentos de reta |
| `PL32` | Converter 3D Pline para 2D |  | Converte uma polilinha 3D para 2D |
| `PL23` | Converter 2D Pline para 3D |  | Converte polilinhas 2D para 3D |
| `CVT` | Converter sistema de coordenadas |  | Transforma o desenho atual de um sistema de coordenadas para outro, sem a necessidade de abrir um novo projeto. |
| `CLL` | Converter LL gerando pontos |  | Converte uma ou mais coordenadas em Lat/Long WGS84 para o sistema de coordenadas do projeto atual, gerando pontos. |
| `RPJ` | Reprojetar coordenadas em lote |  | Reprojeta o sistema de coordenadas de um conjunto de arquivos anexados ao projeto |
| `RSC` | Remover o sistema de coordenadas |  | Remove o sistema de coordenadas do projeto |
| `VCO` | Visualizar outras coordenadas |  | Apresenta as coordenadas do projeto atual convertidas para outros sistemas ao movimentar o mouse sobre o desenho |
| `CHECKDWG` | Aplicar checagem e ajustes gerais |  | Corrige uma série de problemas de geometria e realiza ajustes necessários para a utilização do projeto no AgroCAD. |
| `PADRAO` | Migrar layers para padrões |  | Transfere o conteúdo presente em alguns layers para outros, facilitando a padronização do projeto de acordo com os moldes adequados à utilização do AgroCAD. |
| `CORL` | Ajustar propriedades para o layer |  | Ajusta as cores dos objetos para que estas sigam o padrão do layer |
| `NLCEN` | Definir o layer pelo texto do centróide |  | Coloca o polígono num layer cujo nome será igual ao texto do centroide |
| `FIL` | Selecionar objetos por filtro de dados |  | Filtra os objetos do desenho de acordo com o valor de uma propriedade agregada. |
| `DPT` | Localizar textos de coluna do Excel |  | Destaca textos no AutoCAD a partir de uma coluna do Excel copiada para a área de transferência |
| `CLE` | Apagar curvas pequenas |  | Limpa o desenho, eliminando as polilinhas menores do que um certo tamanho. |
| `DELMAN` | Apagar curvas filtradas por tipo |  | Apaga as linhas a partir de um filtro de seleção |
| `DSOB` | Apagar pontos e linhas sobrepostos |  | Apaga pontos e linhas que estejam exatamente sobrepostos |
| `RDZ` | Apagar pontos por amostragem |  | Reduz o número de pontos amostrais para que o processamento seja mais leve |
| `QCA` | Suavizar curvas para o piloto (Básico) |  | Suaviza curvas selecionadas, inserindo e removendo vértices para viabilizar a conservação da continuidade tangencial. |
| `SVZ` | Suavizar em modo avançado |  | Permite suavizar as curvas utilizando raio de giro, com mais fidelidade à geometria original |
| `RCU` | Suavizar ligação dos pontos executados |  | Redesenha a polilinha referente aos caminho executado, ligando os pontos suavemente por meio de splines, respeitando tangentes e espaçamentos desejáveis entre pontos para que as curvas fiquem adequadas para colheita. |
| `SMO` | Suavizar ajustando para spline |  | Suaviza as linhas selecionadas, ajustando suas geometrias para que sejam equivalentes a uma spline passando pelos mesmos vértices |
| `SMD` | Suavizar para spline a um dado espaçamento |  | Converte os objetos selecionados em polilinhas densas partindo de splines, fazendo amostras a um dado espaçamento |
| `SMP` | Reduzir pontos sem perda de qualidade | SIMPLIFICAPL | Reduz a quantidade de pontos de uma curva, sem, no entanto, perder significativamente a qualidade de sua geometria |
| `HME` | Padronizar espaçamentos entre vértices |  | Padroniza os espaçamentos entre os pontos ao longo de polilinhas selecionadas |
| `ADDV` | Adicionar vértices em ângulos fechados |  | Adiciona vértices em pontos críticos, onde a angulação é mais fechada |
| `NRV` | Simplificar para um número de vértices |  | Simplifica uma polilinha selecionada para que esta alcance um determinado número de vértices |
| `QBD` | Quebrar curvas por angulação |  | Quebra as polilinhas selecionadas nos vértices onde ocorre mudança brusca da angulação, o que facilita a limpeza de dados obtidos em campo. |
| `DVP` | Segmentar curvas a cada X vértices |  | Divide as polilinhas selecionadas a cada número de vértices informados pelo usuário, de modo que o processamento das linhas no campo se torne mais rápido para alguns fabricantes. |
| `QPL` | Quebrar polilinhas em diversos pontos |  | Permite que a polilinha seja dividida em vários segmentos, quebrando-as em pontos especificados pelo usuário |
| `MBR` | Quebras múltiplas entre layers |  | Utiliza os objetos de um conjunto de layers para quebrar (break) objetos de outro conjunto de layers |
| `RNOS` | Remover nós (auto-cruzamentos) |  | Remover auto-cruzamentos de um conjunto de polilinhas selecionadas |
| `PREE` | Preencher espaços |  | Preenche as falhas de registro de linhas com base nas ruas vizinhas |
| `FUN` | Apagar trechos de linhas muito próximas |  | Apaga trechos de linhas que estejam mais próximas do que uma dada medida |
| `EXQ` | Prolongar bordadura automaticamente |  | Quebra as linhas de bordadura nos pontos em que o ângulo seja mais fechado que um dado valor e prolonga automaticamente até os limites do talhão |
| `TOLIM` | Estender linhas até o limite do talhão | ESTENDELIM | Estende as linhas selecionadas até o limite da área de plantio |
| `COF` | Cortar linhas pelo limite do talhão | CORTALIM | Corta os segmentos de linhas que estejam ultrapassando os limites dos talhões selecionados |
| `ESC` | Estender e cortar linhas até o limite do talhão | AJUSTALIM | Estende e corta linhas até os limites do talhão selecionado |
| `DELIM` | Apagar objetos dentro ou fora de limite | APAGALIM | Apaga objetos inteira ou parcialmente contidos numa polilinha |
| `ZTXT` | Ajustar elevação pelo texto no centróide |  | Ajusta a elevação dos polígonos selecionados com base  nos valores dos textos dos centróides |
| `AJEL` | Ajustar elevações por object data |  | Altera a elevação dos objetos com base num campo escolhido pelo usuário. Os campos podem refletir informações originadas do procedimento de importação de arquivos Shape. |
| `DZ` | Alterar elevações da seleção |  | Altera a elevação dos objetos selecionados para um valor absoluto ou relativo |
| `DMP` | Ajustar elevações médias |  | Eleva as polilinhas selecionadas, posicionando-as na cota Z média de seus vértices, levando em consideração a superfície do terreno |
| `MESC` | Ajustar tamanhos de blocos |  | Ajusta o tamanho dos blocos selecionados, multiplicando suas dimensões atuais por um fator ou solicitando diretamente a medida final. |
| `BLP` | Converter blocos para pontos com elevações |  | Transforma os blocos selecionados em pontos com elevações |
| `ELVB` | Elevar Blocos por Atributo |  | Ajusta a elevação dos blocos selecionados para os valores contidos em seus respectivos atributos |
| `SEPA` | Separar objetos por object data |  | Separa os objetos utilizando como critério um atributo selecionado |
| `AJVEL` | Ajustar campo SPEED pela média |  | Ajusta o campo SPEED das coverages selecionadas de acordo com a média deste valor nos pontos que estiverem dentro delas |
| `LSHP` | Ligar pontos por object data |  | Liga um conjunto selecionado de pontos pela ordem de um atributo. Opcionalmente apaga os pontos após ligá-los. |
| `LIGSEL` | Ligar pontos pela ordem de seleção |  | Liga os pontos pela ordem em que os mesmos forem selecionados, interrompendo a continuidade da ligação se a distância entre o ponto e o seguinte for superior a uma determinada medida. Isto permite que pontos sem nenhum atributo de referência sejam conectados automaticamente pelo programa. |
| `LGCSV` | Conectar polígonos a CSV |  | Liga polígonos com códigos no centróide, elevação ou layer com um arquivo CSV contendo metadados |

## AgroCAD > Sistematização

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `CARP` | Acessos |  | A partir de polilinhas, cria os carreadores que permitem o acesso dos veículos à plantação. |
| `GOROA` | NOVO Criar Carreadores | CARREADORES |  |
| `DIVTAL` | Dividir talhões a partir de carreadores em nível. |  | Divide os talhões utilizando os carreadores em nível projetados como referências. |
| `SPLITAL` | Dividir talhões com base em linha |  | Utilizando uma linha como referência, divide a área selecionada respeitando critérios configuráveis |
| `UNE` | Mesclar talhões |  | Une talhões, manipulando carreadores existentes para reformar áreas de plantio de cana-de-açúcar. Permite utilizar o mesmo código para talhões fisicamente separados, computando suas áreas como uma só. |
| `AECCCREATEPARCELFROMOBJECTS` | Estudar divisões de áreas |  | Estuda as possibilidades de dividir uma área, apresentando as medidas de cada segmento e a área do polígono |
| `NT` | Numerar e inserir área |  | Insere os valores de áreas, perímetros e numerações sequenciais nos talhões, utilizando a ordem indicada pelo usuário. Opcionalmente, inclui o código completo do talhão, que pode ser ou não visualizado durante a execução. |
| `SCNT` | Escalar Numerações |  | Aumenta ou diminui o tamanho da fonte das numerações dos talhões |
| `RNT` | Renumerar talhões |  | Renumera os talhões de acordo com a ordem de seleção determinada pelo usuário. |
| `IGN` | Igualar numerações |  | Iguala os números dos talhões, que são então somados como um só na tabela de resumo dos talhões |
| `RBL` | Incluir prefixo em blocos de talhões |  | Inclui um prefixo na numeração dos talhões selecionadas, identificando um bloco |
| `NUT` | Numerar áreas entre curvas |  | Numera áreas entre curvas para posterior resumo em forma de tabela |
| `ALEC` | Inserir áreas livres entre curvas |  | Insere etiquetas apresentando a área livre entre curvas |
| `TTAL` | Tabela de Áreas |  | Gera tabela informando os códigos dos talhões e suas respectivas áreas. |
| `TUT` | Inserir tabela de áreas entre curvas |  | Cria uma tabela incluindo os dados de numeração e área das regiões entre curvas |
| `AGP` | Agrupar Talhões |  |  |
| `CENTR` | Criar centróides |  | Cria centróides no interior dos polígonos selecionados (talhões ou polilinhas fechadas comuns) |
| `OBS` | Áreas de obstáculos sobre pontos |  | Cria polilinhas ao redor de pontos que representem obstáculos mapeados no campo |
| `BFF` | Áreas de obstáculos sobre linhas |  | Delimita áreas de obstáculos a partir da vizinhança de linhas |
| `AROD` | Delimitar área de rodeiros |  | Demarca as regiões do terreno a serem percorridas por pneus ou esteiras dos veículos e classifica como áreas internas não transitáveis |
| `DES` | Incorporar limites de descontos |  | Gerar carreadores de dimensões desprezíveis, descontando polilinhas selecionadas ao computar a área total de um talhão. |
| `COVAS` | Coveamento georreferenciado |  | Posiciona covas de modo georreferenciado e alinhado sobre as linhas de plantio, facilitando a mecanização |
| `DVPT` | Inserir pontos por espaçamento |  | Divide um conjunto de linhas, polilinhas 2D ou 3D utilizando pontos a um determinado espaçamento. |
| `INV` | Inventariar dentro de um raio |  | Contabiliza o número de covas dentro de um raio especificado pelo usuário através do comando COVAS |
| `CPT` | Sulcação |  | Gera as linhas de sulcação no layer determinado nas configurações do programa, utilizando como referências as curvas de terraços, possibilitando especificar o espaçamento e a posição final das cópias. A quantidade de curvas geradas pode ser visualizada ao movimentar o mouse, na barra de status, ao lado das coordenadas. |
| `CPS` | Sulcar com uma única curva |  | Cobre todo o talhão selecionado com uma única curva de referência |
| `OFVA` | [NOVO] Offset Variável Avançado |  | Cria cópias paralelas das curvas, a espaçamentos variáveis, que podem ser salvos e carregados. |
| `OPTSUL` | Configurar opções de sulcação |  | Configura as opções padrões de sulcação, como segmentação de arcos, linhas e quebra em terraços |
| `GOFUR` | NOVO Criar Linhas | CRIALINHAS |  |
| `GODEL` | NOVO Apagar Linhas |  |  |
| `OTTI` | Otimizar cenário de linhas retas |  | Otimiza a geração de linhas retas pelos critérios de comprimento médio, total, número de manobras e declividade |
| `BDD` | Criar acabamento de cabeceira |  | Cria linhas paralelas ao contorno do talhão, como forma de acabamento |
| `CMEI` | Eliminar/manter curvas para meiosi |  | Elimina uma linha a cada X especificadas |
| `MEI1` | Meiosi de 1 linha |  | Permite criar linhas de meiosi para situações em que o implemento criará apenas uma linha |
| `COL` | Colheita |  | Gera linhas paralelas às de sulcação, com espaçamento especificado pelo usuário, armazenando-as nos layers determinados pela configuração do aplicativo. |
| `COLA` | Criar linhas de colheita assimétricas |  | A partir das linhas de sulcação, este comando cria linhas de colheita em quantidades e distâncias variáveis para cada lado. |
| `CO2` | [NOVO] Guias para colhedora de duas linhas |  |  |
| `VANTM` | Criar múltiplas linhas intermediárias |  | Cria linhas intermediárias entre as linhas selecionadas, considerando exatamente o eixo central |
| `VLT` | Criar manobra mínima |  | Desenha, entre duas linhas selecionadas, a manobra de menor comprimento ligando as tangentes |
| `GMN` | Criar novo padrão de manobra |  | Cria um novo padrão de manobra utilizando qualquer polilinha |
| `MN` | Aplicar padrão de manobra |  | Aplica um padrão de manobra sobre um conjunto de linhas |
| `ANI` | Simular circulação de veículo |  | Cria uma animação utilizando as linhas de circulação projetadas |
| `REA` | Prever pontos de reabastecimento |  | Insere marcas indicando os locais em que devem ser realizadas certas operações |
| `PAT` | Desenhar pátios de transbordo |  | Desenha os pátios de transbordo ao longo das linhas indicadas, recortando os talhões automaticamente para descontar a área |
| `SLE` | Setas logísticas de entrada |  | Insere setas logísticas indicando o sentido de entrada dos veículos |
| `SLS` | Setas logísticas de saída |  | Insere setas logísticas indicando o sentido de saída dos veículos |
| `OTMAN` | Conectar para otimizar |  | Minimiza o número de manobras, calculando a redução das mesmas ao seguir linhas contínuas de circulação entre talhões, ignorando carreadores. |
| `GOCON` | NOVO Conectar Linhas | CONECTALINHAS |  |
| `MAN2SUL` | Transformar otimização em sulcação |  | Converte as linhas de manobras otimizadas para linhas de sulcação, eliminando as linhas de sulcação pré-existentes |
| `AGKEST` | Prolongar linhas |  | Estende as linhas de sulcação para que os veículos possam utilizá-la para alinhamento antes de entrar no talhão. |
| `LOCAM` | Definir linhas de orientação |  | Gera um layer com as linhas de orientação de campo |
| `ZLOC` | Adicionar ou Remover linhas de orientação (referências) |  | Força a adição ou remoção de linhas de referência do mapa de orientação |
| `SD` | Inserir setas com sentido de sulcação |  | Insere setas ao longo de curvas, indicando as direções e sentidos das cópias paralelas para geração das linhas de sulcação. |
| `PIVO` | Projetar plantio em pivô |  | Projeta as linhas numa área circular para a utilização de irrigação com pivô |
| `IRR` | Estudar irrigação por alvo |  | Gera estudo de irrigação a partir de referência linear. |
| `IRP` | Irrigação por sistema de rolo |  | Cria projetos de irrigação por aspersão, baseados em puxadas de ramais |
| `VIR` | Inserir vírgulas ao final das curvas |  | Altera o final das linhas para que fiquem em forma de "vírgula" e realizem a contenção da água |
| `BGD` | Desenhar desaguadouros (bigodes) |  | Desenha bigodes nos pontos especificados, de acordo com o parâmetro de declividade especificado pelo usuário |
| `VRG` | Criar bigodes com geometria detalhada |  | Permite a geração de bigodes em arco, com espaçamento vertical controlado |
| `RGP` | Criar regiões paramétricas |  | Divide uma área em regiões paramétricas, cada qual associada a uma curva de referência e espaçamento específico |
| `RGD` | Excluir região paramétrica |  | Deleta uma região paramétrica interira e seus objetos associados, exceto a curva de referência |
| `RGC` | Configurar espaçamentos de curvas por região |  | Permite que sejam especificados os espaçamentos entre curvas em cada região paramétrica |
| `RGT` | Aplicar espaçamento em todas as regiões |  | Configura o mesmo espaçamento para todas as regiões paramétricas |
| `CPV` | Criar sulcos em espaçamentos variáveis |  | Cria linhas a espaçamentos VARIÁVEIS para linhas de sulcação |
| `AJC` | Criar transição suave não paralela |  | Gera linhas de sulcação a partir de duas referências selecionadas, evitando a geração de bicos. |
| `LINT` | Criar uma linha intermediária |  | Desenha a linha intermediária ideal entre duas selecionadas |
| `XCR` | Criar eixos de carreadores |  | Cria os eixos de carreadores a partir dos limites dos talhões. |
| `TMB` | Estaquear polilinhas |  | Insere "estacas" (linhas perpendiculares e equidistantes, com larguras controladas) ao longo de polilinhas selecionadas |
| `OFT` | Criar frente e costas dos terraços |  | Determina um offset da frente e costas do terraço |

## AgroCAD > Análises

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `AGKMEC` | Identificar áreas mecanizáveis |  | Faz mapa temático indicando as áreas com declividade inferior a 12% |
| `BUMPS` | Identificar terraços existentes |  | Ressalta visualmente as regiões da superfície com maior probabilidade de serem terraços existentes |
| `AECCCREATEQUICKPROFILE` | Criar perfil topográfico |  | Cria um perfil topográfico de estudo a partir da seleção de uma polilinha ou da indicação de um conjunto de pontos. |
| `AGKVOLBAG` | Calcular o volume entre superfícies |  | Calcula o volume de qualquer material que esteja armazenado sobre uma área, comparando a altimetria da superfície do pátio com a superfície do material. |
| `COMPA` | Comparar elevações de superfícies |  | Compara elevações de duas superfícies sobrepostas, classificando os valores de acordo com a aproximação percentual entre os valores de uma delas (referência) e a outra. |
| `AECCZONEOFVISUALINFLUENCE` | Campo de visão |  | Analisa o campo de visão em 360 graus ao redor de um ponto indicado pelo usuário, partindo de uma altura igualmente especificada pelo usuário. |
| `AECCPOINTTOPOINTCHECK` | Ponto a Ponto |  | Analisa a visibilidade ao longo de uma linha, utilizando para isto o modelo digital do terreno como referência. |
| `CSL` | Tematizar pela declividade ou elevação |  | Tematiza a superfície, classificando-a de acordo com um certo número de faixas de declividade ou elevação |
| `AGKSEST` | Mostrar propriedades da superfície |  | Apresenta um resumo das características geométricas da superfície |
| `CHUVA` | Simular chuva |  | Simula a incidência de chuva em todos os pontos do terreno |
| `AECCCREATESURFACEWATERDROP` | Simular escoamento no ponto |  | Desenha o caminho de escoamento da água a partir de um ponto. |
| `ACW` | Identificar pontos de acúmulo de água sobre o terreno |  | Identifica pontos que tendem a formar poças no terreno, independente de linhas |
| `ACL` | Identificar pontos de acúmulo de água ao longo das linhas |  | Identifica pontos baixos, que tendem a formar poças ao longo de linhas selecionadas |
| `AECCCATCHMENTAREA` | Delimitar microbacia |  | Partindo de um ponto indicado pelo usuário sobre a superfície, reconhece a sua respectiva área de contribuição`. |
| `AGKPLU` | Mapear pluviosidade |  | Cria mapa de pluviosidade por meio da interpolação do volume de chuva registrado em cada estação meteorológica |
| `RUSLE` | Classificar por potencial de perda de solo |  | Classifica o terreno de acordo com o seu potencial de perda de solo e estima volumes anuais |
| `DRENAG` | Simular opções de drenagem |  | Gera as curvas em desnível possíveis a partir do centro de cada triângulo |
| `DESCARGA` | Drenar para o ponto baixo |  | A partir de um ponto indicado pelo usuário, o comando identifica um caminhamento de drenagem que chegue até ele |
| `DESNIVEL` | Drenar do ponto alto |  | Traça uma curva em desnível a partir de um ponto com maior elevação especificado pelo usuário |
| `PGP` | Criar curva de transição controlada |  | Cria uma curva de drenagem em desnível |
| `SLP` | [NOVO] Curva em desnível avançada |  |  |
| `SLC` | Excesso de Declividade Longitudinal |  | Identifica trechos das guidelines em que a declividade do terreno é superior a um determinado valor limite |
| `CDE` | Classificar Declividades Longitudinais |  | Classifica os segmentos das linhas de circulação de acordo com a declividade |
| `RLAT` | Excesso de Declividade Transversal |  | Identifica trechos das guidelines em que há excesso de declividade transversal |
| `CDL` | Classificar Declividades Transversais |  | Classifica as guidelines de acordo com a declividade transversal |
| `AGKSSUL` | Setas de escoamento ao longo dos sulcos |  | Gera setas indicando o sentido de escoamento da água ao longo dos sulcos selecionados |
| `DMED` | Inserir labels de declividade média |  | Insere labels indicando a declividade média e área dentro dos talhões selecionados |
| `MAS` | Calcular a área sulcada |  | Mede a área das linhas de sulcação |
| `ARPL` | Calcular a área plantada |  | Calcula a área efetivamente ocupada com o plantio, utilizando como referência as linhas de plantio e a largura da planta |
| `ARCAR` | Calcular a área de carreadores |  | Calcula a área de carreadores no projeto com base nos layers em que se encontram os eixos dos mesmos |
| `AEC` | Calcular a área entre curvas |  | Calcula a área entre duas curvas |
| `SOMAREA` | Somar áreas de polígonos |  | Soma as áreas dos polígonos selecionados (talhões ou polilinhas comuns) |
| `MED` | Calcular estatísticas do cenário |  | Fornece o comprimento total e médio das linhas de sulcação e de cana, possibilitando analisar a eficiência da circulação dos veículos. |
| `STS` | [NOVO] Estatísticas Avançadas |  |  |
| `RCF` | Inserir resumo estatístico |  | Insere resumo estatístico no canto da folha |
| `COMPCEN` | Comparar estatísticas de cenários |  | Compara dois ou mais cenários de plantio, oferecendo subsídios para decidir qual deles é o mais adequado. |
| `APCAL` | Calculadora de agricultura de precisão |  | Faz cálculos a partir de parâmetros do cenário de agricultura de precisão. |
| `REFO` | Calcular custos de reformas |  | Calcula os custos de reformas de terraços (manutenção, construção e remoção) |
| `TSHPC` | Mapear dados de shapefile |  | Mapeia dados de shapefiles em representação contínua |
| `LEGG` | Criar legenda de mapa temático |  | Cria legenda de um mapa temático |
| `AGKTBEST` | Calcular estatísticas da aplicação |  | Insere tabela com estatísticas a respeito da aplicação representada no mapa temático |
| `TXVAR` | Mapear taxas variáveis |  | Gera mapeamentos interpolados de diversas naturezas. |
| `KPLI` | Comparar taxas planejadas x executadas |  | Compara um arquivo SHP com valores planejados para aplicação a taxas variáveis com arquivo SHP contendo valores realmente aplicados no campo |
| `TEMA` | Criar mapa temático por object data |  | Gera um mapa temático a partir de dados contidos nos objetos |
| `RELOP` | Relatório de operações no campo |  | Gera um relatório sobre os mapas temáticos referentes a operações e demais variáveis |
| `GPC` | [NOVO] Gerenciar Paletas de Cores |  | Permite criar, excluir ou alterar paletas de cores para mapas temáicos |
| `RAIOX` | Análises vetoriais |  | Disponibiliza uma série de análises que podem ser realizadas a partir dos vetores projetados e executados |
| `MPIS` | Grade de Pisoteio |  | Analisa o pisoteio em áreas grandes |
| `MSOB` | Grade de Sobreposição de Aplicação |  | Analisa a sobreposição da aplicação sem perda de qualidade |
| `MEFI` | Grade de Eficiência de Execução |  | Analisa a eficiência de execução sem perda de qualidade |
| `MCMS` | Grade de Potencial de Compactação |  | Analisa a compactação sem perda de qualidade |
| `PLL` | Analisar paralelismo vetorialmente |  | Analisa desvios de paralelismo por amostragem de distâncias ao longo das curvas |
| `ADERE` | Analisar aderëncia vetorialmente |  | Compara linhas projetadas e executadas para iidentificar fidelidade da execu~c"ao |
| `AD2` | [NOVO] Classificar Aderência |  | Classifica tematicamente a eficiência da execução |
| `SBP` | Analisar sobreposições vetorialmente |  | Identifica e calcula área e percentual de sobreposições entre polígonos |
| `DSM` | Identificar proximidade entre curvas |  | Analisa um conjunto de curvas e identifica visualmente os trechos em que elas encontram-se mais próximas que uma determinada distância |
| `ANC` | Analisar angulações de curvas |  | Analisa as curvas, identificando aquelas que não podem ser percorridas pelos veículos no campo. |
| `ADT` | Analisar desvios após suavização |  | Apresenta parâmetros estatísticos a respeito do desvio de cada curva suavizada em relação à original |
| `DREF` | Ligar talhões a pontos por proximidade |  | Liga os talhões selecionados ao ponto de referência mais próximo |
| `MAPVEL` | Mapear velocidades |  | Converte levantamentos em forma de polígonos fechados em objetos lineares e classifica os segmentos de acordo com a velocidade. |
| `CALTEM` | Calcular tempo de execução de SHP |  | Calcula o tempo total de levantamento/execução a partir de atributos de registro da hora de coleta dos dados. |
| `CLAT` | Classificar curvas pelo comprimento |  | Classifica tematicamente os tiros contínuos, possibilitando analisar a eficiência do planejamento para minimização de manobras. |
| `MDL` | Totalizar e etiquetar comprimentos |  | Mede as linhas selecionadas e opcionalmente insere um texto indicando sua medida. |
| `TBC` | Criar tabela de comprimentos de curvas |  | Cria uma tabela contendo o comprimento de cada curva |
| `CMPT` | Criar tabela de curvas por talhão |  | Cria tabela apresentando o número e área de cada talhão, altém do comprimento total e médio das curvas nele contidas |
| `RLAY` | Resumir área pela descrição do layer |  | Soma áreas, agrupando os resultados de acordo com a descrição do layer |
| `SLAY` | Somar comprimentos por layer |  | Soma o comprimento dos objetos contidos em cada layer |
| `SLT` | Somar linhas e calcular área por talhão |  | Soma linhas contidas e calcula área para cada talhão |

## AgroCAD > Documentação

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `MG` | Criar mapa geral (mosáico) |  | Integra informações de queima referentes a diversas áreas num único mapa geral, que é atualizado automaticamente quando os projetos locais são modificados. |
| `CLT` | Inserir códigos únicos nos talhões |  | Codifica os talhões, organizando-os em layers e opcionalmente inserindo o código no centróide do talhão. |
| `UCLT` | Reverter a codificação de talhões |  | Volta a apresentar as labels de número e área nos talhões que estejam apresentando códigos completos |
| `CFGCT` | Configurar estrutura de codificação dos talhões |  | Configura a forma com que os códigos de talhões deverão ser compostos |
| `GD` | Inserir malha de coordenadas (grade) |  |  |
| `LOCA` | Localizar Talhões na Grade |  | Cria tabela indicando a localização de cada um dos talhões existentes no projeto, dentro de uma grade de coordenadas previamente criada |
| `RSA` | Criar tabela de resumo para áreas líquidas |  | Resume as áreas, totalizando talhões, carreadores, matas, áreas pedregosas ou qualquer outro tipo de informação com base numa estrutura de layers que organize polilinhas fechadas. |
| `TBV` | Criar tabela de resumo para áreas genéricas |  | Cria tabela de áreas baseadas nas polilinhas selecionadas |
| `PEQ` | PEQ - Plano Estadual de Queima |  | Verifica a adequação do projeto para a formalização do plano de queima, indicando graficamente as não-conformidades para que o usuário realize as alterações necessárias. |
| `PAV` | PAV - Plano de Aplicação de Vinhaça |  | Plano de Aplicação de Vinhaça |
| `AGKLAY` | Criar layout e montar desenho na folha |  | Cria um layout utilizando a folha indicada pelo usuário e atribui uma escala |
| `TV` | Criar tabela genérica de vértices |  | Numera os vértices de uma polilinha selecionada, gera tabela contendo medidas e ângulos de cada segmento em formato DMS (graus, minutos, segundos) e listagem dos vértices, também em formato de tabela, incluindo sua numeração e coordenadas planificadas e LL. |
| `TBFIN` | Criar tabela de financiamento 2D |  | Permite selecionar áreas a serem financiadas, os vértices de referência e faz a inserção da tabela |
| `TVF` | Criar tabela de financiamento 3D |  | Gera uma tabela contendo os vértices no formato exigido para a liberação de financiamentos |
| `ETQ` | Etiquetar object data de entidades |  | Etiqueta pontos e polilinhas selecionados, incluindo informações de localização (coordenadas) e atributos importados. |
| `MTE` | Inserir labels de medidas de terraços |  | Insere textos indicando as medidas dos terraços selecionados |
| `CDT` | Identificar coordenadas de um ponto |  | Gera texto indicando coordenadas geográficas do ponto. |
| `MPT` | Marcar ponto com anotações |  | Insere a indicação de um ponto e solicita a inserção de anotações associadas a ele |
| `TXC` | Inserir nomes dos layers nos centróides |  | Insere os nomes dos layers como blocos atributados nos centróides dos talhões selecionados |
| `TXE` | Inserir elevações nos centróides |  | Insere um texto com o valor da elevação no centróide de cada polígono selecionado |
| `OCAR` | Ocultar/Exibir Área do Talhão |  | Oculta ou exibe a informação da área do talhão nos projetos e memoriza de forma independente para cada desenho. |
| `SEN` | Visualizar sentidos de curvas |  | Insere setas temporárias ao longo das linhas de sulcação obtidas a partir dos levantamentos realizados em campo, facilitando a visualização do seu sentido. |
| `TABLAY` | Gerar tabela de layers e cores |  | Gera tabela contendo os nomes de todos os layers e suas respectivas cores |
| `TUT` | Inserir tabela de áreas entre curvas |  | Cria uma tabela incluindo os dados de numeração e área das regiões entre curvas |
| `P360` | Converter Object Data em Atributos |  | Para cada objeto selecionado, identifica seus dados associados e os transforma em atributos. |
| `PTB` | Gerar tabela de atributos |  | Cria uma tabela com os atributos dos objetos selecionados |

## AgroCAD > Importação / Exportação

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `GOIMP` | [NOVO] Importação Avançada | GEOIMPORTAR |  |
| `JDIMP` | Importar Cartão |  | Importa dados de um cartão John Deere |
| `XP-JDR` | Exportar Cartão |  | Exporta os dados do projeto para um cartão no formato John Deere |
| `AYC` | Calcular produtividade de colheita |  | Calcula, a partir dos dados obtidos através do sensor de colheita de cana, qual fo a produtividade |
| `LO-SET` | Carregar Setup |  | Carrega um arquivo de setup no formato John Deere |
| `JDISETUP` | Importar CFT de Setup |  | Importa os dados de Cliente, Fazenda e Talhão disponíveis num setup John Deere |
| `OCIN` | Importar do Operations Center |  | Importa dados do Operations Center |
| `OCOUT` | Exportar para o Operations Center |  | Exporta dados do Operations Center |
| `OPSHP` | Exportar SHP para Operations Center |  | Exporta polígonos de talhões previamente classificados em CFT para o Operations Center |
| `FENDTIN` | Importar CTF Fendt |  | Importa dados de campo Fendt |
| `IXMLIN` | Importar Dados de Operações |  | Importar Dados de Operações |
| `XP-FENDT` | Exportar CTF Fendt |  | Exporta dados para Fendt |
| `CNHIN` | Importar CNH |  | Importa dados em formato CN1 |
| `XP-CNH` | Exportar CNH |  | Exporta dados para o formato CN1 |
| `TRIIN` | Importar Cartão Trimble |  | Importar Cartão |
| `XP-TRI` | Exportar Cartão Trimble |  | Exportar Cartão |
| `SHPIN` | Importar SHP AGCO |  |  |
| `EGSHP` | Exportar SHP AGCO |  |  |
| `SHPIN` | Importar SHP Topcon |  |  |
| `EGSHP` | Exportar SHP Topcon |  |  |
| `TAPIN` | Importar de TAP |  | Importa dados de Topcon Agriculture Platform |
| `XP-TAP` | Exportar para TAP |  | Exporta dados diretamente para Topcon Agriculture Platform |
| `TOPC` | Importar CSV Topcon |  | Importa arquivo CSV Topcon e cria pontos com elevação |
| `TOPV` | Ajustar polilinhas para Topcon |  | Ajusta os vértices das polilinhas para que fiquem adequados ao padrão Topcon |
| `GOEXP` | [NOVO] Exportação Avançada | GEOEXPORTAR |  |
| `VV` | Ligar/Desligar Modo de Visualização da Classificação | CLA_VER | Inicia ou encerra o modo de visualização da classificação de CFT e tipos de objetos |
| `KLA` | Classificação Avançada | CLA_GERENCIAR | Oferece várias operações de classificação de objetos para exportação num único comando |
| `CFT` | Define Cliente, Fazenda e Talhão ao qual pertencem os objetos | CLA_CFT | Define Cliente, Fazenda e Talhão ao qual pertencem os objetos |
| `RCFT` | Remover CFT | CLA_REMOVER | Desassocia Cliente, Fazenda e Talhão |
| `CPCFT` | Copiar CFT | CLA_COPIAR | Copia as informações de Cliente, Fazenda e Talhão do objeto selecionado para outros existentes |
| `CFL` | Classificação Automática de  CFT | CLA_AUTO | Classifica os objetos em Cliente, Fazenda e Talhão, de acordo com os nomes dos layers, object data, atributos de blocos ou textos |
| `JDLIN` | Definir Curvas Adaptáveis | CLA_ADAPT | Define linhas de orientação no campo |
| `CGLE` | Dividir Curvas Adaptáveis em Grupos/Glebas | CLA_GLEBA | Define a que gleba/grupo pertencem os objetos |
| `JDABC` | Definir Curva AB | CLA_CURVAAB | Define quais são as curvas AB |
| `JDABL` | Gerar Linhas AB | CLA_LINHAAB | Define quais são as linhas AB, incluindo a informação de direção como atributo |
| `JDBEX` | Definir Limite Externo | CLA_LIMEXT | Define o limite externo do talhão |
| `JDHBEX` | Cabeceiras Externas (Classificar ou Criar) | CLA_CABEXT | Classifica ou cria a área externa de manobra |
| `JDBIN` | Classificar como Limites Internos | CLA_LIMINT | Classifica objetos como limites internos (ilhas) |
| `JDHBIN` | Áreas Internas de Manobras (Classificar ou Criar) | CLA_CABINT | Classifica ou cria uma área interna de manobra |
| `ITF` | Importar Arquivo Texto Delimitado |  | Importa um arquivo de textos delimitado, resultando em pontos 3D |
| `XTAB` | Importar Planilha Excel como Tabela |  | Importa determinadas colunas e valores de uma planilha Excel como tabela |
| `XCSV` | Exportar Vértices/Layers para CSV |  | Exporta os vértices das polilinhas selecionadas e seus layers para um arquivo CSV |
| `ECSV` | Exportar Pontos e Atributos para CSV |  | Exporta as coordenadas dos pontos selecionados e todos os seus atributos para um arquivo em formato CSV |
| `RCOP` | Exportar códigos, centróides e áreas |  | Gera um CSV contendo códigos, coordenadas de centróides e áreas dos talhões selecionados |
| `XLSOUT` | Exportar atributos de blocos |  | Exporta os dados de atributo de um bloco selecionado para Excel |
| `TEP` | Exportar textos como planilha Excel |  | Exporta os textos selecionados em forma de planilha Excel , procurando manter a posição na planilha compatível com a posição relative entre os textos no desenho |
| `IKML` | Importar superfície do Google |  | Importa a superfície do Google referente à região selecionada pelo usuário no projeto |
| `GEI` | Importar imagem do Google |  | Importa a imagem do Google correspondente a uma região indicada no mapa |
| `GEB` | Visualizar imagem do Google no browser |  | Mostra a imagem do Google Maps referente à área indicada no projeto |
| `KML2` | Importar arquivo KML ou KMZ |  | Importa arquivos KML de linhas e polígonos do Google Earth |
| `EKML` | Publicar Rápido no Google Earth |  | Publica os objetos selecionados no Google Earth |
| `GKML` | Gravar KML simples (Google Earth) |  | Grava um kml com as polilinhas selecionadas, publicando-as no Google Earth |
| `GOPUB` | [NOVO] Publicar |  |  |
| `GOO` | Exportar CSV para integração com Google Earth |  | Exporta um arquivo CSV que pode ser integrado com o Google Earth para mostrar dados alfanuméricos |
| `AGKI` | Inserir imagem georreferenciada |  | Insere uma imagem georreferenciada |
| `EGR` | Gerar arquivos de georreferenciamento de imagens |  | Cria os World Files de georreferenciamento das imagens selecionadas, de acordo com suas posições arbitrárias atuais no projeto |
| `CGR` | Duplicar imagem e georreferenciar |  | Copiar imagem selecionada para outra pasta e criar o World File de georreferenciamento |
| `TBING` | Localização Geoespacial |  | Apresenta um mapa de fundo, baseado na posição geográfica do projeto. |
| `CBING` | Fixar parte da imagem do Bing |  | Recorta uma área de imagem Bing, incorporando-a offline ao projeto |
| `XP-STARA` | Exportar para Stara |  | Exporta para Stara |
| `XP-JACTO` | Exportar para Jacto |  | Exporta para o formato Jacto |
| `XP-PP` | Exportar para o Precision Planting |  | Esporta dados diretamente para o formato compatível com Precision Planting |
| `XP-RAV` | Exportar Raven |  | Exporta linhas para equipamentos Raven |
| `EGSHP` | Exportar PLA |  |  |
| `XP-IXML` | Exportar ISOXML |  | Exporta dados para o formato ISOXML |
| `AGKCVT` | Conversor de linhas projetadas |  | Converte linhas projetadas de um formato de saída para outro |
| `ESOL` | Exportar para Solinftec |  | Exporta os contornos dos talhões para o padrão exigido pela Solinftec |
| `EHEX` | Exportar para Hexagon |  | Exporta os contornos dos talhões para o padrão exigido pela Hexagon |
| `STARAIN` | Importar Stara |  | Importa arquivos de campo Stara |
| `JACTOIN` | Importar Jacto |  | Importa dados em formato Jacto |
| `PPIN` | Importar Precision Planting |  | Importa arquivos de campo do Precision Planting |
| `SHPIN` | Importar PLA |  |  |
| `IXMLIN` | Importar ISOXML |  | Importa dados em formato ISOXML |
| `LGPS` | Importar e conectar Leica |  | Liga pontos descarregados de um GPS, seguindo um parâmetro a ser escolhido como referência para o ordenamento. |
| `GPX` | Importar Pontos GPX |  | Importa um arquivo GPX em forma de pontos |
| `SHPIN` | Importar Arquivos SHP |  | Importa os dados em formato SHP fornecidos pelos equipamentos utilizados em campo, convertendo-os automaticamente para o sistema de coordenadas do projeto, que pode ser especificado nas configurações gerais do aplicativo. Além da geometria, este comando incorpora os dados associados, deixando-os disponíveis para uso em mapeamentos temáticos e outras operações. |
| `EGSHP` | Exportar arquivos SHP Genéricos |  | Exporta arquivos shape genéricos dos objetos selecionados, agrupando-os por tipo de geometria |
| `GEO` | Exportar talhões codificados para SHP |  | Exporta os talhões no formato SHP para o SIG, incluindo informações de codificação. |
| `FXR` | Exportar aplicação uniforme |  | Exporta o arquivo shape de aplicação em taxas fixas |
| `AGKMATV` | Exportar aplicação em taxas variáveis |  | Exporta arquivo shape para aplicação de produto em taxas variáveis |
| `JSHP` | Mesclar arquivos SHP |  | Une diversos shapefiles que tenham estrutura e tipo de geometria idênticos num só arquivo |
| `CCS` | Adicionar campo calculado ao shapefile |  | Com base em uma equação envolvendo campos existentes, adiciona um novo campo ao arquivo shape |
| `SHPCLE` | Limpar Arquivos Shape |  |  |
| `DSHP` | Dividir e simplificar arquivos Shape |  | Divide um arquivo shape de grande porte em vários menores, opcionalmente simplificando os objetos |

## AgroCAD > Novidades

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `WNEW` | Novidades |  | Abre o browser e lista as novidades das versões mais recentes. |
| `SUPORTE` | Pedir Suporte Técnico |  | Abre o sistema de suporte técnico do AgroCAD |

## (fora do ribbon) > -

| Comando | Nome | Porte | Descricao |
|---|---|---|---|
| `JDSIM` | Otimizar Geometria |  | Ajusta as curvas de sulcação, adapando o espaçamento dos pontos e os desvios laterais para o padrão John Deere |
| `(JDPLUGIN` | Importar Surface Water Pro |  | Importa levantamentos de áreas utilizando o Surface Water Pro |
| `AGKELV` | Tematizar pela elevação |  | Tematiza a superfície por faixas de elevação |
| `XCOO` | Exportar pontos para Shape |  | Exporta os pontos selecionados para um arquivo Shape |
| `AMO` | Indicar pontos de amostragem |  | Marca amostras sobre a superfície, indicando o tipo de vegetação a ser classificada |
| `CLA` | Classificar pixels da Imagem |  | Classifica os pixels de acordo com a coloração das amostras |
| `CONT` | Contar clusters por proximidade |  | Contabiliza o número de exemplares classificados |
| `ADDLOC` | Adicionar linhas de orientação |  | Adiciona linhas de orientação |
| `TSHPD` | Mapear Shape Discreto |  | Mapeia dados de shapefiles em formato discreto |
| `(NEXPO` | Export SHP Folder |  |  |
| `AGKADD` | Adicionar novo atalho de comando |  | Permite adicionar um novo comando à toolpalette de atalhos do AgroCAD |
| `XP-LP` | Exportar para Launch Pad |  | Exporta Dados para Launch Pad |
| `GOSTS` | Estatísticas |  |  |
| `PZOD` | Colocar Propriedades como Atributos nos Objetos |  |  |
| `GOBEZ` | Ajustes de Suavização em Curvas |  |  |
| `GOANI` | Animação e Cálculo de Falhas |  |  |
| `GOADE` | Análise de Aderência |  |  |
| `GOCOB` | Análise de Cobertura de Aplicação |  |  |
| `GOPIS` | Análise de Pisoteio |  |  |
| `GOSOB` | Análise de Sobreposição |  |  |
| `BGV` | Bigode Variável |  |  |
| `GOHLP` | Central do Conhecimento |  |  |
| `GOHME` | Controlar Distâncias entre Vértices |  |  |
| `GOTRM` | Cortar Usando Limites |  |  |
| `GOTUR` | Criar Manobras | MANOBRAS |  |
| `SLIN` | Declividade Média de Linhas |  |  |
| `GOOBS` | Desviar de Obstáculos | DESVIAOBS |  |
| `XTR` | Extrair Objetos da Superfície |  |  |
| `GOVER` | Gerar Tabela de Vértices |  |  |
| `GID` | Classificação Automática por Atributos |  |  |
| `GONUM` | Numerar Talhões |  |  |
| `GOLGP` | Ordenar e Ligar Pontos por Critério |  |  |
| `GOMEM` | Polígono a Partir de Dados de Memorial |  |  |
| `GOREF` | Previsão de Pontos de Reabastecimento |  |  |
| `GOBRX` | Quebrar e Estender |  |  |
| `GOSEP` | Separar Talhões Conectados por uma Linha |  |  |
| `GOSMP` | Simplificar Objetos | SIMPLIFICAPL |  |
| `GORES` | Tabela de Resumo de Áreas |  |  |
| `GODUP` | Tratamento ou Classificação de Objetos Sobrepostos |  |  |
| `JTAL` | Unir Talhões |  |  |
| `TAT` | Projetar Curvas Sobre a Superfície |  |  |
| `SDC` | Estudar Declividade sobre Linhas Paralelas |  |  |
| `GOIMG` | Inserir Imagem ou Altimetria Georreferenciadas |  |  |
| `GOMIN` | Distância Mínima entre Curvas |  |  |
| `GODIV` | Dividir Talhões |  |  |
| `GOLLB` | Inserir Labels com Comprimentos de Linhas |  |  |
| `GOSPL` | Quebrar Linhas para Extrair Trechos |  |  |
| `SIM` | Simulador de Linhas e Declividades |  |  |
| `UPF` | Atualizar Geometria de Talhões após Levantamento |  |  |
| `TVALV` | Tabela de Válvulas e Distâncias |  |  |
| `TLAY` | Contabilizar Objetos de Layers Específicos por Talhão |  |  |
| `XCFT` | Exportar Separando por Classificação |  |  |
| `GOCVX` | Estender Linhas de Aplicação para Cobrir |  |  |
| `GOMAT` | Pincel de Propriedades Customizado |  |  |
| `IDMAT` | Identificar Matações em Linhas Existentes |  |  |
| `NAL` | Identificar Linhas que Cruzam com Manchas para Aplicação Complementar |  |  |
| `GOJOI` | Conectar Extremidades e Fechar Cruzamentos |  |  |
| `GOCRO` | Calcular Melhor Ângulo de Cruzamento |  | Calcula o melhor ângulo para as linhas de pulverização, em comparação com as linhas existentes selecionadas |
| `GODVC` | Dividir Área com Base em Curva |  | Divide uma área em partes iguais, com base numa curva de referência selecionada |
| `GOFUN` | Encurtar Linhas de Matação em Ângulo Fechado |  | Interrompe linhas de matação antes de cruzarem com outras, se sua angulação em relação ao alvo for fechada |
| `IEL` | Inverter Cores do Mapa de Elevações |  | Inverte a paleta de cores de um mapa de elevações |
| `IIDW` | Reinterpolar Superfície pelo Método IDW |  | Reinterpola os triângulos de uma superfície, usando o método IDW, que leva em consideração o inverso da distância entre pontos amostrados |
| `TREA` | Calcular Tempos para Alcançar Pontos de Reabastecimento |  | Calcula o tempo necessário para chegar a cada ponto de reabastecimento, fazendo com que seja possível antecipar a operação. Este comando complementa o comando REA |
