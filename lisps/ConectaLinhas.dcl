// ConectaLinhas.dcl - Conectar Linhas entre Talhões (CONECTALINHAS)

conectalinhas : dialog {
  label = "Conectar Linhas entre Talhões";
  : boxed_column {
    label = "Critérios";
    : edit_box { key = "ang";  label = "Ângulo Máximo (°)";    edit_width = 8; }
    : edit_box { key = "esp";  label = "Espaçamento (m)";      edit_width = 8; }
    : edit_box { key = "dmax"; label = "Distância Máxima (m)"; edit_width = 8; }
    : toggle   { key = "apagar"; label = "Apagar Linhas Originais"; }
  }
  : text { key = "status"; label = ""; width = 44; }
  : row {
    : button { key = "sel";    label = "Selecionar Linhas para Otimizar"; is_default = true; }
    : button { key = "cancel"; label = "Cancelar"; is_cancel = true; fixed_width = true; width = 12; }
  }
}
