// CriaLinhas.dcl (v2) - Linhas de Sulcação, Plantio e Colheita (CRIALINHAS / VARSULC)

crialinhas : dialog {
  label = "Linhas de Sulcação, Plantio e Colheita";
  : row {
    // ---------------------------------------------------------------- coluna 1
    : column {
      : image { key = "img"; width = 24; height = 9; fixed_width = true; fixed_height = true; color = -15; }
      : boxed_radio_column {
        key = "modo";
        label = "Linhas a serem criadas";
        : radio_button { key = "G";  label = "Somente Guias"; }
        : radio_button { key = "GC"; label = "Guias + Plantio"; }
        : radio_button { key = "C";  label = "Somente Plantio"; }
      }
      : boxed_column {
        label = "Predefinições";
        : button { key = "carregar"; label = "Carregar..."; }
        : button { key = "salvar";   label = "Salvar..."; }
        : button { key = "padrao";   label = "Tornar Padrão"; }
      }
    }
    // ---------------------------------------------------------------- coluna 2
    : boxed_column {
      label = "Linhas Guias - sequência de espaçamentos";
      : list_box { key = "lista"; width = 50; height = 8; tabs = "5 8 20 25"; }
      : row {
        : edit_box { key = "qtd";  label = "Quantidade";    edit_width = 5; }
        : edit_box { key = "dist"; label = "Distância (m)"; edit_width = 8; }
        : toggle   { key = "repetir"; label = "Repetir (R)"; }
      }
      : row {
        : edit_box { key = "lnlay"; label = "Layer da linha"; edit_width = 18; }
        : edit_box { key = "lncor"; label = "Cor"; edit_width = 4; }
      }
      : row {
        : button { key = "add";  label = "Adicionar"; }
        : button { key = "alt";  label = "Alterar"; }
        : button { key = "del";  label = "Excluir"; }
        : button { key = "up";   label = "Subir"; }
        : button { key = "down"; label = "Descer"; }
      }
      : text { key = "resumo"; label = ""; width = 50; }
      : row {
        : edit_box { key = "layg"; label = "Layer das guias"; edit_width = 18; }
        : edit_box { key = "corg"; label = "Cor"; edit_width = 4; }
      }
      : text { label = "Layer da linha vazio = layer das guias. (R) = repete até o fim."; }
    }
    // ---------------------------------------------------------------- coluna 3
    : column {
      : boxed_column {
        label = "Linhas de Plantio (em torno de cada guia)";
        : row {
          : edit_box { key = "pqtd"; label = "Quantidade"; edit_width = 4; }
          : edit_box { key = "pesp"; label = "Espaçamento (m)"; edit_width = 7; }
        }
        : row {
          : edit_box { key = "layp"; label = "Layer"; edit_width = 16; }
          : edit_box { key = "corp"; label = "Cor"; edit_width = 4; }
        }
      }
      : boxed_column {
        label = "Opções";
        : boxed_radio_row {
          key = "lado";
          label = "Lado";
          : radio_button { key = "A"; label = "Ambos"; }
          : radio_button { key = "U"; label = "Um lado (indicar)"; }
        }
        : toggle { key = "manual"; label = "Modo Manual (clicar a posição final)"; }
        : toggle { key = "incref"; label = "A curva de referência também é guia"; }
      }
    }
  }
  : row {
    : boxed_row {
      label = "Criar Linhas de Cabeceira";
      : column {
        : edit_box { key = "passadas"; label = "Passadas"; edit_width = 4; }
        : toggle   { key = "recuar"; label = "1ª a meio espaçamento"; }
      }
      : column {
        : button { key = "dentro"; label = "Para Dentro"; }
        : button { key = "fora";   label = "Para Fora"; }
      }
    }
    : boxed_row {
      label = "Criar Linhas Internas";
      : button { key = "criar"; label = "Nos Talhões"; height = 3; }
      : column {
        : button { key = "livre";      label = "Sem Talhão"; }
        : button { key = "selecionar"; label = "Plantio em Guias Existentes"; }
      }
    }
  }
  : row {
    : text { key = "status"; label = ""; width = 60; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; fixed_width = true; width = 12; }
  }
}
