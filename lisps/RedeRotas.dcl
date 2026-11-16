// RedeRotas.dcl - Validar / Corrigir a rede de rotas (RA_VALIDAR, RA_CORRIGIR)

ra_param : boxed_column {
  label = "Rede";
  : row {
    : edit_box { key = "camadas"; label = "Camadas"; edit_width = 30; }
    : button { key = "selcam"; label = "Selecionar <"; }
  }
  : edit_box { key = "ponta"; label = "Ponta solta: distância máxima X (m)"; edit_width = 8; }
  : edit_box { key = "quase"; label = "Vértices quase coincidentes até (m)"; edit_width = 8; }
  : edit_box { key = "dens";  label = "Densificação de arcos e curvas (m)"; edit_width = 8; }
  : edit_box { key = "marca"; label = "Tamanho dos marcadores (m)"; edit_width = 8; }
  : edit_box { key = "epsg";  label = "EPSG (vazio = o do desenho)"; edit_width = 8; }
  : text { key = "auto"; label = ""; width = 50; }
}

ra_validar : dialog {
  label = "Validar Rede de Rotas";
  : ra_param { }
  : text { key = "error"; label = ""; width = 50; }
  : row {
    : button { key = "accept"; label = "Validar"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}

ra_corrigir : dialog {
  label = "Corrigir Rede de Rotas";
  : ra_param { }
  : boxed_column {
    label = "Correção";
    : toggle { key = "simula";   label = "Modo simulação (só lista, não altera o desenho)"; }
    : toggle { key = "converte"; label = "Converter ARC/CIRCLE/SPLINE/ELLIPSE em polilinha"; }
    : toggle { key = "achata";   label = "Achatar o Z das polilinhas 3D e linhas (Z = 0)"; }
  }
  : text { key = "error"; label = ""; width = 50; }
  : row {
    : button { key = "accept"; label = "Corrigir"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}

// Configuração das ferramentas da Rede de Rotas (RA_REDE) - comando REDE_CONFIG
rede_config : dialog {
  label = "Configurar Rede de Rotas";
  : boxed_column {
    label = "Camadas";
    : row {
      : edit_box { key = "camadas"; label = "Camadas da rede:"; edit_width = 30; }
      : button { key = "selcam"; label = "Selecionar <"; fixed_width = true; }
    }
    : edit_box { key = "desenho";  label = "Camada de desenho (Desenhar Linha):"; edit_width = 30; }
    : edit_box { key = "maounica"; label = "Camadas de mão única:"; edit_width = 30; }
    : text { label = "Aceita curingas e vírgula. Ex.: REDE*,ESTRADAS (mão única vazia = nenhuma)"; }
  }
  : boxed_column {
    label = "Tolerâncias (m)";
    : edit_box { key = "tol";   label = "Mesmo ponto abaixo de:"; edit_width = 10; }
    : edit_box { key = "gap";   label = "Ponta solta suspeita até:"; edit_width = 10; }
    : edit_box { key = "marca"; label = "Raio dos marcadores:"; edit_width = 10; }
  }
  : text { key = "error"; label = ""; width = 60; }
  : row {
    : button { key = "padrao"; label = "Valores Padrão"; fixed_width = true; }
    : spacer { width = 8; }
    : button { key = "accept"; label = "OK"; is_default = true; fixed_width = true; width = 12; }
    : button { key = "cancel"; label = "Cancelar"; is_cancel = true; fixed_width = true; width = 12; }
  }
}
