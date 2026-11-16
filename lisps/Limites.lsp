;;; ==========================================================================
;;; Limites.lsp - Ajustes de linhas pelo limite do talhao
;;; --------------------------------------------------------------------------
;;; Recria o comportamento dos comandos do AgroCAD (aba AgroCAD > Ajustes):
;;;
;;;   CORTALIM   (COF)   Corta os trechos das linhas que ultrapassam os
;;;                      limites dos talhoes selecionados
;;;   ESTENDELIM (TOLIM) Estende as linhas selecionadas ate o limite do talhao
;;;   AJUSTALIM  (ESC)   Estende e corta as linhas ate o limite do talhao
;;;   APAGALIM   (DELIM) Apaga objetos inteira ou parcialmente contidos (ou
;;;                      fora de) uma polilinha fechada
;;;
;;; Diferencas em relacao ao original:
;;;   - a linha cortada mantem a entidade original (layer, cor, xdata e
;;;     object data ficam no primeiro trecho; os demais sao copias);
;;;   - arcos dentro das polilinhas sao preservados (sem discretizar);
;;;   - APAGALIM nao depende do zoom (nao usa selecao por janela).
;;;
;;; Linhas aceitas: LINE, ARC e LWPOLYLINE. Talhoes: LWPOLYLINE fechadas.
;;; Linhas e talhoes devem estar na mesma elevacao (intersecao e 3D).
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Utilitarios
;;; --------------------------------------------------------------------------
(defun lim:2d (p) (list (car p) (cadr p)))
(defun lim:tan (x) (/ (sin x) (cos x)))
(defun lim:bpar (b frac) (lim:tan (* (atan b) frac)))   ; bulge de arco parcial
(defun lim:hnd (o) (vla-get-Handle o))

(defun lim:ss->objs (ss / i r)
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq r (cons (vlax-ename->vla-object (ssname ss i)) r) i (1+ i)))))
  (reverse r)
)

