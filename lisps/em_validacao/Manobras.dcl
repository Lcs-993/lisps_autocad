// Manobras.dcl - Criar Manobras (MANOBRAS)

manobras : dialog {
  label = "Manobras";
  : boxed_column {
    label = "Parâmetros";
    : edit_box { key = "raio";  label = "Raio de Giro Mínimo ou Ideal [R] (m)"; edit_width = 8; }
    : edit_box { key = "afast"; label = "Afastamento [A] (m)"; edit_width = 8; }
    : edit_box { key = "dmax";  label = "Distância Máxima entre Vértices (m) - 0 = arcos"; edit_width = 8; }
  }
  : boxed_radio_column {
    key = "padrao";
    label = "Criar Manobras";
    : row {
      : radio_button { key = "N"; label = "Conectar Linhas com Manobra a Cada"; }
      : edit_box { key = "passo"; edit_width = 4; }
    }
    : radio_button { key = "C"; label = "Manobras em Caracol"; }
    : radio_button { key = "5"; label = "Manobras em 1-3-5-2-4"; }
  }
  : boxed_column {
    label = "Opções";
    : toggle { key = "cortar"; label = "Cortar Linhas para Criar Afastamento (pede a bordadura)"; }
    : toggle { key = "juntar"; label = "Juntar Trechos Conectados"; }
    : toggle { key = "apagar"; label = "Apagar Linhas Originais"; }
  }
  : text { key = "error"; label = ""; width = 50; }
  : row {
    : button { key = "accept"; label = "Aplicar"; is_default = true; }
    : button { key = "cancel"; label = "Sair"; is_cancel = true; }
  }
}
