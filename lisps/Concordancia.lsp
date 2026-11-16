;;; Concordancia.lsp - SIS_CONCORDAR
;;; Concordância de eixos de estradas agrícolas:
;;;   Cruzamentos: arcos de concordância de raio R nos quadrantes de giro
;;;                (T, X, L e nós múltiplos) + quebra dos eixos no nó.
;;;   Praça:       anel em volta da ilha/obstáculo (contorno + afastamento),
;;;                eixo removido dentro do anel, bifurcação e fusão com
;;;                arcos de raio R nos dois lados, quebra no nó e nas
;;;                tangências.
;;;
;;; Desempenho: geometria 100% analítica a partir do DXF (segmentos retos e
;;; arcos/bulges). Interseções por varredura em x (sweep) dos retângulos dos
;;; segmentos; concordâncias pela interseção das primitivas deslocadas de R;
;;; quebras reconstruindo as entidades (entmake) com bulges parciais. Sem
;;; BREAK/FILLET/IntersectWith. COM só no Offset do anel (1 por ilha).
;;;
;;; Entidades: LINE, ARC, LWPOLYLINE (eixos); CIRCLE e LWPOLYLINE fechada
;;; (ilhas). Normal (0 0 1). Prefixo interno: sc:

(vl-load-com)

(setq *SC-TOL* 1e-6     ; tolerância geométrica das interseções (unid. do desenho)
      *SC-NO*  1e-4)    ; tolerância para agrupar nós e posições

;;; ------------------------------------------------------------------
;;; Parâmetros persistentes
;;; ------------------------------------------------------------------
(defun sc:env-num (k def / v)
  (if (and (setq v (getenv (strcat "LISPS_CONCORDAR_" k))) (setq v (distof v 2))) v def))
(defun sc:env-str (k def / v)
  (if (and (setq v (getenv (strcat "LISPS_CONCORDAR_" k))) (/= v "")) v def))
(defun sc:grava-env ()
  (setenv "LISPS_CONCORDAR_RAIO" (rtos *SC-RAIO* 2 6))
  (setenv "LISPS_CONCORDAR_AFAST" (rtos *SC-AFAST* 2 6))
  (setenv "LISPS_CONCORDAR_MODO" *SC-MODO*)
  (setenv "LISPS_CONCORDAR_QTAN" *SC-QTAN*))

(if (not *SC-RAIO*)  (setq *SC-RAIO*  (sc:env-num "RAIO" 10.0)))
(if (not *SC-AFAST*) (setq *SC-AFAST* (sc:env-num "AFAST" 0.0)))
(if (not *SC-MODO*)  (setq *SC-MODO*  (sc:env-str "MODO" "Cruzamentos")))
(if (not *SC-QTAN*)  (setq *SC-QTAN*  (sc:env-str "QTAN" "Nao")))

;;; ------------------------------------------------------------------
;;; Vetores 2D
;;; ------------------------------------------------------------------
(defun sc:p2 (p) (list (car p) (cadr p)))
(defun sc:v+ (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun sc:v- (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun sc:vk (v k) (list (* k (car v)) (* k (cadr v))))
(defun sc:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun sc:cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))
(defun sc:len (v) (sqrt (sc:dot v v)))
(defun sc:unit (v / l) (setq l (sc:len v)) (if (> l 1e-300) (sc:vk v (/ 1.0 l)) v))
(defun sc:esq (v) (list (- (cadr v)) (car v)))          ; normal à esquerda
(defun sc:ang (v) (atan (cadr v) (car v)))
(defun sc:norm2pi (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)
(defun sc:tan4 (th) (/ (sin (/ th 4.0)) (cos (/ th 4.0))))
(defun sc:clamp (k) (max 0.0 (min 1.0 k)))
(defun sc:butlast (l) (reverse (cdr (reverse l))))

;;; ------------------------------------------------------------------
;;; Segmentos: (p0 p1 bulge comprimento s0 arco)
;;;   arco = (centro raio ângulo-inicial theta) ou nil; theta > 0 anti-horário
;;; Curva:    (idx ename tipo fechada segs L props elev papel extra)
;;; ------------------------------------------------------------------
(defun sc:arco (p0 p1 b / th d c)
  (setq th (* 4.0 (atan b))
        d  (/ (* (distance p0 p1) (+ 1.0 (* b b))) (* 4.0 b))
        c  (sc:p2 (polar p0 (+ (angle p0 p1) (- (/ pi 2.0) (/ th 2.0))) d)))
  (list c (abs d) (angle c p0) th))

(defun sc:prepara (segs / acc out arc ln)
  (setq acc 0.0)
  (foreach sg segs
    (if (not (equal (car sg) (cadr sg) 1e-9))
      (progn
        (if (> (abs (caddr sg)) 1e-10)
          (setq arc (sc:arco (car sg) (cadr sg) (caddr sg))
                ln  (* (cadr arc) (abs (cadddr arc))))
          (setq arc nil ln (distance (car sg) (cadr sg))))
        (setq out (cons (list (car sg) (cadr sg) (caddr sg) ln acc arc) out)
              acc (+ acc ln)))))
  (cons acc (reverse out)))

(defun sc:seg-pt (sg k / arc a)
  (if (setq arc (nth 5 sg))
    (progn
      (setq a (+ (caddr arc) (* (cadddr arc) k)))
      (sc:v+ (car arc) (list (* (cadr arc) (cos a)) (* (cadr arc) (sin a)))))
    (sc:v+ (car sg) (sc:vk (sc:v- (cadr sg) (car sg)) k))))

(defun sc:seg-tan (sg k / arc a v)
  (if (setq arc (nth 5 sg))
    (progn
      (setq a (+ (caddr arc) (* (cadddr arc) k))
            v (list (- (sin a)) (cos a)))
      (if (< (cadddr arc) 0.0) (sc:vk v -1.0) v))
    (sc:unit (sc:v- (cadr sg) (car sg)))))

(defun sc:props (ed)
  (vl-remove-if-not '(lambda (x) (member (car x) '(8 62 6 48 370 420 430 440))) ed))

