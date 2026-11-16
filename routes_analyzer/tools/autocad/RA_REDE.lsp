;;; =====================================================================
;;; RA_REDE.lsp - Topologia da rede de rotas (Routes Analyzer)
;;;
;;; Ajuda a desenhar e corrigir a camada da rede no AutoCAD para que:
;;;   - todas as linhas estejam conectadas por vertices em comum;
;;;   - todos os entroncamentos e cruzamentos estejam quebrados;
;;;   - nao existam pseudo-nos (duas linhas iguais emendadas sem motivo);
;;;   - nao existam pontas soltas "por pouco" (undershoot / overshoot).
;;; Requisitos completos: docs/REQUISITOS_REDE.md
;;;
;;; Compativel com AutoCAD completo e AutoCAD LT 2024+ (nao usa ActiveX).
;;; Carregar: APPLOAD -> RA_REDE.lsp      Ajuda: RA_AJUDA
;;; Unidades do desenho: metros.
;;; =====================================================================

;;; ---------------------------------------------------------------------
;;; Configuracao (valores padrao; altere aqui ou com RA_CONFIG)
;;; ---------------------------------------------------------------------
(or *RA:LAYERS*    (setq *RA:LAYERS*    "REDE*"))      ; filtro das camadas da rede
(or *RA:DRAWLAYER* (setq *RA:DRAWLAYER* "REDE_ROTAS")) ; camada usada pelo RD
(or *RA:TOL*       (setq *RA:TOL*       0.001))        ; abaixo disto e o mesmo ponto (m)
(or *RA:GAP*       (setq *RA:GAP*       2.0))          ; ponta solta suspeita ate (m)
(or *RA:MARK*      (setq *RA:MARK*      2.0))          ; raio dos marcadores (m)
(or *RA:STEP*      (setq *RA:STEP*      5.0))          ; segmento maximo ao converter arcos (m)
(or *RA:ONEWAY*    (setq *RA:ONEWAY*    "*MAO*UNICA*,*_MU")) ; camadas de mao unica
(setq *RA:ERR* "RA_ERROS"            ; camada dos marcadores de erro
      *RA:EXC* "RA_SEM_CONEXAO")     ; camada das excecoes (viadutos)

