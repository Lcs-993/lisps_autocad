;;; ==========================================================================
;;; Carreadores.lsp - Criar Carreadores / Juntar Talhões
;;; --------------------------------------------------------------------------
;;; Equivalente ao GOROA do AgroCAD ("Criar Carreadores"):
;;;
;;;   Criar Carreadores : corta os talhões selecionados por uma faixa de
;;;                       Largura (m) em volta de cada eixo de carreador e
;;;                       desenha o polígono do carreador (layer CARREADORES,
;;;                       recortado à área dos talhões)
;;;   Juntar Talhões    : desfaz carreadores - une os talhões que se encostam
;;;                       ou estão separados por vãos de até Largura (m)
;;;   Manter os talhões originais / Apagar Linhas de Eixos
;;;
;;; Eixos aceitos: LINE, ARC, LWPOLYLINE (aberta ou fechada - anel).
;;; Talhões: LWPOLYLINE fechadas (arcos preservados).
;;;
;;; Desempenho:
;;;   - booleanas feitas pelo ACIS (REGION) em código nativo: robusto com
;;;     arcos, talhões côncavos e cruzamentos de carreadores;
;;;   - faixa de cada eixo montada UMA vez (2 offsets + dados DXF);
;;;   - cada talhão só subtrai as faixas cujo retângulo envolvente o toca;
;;;     talhão sem carreador não é recriado;
;;;   - contornos lidos por entget das arestas explodidas e encadeados em
;;;     O(n) quando vêm em ordem (o normal), com busca só como reserva.
;;;
;;; Comando: CARREADORES
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Parâmetros (persistem via setenv)
;;; --------------------------------------------------------------------------
(defun cr:le-env (/ v)
  (setq *CR-LARG* 8.0 *CR-MANTER* nil *CR-APAGAR-EIXOS* nil)
  (if (and (setq v (getenv "LISPS_CARREADORES"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= 3 (length v)) (numberp (car v)))
    (setq *CR-LARG* (car v) *CR-MANTER* (cadr v) *CR-APAGAR-EIXOS* (caddr v)))
)
(defun cr:grava-env ()
  (setenv "LISPS_CARREADORES" (vl-prin1-to-string (list *CR-LARG* *CR-MANTER* *CR-APAGAR-EIXOS*)))
)
(if (not *CR-LARG*) (cr:le-env))

(setq *CR-TOL* 1e-4)                     ; tolerância de encadeamento (m)

;;; --------------------------------------------------------------------------
;;; Utilitários
;;; --------------------------------------------------------------------------
(defun cr:2d (p) (list (car p) (cadr p)))
(defun cr:doc () (vla-get-ActiveDocument (vlax-get-acad-object)))
(defun cr:espaco () (vla-get-Block (vla-get-ActiveLayout (cr:doc))))

(defun cr:layer-carreador (/ nome cor)
  (setq nome (if tr:cfg-nome (tr:cfg-nome 'NOM_LAY_CARREADORES "CARREADORES") "CARREADORES")
        cor  (if tr:cfg-cor (tr:cfg-cor "COR_LAY_CARREADORES" 7) 7))
  (if (not (tblsearch "LAYER" nome))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 nome) '(70 . 0) (cons 62 cor) '(6 . "Continuous"))))
  nome
)

;;; retângulo envolvente ((xmin ymin) (xmax ymax))
(defun cr:bbox (o / a b)
  (vla-GetBoundingBox o 'a 'b)
  (list (cr:2d (vlax-safearray->list a)) (cr:2d (vlax-safearray->list b)))
)
(defun cr:bbox-toca (a b)
  (and (<= (car (car a)) (car (cadr b))) (<= (car (car b)) (car (cadr a)))
       (<= (cadr (car a)) (cadr (cadr b))) (<= (cadr (car b)) (cadr (cadr a))))
)

;;; vértices e bulges de uma LWPOLYLINE
(defun cr:lw-data (e / ed v b)
  (setq ed (entget e))
  (foreach g ed
    (cond ((= (car g) 10) (setq v (cons (cdr g) v)))
          ((= (car g) 42) (setq b (cons (cdr g) b)))))
  (list (reverse v) (reverse b) (= 1 (logand 1 (cdr (assoc 70 ed)))) ed)
)

