;;; ==========================================================================
;;; SisCoord.lsp - Sistema de Coordenadas do Projeto e Unidades Gerais
;;; --------------------------------------------------------------------------
;;; Equivalente ao CSYS do AgroCAD ("Configurar coordenadas e unidades"):
;;;
;;;   Sistema de Coordenadas do Projeto Atual : lista (código Civil/Map +
;;;       descrição), Novo / Excluir (sistemas do usuário), "Utilizar este
;;;       sistema como padrão de agora em diante"
;;;   Unidades do Projeto : áreas, distâncias médias e longas, velocidades,
;;;       pesos leves/médios/pesados, volumes; "Definir essas unidades padrão
;;;       para novos projetos"
;;;
;;; Aplica o sistema pela API do Map 3D (ade_projsetwscode), que no Civil 3D
;;; é o mesmo das Configurações do Desenho > Unidades e Zona; reserva: COM do
;;; Civil 3D (UnitZoneSettings.CoordinateSystemCode). Sistema projetado (UTM)
;;; também deixa INSUNITS = 6 (metros).
;;;
;;; As unidades ficam no próprio desenho (vlax-ldata "LISPS" "UNIDADES") e
;;; servem às outras rotinas: (lisps:unidade "AG"), (lisps:converte v "AG").
;;;
;;; Desempenho: a lista de sistemas é GERADA (famílias x zonas) uma vez por
;;; sessão; o diálogo abre sem imagem/slide e sem ler arquivos grandes.
;;;
;;; Comando: SISCOORD
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Arquivos de configuração (lisps\config)
;;; --------------------------------------------------------------------------
(defun cs:pasta-lisps ()
  (cond (*LISPS-DIR*)
        ((findfile "SisCoord.dcl") (vl-filename-directory (findfile "SisCoord.dcl"))))
)
(defun cs:pasta-config (/ p)
  (setq p (if (cs:pasta-lisps)
            (strcat (cs:pasta-lisps) "\\config")
            (strcat (getvar "TEMPPREFIX") "lisps_config")))
  (if (not (vl-file-directory-p p)) (vl-mkdir p))
  p
)
(defun cs:arq (nome) (strcat (cs:pasta-config) "\\" nome))

