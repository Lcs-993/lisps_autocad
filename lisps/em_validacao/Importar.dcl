// Importar.dcl - diálogo comum dos importadores (IMPKML, IMPGEOJSON, IMPSHP)

importar : dialog {
  label = "Importar Arquivo";
  : text { key = "titulo"; label = ""; width = 72; }
  : text { key = "info";   label = ""; width = 72; }
  : boxed_column {
    label = "Sistema de Coordenadas";
    : row {
      : edit_box { key = "src"; label = "EPSG de origem"; edit_width = 8; }
      : text { key = "srcinfo"; label = ""; width = 40; }
    }
    : row {
      : edit_box { key = "dst"; label = "EPSG do desenho"; edit_width = 8; }
      : text { key = "dstinfo"; label = ""; width = 40; }
    }
    : toggle { key = "reproj"; label = "Converter as coordenadas para o sistema do desenho"; }
  }
  : boxed_column {
    label = "Camadas";
    : edit_box { key = "camada"; label = "Camada (ou prefixo)"; edit_width = 34; }
    : toggle { key = "porcampo"; label = "Uma camada por valor do campo (prefixo-valor):"; }
    : popup_list { key = "campocam"; width = 40; }
  }
  : boxed_column {
    label = "Atributos";
    : radio_row {
      key = "atrib";
      : radio_button { key = "od";  label = "Object Data (Map 3D)"; }
      : radio_button { key = "xd";  label = "XDATA"; }
      : radio_button { key = "nao"; label = "Não importar"; }
    }
    : toggle { key = "rotulo"; label = "Escrever o valor de um campo como texto:"; }
    : row {
      : popup_list { key = "camporot"; width = 40; }
      : edit_box { key = "altura"; label = "Altura"; edit_width = 6; }
    }
  }
  : toggle { key = "usaz"; label = "Usar a cota Z (pontos com cota, polilinhas 3D)"; }
  : text { key = "error"; label = ""; width = 72; }
  : row {
    : button { key = "accept"; label = "Importar"; is_default = true; }
    : button { key = "cancel"; label = "Cancelar"; is_cancel = true; }
  }
}
