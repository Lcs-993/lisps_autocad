// Carreadores.dcl - Criar Carreadores / Juntar Talhões (CARREADORES)

carreadores : dialog {
  label = "Carreadores";
  : boxed_column {
    label = "Parâmetros";
    : edit_box { key = "larg";   label = "Largura (m)"; edit_width = 8; }
    : toggle   { key = "manter"; label = "Manter os talhões originais"; }
    : toggle   { key = "apagar"; label = "Apagar Linhas de Eixos"; }
  }
  : text { key = "status"; label = ""; width = 40; }
  : row {
    : button { key = "criar";  label = "Criar Carreadores"; is_default = true; }
    : button { key = "juntar"; label = "Juntar Talhões"; }
    : button { key = "cancel"; label = "Cancelar"; is_cancel = true; }
  }
}
