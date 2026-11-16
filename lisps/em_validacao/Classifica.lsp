;;; ==========================================================================
;;; Classifica.lsp - Classificação de objetos para exportação (CFT e tipos)
;;; --------------------------------------------------------------------------
;;; Equivalente ao grupo de classificação do AgroCAD (base das exportações
;;; para monitores de piloto automático):
;;;   CLA_CFT       (CFT)    Cliente / Fazenda / Talhão (diálogo com cadastro)
;;;   CLA_REMOVER   (RCFT)   remove CFT ou toda a classificação
;;;   CLA_COPIAR    (CPCFT)  copia o CFT de um objeto modelo
;;;   CLA_AUTO      (CFL)    CFT automático por layer, Object Data, texto ou
;;;                          atributo de bloco (código único por caracteres)
;;;   CLA_LIMEXT    (JDBEX)  limite externo do talhão
;;;   CLA_LIMINT    (JDBIN)  limites internos (ilhas), passável ou não
;;;   CLA_CABEXT    (JDHBEX) cabeceira externa: classificar ou CRIAR (offset)
;;;   CLA_CABINT    (JDHBIN) cabeceiras internas: classificar ou CRIAR
;;;   CLA_CURVAAB   (JDABC)  curvas AB
;;;   CLA_LINHAAB   (JDABL)  linhas AB (pistas retas) com o rumo (HEADING)
;;;   CLA_ADAPT     (JDLIN)  curvas adaptáveis
;;;   CLA_GLEBA     (CGLE)   grupo/gleba (nome) das curvas
;;;   CLA_OBST / CLA_MARCO   obstáculos e marcos (flags)
;;;   CLA_GERENCIAR (KLA)    tipo + CFT + grupo num diálogo, remover, mapa temático
;;;   CLA_VER       (VV)     liga/desliga o modo de visualização (cores)
;;;   CLA_FILTRO    (TCFT)   filtra/isola talhões por CFT
;;;   CLA_LEGENDA            legenda dos CFT do desenho
;;;
;;; Armazenamento: Object Data, tabela LISPS_CFT (CLIENTE FAZENDA TALHAO TIPO
;;; NOME PASSAVEL OFFSET HEADING) - exportável pelo GEOEXPORTAR (:CAMPO@
;;; LISPS_CFT); sem Map 3D, XDATA (app LISPS_CFT). Cadastro de clientes,
;;; fazendas e talhões no próprio desenho (vlax-ldata LISPS CFT_CADASTRO).
;;; Depende de ImpComum.lsp (Object Data) e Simplifica.lsp (arcos).
;;; ==========================================================================

(vl-load-com)

(setq *CL-TAB* "LISPS_CFT"
      *CL-CAMPOS* '(("CLIENTE" "character") ("FAZENDA" "character") ("TALHAO" "character")
                    ("TIPO" "character") ("NOME" "character") ("PASSAVEL" "character")
                    ("OFFSET" "real") ("HEADING" "real"))
      *CL-TIPOS* '(("LIMITE_EXTERNO" "Limite Externo" 1) ("LIMITE_INTERNO" "Limite Interno" 30)
                   ("CABECEIRA_EXTERNA" "Cabeceira Externa" 3) ("CABECEIRA_INTERNA" "Cabeceira Interna" 4)
                   ("CURVA_AB" "Curva AB" 6) ("LINHA_AB" "Linha AB (Pista Reta)" 5)
                   ("ADAPTAVEL" "Curva Adaptável" 2) ("OBSTACULO" "Obstáculo" 8) ("MARCO" "Marco (Flag)" 7)))

;;; --------------------------------------------------------------------------
;;; Parâmetros
;;; --------------------------------------------------------------------------
(setq *CL-CHAVES* '(*CL-CLI* *CL-FAZ* *CL-TAL* *CL-MANTER* *CL-OFFSET* *CL-AUTOMET* *CL-AUTOUNI*
                    *CL-NC* *CL-NF* *CL-NT* *CL-NG* *CL-CLASSINT* *CL-NOMES* *CL-GRUPO*))
