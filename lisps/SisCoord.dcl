// SisCoord.dcl - Sistema de Coordenadas do Projeto e Unidades Gerais (SISCOORD)

siscoord : dialog {
  label = "Coordenadas do Projeto e Unidades Gerais";
  : boxed_column {
    label = "Sistema de Coordenadas do Projeto Atual";
    : text { key = "atual"; label = ""; width = 70; }
    : row {
      : popup_list { key = "coord"; width = 56; fixed_width = true; }
      : button { key = "excluir"; label = "Excluir"; width = 10; fixed_width = true; }
      : button { key = "novo";    label = "Novo";    width = 10; fixed_width = true; }
    }
    : toggle { key = "mantem"; label = "Utilizar este sistema como padrão de agora em diante"; }
  }
  : boxed_column {
    label = "Unidades do Projeto";
    : row {
      : column {
        : popup_list { key = "AG"; label = "Áreas";             edit_width = 10; }
        : popup_list { key = "LM"; label = "Distâncias Médias"; edit_width = 10; }
        : popup_list { key = "LG"; label = "Distâncias Longas"; edit_width = 10; }
        : popup_list { key = "SG"; label = "Velocidades";       edit_width = 10; }
      }
      : column {
        : popup_list { key = "WP"; label = "Pesos Leves";   edit_width = 10; }
        : popup_list { key = "WM"; label = "Pesos Médios";  edit_width = 10; }
        : popup_list { key = "WG"; label = "Pesos Pesados"; edit_width = 10; }
        : popup_list { key = "VM"; label = "Volumes";       edit_width = 10; }
      }
    }
    : toggle { key = "unid_padrao"; label = "Definir essas unidades padrão para novos projetos"; }
  }
  : text { key = "error"; label = ""; width = 70; }
  ok_cancel;
}

siscoord_novo : dialog {
  label = "Adicionar um novo sistema de coordenadas";
  : row {
    : boxed_row { label = "Código (Civil)"; : edit_box { key = "codigo";    edit_width = 22; } }
    : boxed_row { label = "Descrição";      : edit_box { key = "descricao"; edit_width = 50; } }
  }
  errtile;
  ok_cancel;
}
