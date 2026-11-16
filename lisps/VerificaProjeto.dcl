// VerificaProjeto.dcl - Verificação geral do projeto (comando VERIFICAPROJ)
verificaproj : dialog {
  label = "Verificação Geral do Projeto";
  : row {
    : boxed_column {
      label = "Correções";
      : toggle { key = "c3d";  label = "Transformar polilinhas 3D em 2D"; }
      : toggle { key = "clin"; label = "Transformar linhas em polilinhas"; }
      : row {
        : spacer { width = 3; fixed_width = true; }
        : toggle { key = "cjun"; label = "Unir linhas conectadas (mesma camada)"; }
      }
      : toggle { key = "carc"; label = "Segmentar arcos"; }
      : row {
        : spacer { width = 3; fixed_width = true; }
        : text { key = "txtarc"; label = ""; width = 46; }
      }
      : toggle { key = "cfec"; label = "Fechar talhões"; }
      : row {
        : spacer { width = 3; fixed_width = true; }
        : edit_box { key = "camtal"; label = "Camadas dos talhões:"; edit_width = 20; }
      }
      : toggle { key = "cnos"; label = "Remover nós (auto-cruzamentos e espinhos)"; }
      spacer;
    }
    : boxed_column {
      label = "Verificações (marcam com círculos)";
      : toggle { key = "ccruz";   label = "Identificar auto-cruzamentos"; }
      : toggle { key = "cpseudo"; label = "Identificar pseudo-nós"; }
      : toggle { key = "cspl";    label = "Identificar splines (conversão manual)"; }
      spacer;
      : text { label = "Marcas nas camadas VERIFICA_*"; }
      : row {
        : button { key = "todas";   label = "Marcar Todas"; }
        : button { key = "nenhuma"; label = "Desmarcar Todas"; }
      }
      spacer;
    }
  }
  : boxed_column {
    label = "Opções";
    : radio_row {
      key = "escopo";
      : radio_button { key = "tudo"; label = "Desenho inteiro"; }
      : radio_button { key = "sel";  label = "Selecionar objetos"; }
    }
    : row {
      : edit_box { key = "tol";  label = "Tolerância de ponto igual (m):"; edit_width = 8; }
      : edit_box { key = "raio"; label = "Raio das marcas (m):"; edit_width = 8; }
    }
    : toggle { key = "limpa"; label = "Apagar as marcas da verificação anterior"; }
  }
  : text { key = "error"; label = ""; width = 60; }
  : row {
    : button { key = "padrao"; label = "Valores Padrão"; fixed_width = true; }
    : button { key = "apagar"; label = "Apagar Marcas"; fixed_width = true; }
    : spacer { width = 4; }
    : button { key = "accept"; label = "Verificar"; is_default = true; fixed_width = true; width = 12; }
    : button { key = "cancel"; label = "Cancelar"; is_cancel = true; fixed_width = true; width = 12; }
  }
}
