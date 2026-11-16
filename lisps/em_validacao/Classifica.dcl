// Classifica.dcl - Classificação para exportação (CLA_*)

cla_cftbloco : column {
  : boxed_column {
    label = "Cliente";
    : row {
      : popup_list { key = "cliente"; width = 28; fixed_width = true; }
      : button { key = "remover_cliente"; label = "Remover"; width = 10; fixed_width = true; }
    }
    : row {
      : edit_box { key = "novo_cliente"; label = "Novo:"; edit_limit = 20; }
      : button { key = "adicionar_cliente"; label = "Adicionar"; width = 10; fixed_width = true; }
    }
  }
  : boxed_column {
    label = "Fazenda";
    : row {
      : popup_list { key = "fazenda"; width = 28; fixed_width = true; }
      : button { key = "remover_fazenda"; label = "Remover"; width = 10; fixed_width = true; }
    }
    : row {
      : edit_box { key = "nova_fazenda"; label = "Nova:"; edit_limit = 20; }
      : button { key = "adicionar_fazenda"; label = "Adicionar"; width = 10; fixed_width = true; }
    }
  }
  : boxed_column {
    label = "Talhão/Bloco";
    : row {
      : popup_list { key = "talhao"; width = 28; fixed_width = true; }
      : button { key = "remover_talhao"; label = "Remover"; width = 10; fixed_width = true; }
    }
    : row {
      : edit_box { key = "novo_talhao"; label = "Novo:"; edit_limit = 20; }
      : button { key = "adicionar_talhao"; label = "Adicionar"; width = 10; fixed_width = true; }
    }
  }
}

cla_cft : dialog {
  label = "Classificação para Exportação";
  : cla_cftbloco { }
  : button { key = "legenda"; label = "Inserir ou Atualizar Legenda"; }
  : toggle { key = "manter"; label = "Manter os outros dados dos objetos já classificados"; }
  : text { key = "error"; label = ""; width = 50; }
  ok_cancel;
}

cla_gleba : dialog {
  label = "Classificação em Grupos/Glebas";
  : row {
    : column {
      : boxed_column {
        label = "Nome do Grupo";
        : edit_box { key = "nome"; edit_width = 15; edit_limit = 20; }
      }
      : toggle { key = "chkLayer"; label = "Usar o Nome do Layer"; }
    }
    : boxed_radio_column {
      key = "aplicar";
      label = "Aplicar";
      : radio_button { key = "app0"; label = "Apenas na(s) linha(s) selecionada(s)"; }
      : radio_button { key = "app1"; label = "Em todas as outras linhas do GRUPO selecionado"; }
      : radio_button { key = "app2"; label = "Em todas as outras linhas do LAYER da linha selecionada"; }
    }
    : boxed_radio_column {
      key = "filtro";
      label = "Filtro de CFT";
      : radio_button { key = "cft0"; label = "Não filtrar por CFT"; }
      : radio_button { key = "cft1"; label = "Somente do mesmo CFT da linha selecionada"; }
    }
  }
  ok_cancel;
}

cla_auto : dialog {
  label = "Classificar CFT Automaticamente";
  : boxed_radio_row {
    key = "metodo";
    label = "Método de Extração de CFT";
    : radio_button { key = "layer"; label = "Layer"; }
    : radio_button { key = "object_data"; label = "Object Data"; }
    : radio_button { key = "texto"; label = "Texto"; }
    : radio_button { key = "atributo"; label = "Atributo"; }
  }
  : text { key = "exemplo"; label = ""; width = 72; }
  : boxed_column {
    label = "Campo do Código Único";
    : toggle { key = "usar_unicod"; label = "Usar um único código (dividido pelo número de caracteres)"; }
    : popup_list { key = "cp_unico"; width = 40; }
  }
  : row {
    : boxed_column { label = "CLIENTE";
      : popup_list { key = "cp_cliente"; label = "Campo: "; width = 24; }
      : edit_box { key = "ch_cliente"; label = "Caracteres: "; edit_width = 4; } }
    : boxed_column { label = "FAZENDA";
      : popup_list { key = "cp_fazenda"; label = "Campo: "; width = 24; }
      : edit_box { key = "ch_fazenda"; label = "Caracteres: "; edit_width = 4; } }
  }
  : row {
    : boxed_column { label = "TALHÃO";
      : popup_list { key = "cp_talhao"; label = "Campo: "; width = 24; }
      : edit_box { key = "ch_talhao"; label = "Caracteres: "; edit_width = 4; } }
    : boxed_column { label = "NOME DO OBJETO";
      : popup_list { key = "cp_gleba"; label = "Campo: "; width = 24; }
      : edit_box { key = "ch_gleba"; label = "Caracteres: "; edit_width = 4; } }
  }
  : text { label = "Caracteres = 0: o campo inteiro (no código único: o restante)."; }
  : toggle { key = "classint"; label = "Classificar linhas internas de acordo com os limites"; }
  : toggle { key = "mapear"; label = "Preencher também os nomes dos objetos?"; }
  : text { key = "error"; label = ""; width = 72; }
  ok_cancel;
}

cla_filtro : dialog {
  label = "Filtrar Talhões por CFT";
  : cla_cftbloco { }
  : boxed_radio_row {
    key = "nivel";
    label = "Filtrar por";
    : radio_button { key = "n_cli"; label = "Cliente"; }
    : radio_button { key = "n_faz"; label = "Fazenda"; }
    : radio_button { key = "n_tal"; label = "Talhão"; value = "1"; }
  }
  : toggle { key = "isolar"; label = "Isolar Talhões Filtrados"; }
  : row {
    : button { key = "accept"; label = "Aplicar Filtro"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}

cla_gerenciar : dialog {
  label = "Classificação de Objetos para Exportação";
  : row {
    : column {
      : boxed_column {
        label = "Tipo dos Objetos (Função)";
        : popup_list { key = "tipo"; width = 30; }
        : button { key = "aplicar_tipo"; label = "Aplicar"; }
      }
      : boxed_column {
        label = "Grupo/Nome dos Objetos";
        : edit_box { key = "grupo"; edit_width = 24; }
        : button { key = "aplicar_grupo"; label = "Aplicar"; }
      }
      : boxed_column {
        label = "Gerar Mapa Temático";
        : button { key = "tema_grupo"; label = "Pelo Grupo/Nome"; }
        : button { key = "tema_tipo"; label = "Pelo Tipo de Objeto"; }
        : button { key = "tema_cft"; label = "Por Cliente, Fazenda e Talhão"; }
      }
    }
    : column {
      : boxed_column {
        label = "Cliente, Fazenda e Talhão";
        : cla_cftbloco { }
        : button { key = "aplicar_cft"; label = "Aplicar"; }
      }
      : toggle { key = "classint"; label = "Classificar Objetos Internos com Base nos Limites"; }
      : button { key = "remover"; label = "Remover Classificação"; }
    }
  }
  : text { key = "error"; label = ""; width = 60; }
  : row {
    : button { key = "accept"; label = "Salvar e Sair"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}
