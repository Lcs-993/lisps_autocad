;;; ==========================================================================
;;; Obstaculos.lsp - Desvio de Obstáculos
;;; --------------------------------------------------------------------------
;;; Equivalente ao GOOBS do AgroCAD ("Desviar de Obstáculos"):
;;; as linhas (guias/plantio) que cruzam um obstáculo (polilinha fechada ou
;;; círculo: árvore, poste, afloramento, lagoa...) passam a contorná-lo.
;;;
;;; Parâmetros (diálogo):
;;;   Raio Mínimo (m)          - raio das transições e menor curva do contorno
;;;   Afastamento (m)          - folga entre o obstáculo e a linha mais próxima
;;;   Distância Mínima entre Vértices (m) - simplifica o contorno (0 = não)
;;;   Apenas Interromper as Linhas - corta as linhas no afastamento (sem desvio)
;;;   Contornar Todo o Obstáculo   - a linha dá a volta completa e segue
;;;   Indicar Lado Preferencial    - clica o lado do desvio (senão: o lado em
;;;                                  que as linhas andam menos)
;;;   Selecionar as Linhas Manualmente - senão: todas as linhas abertas
;;;
;;; CONTORNOS ANINHADOS: a linha mais perto do lado do desvio passa a
;;; EXATAMENTE "Afastamento" do obstáculo; cada linha seguinte contorna a
;;; Afastamento + a sua distância lateral até essa primeira linha - o
;;; espaçamento entre as linhas se mantém e nenhuma passa por cima de outra.
;;;
;;; v2 - folga exata com raio mínimo (A < R):
;;;   M    = max(A, R)  (círculo de raio ro: max(A, R - ro))
;;;   contorno = obstáculo dilatado de M + d (cantos com raio >= R), fechado
;;;              por R (cantos côncavos com raio R) e TRANSLADADO de M - A
;;;              para longe do lado do desvio.
;;;   Cada disco B(p, A) do obstáculo dilatado cabe em B(p - (M-A)w, M):
;;;   o contorno contém a folga A e a toca na direção do desvio - folga real
;;;   = Afastamento (antes era max(A, R)) sem curva mais fechada que R.
;;;   Transições linha <-> contorno por arcos tangentes de raio R; a linha é
;;;   prolongada temporariamente pelas tangentes das pontas para a concordância
;;;   caber; ponta dentro da folga -> a linha é interrompida na folga.
;;;   Falhas e ajustes ficam marcados no layer DESVIAOBS_AVISOS (não plota),
;;;   com o motivo escrito, e selecionados ao final.
;;;
;;; Desempenho: candidatos por retângulo envolvente lido do DXF (sem COM, sem
;;; depender da vista); IntersectWith só nos candidatos; contornos só para as
;;; linhas que cruzam; geometria final montada em listas e criada com UM
;;; entmake por linha.
;;;
;;; Comando: DESVIAOBS
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Parâmetros (persistem via setenv)
;;; --------------------------------------------------------------------------
(setq *OB-CHAVES* '(*OB-RAIO* *OB-AFAST* *OB-DMIN* *OB-INTERROMPER* *OB-CONTORNAR*
                    *OB-LADO* *OB-MANUAL*))