(defun cl:le-env (/ v)
  (setq *CL-CLI* "" *CL-FAZ* "" *CL-TAL* "" *CL-MANTER* T *CL-OFFSET* 12.0 *CL-AUTOMET* "layer"
        *CL-AUTOUNI* nil *CL-NC* 0 *CL-NF* 0 *CL-NT* 0 *CL-NG* 0 *CL-CLASSINT* T *CL-NOMES* nil *CL-GRUPO* "")
  (if (and (setq v (getenv "LISPS_CLASSIFICA"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v)) (listp v) (= (length v) (length *CL-CHAVES*)) (numberp (nth 4 v)))
    (mapcar 'set *CL-CHAVES* v))
)
(defun cl:grava-env () (setenv "LISPS_CLASSIFICA" (vl-prin1-to-string (mapcar 'eval *CL-CHAVES*))))
(if (not *CL-OFFSET*) (cl:le-env))

(defun cl:pasta ()
  (cond (*FT-DEV-DIR*) ((findfile "Classifica.dcl") (vl-filename-directory (findfile "Classifica.dcl"))))
)
(defun cl:requer (/ p)
  (setq p (if (cl:pasta) (strcat (cl:pasta) "\\") ""))
  (if (and (not ic:od-ok) (findfile (strcat p "ImpComum.lsp"))) (load (strcat p "ImpComum.lsp")))
  (if (and (not sp:lw-le) (findfile (strcat p "Simplifica.lsp"))) (load (strcat p "Simplifica.lsp")))
  (and ic:od-ok sp:lw-le)
)
(defun cl:lista-ss (ss / i l) (if ss (repeat (setq i (sslength ss)) (setq l (cons (ssname ss (setq i (1- i))) l)))) l)
(defun cl:tipo-nome (c) (cond ((cadr (assoc c *CL-TIPOS*))) (c)))
(defun cl:junta (l d) (if l (apply 'strcat (cons (car l) (mapcar '(lambda (s) (strcat d s)) (cdr l)))) ""))

;;; --------------------------------------------------------------------------
;;; Armazenamento: Object Data LISPS_CFT ou XDATA LISPS_CFT
;;; --------------------------------------------------------------------------
(defun cl:map-p () (ic:od-ok))
(defun cl:tabela (/ tabs)
  (if (cl:map-p)
    (progn
      (setq tabs (ic:od-tabelas))
      (if (not (member *CL-TAB* tabs))
        (vl-catch-all-apply 'ade_oddefinetab
          (list (list (cons "tablename" *CL-TAB*) '("tabledesc" . "Classificação para exportação (LISPS)")
                      (cons "columns"
                            (mapcar '(lambda (c) (list (cons "colname" (car c)) (cons "coldesc" (car c))
                                                       (cons "coltype" (cadr c))
                                                       (cons "defaultval" (if (= (cadr c) "real") 0.0 ""))))
                                    *CL-CAMPOS*))))))
      (member *CL-TAB* (ic:od-tabelas))))
)
(defun cl:tem-od (e / n)
  (and (cl:map-p) (setq n (vl-catch-all-apply 'ade_odrecordqty (list e *CL-TAB*)))
       (not (vl-catch-all-error-p n)) (> n 0))
)
;;; -> (("CLIENTE" . "x") ...) só com os campos preenchidos
(defun cl:le (e / r v ed xd)
  (if (cl:tem-od e)
    (foreach c *CL-CAMPOS*
      (setq v (vl-catch-all-apply 'ade_odgetfield (list e *CL-TAB* (car c) 0)))
      (if (and (not (vl-catch-all-error-p v)) v (not (equal v "")) (not (equal v 0.0)))
        (setq r (cons (cons (car c) v) r))))
    (progn
      (setq ed (entget e (list *CL-TAB*))
            xd (cdr (assoc *CL-TAB* (cdr (assoc -3 ed)))))
      (while (cdr xd)
        (setq v (cdr (cadr xd)))
        (if (assoc (cdr (car xd)) *CL-CAMPOS*)
          (setq r (cons (cons (cdr (car xd))
                              (if (= "real" (cadr (assoc (cdr (car xd)) *CL-CAMPOS*))) (distof v 2) v))
                        r)))
        (setq xd (cddr xd)))))
  (reverse r)
)
(defun cl:valor (e campo) (cdr (assoc campo (cl:le e))))
;;; grava (mescla) os campos dados; manter = nil apaga os outros antes
(defun cl:grava (e dados manter / atual rec xd v)
  (setq atual (if manter (cl:le e)))
  (foreach d dados (setq atual (if (assoc (car d) atual) (subst d (assoc (car d) atual) atual) (append atual (list d)))))
  (if (and (cl:map-p) (cl:tabela))
    (progn
      (if (not (cl:tem-od e))
        (progn (setq rec (vl-catch-all-apply 'ade_odnewrecord (list *CL-TAB*)))
               (vl-catch-all-apply 'ade_odaddrecord (list e *CL-TAB* rec))))
      (foreach c *CL-CAMPOS*
        (setq v (cdr (assoc (car c) atual)))
        (vl-catch-all-apply 'ade_odsetfield
          (list e *CL-TAB* (car c) 0 (if (= (cadr c) "real") (if (numberp v) (float v) 0.0) (if v (ic:texto v) "")))))
      T)
    (progn
      (if (not (tblsearch "APPID" *CL-TAB*)) (regapp *CL-TAB*))
      (foreach d atual
        (if (cdr d) (setq xd (append xd (list (cons 1000 (car d)) (cons 1000 (ic:corta (ic:texto (cdr d)) 250)))))))
      (entmod (append (vl-remove-if '(lambda (g) (= (car g) -3)) (entget e))
                      (list (list -3 (cons *CL-TAB* xd)))))))
)
;;; remove campos (nil = toda a classificação)
(defun cl:remove (e campos / atual)
  (if (null campos)
    (progn
      (if (cl:tem-od e) (vl-catch-all-apply 'ade_oddelrecord (list e *CL-TAB* 0)))
      (if (assoc -3 (entget e (list *CL-TAB*)))
        (entmod (append (vl-remove-if '(lambda (g) (= (car g) -3)) (entget e)) (list (list -3 (list *CL-TAB*)))))))
    (progn
      (setq atual (vl-remove-if '(lambda (d) (member (car d) campos)) (cl:le e)))
      (cl:remove e nil)
      (if atual (cl:grava e atual nil))))
)

;;; --------------------------------------------------------------------------
;;; Cadastro de clientes / fazendas / talhões
;;;   ((cliente (fazenda talhao ...) ...) ...)
;;; --------------------------------------------------------------------------
(defun cl:cadastro (/ c) (if (listp (setq c (vlax-ldata-get "LISPS" "CFT_CADASTRO"))) c))
(defun cl:grava-cadastro (c) (vlax-ldata-put "LISPS" "CFT_CADASTRO" c))
(defun cl:cad-add (cli faz tal / c rc rf)
  (setq c (cl:cadastro))
  (if (and cli (/= cli ""))
    (progn
      (if (not (setq rc (assoc cli c))) (setq rc (list cli) c (append c (list rc))))
      (if (and faz (/= faz ""))
        (progn
          (if (not (setq rf (assoc faz (cdr rc)))) (setq rf (list faz)))
          (if (and tal (/= tal "") (not (member tal (cdr rf)))) (setq rf (append rf (list tal))))
          (setq c (subst (if (assoc faz (cdr rc)) (subst rf (assoc faz (cdr rc)) rc) (append rc (list rf))) rc c))))
      (cl:grava-cadastro c)))
)
(defun cl:cad-rem (cli faz tal / c rc rf)
  (setq c (cl:cadastro))
  (cond
    ((and tal (setq rc (assoc cli c)) (setq rf (assoc faz (cdr rc))))
     (setq c (subst (subst (vl-remove tal rf) rf rc) rc c)))
    ((and faz (setq rc (assoc cli c)) (assoc faz (cdr rc)))
     (setq c (subst (vl-remove (assoc faz (cdr rc)) rc) rc c)))
    ((and cli (assoc cli c)) (setq c (vl-remove (assoc cli c) c))))
  (cl:grava-cadastro c)
)
;;; junta ao cadastro o CFT de todos os objetos classificados do desenho
(defun cl:cad-do-desenho (/ ss d)
  (if (setq ss (ssget "_X" '((410 . "Model"))))
    (foreach e (cl:lista-ss ss)
      (if (setq d (cl:le e))
        (cl:cad-add (cdr (assoc "CLIENTE" d)) (cdr (assoc "FAZENDA" d)) (cdr (assoc "TALHAO" d))))))
)
(defun cl:clientes () (mapcar 'car (cl:cadastro)))
(defun cl:fazendas (cli) (mapcar 'car (cdr (assoc cli (cl:cadastro)))))
(defun cl:talhoes (cli faz) (cdr (assoc faz (cdr (assoc cli (cl:cadastro))))))

;;; --------------------------------------------------------------------------
;;; Geometria
;;; --------------------------------------------------------------------------
;;; vértices 2D (arcos densificados) de uma curva fechada/aberta; nil se não for
(defun cl:pts (e / ed tp)
  (setq ed (entget e) tp (cdr (assoc 0 ed)))
  (cond
    ((= tp "LWPOLYLINE")
     (mapcar '(lambda (r) (list (car (car r)) (cadr (car r))))
             (car (sp:segmenta-recs (cadr (sp:lw-le ed)) (= 1 (logand 1 (cdr (assoc 70 ed)))) 'FLECHA 0.05))))
    ((and (= tp "POLYLINE") (= 0 (logand 80 (cdr (assoc 70 ed)))))
     (mapcar '(lambda (r) (list (car (car r)) (cadr (car r))))
             (car (sp:segmenta-recs (sp:pl-le e) (= 1 (logand 1 (cdr (assoc 70 ed)))) 'FLECHA 0.05))))
    ((member tp '("CIRCLE" "ELLIPSE" "SPLINE" "ARC"))
     (cl:amostra e))
    ((= tp "LINE") (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))
    ((member tp '("POINT" "INSERT" "TEXT" "MTEXT")) (list (cdr (assoc 10 ed)))))
)
(defun cl:amostra (e / L n k r)
  (setq L (vlax-curve-getDistAtParam e (vlax-curve-getEndParam e)) n 64 k 0)
  (while (< k n) (setq r (cons (vlax-curve-getPointAtDist e (/ (* L k) n)) r) k (1+ k)))
  (reverse r)
)
(defun cl:fechada-p (e / tp ed)
  (setq ed (entget e) tp (cdr (assoc 0 ed)))
  (cond ((member tp '("LWPOLYLINE" "POLYLINE")) (= 1 (logand 1 (cdr (assoc 70 ed)))))
        ((= tp "CIRCLE") T)
        ((member tp '("SPLINE" "ELLIPSE")) (vlax-curve-isClosed e)))
)
;;; ponto dentro do polígono (pares/ímpares)
(defun cl:dentro (p pol / x y d a b)
  (setq x (car p) y (cadr p) d nil)
  (mapcar '(lambda (a b)
             (if (and (/= (> (cadr a) y) (> (cadr b) y))
                      (< x (+ (car a) (/ (* (- (car b) (car a)) (- y (cadr a))) (- (cadr b) (cadr a))))))
               (setq d (not d))))
          pol (append (cdr pol) (list (car pol))))
  d
)
;;; ponto representativo do objeto (1º vértice; para fechados, a média)
(defun cl:ponto (e / p)
  (setq p (cl:pts e))
  (if (and (cl:fechada-p e) (cddr p))
    (list (/ (apply '+ (mapcar 'car p)) (length p)) (/ (apply '+ (mapcar 'cadr p)) (length p)))
    (car p))
)
(defun cl:area (pts / a) (setq a 0.0)
  (mapcar '(lambda (p q) (setq a (+ a (- (* (car p) (cadr q)) (* (car q) (cadr p)))))) pts (append (cdr pts) (list (car pts))))
  (abs (/ a 2.0))
)
;;; rumo (azimute, graus a partir do norte, horário) de p0 -> p1
(defun cl:rumo (p0 p1 / a)
  (setq a (- 90.0 (* (/ 180.0 pi) (angle p0 p1))))
  (while (< a 0.0) (setq a (+ a 360.0)))
  (while (>= a 360.0) (setq a (- a 360.0)))
  a
)

;;; --------------------------------------------------------------------------
;;; Aplicar classificação
;;; --------------------------------------------------------------------------
(defun cl:cft-atual () (list (cons "CLIENTE" *CL-CLI*) (cons "FAZENDA" *CL-FAZ*) (cons "TALHAO" *CL-TAL*)))
(defun cl:aplica (ents dados manter / n)
  (setq n 0)
  (foreach e ents (if (cl:grava e dados manter) (setq n (1+ n))))
  n
)
;;; objetos dentro dos limites externos herdam o CFT do limite
(defun cl:internos (/ ss todos lims n d pol)
  (setq n 0 todos (cl:lista-ss (ssget "_X" '((410 . "Model")))))
  (foreach e todos (if (= "LIMITE_EXTERNO" (cl:valor e "TIPO")) (setq lims (cons (list e (cl:pts e) (cl:le e)) lims))))
  (foreach e todos
    (if (and (not (assoc e lims)) (/= "LIMITE_EXTERNO" (cl:valor e "TIPO")))
      (foreach l lims
        (if (and (cddr (cadr l)) (cl:ponto e) (cl:dentro (cl:ponto e) (cadr l)))
          (progn
            (setq d (vl-remove-if-not '(lambda (x) (member (car x) '("CLIENTE" "FAZENDA" "TALHAO"))) (caddr l)))
            (if d (progn (cl:grava e d T) (setq n (1+ n)))))))))
  n
)
(defun cl:sel (msg filtro / ss)
  (princ msg)
  (setq ss (if filtro (ssget filtro) (ssget)))
  (cl:lista-ss ss)
)
(setq *CL-F-CURVAS* '((-4 . "<OR") (0 . "LWPOLYLINE") (0 . "POLYLINE") (0 . "LINE") (0 . "ARC")
                      (0 . "SPLINE") (0 . "CIRCLE") (0 . "ELLIPSE") (-4 . "OR>"))
      *CL-F-FECHADAS* '((-4 . "<OR") (-4 . "<AND") (0 . "LWPOLYLINE,POLYLINE") (-4 . "&") (70 . 1) (-4 . "AND>")
                        (0 . "CIRCLE") (0 . "SPLINE") (0 . "ELLIPSE") (-4 . "OR>"))
      *CL-F-PONTOS* '((0 . "POINT,INSERT,CIRCLE,LWPOLYLINE,POLYLINE")))

(defun cl:undo (f / doc r)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (vla-StartUndoMark doc)
  (setq r (vl-catch-all-apply f nil))
  (vla-EndUndoMark doc)
  (if (vl-catch-all-error-p r) (princ (strcat "\nErro: " (vl-catch-all-error-message r))))
  (princ)
)
(defun cl:classifica-tipo (tipo msg filtro extra / ents n)
  (if (setq ents (cl:sel msg filtro))
    (progn
      (setq n (cl:aplica ents (append (list (cons "TIPO" tipo)) extra) T))
      (princ (strcat "\n" (itoa n) " objeto(s) classificado(s) como " (cl:tipo-nome tipo) "."))
      (if (and *CL-CLASSINT* (= tipo "LIMITE_EXTERNO"))
        (princ (strcat " " (itoa (cl:internos)) " objeto(s) interno(s) receberam o CFT do limite.")))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Diálogo CFT (Classificação para Exportação)
;;; --------------------------------------------------------------------------
(defun cl:popula (k itens sel / i)
  (start_list k) (mapcar 'add_list itens) (end_list)
  (setq i (vl-position sel itens))
  (set_tile k (if i (itoa i) (if itens "0" "")))
)
(defun cl:atu-cft (/ c f)
  (setq c (cl:clientes))
  (if (not (member *CL-CLI* c)) (setq *CL-CLI* (if c (car c) "")))
  (cl:popula "cliente" c *CL-CLI*)
  (setq f (cl:fazendas *CL-CLI*))
  (if (not (member *CL-FAZ* f)) (setq *CL-FAZ* (if f (car f) "")))
  (cl:popula "fazenda" f *CL-FAZ*)
  (setq f (cl:talhoes *CL-CLI* *CL-FAZ*))
  (if (not (member *CL-TAL* f)) (setq *CL-TAL* (if f (car f) "")))
  (cl:popula "talhao" f *CL-TAL*)
)
(defun cl:sel-tile (k v / l)
  (setq l (cond ((= k "cliente") (cl:clientes)) ((= k "fazenda") (cl:fazendas *CL-CLI*)) (T (cl:talhoes *CL-CLI* *CL-FAZ*))))
  (if (and l (/= v ""))
    (cond ((= k "cliente") (setq *CL-CLI* (nth (atoi v) l) *CL-FAZ* "" *CL-TAL* ""))
          ((= k "fazenda") (setq *CL-FAZ* (nth (atoi v) l) *CL-TAL* ""))
          (T (setq *CL-TAL* (nth (atoi v) l)))))
  (cl:atu-cft)
)
(defun cl:adiciona (k / v)
  (setq v (strcase (vl-string-trim " " (get_tile (cdr (assoc k '(("cliente" . "novo_cliente") ("fazenda" . "nova_fazenda") ("talhao" . "novo_talhao"))))))))
  (cond
    ((= v "") (set_tile "error" "Digite o nome antes de adicionar."))
    ((= k "cliente") (cl:cad-add v nil nil) (setq *CL-CLI* v *CL-FAZ* "" *CL-TAL* ""))
    ((= *CL-CLI* "") (set_tile "error" "É preciso selecionar um cliente antes."))
    ((= k "fazenda") (cl:cad-add *CL-CLI* v nil) (setq *CL-FAZ* v *CL-TAL* ""))
    ((= *CL-FAZ* "") (set_tile "error" "É preciso selecionar uma fazenda antes."))
    (T (cl:cad-add *CL-CLI* *CL-FAZ* v) (setq *CL-TAL* v)))
  (cl:atu-cft)
)
(defun cl:remove-cad (k)
  (cond ((= k "cliente") (cl:cad-rem *CL-CLI* nil nil) (setq *CL-CLI* ""))
        ((= k "fazenda") (cl:cad-rem *CL-CLI* *CL-FAZ* nil) (setq *CL-FAZ* ""))
        (T (cl:cad-rem *CL-CLI* *CL-FAZ* *CL-TAL*) (setq *CL-TAL* "")))
  (cl:atu-cft)
)
(defun cl:acoes-cft ()
  (foreach k '("cliente" "fazenda" "talhao")
    (action_tile k (strcat "(cl:sel-tile \"" k "\" $value)"))
    (action_tile (strcat "remover_" k) (strcat "(cl:remove-cad \"" k "\")")))
  (action_tile "adicionar_cliente" "(cl:adiciona \"cliente\")")
  (action_tile "adicionar_fazenda" "(cl:adiciona \"fazenda\")")
  (action_tile "adicionar_talhao" "(cl:adiciona \"talhao\")")
)
(defun cl:dcl (nome ini acoes / dcl arq r)
  (setq arq (if (cl:pasta) (strcat (cl:pasta) "\\Classifica.dcl")))
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo Classifica.dcl não encontrado.") (exit)))
  (setq dcl (load_dialog arq))
  (if (not (new_dialog nome dcl)) (progn (unload_dialog dcl) (exit)))
  (if ini (apply ini nil))
  (if acoes (apply acoes nil))
  (action_tile "cancel" "(done_dialog 0)")
  (setq r (start_dialog))
  (unload_dialog dcl)
  r
)

(defun c:CLA_CFT (/ r ents)
  (if (cl:requer)
    (progn
      (cl:cad-do-desenho)
      (setq r 2)
      (while (member r '(2))
        (setq r (cl:dcl "cla_cft"
                        '(lambda () (cl:atu-cft) (set_tile "manter" (if *CL-MANTER* "1" "0")))
                        '(lambda () (cl:acoes-cft)
                           (action_tile "legenda" "(done_dialog 2)")
                           (action_tile "accept" "(setq *CL-MANTER* (= \"1\" (get_tile \"manter\"))) (if (= *CL-TAL* \"\") (set_tile \"error\" \"Escolha Cliente, Fazenda e Talhão.\") (done_dialog 1))"))))
        (if (= r 2) (cl:legenda)))
      (cl:grava-env)
      (if (and (= r 1) (setq ents (cl:sel (strcat "\nSelecione os objetos de " *CL-CLI* " / " *CL-FAZ* " / " *CL-TAL* ": ") nil)))
        (cl:undo '(lambda () (princ (strcat "\nCFT aplicado em " (itoa (cl:aplica ents (cl:cft-atual) *CL-MANTER*)) " objeto(s).")))))))
  (princ)
)

(defun c:CLA_REMOVER (/ op ents)
  (if (cl:requer)
    (progn
      (initget "Cft Tudo")
      (setq op (cond ((getkword "\nRemover [Cft/Tudo (CFT + tipo + nome)] <Cft>: ")) ("Cft")))
      (if (setq ents (cl:sel "\nSelecione os objetos: " nil))
        (cl:undo '(lambda ()
                    (foreach e ents (cl:remove e (if (= op "Tudo") nil '("CLIENTE" "FAZENDA" "TALHAO"))))
                    (princ (strcat "\nClassificação removida de " (itoa (length ents)) " objeto(s).")))))))
  (princ)
)

(defun c:CLA_COPIAR (/ m d ents)
  (if (and (cl:requer) (setq m (car (entsel "\nSelecione o objeto modelo para Cliente, Fazenda e Talhão: "))))
    (if (not (setq d (vl-remove-if-not '(lambda (x) (member (car x) '("CLIENTE" "FAZENDA" "TALHAO"))) (cl:le m))))
      (princ "\nO objeto modelo não tem CFT.")
      (if (setq ents (cl:sel "\nSelecione os objetos que receberão o CFT: " nil))
        (cl:undo '(lambda () (princ (strcat "\nCFT copiado para " (itoa (cl:aplica ents d T)) " objeto(s).")))))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Tipos de objeto
;;; --------------------------------------------------------------------------
(defun c:CLA_LIMEXT () (if (cl:requer) (cl:classifica-tipo "LIMITE_EXTERNO" "\nSelecione os limites externos: " *CL-F-FECHADAS* nil)) (princ))
(defun c:CLA_LIMINT (/ p)
  (if (cl:requer)
    (progn
      (initget "Sim Nao")
      (setq p (cond ((getkword "\nLimites internos são passáveis (a máquina pode atravessar)? [Sim/Nao] <Nao>: ")) ("Nao")))
      (cl:classifica-tipo "LIMITE_INTERNO" "\nSelecione os limites internos: " *CL-F-FECHADAS*
                          (list (cons "PASSAVEL" (if (= p "Sim") "S" "N"))))))
  (princ)
)
(defun c:CLA_CURVAAB () (if (cl:requer) (cl:classifica-tipo "CURVA_AB" "\nSelecione as curvas AB: " *CL-F-CURVAS* nil)) (princ))
(defun c:CLA_ADAPT ()
  (if (cl:requer) (cl:classifica-tipo "ADAPTAVEL" "\nSelecione as curvas adaptáveis: " *CL-F-CURVAS*
                                      (if (/= *CL-GRUPO* "") (list (cons "NOME" *CL-GRUPO*)))))
  (princ)
)
(defun c:CLA_OBST () (if (cl:requer) (cl:classifica-tipo "OBSTACULO" "\nSelecione os obstáculos (pontos, círculos ou polígonos): " *CL-F-PONTOS* nil)) (princ))
(defun c:CLA_MARCO (/ nome)
  (if (cl:requer)
    (progn
      (setq nome (getstring T "\nNome dos marcos <Marco>: "))
      (cl:classifica-tipo "MARCO" "\nSelecione os pontos dos marcos: " '((0 . "POINT,INSERT"))
                          (list (cons "NOME" (if (= nome "") "Marco" nome))))))
  (princ)
)

;;; Linhas AB: classifica as linhas selecionadas (rumo do início para o fim)
;;; ou, com Enter, cria a linha por dois pontos A e B
(defun c:CLA_LINHAAB (/ ents a b e n p)
  (if (cl:requer)
    (progn
      (princ "\nSelecione as linhas AB ou [Enter] para indicar os pontos A e B: ")
      (setq ents (cl:lista-ss (ssget '((0 . "LINE,LWPOLYLINE,POLYLINE")))))
      (if (and (null ents) (setq a (getpoint "\nPonto A: ")) (setq b (getpoint a "\nPonto B: ")))
        (setq ents (list (entmakex (list '(0 . "LINE") (cons 8 (getvar "CLAYER")) (cons 10 a) (cons 11 b))))))
      (if ents
        (cl:undo
          '(lambda ()
             (setq n 0)
             (foreach e ents
               (setq p (cl:pts e))
               (if (cdr p)
                 (progn
                   (cl:grava e (list (cons "TIPO" "LINHA_AB") (cons "HEADING" (cl:rumo (car p) (last p)))) T)
                   (setq n (1+ n)))))
             (princ (strcat "\n" (itoa n) " linha(s) AB classificada(s) com o rumo (HEADING, graus do norte).")))))))
  (princ)
)

;;; Cabeceiras: selecionar limites para CRIAR (offset) ou Enter para CLASSIFICAR
(defun cl:offset-dentro (e larg fora / o r a0 c res)
  (setq o (vlax-ename->vla-object e) a0 (cl:area (cl:pts e)))
  (foreach s (list larg (- larg))
    (setq r (vl-catch-all-apply 'vlax-invoke (list o 'Offset s)))
    (if (and (not (vl-catch-all-error-p r)) r)
      (foreach c r
        (if (if fora (> (vla-get-Area c) a0) (< (vla-get-Area c) a0))
          (setq res (cons c res))
          (vla-delete c)))))
  res
)
(defun cl:cabeceira (tipo base-tipo msg fora / ents larg n d novos)
  (princ msg)
  (setq ents (cl:lista-ss (ssget *CL-F-FECHADAS*)))
  (if ents
    (progn
      (setq larg (getdist (strcat "\nLargura da cabeceira (m) <" (rtos *CL-OFFSET* 2 2) ">: ")))
      (if larg (setq *CL-OFFSET* larg))
      (cl:grava-env)
      (cl:undo
        '(lambda ()
           (setq n 0)
           (foreach e ents
             (if (/= base-tipo (cl:valor e "TIPO"))
               (princ (strcat "\nAviso: objeto não classificado como " (cl:tipo-nome base-tipo) " (criado assim mesmo).")))
             (setq d (vl-remove-if-not '(lambda (x) (member (car x) '("CLIENTE" "FAZENDA" "TALHAO"))) (cl:le e)))
             (foreach c (cl:offset-dentro e *CL-OFFSET* fora)
               (cl:grava (vlax-vla-object->ename c)
                         (append d (list (cons "TIPO" tipo) (cons "OFFSET" *CL-OFFSET*))) nil)
               (setq n (1+ n))))
           (princ (strcat "\n" (itoa n) " cabeceira(s) criada(s) (" (cl:tipo-nome tipo) ", largura "
                          (rtos *CL-OFFSET* 2 2) " m).")))))
    (progn
      (setq larg (getdist (strcat "\nLargura (OFFSET) das cabeceiras existentes (m) <" (rtos *CL-OFFSET* 2 2) ">: ")))
      (if larg (setq *CL-OFFSET* larg))
      (cl:grava-env)
      (cl:classifica-tipo tipo "\nSelecione as cabeceiras existentes: " *CL-F-FECHADAS* (list (cons "OFFSET" *CL-OFFSET*)))))
  (princ)
)
(defun c:CLA_CABEXT ()
  (if (cl:requer)
    (cl:cabeceira "CABECEIRA_EXTERNA" "LIMITE_EXTERNO"
                  "\nSelecione os limites externos para CRIAR a cabeceira ou [Enter] para CLASSIFICAR: " nil))
  (princ)
)
(defun c:CLA_CABINT ()
  (if (cl:requer)
    (cl:cabeceira "CABECEIRA_INTERNA" "LIMITE_INTERNO"
                  "\nSelecione os limites internos para CRIAR a cabeceira ou [Enter] para CLASSIFICAR: " T))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Grupos / glebas (CGLE)
;;; --------------------------------------------------------------------------
(defun c:CLA_GLEBA (/ r e ents base nome lay grp cft)
  (if (cl:requer)
    (progn
      (setq r (cl:dcl "cla_gleba"
                      '(lambda () (set_tile "nome" *CL-GRUPO*) (set_tile "aplicar" "app0") (set_tile "filtro" "cft0"))
                      '(lambda ()
                         (action_tile "chkLayer" "(mode_tile \"nome\" (atoi $value))")
                         (action_tile "accept" "(setq *gl* (list (get_tile \"nome\") (get_tile \"chkLayer\") (get_tile \"aplicar\") (get_tile \"filtro\"))) (done_dialog 1)"))))
      (if (and (= r 1) (setq ents (cl:sel "\nSelecione a(s) linha(s): " *CL-F-CURVAS*)))
        (progn
          (setq *CL-GRUPO* (car *gl*)) (cl:grava-env)
          (setq base (car ents) lay (cdr (assoc 8 (entget base))) grp (cl:valor base "NOME")
                cft (vl-remove-if-not '(lambda (x) (member (car x) '("CLIENTE" "FAZENDA" "TALHAO"))) (cl:le base)))
          ;; aplicar em: só as selecionadas / todo o grupo / todo o layer
          (cond
            ((= (nth 2 *gl*) "app1")
             (setq ents (append ents (vl-remove-if-not '(lambda (x) (and grp (= grp (cl:valor x "NOME"))))
                                                       (cl:lista-ss (ssget "_X" (append '((410 . "Model")) *CL-F-CURVAS*))))))))
            ((= (nth 2 *gl*) "app2")
             (setq ents (cl:lista-ss (ssget "_X" (append (list (cons 8 lay) '(410 . "Model")) *CL-F-CURVAS*))))))
          ;; filtro de CFT: só os do mesmo CFT da primeira linha
          (if (= (nth 3 *gl*) "cft1")
            (setq ents (vl-remove-if-not
                         '(lambda (x) (equal cft (vl-remove-if-not '(lambda (y) (member (car y) '("CLIENTE" "FAZENDA" "TALHAO"))) (cl:le x))))
                         ents)))
          (cl:undo
            '(lambda ()
               (foreach x ents
                 (cl:grava x (list (cons "NOME" (if (= "1" (cadr *gl*)) (cdr (assoc 8 (entget x))) (car *gl*)))) T))
               (princ (strcat "\nGrupo/gleba aplicado em " (itoa (length ents)) " linha(s).")))))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; CFT automático (CFL)
;;; --------------------------------------------------------------------------
;;; valores-fonte de um objeto conforme o método -> (("campo" . valor) ...)
(defun cl:fontes (e metodo textos / ed r pol v a)
  (setq ed (entget e))
  (cond
    ((= metodo "layer") (list (cons "LAYER" (cdr (assoc 8 ed)))))
    ((= metodo "object_data")
     (foreach t1 (vl-remove *CL-TAB* (if (= 'EXRXSUBR (type ade_odgettables)) (ade_odgettables e)))
       (foreach c (cdr (assoc "columns" (ade_odtabledefn t1)))
         (setq v (vl-catch-all-apply 'ade_odgetfield (list e t1 (cdr (assoc "colname" c)) 0)))
         (if (not (vl-catch-all-error-p v)) (setq r (cons (cons (strcat t1 "." (cdr (assoc "colname" c))) (ic:texto v)) r)))))
     (reverse r))
    ((= metodo "texto")
     (if (and (cl:fechada-p e) (setq pol (cl:pts e)))
       (foreach t1 textos (if (cl:dentro (car t1) pol) (setq r (list (cons "TEXTO" (cadr t1))))))))
    ((= metodo "atributo")
     (if (= "INSERT" (cdr (assoc 0 ed)))
       (foreach a (vl-catch-all-apply 'vlax-invoke (list (vlax-ename->vla-object e) 'GetAttributes))
         (setq r (cons (cons (vla-get-TagString a) (vla-get-TextString a)) r)))
       (if (and (cl:fechada-p e) (setq pol (cl:pts e)))
         (foreach t1 textos (if (and (caddr t1) (cl:dentro (car t1) pol)) (setq r (caddr t1)))))))
    )
  r
)
;;; texto do campo, com n caracteres a partir de ini (n = 0 -> até o fim)
(defun cl:parte (s ini n) (if (and s (<= ini (strlen s))) (vl-string-trim " " (if (> n 0) (substr s ini n) (substr s ini))) ""))

(defun c:CLA_AUTO (/ ents textos campos r n d s fon)
  (if (cl:requer)
    (if (setq ents (cl:sel "\nSelecione os objetos (talhões, linhas, textos e blocos) a classificar: " nil))
      (progn
        ;; textos e blocos com atributos dentro dos polígonos
        (foreach e ents
          (cond ((member (cdr (assoc 0 (entget e))) '("TEXT" "MTEXT"))
                 (setq textos (cons (list (cdr (assoc 10 (entget e))) (vl-string-trim " " (cdr (assoc 1 (entget e))))) textos)))
                ((= "INSERT" (cdr (assoc 0 (entget e))))
                 (setq textos (cons (list (cdr (assoc 10 (entget e))) "" (cl:fontes e "atributo" nil)) textos)))))
        (setq *cl-ents* ents *cl-textos* textos)
        (setq r (cl:dcl "cla_auto" 'cl:ini-auto 'cl:acoes-auto))
        (if (= r 1)
          (cl:undo
            '(lambda ()
               (setq n 0)
               (foreach e ents
                 (if (not (member (cdr (assoc 0 (entget e))) '("TEXT" "MTEXT")))
                   (progn
                     (setq fon (cl:fontes e *CL-AUTOMET* textos) d nil)
                     (if *CL-AUTOUNI*
                       (progn
                         (setq s (cdr (assoc *cl-uni* fon)))
                         (if s (setq d (list (cons "CLIENTE" (cl:parte s 1 *CL-NC*))
                                             (cons "FAZENDA" (cl:parte s (1+ *CL-NC*) *CL-NF*))
                                             (cons "TALHAO" (cl:parte s (+ 1 *CL-NC* *CL-NF*) *CL-NT*))))))
                       (setq d (list (cons "CLIENTE" (cl:parte (cdr (assoc *cl-cc* fon)) 1 *CL-NC*))
                                     (cons "FAZENDA" (cl:parte (cdr (assoc *cl-cf* fon)) 1 *CL-NF*))
                                     (cons "TALHAO" (cl:parte (cdr (assoc *cl-ct* fon)) 1 *CL-NT*)))))
                     (if (and *CL-NOMES* (assoc *cl-cg* fon))
                       (setq d (append d (list (cons "NOME" (cl:parte (cdr (assoc *cl-cg* fon)) 1 *CL-NG*))))))
                     (setq d (vl-remove-if '(lambda (x) (= "" (cdr x))) d))
                     (if d
                       (progn (cl:grava e d T) (setq n (1+ n))
                              (cl:cad-add (cdr (assoc "CLIENTE" d)) (cdr (assoc "FAZENDA" d)) (cdr (assoc "TALHAO" d))))))))
               (princ (strcat "\nCFT automático em " (itoa n) " objeto(s)."))
               (if *CL-CLASSINT* (princ (strcat " " (itoa (cl:internos)) " objeto(s) interno(s) herdaram o CFT dos limites.")))))))))
  (princ)
)
;;; campos disponíveis para o método escolhido
(defun cl:campos-auto (met / r)
  (foreach e *cl-ents*
    (foreach f (cl:fontes e met *cl-textos*) (if (not (member (car f) r)) (setq r (cons (car f) r)))))
  (reverse r)
)
(defun cl:ini-auto ()
  (set_tile "metodo" *CL-AUTOMET*)
  (set_tile "usar_unicod" (if *CL-AUTOUNI* "1" "0"))
  (foreach x (list (list "ch_cliente" *CL-NC*) (list "ch_fazenda" *CL-NF*) (list "ch_talhao" *CL-NT*) (list "ch_gleba" *CL-NG*))
    (set_tile (car x) (itoa (cadr x))))
  (set_tile "classint" (if *CL-CLASSINT* "1" "0"))
  (set_tile "mapear" (if *CL-NOMES* "1" "0"))
  (cl:atu-auto)
)
(defun cl:atu-auto (/ c u)
  (setq *cl-campos* (cl:campos-auto (get_tile "metodo")) c *cl-campos*)
  (foreach k '("cp_unico" "cp_cliente" "cp_fazenda" "cp_talhao" "cp_gleba") (cl:popula k c nil))
  (setq u (= "1" (get_tile "usar_unicod")))
  (mode_tile "cp_unico" (if u 0 1))
  (foreach k '("cp_cliente" "cp_fazenda" "cp_talhao") (mode_tile k (if u 1 0)))
  (mode_tile "cp_gleba" (if (= "1" (get_tile "mapear")) 0 1))
  (set_tile "exemplo" (if c (strcat "Campos: " (ic:corta (cl:junta c ", ") 70)) "Nenhum campo para este método nos objetos selecionados."))
)
(defun cl:acoes-auto ()
  (action_tile "metodo" "(cl:atu-auto)")
  (action_tile "usar_unicod" "(cl:atu-auto)")
  (action_tile "mapear" "(cl:atu-auto)")
  (action_tile "accept" "(if (cl:ok-auto) (done_dialog 1))")
)
(defun cl:ok-auto (/ nth-c)
  (defun nth-c (k) (if *cl-campos* (nth (atoi (get_tile k)) *cl-campos*)))
  (setq *CL-AUTOMET* (get_tile "metodo") *CL-AUTOUNI* (= "1" (get_tile "usar_unicod"))
        *CL-NC* (atoi (get_tile "ch_cliente")) *CL-NF* (atoi (get_tile "ch_fazenda"))
        *CL-NT* (atoi (get_tile "ch_talhao")) *CL-NG* (atoi (get_tile "ch_gleba"))
        *CL-CLASSINT* (= "1" (get_tile "classint")) *CL-NOMES* (= "1" (get_tile "mapear"))
        *cl-uni* (nth-c "cp_unico") *cl-cc* (nth-c "cp_cliente") *cl-cf* (nth-c "cp_fazenda")
        *cl-ct* (nth-c "cp_talhao") *cl-cg* (nth-c "cp_gleba"))
  (cond
    ((null *cl-campos*) (set_tile "error" "Nenhum campo disponível para este método.") nil)
    ((and *CL-AUTOUNI* (= 0 *CL-NC*) (= 0 *CL-NF*))
     (set_tile "error" "Com código único, informe quantos caracteres são do CLIENTE e da FAZENDA.") nil)
    (T (cl:grava-env) T))
)

;;; --------------------------------------------------------------------------
;;; Visualização (VV), legenda, filtro, gerenciador (KLA)
;;; --------------------------------------------------------------------------
(defun cl:cor-hash (s / n) (setq n 0) (foreach c (vl-string->list s) (setq n (rem (+ (* n 31) c) 251))) (+ 1 (rem n 250)))
(defun cl:cor (e modo / d)
  (setq d (cl:le e))
  (cond
    ((null d) nil)
    ((= modo "Tipo") (caddr (assoc (cdr (assoc "TIPO" d)) *CL-TIPOS*)))
    ((= modo "Grupo") (if (assoc "NOME" d) (cl:cor-hash (cdr (assoc "NOME" d)))))
    (T (if (assoc "TALHAO" d) (cl:cor-hash (strcat (cdr (assoc "CLIENTE" d)) "/" (cdr (assoc "FAZENDA" d)) "/" (cdr (assoc "TALHAO" d)))))))
)
(defun cl:vv-ligado (/ ss) (ssget "_X" '((-3 ("LISPS_VV")))))
(defun cl:vv-desliga (/ ss n ed xd c)
  (setq n 0)
  (foreach e (cl:lista-ss (cl:vv-ligado))
    (setq ed (entget e '("LISPS_VV")) xd (cdr (assoc "LISPS_VV" (cdr (assoc -3 ed)))) c (cdr (assoc 1070 xd)))
    (setq ed (vl-remove-if '(lambda (g) (member (car g) '(62 -3))) ed))
    (entmod (append ed (if (and c (/= c 256)) (list (cons 62 c)) '((62 . 256))) (list '(-3 ("LISPS_VV")))))
    (setq n (1+ n)))
  n
)
(defun cl:vv-liga (modo / n c ed)
  (if (not (tblsearch "APPID" "LISPS_VV")) (regapp "LISPS_VV"))
  (setq n 0)
  (foreach e (cl:lista-ss (ssget "_X" '((410 . "Model"))))
    (if (setq c (cl:cor e modo))
      (progn
        (setq ed (entget e))
        (entmod (append (vl-remove-if '(lambda (g) (member (car g) '(62 -3))) ed)
                        (list (cons 62 c) (list -3 (list "LISPS_VV" (cons 1070 (cond ((cdr (assoc 62 ed))) (256))))))))
        (setq n (1+ n)))))
  n
)
(defun c:CLA_VER (/ modo)
  (if (cl:requer)
    (if (cl:vv-ligado)
      (cl:undo '(lambda () (princ (strcat "\nModo de visualização DESLIGADO: cores originais restauradas em " (itoa (cl:vv-desliga)) " objeto(s)."))))
      (progn
        (initget "Tipo Cft Grupo")
        (setq modo (cond ((getkword "\nColorir por [Tipo/Cft/Grupo] <Tipo>: ")) ("Tipo")))
        (cl:undo '(lambda () (princ (strcat "\n*** VOCÊ ESTÁ NO MODO DE CLASSIFICAÇÃO *** " (itoa (cl:vv-liga modo))
                                            " objeto(s) coloridos por " modo ". Rode CLA_VER de novo para desligar.")))))))
  (princ)
)

(defun cl:legenda (/ p ss cont d k txt)
  (if (setq p (getpoint "\nPonto de inserção da legenda: "))
    (progn
      (foreach e (cl:lista-ss (ssget "_X" '((410 . "Model"))))
        (if (setq d (cl:le e))
          (progn
            (setq k (strcat (cond ((cdr (assoc "CLIENTE" d))) ("-")) " / " (cond ((cdr (assoc "FAZENDA" d))) ("-")) " / "
                            (cond ((cdr (assoc "TALHAO" d))) ("-")))
                  k (list k (cl:tipo-nome (cond ((cdr (assoc "TIPO" d))) ("(sem tipo)")))))
            (setq cont (if (assoc k cont) (subst (cons k (1+ (cdr (assoc k cont)))) (assoc k cont) cont) (cons (cons k 1) cont))))))
      (setq cont (vl-sort cont '(lambda (a b) (< (strcat (car (car a)) (cadr (car a))) (strcat (car (car b)) (cadr (car b)))))))
      (setq txt (strcat "{\\bCLIENTE / FAZENDA / TALHÃO - tipo: objetos}\\P"
                        (cl:junta (mapcar '(lambda (c) (strcat (car (car c)) " - " (cadr (car c)) ": " (itoa (cdr c)))) cont) "\\P")))
      (entmake (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 (getvar "CLAYER")) '(100 . "AcDbMText")
                     (cons 10 p) (cons 40 (* 2.5 (max 1.0 (getvar "TEXTSIZE")))) '(71 . 1) (cons 1 txt)))
      (princ (strcat "\nLegenda com " (itoa (length cont)) " linha(s)."))))
)
(defun c:CLA_LEGENDA () (if (cl:requer) (cl:legenda)) (princ))

(defun c:CLA_FILTRO (/ r ents)
  (if (cl:requer)
    (progn
      (cl:cad-do-desenho)
      (setq r (cl:dcl "cla_filtro" '(lambda () (cl:atu-cft) (set_tile "isolar" "1"))
                      '(lambda () (cl:acoes-cft)
                         (action_tile "accept" "(setq *cl-isolar* (= \"1\" (get_tile \"isolar\")) *cl-niv* (get_tile \"nivel\")) (done_dialog 1)"))))
      (if (= r 1)
        (progn
          (setq ents (vl-remove-if-not
                       '(lambda (e / d)
                          (setq d (cl:le e))
                          (and (= *CL-CLI* (cdr (assoc "CLIENTE" d)))
                               (or (= *cl-niv* "n_cli") (= *CL-FAZ* (cdr (assoc "FAZENDA" d))))
                               (or (member *cl-niv* '("n_cli" "n_faz")) (= *CL-TAL* (cdr (assoc "TALHAO" d))))))
                       (cl:lista-ss (ssget "_X" '((410 . "Model"))))))
          (princ (strcat "\n" (itoa (length ents)) " objeto(s) no filtro."))
          (if ents
            (progn
              (setq r (ssadd))
              (foreach e ents (ssadd e r))
              (if (and *cl-isolar* (getcname "ISOLATEOBJECTS"))
                (command "_.ISOLATEOBJECTS" r "")
                (sssetfirst nil r))
              (if *cl-isolar* (princ " Para mostrar tudo de novo: UNISOLATEOBJECTS."))))))))
  (princ)
)

;;; gerenciador (KLA / CFTMANAGER): tipo, CFT e grupo num só lugar
(defun c:CLA_GERENCIAR (/ r ents tipo)
  (if (cl:requer)
    (progn
      (cl:cad-do-desenho)
      (setq r 9)
      (while (/= r 0)
        (setq r (cl:dcl "cla_gerenciar"
                        '(lambda () (cl:atu-cft) (cl:popula "tipo" (mapcar 'cadr *CL-TIPOS*) nil)
                           (set_tile "grupo" *CL-GRUPO*) (set_tile "classint" (if *CL-CLASSINT* "1" "0")))
                        '(lambda () (cl:acoes-cft)
                           (action_tile "aplicar_tipo" "(setq *cl-t* (atoi (get_tile \"tipo\"))) (done_dialog 3)")
                           (action_tile "aplicar_cft" "(if (= *CL-TAL* \"\") (set_tile \"error\" \"Escolha o talhão.\") (done_dialog 4))")
                           (action_tile "aplicar_grupo" "(setq *CL-GRUPO* (get_tile \"grupo\")) (done_dialog 5)")
                           (action_tile "remover" "(done_dialog 6)")
                           (action_tile "tema_tipo" "(done_dialog 7)")
                           (action_tile "tema_cft" "(done_dialog 8)")
                           (action_tile "tema_grupo" "(done_dialog 10)")
                           (action_tile "classint" "(setq *CL-CLASSINT* (= $value \"1\"))")
                           (action_tile "accept" "(done_dialog 0)"))))
        (cl:grava-env)
        (cond
          ((= r 3)
           (setq tipo (car (nth *cl-t* *CL-TIPOS*)))
           (cl:classifica-tipo tipo (strcat "\nSelecione os objetos (" (cl:tipo-nome tipo) "): ") nil nil))
          ((= r 4)
           (if (setq ents (cl:sel "\nSelecione os objetos para o CFT: " nil))
             (cl:undo '(lambda () (princ (strcat "\nCFT aplicado em " (itoa (cl:aplica ents (cl:cft-atual) T)) " objeto(s).")))))
           (if *CL-CLASSINT* (princ (strcat " " (itoa (cl:internos)) " interno(s) pelos limites."))))
          ((= r 5)
           (if (setq ents (cl:sel "\nSelecione os objetos do grupo: " nil))
             (cl:undo '(lambda () (princ (strcat "\nGrupo em " (itoa (cl:aplica ents (list (cons "NOME" *CL-GRUPO*)) T)) " objeto(s)."))))))
          ((= r 6)
           (if (setq ents (cl:sel "\nSelecione os objetos para remover a classificação: " nil))
             (cl:undo '(lambda () (foreach e ents (cl:remove e nil)) (princ (strcat "\nRemovida de " (itoa (length ents)) " objeto(s)."))))))
          ((member r '(7 8 10))
           (cl:undo '(lambda () (cl:vv-desliga)
                       (princ (strcat "\nMapa temático: " (itoa (cl:vv-liga (cdr (assoc r '((7 . "Tipo") (8 . "Cft") (10 . "Grupo"))))))
                                      " objeto(s). CLA_VER desliga.")))))))))
  (princ)
)

(princ)
