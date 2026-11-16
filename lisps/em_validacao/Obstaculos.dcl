// Obstaculos.dcl - Desvio de Obstáculos (DESVIAOBS)

obstaculos : dialog {
  label = "Desvio de Obstáculos";
  : boxed_column {
    label = "Parâmetros";
    : edit_box { key = "raio";  label = "Raio Mínimo (m)"; edit_width = 8; }
    : edit_box { key = "afast"; label = "Afastamento (m)"; edit_width = 8; }
    : edit_box { key = "dmin";  label = "Distância Mínima entre Vértices (m)"; edit_width = 8; }
    : toggle { key = "interromper"; label = "Apenas Interromper as Linhas"; }
    : toggle { key = "contornar";   label = "Contornar Todo o Obstáculo"; }
    : toggle { key = "lado";        label = "Indicar Lado Preferencial"; }
    : toggle { key = "manual";      label = "Selecionar as Linhas Manualmente"; }
  }
  : text { key = "error"; label = ""; width = 44; }
  : row {
    : button { key = "accept"; label = "Aplicar"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}
