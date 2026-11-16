;;; ==========================================================================
;;; CriaLinhas.lsp - Linhas de Sulcação, Plantio e Colheita
;;; --------------------------------------------------------------------------
;;; Recria o fluxo do comando GOFUR ("[NOVO] Criar Linhas") do AgroCAD
;;; (aba AgroCAD > painel Sistematização):
;;;
;;;   Linhas a serem criadas : Somente Guias / Guias + Plantio / Somente Plantio
;;;   Linhas Guias           : espaçamento + Modo Manual (clica a posição final)
;;;   Linhas de Plantio      : quantidade e espaçamento em torno de cada guia
;;;   Cabeceira              : N passadas Para Dentro / Para Fora do talhão
;;;   Linhas Internas        : Criar  -> talhões + curva de referência + lado
;;;                            Selecionar -> cria plantio a partir de guias
;;;   Predefinições          : Carregar / Salvar / Tornar Padrão
;;;
;;; Layers padrão iguais aos do AgEngine: GUIDELINES (amarelo) e
;;; CROPLINES (verde). Talhões = polilinhas fechadas (qualquer layer).
;;;
;;; Comando: CRIALINHAS
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Parâmetros (valores iniciais; o "Tornar Padrão" grava em config\)
;;; --------------------------------------------------------------------------
(setq *CL-VARS* '(*CL-MODO* *CL-ESPG* *CL-MANUAL* *CL-QTD* *CL-ESPP* *CL-PASS*
                  *CL-RECUAR* *CL-AMBOS* *CL-LAYG* *CL-CORG* *CL-LAYP* *CL-CORP*))

(defun cl:defaults ()
  (setq *CL-MODO*   "GC"          ; "G" guias, "GC" guias+plantio, "C" plantio
        *CL-ESPG*   3.0           ; espaçamento entre guias (m)
        *CL-MANUAL* nil           ; modo manual: usuário clica a posição final
        *CL-QTD*    2             ; linhas de plantio por guia
        *CL-ESPP*   1.5           ; espaçamento entre linhas de plantio (m)
        *CL-PASS*   4             ; passadas de cabeceira
        *CL-RECUAR* T             ; 1a passada a meio espaçamento da borda
        *CL-AMBOS*  T             ; linhas internas dos dois lados da referência
        *CL-LAYG*   "GUIDELINES"
        *CL-CORG*   2
        *CL-LAYP*   "CROPLINES"
        *CL-CORP*   3)
)
(if (not *CL-MODO*) (cl:defaults))

;;; --------------------------------------------------------------------------
;;; Arquivos (DCL e predefinições)
;;; --------------------------------------------------------------------------
(defun cl:pasta-lisps ()
  (cond (*LISPS-DIR*)
        ((findfile "CriaLinhas.dcl") (vl-filename-directory (findfile "CriaLinhas.dcl")))
        (T nil))
)

(defun cl:pasta-config (/ p)
  (setq p (if (cl:pasta-lisps)
            (strcat (cl:pasta-lisps) "\\config")
            (strcat (getvar "TEMPPREFIX") "lisps_config")))
  (if (not (vl-file-directory-p p)) (vl-mkdir p))
  p
)

(defun cl:arq-padrao () (strcat (cl:pasta-config) "\\CRIALINHAS_PADRAO.lin"))