;;; LWPOLYLINE a partir de pontos/bulges; props = grupos DXF a copiar
(defun cr:mk-lw (pts buls fechada props)
  (entmake
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity"))
      props
      (list '(100 . "AcDbPolyline") (cons 90 (length pts)) (cons 70 (if fechada 1 0)) '(38 . 0.0))
      (apply 'append (mapcar '(lambda (p b) (list (cons 10 p) (cons 42 b))) pts buls))))
  (entlast)
)

(defun cr:props (ed / r)
  (foreach k '(8 62 6 370 48 420 440) (if (assoc k ed) (setq r (cons (assoc k ed) r))))
  (reverse r)
)

;;; offset; devolve lista de objetos (nil se falhar)
(defun cr:offset (o d / r)
  (setq r (vl-catch-all-apply 'vlax-invoke (list o 'Offset d)))
  (if (vl-catch-all-error-p r) nil r)
)

(defun cr:apaga (l) (foreach o l (vl-catch-all-apply 'vla-delete (list o))))

;;; regiões a partir de curvas fechadas (lista); nil se falhar
(defun cr:regiao (objs / r)
  (setq r (vl-catch-all-apply 'vlax-invoke (list (cr:espaco) 'AddRegion objs)))
  (if (vl-catch-all-error-p r) nil r)
)

;;; une a lista de regiões numa só (as demais são consumidas)
(defun cr:une-regioes (regs / base)
  (setq base (car regs))
  (foreach r (cdr regs) (vla-Boolean base acUnion r))
  base
)

;;; --------------------------------------------------------------------------
;;; Região -> polilinhas fechadas
;;; --------------------------------------------------------------------------
;;; arestas (pa pb bulge) de uma região; explode (recursivo) e apaga as peças
(defun cr:arestas (reg / objs res ed tp c r a0 a1 nrm s)
  (setq objs (vl-catch-all-apply 'vlax-invoke (list reg 'Explode)))
  (if (not (vl-catch-all-error-p objs))
    (foreach o objs
      (if (= (vla-get-ObjectName o) "AcDbRegion")
        (progn (setq res (append (reverse (cr:arestas o)) res)) (vla-delete o))
        (progn
          (setq ed (entget (vlax-vla-object->ename o)) tp (cdr (assoc 0 ed)))
          (cond
            ((= tp "LINE")
             (setq res (cons (list (cr:2d (cdr (assoc 10 ed))) (cr:2d (cdr (assoc 11 ed))) 0.0) res)))
            ((= tp "ARC")
             (setq nrm (cdr (assoc 210 ed)) c (cdr (assoc 10 ed)) r (cdr (assoc 40 ed))
                   a0 (cdr (assoc 50 ed)) a1 (cdr (assoc 51 ed))
                   s  (rem (+ (- a1 a0) (* 4.0 pi)) (* 2.0 pi)))
             (setq res (cons (list (cr:2d (trans (polar c a0 r) nrm 0))
                                   (cr:2d (trans (polar c a1 r) nrm 0))
                                   (* (if (< (caddr nrm) 0) -1.0 1.0) (/ (sin (/ s 4.0)) (cos (/ s 4.0)))))
                             res)))
            (T                                         ; outra curva: corda
             (setq res (cons (list (cr:2d (vlax-curve-getStartPoint o))
                                   (cr:2d (vlax-curve-getEndPoint o)) 0.0)
                             res))))
          (entdel (vlax-vla-object->ename o))))))
  (reverse res)
)

;;; encadeia arestas em laços fechados: ((pts buls) ...)
(defun cr:lacos (ars / res ini fim pts buls a resto ach parou)
  (while ars
    (setq a (car ars) ars (cdr ars) parou nil
          ini (car a) fim (cadr a) pts (list (car a)) buls (list (caddr a)))
    (while (and ars (not parou) (> (distance fim ini) *CR-TOL*))
      (setq a (car ars) ach nil)
      (cond
        ((< (distance (car a) fim) *CR-TOL*) (setq ach a ars (cdr ars)))           ; em ordem
        ((< (distance (cadr a) fim) *CR-TOL*)
         (setq ach (list (cadr a) (car a) (- (caddr a))) ars (cdr ars)))
        (T                                                                         ; reserva
         (setq resto nil)
         (while (and ars (not ach))
           (setq a (car ars) ars (cdr ars))
           (cond ((< (distance (car a) fim) *CR-TOL*) (setq ach a))
                 ((< (distance (cadr a) fim) *CR-TOL*) (setq ach (list (cadr a) (car a) (- (caddr a)))))
                 (T (setq resto (cons a resto)))))
         (setq ars (append (reverse resto) ars))))
      (if ach
        (setq pts (cons (car ach) pts) buls (cons (caddr ach) buls) fim (cadr ach))
        (setq parou T)))                                     ; laço aberto: descarta só ele
    (if (and (cdr pts) (<= (distance fim ini) *CR-TOL*))
      (setq res (cons (list (reverse pts) (reverse buls)) res))))
  (reverse res)
)

;;; região -> polilinhas fechadas com as props; apaga a região
(defun cr:regiao->lw (reg props / n)
  (setq n 0)
  (foreach l (cr:lacos (cr:arestas reg))
    (cr:mk-lw (car l) (cadr l) T props)
    (setq n (1+ n)))
  (vl-catch-all-apply 'vla-delete (list reg))
  n
)

;;; --------------------------------------------------------------------------
;;; Faixa do carreador em volta de um eixo
;;; --------------------------------------------------------------------------
;;; eixo -> LWPOLYLINE temporária (LINE/ARC convertidos)
(defun cr:eixo-lw (e / ed tp o)
  (setq ed (entget e) tp (cdr (assoc 0 ed)) o (vlax-ename->vla-object e))
  (cond
    ((= tp "LWPOLYLINE") (vla-Copy o))
    ((= tp "LINE")
     (vlax-ename->vla-object
       (cr:mk-lw (list (cr:2d (cdr (assoc 10 ed))) (cr:2d (cdr (assoc 11 ed)))) '(0.0 0.0) nil '((8 . "0")))))
    ((= tp "ARC")
     (vlax-ename->vla-object
       (cr:mk-lw (list (cr:2d (vlax-curve-getStartPoint o)) (cr:2d (vlax-curve-getEndPoint o)))
                 (list (/ (sin (/ (vla-get-TotalAngle o) 4.0)) (cos (/ (vla-get-TotalAngle o) 4.0))) 0.0)
                 nil '((8 . "0"))))))
)

;;; região da faixa de largura w em volta do eixo e; nil se falhar
(defun cr:faixa (e w / ax d a b da db pts buls lw reg r1 r2)
  (setq ax (cr:eixo-lw e) d (cr:lw-data (vlax-vla-object->ename ax)))
  (setq a (cr:offset ax (/ w 2.0)) b (cr:offset ax (/ w -2.0)))
  (cond
    ((not (and (= 1 (length a)) (= 1 (length b))))   ; offset falhou ou partiu
     (cr:apaga a) (cr:apaga b) nil)
    ((caddr d)                                        ; eixo fechado: anel
     (setq r1 (cr:regiao a) r2 (cr:regiao b))
     (cr:apaga a) (cr:apaga b)
     (if (and r1 r2)
       (progn
         (setq r1 (car r1) r2 (car r2))
         (if (< (vla-get-Area r1) (vla-get-Area r2)) (setq reg r1 r1 r2 r2 reg))
         (vla-Boolean r1 acSubtraction r2)           ; externo - interno
         (setq reg r1))
       (progn (cr:apaga r1) (cr:apaga r2) (setq reg nil))))
    (T                                                ; aberto: lado A + volta pelo lado B
     (setq da (cr:lw-data (vlax-vla-object->ename (car a)))
           db (cr:lw-data (vlax-vla-object->ename (car b)))
           pts  (append (car da) (reverse (car db)))
           buls (append (reverse (cdr (reverse (cadr da)))) '(0.0)
                        (mapcar '- (cdr (reverse (cadr db)))) '(0.0)))
     (cr:apaga a) (cr:apaga b)
     (setq lw  (vlax-ename->vla-object (cr:mk-lw pts buls T '((8 . "0"))))
           reg (cr:regiao (list lw)))
     (vla-delete lw)
     (setq reg (car reg))))
  (vla-delete ax)
  reg
)

;;; --------------------------------------------------------------------------
;;; Seleção
;;; --------------------------------------------------------------------------
(defun cr:sel-talhoes (/ ss i res)
  (princ "\nSelecione os talhões: ")
  (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
    (progn
      (setq i 0)
      (repeat (sslength ss) (setq res (cons (ssname ss i) res) i (1+ i)))))
  (reverse res)
)

(defun cr:sel-eixos (/ ss i res)
  (princ "\nSelecione os eixos dos carreadores: ")
  (if (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE"))))
    (progn
      (setq i 0)
      (repeat (sslength ss) (setq res (cons (ssname ss i) res) i (1+ i)))))
  (reverse res)
)

;;; --------------------------------------------------------------------------
;;; CRIAR CARREADORES
;;; --------------------------------------------------------------------------
(defun cr:criar (/ talhoes eixos t0 faixas bbs ref rel reg sub rede uni copia
                   n-tal n-pec n-car falhas a0 props lay)
  (if (and (setq talhoes (cr:sel-talhoes))
           (setq eixos (vl-remove-if '(lambda (e) (member e talhoes)) (cr:sel-eixos))))
    (progn
      (setq t0 (getvar "MILLISECS") n-tal 0 n-pec 0 n-car 0 falhas 0)
      ;; 1 faixa (região) por eixo, com seu retângulo envolvente
      (foreach e eixos
        (if (setq reg (cr:faixa e *CR-LARG*))
          (setq faixas (cons (list reg (cr:bbox reg)) faixas))
          (setq falhas (1+ falhas))))
      (foreach tl talhoes
        (setq ref (vlax-ename->vla-object tl)
              bbs (cr:bbox ref)
              rel (vl-remove-if-not '(lambda (f) (cr:bbox-toca (cadr f) bbs)) faixas))
        (if (and rel (setq reg (cr:regiao (list ref))))
          (progn
            (setq reg   (car reg)
                  a0    (vla-get-Area reg)
                  props (cr:props (entget tl))
                  copia (vla-Copy reg)                   ; p/ o polígono do carreador
                  sub   (cr:une-regioes (mapcar '(lambda (f) (vla-Copy (car f))) rel)))
            (vla-Boolean reg acSubtraction sub)
            (if (equal (vla-get-Area reg) a0 1e-6)
              (progn (vla-delete reg) (vla-delete copia))   ; não cruzou: fica como está
              (progn
                (setq n-pec (+ n-pec (cr:regiao->lw reg props))
                      n-tal (1+ n-tal)
                      uni   (cons copia uni))
                (if (not *CR-MANTER*) (entdel tl)))))))
      ;; polígono do carreador = (união dos talhões cortados) INTERSEÇÃO (rede de faixas)
      (if (and uni faixas)
        (progn
          (setq lay  (cr:layer-carreador)
                uni  (cr:une-regioes uni)
                rede (cr:une-regioes (mapcar '(lambda (f) (vla-Copy (car f))) faixas)))
          (vla-Boolean uni acIntersection rede)
          (setq n-car (cr:regiao->lw uni (list (cons 8 lay))))))
      (foreach f faixas (vla-delete (car f)))
      (if *CR-APAGAR-EIXOS* (foreach e eixos (entdel e)))
      (princ (strcat "\n" (itoa n-tal) " talhão(ões) cortado(s) em " (itoa n-pec) " parte(s); "
                     (itoa n-car) " polígono(s) de carreador."
                     (if (> falhas 0) (strcat " " (itoa falhas) " eixo(s) sem faixa válida (offset falhou).") "")
                     " [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; JUNTAR TALHÕES (desfaz carreadores de até Largura)
;;;   fechamento morfológico: offset para fora d -> união -> offset para dentro d
;;; --------------------------------------------------------------------------
(defun cr:dentro (p pts / x y in pb)
  (setq x (car p) y (cadr p) pb (last pts))
  (foreach pa pts
    (if (and (/= (> (cadr pa) y) (> (cadr pb) y))
             (< x (+ (car pa) (/ (* (- (car pb) (car pa)) (- y (cadr pa))) (- (cadr pb) (cadr pa))))))
      (setq in (not in)))
    (setq pb pa))
  in
)

;;; offset de um contorno fechado aumentando (mais = T) ou diminuindo a área
(defun cr:offset-area (o d mais / r a0)
  (setq a0 (vla-get-Area o) r (cr:offset o d))
  (if (and r (/= mais (> (vla-get-Area (car r)) a0)))
    (progn (cr:apaga r) (setq r (cr:offset o (- d)))))
  r
)

(defun cr:juntar (/ talhoes t0 d props regs ofs uni lacos l lw furo n)
  (if (and (setq talhoes (cr:sel-talhoes)) (cdr talhoes))
    (progn
      (setq t0 (getvar "MILLISECS") d (+ (/ *CR-LARG* 2.0) 1e-3) n 0
            props (cr:props (entget (car talhoes))))
      ;; para fora + região
      (foreach tl talhoes
        (if (setq ofs (cr:offset-area (vlax-ename->vla-object tl) d T))
          (progn
            (foreach r (cr:regiao ofs) (setq regs (cons r regs)))
            (cr:apaga ofs))))
      (if regs
        (progn
          (setq uni (cr:une-regioes regs) lacos (cr:lacos (cr:arestas uni)))
          (vl-catch-all-apply 'vla-delete (list uni))
          ;; cada laço volta para dentro; furo (laço dentro de outro) cresce
          (foreach l lacos
            (setq furo (vl-some '(lambda (m) (and (not (eq m l)) (cr:dentro (car (car l)) (car m)))) lacos)
                  lw   (vlax-ename->vla-object (cr:mk-lw (car l) (cadr l) T props)))
            (setq n (+ n (length (cr:offset-area lw d furo))))
            (vla-delete lw))
          (if (and (> n 0) (not *CR-MANTER*)) (foreach tl talhoes (entdel tl)))
          (princ (strcat "\n" (itoa (length talhoes)) " talhão(ões) unido(s) em " (itoa n) " contorno(s)."
                         " [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]")))))
    (princ "\nSelecione pelo menos dois talhões."))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun cr:pasta ()
  (cond (*LISPS-DIR*)
        ((findfile "Carreadores.dcl") (vl-filename-directory (findfile "Carreadores.dcl"))))
)

(defun cr:le-tiles (/ w)
  (setq w (get_tile "larg"))
  (setq w (if w (distof (vl-string-translate "," "." w) 2)))
  (if (and w (> w 0.0))
    (progn
      (setq *CR-LARG* w
            *CR-MANTER* (= "1" (get_tile "manter"))
            *CR-APAGAR-EIXOS* (= "1" (get_tile "apagar")))
      (cr:grava-env)
      T)
    (progn (set_tile "status" "Largura inválida (> 0).") nil))
)

(defun c:CARREADORES (/ *error* doc dcl arq r)
  (setq doc (cr:doc))
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*"))
      (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (setq arq (if (cr:pasta) (strcat (cr:pasta) "\\Carreadores.dcl")))
  (if (not (and arq (findfile arq)))
    (progn (alert "Arquivo Carreadores.dcl não encontrado.") (exit)))
  (setq dcl (load_dialog arq))
  (if (not (new_dialog "carreadores" dcl))
    (progn (alert "Erro ao abrir o diálogo.") (exit)))
  (set_tile "larg"   (rtos *CR-LARG* 2 2))
  (set_tile "manter" (if *CR-MANTER* "1" "0"))
  (set_tile "apagar" (if *CR-APAGAR-EIXOS* "1" "0"))
  (action_tile "criar"  "(if (cr:le-tiles) (done_dialog 1))")
  (action_tile "juntar" "(if (cr:le-tiles) (done_dialog 2))")
  (action_tile "cancel" "(done_dialog 0)")
  (setq r (start_dialog))
  (unload_dialog dcl)
  (setq dcl nil)
  (if (member r '(1 2))
    (progn
      (vla-StartUndoMark doc)
      (if (= r 1) (cr:criar) (cr:juntar))
      (vla-EndUndoMark doc)))
  (princ)
)

(princ "\nCarreadores carregado. Comando: CARREADORES")
(princ)