(defun ob:le-env (/ v)
  (setq *OB-RAIO* 6.0 *OB-AFAST* 3.0 *OB-DMIN* 0.0 *OB-INTERROMPER* nil
        *OB-CONTORNAR* nil *OB-LADO* nil *OB-MANUAL* nil)
  (if (and (setq v (getenv "LISPS_DESVIAOBS"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= (length v) (length *OB-CHAVES*)) (numberp (car v)))
    (mapcar 'set *OB-CHAVES* v))
)
(defun ob:grava-env () (setenv "LISPS_DESVIAOBS" (vl-prin1-to-string (mapcar 'eval *OB-CHAVES*))))
(if (not *OB-RAIO*) (ob:le-env))

;;; --------------------------------------------------------------------------
;;; Geometria básica
;;; --------------------------------------------------------------------------
(defun ob:2d (p) (list (car p) (cadr p)))
(defun ob:tan (x) (/ (sin x) (cos x)))
(defun ob:bpar (b frac) (ob:tan (* (atan b) frac)))
(defun ob:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun ob:sub (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun ob:add (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun ob:esc (v k) (list (* k (car v)) (* k (cadr v))))
(defun ob:cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))
(defun ob:unit (v / l)
  (setq l (sqrt (ob:dot v v)))
  (if (> l 1e-300) (ob:esc v (/ 1.0 l)) v)
)
(defun ob:butlast (l) (reverse (cdr (reverse l))))

;;; ponto q dentro do contorno fechado (dados lw-data): número de voltas
;;; exato com arcos (corda + 2pi quando q está entre a corda e o arco)
(defun ob:dentro (q d / v b n i p0 p1 bl w da th c r m ch)
  (setq v (car d) b (cadr d) n (length v) w 0.0 i 0)
  (repeat n
    (setq p0 (ob:2d (nth i v)) p1 (ob:2d (nth (rem (1+ i) n) v)) bl (nth i b) i (1+ i))
    (if (not (equal p0 p1 1e-12))
      (progn
        (setq da (- (angle q p1) (angle q p0)))
        (while (> da pi) (setq da (- da pi pi)))
        (while (<= da (- pi)) (setq da (+ da pi pi)))
        (if (> (abs bl) 1e-10)
          (progn
            (setq th (* 4.0 (atan bl))
                  c  (polar p0 (+ (angle p0 p1) (- (/ pi 2.0) (/ th 2.0)))
                            (/ (* (distance p0 p1) (+ 1.0 (* bl bl))) (* 4.0 bl)))
                  r  (distance c p0)
                  m  (polar c (+ (angle c p0) (/ th 2.0)) r)
                  ch (ob:sub p1 p0))
            (if (and (< (distance q c) r)
                     (> (* (ob:cross ch (ob:sub q p0)) (ob:cross ch (ob:sub m p0))) 0.0))
              (setq da (+ da (if (> th 0.0) (+ pi pi) (- (+ pi pi))))))))
        (setq w (+ w da)))))
  (> (abs w) pi)
)

(defun ob:lw-data (e / ed v b)
  (setq ed (entget e))
  (foreach g ed
    (cond ((= (car g) 10) (setq v (cons (cdr g) v)))
          ((= (car g) 42) (setq b (cons (cdr g) b)))))
  (list (reverse v) (reverse b) (= 1 (logand 1 (cdr (assoc 70 ed)))) ed)
)

(defun ob:props (ed / r)
  (foreach k '(8 62 6 370 48 420 440) (if (assoc k ed) (setq r (cons (assoc k ed) r))))
  (reverse r)
)

(defun ob:mk-lw (pts buls fechada props)
  (entmake
    (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity"))
            props
            (list '(100 . "AcDbPolyline") (cons 90 (length pts)) (cons 70 (if fechada 1 0)) '(38 . 0.0))
            (apply 'append (mapcar '(lambda (p b) (list (cons 10 p) (cons 42 b))) pts buls))))
  (entlast)
)

(defun ob:apaga (l) (foreach o l (vl-catch-all-apply 'vla-delete (list o))))

(defun ob:offset (o d / r)
  (setq r (vl-catch-all-apply 'vlax-invoke (list o 'Offset d)))
  (if (vl-catch-all-error-p r) nil r)
)

;;; offset de contorno fechado aumentando (mais = T) ou reduzindo a área;
;;; devolve UM objeto (o de maior área) e apaga os demais
(defun ob:offset-area (o d mais / a0 r m)
  (setq a0 (vla-get-Area o) r (ob:offset o d))
  (if (and r (/= mais (> (vla-get-Area (car r)) a0)))
    (progn (ob:apaga r) (setq r (ob:offset o (- d)))))
  (if r
    (progn
      (setq m (car r))
      (foreach x (cdr r) (if (> (vla-get-Area x) (vla-get-Area m)) (setq m x)))
      (ob:apaga (vl-remove m r))
      m))
)

(defun ob:interseccoes (a b / r l)
  (setq r (vl-catch-all-apply 'vlax-invoke (list a 'IntersectWith b acExtendNone)))
  (if (not (vl-catch-all-error-p r))
    (while r (setq l (cons (list (car r) (cadr r)) l) r (cdddr r))))
  l
)

(defun ob:param (o p) (vlax-curve-getParamAtPoint o (vlax-curve-getClosestPointTo o p)))

;;; ponto num parâmetro, com "volta" em curva fechada (n vértices)
(defun ob:pt (o p n) (ob:2d (vlax-curve-getPointAtParam o (if (>= p n) (- p n) p))))

;;; trecho da LWPOLYLINE o (dados d) de a até b no sentido crescente;
;;; fechada: pode passar pelo fim (b < a ou b = a + n). -> (pts segbuls)
(defun ob:trecho (o d a b / v bl n pts buls k ia fa ib fb)
  (setq v (car d) bl (cadr d) n (length v))
  (if (and (caddr d) (< b a)) (setq b (+ b n)))
  (setq ia (fix a) fa (- a ia) ib (fix b) fb (- b ib))
  (if (> fa (- 1.0 1e-9)) (setq ia (1+ ia) fa 0.0))
  (if (and (< fb 1e-9) (> ib ia)) (setq ib (1- ib) fb 1.0))
  (setq pts (list (ob:pt o a n)))
  (if (= ia ib)
    (setq buls (list (ob:bpar (nth (rem ia n) bl) (- fb fa))))
    (progn
      (setq buls (list (ob:bpar (nth (rem ia n) bl) (- 1.0 fa))) k (1+ ia))
      (while (< k ib)
        (setq pts  (cons (nth (rem k n) v) pts)
              buls (cons (nth (rem k n) bl) buls)
              k    (1+ k)))
      (setq pts  (cons (nth (rem ib n) v) pts)
            buls (cons (ob:bpar (nth (rem ib n) bl) fb) buls))))
  (setq pts (cons (ob:pt o b n) pts))
  (list (reverse pts) (reverse buls))
)

(defun ob:inverte (tr) (list (reverse (car tr)) (mapcar '- (reverse (cadr tr)))))

;;; simplifica: tira vértice entre dois segmentos retos se estiver a menos de
;;; dmin do último mantido
(defun ob:simplifica (tr dmin / pts buls rp rb ant b0)
  (if (<= dmin 0.0)
    tr
    (progn
      (setq pts (car tr) buls (cadr tr)
            rp (list (car pts)) rb nil ant (car pts) pts (cdr pts))
      (while (cdr pts)
        (if (and (equal (car buls) 0.0 1e-9) (equal (cadr buls) 0.0 1e-9)
                 (< (distance ant (car pts)) dmin))
          (setq buls (cdr buls))                       ; funde os dois segmentos
          (setq rp (cons (car pts) rp) rb (cons (car buls) rb) ant (car pts) buls (cdr buls)))
        (setq pts (cdr pts)))
      (list (reverse (cons (car pts) rp)) (reverse (cons (car buls) rb)))))
)

;;; une peças (pts segbuls); cn = bulges das ligações entre peças vizinhas
;;; (ligação ignorada quando as pontas já coincidem)
(defun ob:junta (pecas cn / rp rb)
  (foreach pc pecas
    (cond
      ((null rp) (setq rp (reverse (car pc)) rb (reverse (cadr pc))))
      (T
       (if (< (distance (car rp) (car (car pc))) 1e-6)
         (setq rp (append (reverse (cdr (car pc))) rp))
         (setq rb (cons (car cn) rb) rp (append (reverse (car pc)) rp)))
       (setq rb (append (reverse (cadr pc)) rb) cn (cdr cn)))))
  (list (reverse rp) (reverse (cons 0.0 rb)))
)

;;; bulge do arco de p1 a p2 em torno de c (ccw = T anti-horário)
(defun ob:bulge-arco (c p1 p2 ccw / s)
  (setq s (rem (+ (* 4.0 pi) (if ccw (- (angle c p2) (angle c p1)) (- (angle c p1) (angle c p2)))) (* 2.0 pi)))
  (* (if ccw 1.0 -1.0) (ob:tan (/ s 4.0)))
)

;;; --------------------------------------------------------------------------
;;; Linhas e obstáculos
;;; --------------------------------------------------------------------------
;;; retângulo envolvente pelos vértices DXF (sem COM)
(defun ob:bbox-dxf (e / ed xs ys)
  (setq ed (entget e))
  (foreach g ed (if (member (car g) '(10 11)) (setq xs (cons (cadr g) xs) ys (cons (caddr g) ys))))
  (list (list (apply 'min xs) (apply 'min ys)) (list (apply 'max xs) (apply 'max ys)))
)
(defun ob:bbox-toca (a b)
  (and (<= (car (car a)) (car (cadr b))) (<= (car (car b)) (car (cadr a)))
       (<= (cadr (car a)) (cadr (cadr b))) (<= (cadr (car b)) (cadr (cadr a))))
)
(defun ob:bbox-cresce (b d)
  (list (list (- (car (car b)) d) (- (cadr (car b)) d)) (list (+ (car (cadr b)) d) (+ (cadr (cadr b)) d)))
)

;;; obstáculo -> LWPOLYLINE fechada temporária (círculo = 2 semicírculos)
(defun ob:obst-lw (e / ed c r)
  (setq ed (entget e))
  (if (= "CIRCLE" (cdr (assoc 0 ed)))
    (progn
      (setq c (ob:2d (trans (cdr (assoc 10 ed)) (cdr (assoc 210 ed)) 0)) r (cdr (assoc 40 ed)))
      (vlax-ename->vla-object
        (ob:mk-lw (list (polar c 0.0 r) (polar c pi r)) '(1.0 1.0) T '((8 . "0")))))
    (vla-Copy (vlax-ename->vla-object e)))
)

;;; linha aberta -> LWPOLYLINE temporária (LINE convertida)
(defun ob:linha-lw (e / ed)
  (setq ed (entget e))
  (if (= "LINE" (cdr (assoc 0 ed)))
    (vlax-ename->vla-object
      (ob:mk-lw (list (ob:2d (cdr (assoc 10 ed))) (ob:2d (cdr (assoc 11 ed)))) '(0.0 0.0) nil '((8 . "0"))))
    (vla-Copy (vlax-ename->vla-object e)))
)

;;; contorno suavizado a distância c do obstáculo o (temporário); o chamador
;;; garante c >= R nas polilinhas (cantos) e ro + c >= R nos círculos
(defun ob:contorno (o c r / d e f)
  (if (setq d (if (> c 1e-9) (ob:offset-area o c T) (vla-Copy o)))
    (progn
      (setq e (ob:offset-area d r T) f (if e (ob:offset-area e r nil)))
      (ob:apaga (list e))
      (if f (progn (vla-delete d) f) d)))
)

;;; contorno da linha: dilatação c, transladado de desl para longe do lado w
(defun ob:contorno-linha (o c desl w / ct)
  (if (setq ct (ob:contorno o c *OB-RAIO*))
    (progn
      (if (> desl 1e-9)
        (vla-Move ct (vlax-3d-point 0.0 0.0 0.0)
                  (vlax-3d-point (* (- desl) (car w)) (* (- desl) (cadr w)) 0.0)))
      ct))
)

;;; cópia temporária da linha prolongada pelas tangentes das pontas (Lx de
;;; cada lado): parâmetro 1 = ponta inicial original, fim - 1 = ponta final
(defun ob:estende (lw Lx / d p0 p1 u0 u1)
  (setq d  (ob:lw-data (vlax-vla-object->ename lw))
        p0 (ob:2d (vlax-curve-getStartPoint lw))
        p1 (ob:2d (vlax-curve-getEndPoint lw))
        u0 (ob:unit (ob:2d (vlax-curve-getFirstDeriv lw (vlax-curve-getStartParam lw))))
        u1 (ob:unit (ob:2d (vlax-curve-getFirstDeriv lw (vlax-curve-getEndParam lw)))))
  (vlax-ename->vla-object
    (ob:mk-lw (append (list (ob:sub p0 (ob:esc u0 Lx))) (mapcar 'ob:2d (car d)) (list (ob:add p1 (ob:esc u1 Lx))))
              (append '(0.0) (ob:butlast (cadr d)) '(0.0 0.0))
              nil '((8 . "0"))))
)

;;; --------------------------------------------------------------------------
;;; Diagnóstico visual: cópia da linha + texto do motivo no layer de avisos
;;; --------------------------------------------------------------------------
(setq *OB-LAYER-AVISO* "DESVIAOBS_AVISOS")
(defun ob:motivo (cod)
  (cond ((eq cod 'RAIO)  "raio incompatível: a concordância de raio R não alcança o contorno")
        ((eq cod 'TANG)  "tangência inválida: entrada e saída se sobrepõem (raio grande para o desvio)")
        ((eq cod 'CURTA) "falta de extensão: a concordância não cabe nem prolongando a linha")
        ((eq cod 'CONT)  "falha ao gerar o contorno do obstáculo")
        (T "desvio impossível"))
)
(defun ob:marca (lw txt pt / d h)
  (if (not (tblsearch "LAYER" *OB-LAYER-AVISO*))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 *OB-LAYER-AVISO*) '(70 . 0) '(62 . 1) '(6 . "Continuous") '(290 . 0) '(370 . 50))))
  (setq d (ob:lw-data (vlax-vla-object->ename lw))
        h (max 0.5 (/ *OB-RAIO* 4.0)))
  (list (ob:mk-lw (mapcar 'ob:2d (car d)) (cadr d) nil (list (cons 8 *OB-LAYER-AVISO*)))
        (progn
          (entmake (list '(0 . "TEXT") (cons 8 *OB-LAYER-AVISO*)
                         (list 10 (car pt) (cadr pt) 0.0) (cons 40 h) (cons 1 txt)))
          (entlast)))
)

;;; --------------------------------------------------------------------------
;;; Desvio de UMA linha (lw temporária) em volta do contorno ct
;;;   n    = normal (esquerda) da direção dominante das linhas
;;;   lado = +1 / -1: lado do desvio no eixo n
;;;   esq  = T se o lado do desvio fica à ESQUERDA do sentido da linha
;;;   Lx   = prolongamento temporário das pontas (para a concordância caber)
;;;   -> ('OK pts buls prolongamento) ou ('ERRO motivo ponto)
;;; --------------------------------------------------------------------------
(defun ob:desvia (lw ct n lado esq r contornar dmin cen Lx / lx d pe dct nct ext offs of pts ps
                     cin cout tli tlo tci tco pli plo pci pco a b fwd tr volta tol res)
  (setq lx  (ob:estende lw Lx)
        d   (ob:lw-data (vlax-vla-object->ename lx))
        pe  (vlax-curve-getEndParam lx)          ; pontas originais: 1 e pe - 1
        dct (ob:lw-data (vlax-vla-object->ename ct))
        nct (length (car dct))
        ext (ob:offset-area ct r T)
        tol (max 1e-4 (* r 1e-5)))
  ;; linha deslocada de r para o lado do desvio (das duas, a mais para "lado")
  (foreach s '(1.0 -1.0)
    (if (setq of (ob:offset lx (* s r)))
      (setq offs (cons (list (* lado (ob:dot n (ob:2d (vlax-curve-getClosestPointTo (car of) cen)))) of)
                       offs))))
  (setq of (car (vl-sort offs '(lambda (x y) (> (car x) (car y))))))
  (if (and ext of)
    (foreach o (cadr of) (setq pts (append (ob:interseccoes o ext) pts))))
  (foreach x offs (ob:apaga (cadr x)))
  (if ext (vla-delete ext))
  (setq res
    (cond
      ((not (and ext of)) (list 'ERRO 'RAIO cen))
      ((not (cdr pts)) (list 'ERRO 'RAIO cen))
      (T
       ;; centros das transições: o primeiro e o último ao longo da linha
       (setq ps   (vl-sort (mapcar '(lambda (p) (cons (ob:param lx p) p)) pts)
                           '(lambda (x y) (< (car x) (car y))))
             cin  (cdr (car ps))
             cout (cdr (last ps))
             tli  (ob:2d (vlax-curve-getClosestPointTo lx cin))
             tlo  (ob:2d (vlax-curve-getClosestPointTo lx cout))
             tci  (ob:2d (vlax-curve-getClosestPointTo ct cin))
             tco  (ob:2d (vlax-curve-getClosestPointTo ct cout))
             pli  (ob:param lx tli) plo (ob:param lx tlo)
             pci  (ob:param ct tci) pco (ob:param ct tco))
       (cond
         ((not (and pli plo pci pco)) (list 'ERRO 'TANG cin))
         ;; os quatro toques têm de estar a R dos centros (tangência real)
         ((or (> (abs (- (distance cin tli) r)) tol) (> (abs (- (distance cin tci) r)) tol)
              (> (abs (- (distance cout tlo) r)) tol) (> (abs (- (distance cout tco) r)) tol))
          (list 'ERRO 'TANG cin))
         ((not (< pli plo)) (list 'ERRO 'TANG cin))
         ((or (<= pli 1e-6) (>= plo (- pe 1e-6)))
          (list 'ERRO 'CURTA (if (<= pli 1e-6) tli tlo)))
         (T
          ;; trecho do contorno pelo lado do desvio (o meio mais para "lado")
          (setq a   (ob:trecho ct dct pci pco)
                b   (ob:inverte (ob:trecho ct dct pco pci))
                fwd (> (* lado (ob:dot n (nth (/ (length (car a)) 2) (car a))))
                       (* lado (ob:dot n (nth (/ (length (car b)) 2) (car b)))))
                tr  (ob:simplifica (if fwd a b) dmin))
          (if contornar
            (setq volta (ob:trecho ct dct pci (+ pci nct))
                  volta (if fwd volta (ob:inverte volta))))
          (append
            (list 'OK)
            (ob:junta (vl-remove nil
                        (list (if (> pli (+ 1.0 1e-9)) (ob:trecho lx d 1.0 pli) (list (list tli) nil))
                              volta
                              tr
                              (if (< plo (- pe 1.0 1e-9)) (ob:trecho lx d plo (- pe 1.0)) (list (list tlo) nil))))
                      (vl-remove nil
                        (list (ob:bulge-arco cin tli tci esq)          ; transição de entrada
                              (if volta 0.0)
                              (ob:bulge-arco cout tco tlo esq))))       ; transição de saída
            ;; quanto a linha cresceu (no trecho prolongado o parâmetro é linear)
            (list (* Lx (+ (max 0.0 (- 1.0 pli)) (max 0.0 (- plo (- pe 1.0))))))))))))
  (vla-delete lx)
  res
)

;;; corta a linha no contorno ct (dados cd): devolve os trechos de FORA
;;; ((pts buls) ...) - funciona com 1, 2 ou mais cruzamentos (ponta dentro)
(defun ob:interrompe (lw ct cd / d ps a b res)
  (setq d  (ob:lw-data (vlax-vla-object->ename lw))
        ps (append (list (vlax-curve-getStartParam lw))
                   (vl-sort (mapcar '(lambda (p) (ob:param lw p)) (ob:interseccoes lw ct)) '<)
                   (list (vlax-curve-getEndParam lw))))
  (while (cdr ps)
    (setq a (car ps) b (cadr ps) ps (cdr ps))
    (if (and (> (- b a) 1e-6)
             (not (ob:dentro (ob:2d (vlax-curve-getPointAtParam lw (/ (+ a b) 2.0))) cd)))
      (setq res (cons (ob:trecho lw d a b) res))))
  (mapcar '(lambda (tr) (list (car tr) (append (cadr tr) '(0.0)))) (reverse res))
)

;;; --------------------------------------------------------------------------
;;; Ação
;;; --------------------------------------------------------------------------
(defun ob:sel (msg filtro / ss i res)
  (princ msg)
  (if (setq ss (ssget filtro))
    (progn (setq i 0) (repeat (sslength ss) (setq res (cons (ssname ss i) res) i (1+ i)))))
  (reverse res)
)

;;; todas as linhas abertas do espaço atual
(defun ob:todas-linhas (/ ss i res)
  (if (setq ss (ssget "_X" (list '(-4 . "<OR") '(0 . "LINE")
                                 '(-4 . "<AND") '(0 . "LWPOLYLINE") '(-4 . "<NOT") '(-4 . "&") '(70 . 1) '(-4 . "NOT>") '(-4 . "AND>")
                                 '(-4 . "OR>") (cons 410 (getvar "CTAB")))))
    (progn (setq i 0) (repeat (sslength ss) (setq res (cons (ssname ss i) res) i (1+ i)))))
  res
)

;;; direção dominante (média axial) de linhas lw temporárias -> (u n)
(defun ob:eixos (lws / c s a l th)
  (setq c 0.0 s 0.0)
  (foreach o lws
    (setq a (angle (vlax-curve-getStartPoint o) (vlax-curve-getEndPoint o))
          l (distance (vlax-curve-getStartPoint o) (vlax-curve-getEndPoint o))
          c (+ c (* l (cos (* 2.0 a)))) s (+ s (* l (sin (* 2.0 a))))))
  (setq th (if (and (equal c 0.0 1e-12) (equal s 0.0 1e-12)) 0.0 (/ (atan s c) 2.0)))
  (list (list (cos th) (sin th)) (list (- (sin th)) (cos th)))
)

;;; processa UM obstáculo; cand = ((ename bbox) ...)
;;; -> (cand-novo n-desv n-int n-falhas n-prolong n-ponta marcas)
(defun ob:um-obstaculo (eo cand lado-pt / A R ed ro M desl o c0 c0d bb cen viz cruz ex u n ys vals
                           lmin lmax lado w ytop nl ndev nint fal nprl npta novos marcas)
  (setq A    *OB-AFAST* R *OB-RAIO*
        ed   (entget eo)
        ro   (if (= "CIRCLE" (cdr (assoc 0 ed))) (cdr (assoc 40 ed)))
        ;; folga do contorno antes do deslocamento: garante raio >= R
        M    (if ro (max A (- R ro)) (max A R))
        desl (- M A)
        o    (ob:obst-lw eo)
        ;; zona da folga real (Afastamento): define quem cruza e o corte
        c0   (if (> A 1e-9) (ob:offset-area o A T) (vla-Copy o))
        ndev 0 nint 0 fal 0 nprl 0 npta 0)
  (if c0
    (progn
      (setq c0d (ob:lw-data (vlax-vla-object->ename c0))
            bb  (ob:bbox-dxf (vlax-vla-object->ename c0))
            cen (list (/ (+ (car (car bb)) (car (cadr bb))) 2.0) (/ (+ (cadr (car bb)) (cadr (cadr bb))) 2.0))
            viz (vl-remove-if-not '(lambda (x) (ob:bbox-toca (cadr x) bb)) cand))
      ;; linhas que cruzam a folga
      (foreach x viz
        (setq ex (ob:linha-lw (car x)))
        (if (ob:interseccoes ex c0)
          (setq cruz (cons (list (car x) ex) cruz))
          (vla-delete ex)))
      (if cruz
        (progn
          (setq u (ob:eixos (mapcar 'cadr cruz)) n (cadr u) u (car u))
          ;; posição lateral de cada linha (no ponto mais perto do centro)
          (setq ys (mapcar '(lambda (x) (ob:dot n (ob:2d (vlax-curve-getClosestPointTo (cadr x) cen)))) cruz)
                vals (mapcar '(lambda (p) (ob:dot n (ob:2d p))) (car c0d))
                lmin (apply 'min vals) lmax (apply 'max vals))
          ;; lado: o clicado, ou o de menor deslocamento total
          (setq lado (cond
                       (lado-pt (if (< (ob:dot n (ob:sub (ob:2d lado-pt) cen)) 0.0) -1.0 1.0))
                       ((<= (apply '+ (mapcar '(lambda (y) (- lmax y)) ys))
                            (apply '+ (mapcar '(lambda (y) (- y lmin)) ys)))
                        1.0)
                       (T -1.0))
                w    (ob:esc n lado)
                ytop (if (> lado 0) (apply 'max ys) (apply 'min ys)))
          (mapcar
            '(lambda (x y / s0 s1 props pec ct esq res txt pt)
               (setq props (ob:props (entget (car x)))
                     s0    (ob:2d (vlax-curve-getStartPoint (cadr x)))
                     s1    (ob:2d (vlax-curve-getEndPoint (cadr x))))
               (cond
                 ;; Apenas Interromper (corta na folga A)
                 (*OB-INTERROMPER*
                  (if (setq pec (ob:interrompe (cadr x) c0 c0d))
                    (setq nint (1+ nint))
                    (setq txt "linha inteira dentro do afastamento" pt cen)))
                 ;; ponta dentro da folga: desvio impossível -> interrompe na folga
                 ((or (ob:dentro s0 c0d) (ob:dentro s1 c0d))
                  (if (setq pec (ob:interrompe (cadr x) c0 c0d))
                    (setq nint (1+ nint) npta (1+ npta)
                          txt  "ponta dentro do afastamento: linha interrompida na folga (sem desvio)"
                          pt   (if (ob:dentro s0 c0d) s0 s1))
                    (setq txt "linha inteira dentro do afastamento" pt cen)))
                 ;; desvio
                 (T
                  (setq ct  (ob:contorno-linha o (+ M (abs (- ytop y))) desl w)
                        esq (> (* lado (ob:dot (ob:sub s1 s0) u)) 0.0)
                        res (if ct
                              (ob:desvia (cadr x) ct n lado esq R *OB-CONTORNAR* *OB-DMIN* cen
                                         (+ (* 4.0 R) (distance (car (ob:bbox-dxf (vlax-vla-object->ename ct)))
                                                                (cadr (ob:bbox-dxf (vlax-vla-object->ename ct))))))
                              (list 'ERRO 'CONT cen)))
                  (if ct (vla-delete ct))
                  (if (eq (car res) 'OK)
                    (progn
                      (setq pec (list (cdr res)) ndev (1+ ndev))
                      (if (> (cadddr res) 1e-3)
                        (setq nprl (1+ nprl)
                              txt  (strcat "prolongada " (rtos (cadddr res) 2 2) " m para a concordância caber")
                              pt   (if (< (distance s0 cen) (distance s1 cen)) s0 s1))))
                    (setq txt (ob:motivo (cadr res)) pt (caddr res)))))
               (if txt (setq marcas (append (ob:marca (cadr x) txt pt) marcas)))
               (if pec
                 (progn
                   (foreach p pec
                     (setq nl (ob:mk-lw (car p) (cadr p) nil props)
                           novos (cons (list nl (ob:bbox-dxf nl)) novos)))
                   (entdel (car x))
                   (setq cand (vl-remove-if '(lambda (c) (eq (car c) (car x))) cand)))
                 (setq fal (1+ fal)))
               (vla-delete (cadr x)))
            cruz ys)))
      (vla-delete c0)))
  (vla-delete o)
  (list (append novos cand) ndev nint fal nprl npta marcas)
)

(defun ob:executa (/ obst cand lado-pt t0 r tdev tint tfal tprl tpta marcas gap ss)
  (if (setq obst (ob:sel "\nSelecione os obstáculos: "
                         '((-4 . "<OR") (0 . "CIRCLE") (-4 . "<AND") (0 . "LWPOLYLINE") (-4 . "&") (70 . 1) (-4 . "AND>") (-4 . "OR>"))))
    (progn
      (setq cand (if *OB-MANUAL*
                   (ob:sel "\nSelecione as linhas a serem desviadas: "
                           '((-4 . "<OR") (0 . "LINE")
                             (-4 . "<AND") (0 . "LWPOLYLINE") (-4 . "<NOT") (-4 . "&") (70 . 1) (-4 . "NOT>") (-4 . "AND>")
                             (-4 . "OR>")))
                   (ob:todas-linhas))
            cand (mapcar '(lambda (e) (list e (ob:bbox-dxf e)))
                         (vl-remove-if '(lambda (e) (member e obst)) cand)))
      (if (and *OB-LADO* (not *OB-INTERROMPER*))
        (setq lado-pt (getpoint "\nClique para escolher o lado preferencial: ")))
      (setq t0 (getvar "MILLISECS") tdev 0 tint 0 tfal 0 tprl 0 tpta 0
            gap (getvar "OFFSETGAPTYPE"))
      (setvar "OFFSETGAPTYPE" 1)                       ; cantos arredondados nos offsets
      (foreach eo obst
        (setq r      (ob:um-obstaculo eo cand lado-pt)
              cand   (nth 0 r)
              tdev   (+ tdev (nth 1 r)) tint (+ tint (nth 2 r)) tfal (+ tfal (nth 3 r))
              tprl   (+ tprl (nth 4 r)) tpta (+ tpta (nth 5 r))
              marcas (append (nth 6 r) marcas)))
      (setvar "OFFSETGAPTYPE" gap)
      (princ (strcat "\n" (itoa (length obst)) " obstáculo(s): "
                     (if *OB-INTERROMPER*
                       (strcat (itoa tint) " linha(s) interrompida(s)")
                       (strcat (itoa tdev) " linha(s) desviada(s)"
                               (if (> tprl 0) (strcat " (" (itoa tprl) " prolongada(s) para a concordância caber)") "")
                               (if (> tpta 0) (strcat "; " (itoa tpta) " interrompida(s): ponta dentro do afastamento") "")))
                     (if (> tfal 0) (strcat "; " (itoa tfal) " linha(s) SEM desvio possível (inalterada(s))") "")
                     ". [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))
      (if marcas
        (progn
          (setq ss (ssadd))
          (foreach e marcas (ssadd e ss))
          (princ (strcat "\nAvisos com o motivo no layer " *OB-LAYER-AVISO*
                         " (vermelho, não plota) - selecionados; apague-os depois de conferir."))
          (sssetfirst nil ss)))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun ob:pasta ()
  (cond (*FT-DEV-DIR*)
        ((findfile "Obstaculos.dcl") (vl-filename-directory (findfile "Obstaculos.dcl"))))
)
(defun ob:num (k / s) (setq s (get_tile k)) (if s (distof (vl-string-translate "," "." s) 2)))

(defun ob:le-tiles (/ r a m)
  (setq r (ob:num "raio") a (ob:num "afast") m (ob:num "dmin"))
  (cond
    ((not (and r (> r 0.0))) (set_tile "error" "Raio mínimo inválido (> 0).") nil)
    ((not (and a (>= a 0.0))) (set_tile "error" "Afastamento inválido (>= 0).") nil)
    ((not (and m (>= m 0.0))) (set_tile "error" "Distância mínima inválida (>= 0).") nil)
    (T (setq *OB-RAIO* r *OB-AFAST* a *OB-DMIN* m
             *OB-INTERROMPER* (= "1" (get_tile "interromper"))
             *OB-CONTORNAR*   (= "1" (get_tile "contornar"))
             *OB-LADO*        (= "1" (get_tile "lado"))
             *OB-MANUAL*      (= "1" (get_tile "manual")))
       (ob:grava-env)
       T))
)

(defun ob:habilita (v)
  (foreach k '("raio" "dmin" "contornar" "lado") (mode_tile k (if (= v "1") 1 0)))
)

(defun c:DESVIAOBS (/ *error* doc dcl arq r gap)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) gap (getvar "OFFSETGAPTYPE"))
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (setvar "OFFSETGAPTYPE" gap)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (setq arq (if (ob:pasta) (strcat (ob:pasta) "\\Obstaculos.dcl")))
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo Obstaculos.dcl não encontrado.") (exit)))
  (setq dcl (load_dialog arq))
  (if (not (new_dialog "obstaculos" dcl)) (progn (alert "Erro ao abrir o diálogo.") (exit)))
  (set_tile "raio"        (rtos *OB-RAIO* 2 2))
  (set_tile "afast"       (rtos *OB-AFAST* 2 2))
  (set_tile "dmin"        (rtos *OB-DMIN* 2 2))
  (set_tile "interromper" (if *OB-INTERROMPER* "1" "0"))
  (set_tile "contornar"   (if *OB-CONTORNAR* "1" "0"))
  (set_tile "lado"        (if *OB-LADO* "1" "0"))
  (set_tile "manual"      (if *OB-MANUAL* "1" "0"))
  (ob:habilita (if *OB-INTERROMPER* "1" "0"))
  (action_tile "interromper" "(ob:habilita $value)")
  (action_tile "accept" "(if (ob:le-tiles) (done_dialog 1))")
  (action_tile "cancel" "(done_dialog 0)")
  (setq r (start_dialog))
  (unload_dialog dcl)
  (setq dcl nil)
  (if (= r 1)
    (progn (vla-StartUndoMark doc) (ob:executa) (vla-EndUndoMark doc)))
  (princ)
)

(princ "\nObstaculos carregado. Comando: DESVIAOBS")
(princ)