(defun cl:salvar-params (arq / f)
  (if (setq f (open arq "w"))
    (progn
      (write-line (vl-prin1-to-string (mapcar 'eval *CL-VARS*)) f)
      (close f)
      T
    )
  )
)

(defun cl:carregar-params (arq / f l v)
  (if (and arq (findfile arq) (setq f (open arq "r")))
    (progn
      (setq l (read-line f))
      (close f)
      (setq v (vl-catch-all-apply 'read (list l)))
      (if (and (listp v) (= (length v) (length *CL-VARS*)))
        (progn (mapcar 'set *CL-VARS* v) T)
      )
    )
  )
)

;;; --------------------------------------------------------------------------
;;; Utilitários gerais
;;; --------------------------------------------------------------------------
(defun cl:2d (p) (list (car p) (cadr p)))

(defun cl:tan (x) (/ (sin x) (cos x)))

;;; bulge de um trecho parcial de arco (fração do ângulo total)
(defun cl:bpar (b frac) (cl:tan (* (atan b) frac)))

(defun cl:num (s / v)
  (if s (setq v (distof (vl-string-translate "," "." s) 2)))
  v
)

(defun cl:layer (nome cor / lay)
  (if (not (tblsearch "LAYER" nome))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 nome) '(70 . 0)
                   (cons 62 cor) '(6 . "Continuous")))
  )
  (setq lay (vla-item (vla-get-Layers (vla-get-ActiveDocument (vlax-get-acad-object))) nome))
  (vla-put-LayerOn lay :vlax-true)
  (vl-catch-all-apply 'vla-put-Freeze (list lay :vlax-false))
  (vla-put-Lock lay :vlax-false)
)

;;; dados de uma LWPOLYLINE: (vertices bulges fechada?)
(defun cl:lw-data (e / ed v b)
  (setq ed (entget e))
  (foreach g ed
    (cond ((= (car g) 10) (setq v (cons (cl:2d (cdr g)) v)))
          ((= (car g) 42) (setq b (cons (cdr g) b))))
  )
  (list (reverse v) (reverse b) (= 1 (logand 1 (cdr (assoc 70 ed)))))
)

;;; cria LWPOLYLINE e devolve o objeto VLA
(defun cl:mk-lw (pts buls fechada lay)
  (entmake
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
            '(100 . "AcDbPolyline") (cons 90 (length pts))
            (cons 70 (if fechada 1 0)) '(38 . 0.0))
      (apply 'append
             (mapcar '(lambda (p b) (list (cons 10 p) (cons 42 b))) pts buls))
    )
  )
  (vlax-ename->vla-object (entlast))
)

(defun cl:offset (o d / r)
  (setq r (vl-catch-all-apply 'vlax-invoke (list o 'Offset d)))
  (if (vl-catch-all-error-p r) nil r)
)

(defun cl:poe-layer (lst lay)
  (foreach o lst (vl-catch-all-apply 'vla-put-Layer (list o lay)))
  lst
)

;;; --------------------------------------------------------------------------
;;; Geometria
;;; --------------------------------------------------------------------------

;;; pontos de amostragem do contorno (arcos discretizados) para "ponto dentro"
(defun cl:amostra (o / d v b n i j res)
  (setq d (cl:lw-data (vlax-vla-object->ename o))
        v (car d) b (cadr d) n (length v) i 0)
  (repeat n
    (setq res (cons (nth i v) res))
    (if (and (/= 0.0 (nth i b)) (or (caddr d) (< i (1- n))))
      (progn
        (setq j 1)
        (repeat 7
          (setq res (cons (cl:2d (vlax-curve-getPointAtParam o (+ i (/ j 8.0)))) res)
                j (1+ j)))
      )
    )
    (setq i (1+ i))
  )
  (reverse res)
)

;;; ponto dentro do polígono (ray casting)
(defun cl:dentro (p poly / x y in pa pb)
  (setq x (car p) y (cadr p) pb (last poly))
  (foreach pa poly
    (if (and (/= (> (cadr pa) y) (> (cadr pb) y))
             (< x (+ (car pa) (/ (* (- (car pb) (car pa)) (- y (cadr pa)))
                                 (- (cadr pb) (cadr pa))))))
      (setq in (not in))
    )
    (setq pb pa)
  )
  in
)

;;; trecho [a,b] (parâmetros) de uma LWPOLYLINE, preservando arcos
(defun cl:sub-lw (o a b lay / d v bl n ia fa ib fb pts buls k)
  (setq d (cl:lw-data (vlax-vla-object->ename o))
        v (car d) bl (cadr d) n (length v)
        ia (fix a) fa (- a ia) ib (fix b) fb (- b ib))
  (if (> fa (- 1.0 1e-9)) (setq ia (1+ ia) fa 0.0))
  (if (and (< fb 1e-9) (> ib ia)) (setq ib (1- ib) fb 1.0))
  (setq pts (list (cl:2d (vlax-curve-getPointAtParam o a))))
  (if (= ia ib)
    (setq buls (list (cl:bpar (nth (rem ia n) bl) (- fb fa))))
    (progn
      (setq buls (list (cl:bpar (nth (rem ia n) bl) (- 1.0 fa)))
            k (1+ ia))
      (while (< k ib)
        (setq pts  (cons (nth (rem k n) v) pts)
              buls (cons (nth (rem k n) bl) buls)
              k    (1+ k)))
      (setq pts  (cons (nth (rem ib n) v) pts)
            buls (cons (cl:bpar (nth (rem ib n) bl) fb) buls))
    )
  )
  (setq pts  (cons (cl:2d (vlax-curve-getPointAtParam o b)) pts)
        buls (cons 0.0 buls))
  (cl:mk-lw (reverse pts) (reverse buls) nil lay)
)

;;; recorta a curva o pelo talhão (bnd/poly). Apaga o; devolve os pedaços internos.
(defun cl:clip (o bnd poly lay / ints pt pr prms a b res)
  (setq ints (vl-catch-all-apply 'vlax-invoke (list o 'IntersectWith bnd acExtendNone)))
  (if (vl-catch-all-error-p ints) (setq ints nil))
  (while ints
    (setq pt (list (car ints) (cadr ints) (caddr ints)) ints (cdddr ints)
          pr (vlax-curve-getParamAtPoint o (vlax-curve-getClosestPointTo o pt)))
    (if pr (setq prms (cons pr prms)))
  )
  (cond
    ;; curva fechada sem cruzar o contorno: fica inteira ou sai inteira
    ((and (null prms) (vlax-curve-isClosed o))
     (if (cl:dentro (cl:2d (vlax-curve-getStartPoint o)) poly)
       (progn (vla-put-Layer o lay) (list o))
       (progn (vla-delete o) nil))
    )
    (T
     (setq prms (append (list (vlax-curve-getStartParam o))
                        (vl-sort prms '<)
                        (list (vlax-curve-getEndParam o))))
     (while (cdr prms)
       (setq a (car prms) b (cadr prms) prms (cdr prms))
       (if (and (> (- b a) 1e-6)
                (cl:dentro (cl:2d (vlax-curve-getPointAtParam o (/ (+ a b) 2.0))) poly))
         (setq res (cons (cl:sub-lw o a b lay) res))
       )
     )
     (vla-delete o)
     res
    )
  )
)

;;; curva de referência convertida em LWPOLYLINE e prolongada pelas tangentes
(defun cl:ref-ext (e ext / o typ d pts buls t0 tn)
  (setq o (vlax-ename->vla-object e) typ (cdr (assoc 0 (entget e))))
  (cond
    ((= typ "LWPOLYLINE")
     (setq d (cl:lw-data e) pts (car d) buls (cadr d))
     (if (caddr d) (setq ext nil))   ; referência fechada: não prolonga
    )
    ((= typ "LINE")
     (setq pts  (list (cl:2d (vlax-curve-getStartPoint o)) (cl:2d (vlax-curve-getEndPoint o)))
           buls (list 0.0 0.0))
    )
    ((= typ "ARC")
     (setq pts  (list (cl:2d (vlax-curve-getStartPoint o)) (cl:2d (vlax-curve-getEndPoint o)))
           buls (list (cl:tan (/ (vla-get-TotalAngle o) 4.0)) 0.0))
    )
  )
  (if ext
    (progn
      (setq t0 (vlax-curve-getFirstDeriv o (vlax-curve-getStartParam o))
            tn (vlax-curve-getFirstDeriv o (vlax-curve-getEndParam o)))
      (setq pts  (append (list (polar (car pts) (+ (angle '(0 0) (cl:2d t0)) pi) ext))
                         pts
                         (list (polar (last pts) (angle '(0 0) (cl:2d tn)) ext)))
            buls (append '(0.0) (reverse (cdr (reverse buls))) '(0.0 0.0)))
      (cl:mk-lw pts buls nil "0")
    )
    (cl:mk-lw pts buls (= typ "LWPOLYLINE") "0")
  )
)

;;; +1 ou -1: sinal do offset que vai para o lado do ponto pt
(defun cl:sinal (o pt / r s)
  (setq s 1.0)
  (if (setq r (cl:offset o 1.0))
    (progn
      (if (> (distance pt (vlax-curve-getClosestPointTo (car r) pt))
             (distance pt (vlax-curve-getClosestPointTo o pt)))
        (setq s -1.0))
      (mapcar 'vla-delete r)
    )
  )
  s
)

;;; --------------------------------------------------------------------------
;;; Linhas de plantio em torno de cada guia
;;; --------------------------------------------------------------------------
(defun cl:plantio (guias bnd poly / res o i p objs)
  (cl:layer *CL-LAYP* *CL-CORP*)
  (foreach o guias
    (setq i 0)
    (repeat *CL-QTD*
      (setq p (* (- i (/ (- *CL-QTD* 1) 2.0)) *CL-ESPP*))
      (setq objs (if (equal p 0.0 1e-9) (list (vla-Copy o)) (cl:offset o p)))
      (foreach x objs
        (vla-put-Layer x *CL-LAYP*)
        (if bnd
          (setq res (append (cl:clip x bnd poly *CL-LAYP*) res))
          (setq res (cons x res)))
      )
      (setq i (1+ i))
    )
  )
  res
)

;;; --------------------------------------------------------------------------
;;; Ações
;;; --------------------------------------------------------------------------

;;; seleção de talhões (polilinhas fechadas)
(defun cl:sel-talhoes (/ ss i res)
  (princ "\nSelecione os talhões: ")
  (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq res (cons (vlax-ename->vla-object (ssname ss i)) res) i (1+ i)))
    )
  )
  res
)

;;; CABECEIRA: offsets do contorno do talhão
(defun cl:cabeceira (dentro / talhoes bnd a0 r sinal k d objs guias tot)
  (if (setq talhoes (cl:sel-talhoes))
    (progn
      (cl:layer *CL-LAYG* *CL-CORG*)
      (setq tot 0)
      (foreach bnd talhoes
        (setq a0 (vla-get-Area bnd) sinal 1.0 guias nil)
        (if (setq r (cl:offset bnd 1.0))
          (progn
            (if (> (vla-get-Area (car r)) a0) (setq sinal -1.0))
            (mapcar 'vla-delete r)))
        (if (not dentro) (setq sinal (- sinal)))
        (setq k 1)
        (repeat *CL-PASS*
          (setq d (* *CL-ESPG* (if *CL-RECUAR* (- k 0.5) k)))
          (setq objs (cl:offset bnd (* sinal d)))
          (if (null objs)
            (princ (strcat "\nPassada " (itoa k) " não coube no talhão; parando."))
          )
          (setq guias (append (cl:poe-layer objs *CL-LAYG*) guias) k (1+ k))
        )
        (if (member *CL-MODO* '("GC" "C"))
          (setq tot (+ tot (length (cl:plantio guias nil nil)))))
        (if (= *CL-MODO* "C")
          (mapcar 'vla-delete guias)
          (setq tot (+ tot (length guias))))
      )
      (princ (strcat "\n" (itoa tot) " linha(s) de cabeceira criada(s)."))
    )
  )
)

;;; LINHAS INTERNAS: offsets da curva de referência recortados pelo talhão
(defun cl:internas (/ talhoes ent ref tipo ptlado lados limite bnd poly xs ys
                      ext refo maxd kmax k s guias novas tot)
  (if (setq talhoes (cl:sel-talhoes))
    (progn
      (while (and (setq ent (entsel "\nSelecione a curva: "))
                  (not (member (setq tipo (cdr (assoc 0 (entget (car ent)))))
                               '("LINE" "LWPOLYLINE" "ARC"))))
        (princ "\nA curva precisa ser LINHA, POLILINHA ou ARCO.")
      )
      (if ent
        (progn
          (setq ref (car ent))
          ;; lado / posição final
          (cond
            (*CL-MANUAL*
             (setq ptlado (getpoint "\nIndique a posição final das linhas: "))
             (if ptlado
               (setq limite (distance ptlado
                                      (vlax-curve-getClosestPointTo
                                        (vlax-ename->vla-object ref) ptlado T))))
            )
            (*CL-AMBOS* (setq lados '(1.0 -1.0)))
            (T
             (initget "Ambos")
             (setq ptlado (getpoint "\nIndique o lado do offset [Ambos]: "))
             (if (= ptlado "Ambos") (setq lados '(1.0 -1.0) ptlado nil))
            )
          )
          (if (or lados ptlado)
            (progn
              (cl:layer *CL-LAYG* *CL-CORG*)
              (setq tot 0)
              (foreach bnd talhoes
                (setq poly (cl:amostra bnd)
                      xs   (mapcar 'car poly)
                      ys   (mapcar 'cadr poly)
                      ext  (* 1.5 (distance (list (apply 'min xs) (apply 'min ys))
                                            (list (apply 'max xs) (apply 'max ys)))))
                (setq refo (cl:ref-ext ref ext))
                (if ptlado (setq lados (list (cl:sinal refo ptlado))))
                ;; distância máxima até o contorno => quantas linhas cabem
                (setq maxd 0.0)
                (foreach p poly
                  (setq maxd (max maxd (distance p (cl:2d (vlax-curve-getClosestPointTo refo p))))))
                (setq kmax (if limite
                             (fix (+ (/ limite *CL-ESPG*) 1e-6))
                             (1+ (fix (/ maxd *CL-ESPG*)))))
                ;; a própria referência (k = 0) e os offsets
                (setq guias (cl:clip (vla-Copy refo) bnd poly *CL-LAYG*) k 1)
                (repeat kmax
                  (foreach s lados
                    (foreach o (cl:offset refo (* s k *CL-ESPG*))
                      (setq guias (append (cl:clip o bnd poly *CL-LAYG*) guias))))
                  (setq k (1+ k))
                )
                (vla-delete refo)
                (if (member *CL-MODO* '("GC" "C"))
                  (setq tot (+ tot (length (cl:plantio guias bnd poly)))))
                (if (= *CL-MODO* "C")
                  (mapcar 'vla-delete guias)
                  (setq tot (+ tot (length guias))))
              )
              (princ (strcat "\n" (itoa tot) " linha(s) criada(s)."))
            )
          )
        )
      )
    )
  )
)

;;; SELECIONAR: cria linhas de plantio a partir de guias existentes
(defun cl:selecionar (/ ss i guias res)
  (princ "\nSelecione as Linhas: ")
  (if (setq ss (ssget '((0 . "LINE,LWPOLYLINE,ARC,SPLINE,POLYLINE"))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq guias (cons (vlax-ename->vla-object (ssname ss i)) guias) i (1+ i)))
      (setq res (cl:plantio guias nil nil))
      (princ (strcat "\n" (itoa (length res)) " linha(s) de plantio criada(s)."))
    )
  )
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun cl:desenha ( / w h xs x c)
  (setq w (dimx_tile "img") h (dimy_tile "img"))
  (start_image "img")
  (fill_image 0 0 w h -15)
  (foreach x (list (/ w 6) (/ w 2) (- w (/ w 6)))
    (if (member *CL-MODO* '("G" "GC"))
      (progn                                   ; guia tracejada (laranja)
        (setq c 0)
        (while (< c h)
          (vector_image x c x (min h (+ c 6)) 30)
          (setq c (+ c 10)))))
    (if (member *CL-MODO* '("GC" "C"))
      (progn                                   ; plantio (verde)
        (vector_image (- x 5) 0 (- x 5) h 94)
        (vector_image (+ x 5) 0 (+ x 5) h 94)))
  )
  (end_image)
)

(defun cl:habilita ()
  (mode_tile "qtd"  (if (= *CL-MODO* "G") 1 0))
  (mode_tile "espp" (if (or (= *CL-MODO* "G") (< *CL-QTD* 2)) 1 0))
  (cl:desenha)
)

(defun cl:preenche ()
  (set_tile "modo"     *CL-MODO*)
  (set_tile "espg"     (rtos *CL-ESPG* 2 4))
  (set_tile "manual"   (if *CL-MANUAL* "1" "0"))
  (set_tile "qtd"      (itoa *CL-QTD*))
  (set_tile "espp"     (rtos *CL-ESPP* 2 4))
  (set_tile "passadas" (itoa *CL-PASS*))
  (cl:habilita)
)

;;; lê e valida os campos; devolve T se tudo certo
(defun cl:le-tiles (/ espg qtd espp pass)
  (setq espg (cl:num (get_tile "espg"))
        qtd  (atoi (get_tile "qtd"))
        espp (cl:num (get_tile "espp"))
        pass (atoi (get_tile "passadas")))
  (cond
    ((not (and espg (> espg 0))) (set_tile "status" "Espaçamento das guias inválido.") nil)
    ((< qtd 1)                   (set_tile "status" "Quantidade de linhas de plantio inválida.") nil)
    ((not (and espp (> espp 0))) (set_tile "status" "Espaçamento do plantio inválido.") nil)
    ((< pass 1)                  (set_tile "status" "Número de passadas inválido.") nil)
    (T
     (setq *CL-MODO*   (get_tile "modo")
           *CL-ESPG*   espg
           *CL-MANUAL* (= (get_tile "manual") "1")
           *CL-QTD*    qtd
           *CL-ESPP*   espp
           *CL-PASS*   pass)
     (set_tile "status" "")
     T)
  )
)

(defun cl:dlg-avancado (dcl / id r corg corp)
  (if (new_dialog "crialinhas_avancado" dcl)
    (progn
      (set_tile "layg"   *CL-LAYG*)
      (set_tile "corg"   (itoa *CL-CORG*))
      (set_tile "layp"   *CL-LAYP*)
      (set_tile "corp"   (itoa *CL-CORP*))
      (set_tile "recuar" (if *CL-RECUAR* "1" "0"))
      (set_tile "ambos"  (if *CL-AMBOS* "1" "0"))
      (action_tile "accept"
        (strcat
          "(setq corg (atoi (get_tile \"corg\")) corp (atoi (get_tile \"corp\")))"
          "(if (and (snvalid (get_tile \"layg\")) (snvalid (get_tile \"layp\"))"
          "         (< 0 corg 256) (< 0 corp 256))"
          "  (progn (setq *CL-LAYG* (get_tile \"layg\") *CL-CORG* corg"
          "               *CL-LAYP* (get_tile \"layp\") *CL-CORP* corp"
          "               *CL-RECUAR* (= (get_tile \"recuar\") \"1\")"
          "               *CL-AMBOS*  (= (get_tile \"ambos\") \"1\"))"
          "         (done_dialog 1))"
          "  (alert \"Nome de layer ou cor (1-255) inválido.\"))"))
      (start_dialog)
    )
  )
)

(defun c:CRIALINHAS (/ *error* doc dcl arqdcl r loop arq)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*"))
      (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (setq arqdcl (if (cl:pasta-lisps) (strcat (cl:pasta-lisps) "\\CriaLinhas.dcl")))
  (if (not (and arqdcl (findfile arqdcl)))
    (progn (alert "Arquivo CriaLinhas.dcl não encontrado.") (exit)))
  (if (not *CL-INIT*)
    (progn (cl:carregar-params (cl:arq-padrao)) (setq *CL-INIT* T)))

  (setq loop T)
  (while loop
    (setq dcl (load_dialog arqdcl))
    (if (not (new_dialog "crialinhas" dcl))
      (progn (alert "Erro ao abrir o diálogo.") (exit)))
    (cl:preenche)
    (action_tile "modo"     "(setq *CL-MODO* $value) (cl:habilita)")
    (action_tile "qtd"      "(setq *CL-QTD* (max 1 (atoi $value))) (cl:habilita)")
    (action_tile "dentro"   "(if (cl:le-tiles) (done_dialog 2))")
    (action_tile "fora"     "(if (cl:le-tiles) (done_dialog 3))")
    (action_tile "criar"    "(if (cl:le-tiles) (done_dialog 4))")
    (action_tile "selecionar" "(if (cl:le-tiles) (done_dialog 5))")
    (action_tile "avancado" "(if (cl:le-tiles) (done_dialog 6))")
    (action_tile "carregar" "(done_dialog 7)")
    (action_tile "salvar"   "(if (cl:le-tiles) (done_dialog 8))")
    (action_tile "padrao"
      "(if (cl:le-tiles) (set_tile \"status\" (if (cl:salvar-params (cl:arq-padrao)) \"Parâmetros gravados como padrão.\" \"Não foi possível gravar o padrão.\")))")
    (action_tile "cancel"   "(done_dialog 0)")
    (setq r (start_dialog))
    (if (= r 6) (cl:dlg-avancado dcl))
    (unload_dialog dcl)
    (setq dcl nil)
    (cond
      ((member r '(2 3 4 5))
       (vla-StartUndoMark doc)
       (cond ((= r 2) (cl:cabeceira T))
             ((= r 3) (cl:cabeceira nil))
             ((= r 4) (cl:internas))
             ((= r 5) (cl:selecionar)))
       (vla-EndUndoMark doc)
      )
      ((= r 7)
       (if (setq arq (getfiled "Carregar predefinição" (strcat (cl:pasta-config) "\\") "lin" 0))
         (if (cl:carregar-params arq)
           (princ (strcat "\nPredefinição carregada: " arq))
           (alert "Arquivo de predefinição inválido."))))
      ((= r 8)
       (if (setq arq (getfiled "Salvar predefinição" (strcat (cl:pasta-config) "\\") "lin" 1))
         (if (cl:salvar-params arq) (princ (strcat "\nPredefinição salva: " arq)))))
      ((= r 6))                                   ; volta ao diálogo
      (T (setq loop nil))
    )
  )
  (princ)
)

(princ "\nCriaLinhas carregado. Comando: CRIALINHAS")
(princ)
