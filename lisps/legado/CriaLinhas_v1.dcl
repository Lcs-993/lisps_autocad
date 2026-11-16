// CriaLinhas.dcl - Linhas de Sulcação, Plantio e Colheita (comando CRIALINHAS)

crialinhas : dialog {
  label = "Linhas de Sulcação, Plantio e Colheita";
  : row {
    : image { key = "img"; width = 22; height = 12; fixed_width = true; fixed_height = true; color = -15; }
    : column {
      : boxed_row {
        label = "Predefinições";
        : button { key = "carregar"; label = "Carregar..."; }
        : button { key = "salvar";   label = "Salvar..."; }
        : button { key = "padrao";   label = "Tornar Padrão"; }
      }
      : boxed_radio_row {
        key = "modo";
        label = "Linhas a serem criadas";
        : radio_button { key = "G";  label = "Somente Guias"; }
        : radio_button { key = "GC"; label = "Guias + Plantio"; }
        : radio_button { key = "C";  label = "Somente Plantio"; }
      }
      : row {
        : boxed_column {
          label = "Linhas Guias";
          : edit_box { key = "espg"; label = "Espaçamento (m)"; edit_width = 8; }
          : toggle   { key = "manual"; label = "Modo Manual"; }
        }
        : boxed_column {
          label = "Linhas de Plantio";
          : edit_box { key = "qtd";  label = "Quantidade"; edit_width = 8; }
          : edit_box { key = "espp"; label = "Espaçamento (m)"; edit_width = 8; }
        }
      }
    }
  }
  : row {
    : boxed_row {
      label = "Criar Linhas de Cabeceira";
      : edit_box { key = "passadas"; label = "Passadas"; edit_width = 4; }
      : column {
        : button { key = "dentro"; label = "Para Dentro"; }
        : button { key = "fora";   label = "Para Fora"; }
      }
    }
    : boxed_row {
      label = "Criar Linhas Internas";
      : button { key = "criar"; label = "Criar"; height = 3; }
      : column {
        : button { key = "selecionar"; label = "Selecionar"; }
        : button { key = "avancado";   label = "Opções Avançadas..."; }
      }
    }
  }
  : row {
    : text { key = "status"; label = ""; width = 50; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; fixed_width = true; width = 12; }
  }
}

crialinhas_avancado : dialog {
  label = "Opções Avançadas";
  : boxed_column {
    label = "Layers";
    : row {
      : edit_box { key = "layg"; label = "Layer das guias";   edit_width = 18; }
      : edit_box { key = "corg"; label = "Cor"; edit_width = 4; }
    }
    : row {
      : edit_box { key = "layp"; label = "Layer do plantio";  edit_width = 18; }
      : edit_box { key = "corp"; label = "Cor"; edit_width = 4; }
    }
  }
  : boxed_column {
    label = "Linhas de Cabeceira";
    : toggle { key = "recuar"; label = "Incluir recuo na primeira passada (meio espaçamento da borda)"; }
  }
  : boxed_column {
    label = "Linhas Internas";
    : toggle { key = "ambos"; label = "Sulcar os dois lados da curva de referência (sem perguntar o lado)"; }
  }
  ok_cancel;
}
