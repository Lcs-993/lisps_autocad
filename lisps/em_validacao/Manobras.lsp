;;; ==========================================================================
;;; Manobras.lsp - Criar Manobras entre linhas
;;; --------------------------------------------------------------------------
;;; Equivalente ao GOTUR do AgroCAD ("Criar Manobras"):
;;;
;;;   Raio de Giro Mínimo ou Ideal [R]
;;;   Afastamento [A]                    - folga entre a manobra e a bordadura
;;;   Distância Máxima entre Vértices (m) - 0 = arcos exatos; > 0 = arcos
;;;                                        discretizados (para exportação)
;;;   Conectar Linhas com Manobra a Cada N  (padrão "a cada N")
;;;   Manobras em Caracol / Manobras em 1-3-5-2-4
;;;   Cortar Linhas para Criar Afastamento  (pede a bordadura)
;;;   Juntar Trechos Conectados / Apagar Linhas Originais
;;;
;;; Forma da manobra entre duas linhas (separação lateral s):
;;;   s >= 2R : U      - arco 90° + reta (s - 2R) + arco 90°
;;;   s <  2R : ÔMEGA  - sai para fora (arco b), volta pelo arco maior
;;;             (pi + 2b) e entra (arco b); b = atan2(h, s/2 + R),
;;;             h = sqrt(4R² - (s/2 + R)²); profundidade h + R
;;;   pontas desencontradas: a linha mais curta é prolongada em reta.
;;;
;;; Desempenho: geometria das manobras 100% analítica (bulges exatos, sem
;;; offsets/fillet via comando); ordem por varredura lateral; um entmake por
;;; trajeto; COM só no corte pela bordadura (um IntersectWith por linha).
;;;
;;; Comando: MANOBRAS
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Parâmetros (persistem via setenv)
;;; --------------------------------------------------------------------------
(setq *MN-CHAVES* '(*MN-RAIO* *MN-AFAST* *MN-DMAX* *MN-PASSO* *MN-PADRAO* *MN-CORTAR*
                    *MN-JUNTAR* *MN-APAGAR*))