;;; executa fn (sem argumentos) dentro de um UNDO com tratamento de erro
(defun lim:rodar (fn / *error* doc)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*"))
      (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (vla-StartUndoMark doc)
  (apply fn nil)
  (vla-EndUndoMark doc)
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Talhoes: (obj poligono-amostrado bbox)
;;; --------------------------------------------------------------------------
;;; vertices + 7 pontos intermediarios em cada trecho em arco
(defun lim:amostra (o / n i j res)
  (setq n (fix (+ 0.5 (vlax-curve-getEndParam o))) i 0)
  (repeat n
    (setq res (cons (lim:2d (vlax-curve-getPointAtParam o i)) res))
    (if (/= 0.0 (vla-GetBulge o i))
      (progn
        (setq j 1)
        (repeat 7
          (setq res (cons (lim:2d (vlax-curve-getPointAtParam o (+ i (/ j 8.0)))) res)
                j   (1+ j)))))
    (setq i (1+ i))
  )
  (reverse res)
)

(defun lim:talhao (o / poly xs ys)
  (setq poly (lim:amostra o)
        xs   (mapcar 'car poly)
        ys   (mapcar 'cadr poly))
  (list o poly (list (apply 'min xs) (apply 'min ys) (apply 'max xs) (apply 'max ys)))
)

(defun lim:sel-talhoes (msg / ss)
  (princ msg)
  (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
    (mapcar 'lim:talhao (lim:ss->objs ss)))
)

(defun lim:no-bbox (p bb)
  (and (<= (car bb) (car p) (caddr bb)) (<= (cadr bb) (cadr p) (cadddr bb)))
)

;;; ponto dentro do poligono (ray casting)
(defun lim:dentro-pol (p poly / x y in pb)
  (setq x (car p) y (cadr p) pb (last poly))
  (foreach pa poly
    (if (and (/= (> (cadr pa) y) (> (cadr pb) y))
             (< x (+ (car pa) (/ (* (- (car pb) (car pa)) (- y (cadr pa)))
                                 (- (cadr pb) (cadr pa))))))
      (setq in (not in)))
    (setq pb pa)
  )
  in
)

(defun lim:dentro (p tl) (and (lim:no-bbox p (caddr tl)) (lim:dentro-pol p (cadr tl))))

(defun lim:talhao-de (p tals)
  (vl-some '(lambda (tl) (if (lim:dentro p tl) tl)) tals)
)

;;; seleciona as linhas (sem os proprios talhoes). abertas? = so linhas abertas
(defun lim:sel-linhas (msg tals abertas? / ss hs)
  (princ msg)
  (setq ss (ssget (if abertas?
                    '((-4 . "<OR") (0 . "LINE")
                        (-4 . "<AND") (0 . "LWPOLYLINE")
                          (-4 . "<NOT") (-4 . "&") (70 . 1) (-4 . "NOT>")
                        (-4 . "AND>")
                      (-4 . "OR>"))
                    '((0 . "LINE,ARC,LWPOLYLINE"))))
        hs (mapcar '(lambda (tl) (lim:hnd (car tl))) tals))
  (vl-remove-if '(lambda (o) (member (lim:hnd o) hs)) (lim:ss->objs ss))
)

;;; --------------------------------------------------------------------------
;;; Geometria dos trechos
;;; --------------------------------------------------------------------------
(defun lim:lw-data (e / ed v b)
  (setq ed (entget e))
  (foreach g ed
    (cond ((= (car g) 10) (setq v (cons (lim:2d (cdr g)) v)))
          ((= (car g) 42) (setq b (cons (cdr g) b)))))
  (list (reverse v) (reverse b))
)

;;; trecho [a,b] de uma LWPOLYLINE -> (P pontos bulges), preservando arcos
(defun lim:sub-lw (o a b / d v bl n ia fa ib fb pts buls k)
  (setq d  (lim:lw-data (vlax-vla-object->ename o))
        v  (car d) bl (cadr d) n (length v)
        ia (fix a) fa (- a ia) ib (fix b) fb (- b ib))
  (if (> fa (- 1.0 1e-9)) (setq ia (1+ ia) fa 0.0))
  (if (and (< fb 1e-9) (> ib ia)) (setq ib (1- ib) fb 1.0))
  (setq pts (list (lim:2d (vlax-curve-getPointAtParam o a))))
  (if (= ia ib)
    (setq buls (list (lim:bpar (nth (rem ia n) bl) (- fb fa))))
    (progn
      (setq buls (list (lim:bpar (nth (rem ia n) bl) (- 1.0 fa))) k (1+ ia))
      (while (< k ib)
        (setq pts  (cons (nth (rem k n) v) pts)
              buls (cons (nth (rem k n) bl) buls)
              k    (1+ k)))
      (setq pts  (cons (nth (rem ib n) v) pts)
            buls (cons (lim:bpar (nth (rem ib n) bl) fb) buls))
    )
  )
  (setq pts  (cons (lim:2d (vlax-curve-getPointAtParam o b)) pts)
        buls (cons 0.0 buls))
  (list 'P (reverse pts) (reverse buls))
)

;;; descritor do trecho [a,b] de qualquer curva suportada
(defun lim:geo (o a b / nome)
  (setq nome (vla-get-ObjectName o))
  (cond
    ((= nome "AcDbLine")
     (list 'L (vlax-curve-getPointAtParam o a) (vlax-curve-getPointAtParam o b)))
    ((= nome "AcDbArc") (list 'A a b))
    (T (lim:sub-lw o a b))
  )
)

;;; reescreve os vertices de uma LWPOLYLINE mantendo layer/cor/xdata
(defun lim:lw-set (e pts buls / ed cab cau mid)
  (setq ed (entget e '("*")))
  (foreach g ed
    (cond ((member (car g) '(10 40 41 42 91)))
          ((member (car g) '(210 -3)) (setq cau (cons g cau)))
          ((= (car g) 90) (setq cab (cons (cons 90 (length pts)) cab)))
          ((= (car g) 70) (setq cab (cons (cons 70 (logand (cdr g) (~ 1))) cab)))
          (T (setq cab (cons g cab)))))
  (setq mid (apply 'append
                   (mapcar '(lambda (p b) (list (cons 10 p) '(40 . 0.0) '(41 . 0.0) (cons 42 b)))
                           pts buls)))
  (entmod (append (reverse cab) mid (reverse cau)))
  (entupd e)
)

(defun lim:set-geo (o g / ang)
  (cond
    ((= (car g) 'L)
     (vla-put-StartPoint o (vlax-3d-point (cadr g)))
     (vla-put-EndPoint o (vlax-3d-point (caddr g))))
    ((= (car g) 'A)
     (setq ang (* 2.0 pi))
     (vla-put-StartAngle o (rem (cadr g) ang))
     (vla-put-EndAngle o (rem (caddr g) ang)))
    (T (lim:lw-set (vlax-vla-object->ename o) (cadr g) (caddr g)))
  )
  o
)

;;; --------------------------------------------------------------------------
;;; Cortar (COF)
;;; --------------------------------------------------------------------------
(defun lim:params-corte (o tals / r pr prms)
  (foreach tl tals
    (if (lim:bbox-cruza o (caddr tl))
      (progn
        (setq r (vl-catch-all-apply 'vlax-invoke (list o 'IntersectWith (car tl) acExtendNone)))
        (if (vl-catch-all-error-p r) (setq r nil))
        (while r
          (setq pr (vlax-curve-getParamAtPoint
                     o (vlax-curve-getClosestPointTo o (list (car r) (cadr r) (caddr r))))
                r  (cdddr r))
          (if pr (setq prms (cons pr prms)))))))
  (vl-sort prms '<)
)

;;; caixa envolvente do objeto cruza (ou toca) a bbox bb?
(defun lim:bbox-cruza (o bb / mn mx r)
  (setq r (vl-catch-all-apply 'vla-GetBoundingBox (list o 'mn 'mx)))
  (if (vl-catch-all-error-p r)
    T
    (progn
      (setq mn (vlax-safearray->list mn) mx (vlax-safearray->list mx))
      (not (or (< (car mx) (car bb)) (> (car mn) (caddr bb))
               (< (cadr mx) (cadr bb)) (> (cadr mn) (cadddr bb))))))
)

;;; devolve 'mantida 'cortada ou 'apagada
(defun lim:cortar (o tals / ini fim prms a b segs geos)
  (setq ini  (vlax-curve-getStartParam o)
        fim  (vlax-curve-getEndParam o)
        prms (lim:params-corte o tals))
  (if (null prms)
    (if (lim:talhao-de (lim:2d (vlax-curve-getPointAtParam o (/ (+ ini fim) 2.0))) tals)
      'mantida
      (progn (vla-delete o) 'apagada))
    (progn
      (setq prms (append (list ini) prms (list fim)))
      (while (cdr prms)
        (setq a (car prms) b (cadr prms) prms (cdr prms))
        (if (and (> (- b a) 1e-6)
                 (lim:talhao-de (lim:2d (vlax-curve-getPointAtParam o (/ (+ a b) 2.0))) tals))
          (setq segs (cons (list a b) segs))))
      (setq segs (reverse segs))
      (cond
        ((null segs) (vla-delete o) 'apagada)
        ((and (null (cdr segs)) (equal (car segs) (list ini fim) 1e-6)) 'mantida)
        (T
         ;; calcula todos os trechos antes de alterar o original
         (setq geos (mapcar '(lambda (s) (lim:geo o (car s) (cadr s))) segs))
         (lim:set-geo o (car geos))
         (foreach g (cdr geos) (lim:set-geo (vla-Copy o) g))
         'cortada)
      )
    )
  )
)

;;; --------------------------------------------------------------------------
;;; Estender (TOLIM)
;;; --------------------------------------------------------------------------
;;; ponto onde o prolongamento da ponta (no fim? = T) encontra o talhao que
;;; contem essa ponta; nil se a ponta esta fora ou ja esta no limite
(defun lim:alvo-ponta (o fim? tals / par p p2 tg tl z ray r q d best dbest)
  (setq par (if fim? (vlax-curve-getEndParam o) (vlax-curve-getStartParam o))
        p   (vlax-curve-getPointAtParam o par)
        p2  (lim:2d p)
        tg  (vlax-curve-getFirstDeriv o par))
  (if (not fim?) (setq tg (mapcar '- tg)))
  (if (and (setq tl (lim:talhao-de p2 tals))
           (> (distance p2 (lim:2d (vlax-curve-getClosestPointTo (car tl) p))) 1e-4)
           (> (distance '(0 0) (lim:2d tg)) 1e-12))
    (progn
      (setq z   (vla-get-Elevation (car tl))
            tg  (lim:2d tg)
            tg  (mapcar '(lambda (c) (/ c (distance '(0 0) tg))) tg))
      (entmake (list '(0 . "RAY") '(100 . "AcDbEntity") '(100 . "AcDbRay")
                     (list 10 (car p) (cadr p) z) (list 11 (car tg) (cadr tg) 0.0)))
      (setq ray (vlax-ename->vla-object (entlast))
            r   (vl-catch-all-apply 'vlax-invoke (list ray 'IntersectWith (car tl) acExtendNone)))
      (vla-delete ray)
      (if (vl-catch-all-error-p r) (setq r nil))
      (while r
        (setq q (list (car r) (cadr r)) r (cdddr r) d (distance p2 q))
        (if (and (> d 1e-6) (or (null dbest) (< d dbest)))
          (setq best q dbest d)))
      best
    )
  )
)

(defun lim:pt2-var (p)
  (vlax-make-variant
    (vlax-safearray-fill (vlax-make-safearray vlax-vbDouble '(0 . 1)) (lim:2d p)))
)

;;; estende as duas pontas; devolve o numero de pontas estendidas
(defun lim:estender (o tals / nome n q z k)
  (setq nome (vla-get-ObjectName o) k 0)
  (foreach fim? '(nil T)
    (if (setq q (lim:alvo-ponta o fim? tals))
      (progn
        (cond
          ((= nome "AcDbLine")
           (setq z (caddr (if fim? (vlax-curve-getEndPoint o) (vlax-curve-getStartPoint o))))
           (if fim?
             (vla-put-EndPoint o (vlax-3d-point (list (car q) (cadr q) z)))
             (vla-put-StartPoint o (vlax-3d-point (list (car q) (cadr q) z)))))
          ((= nome "AcDbPolyline")
           (setq n (fix (+ 0.5 (vlax-curve-getEndParam o))))   ; ultimo vertice
           (cond
             ;; trecho final reto: move o vertice da ponta
             ((and fim? (= 0.0 (vla-GetBulge o (1- n))))
              (vla-put-Coordinate o n (lim:pt2-var q)))
             ((and (not fim?) (= 0.0 (vla-GetBulge o 0)))
              (vla-put-Coordinate o 0 (lim:pt2-var q)))
             ;; trecho final em arco: acrescenta um segmento reto tangente
             (fim?
              (vla-SetBulge o n 0.0)
              (vla-AddVertex o (1+ n) (lim:pt2-var q)))
             (T
              (vla-AddVertex o 0 (lim:pt2-var q))
              (vla-SetBulge o 0 0.0))
           ))
        )
        (setq k (1+ k))
      )
    )
  )
  k
)

;;; --------------------------------------------------------------------------
;;; Comandos
;;; --------------------------------------------------------------------------
(defun lim:resumo (cont)
  (princ (strcat "\n" (itoa (nth 0 cont)) " cortada(s), "
                 (itoa (nth 1 cont)) " apagada(s) por estarem fora, "
                 (itoa (nth 2 cont)) " ponta(s) estendida(s)"
                 (if (> (nth 3 cont) 0)
                   (strcat ", " (itoa (nth 3 cont)) " com erro (layer travado?)")
                   "")
                 "."))
)

;;; modo: 'C cortar, 'E estender, 'EC estender e cortar
(defun lim:processar (modo / tals linhas cont r)
  (if (and (setq linhas (lim:sel-linhas "\nSelecione as linhas: " nil (= modo 'E)))
           (setq tals (lim:sel-talhoes "\nSelecione os talhoes (limites): ")))
    (progn
      ;; remove das linhas os talhoes selecionados na segunda etapa
      (setq r (mapcar '(lambda (tl) (lim:hnd (car tl))) tals)
            linhas (vl-remove-if '(lambda (o) (member (lim:hnd o) r)) linhas)
            cont '(0 0 0 0))
      (foreach o linhas
        (setq r (vl-catch-all-apply
                  '(lambda (/ k)
                     (setq k 0)
                     (if (and (member modo '(E EC)) (not (vlax-curve-isClosed o)))
                       (setq k (lim:estender o tals)))
                     (list k (if (member modo '(C EC)) (lim:cortar o tals) 'mantida)))
                  nil))
        (if (vl-catch-all-error-p r)
          (setq cont (list (nth 0 cont) (nth 1 cont) (nth 2 cont) (1+ (nth 3 cont))))
          (setq cont (list (+ (nth 0 cont) (if (eq (cadr r) 'cortada) 1 0))
                           (+ (nth 1 cont) (if (eq (cadr r) 'apagada) 1 0))
                           (+ (nth 2 cont) (car r))
                           (nth 3 cont))))
      )
      (lim:resumo cont)
    )
    (princ "\nNada selecionado.")
  )
)

(defun c:CORTALIM ()   (lim:rodar '(lambda () (lim:processar 'C))))
(defun c:ESTENDELIM () (lim:rodar '(lambda () (lim:processar 'E))))
(defun c:AJUSTALIM ()  (lim:rodar '(lambda () (lim:processar 'EC))))

;;; --------------------------------------------------------------------------
;;; APAGALIM (DELIM)
;;; --------------------------------------------------------------------------
;;; situacao do objeto em relacao ao limite: 'dentro 'fora 'cruza
(defun lim:situacao (o tl / r mn mx p)
  (cond
    ((not (lim:bbox-cruza o (caddr tl))) 'fora)
    ((and (setq r (vl-catch-all-apply 'vlax-invoke (list o 'IntersectWith (car tl) acExtendNone)))
          (not (vl-catch-all-error-p r)))
     'cruza)
    (T
     (setq p (vl-catch-all-apply 'vlax-curve-getStartPoint (list o)))
     (if (or (null p) (vl-catch-all-error-p p))
       (progn                                   ; nao e curva: centro da bbox
         (vla-GetBoundingBox o 'mn 'mx)
         (setq mn (vlax-safearray->list mn) mx (vlax-safearray->list mx)
               p  (mapcar '(lambda (a b) (/ (+ a b) 2.0)) mn mx))))
     (if (lim:dentro (lim:2d p) tl) 'dentro 'fora))
  )
)

;;; layer visivel (ligado e descongelado)? usa cache em *lim-vis*
(defun lim:layer-visivel (nome / c lay)
  (if (setq c (assoc nome *lim-vis*))
    (cdr c)
    (progn
      (setq lay (vla-item (vla-get-Layers (vla-get-ActiveDocument (vlax-get-acad-object))) nome)
            c   (and (= :vlax-true (vla-get-LayerOn lay)) (= :vlax-false (vla-get-Freeze lay))))
      (setq *lim-vis* (cons (cons nome c) *lim-vis*))
      c))
)

(defun lim:apagar (/ ent tl lado modo ss h n err o s *lim-vis*)
  (while (and (setq ent (entsel "\nSelecione a polilinha limite: "))
              (not (and (= "LWPOLYLINE" (cdr (assoc 0 (entget (car ent)))))
                        (= 1 (logand 1 (cdr (assoc 70 (entget (car ent)))))))))
    (princ "\nO limite precisa ser uma polilinha fechada.")
  )
  (if ent
    (progn
      (setq tl (lim:talhao (vlax-ename->vla-object (car ent))) h (lim:hnd (car tl)))
      (initget "Dentro Fora")
      (setq lado (cond ((getkword "\nApagar objetos [Dentro/Fora] do limite <Dentro>: ")) ("Dentro")))
      (initget "Inteiros Parciais")
      (setq modo (cond ((getkword "\nConsiderar [Inteiros/Parciais (inclui os que cruzam)] <Inteiros>: "))
                       ("Inteiros")))
      (setq ss (ssget "_X" (list (cons 410 (getvar "CTAB")))) n 0 err 0)
      (foreach o (lim:ss->objs ss)
        (if (and (/= (lim:hnd o) h) (lim:layer-visivel (vla-get-Layer o)))
          (progn
            (setq s (vl-catch-all-apply 'lim:situacao (list o tl)))
            (if (and (not (vl-catch-all-error-p s))
                     (or (and (= lado "Dentro") (eq s 'dentro))
                         (and (= lado "Fora") (eq s 'fora))
                         (and (= modo "Parciais") (eq s 'cruza))))
              (if (vl-catch-all-error-p (vl-catch-all-apply 'vla-delete (list o)))
                (setq err (1+ err))
                (setq n (1+ n)))))))
      (princ (strcat "\n" (itoa n) " objeto(s) apagado(s)"
                     (if (> err 0) (strcat ", " (itoa err) " em layer travado") "")
                     "."))
    )
  )
)

(defun c:APAGALIM () (lim:rodar 'lim:apagar))

(princ "\nLimites carregado. Comandos: CORTALIM ESTENDELIM AJUSTALIM APAGALIM")
(princ)
