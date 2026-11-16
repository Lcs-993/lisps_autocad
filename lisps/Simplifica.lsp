;;; ==========================================================================
;;; Simplifica.lsp - Simplificar polilinhas e segmentar arcos
;;; --------------------------------------------------------------------------
;;; SIMPLIFICAPL  (equivalente ao SMP/GOSMP do AgroCAD - "Reduzir pontos sem
;;;               perda de qualidade"): remove vértices de polilinhas sem que a
;;;               curva se afaste mais que a Tolerância de Desvio [A].
;;;   Algoritmo: Douglas-Peucker com distância ponto-SEGMENTO (não reta
;;;   infinita): todo vértice removido fica a <= A do novo segmento.
;;;   - pontas das abertas e vértices vizinhos de ARCOS ficam fixos: os arcos
;;;     são preservados exatamente (use SEGMENTARCOS antes para simplificá-los);
;;;   - fechadas só de retas: fixa o vértice 0 e o mais distante dele;
;;;   - A = 0 remove só vértices repetidos e colineares;
;;;   - LWPOLYLINE (entmod, mantém o handle), POLYLINE 2D e 3D (3D: desvio
;;;     medido em 3D); curvas fit/spline e malhas são ignoradas.
;;;   Implementação iterativa (pilha de trechos = ponteiro + contagem, sem
;;;   recursão e sem copiar listas): aguenta polilinhas de centenas de
;;;   milhares de vértices.
;;;
;;; SEGMENTARCOS  (equivalente ao AR2RE/ARC2SEG - "Converter arcos de
;;;               polilinhas em segmentos"): cada arco (bulge) vira segmentos
;;;               de reta com vértices SOBRE o arco.
;;;   - Desvio Máximo (flecha): menor número de cordas iguais com flecha
;;;     r(1 - cos(theta/2n)) <= flecha;
;;;   - Usar Medida Fixa em Metros: cordas iguais com comprimento de arco
;;;     <= medida;
;;;   - opcional: ARC e CIRCLE avulsos viram LWPOLYLINE (mesmas propriedades,
;;;     mesmo plano/elevação);
;;;   - larguras por vértice são interpoladas ao longo do arco.
;;;
;;; API (para outras rotinas, ex.: DESVIAOBS):
;;;   (sp:dp recs tol)                 -> (recs-mantidos . maior-desvio)
;;;   (sp:simplifica-recs recs fech A) -> (recs . maior-desvio)
;;;   (sp:segmenta-recs recs fech modo val) -> (recs . n-arcos)
;;;   (sp:arco-geo p0 p1 bulge)        -> (centro raio ang0 theta)
;;;   (sp:n-arco raio theta modo val)  -> número de cordas
;;;   recs = ((ponto largura-ini largura-fim bulge) ...); modo 'FLECHA/'MEDIDA
;;;
;;; PADRONIZAVERT (equivalente ao HME do AgroCAD - "Padronizar espaçamentos
;;;               entre vértices"): refaz os vértices ao longo da polilinha a
;;;               cada Espaçamento (medido sobre a curva, arcos inclusive).
;;;   - cada trecho é dividido em partes iguais com o tamanho mais próximo do
;;;     espaçamento (sem sobra curta no fim);
;;;   - Preservar cantos: vértices onde a direção muda mais que o Ângulo de
;;;     Canto ficam fixos e os trechos entre eles são divididos à parte
;;;     (sem isso os cantos dos talhões seriam "cortados");
;;;   - o resultado só tem segmentos retos (arcos viram cordas sobre o arco).
;;;
;;; Comandos: SIMPLIFICAPL, SEGMENTARCOS, PADRONIZAVERT
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Parâmetros (persistem via setenv)
;;; --------------------------------------------------------------------------
(setq *SP-CHAVES* '(*SP-TOL* *SP-MANTER*)
      *SA-CHAVES* '(*SA-FIXA* *SA-FLECHA* *SA-MEDIDA* *SA-AVULSOS* *SA-MANTER*)
      *HM-CHAVES* '(*HM-ESP* *HM-CANTOS* *HM-ANG* *HM-MANTER*))

(defun sp:le-env (nome chaves padrao teste / v)
  (mapcar 'set chaves padrao)
  (if (and (setq v (getenv nome))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= (length v) (length chaves))
           (apply teste (list v)))
    (mapcar 'set chaves v))
)
(defun sp:grava-env (nome chaves) (setenv nome (vl-prin1-to-string (mapcar 'eval chaves))))

(if (not *SP-TOL*)
  (sp:le-env "LISPS_SIMPLIFICA" *SP-CHAVES* '(0.05 nil) '(lambda (v) (numberp (car v)))))
(if (not *SA-FLECHA*)
  (sp:le-env "LISPS_SEGARCOS" *SA-CHAVES* '(nil 0.05 5.0 nil nil)
             '(lambda (v) (and (numberp (cadr v)) (numberp (caddr v))))))
(if (not *HM-ESP*)
  (sp:le-env "LISPS_PADRONIZAVERT" *HM-CHAVES* '(5.0 T 30.0 nil)
             '(lambda (v) (and (numberp (car v)) (> (car v) 0) (numberp (caddr v))))))

;;; --------------------------------------------------------------------------
;;; Geometria básica
;;; --------------------------------------------------------------------------
(defun sp:2d (p) (list (car p) (cadr p)))
(defun sp:z (p) (if (caddr p) (caddr p) 0.0))
(defun sp:arco-p (b) (and b (> (abs b) 1e-12)))
(defun sp:butlast (l) (reverse (cdr (reverse l))))
(defun sp:acos (x) (atan (sqrt (max 0.0 (- 1.0 (* x x)))) x))
;;; teto de x > 0 (com folga numérica), no mínimo 1
(defun sp:ceil (x / f)
  (setq f (fix x))
  (max 1 (if (> x (+ f 1e-9)) (1+ f) f))
)
(defun sp:num (k ed / x) (if (setq x (cdr (assoc k ed))) x 0.0))

;;; distância do ponto p ao SEGMENTO a-b (3D; pontos 2D têm z = 0)
(defun sp:dseg (p a b / ux uy uz vx vy vz l2 k)
  (setq ux (- (car b) (car a)) uy (- (cadr b) (cadr a)) uz (- (sp:z b) (sp:z a))
        vx (- (car p) (car a)) vy (- (cadr p) (cadr a)) vz (- (sp:z p) (sp:z a))
        l2 (+ (* ux ux) (* uy uy) (* uz uz)))
  (if (> l2 1e-24)
    (setq k  (max 0.0 (min 1.0 (/ (+ (* ux vx) (* uy vy) (* uz vz)) l2)))
          vx (- vx (* k ux)) vy (- vy (* k uy)) vz (- vz (* k uz))))
  (sqrt (+ (* vx vx) (* vy vy) (* vz vz)))
)

;;; --------------------------------------------------------------------------
;;; Douglas-Peucker iterativo
;;;   cada trecho pendente = (início n último): início é um PONTEIRO para a
;;;   lista original (sem cópia), n o número de registros, último o registro
;;;   final. Trechos saem da pilha da esquerda para a direita, então os
;;;   vértices mantidos já saem em ordem.
;;;   recs: registros cujo car é o ponto -> (mantidos . maior-desvio-removido)
;;; --------------------------------------------------------------------------
(defun sp:dp (recs tol / lim pilha tr ini n fim a b r i d dmax cauda imax out dout)
  (setq lim   (+ tol 1e-9)
        dout  0.0
        pilha (list (list recs (length recs) (last recs))))
  (while pilha
    (setq tr (car pilha) pilha (cdr pilha)
          ini (car tr) n (cadr tr) fim (caddr tr))
    (if (<= n 2)
      (setq out (cons (car ini) out))
      (progn
        (setq a (car (car ini)) b (car fim) r (cdr ini) i 1 dmax -1.0)
        (while (< i (1- n))
          (if (> (setq d (sp:dseg (car (car r)) a b)) dmax)
            (setq dmax d cauda r imax i))
          (setq r (cdr r) i (1+ i)))
        (if (> dmax lim)
          ;; divide no vértice mais distante: [0..imax] e [imax..n-1]
          (setq pilha (cons (list ini (1+ imax) (car cauda))
                            (cons (list cauda (- n imax) fim) pilha)))
          (setq out  (cons (car ini) out)
                dout (max dout dmax))))))
  (cons (reverse (cons (last recs) out)) dout)
)

;;; gira a lista para começar no índice k
(defun sp:gira (l k / cab)
  (repeat k (setq cab (cons (car l) cab) l (cdr l)))
  (append l (reverse cab))
)

;;; --------------------------------------------------------------------------
;;; Simplificação de uma polilinha (registros)
;;;   -> (novos-recs . maior-desvio); vértices fixos: pontas (aberta) e
;;;   vizinhos de arcos; cada trecho de RETAS entre dois fixos passa pelo DP.
;;; --------------------------------------------------------------------------
(defun sp:simplifica-recs (recs fech tol / n bs ant i k dmx p0 fix pares run r1 res dout)
  (setq n  (length recs)
        bs (mapcar 'cadddr recs)
        ;; bulge do segmento que CHEGA em cada vértice
        ant (if fech (cons (last bs) (sp:butlast bs)) (cons 0.0 (sp:butlast bs))))
  ;; numa aberta o bulge do último vértice não descreve segmento
  (if (not fech) (setq bs (append (sp:butlast bs) '(0.0))))
  (setq i -1
        fix (mapcar '(lambda (b a)
                       (setq i (1+ i))
                       (or (sp:arco-p b) (sp:arco-p a)
                           (and (not fech) (or (= i 0) (= i (1- n))))))
                    bs ant))
  (if (not (member T fix))
    ;; anel só de retas: fixa o vértice 0 e o mais distante dele
    (progn
      (setq k 0 i 0 dmx -1.0 p0 (car (car recs)))
      (foreach r recs
        (if (> (distance (car r) p0) dmx) (setq dmx (distance (car r) p0) k i))
        (setq i (1+ i)))
      (setq i -1 fix (mapcar '(lambda (f) (setq i (1+ i)) (or (= i 0) (= i k))) fix))))
  (setq pares (mapcar 'cons fix recs))                    ; (fixo . rec)
  (if fech
    ;; começa num vértice fixo e repete-o no fim (fecha o anel)
    (progn
      (setq k 0 r1 pares)
      (while (not (car (car r1))) (setq k (1+ k) r1 (cdr r1)))
      (setq pares (sp:gira pares k)
            pares (append pares (list (car pares))))))
  (setq run  (list (cdr (car pares)))
        pares (cdr pares)
        dout 0.0)
  (foreach p pares
    (setq run (cons (cdr p) run))
    (if (car p)
      (setq r1   (sp:dp (reverse run) tol)
            res  (append (cdr (reverse (car r1))) res)   ; sem o fixo final
            dout (max dout (cdr r1))
            run  (list (cdr p)))))
  (setq res (reverse res))
  (if (not fech) (setq res (append res run)))             ; último vértice
  (if (and fech (< (length res) 3) (not (vl-some 'sp:arco-p (mapcar 'cadddr res))))
    (cons recs 0.0)                                       ; não degenera o anel
    (cons res dout))
)

;;; --------------------------------------------------------------------------
;;; Arcos -> segmentos
;;; --------------------------------------------------------------------------
;;; arco p0->p1 de bulge b -> (centro raio ang0 theta); theta > 0 = anti-horário
(defun sp:arco-geo (p0 p1 b / c ux uy h cen)
  (setq c  (distance (sp:2d p0) (sp:2d p1))
        ux (/ (- (car p1) (car p0)) c)
        uy (/ (- (cadr p1) (cadr p0)) c)
        ;; centro: no meio da corda, deslocado pela normal esquerda
        h  (/ (* c (- 1.0 (* b b))) (* 4.0 b))
        cen (list (- (/ (+ (car p0) (car p1)) 2.0) (* h uy))
                  (+ (/ (+ (cadr p0) (cadr p1)) 2.0) (* h ux))))
  (list cen
        (/ (* c (+ 1.0 (* b b))) (* 4.0 (abs b)))
        (atan (- (cadr p0) (cadr cen)) (- (car p0) (car cen)))
        (* 4.0 (atan b)))
)

;;; número de cordas iguais para o arco de raio r e ângulo th
;;;   'FLECHA: r(1 - cos(th/2n)) <= val ; 'MEDIDA: r.th/n <= val
(defun sp:n-arco (r th modo val / x)
  (setq th (abs th)
        x  (if (eq modo 'MEDIDA)
             (/ (* r th) val)
             (if (>= val (* 2.0 r)) 0.0 (/ th (* 2.0 (sp:acos (- 1.0 (/ val r))))))))
  (sp:ceil (min x 10000.0))
)

;;; ponto do arco geo no ângulo a0 + th.k/n, com o z de pz (se houver)
(defun sp:ponto-arco (geo k n pz / a q)
  (setq a (+ (caddr geo) (/ (* (cadddr geo) k) n))
        q (list (+ (car (car geo)) (* (cadr geo) (cos a)))
                (+ (cadr (car geo)) (* (cadr geo) (sin a)))))
  (if (caddr pz) (append q (list (caddr pz))) q)
)

;;; -> (novos-recs . n-arcos) ; cada arco vira n registros retos (sem p1)
(defun sp:segmenta-recs (recs fech modo val / prox res na geo m k sw dw)
  (setq prox (append (mapcar 'car (cdr recs)) (list (if fech (car (car recs)))))
        na   0)
  (mapcar
    '(lambda (r q)
       (if (and q (sp:arco-p (cadddr r))
                (> (distance (sp:2d (car r)) (sp:2d q)) 1e-9))
         (progn
           (setq geo (sp:arco-geo (car r) q (cadddr r))
                 m   (sp:n-arco (cadr geo) (cadddr geo) modo val)
                 sw  (cadr r)
                 dw  (/ (- (caddr r) (cadr r)) m)
                 na  (1+ na)
                 k   0)
           (while (< k m)
             (setq res (cons (list (if (= k 0) (car r) (sp:ponto-arco geo k m (car r)))
                                   (+ sw (* dw k)) (+ sw (* dw (1+ k))) 0.0)
                             res)
                   k   (1+ k))))
         (setq res (cons r res))))
    recs prox)
  (cons (reverse res) na)
)

;;; ARC / CIRCLE avulso -> LWPOLYLINE (mesmo plano, mesmas propriedades)
(defun sp:arco-ent (e modo val manter / ed circ cen r a0 th n k pts ok)
  (setq ed   (entget e)
        circ (= "CIRCLE" (cdr (assoc 0 ed)))
        cen  (cdr (assoc 10 ed))
        r    (cdr (assoc 40 ed)))
  (if circ
    (setq a0 0.0 th (* 2.0 pi))
    (setq a0 (cdr (assoc 50 ed))
          th (rem (- (cdr (assoc 51 ed)) a0) (* 2.0 pi))
          th (if (<= th 1e-12) (+ th (* 2.0 pi)) th)))
  (setq n (sp:n-arco r th modo val))
  (if circ (setq n (max n 3)))
  (setq k 0)
  (while (<= k (if circ (1- n) n))
    (setq pts (cons (list (+ (car cen) (* r (cos (+ a0 (/ (* th k) n)))))
                          (+ (cadr cen) (* r (sin (+ a0 (/ (* th k) n))))))
                    pts)
          k   (1+ k)))
  (setq ok (entmake
             (append
               (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity"))
               (vl-remove-if-not '(lambda (g) (member (car g) '(6 8 39 48 62 67 370 410 420 430 440))) ed)
               (list '(100 . "AcDbPolyline") (cons 90 (length pts)) (cons 70 (if circ 1 0))
                     (cons 38 (sp:z cen)))
               (mapcar '(lambda (p) (cons 10 p)) (reverse pts))
               (list (cond ((assoc 210 ed)) ('(210 0.0 0.0 1.0)))))))
  (if (and ok (not manter)) (entdel e))
  (if ok (length pts))
)

;;; --------------------------------------------------------------------------
;;; Leitura / gravação de polilinhas
;;; --------------------------------------------------------------------------
;;; LWPOLYLINE -> (cabeçalho recs cauda)
(defun sp:lw-le (ed / cab recs cau p sw ew b est)
  (foreach g ed
    (cond
      ((= (car g) 10)
       (if p (setq recs (cons (list p sw ew b) recs)))
       (setq p (cdr g) sw 0.0 ew 0.0 b 0.0 est T))
      ((and est (= (car g) 40)) (setq sw (cdr g)))
      ((and est (= (car g) 41)) (setq ew (cdr g)))
      ((and est (= (car g) 42)) (setq b (cdr g)))
      ((and est (= (car g) 91)))
      (est (setq cau (cons g cau)))
      (T   (setq cab (cons g cab)))))
  (if p (setq recs (cons (list p sw ew b) recs)))
  (list (reverse cab) (reverse recs) (reverse cau))
)

(defun sp:lw-grava (cab recs cau / nova)
  (setq nova (append (subst (cons 90 (length recs)) (assoc 90 cab) cab)
                     (apply 'append
                            (mapcar '(lambda (r) (list (cons 10 (sp:2d (car r))) (cons 40 (cadr r))
                                                       (cons 41 (caddr r)) (cons 42 (cadddr r))))
                                    recs))
                     cau))
  (if (entmod nova) (progn (entupd (cdr (assoc -1 nova))) T))
)

;;; POLYLINE (2D/3D) -> recs ; vértices de controle de spline são ignorados
(defun sp:pl-le (e / v vd recs)
  (setq v (entnext e))
  (while (and v (= "VERTEX" (cdr (assoc 0 (setq vd (entget v))))))
    (if (zerop (logand 16 (cdr (assoc 70 vd))))
      (setq recs (cons (list (cdr (assoc 10 vd)) (sp:num 40 vd) (sp:num 41 vd) (sp:num 42 vd)) recs)))
    (setq v (entnext v)))
  (reverse recs)
)

;;; recria a POLYLINE com os novos vértices (mesmo cabeçalho, xdata incluído)
(defun sp:pl-grava (e recs manter / ed lay v3 ok)
  (setq ed  (entget e '("*"))
        lay (assoc 8 ed)
        v3  (= 8 (logand 8 (cdr (assoc 70 ed))))
        ok  (entmake (vl-remove-if '(lambda (g) (member (car g) '(-1 5 102 330 360))) ed)))
  (foreach r recs
    (if ok
      (setq ok (entmake
                 (if v3
                   (list '(0 . "VERTEX") '(100 . "AcDbEntity") lay '(100 . "AcDbVertex")
                         '(100 . "AcDb3dPolylineVertex") (cons 10 (car r)) '(70 . 32))
                   (list '(0 . "VERTEX") '(100 . "AcDbEntity") lay '(100 . "AcDbVertex")
                         '(100 . "AcDb2dVertex") (cons 10 (car r)) (cons 40 (cadr r))
                         (cons 41 (caddr r)) (cons 42 (cadddr r)) '(70 . 0)))))))
  (if ok (setq ok (entmake (list '(0 . "SEQEND") '(100 . "AcDbEntity") lay))))
  (if (and ok (not manter)) (entdel e))
  ok
)

;;; aplica f (recs fech) -> (novos . info) ou nil (sem mudança) à polilinha e
;;; -> (vértices-antes vértices-depois info) ; nil se não mudou
(defun sp:aplica (e f manter / ed lw dados recs fech r e2 ok)
  (setq ed   (entget e)
        lw   (= "LWPOLYLINE" (cdr (assoc 0 ed)))
        fech (= 1 (logand 1 (cdr (assoc 70 ed))))
        recs (if lw (cadr (sp:lw-le ed)) (sp:pl-le e)))
  (if (and recs (setq r (apply f (list recs fech))))
    (progn
      (setq ok (if lw
                 (progn
                   (setq e2    (if manter (vlax-vla-object->ename (vla-Copy (vlax-ename->vla-object e))) e)
                         dados (sp:lw-le (entget e2)))
                   (sp:lw-grava (car dados) (car r) (caddr dados)))
                 (sp:pl-grava e (car r) manter)))
      (if ok (list (length recs) (length (car r)) (cdr r)))))
)

(setq *SP-FILTRO-PL*
  '((-4 . "<OR") (0 . "LWPOLYLINE")
    (-4 . "<AND") (0 . "POLYLINE") (-4 . "<NOT") (-4 . "&") (70 . 86) (-4 . "NOT>") (-4 . "AND>")
    (-4 . "OR>")))

(defun sp:lista (ss / i l)
  (if ss (repeat (setq i (sslength ss)) (setq l (cons (ssname ss (setq i (1- i))) l))))
  l
)

;;; --------------------------------------------------------------------------
;;; Execução
;;; --------------------------------------------------------------------------
(defun sp:f-simplifica (recs fech / r)
  (if (>= (length recs) 3)
    (progn
      (setq r (sp:simplifica-recs recs fech *SP-TOL*))
      (if (< (length (car r)) (length recs)) r))))

(defun sp:executa-smp (/ ss l t0 r nobj nmud va vd dmax)
  (if (setq l (sp:lista (ssget "_:L" *SP-FILTRO-PL*)))
    (progn
      (setq t0 (getvar "MILLISECS") nobj (length l) nmud 0 va 0 vd 0 dmax 0.0)
      (foreach e l
        (if (setq r (sp:aplica e 'sp:f-simplifica *SP-MANTER*))
          (setq nmud (1+ nmud) va (+ va (car r)) vd (+ vd (cadr r)) dmax (max dmax (caddr r)))))
      (princ (strcat "\n" (itoa nobj) " polilinha(s), " (itoa nmud) " simplificada(s)"
                     (if (> nmud 0)
                       (strcat ": " (itoa va) " -> " (itoa vd) " vértices (-"
                               (rtos (* 100.0 (/ (- va vd) (float va))) 2 1) "%), maior desvio real "
                               (rtos dmax 2 4) " m (tolerância " (rtos *SP-TOL* 2 4) " m)")
                       "")
                     ". [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))))
  (princ)
)

(defun sp:f-segmenta (recs fech / r)
  (setq r (sp:segmenta-recs recs fech (if *SA-FIXA* 'MEDIDA 'FLECHA) (if *SA-FIXA* *SA-MEDIDA* *SA-FLECHA*)))
  (if (> (cdr r) 0) r)
)

(defun sp:executa-seg (/ l t0 r npl narc nvd nav filtro)
  (setq filtro (if *SA-AVULSOS*
                 (append '((-4 . "<OR") (0 . "ARC") (0 . "CIRCLE")) (cdr *SP-FILTRO-PL*))
                 *SP-FILTRO-PL*))
  (if (setq l (sp:lista (ssget "_:L" filtro)))
    (progn
      (setq t0 (getvar "MILLISECS") npl 0 narc 0 nvd 0 nav 0)
      (foreach e l
        (if (wcmatch (cdr (assoc 0 (entget e))) "ARC,CIRCLE")
          (if (setq r (sp:arco-ent e (if *SA-FIXA* 'MEDIDA 'FLECHA)
                                   (if *SA-FIXA* *SA-MEDIDA* *SA-FLECHA*) *SA-MANTER*))
            (setq nav (1+ nav) nvd (+ nvd r)))
          (if (setq r (sp:aplica e 'sp:f-segmenta *SA-MANTER*))
            (setq npl (1+ npl) narc (+ narc (caddr r)) nvd (+ nvd (- (cadr r) (car r)))))))
      (princ (strcat "\n" (itoa narc) " arco(s) segmentado(s) em " (itoa npl) " polilinha(s)"
                     (if (> nav 0) (strcat "; " (itoa nav) " arco(s)/círculo(s) avulso(s) convertido(s)") "")
                     "; " (itoa nvd) " vértice(s) criado(s) - "
                     (if *SA-FIXA*
                       (strcat "medida fixa " (rtos *SA-MEDIDA* 2 3) " m")
                       (strcat "flecha máx. " (rtos *SA-FLECHA* 2 4) " m"))
                     ". [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Diálogos
;;; --------------------------------------------------------------------------
(defun sp:pasta ()
  (cond (*LISPS-DIR*)
        ((findfile "Simplifica.dcl") (vl-filename-directory (findfile "Simplifica.dcl"))))
)
(defun sp:num-tile (k / s) (setq s (get_tile k)) (if s (distof (vl-string-translate "," "." s) 2)))

;;; abre o diálogo nome, inicia com ini, valida com ok?; roda exec com Undo
(defun sp:comando (nome ini ok? exec / *error* doc dcl arq r)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (setq arq (if (sp:pasta) (strcat (sp:pasta) "\\Simplifica.dcl")))
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo Simplifica.dcl não encontrado.") (exit)))
  (setq dcl (load_dialog arq))
  (if (not (new_dialog nome dcl)) (progn (alert "Erro ao abrir o diálogo.") (exit)))
  (apply ini nil)
  (action_tile "accept" (strcat "(if (" (vl-symbol-name ok?) ") (done_dialog 1))"))
  (action_tile "cancel" "(done_dialog 0)")
  (setq r (start_dialog))
  (unload_dialog dcl)
  (setq dcl nil)
  (if (= r 1)
    (progn (vla-StartUndoMark doc) (apply exec nil) (vla-EndUndoMark doc)))
  (princ)
)

;;; SIMPLIFICAPL
(defun sp:ini-smp ()
  (set_tile "tol" (rtos *SP-TOL* 2 4))
  (set_tile "manter" (if *SP-MANTER* "1" "0"))
)
(defun sp:ok-smp (/ a)
  (setq a (sp:num-tile "tol"))
  (if (not (and a (>= a 0.0)))
    (progn (set_tile "error" "Tolerância inválida (>= 0).") nil)
    (progn (setq *SP-TOL* a *SP-MANTER* (= "1" (get_tile "manter")))
           (sp:grava-env "LISPS_SIMPLIFICA" *SP-CHAVES*)
           T))
)
(defun c:SIMPLIFICAPL () (sp:comando "simplifica" 'sp:ini-smp 'sp:ok-smp 'sp:executa-smp))

;;; SEGMENTARCOS
(defun sp:hab-seg (v)
  (mode_tile "medida" (if (= v "1") 0 1))
  (mode_tile "flecha" (if (= v "1") 1 0))
)
(defun sp:ini-seg ()
  (set_tile "flecha"  (rtos *SA-FLECHA* 2 4))
  (set_tile "medida"  (rtos *SA-MEDIDA* 2 3))
  (set_tile "fixa"    (if *SA-FIXA* "1" "0"))
  (set_tile "avulsos" (if *SA-AVULSOS* "1" "0"))
  (set_tile "manter"  (if *SA-MANTER* "1" "0"))
  (sp:hab-seg (if *SA-FIXA* "1" "0"))
  (action_tile "fixa" "(sp:hab-seg $value)")
)
(defun sp:ok-seg (/ f m)
  (setq f (sp:num-tile "flecha") m (sp:num-tile "medida"))
  (cond
    ((not (and f (> f 0.0))) (set_tile "error" "Desvio máximo inválido (> 0).") nil)
    ((not (and m (> m 0.0))) (set_tile "error" "Medida inválida (> 0).") nil)
    (T (setq *SA-FLECHA* f *SA-MEDIDA* m
             *SA-FIXA*    (= "1" (get_tile "fixa"))
             *SA-AVULSOS* (= "1" (get_tile "avulsos"))
             *SA-MANTER*  (= "1" (get_tile "manter")))
       (sp:grava-env "LISPS_SEGARCOS" *SA-CHAVES*)
       T))
)
(defun c:SEGMENTARCOS () (sp:comando "segarcos" 'sp:ini-seg 'sp:ok-seg 'sp:executa-seg))

;;; --------------------------------------------------------------------------
;;; PADRONIZAVERT (HME) - vértices a espaçamento constante ao longo da curva
;;; --------------------------------------------------------------------------
;;; vértice k é canto? (mudança de direção > *HM-ANG* graus)
(defun sp:canto-p (e k / a b la lb)
  (setq a  (vlax-curve-getFirstDeriv e (- k 1e-6))
        b  (vlax-curve-getFirstDeriv e (+ k 1e-6))
        la (distance '(0 0) (sp:2d a))
        lb (distance '(0 0) (sp:2d b)))
  (and (> la 1e-12) (> lb 1e-12)
       (> (sp:acos (max -1.0 (min 1.0 (/ (+ (* (car a) (car b)) (* (cadr a) (cadr b))) (* la lb)))))
          (/ (* *HM-ANG* pi) 180.0)))
)

;;; usada por sp:aplica; a curva é *SP-ENT* (recs só dá o nº de vértices)
(defun sp:f-hme (recs fech / e nv total cortes k out)
  (setq e     *SP-ENT*
        nv    (length recs)
        total (vlax-curve-getDistAtParam e (vlax-curve-getEndParam e)))
  (if (and total (> total 1e-9))
    (progn
      (setq cortes (list 0.0))
      (if *HM-CANTOS*
        (progn
          (setq k 1)
          (while (< k (if fech nv (1- nv)))
            (if (sp:canto-p e k) (setq cortes (cons (vlax-curve-getDistAtParam e k) cortes)))
            (setq k (1+ k)))))
      (setq cortes (reverse (cons total cortes)))
      (mapcar
        '(lambda (d0 d1 / dl n j)
           (setq dl (- d1 d0))
           (if (> dl 1e-9)
             (progn
               (setq n (max 1 (fix (+ 0.5 (/ dl *HM-ESP*)))) j 0)
               (repeat n
                 (setq out (cons (vlax-curve-getPointAtDist e (+ d0 (/ (* dl j) n))) out)
                       j   (1+ j))))))
        cortes (cdr cortes))
      (if (not fech) (setq out (cons (vlax-curve-getEndPoint e) out)))
      (setq out (vl-remove 'nil out))
      (if (>= (length out) (if fech 3 2))
        (cons (mapcar '(lambda (p) (list (trans p 0 e) 0.0 0.0 0.0)) (reverse out)) nil))))
)

(defun sp:executa-hme (/ l t0 r nobj nmud va vd *SP-ENT*)
  (if (setq l (sp:lista (ssget "_:L" *SP-FILTRO-PL*)))
    (progn
      (setq t0 (getvar "MILLISECS") nobj (length l) nmud 0 va 0 vd 0)
      (foreach e l
        (setq *SP-ENT* e)
        (if (setq r (sp:aplica e 'sp:f-hme *HM-MANTER*))
          (setq nmud (1+ nmud) va (+ va (car r)) vd (+ vd (cadr r)))))
      (princ (strcat "\n" (itoa nmud) " de " (itoa nobj) " polilinha(s) padronizada(s): "
                     (itoa va) " -> " (itoa vd) " vértices, espaçamento " (rtos *HM-ESP* 2 2) " m"
                     (if *HM-CANTOS* (strcat ", cantos > " (rtos *HM-ANG* 2 0) " graus preservados") "")
                     ". [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))))
  (princ)
)

(defun sp:ini-hme ()
  (set_tile "esp"    (rtos *HM-ESP* 2 3))
  (set_tile "cantos" (if *HM-CANTOS* "1" "0"))
  (set_tile "ang"    (rtos *HM-ANG* 2 1))
  (set_tile "manter" (if *HM-MANTER* "1" "0"))
  (mode_tile "ang" (if *HM-CANTOS* 0 1))
  (action_tile "cantos" "(mode_tile \"ang\" (if (= $value \"1\") 0 1))")
)
(defun sp:ok-hme (/ d a)
  (setq d (sp:num-tile "esp") a (sp:num-tile "ang"))
  (cond
    ((not (and d (> d 0.0))) (set_tile "error" "Espaçamento inválido (> 0).") nil)
    ((not (and a (> a 0.0) (< a 180.0))) (set_tile "error" "Ângulo de canto inválido (0 a 180).") nil)
    (T (setq *HM-ESP* d *HM-ANG* a
             *HM-CANTOS* (= "1" (get_tile "cantos"))
             *HM-MANTER* (= "1" (get_tile "manter")))
       (sp:grava-env "LISPS_PADRONIZAVERT" *HM-CHAVES*)
       T))
)
(defun c:PADRONIZAVERT () (sp:comando "hme" 'sp:ini-hme 'sp:ok-hme 'sp:executa-hme))

(princ "\nSimplifica carregado. Comandos: SIMPLIFICAPL, SEGMENTARCOS, PADRONIZAVERT")
(princ)