(defun mn:le-env (/ v)
  (setq *MN-RAIO* 6.0 *MN-AFAST* 2.0 *MN-DMAX* 0.0 *MN-PASSO* 1 *MN-PADRAO* "N"
        *MN-CORTAR* nil *MN-JUNTAR* T *MN-APAGAR* T)
  (if (and (setq v (getenv "LISPS_MANOBRAS"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= (length v) (length *MN-CHAVES*)) (numberp (car v)))
    (mapcar 'set *MN-CHAVES* v))
)
(defun mn:grava-env () (setenv "LISPS_MANOBRAS" (vl-prin1-to-string (mapcar 'eval *MN-CHAVES*))))
(if (not *MN-RAIO*) (mn:le-env))

;;; --------------------------------------------------------------------------
;;; Geometria
;;; --------------------------------------------------------------------------
(defun mn:2d (p) (list (car p) (cadr p)))
(defun mn:tan (x) (/ (sin x) (cos x)))
(defun mn:bpar (b frac) (mn:tan (* (atan b) frac)))
(defun mn:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun mn:sub (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun mn:add (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun mn:esc (a k) (list (* (car a) k) (* (cadr a) k)))
(defun mn:unit (a / l) (setq l (distance '(0 0) a)) (list (/ (car a) l) (/ (cadr a) l)))

(defun mn:props (ed / r)
  (foreach k '(8 62 6 370 48 420 440) (if (assoc k ed) (setq r (cons (assoc k ed) r))))
  (reverse r)
)

(defun mn:mk-lw (pts buls props)
  (entmake
    (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity"))
            props
            (list '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 0) '(38 . 0.0))
            (apply 'append (mapcar '(lambda (p b) (list (cons 10 p) (cons 42 b))) pts buls))))
  (entlast)
)

;;; dados de LINE / LWPOLYLINE aberta: (pts segbuls ed)
(defun mn:dados (e / ed pts buls)
  (setq ed (entget e))
  (if (= "LINE" (cdr (assoc 0 ed)))
    (list (list (mn:2d (cdr (assoc 10 ed))) (mn:2d (cdr (assoc 11 ed)))) '(0.0) ed)
    (progn
      (foreach g ed
        (cond ((= (car g) 10) (setq pts (cons (cdr g) pts)))
              ((= (car g) 42) (setq buls (cons (cdr g) buls)))))
      (list (reverse pts) (cdr buls) ed)))       ; cdr de buls invertido = tira o último
)
;;; (cdr buls) acima: buls está invertido; o "último" bulge (sem segmento) sai
;;; e a lista volta à ordem certa em mn:fixa
(defun mn:fixa (d) (list (car d) (reverse (cadr d)) (caddr d)))

(defun mn:inverte (pts sb) (list (reverse pts) (mapcar '- (reverse sb))))

;;; tangente (unitária) no início / fim de uma linha (pts segbuls)
(defun mn:tang-ini (pts sb / a)
  (setq a (- (angle (car pts) (cadr pts)) (* 2.0 (atan (car sb)))))
  (list (cos a) (sin a))
)
(defun mn:tang-fim (pts sb / a n)
  (setq n (length pts)
        a (+ (angle (nth (- n 2) pts) (last pts)) (* 2.0 (atan (last sb)))))
  (list (cos a) (sin a))
)

;;; --------------------------------------------------------------------------
;;; Manobra entre P (fim da linha a, rumo h) e Q (início da linha b)
;;;   -> (pts segbuls profundidade tipo) com pts de P até Q
;;; --------------------------------------------------------------------------
(defun mn:manobra (p h q r / dir v f l sg s p1 q1 hgt be loc bl pts sb)
  (setq dir (list (cadr h) (- (car h)))               ; direita de h
        v   (mn:sub q p)
        f   (mn:dot v h)
        l   (mn:dot v dir)
        sg  (if (< l 0.0) -1.0 1.0)                    ; b à direita (+1) ou esquerda (-1)
        s   (abs l)
        p1  (mn:add p (mn:esc h (max f 0.0)))         ; pontas igualadas
        q1  (mn:add q (mn:esc h (max (- f) 0.0))))
  ;; pontos e bulges no sistema local (x = lado de b, y = à frente)
  (if (>= s (* 2.0 r))
    (setq loc (list '(0.0 0.0) (list r r) (list (- s r) r) (list s 0.0))
          bl  (list (- (mn:tan (/ pi 8.0))) 0.0 (- (mn:tan (/ pi 8.0))))
          hgt 0.0)
    (setq hgt (sqrt (max 0.0 (- (* 4.0 r r) (expt (+ (/ s 2.0) r) 2))))
          be  (atan hgt (+ (/ s 2.0) r))
          loc (list '(0.0 0.0)
                    (list (+ (- r) (* r (cos be))) (* r (sin be)))
                    (list (- (+ s r) (* r (cos be))) (* r (sin be)))
                    (list s 0.0))
          bl  (list (mn:tan (/ be 4.0)) (- (mn:tan (/ (+ pi (* 2.0 be)) 4.0))) (mn:tan (/ be 4.0)))))
  ;; local -> mundo (espelha se b estiver à esquerda)
  (setq pts (mapcar '(lambda (x) (mn:add p1 (mn:add (mn:esc dir (* sg (car x))) (mn:esc h (cadr x))))) loc)
        sb  (mapcar '(lambda (b) (* sg b)) bl))
  ;; tira segmento nulo (U com s = 2R)
  (if (< (distance (cadr pts) (caddr pts)) 1e-9)
    (setq pts (list (car pts) (cadr pts) (cadddr pts)) sb (list (car sb) (caddr sb))))
  ;; prolongamentos retos
  (if (> (distance p p1) 1e-9) (setq pts (cons p pts) sb (cons 0.0 sb)))
  (if (> (distance q q1) 1e-9) (setq pts (append pts (list q)) sb (append sb '(0.0))))
  (list pts sb (+ r hgt) (if (>= s (* 2.0 r)) "U" "OMEGA"))
)

;;; profundidade (além da ponta) de uma manobra com separação s
(defun mn:profundidade (s r)
  (if (>= s (* 2.0 r)) r (+ r (sqrt (max 0.0 (- (* 4.0 r r) (expt (+ (/ s 2.0) r) 2))))))
)

;;; arcos -> cordas de no máximo dmax
(defun mn:discretiza (pts sb dmax / rp rb p q b th c rr a0 k i)
  (if (<= dmax 0.0)
    (list pts sb)
    (progn
      (setq rp (list (car pts)))
      (while (cdr pts)
        (setq p (car pts) q (cadr pts) b (car sb) pts (cdr pts) sb (cdr sb))
        (if (equal b 0.0 1e-9)
          (setq rp (cons q rp) rb (cons 0.0 rb))
          (progn
            (setq th (* 4.0 (atan b))
                  c  (polar p (+ (angle p q) (- (/ pi 2.0) (/ th 2.0)))
                            (/ (* (distance p q) (1+ (* b b))) (* 4.0 b)))
                  rr (distance c p) a0 (angle c p)
                  k  (max 1 (fix (+ 0.999999 (/ (* rr (abs th)) dmax)))) i 1)
            (repeat (1- k)
              (setq rp (cons (polar c (+ a0 (* th (/ i (float k)))) rr) rp) rb (cons 0.0 rb) i (1+ i)))
            (setq rp (cons q rp) rb (cons 0.0 rb)))))
      (list (reverse rp) (reverse rb))))
)

;;; --------------------------------------------------------------------------
;;; Ordem de visita (índices das linhas ordenadas lateralmente)
;;; --------------------------------------------------------------------------
(defun mn:faixa (a b / r) (while (< a b) (setq r (cons a r) a (1+ a))) (reverse r))

;;; "a cada N": g, g+N, g+2N ... para g = 0..N-1 (um só trajeto)
(defun mn:ordem-passo (n p / g res)
  (setq g 0)
  (while (< g p)
    (setq res (append res (vl-remove-if '(lambda (i) (/= (rem i p) g)) (mn:faixa 0 n))) g (1+ g)))
  (list res)
)

;;; 1-3-5-2-4 em blocos de 5 (um só trajeto)
(defun mn:ordem-13524 (n / b res blk)
  (setq b 0)
  (while (< b n)
    (setq blk (mn:faixa b (min n (+ b 5)))
          res (append res
                      (vl-remove-if '(lambda (i) (= 1 (rem (- i b) 2))) blk)
                      (vl-remove-if '(lambda (i) (= 0 (rem (- i b) 2))) blk))
          b   (+ b 5)))
  (list res)
)

;;; caracol: blocos de 2k (i, i+k, i+1, i+k+1 ...); k = (2R/esp) + 1
;;; continuo = T: um trajeto só; senão um trajeto por bloco
(defun mn:ordem-caracol (n esp r continuo / k b m kk res blk todos i)
  (setq k (max 1 (1+ (fix (+ 0.999999 (/ (* 2.0 r) esp))))) b 0)
  (while (< b n)
    (setq m (min (* 2 k) (- n b)) kk (/ (1+ m) 2) blk nil i 0)
    (while (< i kk)
      (setq blk (cons (+ b i) blk))
      (if (< (+ i kk) m) (setq blk (cons (+ b i kk) blk)))
      (setq i (1+ i)))
    (setq res (cons (reverse blk) res) b (+ b m)))
  (setq res (reverse res))
  (if continuo (list (apply 'append res)) res)
)

;;; --------------------------------------------------------------------------
;;; Corte pela bordadura (afastamento)
;;; --------------------------------------------------------------------------
(defun mn:dentro (p pts / x y in pb)
  (setq x (car p) y (cadr p) pb (last pts))
  (foreach pa pts
    (if (and (/= (> (cadr pa) y) (> (cadr pb) y))
             (< x (+ (car pa) (/ (* (- (car pb) (car pa)) (- y (cadr pa))) (- (cadr pb) (cadr pa))))))
      (setq in (not in)))
    (setq pb pa))
  in
)

;;; trecho [a, b] (parâmetros) de uma linha (pts segbuls)
(defun mn:trecho (o pts sb a b / ia fa ib fb rp rb k)
  (setq ia (fix a) fa (- a ia) ib (fix b) fb (- b ib))
  (if (> fa (- 1.0 1e-9)) (setq ia (1+ ia) fa 0.0))
  (if (and (< fb 1e-9) (> ib ia)) (setq ib (1- ib) fb 1.0))
  (setq rp (list (mn:2d (vlax-curve-getPointAtParam o a))))
  (if (= ia ib)
    (setq rb (list (mn:bpar (nth ia sb) (- fb fa))))
    (progn
      (setq rb (list (mn:bpar (nth ia sb) (- 1.0 fa))) k (1+ ia))
      (while (< k ib) (setq rp (cons (nth k pts) rp) rb (cons (nth k sb) rb) k (1+ k)))
      (setq rp (cons (nth ib pts) rp) rb (cons (mn:bpar (nth ib sb) fb) rb))))
  (setq rp (cons (mn:2d (vlax-curve-getPointAtParam o b)) rp))
  (list (reverse rp) (reverse rb))
)

;;; corta a linha d no polígono interno (vla) -> d novo (maior trecho dentro)
(defun mn:corta (d interno ipts / o r ps a b best bl tr)
  (setq o (vlax-ename->vla-object (mn:mk-lw (car d) (append (cadr d) '(0.0)) '((8 . "0"))))
        r (vl-catch-all-apply 'vlax-invoke (list o 'IntersectWith interno acExtendNone)))
  (if (not (vl-catch-all-error-p r))
    (while r
      (setq ps (cons (vlax-curve-getParamAtPoint o (vlax-curve-getClosestPointTo o (list (car r) (cadr r) 0.0))) ps)
            r  (cdddr r))))
  (setq ps (append (list (vlax-curve-getStartParam o)) (vl-sort (vl-remove nil ps) '<)
                   (list (vlax-curve-getEndParam o)))
        bl 0.0)
  (while (cdr ps)
    (setq a (car ps) b (cadr ps) ps (cdr ps))
    (if (and (> (- b a) 1e-6)
             (mn:dentro (mn:2d (vlax-curve-getPointAtParam o (/ (+ a b) 2.0))) ipts)
             (> (- (vlax-curve-getDistAtParam o b) (vlax-curve-getDistAtParam o a)) bl))
      (setq bl (- (vlax-curve-getDistAtParam o b) (vlax-curve-getDistAtParam o a))
            best (list a b))))
  (if best (setq tr (mn:trecho o (car d) (cadr d) (car best) (cadr best))))
  (vla-delete o)
  (if tr (list (car tr) (cadr tr) (caddr d)))
)

;;; polígono interno da bordadura a distância dd (vla) e seus vértices
(defun mn:interno (bord dd / o a0 r m)
  (setq o (vlax-ename->vla-object bord) a0 (vla-get-Area o)
        r (vl-catch-all-apply 'vlax-invoke (list o 'Offset dd)))
  (if (or (vl-catch-all-error-p r) (null r) (> (vla-get-Area (car r)) a0))
    (progn
      (if (and r (not (vl-catch-all-error-p r))) (foreach x r (vla-delete x)))
      (setq r (vl-catch-all-apply 'vlax-invoke (list o 'Offset (- dd))))))
  (if (and r (not (vl-catch-all-error-p r)))
    (progn
      (setq m (car r))
      (foreach x (cdr r) (if (> (vla-get-Area x) (vla-get-Area m)) (setq m x)))
      (foreach x r (if (not (eq x m)) (vla-delete x)))
      m))
)

;;; --------------------------------------------------------------------------
;;; Ação
;;; --------------------------------------------------------------------------
(defun mn:layer-manobras (/ nome cor)
  (setq nome (if tr:cfg-nome (tr:cfg-nome 'NOM_LAY_MANOBRAS "MANOBRAS") "MANOBRAS")
        cor  (if tr:cfg-cor (tr:cfg-cor "COR_LAY_MANOBRAS" 4) 4))
  (if (not (tblsearch "LAYER" nome))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 nome) '(70 . 0) (cons 62 cor) '(6 . "Continuous"))))
  nome
)

(defun mn:executa (/ bord ss i e d dados enames th u n lats ord esp seqs pini prim ult
                     cont interno ipts dd t0 nman nu no comp lay sg tray p h q m pts sb
                     orient visit ntray)
  (if *MN-CORTAR*
    (progn
      (princ "\nSelecione a Bordadura (Enter = sem corte): ")
      (setq bord (ssget ":S" '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
      (if bord (setq bord (ssname bord 0)))))
  (princ "\nSelecione as Curvas (a ordem é a posição lateral): ")
  (setq ss (ssget '((-4 . "<OR") (0 . "LINE")
                    (-4 . "<AND") (0 . "LWPOLYLINE") (-4 . "<NOT") (-4 . "&") (70 . 1) (-4 . "NOT>") (-4 . "AND>")
                    (-4 . "OR>"))))
  (if (and ss (> (sslength ss) 1)
           (setq pini (getpoint "\nIndique o ponto de início do trajeto: ")))
    (progn
      (setq t0 (getvar "MILLISECS") i 0 pini (mn:2d pini))
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) d (mn:dados e))
        (if (/= "LINE" (cdr (assoc 0 (caddr d)))) (setq d (mn:fixa d)))
        (if (and (cdr (car d)) (> (distance (car (car d)) (last (car d))) 1e-6))
          (setq dados (cons d dados) enames (cons e enames))))
      ;; direção dominante e ordem lateral
      (setq th (mn:axial dados) u (list (cos th) (sin th)) n (list (- (sin th)) (cos th))
            lats (mapcar '(lambda (d) (mn:dot n (mn:esc (mn:add (car (car d)) (last (car d))) 0.5))) dados)
            ord  (vl-sort-i lats '<)
            dados  (mapcar '(lambda (k) (nth k dados)) ord)
            enames (mapcar '(lambda (k) (nth k enames)) ord)
            lats   (mapcar '(lambda (k) (nth k lats)) ord)
            esp    (mn:mediana (mapcar '- (cdr lats) (reverse (cdr (reverse lats))))))
      ;; começa pela ponta mais perto do clique (primeira ou última linha)
      (setq prim (car dados) ult (last dados))
      (if (< (min (distance pini (car (car ult))) (distance pini (last (car ult))))
             (min (distance pini (car (car prim))) (distance pini (last (car prim)))))
        (setq dados (reverse dados) enames (reverse enames) prim (car dados)))
      ;; sentido da 1a linha: sai da ponta mais perto do clique
      (setq sg (if (< (distance pini (car (car prim))) (distance pini (last (car prim))))
                 (mn:dot (mn:sub (last (car prim)) (car (car prim))) u)
                 (mn:dot (mn:sub (car (car prim)) (last (car prim))) u))
            sg (if (< sg 0.0) -1.0 1.0))
      ;; trajetos
      (setq seqs (cond
                   ((= *MN-PADRAO* "C")
                    (initget "Sim Nao")
                    (setq cont (/= "Nao" (getkword "\nDeseja que as manobras em caracol sejam contínuas? (conectadas) [Sim/Nao] <Sim>: ")))
                    (mn:ordem-caracol (length dados) (max esp 1e-6) *MN-RAIO* cont))
                   ((= *MN-PADRAO* "5") (mn:ordem-13524 (length dados)))
                   (T (mn:ordem-passo (length dados) (max 1 *MN-PASSO*)))))
      ;; corte pela bordadura: afastamento + maior profundidade de manobra
      (if bord
        (progn
          (setq dd (+ *MN-AFAST* (mn:prof-max seqs lats *MN-RAIO*))
                interno (mn:interno bord dd))
          (if interno
            (progn
              (setq ipts (mn:amostra interno)
                    dados (mapcar '(lambda (d / c) (if (setq c (mn:corta d interno ipts)) c d)) dados))
              (vla-delete interno)))))
      ;; monta os trajetos
      (setq lay (if (not *MN-JUNTAR*) (mn:layer-manobras)) nman 0 nu 0 no 0 comp 0.0 ntray 0)
      (foreach s seqs
        (setq tray nil orient sg m 0)
        (foreach k s
          (setq d (nth k dados)
                pts (car d) sb (cadr d))
          ;; sentido alternado: a m-ésima linha do trajeto vai em sg.(-1)^m
          (if (< (* orient (mn:dot (mn:sub (last pts) (car pts)) u)) 0.0)
            (setq d (mn:inverte pts sb) pts (car d) sb (cadr d)))
          (if tray
            (progn
              (setq p (last (car tray))
                    h (mn:tang-fim (car tray) (cadr tray))
                    q (car pts)
                    m (mn:manobra p h q *MN-RAIO*)
                    m (append (mn:discretiza (car m) (cadr m) *MN-DMAX*) (cddr m))
                    nman (1+ nman)
                    comp (+ comp (mn:comprimento (car m) (cadr m))))
              (if (= "U" (cadddr m)) (setq nu (1+ nu)) (setq no (1+ no)))
              (if *MN-JUNTAR*
                (setq tray (list (append (car tray) (cdr (car m)) (cdr pts))
                                 (append (cadr tray) (cadr m) sb)))
                (progn
                  (mn:mk-lw (car m) (append (cadr m) '(0.0)) (list (cons 8 lay)))
                  (setq tray (list pts sb)))))
            (setq tray (list pts sb)))
          (if (not *MN-JUNTAR*)                         ; linha (cortada) avulsa
            (if (or bord) (mn:mk-lw pts (append sb '(0.0)) (mn:props (caddr (nth k dados))))))
          (setq orient (- orient)))
        (if *MN-JUNTAR*
          (progn
            (mn:mk-lw (car tray) (append (cadr tray) '(0.0)) (mn:props (caddr (nth (car s) dados))))
            (setq ntray (1+ ntray)))))
      (if (and *MN-APAGAR* (or *MN-JUNTAR* bord)) (foreach e enames (entdel e)))
      (princ (strcat "\n" (itoa (length dados)) " linha(s), " (itoa nman) " manobra(s) ("
                     (itoa nu) " em U, " (itoa no) " em ômega), comprimento total "
                     (rtos comp 2 1) " m"
                     (if *MN-JUNTAR* (strcat ", " (itoa ntray) " trajeto(s) contínuo(s)") "")
                     (if (and *MN-CORTAR* (not bord)) "; sem bordadura: linhas não cortadas" "")
                     ". [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))))
  (princ)
)

;;; média axial (ângulo) das linhas
(defun mn:axial (dados / c s a l)
  (setq c 0.0 s 0.0)
  (foreach d dados
    (setq a (angle (car (car d)) (last (car d))) l (distance (car (car d)) (last (car d)))
          c (+ c (* l (cos (* 2.0 a)))) s (+ s (* l (sin (* 2.0 a))))))
  (if (and (equal c 0.0 1e-12) (equal s 0.0 1e-12)) 0.0 (/ (atan s c) 2.0))
)

(defun mn:mediana (l / s n)
  (setq s (vl-sort-i l '<) n (length l))
  (if (> n 0) (abs (nth (nth (/ n 2) s) l)) 1.0)
)

;;; maior profundidade das manobras planejadas
(defun mn:prof-max (seqs lats r / m)
  (setq m r)
  (foreach s seqs
    (mapcar '(lambda (a b) (setq m (max m (mn:profundidade (abs (- (nth b lats) (nth a lats))) r))))
            s (cdr s)))
  m
)

(defun mn:comprimento (pts sb / s)
  (setq s 0.0)
  (mapcar '(lambda (p q b)
             (setq s (+ s (if (equal b 0.0 1e-12)
                            (distance p q)
                            (* (/ (* (distance p q) (1+ (* b b))) (* 4.0 (abs b))) (* 4.0 (abs (atan b))))))))
          pts (cdr pts) sb)
  s
)

;;; vértices do polígono interno (arcos com 8 subdivisões) p/ ponto-dentro
(defun mn:amostra (o / ed v b res i n j)
  (setq ed (entget (vlax-vla-object->ename o)) i 0)
  (foreach g ed
    (cond ((= (car g) 10) (setq v (cons (cdr g) v)))
          ((= (car g) 42) (setq b (cons (cdr g) b)))))
  (setq v (reverse v) b (reverse b))
  (foreach p v
    (setq res (cons p res))
    (if (/= 0.0 (car b))
      (progn (setq j 1)
             (repeat 7 (setq res (cons (mn:2d (vlax-curve-getPointAtParam o (+ i (/ j 8.0)))) res) j (1+ j)))))
    (setq b (cdr b) i (1+ i)))
  (reverse res)
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun mn:pasta ()
  (cond (*FT-DEV-DIR*)
        ((findfile "Manobras.dcl") (vl-filename-directory (findfile "Manobras.dcl"))))
)
(defun mn:num (k / s) (setq s (get_tile k)) (if s (distof (vl-string-translate "," "." s) 2)))

(defun mn:le-tiles (/ r a m p)
  (setq r (mn:num "raio") a (mn:num "afast") m (mn:num "dmax") p (atoi (get_tile "passo")))
  (cond
    ((not (and r (> r 0.0))) (set_tile "error" "Raio de giro inválido (> 0).") nil)
    ((not (and a (>= a 0.0))) (set_tile "error" "Afastamento inválido (>= 0).") nil)
    ((not (and m (>= m 0.0))) (set_tile "error" "Distância máxima entre vértices inválida (>= 0).") nil)
    ((< p 1) (set_tile "error" "\"A cada\" deve ser >= 1.") nil)
    (T (setq *MN-RAIO* r *MN-AFAST* a *MN-DMAX* m *MN-PASSO* p
             *MN-PADRAO* (get_tile "padrao")
             *MN-CORTAR* (= "1" (get_tile "cortar"))
             *MN-JUNTAR* (= "1" (get_tile "juntar"))
             *MN-APAGAR* (= "1" (get_tile "apagar")))
       (mn:grava-env)
       T))
)

(defun c:MANOBRAS (/ *error* doc dcl arq r)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (setq arq (if (mn:pasta) (strcat (mn:pasta) "\\Manobras.dcl")))
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo Manobras.dcl não encontrado.") (exit)))
  (setq dcl (load_dialog arq))
  (if (not (new_dialog "manobras" dcl)) (progn (alert "Erro ao abrir o diálogo.") (exit)))
  (set_tile "raio"   (rtos *MN-RAIO* 2 2))
  (set_tile "afast"  (rtos *MN-AFAST* 2 2))
  (set_tile "dmax"   (rtos *MN-DMAX* 2 2))
  (set_tile "passo"  (itoa *MN-PASSO*))
  (set_tile "padrao" *MN-PADRAO*)
  (set_tile "cortar" (if *MN-CORTAR* "1" "0"))
  (set_tile "juntar" (if *MN-JUNTAR* "1" "0"))
  (set_tile "apagar" (if *MN-APAGAR* "1" "0"))
  (mode_tile "passo" (if (= *MN-PADRAO* "N") 0 1))
  (action_tile "padrao" "(mode_tile \"passo\" (if (= $value \"N\") 0 1))")
  (action_tile "accept" "(if (mn:le-tiles) (done_dialog 1))")
  (action_tile "cancel" "(done_dialog 0)")
  (setq r (start_dialog))
  (unload_dialog dcl)
  (setq dcl nil)
  (if (= r 1)
    (progn (vla-StartUndoMark doc) (mn:executa) (vla-EndUndoMark doc)))
  (princ)
)

(princ "\nManobras carregado. Comando: MANOBRAS")
(princ)