(defun cs:le-sexp (arq / f s l v)
  (if (and (setq arq (findfile arq)) (setq f (open arq "r")))
    (progn
      (setq s "")
      (while (setq l (read-line f)) (setq s (strcat s l " ")))
      (close f)
      (setq v (vl-catch-all-apply 'read (list s)))
      (if (not (vl-catch-all-error-p v)) v)))
)
(defun cs:grava-sexp (arq v / f)
  (if (setq f (open arq "w")) (progn (prin1 v f) (close f) T))
)

;;; --------------------------------------------------------------------------
;;; Lista de sistemas de coordenadas: ((codigo descricao usuario?) ...)
;;; --------------------------------------------------------------------------
(defun cs:z2 (z) (if (< z 10) (strcat "0" (itoa z)) (itoa z)))

;;; família de UTM: prefixo do código, rótulo, zonas sul e norte
(defun cs:familia (pref rot sul norte dois / res)
  (foreach z sul
    (setq res (cons (list (strcat pref (if dois (cs:z2 z) (itoa z)) "S")
                          (strcat rot " Zona " (itoa z) " Sul") nil) res)))
  (foreach z norte
    (setq res (cons (list (strcat pref (if dois (cs:z2 z) (itoa z)) "N")
                          (strcat rot " Zona " (itoa z) " Norte") nil) res)))
  (reverse res)
)
(defun cs:faixa (a b / r) (while (<= a b) (setq r (cons a r) a (1+ a))) (reverse r))

(defun cs:embutidos ()
  (append
    (list (list "LL84" "Lat/Long WGS84" nil))
    (cs:familia "SIRGAS2000.UTM-" "Sirgas 2000" (cs:faixa 17 25) (cs:faixa 15 22) nil)
    (cs:familia "SA-SIR-" "Sirgas" (cs:faixa 17 25) (cs:faixa 15 22) nil)
    (cs:familia "UTM84-" "WGS84 UTM" (cs:faixa 1 60) (cs:faixa 1 60) T)
    (cs:familia "SAD69.UTM-" "UTM SAD69" (cs:faixa 17 25) (cs:faixa 18 22) nil)
    (cs:familia "Corrego.UTM-" "Córrego Alegre / UTM" (cs:faixa 21 25) nil nil))
)

;;; lista do AgroCAD, se instalado (só os códigos que ainda não temos)
(defun cs:do-agrocad (/ arq)
  (if (and (not COORDS_AGROCAD)
           (setq arq (findfile "C:\\Tecgraf\\AgroCAD\\Config\\COORDS-pt-BR.AGROCAD")))
    (vl-catch-all-apply 'load (list arq)))
  (if (listp COORDS_AGROCAD)
    (mapcar '(lambda (x) (list (cadr x) (car x) nil))
            (vl-remove-if-not '(lambda (x) (and (listp x) (= 'STR (type (car x))) (= 'STR (type (cadr x)))))
                              COORDS_AGROCAD)))
)

(defun cs:usuario () (cs:le-sexp (cs:arq "COORDS_USUARIO.lsd")))

(defun cs:monta-lista (/ base cod)
  (setq base (cs:embutidos))
  (foreach x (cs:do-agrocad)
    (if (not (assoc (car x) base)) (setq base (append base (list x)))))
  (foreach x (cs:usuario)
    (if (not (assoc (car x) base)) (setq base (append base (list (list (car x) (cadr x) T))))))
  base
)

;;; --------------------------------------------------------------------------
;;; Sistema de coordenadas do desenho (Map 3D / Civil 3D)
;;; --------------------------------------------------------------------------
;;; banco de dados do Civil 3D (COM), ou nil
(defun cs:civil-db (/ ver app)
  (if (and (setq ver (vl-registry-read "HKEY_CLASSES_ROOT\\AeccXUiLand.AeccApplication\\CurVer"))
           (setq app (vl-catch-all-apply 'vla-GetInterfaceObject (list (vlax-get-acad-object) ver)))
           (not (vl-catch-all-error-p app)))
    (vl-catch-all-apply 'vlax-get-property (list app 'ActiveDocument)))
)
(defun cs:civil-uz (/ doc r)
  (if (and (setq doc (cs:civil-db)) (not (vl-catch-all-error-p doc)))
    (progn
      (setq r (vl-catch-all-apply
                '(lambda () (vlax-get (vlax-get (vlax-get doc 'Settings) 'DrawingSettings) 'UnitZoneSettings))
                nil))
      (if (not (vl-catch-all-error-p r)) r)))
)

(defun cs:atual (/ r uz)
  (cond
    ((and (= 'EXRXSUBR (type ade_projgetwscode))
          (setq r (vl-catch-all-apply 'ade_projgetwscode nil))
          (not (vl-catch-all-error-p r)) (= 'STR (type r)) (/= r ""))
     r)
    ((and (setq uz (cs:civil-uz))
          (setq r (vl-catch-all-apply 'vlax-get (list uz 'CoordinateSystemCode)))
          (not (vl-catch-all-error-p r)) (= 'STR (type r)) (/= r ""))
     r))
)

;;; aplica o código; devolve T se deu certo
(defun cs:aplica (cod / r uz ok)
  (if (and (= 'EXRXSUBR (type ade_projsetwscode))
           (setq r (vl-catch-all-apply 'ade_projsetwscode (list cod)))
           (not (vl-catch-all-error-p r)) r)
    (setq ok T)
    (if (and (setq uz (cs:civil-uz))
             (not (vl-catch-all-error-p (vl-catch-all-apply 'vlax-put (list uz 'CoordinateSystemCode cod)))))
      (setq ok T)))
  (if (and ok (/= (strcase cod) "LL84")) (setvar "INSUNITS" 6))
  ok
)

;;; --------------------------------------------------------------------------
;;; Unidades do projeto
;;; --------------------------------------------------------------------------
;;; (chave rótulo ((nome fator-a-partir-do-SI) ...))
;;; SI: área m², distância média m, longa km, peso leve g, médio kg,
;;; pesado t, velocidade km/h, volume L
(setq *CS-UNID*
  (list
    (list "AG" "Áreas"              '(("ha" 1e-4) ("m²" 1.0) ("ac" 2.4710538146716534e-4)))
    (list "LM" "Distâncias Médias"  '(("m" 1.0) ("ft" 3.280839895013123)))
    (list "LG" "Distâncias Longas"  '(("km" 1.0) ("mi" 0.621371192237334)))
    (list "SG" "Velocidades"        '(("km/h" 1.0) ("mi/h" 0.621371192237334)))
    (list "WP" "Pesos Leves"        '(("g" 1.0) ("oz" 0.03527396194958041)))
    (list "WM" "Pesos Médios"       '(("kg" 1.0) ("lb" 2.204622621848776)))
    (list "WG" "Pesos Pesados"      '(("t" 1.0) ("ton (EUA)" 1.1023113109243878)))
    (list "VM" "Volumes"            '(("L" 1.0) ("gal (EUA)" 0.26417205235814845)))))

(defun cs:unid-padrao (/ v)
  (setq v (cs:le-sexp (cs:arq "UNIDADES_PADRAO.lsd")))
  (if (and (listp v) (= (length v) (length *CS-UNID*))) v
    (mapcar '(lambda (u) (car (car (caddr u)))) *CS-UNID*))
)
(defun cs:unid-desenho (/ v)
  (setq v (vlax-ldata-get "LISPS" "UNIDADES"))
  (if (and (listp v) (= (length v) (length *CS-UNID*))) v (cs:unid-padrao))
)

;;; API para as outras rotinas
(defun lisps:unidade (chave / i)
  (setq i (vl-position chave (mapcar 'car *CS-UNID*)))
  (if i (nth i (cs:unid-desenho)))
)
;;; valor no SI -> unidade do projeto
(defun lisps:converte (v chave / u)
  (if (setq u (assoc (lisps:unidade chave) (caddr (assoc chave *CS-UNID*))))
    (* v (cadr u)) v)
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun cs:preenche-lista (sel / i)
  (start_list "coord")
  (foreach x *CS-LISTA*
    (add_list (strcat (cadr x) "   [" (car x) "]" (if (caddr x) "  *" ""))))
  (end_list)
  (setq i (if sel (vl-position (strcase sel) (mapcar '(lambda (x) (strcase (car x))) *CS-LISTA*))))
  (set_tile "coord" (itoa (if i i 0)))
)

(defun cs:sel () (nth (atoi (get_tile "coord")) *CS-LISTA*))

(defun cs:novo (/ dcl r cod des)
  (setq dcl (load_dialog (strcat (cs:pasta-lisps) "\\SisCoord.dcl")))
  (if (new_dialog "siscoord_novo" dcl)
    (progn
      (action_tile "accept"
        "(setq cod (vl-string-trim \" \" (get_tile \"codigo\")) des (vl-string-trim \" \" (get_tile \"descricao\")))
         (cond ((= cod \"\") (set_tile \"error\" \"Informe o código.\"))
               ((vl-string-search \" \" cod) (set_tile \"error\" \"O código não tem espaços.\"))
               ((assoc (strcase cod) (mapcar '(lambda (x) (cons (strcase (car x)) x)) *CS-LISTA*))
                (set_tile \"error\" \"Este código já foi cadastrado!\"))
               (T (done_dialog 1)))")
      (setq r (start_dialog))))
  (unload_dialog dcl)
  (if (= r 1)
    (progn
      (if (= des "") (setq des cod))
      (cs:grava-sexp (cs:arq "COORDS_USUARIO.lsd") (append (cs:usuario) (list (list cod des))))
      cod))
)

(defun c:SISCOORD (/ *error* dcl arq r loop sel atual padrao unid acao x ok)
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (setq arq (if (cs:pasta-lisps) (strcat (cs:pasta-lisps) "\\SisCoord.dcl")))
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo SisCoord.dcl não encontrado.") (exit)))
  (if (not *CS-LISTA*) (setq *CS-LISTA* (cs:monta-lista)))
  (setq atual  (cs:atual)
        padrao (cs:le-sexp (cs:arq "COORD_PADRAO.lsd"))
        sel    (cond (atual) ((= 'STR (type padrao)) padrao))
        unid   (cs:unid-desenho)
        loop   T)
  (while loop
    (setq dcl (load_dialog arq))
    (if (not (new_dialog "siscoord" dcl)) (progn (alert "Erro ao abrir o diálogo.") (exit)))
    (cs:preenche-lista sel)
    (set_tile "atual" (strcat "Sistema atual do desenho: " (if atual atual "(nenhum)")))
    (set_tile "mantem" "0")
    (set_tile "unid_padrao" "0")
    (mapcar '(lambda (u v / i)
               (start_list (car u))
               (foreach o (caddr u) (add_list (car o)))
               (end_list)
               (setq i (vl-position v (mapcar 'car (caddr u))))
               (set_tile (car u) (itoa (if i i 0))))
            *CS-UNID* unid)
    (action_tile "novo"    "(setq sel (car (cs:sel))) (done_dialog 2)")
    (action_tile "excluir"
      "(if (caddr (cs:sel)) (progn (setq sel (car (cs:sel))) (done_dialog 3)) (set_tile \"error\" \"Só os sistemas do usuário (*) podem ser excluídos.\"))")
    (action_tile "accept"
      "(setq sel (car (cs:sel))
             acao (list (get_tile \"mantem\") (get_tile \"unid_padrao\")
                        (mapcar '(lambda (u) (car (nth (atoi (get_tile (car u))) (caddr u)))) *CS-UNID*)))
       (done_dialog 1)")
    (action_tile "cancel"  "(done_dialog 0)")
    (setq r (start_dialog))
    (unload_dialog dcl)
    (setq dcl nil)
    (cond
      ((= r 2) (if (setq x (cs:novo)) (setq *CS-LISTA* (cs:monta-lista) sel x)))
      ((= r 3)
       (setq x (nth (vl-position sel (mapcar 'car *CS-LISTA*)) *CS-LISTA*))
       (if (and x (caddr x))
         (progn
           (cs:grava-sexp (cs:arq "COORDS_USUARIO.lsd")
                          (vl-remove-if '(lambda (u) (= (strcase (car u)) (strcase (car x)))) (cs:usuario)))
           (setq *CS-LISTA* (cs:monta-lista) sel nil))))
      ((= r 1)
       (setq loop nil)
       ;; unidades no desenho (+ padrão)
       (vlax-ldata-put "LISPS" "UNIDADES" (caddr acao))
       (if (= "1" (cadr acao))
         (progn (cs:grava-sexp (cs:arq "UNIDADES_PADRAO.lsd") (caddr acao))
                (princ "\nAs unidades padrões para os próximos projetos foram alteradas!")))
       ;; sistema de coordenadas
       (if (= "1" (car acao)) (cs:grava-sexp (cs:arq "COORD_PADRAO.lsd") sel))
       (cond
         ((and atual (= (strcase atual) (strcase sel)))
          (princ (strcat "\nSistema de coordenadas mantido: " sel)))
         ((cs:aplica sel)
          (princ (strcat "\nO sistema de coordenadas do projeto foi alterado com sucesso: " sel)))
         (T (alert (strcat "Não foi possível aplicar o sistema \"" sel "\".\n"
                           "Confira se o código existe na biblioteca de coordenadas do Civil 3D/Map 3D.")))))
      (T (setq loop nil))))
  (princ)
)

(princ "\nSisCoord carregado. Comando: SISCOORD")
(princ)
