// CriaLinhas.dcl - Configuração do CRIALINHAS (Guidelines e Fileiras de Plantio).
// O diálogo só configura; a criação é feita pela linha de comando (CRIALINHAS).

crialinhas : dialog {
  label = "Configurar Guidelines e Fileiras";

  // ---- topo: preview | predefinições + tipo de geração
  : row {
    : boxed_column {
      label = "Pré-visualização";
      : image { key = "img"; width = 30; height = 9; fixed_width = true; fixed_height = true; color = -15; }
    }
    : column {
      : boxed_column {
        label = "Predefinições";
        : row {
          : button { key = "carregar"; label = "Carregar..."; }
          : button { key = "salvar";   label = "Salvar..."; }
        }
        : button { key = "padrao"; label = "Definir como Padrão"; }
      }
      : boxed_radio_column {
        key = "modo";
        label = "Tipo de Geração";
        : radio_button { key = "G";  label = "Somente Guidelines"; }
        : radio_button { key = "GC"; label = "Guidelines + Fileiras"; }
        : radio_button { key = "C";  label = "Somente Fileiras"; }
      }
    }
  }

  // ---- espaçamento e distribuição
  : boxed_row {
    label = "Configurações de Espaçamento e Distribuição";
    : boxed_column {
      label = "Linhas Guidelines";
      : text { label = "Extensão das linhas internas:"; }
      : radio_column {
        key = "manual";
        : radio_button { key = "auto"; label = "Automático (todo o talhão)"; }
        : radio_button { key = "man";  label = "Manual (indicar posição final)"; }
      }
      : edit_box { key = "espg"; label = "Espaçamento (m):"; edit_width = 8; }
    }
    : boxed_column {
      label = "Fileiras de Plantio";
      : edit_box { key = "qtd";  label = "Quantidade por Passada:"; edit_width = 8; }
      : edit_box { key = "espp"; label = "Espaçamento entre Fileiras (m):"; edit_width = 8; }
      : spacer { height = 1; }
    }
  }

  // ---- rodapé
  : text { key = "status"; label = ""; }
  : row {
    : button { key = "avancado"; label = "Opções Avançadas..."; fixed_width = true; }
    : spacer { width = 8; }
    : button { key = "accept"; label = "OK"; is_default = true; fixed_width = true; width = 12; }
    : button { key = "cancel"; label = "Cancelar"; is_cancel = true; fixed_width = true; width = 12; }
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
    label = "Linhas Internas";
    : toggle { key = "ambos"; label = "Sulcar os dois lados da curva de referência (sem perguntar o lado)"; }
  }
  ok_cancel;
}