(defun sc:le (en idx papel / ed tp nrm segs c r a0 a1 th pts bs fech elev ex pr)
  (setq ed (entget en) tp (cdr (assoc 0 ed)) nrm (cdr (assoc 210 ed)) fech nil)
  (if (or (null nrm) (equal nrm '(0.0 0.0 1.0) 1e-9))
    (progn
      (cond
        ((= tp "LINE")
         (setq elev (caddr (cdr (assoc 10 ed)))
               segs (list (list (sc:p2 (cdr (assoc 10 ed))) (sc:p2 (cdr (assoc 11 ed))) 0.0))))
        ((= tp "ARC")
         (setq c (cdr (assoc 10 ed)) r (cdr (assoc 40 ed))
               a0 (cdr (assoc 50 ed)) a1 (cdr (assoc 51 ed))
               elev (caddr c) c (sc:p2 c)
               th (sc:norm2pi (- a1 a0))
               ex (list c r)
               segs (list (list (sc:p2 (polar c a0 r)) (sc:p2 (polar c a1 r)) (sc:tan4 th)))))
        ((= tp "CIRCLE")
         (setq c (cdr (assoc 10 ed)) r (cdr (assoc 40 ed))
               elev (caddr c) c (sc:p2 c) fech T ex (list c r)
               segs (list (list (sc:v+ c (list r 0.0)) (sc:v- c (list r 0.0)) 1.0)
                          (list (sc:v- c (list r 0.0)) (sc:v+ c (list r 0.0)) 1.0))))
        ((= tp "LWPOLYLINE")
         (foreach x ed
           (cond ((= (car x) 10) (setq pts (cons (list (cadr x) (caddr x)) pts) bs (cons 0.0 bs)))
                 ((= (car x) 42) (setq bs (cons (cdr x) (cdr bs))))))
         (setq pts (reverse pts) bs (reverse bs)
               fech (= 1 (logand 1 (cdr (assoc 70 ed))))
               elev (cond ((cdr (assoc 38 ed))) (0.0))
               ex (list (logand 128 (cdr (assoc 70 ed))) (cdr (assoc 43 ed)))
               segs (mapcar 'list pts (cdr pts) bs))
         (if fech (setq segs (append segs (list (list (last pts) (car pts) (last bs))))))))
      (setq pr (sc:prepara segs))
      (if (and segs (> (car pr) 1e-9))
        (list idx en tp fech (cdr pr) (car pr) (sc:props ed) elev papel ex)))))

;;; posição s (comprimento) -> (seg . k); dir decide o segmento num vértice
(defun sc:loc-dir (cv s dir / segs sg)
  (setq segs (nth 4 cv))
  (if (> dir 0)
    (while (and (cdr segs) (>= s (- (+ (nth 4 (car segs)) (nth 3 (car segs))) *SC-NO*)))
      (setq segs (cdr segs)))
    (while (and (cdr segs) (> s (+ (nth 4 (car segs)) (nth 3 (car segs)) *SC-NO*)))
      (setq segs (cdr segs))))
  (setq sg (car segs))
  (cons sg (sc:clamp (/ (- s (nth 4 sg)) (nth 3 sg)))))

(defun sc:pt-s (cv s / lc) (setq lc (sc:loc-dir cv s 1)) (sc:seg-pt (car lc) (cdr lc)))
(defun sc:s-de (sg k) (+ (nth 4 sg) (* k (nth 3 sg))))

;;; ------------------------------------------------------------------
;;; Interseções analíticas
;;; ------------------------------------------------------------------
(defun sc:em01 (k len / e) (setq e (/ *SC-TOL* len)) (and (>= k (- e)) (<= k (+ 1.0 e))))

;;; reta p + k d com círculo (c r) -> lista de k
(defun sc:lin-circ (p d c r / dd k0 h m)
  (setq dd (sc:dot d d)
        k0 (/ (sc:dot (sc:v- c p) d) dd)
        h  (distance (sc:v+ p (sc:vk d k0)) c))
  (cond ((> h (+ r *SC-TOL*)) nil)
        ((> h (- r *SC-TOL*)) (list k0))
        (T (setq m (/ (sqrt (- (* r r) (* h h))) (sqrt dd)))
           (list (- k0 m) (+ k0 m)))))

(defun sc:circ-circ (c1 r1 c2 r2 / d a h u m n)
  (setq d (distance c1 c2))
  (cond ((< d 1e-12) nil)
        ((> d (+ r1 r2 *SC-TOL*)) nil)
        ((< d (- (abs (- r1 r2)) *SC-TOL*)) nil)
        (T (setq a (/ (+ (* d d) (* r1 r1) (- (* r2 r2))) (* 2.0 d))
                 h (sqrt (max 0.0 (- (* r1 r1) (* a a))))
                 u (sc:unit (sc:v- c2 c1))
                 m (sc:v+ c1 (sc:vk u a))
                 n (sc:vk (sc:esq u) h))
           (if (< h *SC-TOL*) (list m) (list (sc:v+ m n) (sc:v- m n))))))

;;; parâmetro de q sobre o arco (k em [0,1]) ou nil
(defun sc:k-arco (arc q / th d e)
  (setq th (cadddr arc)
        d  (angle (car arc) q)
        d  (if (> th 0.0) (sc:norm2pi (- d (caddr arc))) (sc:norm2pi (- (caddr arc) d)))
        e  (/ *SC-TOL* (cadr arc)))
  (cond ((<= d (+ (abs th) e)) (min 1.0 (/ d (abs th))))
        ((>= d (- (+ pi pi) e)) 0.0)))

(defun sc:int-ll (a b / p r q s den tt uu)
  (setq p (car a) r (sc:v- (cadr a) p) q (car b) s (sc:v- (cadr b) q) den (sc:cross r s))
  (if (> (abs den) (* 1e-12 (nth 3 a) (nth 3 b)))
    (progn
      (setq tt (/ (sc:cross (sc:v- q p) s) den)
            uu (/ (sc:cross (sc:v- q p) r) den))
      (if (and (sc:em01 tt (nth 3 a)) (sc:em01 uu (nth 3 b)))
        (list (list (sc:clamp tt) (sc:clamp uu)))))))

(defun sc:int-la (l a / arc d res kb)
  (setq arc (nth 5 a) d (sc:v- (cadr l) (car l)))
  (foreach k (sc:lin-circ (car l) d (car arc) (cadr arc))
    (if (and (sc:em01 k (nth 3 l)) (setq kb (sc:k-arco arc (sc:v+ (car l) (sc:vk d k)))))
      (setq res (cons (list (sc:clamp k) kb) res))))
  res)

;;; -> lista de (ka kb)
(defun sc:int-seg (a b / aa ab res ka kb)
  (setq aa (nth 5 a) ab (nth 5 b))
  (cond
    ((and (null aa) (null ab)) (sc:int-ll a b))
    ((and aa ab)
     (foreach q (sc:circ-circ (car aa) (cadr aa) (car ab) (cadr ab))
       (if (and (setq ka (sc:k-arco aa q)) (setq kb (sc:k-arco ab q)))
         (setq res (cons (list ka kb) res))))
     res)
    (aa (mapcar 'reverse (sc:int-la b a)))
    (T (sc:int-la a b))))

(defun sc:bbox (sg / arc p q e)
  (setq e *SC-TOL*)
  (if (setq arc (nth 5 sg))
    (list (- (car (car arc)) (cadr arc) e) (+ (car (car arc)) (cadr arc) e)
          (- (cadr (car arc)) (cadr arc) e) (+ (cadr (car arc)) (cadr arc) e))
    (progn (setq p (car sg) q (cadr sg))
      (list (- (min (car p) (car q)) e) (+ (max (car p) (car q)) e)
            (- (min (cadr p) (cadr q)) e) (+ (max (cadr p) (cadr q)) e)))))

;;; merge sort estável pela chave (car x) - vl-sort pode descartar repetidos
(defun sc:merge (a b / r)
  (while (and a b)
    (if (< (car (car b)) (car (car a)))
      (setq r (cons (car b) r) b (cdr b))
      (setq r (cons (car a) r) a (cdr a))))
  (append (reverse r) a b))
(defun sc:msort (l / a b)
  (if (cdr l)
    (progn
      (while l
        (setq a (cons (car l) a) l (cdr l))
        (if l (setq b (cons (car l) b) l (cdr l))))
      (sc:merge (sc:msort a) (sc:msort b)))
    l))

(defun sc:par-ok (ca cb modoP)
  (and (not (eq ca cb)) (or (not modoP) (not (eq (nth 8 ca) (nth 8 cb))))))

;;; varredura: -> lista de (ponto (cvA . sA) (cvB . sB))
(defun sc:intersecoes (cvs modoP / ents act res)
  (foreach cv cvs
    (foreach sg (nth 4 cv)
      (setq ents (cons (append (sc:bbox sg) (list cv sg)) ents))))
  (foreach e (sc:msort ents)
    (setq act (vl-remove-if '(lambda (a) (< (cadr a) (car e))) act))
    (foreach a act
      (if (and (<= (caddr a) (cadddr e)) (<= (caddr e) (cadddr a))
               (sc:par-ok (nth 4 a) (nth 4 e) modoP))
        (foreach kk (sc:int-seg (nth 5 a) (nth 5 e))
          (setq res (cons (list (sc:seg-pt (nth 5 a) (car kk))
                                (cons (nth 4 a) (sc:s-de (nth 5 a) (car kk)))
                                (cons (nth 4 e) (sc:s-de (nth 5 e) (cadr kk))))
                          res)))))
    (setq act (cons e act)))
  res)

;;; ------------------------------------------------------------------
;;; Nós e ramos
;;; ------------------------------------------------------------------
(defun sc:mesmo-s (cv a b)
  (or (< (abs (- a b)) *SC-NO*)
      (and (nth 3 cv) (< (- (nth 5 cv) (abs (- a b))) *SC-NO*))))

;;; -> lista de (ponto hits), hits = ((cv . s) ...) sem repetição
(defun sc:agrupa (ints / nos n hs)
  (foreach it ints
    (if (setq n (vl-some '(lambda (no) (if (< (distance (car no) (car it)) *SC-NO*) no)) nos))
      (setq nos (subst (list (car n) (append (cdr it) (cadr n))) n nos))
      (setq nos (cons (list (car it) (cdr it)) nos))))
  (mapcar
    '(lambda (no / out)
       (foreach h (cadr no)
         (if (not (vl-some '(lambda (o) (and (eq (car o) (car h)) (sc:mesmo-s (car h) (cdr o) (cdr h)))) out))
           (setq out (cons h out))))
       (list (car no) out))
    nos))

;;; ramo = (cv dir u seg k s): sai do nó no sentido dir (+1/-1) da curva
(defun sc:ramo (cv s dir / L lc)
  (setq L (nth 5 cv))
  (if (nth 3 cv)
    (cond ((and (< dir 0) (< s *SC-NO*)) (setq s L))
          ((and (> dir 0) (> s (- L *SC-NO*))) (setq s 0.0))))
  (setq lc (sc:loc-dir cv s dir))
  (list cv dir (sc:vk (sc:seg-tan (car lc) (cdr lc)) dir) (car lc) (cdr lc) s))

;;; ponto dentro de um anel fechado: número de voltas exato com arcos
(defun sc:na-lente (q sg arc / ch)
  (setq ch (sc:v- (cadr sg) (car sg)))
  (and (< (distance q (car arc)) (cadr arc))
       (> (* (sc:cross ch (sc:v- q (car sg))) (sc:cross ch (sc:v- (sc:seg-pt sg 0.5) (car sg)))) 0.0)))

(defun sc:dentro (q cv / w da arc)
  (setq w 0.0)
  (foreach sg (nth 4 cv)
    (setq da (- (angle q (cadr sg)) (angle q (car sg))))
    (while (> da pi) (setq da (- da pi pi)))
    (while (<= da (- pi)) (setq da (+ da pi pi)))
    (if (and (setq arc (nth 5 sg)) (sc:na-lente q sg arc))
      (setq da (+ da (if (> (cadddr arc) 0.0) (+ pi pi) (- (+ pi pi))))))
    (setq w (+ w da)))
  (> (abs w) pi))

(defun sc:ramo-dentro (b aneis R / cv q)
  (setq cv (car b))
  (if (eq (nth 8 cv) 'E)
    (progn
      (setq q (sc:pt-s cv (max 0.0 (min (nth 5 cv) (+ (nth 5 b) (* (nth 1 b) (/ R 100.0)))))))
      (vl-some '(lambda (a) (sc:dentro q a)) aneis))))

(defun sc:ramos (hits aneis R / out cv s)
  (foreach h hits
    (setq cv (car h) s (cdr h))
    (if (or (nth 3 cv) (> s *SC-NO*)) (setq out (cons (sc:ramo cv s -1) out)))
    (if (or (nth 3 cv) (< s (- (nth 5 cv) *SC-NO*))) (setq out (cons (sc:ramo cv s 1) out))))
  (if aneis (setq out (vl-remove-if '(lambda (b) (sc:ramo-dentro b aneis R)) out)))
  out)

;;; ------------------------------------------------------------------
;;; Concordância entre dois ramos (setor anti-horário de bi até bj)
;;; ------------------------------------------------------------------
;;; primitiva do ramo deslocada de R para o lado n: ('L ponto dir) | ('C centro raio)
(defun sc:off (b n R / sg arc)
  (setq sg (nth 3 b) arc (nth 5 sg))
  (if arc
    (list 'C (car arc)
          (if (> (sc:dot (sc:v- (car arc) (sc:seg-pt sg (nth 4 b))) n) 0.0)
            (abs (- (cadr arc) R))
            (+ (cadr arc) R)))
    (list 'L (sc:v+ (car sg) (sc:vk n R)) (sc:unit (sc:v- (cadr sg) (car sg))))))

(defun sc:int-prim (a b / den)
  (cond
    ((and (eq (car a) 'L) (eq (car b) 'L))
     (setq den (sc:cross (caddr a) (caddr b)))
     (if (> (abs den) 1e-12)
       (list (sc:v+ (cadr a) (sc:vk (caddr a) (/ (sc:cross (sc:v- (cadr b) (cadr a)) (caddr b)) den))))))
    ((eq (car a) 'L)
     (mapcar '(lambda (k) (sc:v+ (cadr a) (sc:vk (caddr a) k)))
             (sc:lin-circ (cadr a) (caddr a) (cadr b) (caddr b))))
    ((eq (car b) 'L) (sc:int-prim b a))
    (T (sc:circ-circ (cadr a) (caddr a) (cadr b) (caddr b)))))

;;; ponto de tangência no segmento do ramo, à frente do nó -> (ponto . s) ou nil
(defun sc:toque (b c R / sg arc dd q r p k d)
  (setq sg (nth 3 b) arc (nth 5 sg))
  (if arc
    (setq dd (distance c (car arc)) q (sc:unit (sc:v- c (car arc))) r (cadr arc)
          p  (if (and (< r R) (< (abs (- dd (- R r))) (abs (- dd (+ R r)))))
               (sc:v- (car arc) (sc:vk q r))
               (sc:v+ (car arc) (sc:vk q r)))
          k  (sc:k-arco arc p))
    (progn
      (setq d (sc:v- (cadr sg) (car sg))
            k (/ (sc:dot (sc:v- c (car sg)) d) (sc:dot d d))
            p (sc:v+ (car sg) (sc:vk d k)))
      (if (not (sc:em01 k (nth 3 sg))) (setq k nil))))
  (if (and k (> (* (nth 1 b) (- k (nth 4 b))) (/ *SC-NO* (nth 3 sg))))
    (cons p (sc:s-de sg (sc:clamp k)))))

;;; -> (centro (Ti . si) (Tj . sj)) ou nil
(defun sc:filete (X bi bj R / ofi ofj ti tj d bd best)
  (setq ofi (sc:off bi (sc:esq (nth 2 bi)) R)
        ofj (sc:off bj (sc:vk (sc:esq (nth 2 bj)) -1.0) R))
  (foreach c (sc:int-prim ofi ofj)
    (if (and (setq ti (sc:toque bi c R)) (setq tj (sc:toque bj c R))
             (setq d (distance c X)) (or (null bd) (< d bd)))
      (setq bd d best (list c ti tj))))
  best)

(defun sc:faz-arco (X f R cv / c a1 a2 sw tmp)
  (setq c (car f) a1 (angle c (car (cadr f))) a2 (angle c (car (caddr f)))
        sw (sc:norm2pi (- a2 a1)))
  ;; o arco de concordância é o que passa do lado do nó
  (if (> (distance (polar c (+ a1 (/ sw 2.0)) R) X) (distance (polar c (+ a1 (/ sw 2.0) pi) R) X))
    (setq tmp a1 a1 a2 a2 tmp))
  (entmake (append '((0 . "ARC")) (nth 6 cv)
                   (list (list 10 (car c) (cadr c) (nth 7 cv)) (cons 40 R) (cons 50 a1) (cons 51 a2)))))

;;; ------------------------------------------------------------------
;;; Quebra: reconstrói a curva em trechos herdando as propriedades
;;; ------------------------------------------------------------------
(defun sc:sub (cv a b / res s0 s1 ka kb fim)
  (foreach sg (nth 4 cv)
    (setq s0 (nth 4 sg) s1 (+ s0 (nth 3 sg)))
    (if (and (< a (- s1 1e-9)) (> b (+ s0 1e-9)))
      (setq ka  (/ (- (max a s0) s0) (nth 3 sg))
            kb  (/ (- (min b s1) s0) (nth 3 sg))
            res (cons (list (sc:seg-pt sg ka)
                            (if (nth 5 sg) (sc:tan4 (* (cadddr (nth 5 sg)) (- kb ka))) 0.0))
                      res)
            fim (sc:seg-pt sg kb))))
  (reverse (cons (list fim 0.0) res)))

(defun sc:emite (cv vs / tp z c)
  (setq tp (nth 2 cv) z (nth 7 cv))
  (cond
    ((and (= tp "LINE") (= (length vs) 2))
     (entmake (append '((0 . "LINE")) (nth 6 cv)
                      (list (list 10 (car (caar vs)) (cadr (caar vs)) z)
                            (list 11 (car (car (cadr vs))) (cadr (car (cadr vs))) z)))))
    ((member tp '("ARC" "CIRCLE"))
     (setq c (car (nth 9 cv)))
     (entmake (append '((0 . "ARC")) (nth 6 cv)
                      (list (list 10 (car c) (cadr c) z) (cons 40 (cadr (nth 9 cv)))
                            (cons 50 (angle c (car (car vs))))
                            (cons 51 (angle c (car (last vs))))))))
    (T
     (entmake (append '((0 . "LWPOLYLINE") (100 . "AcDbEntity")) (nth 6 cv)
                      (list '(100 . "AcDbPolyline") (cons 90 (length vs))
                            (cons 70 (if (= tp "LWPOLYLINE") (car (nth 9 cv)) 0)) (cons 38 z))
                      (if (and (= tp "LWPOLYLINE") (cadr (nth 9 cv))) (list (cons 43 (cadr (nth 9 cv)))))
                      (apply 'append (mapcar '(lambda (v) (list (cons 10 (car v)) (cons 42 (cadr v)))) vs)))))))

(defun sc:uniq-s (l / out)
  (foreach s l (if (or (null out) (> (- s (car out)) *SC-NO*)) (setq out (cons s out))))
  (reverse out))

;;; ss: posições de quebra; aneis: descarta trechos de eixo dentro deles
(defun sc:quebra (cv ss aneis / L fech iv n a b m)
  (setq L (nth 5 cv) fech (nth 3 cv))
  (if fech (setq ss (mapcar '(lambda (s) (if (> s (- L *SC-NO*)) 0.0 s)) ss)))
  (setq ss (sc:uniq-s (vl-sort ss '<)))
  (if (not fech)
    (setq ss (vl-remove-if '(lambda (s) (or (< s *SC-NO*) (> s (- L *SC-NO*)))) ss)))
  ;; círculo com uma só quebra: dois trechos (um ARC não fecha 360 graus)
  (if (and (= (nth 2 cv) "CIRCLE") ss (null (cdr ss)))
    (setq ss (vl-sort (list (car ss) (rem (+ (car ss) (/ L 2.0)) L)) '<)))
  (setq n 0)
  (if ss
    (progn
      (setq iv (if fech
                 (mapcar 'list ss (append (cdr ss) (list (+ (car ss) L))))
                 (mapcar 'list (cons 0.0 ss) (append ss (list L)))))
      (foreach i iv
        (setq a (car i) b (cadr i) m (/ (+ a b) 2.0))
        (if (> m L) (setq m (- m L)))
        (if (not (and aneis (eq (nth 8 cv) 'E)
                      (vl-some '(lambda (r) (sc:dentro (sc:pt-s cv m) r)) aneis)))
          (progn
            (sc:emite cv (if (> b (+ L 1e-9))
                           (append (sc:butlast (sc:sub cv a L)) (sc:sub cv 0.0 (- b L)))
                           (sc:sub cv a b)))
            (setq n (1+ n)))))
      (entdel (nth 1 cv))))
  n)

(defun sc:add-brk (brks cv s / e)
  (if (setq e (assoc (car cv) brks))
    (subst (append e (list s)) e brks)
    (cons (list (car cv) s) brks)))

;;; ------------------------------------------------------------------
;;; Motor: interseções -> nós -> concordâncias -> quebras
;;; -> (nós arcos trechos avisos)
;;; ------------------------------------------------------------------
(defun sc:processa (cvs modoP qtan R aneis / nos brks narc nav rs ang ord bi bj phi f e npc n)
  (setq nos (sc:agrupa (sc:intersecoes cvs modoP)) narc 0 nav 0 npc 0)
  (foreach no nos
    (foreach h (cadr no) (setq brks (sc:add-brk brks (car h) (cdr h))))
    (setq rs (sc:ramos (cadr no) aneis R))
    (if (cdr rs)
      (progn
        (setq ang (mapcar '(lambda (b) (sc:norm2pi (sc:ang (nth 2 b)))) rs)
              ord (mapcar '(lambda (i) (nth i rs)) (vl-sort-i ang '<))
              n   (length ord))
        (setq e 0)
        (repeat n
          (setq bi (nth e ord) bj (nth (rem (1+ e) n) ord)
                phi (sc:norm2pi (- (sc:ang (nth 2 bj)) (sc:ang (nth 2 bi)))))
          ;; só entre curvas diferentes e em quadrantes de giro (< 180 graus)
          (if (and (not (eq (car bi) (car bj))) (> phi 1e-3) (< phi (- pi 1e-3)))
            (if (setq f (sc:filete (car no) bi bj R))
              (progn
                (sc:faz-arco (car no) f R (car bi))
                (setq narc (1+ narc))
                (if qtan
                  (setq brks (sc:add-brk brks (car bi) (cdr (cadr f)))
                        brks (sc:add-brk brks (car bj) (cdr (caddr f))))))
              (setq nav (1+ nav))))
          (setq e (1+ e))))))
  (foreach cv cvs
    (if (setq e (assoc (car cv) brks))
      (setq npc (+ npc (sc:quebra cv (cdr e) aneis)))))
  (list (length nos) narc npc nav))

;;; ------------------------------------------------------------------
;;; Anel da praça: ilha deslocada para fora (cantos arredondados)
;;; ------------------------------------------------------------------
(defun sc:anel (en af eixo / o r1 r2 a1 a2 res src)
  (setq o (vlax-ename->vla-object en)
        r1 (vl-catch-all-apply 'vlax-invoke (list o 'Offset af))
        r2 (vl-catch-all-apply 'vlax-invoke (list o 'Offset (- af))))
  (setq r1 (if (vl-catch-all-error-p r1) nil (car r1))
        r2 (if (vl-catch-all-error-p r2) nil (car r2)))
  (setq a1 (if r1 (vla-get-Area r1) -1.0) a2 (if r2 (vla-get-Area r2) -1.0))
  (if (> a1 a2) (setq res r1) (setq res r2 r2 r1))
  (if r2 (vla-Delete r2))
  (if res
    (progn
      (setq src (vlax-ename->vla-object eixo))
      (vla-put-Layer res (vla-get-Layer src))
      (vla-put-TrueColor res (vla-get-TrueColor src))
      (vla-put-Linetype res (vla-get-Linetype src))
      (vla-put-LinetypeScale res (vla-get-LinetypeScale src))
      (vla-put-Lineweight res (vla-get-Lineweight src))
      (vlax-vla-object->ename res))))

;;; ------------------------------------------------------------------
;;; Comando
;;; ------------------------------------------------------------------
(defun c:SIS_CONCORDAR (/ *error* doc sv modo r af kw ss so cvs aneis obs en cv i t0 res nlid)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        sv  (mapcar '(lambda (v) (cons v (getvar v))) '("OSMODE" "CMDECHO" "OFFSETGAPTYPE")))
  (defun *error* (m)
    (foreach p sv (vl-catch-all-apply 'setvar (list (car p) (cdr p))))
    (vla-EndUndoMark doc)
    (if (and m (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*BREAK*")))
      (princ (strcat "\nSIS_CONCORDAR: " m)))
    (princ))
  (vla-StartUndoMark doc)
  (setvar "CMDECHO" 0)

  ;; --- entradas ---
  (initget "Cruzamentos Praca")
  (setq modo (cond ((getkword (strcat "\nConcordar [Cruzamentos/Praca] <" *SC-MODO* ">: "))) (*SC-MODO*)))
  (initget 6)
  (setq r (cond ((getdist (strcat "\nRaio de concordância <" (rtos *SC-RAIO* 2 3) ">: "))) (*SC-RAIO*)))
  (setq *SC-MODO* modo *SC-RAIO* r)
  (if (= modo "Praca")
    (progn
      (initget 4)
      (setq af (cond ((getdist (strcat "\nAfastamento do anel à ilha (0 = a própria ilha é o eixo) <"
                                       (rtos *SC-AFAST* 2 3) ">: ")))
                     (*SC-AFAST*))
            *SC-AFAST* af))
    (progn
      (initget "Sim Nao")
      (setq kw (cond ((getkword (strcat "\nQuebrar também nas tangências? [Sim/Nao] <" *SC-QTAN* ">: ")))
                     (*SC-QTAN*))
            *SC-QTAN* kw)))
  (sc:grava-env)
  (setvar "OSMODE" 0)

  ;; --- seleção ---
  (if (= modo "Praca")
    (progn
      (princ "\nSelecione as ilhas/praças (círculos ou polilinhas fechadas): ")
      (setq so (ssget '((-4 . "<OR") (0 . "CIRCLE")
                        (-4 . "<AND") (0 . "LWPOLYLINE") (-4 . "&") (70 . 1) (-4 . "AND>")
                        (-4 . "OR>"))))))
  (if (or (/= modo "Praca") so)
    (progn
      (princ "\nSelecione os eixos das estradas: ")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE"))))))

  (if ss
    (progn
      (setq t0 (getvar "MILLISECS") i 0 nlid 0)
      (if so
        (repeat (sslength so) (setq obs (cons (ssname so i) obs) i (1+ i))))
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) i (1+ i))
        (if (not (member en obs))
          (if (setq cv (sc:le en (length cvs) 'E)) (setq cvs (cons cv cvs)) (setq nlid (1+ nlid)))))
      (if (and (= modo "Praca") cvs)
        (progn
          (setvar "OFFSETGAPTYPE" 1)
          (foreach o obs
            (if (setq en (if (> af 0.0) (sc:anel o af (nth 1 (car cvs))) o))
              (if (setq cv (sc:le en (+ (length cvs) (length aneis)) 'P))
                (setq aneis (cons cv aneis))
                (setq nlid (1+ nlid)))))))
      (cond
        ((null cvs) (princ "\nNenhum eixo válido."))
        ((and (= modo "Praca") (null aneis)) (princ "\nNenhuma ilha válida."))
        (T
         (setq res (if (= modo "Praca")
                     (sc:processa (append cvs aneis) T T r aneis)
                     (sc:processa cvs nil (= *SC-QTAN* "Sim") r nil)))
         (princ (strcat "\nSIS_CONCORDAR: " (itoa (car res)) " nó(s), "
                        (itoa (cadr res)) " arco(s) de concordância, "
                        (itoa (caddr res)) " trecho(s) após a quebra"
                        (if (> (cadddr res) 0)
                          (strcat ", " (itoa (cadddr res)) " quadrante(s) sem concordância (raio maior que o segmento)")
                          "")
                        (if (> nlid 0) (strcat ", " (itoa nlid) " entidade(s) ignorada(s) (normal fora de Z)") "")
                        (strcat " - " (itoa (- (getvar "MILLISECS") t0)) " ms."))))))
    (princ "\nNada selecionado."))
  (*error* nil))

(princ "\nSIS_CONCORDAR carregado.")
(princ)
