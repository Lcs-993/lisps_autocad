// Simplifica.dcl - Simplificar Polilinhas (SIMPLIFICAPL), Segmentar Arcos (SEGMENTARCOS) e Padronizar Vértices (PADRONIZAVERT)

simplifica : dialog {
  label = "Simplificar Polilinhas";
  : boxed_column {
    label = "Parâmetros";
    : edit_box { key = "tol"; label = "Tolerância de Desvio [A] (m)"; edit_width = 8; }
    : toggle { key = "manter"; label = "Manter Objetos Originais"; }
  }
  : text { key = "error"; label = ""; width = 40; }
  : row {
    : button { key = "accept"; label = "Simplificar"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}

segarcos : dialog {
  label = "Segmentar Arcos";
  : boxed_column {
    label = "Divisão dos Arcos";
    : edit_box { key = "flecha"; label = "Desvio Máximo - flecha (m)"; edit_width = 8; }
    : toggle { key = "fixa"; label = "Usar Medida Fixa em Metros"; }
    : edit_box { key = "medida"; label = "Medida dos Segmentos (m)"; edit_width = 8; }
  }
  : boxed_column {
    label = "Objetos";
    : toggle { key = "avulsos"; label = "Incluir Arcos e Círculos Avulsos"; }
    : toggle { key = "manter";  label = "Manter Objetos Originais"; }
  }
  : text { key = "error"; label = ""; width = 40; }
  : row {
    : button { key = "accept"; label = "Aplicar"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}

hme : dialog {
  label = "Padronizar Espaçamento entre Vértices";
  : boxed_column {
    label = "Espaçamento";
    : edit_box { key = "esp"; label = "Espaçamento entre Vértices (m)"; edit_width = 8; }
    : text { label = "Cada trecho é dividido em partes iguais, com a medida mais próxima."; }
  }
  : boxed_column {
    label = "Cantos";
    : toggle { key = "cantos"; label = "Preservar Vértices de Canto"; }
    : edit_box { key = "ang"; label = "Ângulo de Canto (graus)"; edit_width = 8; }
  }
  : toggle { key = "manter"; label = "Manter Objetos Originais"; }
  : text { key = "error"; label = ""; width = 40; }
  : row {
    : button { key = "accept"; label = "Aplicar"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}