;;; ---------------------------------------------------------------------
;;; Geometria
;;; ---------------------------------------------------------------------
(defun ra:2d (p) (list (car p) (cadr p)))
(defun ra:sub (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun ra:add (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun ra:mul (a k) (list (* (car a) k) (* (cadr a) k)))
(defun ra:cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))
(defun ra:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun ra:len (a) (sqrt (ra:dot a a)))
(defun ra:msg (s) (princ (strcat "\n" s)))

;;; chave textual de um ponto, arredondada pela tolerancia
(defun ra:key (p)
  (strcat (rtos (/ (car p) *RA:TOL*) 2 0) "_" (rtos (/ (cadr p) *RA:TOL*) 2 0)))

;;; remove pontos consecutivos repetidos
(defun ra:dedup (pts / res)
  (foreach p pts
    (if (or (null res) (> (distance (car res) p) 1e-9)) (setq res (cons p res))))
  (reverse res))

(defun ra:plen (pts / s)
  (setq s 0.0)
  (while (cadr pts) (setq s (+ s (distance (car pts) (cadr pts))) pts (cdr pts)))
  s)

;;; ---------------------------------------------------------------------
;;; Leitura das entidades da rede
;;; registro: (idx ename tipo pts elevacao fechada dados)
;;; ---------------------------------------------------------------------
(defun ra:ss ()
  (ssget "_X" (list '(0 . "LINE,LWPOLYLINE,POLYLINE,ARC,SPLINE,ELLIPSE")
                    (cons 8 *RA:LAYERS*) '(410 . "Model"))))

(defun ra:read (e / ed typ pts el cl ok fl v vd)
  (setq ed (entget e '("*")) typ (cdr (assoc 0 ed)) ok T)
  (cond
    ((= typ "LINE")
     (setq pts (list (ra:2d (cdr (assoc 10 ed))) (ra:2d (cdr (assoc 11 ed))))
           el  (caddr (cdr (assoc 10 ed)))))
    ((= typ "LWPOLYLINE")
     (if (and (assoc 210 ed) (not (equal (cdr (assoc 210 ed)) '(0.0 0.0 1.0) 1e-9)))
       (setq ok "polilinha fora do plano XY"))
     (foreach g ed
       (cond ((= (car g) 10) (setq pts (cons (cdr g) pts)))
             ((and (= (car g) 42) (/= (cdr g) 0.0)) (setq ok "polilinha com arco (use RS)"))))
     (setq pts (reverse pts)
           el  (if (assoc 38 ed) (cdr (assoc 38 ed)) 0.0)
           cl  (= 1 (logand 1 (cdr (assoc 70 ed))))))
    ((= typ "POLYLINE")
     (setq fl (cdr (assoc 70 ed)) el (caddr (cdr (assoc 10 ed))))
     (if (/= 0 (logand fl 80))
       (setq ok "malha/face nao suportada")
       (progn
         (setq v (entnext e))
         (while (and v (= (cdr (assoc 0 (setq vd (entget v)))) "VERTEX"))
           (if (= 0 (logand (cdr (assoc 70 vd)) 16))
             (progn
               (setq pts (cons (ra:2d (cdr (assoc 10 vd))) pts))
               (if (and (assoc 42 vd) (/= 0.0 (cdr (assoc 42 vd))))
                 (setq ok "polilinha com arco (use RS)"))))
           (setq v (entnext v)))
         (setq pts (reverse pts) cl (= 1 (logand 1 fl))))))
    (T (setq ok (strcat typ " nao suportado (ARC: use RS; SPLINE: converta em polilinha)"))))
  (if (and cl (> (length pts) 2)) (setq pts (append pts (list (car pts)))))
  (setq pts (ra:dedup pts))
  (if (and (eq ok T) (< (length pts) 2)) (setq ok "linha de comprimento zero"))
  (if (eq ok T) (list e typ pts (if el el 0.0) cl ed) ok))

;;; retorna (lista-de-registros lista-de-(ename motivo))
(defun ra:load (ss / i e r ents bad idx lay)
  (setq i 0 idx 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i) lay (strcase (cdr (assoc 8 (entget e)))))
      (if (not (member lay (list (strcase *RA:ERR*) (strcase *RA:EXC*))))
        (progn
          (setq r (ra:read e))
          (if (listp r)
            (setq ents (cons (cons idx r) ents) idx (1+ idx))
            (setq bad (cons (list e r) bad)))))))
  (list (reverse ents) bad))

;;; ---------------------------------------------------------------------
;;; Criacao / alteracao de entidades
;;; ---------------------------------------------------------------------
(defun ra:props (ed / res)
  (foreach c '(8 6 62 370 48 420 430 440)
    (if (assoc c ed) (setq res (cons (assoc c ed) res))))
  (reverse res))

;;; cria LINE (se o original era LINE e tem 2 pontos) ou LWPOLYLINE,
;;; copiando camada, cor, tipo de linha e XDATA do original
(defun ra:make (r pts / ed el xd)
  (setq ed (nth 6 r) el (nth 4 r)
        xd (if (assoc -3 ed) (list (assoc -3 ed))))
  (if (and (= (nth 2 r) "LINE") (= (length pts) 2))
    (entmakex (append (list '(0 . "LINE")) (ra:props ed)
                      (list (cons 10 (list (car (car pts)) (cadr (car pts)) el))
                            (cons 11 (list (car (cadr pts)) (cadr (cadr pts)) el)))
                      xd))
    (entmakex (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")) (ra:props ed)
                      (list '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 0) (cons 38 el))
                      (mapcar '(lambda (p) (cons 10 (ra:2d p))) pts)
                      xd))))

;;; move a ponta 'S (inicio) ou 'E (fim) de uma entidade para np
(defun ra:set-end (r which np / e ed c old n i v vd fv lv)
  (setq e (nth 1 r) ed (entget e))
  (cond
    ((= (nth 2 r) "LINE")
     (setq c (if (eq which 'S) 10 11) old (assoc c ed))
     (entmod (subst (cons c (list (car np) (cadr np) (caddr (cdr old)))) old ed)))
    ((= (nth 2 r) "LWPOLYLINE")
     (setq n (if (eq which 'S) 0 (1- (cdr (assoc 90 ed)))) i -1)
     (entmod (mapcar '(lambda (g)
                        (if (and (= (car g) 10) (= (setq i (1+ i)) n)) (cons 10 (ra:2d np)) g))
                     ed)))
    ((= (nth 2 r) "POLYLINE")
     (setq v (entnext e))
     (while (and v (= (cdr (assoc 0 (setq vd (entget v)))) "VERTEX"))
       (if (= 0 (logand (cdr (assoc 70 vd)) 16)) (progn (or fv (setq fv v)) (setq lv v)))
       (setq v (entnext v)))
     (setq vd (entget (if (eq which 'S) fv lv)) old (assoc 10 vd))
     (entmod (subst (cons 10 (list (car np) (cadr np) (caddr (cdr old)))) old vd))
     (entupd e))))

;;; ---------------------------------------------------------------------
;;; Segmentos e intersecoes (varredura ordenada por X)
;;; segmento: (xmin xmax ymin ymax p1 p2 idx-entidade idx-segmento)
;;; ---------------------------------------------------------------------
(defun ra:segs (ents / segs pts i p1 p2)
  (foreach r ents
    (setq pts (nth 3 r) i 0)
    (while (cadr pts)
      (setq p1 (car pts) p2 (cadr pts)
            segs (cons (list (min (car p1) (car p2)) (max (car p1) (car p2))
                             (min (cadr p1) (cadr p2)) (max (cadr p1) (cadr p2))
                             p1 p2 (car r) i)
                       segs)
            pts (cdr pts) i (1+ i))))
  (vl-sort segs '(lambda (a b) (< (car a) (car b)))))

;;; intersecao entre dois segmentos:
;;;   ('X idxA posA idxB posB ponto)  - cruzam/tocam (pos = segmento + parametro)
;;;   ('O idxA idxB ponto)            - sobrepostos (colineares)
(defun ra:segx (a b / p r q s la lb den qp ta ub ea eb pt d t0 t1 lo hi)
  (setq p (nth 4 a) r (ra:sub (nth 5 a) p)
        q (nth 4 b) s (ra:sub (nth 5 b) q)
        la (ra:len r) lb (ra:len s))
  (cond
    ((or (< la 1e-12) (< lb 1e-12)) nil)
    ((> (abs (setq den (ra:cross r s))) (* 1e-10 la lb))
     (setq qp (ra:sub q p)
           ta (/ (ra:cross qp s) den)
           ub (/ (ra:cross qp r) den)
           ea (/ *RA:TOL* la)
           eb (/ *RA:TOL* lb))
     (if (and (>= ta (- ea)) (<= ta (+ 1.0 ea)) (>= ub (- eb)) (<= ub (+ 1.0 eb)))
       (progn
         (cond ((<= ta ea) (setq ta 0.0 pt p))
               ((>= ta (- 1.0 ea)) (setq ta 1.0 pt (nth 5 a))))
         (cond ((<= ub eb) (setq ub 0.0) (or pt (setq pt q)))
               ((>= ub (- 1.0 eb)) (setq ub 1.0) (or pt (setq pt (nth 5 b)))))
         (or pt (setq pt (ra:add p (ra:mul r ta))))
         (list 'X (nth 6 a) (+ (nth 7 a) ta) (nth 6 b) (+ (nth 7 b) ub) pt))))
    (T
     (setq qp (ra:sub q p) d (/ (abs (ra:cross qp r)) la))
     (if (< d *RA:TOL*)
       (progn
         (setq t0 (/ (ra:dot qp r) (* la la))
               t1 (/ (ra:dot (ra:sub (nth 5 b) p) r) (* la la))
               lo (max 0.0 (min t0 t1))
               hi (min 1.0 (max t0 t1)))
         (if (> (* la (- hi lo)) *RA:TOL*)
           (list 'O (nth 6 a) (nth 6 b) (ra:add p (ra:mul r (/ (+ lo hi) 2.0))))))))))

(defun ra:hits (segs / a b rest h hits)
  (while segs
    (setq a (car segs) segs (cdr segs) rest segs)
    (while (and rest (<= (car (car rest)) (+ (cadr a) *RA:TOL*)))
      (setq b (car rest) rest (cdr rest))
      (if (and (/= (nth 6 a) (nth 6 b))
               (<= (nth 2 b) (+ (nth 3 a) *RA:TOL*))
               (<= (nth 2 a) (+ (nth 3 b) *RA:TOL*))
               (setq h (ra:segx a b)))
        (setq hits (cons h hits)))))
  hits)

;;; posicao corresponde a uma das pontas da entidade?
(defun ra:isend (r pos)
  (or (< pos 1e-9) (> pos (- (length (nth 3 r)) 1 1e-9))))

;;; pontos de excecao (viadutos): entidades na camada RA_SEM_CONEXAO
(defun ra:exc-pts (/ ss i ed res)
  (if (setq ss (ssget "_X" (list (cons 8 *RA:EXC*))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ed (entget (ssname ss i)) i (1+ i))
        (if (assoc 10 ed) (setq res (cons (ra:2d (cdr (assoc 10 ed))) res))))))
  res)

(defun ra:is-exc (pt excs)
  (vl-some '(lambda (x) (< (distance x pt) (max *RA:GAP* *RA:MARK*))) excs))

;;; entroncamentos sem quebra: (tipo ponto idxA posA|nil idxB posB|nil)
;;; tipo "X" = cruzamento, "T" = uma linha chega no meio da outra.
;;; pos nil = naquela entidade o ponto ja e uma ponta (nao precisa quebrar)
(defun ra:junctions (ents hits excs / res ra rb ea eb)
  (foreach h hits
    (if (eq (car h) 'X)
      (progn
        (setq ra (nth (nth 1 h) ents) rb (nth (nth 3 h) ents)
              ea (ra:isend ra (nth 2 h)) eb (ra:isend rb (nth 4 h)))
        (if (and (not (and ea eb)) (not (ra:is-exc (nth 5 h) excs)))
          (setq res (cons (list (if (or ea eb) "T" "X") (nth 5 h)
                                (nth 1 h) (if ea nil (nth 2 h))
                                (nth 3 h) (if eb nil (nth 4 h)))
                          res))))))
  res)

;;; ---------------------------------------------------------------------
;;; Quebra nos entroncamentos
;;; ---------------------------------------------------------------------
(defun ra:alist-add (tbl k v / a)
  (if (setq a (assoc k tbl))
    (subst (cons k (cons v (cdr a))) a tbl)
    (cons (list k v) tbl)))

(defun ra:cuts (juncs / tbl)
  (foreach j juncs
    (if (nth 3 j) (setq tbl (ra:alist-add tbl (nth 2 j) (cons (nth 3 j) (nth 1 j)))))
    (if (nth 5 j) (setq tbl (ra:alist-add tbl (nth 4 j) (cons (nth 5 j) (nth 1 j))))))
  tbl)

;;; divide a lista de pontos nas posicoes de corte -> lista de pedacos
(defun ra:pieces (pts cuts / items i m res cur)
  (setq i 0)
  (foreach p pts (setq items (cons (list (float i) p nil) items) i (1+ i)))
  (foreach c cuts (setq items (cons (list (car c) (cdr c) T) items)))
  (setq items (vl-sort items '(lambda (a b) (< (car a) (car b)))))
  (foreach it items
    (if (and m (< (distance (cadr it) (cadr (car m))) *RA:TOL*))
      (if (caddr it) (setq m (cons it (cdr m))))
      (setq m (cons it m))))
  (setq m (reverse m) cur (list (cadr (car m))))
  (foreach it (cdr m)
    (setq cur (cons (cadr it) cur))
    (if (caddr it) (setq res (cons (reverse cur) res) cur (list (cadr it)))))
  (setq res (cons (reverse cur) res))
  (vl-remove-if '(lambda (pc) (< (length pc) 2)) (reverse res)))

(defun ra:apply-cuts (ents tbl / n r pcs)
  (setq n 0)
  (foreach c tbl
    (setq r (nth (car c) ents) pcs (ra:pieces (nth 3 r) (cdr c)))
    (if (> (length pcs) 1)
      (progn
        (foreach pc pcs (ra:make r pc))
        (entdel (nth 1 r))
        (setq n (1+ n)))))
  n)

;;; quebra todas as linhas nos entroncamentos; only = ename para limitar
;;; aos entroncamentos que envolvem aquela entidade (usado pelo RD)
(defun ra:break-all (only / ld ents segs juncs)
  (setq ld (ra:load (ra:ss)) ents (car ld))
  (if ents
    (progn
      (setq segs (ra:segs ents)
            juncs (ra:junctions ents (ra:hits segs) (ra:exc-pts)))
      (if only
        (setq juncs (vl-remove-if-not
                      '(lambda (j) (or (eq (nth 1 (nth (nth 2 j) ents)) only)
                                       (eq (nth 1 (nth (nth 4 j) ents)) only)))
                      juncs)))
      (ra:apply-cuts ents (ra:cuts juncs)))
    0))

;;; ---------------------------------------------------------------------
;;; Nos (vertices agrupados por posicao)
;;; item: (chave idx-entidade ponta('S/'E/nil) ponto)
;;; ---------------------------------------------------------------------
(defun ra:vkeys (ents / res pts n i)
  (foreach r ents
    (setq pts (nth 3 r) n (1- (length pts)) i 0)
    (if (nth 5 r)
      (foreach p (cdr pts) (setq res (cons (list (ra:key p) (car r) nil p) res)))
      (foreach p pts
        (setq res (cons (list (ra:key p) (car r) (cond ((= i 0) 'S) ((= i n) 'E)) p) res)
              i (1+ i)))))
  (vl-sort res '(lambda (a b) (< (car a) (car b)))))

(defun ra:groups (sorted / res cur)
  (foreach it sorted
    (if (and cur (= (car it) (car (car cur))))
      (setq cur (cons it cur))
      (progn (if cur (setq res (cons cur res))) (setq cur (list it)))))
  (if cur (setq res (cons cur res)))
  res)

;;; mesmas propriedades (camada, cor, tipo de linha, XDATA)?
(defun ra:compat (a b)
  (and (equal (ra:props (nth 6 a)) (ra:props (nth 6 b)))
       (equal (assoc -3 (nth 6 a)) (assoc -3 (nth 6 b)))))

;;; as duas linhas ligam os mesmos dois pontos (duplicada ou laco)?
(defun ra:same-ends (a b / ka kb)
  (setq ka (list (ra:key (car (nth 3 a))) (ra:key (last (nth 3 a))))
        kb (list (ra:key (car (nth 3 b))) (ra:key (last (nth 3 b)))))
  (or (equal ka kb) (equal ka (reverse kb))))

;;; pseudo-no: exatamente duas pontas de linhas diferentes e compativeis,
;;; sem nenhuma outra linha passando pelo ponto
(defun ra:pseudo-p (g ents jkeys / a b)
  (and (= (length g) 2)
       (nth 2 (car g)) (nth 2 (cadr g))
       (/= (nth 1 (car g)) (nth 1 (cadr g)))
       (not (member (car (car g)) jkeys))
       (setq a (nth (nth 1 (car g)) ents) b (nth (nth 1 (cadr g)) ents))
       (ra:compat a b)
       (not (ra:same-ends a b))))

;;; ponto mais proximo em OUTRAS entidades, ate gap.
;;; Retorna (distancia ponto e-vertice?) ou nil. Prefere vertice se estiver
;;; quase tao perto quanto o ponto mais proximo na linha.
(defun ra:nearest (pt idx segs gap / x y s p1 p2 r l2 tt f d v bdv bv bds bs)
  (setq x (car pt) y (cadr pt) bdv gap bds gap)
  (while (and segs (<= (car (car segs)) (+ x gap)))
    (setq s (car segs) segs (cdr segs))
    (if (and (/= (nth 6 s) idx) (>= (cadr s) (- x gap))
             (<= (nth 2 s) (+ y gap)) (>= (nth 3 s) (- y gap)))
      (progn
        (setq p1 (nth 4 s) p2 (nth 5 s))
        (foreach v (list p1 p2)
          (if (< (setq d (distance v pt)) bdv) (setq bdv d bv v)))
        (setq r (ra:sub p2 p1) l2 (ra:dot r r))
        (if (> l2 0.0)
          (progn
            (setq tt (max 0.0 (min 1.0 (/ (ra:dot (ra:sub pt p1) r) l2)))
                  f  (ra:add p1 (ra:mul r tt))
                  d  (distance f pt))
            (if (< d bds) (setq bds d bs f)))))))
  (cond
    ((and bv (or (null bs) (<= bdv (max (* 1.5 bds) (* 10.0 *RA:TOL*))))) (list bdv bv T))
    (bs (list bds bs nil))))

;;; ponta solta suspeita: ponta sozinha com outra linha a menos de GAP
(defun ra:dangle (g segs / it nr)
  (setq it (car g))
  (if (and (= (length g) 1) (nth 2 it))
    (progn
      (setq nr (ra:nearest (nth 3 it) (nth 1 it) segs *RA:GAP*))
      (if (and nr (> (car nr) 1e-9) (or (caddr nr) (> (car nr) *RA:TOL*))) nr))))

;;; ---------------------------------------------------------------------
;;; Componentes conexos (union-find em simbolos RA_P<n>)
;;; retorna lista (raiz comprimento ponto), maior primeiro
;;; ---------------------------------------------------------------------
(defun ra:par (i) (eval (read (strcat "RA_P" (itoa i)))))
(defun ra:setpar (i v) (set (read (strcat "RA_P" (itoa i))) v))
(defun ra:find (i / p) (while (/= (setq p (ra:par i)) i) (setq i p)) i)
(defun ra:union (a b)
  (setq a (ra:find a) b (ra:find b))
  (if (/= a b) (ra:setpar (max a b) (min a b))))

(defun ra:components (ents groups / lens root a)
  (foreach r ents (ra:setpar (car r) (car r)))
  (foreach g groups (foreach it (cdr g) (ra:union (nth 1 (car g)) (nth 1 it))))
  (foreach r ents
    (setq root (ra:find (car r)) a (assoc root lens))
    (setq lens (if a
                 (subst (list root (+ (cadr a) (ra:plen (nth 3 r))) (caddr a)) a lens)
                 (cons (list root (ra:plen (nth 3 r)) (car (nth 3 r))) lens))))
  (foreach r ents (ra:setpar (car r) nil))
  (vl-sort lens '(lambda (a b) (> (cadr a) (cadr b)))))

;;; ---------------------------------------------------------------------
;;; Duplicadas (mesmos vertices, em qualquer sentido)
;;; ---------------------------------------------------------------------
(defun ra:sig (pts) (apply 'strcat (mapcar '(lambda (p) (strcat (ra:key p) ";")) pts)))

(defun ra:dups (ents / l prev res s1 s2)
  (foreach r ents
    (setq s1 (ra:sig (nth 3 r)) s2 (ra:sig (reverse (nth 3 r)))
          l  (cons (cons (if (< s1 s2) s1 s2) (car r)) l)))
  (setq l (vl-sort l '(lambda (a b) (< (car a) (car b)))))
  (foreach it l
    (if (and prev (= (car it) (car prev))) (setq res (cons (cdr it) res)) (setq prev it)))
  res)

;;; ---------------------------------------------------------------------
;;; Marcadores
;;; ---------------------------------------------------------------------
(defun ra:mklayer (name col)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 name) '(70 . 0) (cons 62 col) '(6 . "Continuous") '(290 . 0)))))

(defun ra:mark (pt col)
  (entmakex (list '(0 . "CIRCLE") (cons 8 *RA:ERR*) (cons 62 col)
                  (list 10 (car pt) (cadr pt) 0.0) (cons 40 *RA:MARK*))))

(defun ra:clear-marks (/ ss i)
  (if (setq ss (ssget "_X" (list (cons 8 *RA:ERR*))))
    (progn (setq i 0) (repeat (sslength ss) (entdel (ssname ss i)) (setq i (1+ i)))))
  (setq *ra-ix* 0))

(defun ra:cname (c)
  (cond ((= c 1)  "cruzamento sem quebra")
        ((= c 30) "entroncamento (T) sem quebra")
        ((= c 2)  "pseudo-no")
        ((= c 6)  "ponta solta suspeita")
        ((= c 5)  "sobreposicao / duplicada")
        ((= c 3)  "parte desconectada da rede principal")
        ((= c 4)  "entidade nao suportada")
        (T "?")))

;;; ---------------------------------------------------------------------
;;; Controle de UNDO / erros
;;; ---------------------------------------------------------------------
(defun ra:err (msg)
  (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
    (princ (strcat "\nRA erro: " msg)))
  (command-s "_.UNDO" "_E")
  (if *ra-old* (progn (setvar "CMDECHO" (car *ra-old*)) (setvar "OSMODE" (cadr *ra-old*))))
  (setq *error* *ra-olderr*)
  (princ))

(defun ra:start ()
  (setq *ra-old* (list (getvar "CMDECHO") (getvar "OSMODE"))
        *ra-olderr* *error*
        *error* ra:err)
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE"))

(defun ra:end ()
  (command "_.UNDO" "_E")
  (setvar "CMDECHO" (car *ra-old*))
  (setvar "OSMODE" (cadr *ra-old*))
  (setq *error* *ra-olderr*)
  (princ))

;;; ---------------------------------------------------------------------
;;; Verificacao
;;; ---------------------------------------------------------------------
(defun ra:verify (/ ld ents bad segs hits juncs seen groups dups comps tot k
                    nT nX nP nD nO nU nTot)
  (ra:clear-marks)
  (ra:mklayer *RA:ERR* 1)
  (setq ld (ra:load (ra:ss)) ents (car ld) bad (cadr ld)
        nT 0 nX 0 nP 0 nD 0 nO 0 nU (length bad))
  (foreach b bad (ra:mark (ra:2d (cdr (assoc 10 (entget (car b))))) 4))
  (if (null ents)
    (ra:msg (strcat "Nenhuma linha nas camadas \"" *RA:LAYERS* "\". Ajuste com RA_CONFIG."))
    (progn
      (setq segs  (ra:segs ents)
            hits  (ra:hits segs)
            juncs (ra:junctions ents hits (ra:exc-pts)))
      (foreach j juncs
        (setq k (ra:key (nth 1 j)))
        (if (not (member k seen))
          (progn
            (setq seen (cons k seen))
            (if (= (car j) "T")
              (progn (setq nT (1+ nT)) (ra:mark (nth 1 j) 30))
              (progn (setq nX (1+ nX)) (ra:mark (nth 1 j) 1))))))
      (foreach h hits
        (if (eq (car h) 'O) (progn (setq nO (1+ nO)) (ra:mark (nth 3 h) 5))))
      (setq groups (ra:groups (ra:vkeys ents)))
      (foreach g groups
        (cond
          ((ra:pseudo-p g ents seen) (setq nP (1+ nP)) (ra:mark (nth 3 (car g)) 2))
          ((ra:dangle g segs) (setq nD (1+ nD)) (ra:mark (nth 3 (car g)) 6))))
      (setq dups (ra:dups ents))
      (foreach d dups (ra:mark (car (nth 3 (nth d ents))) 5))
      (setq comps (ra:components ents groups) tot 0.0)
      (foreach c comps (setq tot (+ tot (cadr c))))
      (foreach c (cdr comps) (ra:mark (caddr c) 3))
      (setq nTot (+ nX nT nP nD nO nU (length dups) (1- (length comps))))
      (ra:msg "========== Routes Analyzer - verificacao da rede ==========")
      (ra:msg (strcat "Camadas: " *RA:LAYERS* "   Linhas: " (itoa (length ents))
                      "   Comprimento: " (rtos (/ tot 1000.0) 2 3) " km"))
      (ra:msg (strcat "  [vermelho] Cruzamentos sem quebra ............ " (itoa nX)))
      (ra:msg (strcat "  [laranja]  Entroncamentos (T) sem quebra ..... " (itoa nT)))
      (ra:msg (strcat "  [amarelo]  Pseudo-nos ......................... " (itoa nP)))
      (ra:msg (strcat "  [magenta]  Pontas soltas suspeitas (< " (rtos *RA:GAP* 2 2) " m) .. " (itoa nD)))
      (ra:msg (strcat "  [azul]     Sobreposicoes / duplicadas ......... " (itoa (+ nO (length dups)))))
      (ra:msg (strcat "  [ciano]    Entidades nao suportadas ........... " (itoa nU)))
      (ra:msg (strcat "  [verde]    Partes desconectadas ............... " (itoa (1- (length comps)))
                      "  (principal = " (rtos (if (> tot 0.0) (* 100.0 (/ (cadr (car comps)) tot)) 100.0) 2 1)
                      "% do comprimento)"))
      (if (= nTot 0)
        (ra:msg "Rede OK: conectada, quebrada nos entroncamentos e sem pseudo-nos.")
        (ra:msg "Use RN para ir ao proximo marcador e RC para corrigir automaticamente."))))
  (princ))

;;; ---------------------------------------------------------------------
;;; Correcoes
;;; ---------------------------------------------------------------------
(defun ra:del-dups (/ ld ents n)
  (setq ld (ra:load (ra:ss)) ents (car ld) n 0)
  (foreach d (ra:dups ents) (entdel (nth 1 (nth d ents))) (setq n (1+ n)))
  n)

;;; leva pontas soltas ate a linha/vertice mais proximo (dentro de GAP)
(defun ra:snap-dangles (/ ld ents segs done n it nr)
  (setq ld (ra:load (ra:ss)) ents (car ld) n 0)
  (if ents
    (progn
      (setq segs (ra:segs ents))
      (foreach g (ra:groups (ra:vkeys ents))
        (if (and (not (member (car (car g)) done)) (setq nr (ra:dangle g segs)))
          (progn
            (setq it (car g))
            (ra:set-end (nth (nth 1 it) ents) (nth 2 it) (cadr nr))
            (setq done (cons (ra:key (cadr nr)) done) n (1+ n)))))))
  n)

(defun ra:norev (r)
  (or (assoc -3 (nth 6 r))
      (wcmatch (strcase (cdr (assoc 8 (nth 6 r)))) (strcase *RA:ONEWAY*))))

;;; emenda duas linhas num pseudo-no; wa/wb = qual ponta esta no no
(defun ra:join2 (ra wa rb wb / pa pb pts rev)
  (setq pa (nth 3 ra) pb (nth 3 rb))
  (cond
    ((and (eq wa 'E) (eq wb 'S)) (setq pts (append pa (cdr pb))))
    ((and (eq wa 'S) (eq wb 'E)) (setq pts (append pb (cdr pa))))
    ((eq wa 'E) (setq rev T pts (append pa (cdr (reverse pb)))))
    (T (setq rev T pts (append (reverse pa) (cdr pb)))))
  (if (and rev (or (ra:norev ra) (ra:norev rb)))
    nil   ; inverteria o sentido de uma via de mao unica / com dados
    (progn
      (ra:make ra pts)
      (entdel (nth 1 ra))
      (entdel (nth 1 rb))
      T)))

(defun ra:join-pass (/ ld ents segs juncs jkeys used n a b)
  (setq ld (ra:load (ra:ss)) ents (car ld) n 0)
  (if ents
    (progn
      (setq segs  (ra:segs ents)
            juncs (ra:junctions ents (ra:hits segs) (ra:exc-pts))
            jkeys (mapcar '(lambda (j) (ra:key (nth 1 j))) juncs))
      (foreach g (ra:groups (ra:vkeys ents))
        (if (ra:pseudo-p g ents jkeys)
          (progn
            (setq a (car g) b (cadr g))
            (if (and (not (member (nth 1 a) used)) (not (member (nth 1 b) used))
                     (ra:join2 (nth (nth 1 a) ents) (nth 2 a) (nth (nth 1 b) ents) (nth 2 b)))
              (setq used (cons (nth 1 a) (cons (nth 1 b) used)) n (1+ n))))))))
  n)

(defun ra:join-all (/ n k)
  (setq n 0)
  (while (> (setq k (ra:join-pass)) 0) (setq n (+ n k)))
  n)

;;; ---------------------------------------------------------------------
;;; Arcos -> segmentos
;;; ---------------------------------------------------------------------
(defun ra:arcpts (c r a0 sw / n i res)
  (setq n (max 1 (fix (+ 0.999 (/ (abs (* r sw)) *RA:STEP*)))) i 1)
  (while (<= i n)
    (setq res (cons (polar c (+ a0 (* sw (/ (float i) n))) r) res) i (1+ i)))
  (reverse res))

(defun ra:arc-ent-pts (ed / c r a0 sw)
  (setq c (ra:2d (cdr (assoc 10 ed))) r (cdr (assoc 40 ed))
        a0 (cdr (assoc 50 ed)) sw (- (cdr (assoc 51 ed)) a0))
  (if (<= sw 0.0) (setq sw (+ sw (* 2.0 pi))))
  (cons (polar c a0 r) (ra:arcpts c r a0 sw)))

(defun ra:has-bulge (ed)
  (vl-some '(lambda (g) (and (= (car g) 42) (/= (cdr g) 0.0))) ed))

(defun ra:lw-seg-pts (ed / vs bs p p2 b cen res)
  (foreach g ed
    (cond ((= (car g) 10) (setq vs (cons (ra:2d (cdr g)) vs) bs (cons 0.0 bs)))
          ((= (car g) 42) (setq bs (cons (cdr g) (cdr bs))))))
  (setq vs (reverse vs) bs (reverse bs))
  (if (= 1 (logand 1 (cdr (assoc 70 ed)))) (setq vs (append vs (list (car vs)))))
  (setq res (list (car vs)))
  (while (cadr vs)
    (setq p (car vs) p2 (cadr vs) b (car bs))
    (if (equal b 0.0 1e-12)
      (setq res (cons p2 res))
      (progn
        (setq cen (polar p (+ (angle p p2) (- (/ pi 2.0) (* 2.0 (atan b))))
                         (/ (* (distance p p2) (+ 1.0 (* b b))) (* 4.0 b))))
        (foreach q (ra:arcpts cen (distance cen p) (angle cen p) (* 4.0 (atan b)))
          (setq res (cons q res)))
        (setq res (cons p2 (cdr res)))))
    (setq vs (cdr vs) bs (cdr bs)))
  (reverse res))

;;; =====================================================================
;;; COMANDOS
;;; =====================================================================
(defun c:RA_VERIFICAR () (ra:start) (ra:verify) (ra:end))

(defun c:RA_QUEBRAR (/ n)
  (ra:start)
  (setq n (ra:break-all nil))
  (ra:msg (strcat (itoa n) " linha(s) quebrada(s) nos entroncamentos/cruzamentos."))
  (ra:end))

(defun c:RA_PONTAS (/ n1 n2)
  (ra:start)
  (setq n1 (ra:snap-dangles) n2 (ra:break-all nil))
  (ra:msg (strcat (itoa n1) " ponta(s) solta(s) ligada(s); " (itoa n2) " linha(s) quebrada(s)."))
  (ra:end))

(defun c:RA_JUNTAR (/ n)
  (ra:start)
  (setq n (ra:join-all))
  (ra:msg (strcat (itoa n) " pseudo-no(s) eliminado(s) (linhas emendadas)."))
  (ra:end))

(defun c:RA_CORRIGIR (/ n1 n2 n3 n4)
  (ra:start)
  (ra:clear-marks)
  (setq n1 (ra:del-dups)
        n2 (ra:snap-dangles)
        n3 (ra:break-all nil)
        n4 (ra:join-all))
  (ra:msg (strcat "Correcao: " (itoa n1) " duplicada(s) apagada(s), "
                  (itoa n2) " ponta(s) ligada(s), " (itoa n3) " linha(s) quebrada(s), "
                  (itoa n4) " pseudo-no(s) eliminado(s).  (U desfaz tudo)"))
  (ra:verify)
  (ra:end))

(defun c:RA_DESENHAR (/ before new n)
  (ra:start)
  (ra:mklayer *RA:DRAWLAYER* 4)
  (if (not (wcmatch (strcase *RA:DRAWLAYER*) (strcase *RA:LAYERS*)))
    (ra:msg "Aviso: a camada de desenho nao entra no filtro da rede (RA_CONFIG)."))
  (setvar "CLAYER" *RA:DRAWLAYER*)
  (setvar "OSMODE" 545)                 ; fim + intersecao + proximo
  (setvar "CMDECHO" 1)
  (setq before (entlast))
  (ra:msg "Desenhe a linha da rede (snaps: fim, intersecao, proximo). Enter termina.")
  (command "_.PLINE")
  (while (> (getvar "CMDACTIVE") 0) (command pause))
  (setvar "CMDECHO" 0)
  (setq new (entlast))
  (if (and new (not (eq new before)))
    (progn
      (setq n (ra:break-all new))
      (ra:msg (strcat "Linha criada; " (itoa n) " linha(s) quebrada(s) nos entroncamentos."))))
  (ra:end))

(defun c:RA_SEGMENTAR (/ ss i e ed typ pts el n)
  (ra:start)
  (setq ss (ssget "_X" (list '(0 . "ARC,LWPOLYLINE") (cons 8 *RA:LAYERS*) '(410 . "Model")))
        n 0 i 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i) ed (entget e '("*")) typ (cdr (assoc 0 ed)) pts nil)
      (cond
        ((= typ "ARC")
         (setq pts (ra:arc-ent-pts ed) el (caddr (cdr (assoc 10 ed)))))
        ((and (= typ "LWPOLYLINE") (ra:has-bulge ed))
         (setq pts (ra:lw-seg-pts ed) el (if (assoc 38 ed) (cdr (assoc 38 ed)) 0.0))))
      (if pts
        (progn
          (ra:make (list nil "LWPOLYLINE" nil nil el nil ed) pts)
          (entdel e)
          (setq n (1+ n))))))
  (ra:msg (strcat (itoa n) " arco(s) convertido(s) em segmentos de ate "
                  (rtos *RA:STEP* 2 1) " m."))
  (ra:end))

(defun c:RA_SEMCONEXAO (/ p)
  (ra:mklayer *RA:EXC* 8)
  (while (setq p (getpoint "\nClique no cruzamento que NAO deve conectar (viaduto) <Enter sai>: "))
    (entmakex (list '(0 . "CIRCLE") (cons 8 *RA:EXC*) (list 10 (car p) (cadr p) 0.0)
                    (cons 40 *RA:MARK*))))
  (princ))

(defun c:RA_LIMPAR () (ra:clear-marks) (ra:msg "Marcadores apagados.") (princ))

(defun c:RA_PROXIMO (/ ss e ed)
  (if (setq ss (ssget "_X" (list (cons 8 *RA:ERR*))))
    (progn
      (if (or (null *ra-ix*) (>= *ra-ix* (sslength ss))) (setq *ra-ix* 0))
      (setq e (ssname ss *ra-ix*) ed (entget e) *ra-ix* (1+ *ra-ix*))
      (command "_.ZOOM" "_C" (cdr (assoc 10 ed)) (* 15.0 *RA:MARK*))
      (ra:msg (strcat "Marcador " (itoa *ra-ix*) " de " (itoa (sslength ss)) ": "
                      (ra:cname (cdr (assoc 62 ed))))))
    (ra:msg "Nenhum marcador. Rode RV."))
  (princ))

(defun c:RA_CONFIG (/ s r)
  (ra:msg (strcat "Atual: camadas=" *RA:LAYERS* "  desenho=" *RA:DRAWLAYER*
                  "  tol=" (rtos *RA:TOL* 2 4) "  gap=" (rtos *RA:GAP* 2 2)
                  "  marcador=" (rtos *RA:MARK* 2 2) "  arco=" (rtos *RA:STEP* 2 1)))
  (if (/= "" (setq s (getstring T (strcat "\nFiltro de camadas da rede <" *RA:LAYERS* ">: "))))
    (setq *RA:LAYERS* (strcase s)))
  (if (/= "" (setq s (getstring T (strcat "\nCamada de desenho <" *RA:DRAWLAYER* ">: "))))
    (setq *RA:DRAWLAYER* (strcase s)))
  (initget 6)
  (if (setq r (getreal (strcat "\nTolerancia de ponto igual, m <" (rtos *RA:TOL* 2 4) ">: ")))
    (setq *RA:TOL* r))
  (initget 6)
  (if (setq r (getreal (strcat "\nDistancia de ponta solta, m <" (rtos *RA:GAP* 2 2) ">: ")))
    (setq *RA:GAP* r))
  (initget 6)
  (if (setq r (getreal (strcat "\nRaio dos marcadores, m <" (rtos *RA:MARK* 2 2) ">: ")))
    (setq *RA:MARK* r))
  (initget 6)
  (if (setq r (getreal (strcat "\nSegmento maximo de arco, m <" (rtos *RA:STEP* 2 1) ">: ")))
    (setq *RA:STEP* r))
  (princ))

(defun c:RA_AJUDA ()
  (ra:msg "================ Routes Analyzer - rede de rotas ================")
  (ra:msg " RV  RA_VERIFICAR   verifica e marca problemas na camada RA_ERROS")
  (ra:msg " RN  RA_PROXIMO     vai ao proximo marcador")
  (ra:msg " RL  RA_LIMPAR      apaga os marcadores")
  (ra:msg " RC  RA_CORRIGIR    corrige tudo: duplicadas, pontas, quebras, pseudo-nos")
  (ra:msg " RQ  RA_QUEBRAR     quebra as linhas em todos os entroncamentos/cruzamentos")
  (ra:msg " RF  RA_PONTAS      liga pontas soltas (< GAP) e quebra")
  (ra:msg " RJ  RA_JUNTAR      emenda linhas em pseudo-nos")
  (ra:msg " RD  RA_DESENHAR    desenha linha da rede com snaps e quebra automatica")
  (ra:msg " RS  RA_SEGMENTAR   converte arcos da rede em segmentos retos")
  (ra:msg " RX  RA_SEMCONEXAO  marca cruzamento que NAO conecta (viaduto)")
  (ra:msg "     RA_CONFIG      camadas e tolerancias")
  (ra:msg " Cores: vermelho=cruzamento sem quebra, laranja=T sem quebra, amarelo=pseudo-no,")
  (ra:msg "        magenta=ponta solta, azul=sobreposicao, ciano=nao suportado, verde=desconectado")
  (princ))

;;; atalhos
(defun c:RV () (c:RA_VERIFICAR))
(defun c:RN () (c:RA_PROXIMO))
(defun c:RL () (c:RA_LIMPAR))
(defun c:RC () (c:RA_CORRIGIR))
(defun c:RQ () (c:RA_QUEBRAR))
(defun c:RF () (c:RA_PONTAS))
(defun c:RJ () (c:RA_JUNTAR))
(defun c:RD () (c:RA_DESENHAR))
(defun c:RS () (c:RA_SEGMENTAR))
(defun c:RX () (c:RA_SEMCONEXAO))

(princ "\nRA_REDE carregado. Digite RA_AJUDA para ver os comandos.")
(princ)
