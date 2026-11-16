// GeoImpExp.dcl - Importação / Exportação Avançada (GEOIMPORTAR, GEOEXPORTAR)

gx_importar : dialog {
  label = "Importação Avançada";
  : text { key = "arquivo"; label = ""; width = 70; }
  : boxed_column {
    label = "Motor";
    : radio_row {
      key = "motor";
      : radio_button { key = "map";     label = "Map 3D (MAPIMPORT)"; }
      : radio_button { key = "proprio"; label = "Leitor próprio (LISPS)"; }
    }
    : edit_box { key = "fmt"; label = "Código do formato no Map"; edit_width = 14; }
  }
  : boxed_column {
    label = "Importar Atributos";
    : toggle { key = "atrib"; label = "Deseja trazer também os dados dos objetos? (Object Data)"; }
    : edit_box { key = "tabela"; label = "Tabela de Object Data"; edit_width = 28; }
  }
  : boxed_column {
    label = "Camadas";
    : edit_box { key = "camada"; label = "Camada"; edit_width = 34; }
    : toggle { key = "porcampo"; label = "Camada pelo valor do campo:"; }
    : popup_list { key = "campocam"; width = 34; }
  }
  : boxed_column {
    label = "Sistema de Coordenadas";
    : edit_box { key = "src"; label = "Sistema do arquivo (vazio = o do .prj / arquivo)"; edit_width = 22; }
    : text { key = "dstinfo"; label = ""; width = 60; }
    : toggle { key = "conv"; label = "Converter para o sistema do desenho"; }
  }
  : toggle { key = "polig"; label = "Importar polígonos como polilinhas fechadas"; }
  : text { key = "error"; label = ""; width = 70; }
  : row {
    : button { key = "accept"; label = "Importar"; is_default = true; }
    : button { key = "cancel"; label = "Cancelar"; is_cancel = true; }
  }
}

gx_exportar : dialog {
  label = "Exportação Avançada";
  : boxed_column {
    label = "O que exportar";
    : radio_row {
      key = "modo";
      : radio_button { key = "cam"; label = "Camadas"; }
      : radio_button { key = "sel"; label = "Objetos selecionados"; }
    }
    : row {
      : edit_box { key = "camadas"; label = "Camadas"; edit_width = 34; }
      : button { key = "selcam"; label = "Selecionar <"; }
    }
  }
  : boxed_column {
    label = "Formato";
    : popup_list { key = "fmt"; width = 30; }
    : toggle { key = "polig"; label = "Polilinhas fechadas como polígonos"; }
    : toggle { key = "atrib"; label = "Exportar os dados dos objetos (Object Data) e a camada"; }
  }
  : boxed_column {
    label = "Sistema de Coordenadas";
    : text { key = "dstinfo"; label = ""; width = 60; }
    : toggle { key = "conv"; label = "Converter para o sistema (Map):"; }
    : edit_box { key = "crs"; label = "Código do Map"; edit_width = 24; }
    : text { label = "KML e GeoJSON saem sempre em WGS 84."; }
  }
  : text { key = "error"; label = ""; width = 70; }
  : row {
    : button { key = "accept"; label = "Exportar"; is_default = true; }
    : button { key = "cancel"; label = "Cancelar"; is_cancel = true; }
  }
}
