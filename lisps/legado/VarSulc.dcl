// VarSulc.dcl - Sulcação com Espaçamentos Variáveis (comando VARSULC)

varsulc : dialog {
  label = "Sulcação com Espaçamentos Variáveis";
  : row {
    : boxed_column {
      label = "Sequência de espaçamentos (a partir da referência)";
      : list_box { key = "lista"; width = 52; height = 10; tabs = "5 8 20 25"; }
      : row {
        : edit_box { key = "qtd";  label = "Quantidade";    edit_width = 5; }
        : edit_box { key = "dist"; label = "Distância (m)"; edit_width = 8; }
      }
      : row {
        : edit_box { key = "lnlay"; label = "Layer da linha"; edit_width = 18; }
        : edit_box { key = "lncor"; label = "Cor"; edit_width = 4; }
      }
      : text { label = "Layer vazio = usa o layer padrão (à direita)."; }
      : row {
        : button { key = "add"; label = "Adicionar"; }
        : button { key = "alt"; label = "Alterar"; }
        : button { key = "del"; label = "Excluir"; }
      }
      : row {
        : button { key = "up";   label = "Subir"; }
        : button { key = "down"; label = "Descer"; }
      }
      : toggle { key = "repetir"; label = "Repetir (R): esta linha se repete até o fim"; }
      : text   { key = "resumo"; label = ""; width = 52; }
    }
    : column {
      : boxed_row {
        label = "Predefinições";
        : button { key = "carregar"; label = "Carregar..."; }
        : button { key = "salvar";   label = "Salvar..."; }
        : button { key = "padrao";   label = "Tornar Padrão"; }
      }
      : boxed_radio_column {
        key = "lado";
        label = "Lado das linhas";
        : radio_button { key = "U"; label = "Um lado (indicar com o mouse)"; }
        : radio_button { key = "A"; label = "Ambos os lados (espelhado)"; }
      }
      : boxed_column {
        label = "Layer padrão";
        : row {
          : edit_box { key = "lay"; label = "Layer"; edit_width = 18; }
          : edit_box { key = "cor"; label = "Cor";   edit_width = 4; }
        }
        : toggle { key = "incref"; label = "Incluir cópia da curva de referência"; }
      }
      : boxed_column {
        label = "Aplicar";
        : button { key = "talhao"; label = "Nos Talhões (recorta no limite)..."; }
        : button { key = "livre";  label = "Sem Talhão..."; }
      }
    }
  }
  : row {
    : text { key = "status"; label = ""; width = 50; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; fixed_width = true; width = 12; }
  }
}
