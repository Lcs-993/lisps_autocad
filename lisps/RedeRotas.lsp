;;; ==========================================================================
;;; RedeRotas.lsp - Validar e preparar a geometria da rede de rotas
;;; --------------------------------------------------------------------------
;;; Prepara as linhas do desenho para o Routes Analyzer (ou outra ferramenta
;;; de rotas que monte o grafo POR VÉRTICES): duas linhas só se conectam onde
;;; têm um vértice em comum, na mesma coordenada.
;;;
;;; REDE_VALIDAR   (só leitura) - marca no layer REDE_ERROS (não plota) e grava
;;;              <desenho>_REDE_validacao.csv:
;;;   CRUZAMENTO        cruzamento sem vértice comum
;;;   T_SEM_VERTICE     vértice de uma linha sobre o segmento de outra
;;;   PONTA_SOLTA       ponta a menos de X m de outra linha, sem tocar
;;;   QUASE_COINCIDENTE vértices a 0 < d < tolerância (ponta envolvida, ou d < 1 mm)
;;;   DUPLICADA / SOBREPOSTA  linhas ou trechos colineares repetidos
;;;   SEGMENTO_ZERO     vértices consecutivos repetidos
;;;   NAO_SUPORTADA     ARC, CIRCLE, SPLINE, ELLIPSE (convertíveis), blocos,
;;;                     textos e outros objetos nas camadas da rede
;;;   COORDENADAS / UNIDADE / CRS  faixa plausível do EPSG, INSUNITS, EPSG
;;;   Z_VARIAVEL        polilinha 3D / LINE com Z variável (Z é ignorado)
;;;   ARCOS             polilinha com arcos (vira vértices na correção/exportação)
;;;   FRAGMENTO         componente isolado (o principal é o de maior comprimento)
;;; REDE_PROXIMO / REDE_ANTERIOR - navega pelos marcadores (zoom + seleção)
;;; REDE_CORRIGIR  - mesmo motor sobre um MODELO em memória; modo simulação
;;;              (padrão) só lista; senão pede confirmação e aplica num UNDO
;;;              único. Ordem: segmentos zero -> unir quase coincidentes ->
;;;              pontas soltas (estender pela direção da ponta ou ligar ao
;;;              ponto mais próximo) -> vértices em cruzamentos e T -> unir ->
;;;              duplicados/sobrepostos -> segmentos zero (repete até
;;;              estabilizar). Converte ARC/SPLINE/ELLIPSE em polilinha e
;;;              densifica arcos (máx. "Densificação" m entre vértices);
;;;              achata Z se marcado. Nunca inverte o sentido das linhas.
;;;              Log: <desenho>_REDE_correcoes.csv. Valida de novo no final.
;;; REDE_EXPORTAR  - GeoJSON (LineString 2D, membro "crs" com o EPSG,
;;;              propriedades handle/layer), aceito pelo viewer/js/io.js.
;;;
;;; Desempenho: pares por GRADE espacial (cada par testado uma vez, na célula
;;; do canto inferior esquerdo da interseção das caixas), union-find em
;;; safearray, nada de COM por segmento.
;;;
;;; Depende de Simplifica.lsp (sp:lw-le, sp:segmenta-recs, ...).
;;; Comandos: REDE_VALIDAR, REDE_CORRIGIR, REDE_PROXIMO, REDE_ANTERIOR, REDE_EXPORTAR
;;;
;;; Coexiste com a outra versão (routes_analyzer\tools\autocad\RA_REDE.lsp,
;;; comandos RA_*, prefixo ra:, layer RA_ERROS): por isso esta usa rr:,
;;; REDE_* e o layer REDE_ERROS. REDE_CARREGA_RA carrega a outra (menu).
;;; ==========================================================================

(vl-load-com)

(setq *RR-EPS0*  1e-6                   ; mesmo ponto
      *RR-EPST*  1e-3                   ; toque (vértice sobre segmento)
      *RR-LAYER* "REDE_ERROS")

;;; tipo  cor  sigla
(setq *RR-TIPOS*
  '(("CRUZAMENTO" 1 "X") ("T_SEM_VERTICE" 30 "T") ("PONTA_SOLTA" 2 "PS")
    ("QUASE_COINCIDENTE" 6 "QC") ("DUPLICADA" 4 "DUP") ("SOBREPOSTA" 4 "SOB")
    ("SEGMENTO_ZERO" 5 "Z0") ("NAO_SUPORTADA" 3 "NS") ("COORDENADAS" 7 "CRD")
    ("UNIDADE" 7 "UN") ("CRS" 7 "CRS") ("Z_VARIAVEL" 8 "Z") ("ARCOS" 9 "ARC")
    ("FRAGMENTO" 140 "FRG")))

;;; --------------------------------------------------------------------------
;;; Parâmetros (persistem via setenv)
;;; --------------------------------------------------------------------------
(setq *RR-CHAVES* '(*RR-CAMADAS* *RR-PONTA* *RR-QUASE* *RR-DENS* *RR-MARCA* *RR-EPSG*
                    *RR-SIMULA* *RR-ACHATA* *RR-CONVERTE*))
(defun rr:le-env (/ v)
  (setq *RR-CAMADAS* "" *RR-PONTA* 3.0 *RR-QUASE* 1.0 *RR-DENS* 5.0 *RR-MARCA* 2.0
        *RR-EPSG* "" *RR-SIMULA* T *RR-ACHATA* nil *RR-CONVERTE* T)
  (if (and (setq v (getenv "LISPS_REDEROTAS"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= (length v) (length *RR-CHAVES*))
           (= 'STR (type (car v))) (numberp (cadr v)))
    (mapcar 'set *RR-CHAVES* v))
)
(defun rr:grava-env () (setenv "LISPS_REDEROTAS" (vl-prin1-to-string (mapcar 'eval *RR-CHAVES*))))
(if (not *RR-PONTA*) (rr:le-env))

;;; --------------------------------------------------------------------------
;;; Utilidades
;;; --------------------------------------------------------------------------
(defun rr:pasta ()
  (cond (*LISPS-DIR*)
        ((findfile "RedeRotas.dcl") (vl-filename-directory (findfile "RedeRotas.dcl"))))
)
(defun rr:requer (/ arq)
  (if (and (not sp:lw-le)
           (setq arq (cond ((and (rr:pasta) (findfile (strcat (rr:pasta) "\\Simplifica.lsp"))))
                           ((findfile "Simplifica.lsp")))))
    (load arq))
  (if sp:lw-le T (progn (alert "Simplifica.lsp não encontrado (necessário para RedeRotas).") nil))
)
(defun rr:d2 (ax ay bx by) (sqrt (+ (* (- bx ax) (- bx ax)) (* (- by ay) (- by ay)))))
(defun rr:dist (p q) (rr:d2 (car p) (cadr p) (car q) (cadr q)))
(defun rr:troca (l pos v / i) (setq i -1) (mapcar '(lambda (x) (if (= (setq i (1+ i)) pos) v x)) l))
(defun rr:flag (r f) (if (member f (nth 5 r)) r (rr:troca r 5 (cons f (nth 5 r)))))
(defun rr:ativo-p (r) (not (member 'DEL (nth 5 r))))
(defun rr:xy (x y) (strcat (rtos x 2 3) "," (rtos y 2 3)))
(defun rr:separa (s d / i r)
  (while (setq i (vl-string-search d s))
    (setq r (cons (substr s 1 i) r) s (substr s (+ i 1 (strlen d)))))
  (reverse (cons s r))
)
(defun rr:corta (s n) (if (> (strlen s) n) (substr s 1 n) s))
(defun rr:num-tile (k / s) (setq s (get_tile k)) (if s (distof (vl-string-translate "," "." s) 2)))

;;; safearray como vetor mutável (union-find, contadores)
(defun rr:vet (n tipo ini / v i)
  (setq v (vlax-make-safearray tipo (cons 0 (max 0 (1- n)))) i 0)
  (if ini (while (< i n) (vlax-safearray-put-element v i (if (eq ini 'IDX) i ini)) (setq i (1+ i))))
  v
)
(defun rr:vg (v i) (vlax-safearray-get-element v i))
(defun rr:vp (v i x) (vlax-safearray-put-element v i x))
(defun rr:find (uf i / p)
  (while (/= (setq p (rr:vg uf i)) i)
    (rr:vp uf i (rr:vg uf p))
    (setq i p))
  i
)
;;; raiz = menor índice (determinístico)
(defun rr:une (uf a b / x y)
  (setq x (rr:find uf a) y (rr:find uf b))
  (if (/= x y) (rr:vp uf (max x y) (min x y)))
)

;;; --------------------------------------------------------------------------
;;; Geometria
;;; --------------------------------------------------------------------------
;;; projeção de p no segmento a-b -> (dist u fx fy)
(defun rr:proj (px py ax ay bx by / ux uy l2 u fx fy)
  (setq ux (- bx ax) uy (- by ay) l2 (+ (* ux ux) (* uy uy))
        u  (if (> l2 1e-24) (max 0.0 (min 1.0 (/ (+ (* (- px ax) ux) (* (- py ay) uy)) l2))) 0.0)
        fx (+ ax (* u ux)) fy (+ ay (* u uy)))
  (list (rr:d2 px py fx fy) u fx fy)
)
(defun rr:cross (ax ay bx by cx cy) (- (* (- bx ax) (- cy ay)) (* (- by ay) (- cx ax))))
;;; cruzamento próprio (interiores) -> u no segmento a-b, ou nil
(defun rr:cruza (ax ay bx by cx cy dx dy / o1 o2 o3 o4)
  (setq o1 (rr:cross ax ay bx by cx cy) o2 (rr:cross ax ay bx by dx dy)
        o3 (rr:cross cx cy dx dy ax ay) o4 (rr:cross cx cy dx dy bx by))
  (if (and (< (* o1 o2) 0.0) (< (* o3 o4) 0.0)) (/ o3 (- o3 o4)))
)
(defun rr:adjacente (i j n fech) (or (= (abs (- i j)) 1) (and fech (> n 2) (= (abs (- i j)) (1- n)))))
(defun rr:comprimento (pts fech / l)
  (setq l 0.0)
  (mapcar '(lambda (a b) (setq l (+ l (rr:dist a b)))) pts (cdr pts))
  (if (and fech (cdr pts)) (setq l (+ l (rr:dist (last pts) (car pts)))))
  l
)
(defun rr:proximos (pts fech) (append (cdr pts) (list (if fech (car pts)))))

;;; --------------------------------------------------------------------------
;;; Pares por grade espacial
;;;   itens: (xmin ymin xmax ymax ...) ; (fn a b) é chamada UMA vez por par de
;;;   caixas que se tocam - na célula do canto (max xmin, max ymin).
;;; --------------------------------------------------------------------------
(defun rr:celula (x y x0 y0 cel) (+ (* (fix (/ (- x x0) cel)) 1048576.0) (fix (/ (- y y0) cel))))

(defun rr:pares (itens cel fn / x0 y0 lst cx cx1 cy cy0 cy1 k g a)
  (if itens
    (progn
      (setq x0 (car (car itens)) y0 (cadr (car itens)))
      (foreach it itens (setq x0 (min x0 (car it)) y0 (min y0 (cadr it))))
      (foreach it itens
        (setq cx  (fix (/ (- (car it) x0) cel))  cx1 (fix (/ (- (caddr it) x0) cel))
              cy0 (fix (/ (- (cadr it) y0) cel)) cy1 (fix (/ (- (cadddr it) y0) cel)))
        (while (<= cx cx1)
          (setq cy cy0)
          (while (<= cy cy1)
            (setq lst (cons (cons (+ (* cx 1048576.0) cy) it) lst) cy (1+ cy)))
          (setq cx (1+ cx))))
      (setq lst (vl-sort lst '(lambda (a b) (< (car a) (car b)))))
      (while lst
        (setq k (car (car lst)) g nil)
        (while (and lst (= (car (car lst)) k))
          (setq g (cons (cdr (car lst)) g) lst (cdr lst)))
        (while g
          (setq a (car g) g (cdr g))
          (foreach b g
            (if (and (<= (car a) (caddr b)) (<= (car b) (caddr a))
                     (<= (cadr a) (cadddr b)) (<= (cadr b) (cadddr a))
                     (= k (rr:celula (max (car a) (car b)) (max (cadr a) (cadr b)) x0 y0 cel)))
              (apply fn (list a b))))))))
)

;;; --------------------------------------------------------------------------
;;; Modelo da rede
;;;   registro = (id ename tipo fechada pts flags origem)
;;;   pts = ((x y z) ...) ; flags: CONV ARCOS ZVAR MOD DEL NOVO
;;; --------------------------------------------------------------------------
(defun rr:reindexa (model / i) (setq i -1) (mapcar '(lambda (r) (rr:troca r 0 (setq i (1+ i)))) model))

;;; amostra uma curva (ARC, CIRCLE, SPLINE, ELLIPSE, POLYLINE fit) a cada <= dens
(defun rr:amostra (e dens fech / L n k pts)
  (setq L (vlax-curve-getDistAtParam e (vlax-curve-getEndParam e))
        n (sp:ceil (/ L dens))
        n (if fech (max n 3) n)
        k 0)
  (while (< k (if fech n (1+ n)))
    (setq pts (cons (cond ((= k 0) (vlax-curve-getStartPoint e))
                          ((= k n) (vlax-curve-getEndPoint e))
                          (T (vlax-curve-getPointAtDist e (/ (* L k) n))))
                    pts)
          k   (1+ k)))
  (reverse pts)
)

(defun rr:zvar-p (pts / z)
  (setq z (caddr (car pts)))
  (vl-some '(lambda (p) (> (abs (- (caddr p) z)) 1e-6)) pts)
)

;;; ename -> registro, ou (NAO ename tipo ponto convertivel?)
(defun rr:le-ent (e id / ed tp fl recs pts fech flags z)
  (setq ed (entget e) tp (cdr (assoc 0 ed)))
  (cond
    ((= tp "LINE")
     (setq pts (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))
     (list id e "LINE" nil pts (if (rr:zvar-p pts) '(ZVAR)) e))
    ((= tp "LWPOLYLINE")
     (setq fech (= 1 (logand 1 (cdr (assoc 70 ed))))
           recs (cadr (sp:lw-le ed))
           z    (sp:num 38 ed))
     (if (vl-some 'sp:arco-p (mapcar 'cadddr (if fech recs (sp:butlast recs))))
       (setq recs (car (sp:segmenta-recs recs fech 'MEDIDA *RR-DENS*)) flags '(ARCOS)))
     (list id e "LWPOLYLINE" fech (mapcar '(lambda (r) (list (car (car r)) (cadr (car r)) z)) recs) flags e))
    ((= tp "POLYLINE")
     (setq fl (cdr (assoc 70 ed)) fech (= 1 (logand 1 fl)))
     (cond
       ((/= 0 (logand 80 fl)) (list 'NAO e "POLYLINE (malha)" (vlax-curve-getStartPoint e) nil))
       ((/= 0 (logand 6 fl))                                   ; fit / spline
        (list id e "POLYLINE" fech (rr:amostra e *RR-DENS* fech) '(CONV) e))
       ((/= 0 (logand 8 fl))                                   ; 3D
        (setq pts (mapcar 'car (sp:pl-le e)))
        (list id e "POLYLINE3D" fech pts (if (rr:zvar-p pts) '(ZVAR)) e))
       (T
        (setq recs (sp:pl-le e) z (caddr (cdr (assoc 10 ed))))
        (if (vl-some 'sp:arco-p (mapcar 'cadddr (if fech recs (sp:butlast recs))))
          (setq recs (car (sp:segmenta-recs recs fech 'MEDIDA *RR-DENS*)) flags '(ARCOS)))
        (list id e "POLYLINE" fech (mapcar '(lambda (r) (list (car (car r)) (cadr (car r)) z)) recs) flags e))))
    ((member tp '("ARC" "CIRCLE" "SPLINE" "ELLIPSE"))
     (setq fech (or (= tp "CIRCLE") (vlax-curve-isClosed e)))
     (list id e tp fech (rr:amostra e *RR-DENS* fech) '(CONV) e))
    (T (list 'NAO e tp (cond ((assoc 10 ed) (cdr (assoc 10 ed))) ('(0.0 0.0 0.0))) nil)))
)

;;; lê as camadas da rede -> (modelo naosup) ; converte? = ARC/SPLINE entram no modelo
(defun rr:le-rede (converte / ss i e r model naosup id)
  (setq id 0)
  (if (setq ss (ssget "_X" (list (cons 8 *RR-CAMADAS*) '(410 . "Model"))))
    (repeat (setq i (sslength ss))
      (setq e (ssname ss (setq i (1- i))))
      (if (/= (strcase (cdr (assoc 8 (entget e)))) *RR-LAYER*)
        (progn
          (setq r (rr:le-ent e id))
          (cond
            ((eq (car r) 'NAO) (setq naosup (cons r naosup)))
            ((and (member 'CONV (nth 5 r)) (not converte))
             (setq naosup (cons (list 'NAO e (nth 2 r) (car (nth 4 r)) T) naosup)))
            ((< (length (nth 4 r)) 1))
            (T (setq model (cons r model) id (1+ id))))))))
  (list (rr:reindexa (reverse model)) naosup)
)

;;; --------------------------------------------------------------------------
;;; Análise topológica (núcleo; o mesmo para validar, corrigir e simular)
;;; -> (quase cruz tees sob pontas zeros comp)
;;;   quase : (d va vb ca cb)  v = (vid x y ent k fim n fech) ; c = nº no nó
;;;   cruz  : (px py e1 k1 u e2 k2 v)
;;;   tees  : (px py ent-origem ent-alvo seg-alvo u)
;;;   sob   : (ea eb comprimento mx my duplicada?)
;;;   pontas: (ent fim d qx qy ent-alvo seg-alvo fx fy cx cy dx dy)
;;;   zeros : (x y ent k)
;;;   comp  : (n-componentes fração-principal fragmentos comprimento-total)
;;; --------------------------------------------------------------------------
(defun rr:par-vv (a b / va vb d)
  (setq va (nth 5 a) vb (nth 5 b) d (rr:d2 (nth 1 va) (nth 2 va) (nth 1 vb) (nth 2 vb)))
  (cond
    ((<= d *RR-EPS0*) (rr:une *rr-uf* (car va) (car vb)))
    ((>= d *rr-tolq*))
    ((and (= (nth 3 va) (nth 3 vb)) (rr:adjacente (nth 4 va) (nth 4 vb) (nth 6 va) (nth 7 va))))
    ((or (< d *RR-EPST*) (nth 5 va) (nth 5 vb))
     (setq *rr-quase* (cons (list d va vb) *rr-quase*))))
)

;;; vértice p (do segmento src) sobre o segmento dst? -> T se toca (registra o T
;;; quando não está perto de um vértice de dst)
(defun rr:toque (px py src dst / pr)
  (setq pr (rr:proj px py (nth 7 dst) (nth 8 dst) (nth 9 dst) (nth 10 dst)))
  (if (<= (car pr) *RR-EPST*)
    (progn
      (if (and (> (rr:d2 px py (nth 7 dst) (nth 8 dst)) *RR-EPST*)
               (> (rr:d2 px py (nth 9 dst) (nth 10 dst)) *RR-EPST*))
        (setq *rr-tees* (cons (list px py (nth 5 src) (nth 5 dst) (nth 6 dst) (cadr pr)) *rr-tees*)))
      T))
)

(defun rr:sobrep (s1 s2 / ax ay bx by L ux uy cx cy dx dy tc td lo hi m)
  (setq ax (nth 7 s1) ay (nth 8 s1) bx (nth 9 s1) by (nth 10 s1)
        cx (nth 7 s2) cy (nth 8 s2) dx (nth 9 s2) dy (nth 10 s2)
        L  (rr:d2 ax ay bx by))
  (if (> L *RR-EPS0*)
    (progn
      (setq ux (/ (- bx ax) L) uy (/ (- by ay) L))
      (if (and (<= (abs (- (* ux (- cy ay)) (* uy (- cx ax)))) *RR-EPST*)
               (<= (abs (- (* ux (- dy ay)) (* uy (- dx ax)))) *RR-EPST*))
        (progn
          (setq tc (+ (* ux (- cx ax)) (* uy (- cy ay)))
                td (+ (* ux (- dx ax)) (* uy (- dy ay)))
                lo (max 0.0 (min tc td))
                hi (min L (max tc td))
                m  (/ (+ lo hi) 2.0))
          (if (> (- hi lo) *RR-EPST*)
            (setq *rr-sob* (cons (list (nth 5 s1) (nth 5 s2) (- hi lo) (+ ax (* ux m)) (+ ay (* uy m)))
                                 *rr-sob*)))))))
)

(defun rr:par-ss (s1 s2 / ax ay bx by cx cy dx dy toq u)
  (if (not (and (= (nth 5 s1) (nth 5 s2))
                (rr:adjacente (nth 6 s1) (nth 6 s2) (nth 11 s1) (nth 12 s1))))
    (progn
      (setq ax (nth 7 s1) ay (nth 8 s1) bx (nth 9 s1) by (nth 10 s1)
            cx (nth 7 s2) cy (nth 8 s2) dx (nth 9 s2) dy (nth 10 s2))
      (foreach x (list (list ax ay s1 s2) (list bx by s1 s2) (list cx cy s2 s1) (list dx dy s2 s1))
        (if (apply 'rr:toque x) (setq toq T)))
      (rr:sobrep s1 s2)
      (if (and (not toq) (setq u (rr:cruza ax ay bx by cx cy dx dy)))
        (setq *rr-cruz* (cons (list (+ ax (* u (- bx ax))) (+ ay (* u (- by ay)))
                                    (nth 5 s1) (nth 6 s1) u
                                    (nth 5 s2) (nth 6 s2) (rr:cruza cx cy dx dy ax ay bx by))
                              *rr-cruz*)))))
)

;;; segmento c4 = (ax ay bx by) a <= EPST do segmento s?
(defun rr:seg-perto (c s / ax ay bx by cx cy dx dy)
  (setq ax (car c) ay (cadr c) bx (caddr c) by (cadddr c)
        cx (nth 7 s) cy (nth 8 s) dx (nth 9 s) dy (nth 10 s))
  (or (rr:cruza ax ay bx by cx cy dx dy)
      (<= (car (rr:proj ax ay cx cy dx dy)) *RR-EPST*) (<= (car (rr:proj bx by cx cy dx dy)) *RR-EPST*)
      (<= (car (rr:proj cx cy ax ay bx by)) *RR-EPST*) (<= (car (rr:proj dx dy ax ay bx by)) *RR-EPST*))
)

;;; ponta solta p x segmento s: candidato se EPST < d <= X e a própria ponta
;;; (cadeia até X) não toca s (senão é só uma sobra depois do cruzamento)
(defun rr:par-sp (s p / qx qy pr)
  (if (not (and (= (nth 5 s) (nth 5 p)) (assoc (nth 6 s) (nth 9 p))))
    (progn
      (setq qx (nth 7 p) qy (nth 8 p)
            pr (rr:proj qx qy (nth 7 s) (nth 8 s) (nth 9 s) (nth 10 s)))
      (if (and (> (car pr) *RR-EPST*) (<= (car pr) *rr-x*)
               (not (vl-some '(lambda (c) (rr:seg-perto (cdr c) s)) (nth 9 p))))
        (setq *rr-cand* (cons (list (nth 5 p) (nth 6 p) (car pr) qx qy (nth 5 s) (nth 6 s)
                                    (caddr pr) (cadddr pr) (nth 7 s) (nth 8 s) (nth 9 s) (nth 10 s))
                              *rr-cand*)))))
)

(defun rr:par-sx (a b)
  (cond
    ((and (eq (nth 4 a) 'S) (eq (nth 4 b) 'S)) (rr:par-ss a b))
    ((and (eq (nth 4 a) 'S) (eq (nth 4 b) 'P)) (rr:par-sp a b))
    ((and (eq (nth 4 a) 'P) (eq (nth 4 b) 'S)) (rr:par-sp b a)))
)

;;; cadeia de segmentos a partir de uma ponta, até somar >= X: ((k ax ay bx by) ...)
(defun rr:cadeia (pts inicio X / segs k acc res)
  (setq k 0)
  (mapcar '(lambda (a b) (setq segs (cons (list k (car a) (cadr a) (car b) (cadr b)) segs) k (1+ k)))
          pts (cdr pts))
  (setq segs (if inicio (reverse segs) segs) acc 0.0)
  (while (and segs (or (null res) (< acc X)))
    (setq res (cons (car segs) res)
          acc (+ acc (rr:d2 (nth 1 (car segs)) (nth 2 (car segs)) (nth 3 (car segs)) (nth 4 (car segs))))
          segs (cdr segs)))
  res
)

(defun rr:mesmo-pt (x y l) (vl-some '(lambda (p) (<= (rr:d2 x y (car p) (cadr p)) *RR-EPS0*)) l))

(defun rr:analisa (model X tolQ / nent nv vs base pts n fech k id h itens entv cnt euf elen
                   tot zeros segs probes nseg somal raiz grupos main ncomp frags ptsq pontas
                   ult sob agrup)
  (setq *rr-uf* nil *rr-quase* nil *rr-cruz* nil *rr-tees* nil *rr-sob* nil *rr-cand* nil
        *rr-x* X *rr-tolq* tolQ
        nent (length model) nv 0)
  ;; 1. vértices e segmentos de comprimento zero
  (foreach r model
    (if (rr:ativo-p r)
      (progn
        (setq id (car r) pts (nth 4 r) n (length pts) fech (nth 3 r) k 0)
        (foreach p pts
          (setq vs (cons (list nv (car p) (cadr p) id k (and (not fech) (or (= k 0) (= k (1- n)))) n fech) vs)
                nv (1+ nv) k (1+ k)))
        (setq k 0)
        (mapcar '(lambda (a b)
                   (if (and b (<= (rr:dist a b) *RR-EPS0*)) (setq zeros (cons (list (car a) (cadr a) id k) zeros)))
                   (setq k (1+ k)))
                pts (if (and fech (cdr pts)) (rr:proximos pts T) (cdr pts))))))
  (setq vs (reverse vs))
  ;; 2. nós (mesma coordenada) e quase coincidentes, por grade
  (setq *rr-uf* (rr:vet nv vlax-vbLong 'IDX)
        entv    (rr:vet nv vlax-vbLong 0)
        h       (/ tolQ 2.0))
  (foreach v vs (rr:vp entv (car v) (nth 3 v)))
  (rr:pares (mapcar '(lambda (v) (list (- (nth 1 v) h) (- (nth 2 v) h) (+ (nth 1 v) h) (+ (nth 2 v) h) 'V v)) vs)
            (max (* 4.0 tolQ) 1e-3) 'rr:par-vv)
  ;; 3. vértices por nó
  (setq cnt (rr:vet nv vlax-vbLong 0))
  (foreach v vs (setq k (rr:find *rr-uf* (car v))) (rr:vp cnt k (1+ (rr:vg cnt k))))
  (setq *rr-quase*
        (mapcar '(lambda (q) (list (car q) (cadr q) (caddr q)
                                   (rr:vg cnt (rr:find *rr-uf* (car (cadr q))))
                                   (rr:vg cnt (rr:find *rr-uf* (car (caddr q))))))
                (vl-remove-if '(lambda (q) (= (rr:find *rr-uf* (car (cadr q))) (rr:find *rr-uf* (car (caddr q)))))
                              *rr-quase*)))
  ;; 4. componentes: linhas que compartilham um nó
  (setq euf (rr:vet nent vlax-vbLong 'IDX) elen (rr:vet nent vlax-vbDouble 0.0) tot 0.0)
  (foreach v vs (rr:une euf (nth 3 v) (rr:vg entv (rr:find *rr-uf* (car v)))))
  (foreach r model
    (if (rr:ativo-p r)
      (progn
        (setq k (rr:comprimento (nth 4 r) (nth 3 r)) tot (+ tot k) raiz (rr:find euf (car r)))
        (rr:vp elen raiz (+ (rr:vg elen raiz) k))
        (if (setq h (assoc raiz grupos))
          (setq grupos (subst (cons raiz (cons (car r) (cdr h))) h grupos))
          (setq grupos (cons (list raiz (car r)) grupos))))))
  (setq ncomp (length grupos) main (car (car grupos)))
  (foreach g grupos (if (> (rr:vg elen (car g)) (rr:vg elen main)) (setq main (car g))))
  (foreach g grupos
    (if (/= (car g) main)
      (setq frags (cons (list (rr:vg elen (car g)) (reverse (cdr g))) frags))))
  ;; 5. segmentos e pontas soltas (sondas)
  (setq base 0 somal 0.0 nseg 0)
  (foreach r model
    (if (rr:ativo-p r)
      (progn
        (setq id (car r) pts (nth 4 r) n (length pts) fech (nth 3 r) k 0)
        (mapcar
          '(lambda (a b)
             (if b
               (progn
                 (setq segs (cons (list (min (car a) (car b)) (min (cadr a) (cadr b))
                                        (max (car a) (car b)) (max (cadr a) (cadr b))
                                        'S id k (car a) (cadr a) (car b) (cadr b)
                                        (if fech n (1- n)) fech)
                                  segs)
                       somal (+ somal (rr:dist a b)) nseg (1+ nseg) k (1+ k)))))
          pts (if (and fech (> n 2)) (rr:proximos pts T) (cdr pts)))
        (if (and (not fech) (> n 1))
          (foreach x (list (list 0 base (car pts) T) (list 1 (+ base n -1) (last pts) nil))
            (if (= 1 (rr:vg cnt (rr:find *rr-uf* (cadr x))))
              (setq probes (cons (list (- (car (caddr x)) X) (- (cadr (caddr x)) X)
                                       (+ (car (caddr x)) X) (+ (cadr (caddr x)) X)
                                       'P id (car x) (car (caddr x)) (cadr (caddr x))
                                       (rr:cadeia pts (cadddr x) X))
                                 probes)))))
        (setq base (+ base n)))))
  (rr:pares (append segs probes) (max (* 4.0 X) (if (> nseg 0) (/ somal nseg) 1.0) 1e-3) 'rr:par-sx)
  ;; 6. pós-processamento
  ;; T: sem repetição (mesmo ponto na mesma linha) e sem os já tratados como quase
  (setq ptsq (apply 'append (mapcar '(lambda (q) (list (list (nth 1 (cadr q)) (nth 2 (cadr q)))
                                                        (list (nth 1 (caddr q)) (nth 2 (caddr q)))))
                                    *rr-quase*)))
  (setq *rr-tees* (vl-sort *rr-tees*
                    '(lambda (a b) (cond ((/= (nth 3 a) (nth 3 b)) (< (nth 3 a) (nth 3 b)))
                                         ((/= (car a) (car b)) (< (car a) (car b)))
                                         (T (< (cadr a) (cadr b))))))
        ult nil)
  (setq *rr-tees*
        (vl-remove-if
          '(lambda (x)
             (prog1 (or (and ult (= (nth 3 x) (nth 3 ult)) (<= (rr:d2 (car x) (cadr x) (car ult) (cadr ult)) *RR-EPS0*))
                        (rr:mesmo-pt (car x) (cadr x) ptsq))
                    (setq ult x)))
          *rr-tees*))
  ;; pontas: o candidato mais próximo de cada sonda; não vale se já é T ou quase
  (setq *rr-cand* (vl-sort *rr-cand*
                    '(lambda (a b) (cond ((/= (car a) (car b)) (< (car a) (car b)))
                                         ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))
                                         (T (< (caddr a) (caddr b))))))
        ult nil)
  (foreach c *rr-cand*
    (if (not (and ult (= (car c) (car ult)) (= (cadr c) (cadr ult))))
      (if (not (or (rr:mesmo-pt (nth 3 c) (nth 4 c) ptsq)
                   (rr:mesmo-pt (nth 3 c) (nth 4 c) *rr-tees*)))
        (setq pontas (cons c pontas))))
    (setq ult c))
  ;; sobreposições agregadas por par de linhas: duplicada = cobre a menor inteira
  (foreach s *rr-sob*
    (setq k (list (min (car s) (cadr s)) (max (car s) (cadr s))))
    (if (setq h (assoc k agrup))
      (setq agrup (subst (list k (+ (cadr h) (caddr s)) (caddr h) (cadddr h)) h agrup))
      (setq agrup (cons (list k (caddr s) (nth 3 s) (nth 4 s)) agrup))))
  (setq sob (mapcar '(lambda (a)
                       (list (car (car a)) (cadr (car a)) (cadr a) (caddr a) (cadddr a)
                             (>= (cadr a) (- (min (rr:comprimento (nth 4 (nth (car (car a)) model)) (nth 3 (nth (car (car a)) model)))
                                                  (rr:comprimento (nth 4 (nth (cadr (car a)) model)) (nth 3 (nth (cadr (car a)) model))))
                                             *RR-EPST*))))
                    agrup))
  (list *rr-quase* (reverse *rr-cruz*) *rr-tees* sob (reverse pontas) (reverse zeros)
        (list ncomp (if (> tot 0.0) (/ (rr:vg elen main) tot) 1.0) frags tot))
)

;;; --------------------------------------------------------------------------
;;; Correção (sobre o modelo; *rr-log* recebe as alterações)
;;;   log = (operação handle x y antes depois)
;;; --------------------------------------------------------------------------
(defun rr:handle (r / e)
  (cond ((and (nth 1 r) (entget (nth 1 r))) (cdr (assoc 5 (entget (nth 1 r)))))
        ((and (nth 6 r) (entget (nth 6 r))) (strcat (cdr (assoc 5 (entget (nth 6 r)))) "+nova"))
        (T "?"))
)
(defun rr:log (op r x y antes depois)
  (setq *rr-log* (cons (list op (if r (rr:handle r) "") x y antes depois) *rr-log*))
)

(defun rr:limpa-pts (pts fech / res)
  (foreach p pts (if (not (and res (<= (rr:dist p (car res)) *RR-EPS0*))) (setq res (cons p res))))
  (setq res (reverse res))
  (if (and fech (cdr res) (<= (rr:dist (car res) (last res)) *RR-EPS0*)) (setq res (sp:butlast res)))
  res
)

(defun rr:c-zeros (model)
  (mapcar
    '(lambda (r / p2)
       (if (not (rr:ativo-p r))
         r
         (progn
           (setq p2 (rr:limpa-pts (nth 4 r) (nth 3 r)))
           (cond
             ((< (length p2) 2)
              (rr:log "APAGAR_ENTIDADE" r (car (car (nth 4 r))) (cadr (car (nth 4 r))) "comprimento zero" "")
              (rr:flag r 'DEL))
             ((< (length p2) (length (nth 4 r)))
              (rr:log "REMOVER_SEGMENTO_ZERO" r (car (car p2)) (cadr (car p2))
                      (itoa (length (nth 4 r))) (itoa (length p2)))
              (rr:flag (rr:troca (rr:troca r 4 p2) 3 (and (nth 3 r) (> (length p2) 2))) 'MOD))
             (T r)))))
    model)
)

;;; move todos os vértices em (sx sy) para (tx ty): moves = ((sx sy tx ty) ...)
(defun rr:c-mover (model moves)
  (mapcar
    '(lambda (r / mud p2)
       (setq mud nil
             p2  (mapcar '(lambda (p / m)
                            (if (setq m (vl-some '(lambda (m) (if (<= (rr:d2 (car p) (cadr p) (car m) (cadr m)) *RR-EPS0*) m))
                                                 moves))
                              (progn (setq mud T) (list (caddr m) (cadddr m) (caddr p)))
                              p))
                         (nth 4 r)))
       (if (and mud (rr:ativo-p r)) (rr:flag (rr:troca r 4 p2) 'MOD) r))
    model)
)

;;; une vértices quase coincidentes: cada grupo vai para o vértice com mais
;;; linhas no nó (depois: o que não é ponta; depois: o de menor id)
(defun rr:c-unir (model / an grupos ga gb alvo moves ok)
  (setq an (rr:analisa model *RR-PONTA* *RR-QUASE*))
  (foreach q (car an)
    (setq ga (vl-some '(lambda (g) (if (assoc (car (cadr q)) g) g)) grupos)
          gb (vl-some '(lambda (g) (if (assoc (car (caddr q)) g) g)) grupos))
    (setq grupos (vl-remove ga (vl-remove gb grupos))
          grupos (cons (append (if ga ga (list (cons (car (cadr q)) (list (cadr q) (nth 3 q)))))
                               (if (and gb (not (equal ga gb))) gb
                                 (if (not gb) (list (cons (car (caddr q)) (list (caddr q) (nth 4 q)))))))
                       grupos)))
  (foreach g grupos
    ;; membros: (vid v cnt)
    (setq g (vl-sort g '(lambda (a b) (< (car a) (car b))))
          alvo (car g))
    (foreach m (cdr g)
      (if (or (> (caddr m) (caddr alvo))
              (and (= (caddr m) (caddr alvo)) (nth 5 (cadr alvo)) (not (nth 5 (cadr m)))))
        (setq alvo m)))
    ;; só quem está a < tolerância do alvo; o resto fica para o próximo passo
    (foreach m g
      (setq ok (rr:d2 (nth 1 (cadr m)) (nth 2 (cadr m)) (nth 1 (cadr alvo)) (nth 2 (cadr alvo))))
      (if (and (> ok *RR-EPS0*) (< ok *RR-QUASE*))
        (progn
          (setq moves (cons (list (nth 1 (cadr m)) (nth 2 (cadr m)) (nth 1 (cadr alvo)) (nth 2 (cadr alvo))) moves))
          (rr:log "UNIR_VERTICE" (nth (nth 3 (cadr m)) model) (nth 1 (cadr alvo)) (nth 2 (cadr alvo))
                  (rr:xy (nth 1 (cadr m)) (nth 2 (cadr m))) (rr:xy (nth 1 (cadr alvo)) (nth 2 (cadr alvo))))))))
  (if moves (rr:c-mover model moves) model)
)

;;; insere (x y) no segmento mais próximo de pts -> pts novo (ou o mesmo)
(defun rr:ins-ponto (pts fech x y / best bk k res z)
  (setq k 0 best 1e99)
  (mapcar '(lambda (a b / pr)
             (if b (progn (setq pr (rr:proj x y (car a) (cadr a) (car b) (cadr b)))
                          (if (< (car pr) best) (setq best (car pr) bk (list k (cadr pr) a b)))))
             (setq k (1+ k)))
          pts (rr:proximos pts fech))
  (if (and bk (<= best *RR-EPST*))
    (progn
      (setq k 0
            z (+ (caddr (caddr bk)) (* (cadr bk) (- (caddr (cadddr bk)) (caddr (caddr bk))))))
      (foreach p pts
        (setq res (cons p res))
        (if (= k (car bk)) (setq res (cons (list x y z) res)))
        (setq k (1+ k)))
      (reverse res))
    pts)
)

(defun rr:vertice-perto (pts x y / m)
  (foreach p pts (if (and (not m) (<= (rr:d2 x y (car p) (cadr p)) *RR-EPST*)) (setq m p)))
  m
)

;;; pontas soltas: estende pela direção da ponta até a linha vizinha (se a
;;; reta corta o segmento a <= X), senão liga ao ponto mais próximo; cria o
;;; vértice na linha vizinha
(defun rr:c-pontas (model / an ra pts q nb wx wy L cx cy ex ey den s v px py modo rb pv)
  (setq an (rr:analisa model *RR-PONTA* *RR-QUASE*))
  (foreach c (nth 4 an)
    (setq ra  (nth (car c) model)
          pts (nth 4 ra)
          q   (if (= 0 (cadr c)) (car pts) (last pts)))
    ;; uma correção anterior deste passo já ligou a ponta?
    (if (not (rr:conectado-p model (car c) q))
     (progn
    (setq nb  (if (= 0 (cadr c)) (cadr pts) (cadr (reverse pts)))
          L   (rr:dist q nb)
          modo "LIGAR_PONTA" px (nth 7 c) py (nth 8 c))
    (if (> L *RR-EPS0*)
      (progn
        (setq wx (/ (- (car q) (car nb)) L) wy (/ (- (cadr q) (cadr nb)) L)
              cx (nth 9 c) cy (nth 10 c) ex (- (nth 11 c) cx) ey (- (nth 12 c) cy)
              den (- (* wx ey) (* wy ex)))
        (if (> (abs den) 1e-12)
          (progn
            (setq s (/ (- (* (- cx (car q)) ey) (* (- cy (cadr q)) ex)) den)
                  v (/ (- (* (- cx (car q)) wy) (* (- cy (cadr q)) wx)) den))
            (if (and (> s 0.0) (<= s (+ *RR-PONTA* *RR-EPST*)) (>= v -1e-9) (<= v (+ 1.0 1e-9)))
              (setq modo "ESTENDER_PONTA" px (+ (car q) (* s wx)) py (+ (cadr q) (* s wy))))))))
    ;; vértice existente da linha vizinha perto do ponto: usa ele
    (setq rb (nth (nth 5 c) model))
    (if (setq pv (rr:vertice-perto (nth 4 rb) px py)) (setq px (car pv) py (cadr pv)))
    ;; altera a ponta
    (setq pts (if (= modo "ESTENDER_PONTA")
                (if (= 0 (cadr c))
                  (cons (list px py (caddr q)) (cdr pts))
                  (append (sp:butlast pts) (list (list px py (caddr q)))))
                (if (= 0 (cadr c))
                  (cons (list px py (caddr q)) pts)
                  (append pts (list (list px py (caddr q)))))))
    (setq model (rr:troca model (car c) (rr:flag (rr:troca ra 4 pts) 'MOD)))
    (rr:log modo ra px py (rr:xy (car q) (cadr q)) (rr:xy px py))
    ;; vértice na linha vizinha
    (if (not pv)
      (progn
        (setq rb (nth (nth 5 c) model))
        (setq model (rr:troca model (nth 5 c) (rr:flag (rr:troca rb 4 (rr:ins-ponto (nth 4 rb) (nth 3 rb) px py)) 'MOD)))
        (rr:log "INSERIR_VERTICE" rb px py "ponta solta" (rr:xy px py)))))))
  model
)

;;; o ponto q (ponta da linha id) coincide com algum OUTRO vértice da rede?
(defun rr:conectado-p (model id q / n)
  (setq n 0)
  (foreach r model
    (if (rr:ativo-p r)
      (foreach p (nth 4 r)
        (if (<= (rr:dist p q) *RR-EPS0*) (setq n (1+ n))))))
  (> n 1)
)

;;; vértices nos cruzamentos e T (em lote por linha)
(defun rr:c-inserir (model / an reqs porent g)
  (setq an (rr:analisa model *RR-PONTA* *RR-QUASE*))
  (foreach c (nth 1 an)
    (setq reqs (cons (list (nth 2 c) (nth 3 c) (nth 4 c) (car c) (cadr c) "cruzamento")
                     (cons (list (nth 5 c) (nth 6 c) (nth 7 c) (car c) (cadr c) "cruzamento") reqs))))
  (foreach x (nth 2 an)
    (setq reqs (cons (list (nth 3 x) (nth 4 x) (nth 5 x) (car x) (cadr x) "T") reqs)))
  (setq reqs (vl-sort reqs '(lambda (a b) (cond ((/= (car a) (car b)) (< (car a) (car b)))
                                                ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))
                                                (T (< (caddr a) (caddr b)))))))
  (mapcar
    '(lambda (r / meus res k)
       (while (and reqs (= (car (car reqs)) (car r)))
         (setq meus (cons (car reqs) meus) reqs (cdr reqs)))
       (if (not meus)
         r
         (progn
           (setq meus (reverse meus) k 0)
           (mapcar '(lambda (p q)
                      (setq res (cons p res))
                      (while (and meus (= (cadr (car meus)) k))
                        (setq g (car meus) meus (cdr meus))
                        (if (and q (> (rr:d2 (nth 3 g) (nth 4 g) (car (car res)) (cadr (car res))) *RR-EPS0*)
                                 (> (rr:d2 (nth 3 g) (nth 4 g) (car q) (cadr q)) *RR-EPS0*))
                          (progn
                            (setq res (cons (list (nth 3 g) (nth 4 g)
                                                  (+ (caddr p) (* (nth 2 g) (- (caddr q) (caddr p)))))
                                            res))
                            (rr:log "INSERIR_VERTICE" r (nth 3 g) (nth 4 g) (nth 5 g) (rr:xy (nth 3 g) (nth 4 g))))))
                      (setq k (1+ k)))
                   (nth 4 r) (rr:proximos (nth 4 r) (nth 3 r)))
           (rr:flag (rr:troca r 4 (reverse res)) 'MOD))))
    model)
)

;;; divide pts removendo os segmentos rem -> lista de trechos (pts)
(defun rr:divide (pts fech rems / n i rot runs cur k)
  (setq n (length pts))
  (if fech
    (progn
      ;; começa logo depois do primeiro segmento removido
      (setq i    (1+ (apply 'min rems))
            rot  (sp:gira pts (rem i n))
            rot  (append rot (list (car rot)))
            rems (mapcar '(lambda (k) (rem (+ (- k i) n n) n)) rems)
            pts  rot)))
  (setq k 0)
  (mapcar '(lambda (a b)
             (if (member k rems)
               (progn (if cur (setq runs (cons (reverse cur) runs))) (setq cur nil))
               (setq cur (cons b (if cur cur (list a)))))
             (setq k (1+ k)))
          pts (cdr pts))
  (if cur (setq runs (cons (reverse cur) runs)))
  (reverse runs)
)

;;; segmentos idênticos (mesmas pontas) entre linhas ou na mesma linha:
;;; mantém o primeiro (menor id), remove os outros dividindo a linha
;;; pontas normalizadas: por x (com tolerância), depois por y
(defun rr:menor (a b)
  (if (> (abs (- (car a) (car b))) *RR-EPS0*) (< (car a) (car b)) (< (cadr a) (cadr b)))
)

(defun rr:c-sobrep (model / segs g remov novos nid k s fora)
  (foreach r model
    (if (rr:ativo-p r)
      (progn
        (setq k 0)
        (mapcar '(lambda (a b)
                   (if b
                     (setq segs (cons (if (rr:menor a b)
                                        (list (car a) (cadr a) (car b) (cadr b) (car r) k)
                                        (list (car b) (cadr b) (car a) (cadr a) (car r) k))
                                      segs)))
                   (setq k (1+ k)))
                (nth 4 r) (if (and (nth 3 r) (> (length (nth 4 r)) 2)) (rr:proximos (nth 4 r) T) (cdr (nth 4 r)))))))
  (setq segs (vl-sort segs '(lambda (a b) (cond ((/= (nth 0 a) (nth 0 b)) (< (nth 0 a) (nth 0 b)))
                                                ((/= (nth 1 a) (nth 1 b)) (< (nth 1 a) (nth 1 b)))
                                                ((/= (nth 2 a) (nth 2 b)) (< (nth 2 a) (nth 2 b)))
                                                ((/= (nth 3 a) (nth 3 b)) (< (nth 3 a) (nth 3 b)))
                                                ((/= (nth 4 a) (nth 4 b)) (< (nth 4 a) (nth 4 b)))
                                                (T (< (nth 5 a) (nth 5 b)))))))
  ;; janela em x: entre dois iguais pode haver outro segmento que sai do mesmo ponto
  (while segs
    (setq g (car segs) segs (cdr segs))
    (if (not (member g fora))
      (progn
        (setq s segs)
        (while (and s (<= (- (nth 0 (car s)) (nth 0 g)) (* 2.0 *RR-EPS0*)))
          (if (and (not (member (car s) fora))
                   (<= (rr:d2 (nth 0 g) (nth 1 g) (nth 0 (car s)) (nth 1 (car s))) *RR-EPS0*)
                   (<= (rr:d2 (nth 2 g) (nth 3 g) (nth 2 (car s)) (nth 3 (car s))) *RR-EPS0*))
            (setq fora  (cons (car s) fora)
                  remov (cons (list (nth 4 (car s)) (nth 5 (car s)) g) remov)))
          (setq s (cdr s))))))
  (if remov
    (progn
      (setq nid (length model))
      (setq model
        (mapcar
          '(lambda (r / meus runs)
             (setq meus (mapcar 'cadr (vl-remove-if-not '(lambda (x) (= (car x) (car r))) remov)))
             (if (not meus)
               r
               (progn
                 (foreach x (vl-remove-if-not '(lambda (x) (= (car x) (car r))) remov)
                   (rr:log "REMOVER_SOBREPOSICAO" r (nth 0 (caddr x)) (nth 1 (caddr x))
                           (strcat (rr:xy (nth 0 (caddr x)) (nth 1 (caddr x))) " - " (rr:xy (nth 2 (caddr x)) (nth 3 (caddr x))))
                           "removido"))
                 (setq runs (rr:divide (nth 4 r) (nth 3 r) meus))
                 (cond
                   ((null runs) (rr:log "APAGAR_ENTIDADE" r (car (car (nth 4 r))) (cadr (car (nth 4 r))) "duplicada" "")
                                (rr:flag r 'DEL))
                   (T
                    (foreach p (cdr runs)
                      (setq novos (cons (list (+ nid (length novos)) nil (nth 2 r) nil p
                                              (vl-remove 'DEL (cons 'NOVO (cons 'MOD (nth 5 r)))) (nth 6 r))
                                        novos)))
                    (if (cdr runs) (rr:log "DIVIDIR" r (car (car (car runs))) (cadr (car (car runs))) "1" (itoa (length runs))))
                    (rr:flag (rr:troca (rr:troca r 4 (car runs)) 3 nil) 'MOD))))))
          model))
      (append model (reverse novos)))
    model)
)

(defun rr:corrige (model / n0 passo)
  (setq model (rr:c-zeros model)
        model (rr:c-unir model)
        passo 0 n0 -1)
  (while (and (< passo 6) (/= n0 (length *rr-log*)))
    (setq n0    (length *rr-log*)
          model (rr:c-pontas model)
          model (rr:c-inserir model)
          model (rr:c-unir model)
          model (rr:c-sobrep model)
          model (rr:c-zeros model)
          passo (1+ passo)))
  model
)

;;; --------------------------------------------------------------------------
;;; Gravação do modelo no desenho
;;; --------------------------------------------------------------------------
(defun rr:sem-ids (ed) (vl-remove-if '(lambda (g) (member (car g) '(-1 5 102 330 360))) ed))
(defun rr:props (ed) (vl-remove-if-not '(lambda (g) (member (car g) '(6 8 39 48 62 370 410 420 430 440))) ed))

(defun rr:mk-lw (ed pts fech)
  (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")) (rr:props ed)
                   (list '(100 . "AcDbPolyline") (cons 90 (length pts)) (cons 70 (if fech 1 0))
                         (cons 38 (caddr (car pts))))
                   (mapcar '(lambda (p) (cons 10 (list (car p) (cadr p)))) pts)
                   (list '(210 0.0 0.0 1.0))))
)

(defun rr:pl-grava (ed pts fech v3 / ok lay)
  (setq lay (assoc 8 ed)
        ok  (entmake (subst (cons 70 (if fech (logior 1 (cdr (assoc 70 ed))) (logand (~ 1) (cdr (assoc 70 ed)))))
                            (assoc 70 ed) (rr:sem-ids ed))))
  (foreach p pts
    (if ok
      (setq ok (entmake (if v3
                          (list '(0 . "VERTEX") '(100 . "AcDbEntity") lay '(100 . "AcDbVertex")
                                '(100 . "AcDb3dPolylineVertex") (cons 10 p) '(70 . 32))
                          (list '(0 . "VERTEX") '(100 . "AcDbEntity") lay '(100 . "AcDbVertex")
                                '(100 . "AcDb2dVertex") (cons 10 p) '(70 . 0)))))))
  (if ok (entmake (list '(0 . "SEQEND") '(100 . "AcDbEntity") lay)))
)

;;; grava UM registro (e: entidade a alterar, ou nil = criar a partir de origem)
(defun rr:grava-reg (r / e ed tp pts fech dados segs)
  (setq e (nth 1 r) ed (entget (nth 6 r) '("*")) tp (nth 2 r) pts (nth 4 r) fech (nth 3 r))
  (cond
    ((member 'CONV (nth 5 r))
     (rr:mk-lw ed pts fech)
     (if e (entdel e)))
    ((= tp "LINE")
     (mapcar '(lambda (a b)
                (if b
                  (if e
                    (progn (entmod (subst (cons 11 b) (assoc 11 ed) (subst (cons 10 a) (assoc 10 ed) ed)))
                           (setq e nil))
                    (entmake (subst (cons 11 b) (assoc 11 ed) (subst (cons 10 a) (assoc 10 ed) (rr:sem-ids ed)))))))
             pts (rr:proximos pts fech)))
    ((= tp "LWPOLYLINE")
     (setq dados (sp:lw-le (entget (nth 6 r)))
           dados (list (subst (cons 70 (if fech (logior 1 (cdr (assoc 70 (car dados)))) (logand (~ 1) (cdr (assoc 70 (car dados))))))
                              (assoc 70 (car dados)) (car dados))
                       (mapcar '(lambda (p) (list (list (car p) (cadr p)) 0.0 0.0 0.0)) pts)
                       (caddr dados)))
     (if e
       (sp:lw-grava (car dados) (cadr dados) (caddr dados))
       (entmake (append (subst (cons 90 (length pts)) (assoc 90 (car dados)) (rr:sem-ids (car dados)))
                        (apply 'append (mapcar '(lambda (x) (list (cons 10 (car x)) '(40 . 0.0) '(41 . 0.0) '(42 . 0.0))) (cadr dados)))
                        (caddr dados)))))
    (T                                                          ; POLYLINE 2D / 3D
     (rr:pl-grava ed pts fech (= tp "POLYLINE3D"))
     (if e (entdel e))))
)

(defun rr:grava (model / n)
  (setq n 0)
  ;; primeiro os trechos novos (a origem ainda existe), depois os alterados
  (foreach r model
    (if (and (member 'NOVO (nth 5 r)) (rr:ativo-p r)) (progn (rr:grava-reg r) (setq n (1+ n)))))
  (foreach r model
    (cond
      ((member 'NOVO (nth 5 r)))
      ((not (rr:ativo-p r)) (if (and (nth 1 r) (entget (nth 1 r))) (progn (entdel (nth 1 r)) (setq n (1+ n)))))
      ((member 'MOD (nth 5 r)) (rr:grava-reg r) (setq n (1+ n)))))
  n
)

;;; --------------------------------------------------------------------------
;;; CRS / EPSG
;;; --------------------------------------------------------------------------
(defun rr:epsg-num (s / n)
  (if (and (= 'STR (type s)) (wcmatch s "#*") (not (wcmatch s "*[~0-9]*")))
    (setq n (atoi s)))
  n
)
;;; código do Map/Civil -> EPSG
(defun rr:epsg-de-codigo (c / z suf)
  (if c
    (progn
      (setq c (strcase c))
      (if (wcmatch c "*-##[NS],*-#[NS]")
        (setq z   (atoi (substr c (+ 2 (vl-string-position (ascii "-") c 0 T)) 2))
              suf (substr c (strlen c))))
      (cond
        ((= c "LL84") 4326)
        ((and z (= suf "S") (wcmatch c "SIRGAS2000.UTM-*,SA-SIR-*") (<= 17 z 25)) (+ 31960 z))
        ((and z (wcmatch c "UTM84-*")) (+ (if (= suf "S") 32700 32600) z))
        ((and z (= suf "S") (wcmatch c "SAD69.UTM-*") (<= 17 z 25)) (+ 29160 z)))))
)
(defun rr:codigo-desenho (/ r)
  (cond
    ((and cs:atual (setq r (vl-catch-all-apply 'cs:atual nil)) (not (vl-catch-all-error-p r))) r)
    ((and (= 'EXRXSUBR (type ade_projgetwscode))
          (setq r (vl-catch-all-apply 'ade_projgetwscode nil))
          (not (vl-catch-all-error-p r)) (= 'STR (type r)) (/= r "")) r))
)
(defun rr:epsg (/ c)
  (cond
    ((rr:epsg-num *RR-EPSG*))
    ((rr:epsg-de-codigo (setq c (rr:codigo-desenho))))
    (T nil))
)
;;; EPSG que o viewer/js/geo.js resolve
(defun rr:epsg-aceito (n)
  (and n (or (member n '(4326 4674 4989 4618 4258 4269 3857 900913 102100 5880))
             (<= 32601 n 32660) (<= 32701 n 32760) (<= 31977 n 31985) (<= 29177 n 29185)))
)
;;; faixa plausível -> (xmin ymin xmax ymax) ou nil
(defun rr:faixa (n)
  (cond
    ((or (<= 32701 n 32760) (<= 31977 n 31985) (<= 29177 n 29185)) '(100000.0 1000000.0 900000.0 10000000.0))
    ((<= 32601 n 32660) '(100000.0 0.0 900000.0 9400000.0))
    ((member n '(3857 900913 102100)) '(-20037509.0 -20048967.0 20037509.0 20048967.0))
    ((= n 5880) '(2000000.0 5000000.0 8000000.0 12000000.0))
    ((member n '(4326 4674 4989 4618 4258 4269)) '(-180.0 -90.0 180.0 90.0)))
)

;;; --------------------------------------------------------------------------
;;; Erros: (tipo x y handle1 handle2 descrição sugestão)
;;; --------------------------------------------------------------------------
(defun rr:hv (model / v)
  (setq v (rr:vet (length model) vlax-vbString nil))
  (foreach r model (rr:vp v (car r) (rr:handle r)))
  v
)
(defun rr:erros (model an naosup / hv er epsg fx n c)
  (setq hv (rr:hv model))
  (foreach x (nth 1 an)
    (setq er (cons (list "CRUZAMENTO" (car x) (cadr x) (rr:vg hv (nth 2 x)) (rr:vg hv (nth 5 x))
                         "Cruzamento sem vértice comum: as linhas não se conectam"
                         "Inserir o vértice nas duas linhas (REDE_CORRIGIR)") er)))
  (foreach x (nth 2 an)
    (setq er (cons (list "T_SEM_VERTICE" (car x) (cadr x) (rr:vg hv (nth 3 x)) (rr:vg hv (nth 2 x))
                         "Vértice sobre o segmento de outra linha, que não tem vértice ali"
                         "Inserir o vértice na linha atravessada (REDE_CORRIGIR)") er)))
  (foreach x (nth 4 an)
    (setq er (cons (list "PONTA_SOLTA" (nth 3 x) (nth 4 x) (rr:vg hv (car x)) (rr:vg hv (nth 5 x))
                         (strcat "Ponta solta a " (rtos (nth 2 x) 2 2) " m de outra linha, sem tocar")
                         "Estender/ligar até a linha vizinha e criar o vértice nela (REDE_CORRIGIR)") er)))
  (foreach x (car an)
    (setq er (cons (list "QUASE_COINCIDENTE" (nth 1 (cadr x)) (nth 2 (cadr x))
                         (rr:vg hv (nth 3 (cadr x))) (rr:vg hv (nth 3 (caddr x)))
                         (strcat "Vértices a " (rtos (car x) 2 4) " m: podem não se unir na grade de conexão")
                         "Unir na mesma coordenada (REDE_CORRIGIR)") er)))
  (foreach x (nth 3 an)
    (setq er (cons (list (if (nth 5 x) "DUPLICADA" "SOBREPOSTA") (nth 3 x) (nth 4 x)
                         (rr:vg hv (car x)) (rr:vg hv (cadr x))
                         (if (nth 5 x) "Linha duplicada (coberta inteira por outra)"
                           (strcat "Trecho sobreposto de " (rtos (caddr x) 2 2) " m"))
                         "Remover o trecho repetido (REDE_CORRIGIR)") er)))
  (foreach x (nth 5 an)
    (setq er (cons (list "SEGMENTO_ZERO" (car x) (cadr x) (rr:vg hv (caddr x)) ""
                         "Segmento de comprimento zero (vértice repetido)"
                         "Remover o vértice repetido (REDE_CORRIGIR)") er)))
  (foreach x naosup
    (setq er (cons (list "NAO_SUPORTADA" (car (cadddr x)) (cadr (cadddr x)) (cdr (assoc 5 (entget (cadr x)))) ""
                         (strcat (caddr x) " na camada da rede (não vira linha da rede)")
                         (if (nth 4 x) "REDE_CORRIGIR converte em polilinha" "Remover ou mudar de camada")) er)))
  (foreach r model
    (if (member 'ZVAR (nth 5 r))
      (setq er (cons (list "Z_VARIAVEL" (car (car (nth 4 r))) (cadr (car (nth 4 r))) (rr:vg hv (car r)) ""
                           "Z variável (o Routes Analyzer ignora o Z; a cota vem do MDT)"
                           "Achatar Z (opção do REDE_CORRIGIR)") er)))
    (if (member 'ARCOS (nth 5 r))
      (setq er (cons (list "ARCOS" (car (car (nth 4 r))) (cadr (car (nth 4 r))) (rr:vg hv (car r)) ""
                           "Polilinha com arcos: os arcos viram vértices na correção/exportação"
                           "Nenhuma (aviso); REDE_CORRIGIR densifica") er))))
  ;; fragmentos
  (foreach f (caddr (nth 6 an))
    (setq c (car (nth 4 (nth (car (cadr f)) model))))
    (setq er (cons (list "FRAGMENTO" (car c) (cadr c) (rr:vg hv (car (cadr f))) ""
                         (strcat "Fragmento isolado: " (itoa (length (cadr f))) " linha(s), "
                                 (rtos (car f) 2 1) " m ("
                                 (rtos (* 100.0 (/ (car f) (max 1e-9 (cadddr (nth 6 an))))) 2 1) "% da rede)")
                         "Ligar à rede principal (ver os outros erros perto dele)") er)))
  ;; CRS, unidade e faixa de coordenadas
  (setq epsg (rr:epsg) c (if model (car (nth 4 (car model))) '(0.0 0.0)))
  (cond
    ((not epsg)
     (setq er (cons (list "CRS" (car c) (cadr c) "" "" "Sistema de coordenadas desconhecido"
                          "Definir no SISCOORD ou informar o EPSG no diálogo") er)))
    ((not (rr:epsg-aceito epsg))
     (setq er (cons (list "CRS" (car c) (cadr c) "" "" (strcat "EPSG " (itoa epsg) " não é reconhecido pelo Routes Analyzer")
                          "Usar SIRGAS 2000 UTM (31977-31985), WGS 84 UTM ou informar proj4 no visualizador") er))))
  (if (/= 6 (getvar "INSUNITS"))
    (setq er (cons (list "UNIDADE" (car c) (cadr c) "" "" (strcat "INSUNITS = " (itoa (getvar "INSUNITS")) " (não é metro)")
                         "Desenho deve estar em metros (INSUNITS = 6)") er)))
  (if (and epsg (setq fx (rr:faixa epsg)))
    (progn
      (setq n 0)
      (foreach r model
        (if (and (< n 50)
                 (vl-some '(lambda (p) (or (< (car p) (car fx)) (< (cadr p) (cadr fx))
                                           (> (car p) (caddr fx)) (> (cadr p) (cadddr fx))))
                          (nth 4 r)))
          (setq n  (1+ n)
                er (cons (list "COORDENADAS" (car (car (nth 4 r))) (cadr (car (nth 4 r))) (rr:vg hv (car r)) ""
                               (strcat "Fora da faixa plausível do EPSG " (itoa epsg)
                                       (if (and (< (abs (car (car (nth 4 r)))) 100000.0) (< (abs (cadr (car (nth 4 r)))) 100000.0))
                                         ": coordenadas locais (perto de 0,0)" ": unidade ou sistema errado"))
                               "Conferir sistema de coordenadas e unidade do desenho") er))))))
  (reverse er)
)

;;; --------------------------------------------------------------------------
;;; Marcadores, relatório e navegação
;;; --------------------------------------------------------------------------
(defun rr:camada-erros ()
  (if (not (tblsearch "LAYER" *RR-LAYER*))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 *RR-LAYER*) '(70 . 0) '(62 . 1) '(6 . "Continuous") '(290 . 0))))
  (if (not (tblsearch "APPID" *RR-LAYER*)) (regapp *RR-LAYER*))
)
(defun rr:limpa-marcas (/ ss i)
  (if (setq ss (ssget "_X" (list (cons 8 *RR-LAYER*))))
    (repeat (setq i (sslength ss)) (entdel (ssname ss (setq i (1- i))))))
)
(defun rr:marca (n er / tp cor x y r)
  (setq tp (assoc (car er) *RR-TIPOS*) cor (cadr tp) x (nth 1 er) y (nth 2 er) r *RR-MARCA*)
  (entmake (list '(0 . "CIRCLE") (cons 8 *RR-LAYER*) (cons 62 cor) (list 10 x y 0.0) (cons 40 r)
                 (list -3 (list *RR-LAYER* (cons 1071 n) (cons 1000 (car er)) (cons 1000 (rr:corta (nth 5 er) 250))
                                (cons 1000 (rr:corta (nth 6 er) 250))
                                (cons 1000 (strcat (nth 3 er) "," (nth 4 er)))))))
  (entmake (list '(0 . "TEXT") (cons 8 *RR-LAYER*) (cons 62 cor) (list 10 (+ x r) (+ y r) 0.0) (cons 40 r)
                 (cons 1 (strcat (itoa n) " " (caddr tp)))))
)
(defun rr:csv-campo (s) (if (wcmatch s "*;*,*\"*") (strcat "\"" (vl-string-subst "\"\"" "\"" s) "\"") s))
(defun rr:arq (sufixo) (strcat (getvar "DWGPREFIX") (vl-filename-base (getvar "DWGNAME")) sufixo))

(defun rr:grava-csv (arq cab linhas / f)
  (if (setq f (open arq "w"))
    (progn
      (write-line cab f)
      (foreach l linhas (write-line (apply 'strcat (cdr (apply 'append (mapcar '(lambda (c) (list ";" (rr:csv-campo c))) l)))) f))
      (close f)
      arq))
)

(defun rr:resumo (an er / cont)
  (foreach e er
    (setq cont (if (assoc (car e) cont)
                 (subst (cons (car e) (1+ (cdr (assoc (car e) cont)))) (assoc (car e) cont) cont)
                 (cons (cons (car e) 1) cont))))
  (strcat "\nComponentes conexos: " (itoa (car (nth 6 an)))
          " (principal " (rtos (* 100.0 (cadr (nth 6 an))) 2 1) "% do comprimento, "
          (rtos (/ (cadddr (nth 6 an)) 1000.0) 2 3) " km)"
          (apply 'strcat (mapcar '(lambda (c) (strcat "\n  " (car c) ": " (itoa (cdr c)))) (reverse cont))))
)

;;; valida, marca e grava o relatório -> (análise erros)
(defun rr:valida (marcar / dz lido model an er arq n)
  (setq dz (getvar "DIMZIN"))
  (setvar "DIMZIN" 0)
  (setq lido (rr:le-rede nil) model (car lido)
        an   (rr:analisa model *RR-PONTA* *RR-QUASE*)
        er   (rr:erros model an (cadr lido)))
  (if marcar
    (progn
      (rr:camada-erros)
      (rr:limpa-marcas)
      (setq n 0)
      (foreach e er (rr:marca (setq n (1+ n)) e))
      (setq n 0
            arq (rr:grava-csv (rr:arq "_REDE_validacao.csv") "n;tipo;descricao;x;y;handle;handle2;sugestao"
                              (mapcar '(lambda (e) (list (itoa (setq n (1+ n))) (car e) (nth 5 e)
                                                         (rtos (nth 1 e) 2 3) (rtos (nth 2 e) 2 3)
                                                         (nth 3 e) (nth 4 e) (nth 6 e)))
                                      er)))
      (setq *RR-IDX* nil)))
  (princ (strcat "\n" (itoa (length model)) " linha(s) na rede, " (itoa (length er)) " erro(s)/aviso(s)."
                 (rr:resumo an er)))
  (if (and marcar arq) (princ (strcat "\nRelatório: " arq "\nMarcadores no layer " *RR-LAYER* " - use REDE_PROXIMO / REDE_ANTERIOR.")))
  (setvar "DIMZIN" dz)
  (list an er)
)

(defun rr:marcas (/ ss i e xd l)
  (if (setq ss (ssget "_X" (list '(0 . "CIRCLE") (cons 8 *RR-LAYER*) (list -3 (list *RR-LAYER*)))))
    (repeat (setq i (sslength ss))
      (setq e  (ssname ss (setq i (1- i)))
            xd (cdr (assoc *RR-LAYER* (cdr (assoc -3 (entget e (list *RR-LAYER*)))))))
      (if (assoc 1071 xd) (setq l (cons (list (cdr (assoc 1071 xd)) e xd) l)))))
  (vl-sort l '(lambda (a b) (< (car a) (car b))))
)
(defun rr:vai (passo / l n m s c ss h)
  (setq l (rr:marcas) n (length l))
  (if (= n 0)
    (princ "\nNenhum marcador em REDE_ERROS: rode REDE_VALIDAR.")
    (progn
      (setq *RR-IDX* (if *RR-IDX* (rem (+ *RR-IDX* passo n) n) (if (> passo 0) 0 (1- n)))
            m (nth *RR-IDX* l)
            s (mapcar 'cdr (vl-remove-if-not '(lambda (g) (= 1000 (car g))) (caddr m)))
            c (cdr (assoc 10 (entget (cadr m)))))
      (vla-ZoomCenter (vlax-get-acad-object) (vlax-3d-point c) (* 30.0 (cdr (assoc 40 (entget (cadr m))))))
      (princ (strcat "\n[" (itoa (1+ *RR-IDX*)) "/" (itoa n) "] " (car s) ": " (cadr s)
                     "\n  Sugestão: " (caddr s)))
      (setq ss (ssadd))
      (foreach h (rr:separa (cadddr s) ",")
        (if (and (/= h "") (setq h (handent h)) (entget h)) (ssadd h ss)))
      (ssadd (cadr m) ss)
      (sssetfirst nil ss)))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Exportação GeoJSON
;;; --------------------------------------------------------------------------
(defun rr:hex4 (n / s d)
  (setq s "")
  (repeat 4 (setq d (rem n 16) s (strcat (substr "0123456789ABCDEF" (1+ d) 1) s) n (/ n 16)))
  s
)
(defun rr:json-str (s / r)
  (setq r "")
  (foreach c (vl-string->list s)
    (setq r (strcat r (cond ((= c 34) "\\\"") ((= c 92) "\\\\")
                            ((or (< c 32) (> c 126)) (strcat "\\u" (rr:hex4 c)))
                            (T (chr c))))))
  (strcat "\"" r "\"")
)
(defun rr:exporta (arq epsg / dz lido model f prim n)
  (setq dz (getvar "DIMZIN"))
  (setvar "DIMZIN" 0)
  (setq lido (rr:le-rede nil) model (car lido) n 0)
  (if (setq f (open arq "w"))
    (progn
      (write-line "{\"type\":\"FeatureCollection\",\"name\":\"rede\"," f)
      (write-line (strcat "\"crs\":{\"type\":\"name\",\"properties\":{\"name\":\"urn:ogc:def:crs:EPSG::" (itoa epsg) "\"}},") f)
      (write-line "\"features\":[" f)
      (setq prim T)
      (foreach r model
        (if (> (length (rr:limpa-pts (nth 4 r) (nth 3 r))) 1)
          (progn
            (if (not prim) (write-line "," f))
            (setq prim nil n (1+ n))
            (princ (strcat "{\"type\":\"Feature\",\"properties\":{\"handle\":" (rr:json-str (rr:handle r))
                           ",\"layer\":" (rr:json-str (cdr (assoc 8 (entget (nth 1 r)))))
                           "},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[") f)
            (setq prim T)
            (foreach p (if (nth 3 r) (append (nth 4 r) (list (car (nth 4 r)))) (nth 4 r))
              (princ (strcat (if prim "" ",") "[" (rtos (car p) 2 4) "," (rtos (cadr p) 2 4) "]") f)
              (setq prim nil))
            (princ "]}}" f))))
      (write-line "" f)
      (write-line "]}" f)
      (close f)))
  (setvar "DIMZIN" dz)
  (list n (length (cadr lido)))
)

;;; --------------------------------------------------------------------------
;;; Diálogo e comandos
;;; --------------------------------------------------------------------------
(defun rr:ini-tiles (corr)
  (set_tile "camadas" *RR-CAMADAS*)
  (set_tile "ponta" (rtos *RR-PONTA* 2 2))
  (set_tile "quase" (rtos *RR-QUASE* 2 3))
  (set_tile "dens"  (rtos *RR-DENS* 2 2))
  (set_tile "marca" (rtos *RR-MARCA* 2 2))
  (set_tile "epsg"  *RR-EPSG*)
  (set_tile "auto"  (strcat "Do desenho: " (cond ((rr:codigo-desenho)) ("(nenhum)"))
                            (if (rr:epsg-de-codigo (rr:codigo-desenho))
                              (strcat " = EPSG " (itoa (rr:epsg-de-codigo (rr:codigo-desenho)))) "")))
  (if corr
    (progn
      (set_tile "simula"   (if *RR-SIMULA* "1" "0"))
      (set_tile "achata"   (if *RR-ACHATA* "1" "0"))
      (set_tile "converte" (if *RR-CONVERTE* "1" "0"))))
)
(defun rr:le-tiles (corr / v)
  (setq v (mapcar 'rr:num-tile '("ponta" "quase" "dens" "marca"))
        *RR-CAMADAS* (strcase (vl-string-trim " " (get_tile "camadas")))
        *RR-EPSG* (vl-string-trim " " (get_tile "epsg")))
  (if corr
    (setq *RR-SIMULA* (= "1" (get_tile "simula")) *RR-ACHATA* (= "1" (get_tile "achata"))
          *RR-CONVERTE* (= "1" (get_tile "converte"))))
  (cond
    ((= *RR-CAMADAS* "") (set_tile "error" "Informe as camadas da rede.") nil)
    ((vl-some '(lambda (x) (not (and x (> x 0.0)))) v) (set_tile "error" "Os valores devem ser > 0.") nil)
    ((and (/= *RR-EPSG* "") (not (rr:epsg-num *RR-EPSG*))) (set_tile "error" "EPSG inválido (só números).") nil)
    (T (setq *RR-PONTA* (car v) *RR-QUASE* (cadr v) *RR-DENS* (caddr v) *RR-MARCA* (cadddr v))
       (rr:grava-env)
       T))
)
(defun rr:seleciona-camadas (/ ss i l c)
  (princ "\nSelecione um objeto de cada camada da rede: ")
  (if (setq ss (ssget))
    (progn
      (setq l (if (/= *RR-CAMADAS* "") (rr:separa *RR-CAMADAS* ",")))
      (repeat (setq i (sslength ss))
        (setq c (strcase (cdr (assoc 8 (entget (ssname ss (setq i (1- i))))))))
        (if (and (/= c *RR-LAYER*) (not (member c l))) (setq l (append l (list c)))))
      (setq *RR-CAMADAS* (apply 'strcat (cdr (apply 'append (mapcar '(lambda (c) (list "," c)) l)))))
      (rr:grava-env)))
)
(defun rr:dialogo (nome corr / dcl arq r)
  (setq arq (if (rr:pasta) (strcat (rr:pasta) "\\RedeRotas.dcl")) r 2)
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo RedeRotas.dcl não encontrado.") (exit)))
  (while (= r 2)
    (setq dcl (load_dialog arq))
    (if (not (new_dialog nome dcl)) (progn (unload_dialog dcl) (alert "Erro ao abrir o diálogo.") (exit)))
    (rr:ini-tiles corr)
    (action_tile "selcam" (strcat "(rr:le-tiles " (if corr "T" "nil") ") (done_dialog 2)"))
    (action_tile "accept" (strcat "(if (rr:le-tiles " (if corr "T" "nil") ") (done_dialog 1))"))
    (action_tile "cancel" "(done_dialog 0)")
    (setq r (start_dialog))
    (unload_dialog dcl)
    (if (= r 2) (rr:seleciona-camadas)))
  (= r 1)
)
(defun rr:prepara ()
  (if (= 0 (getvar "TILEMODE")) (setvar "TILEMODE" 1))
  (rr:requer)
)

(defun c:REDE_VALIDAR (/ t0)
  (if (and (rr:prepara) (rr:dialogo "ra_validar" nil))
    (progn
      (setq t0 (getvar "MILLISECS"))
      (rr:valida T)
      (princ (strcat " [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))))
  (princ)
)

(defun c:REDE_CORRIGIR (/ *error* doc dz t0 lido model log arq n an er ok)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) dz (getvar "DIMZIN"))
  (defun *error* (msg)
    (setvar "DIMZIN" dz)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (if (and (rr:prepara) (rr:dialogo "ra_corrigir" T))
    (progn
      (setvar "DIMZIN" 0)
      (setq t0 (getvar "MILLISECS") *rr-log* nil
            lido (rr:le-rede *RR-CONVERTE*) model (car lido))
      ;; conversões e Z (registradas no log)
      (setq model
        (mapcar '(lambda (r)
                   (cond
                     ((member 'CONV (nth 5 r))
                      (rr:log "CONVERTER" r (car (car (nth 4 r))) (cadr (car (nth 4 r))) (nth 2 r)
                              (strcat "LWPOLYLINE (" (itoa (length (nth 4 r))) " vértices)"))
                      (rr:flag r 'MOD))
                     ((and (member 'ZVAR (nth 5 r)) *RR-ACHATA*)
                      (rr:log "ACHATAR_Z" r (car (car (nth 4 r))) (cadr (car (nth 4 r))) "Z variável" "Z = 0")
                      (rr:flag (rr:troca (rr:troca r 4 (mapcar '(lambda (p) (list (car p) (cadr p) 0.0)) (nth 4 r)))
                                         5 (vl-remove 'ZVAR (nth 5 r)))
                               'MOD))
                     ((member 'ARCOS (nth 5 r))
                      (rr:log "DENSIFICAR_ARCOS" r (car (car (nth 4 r))) (cadr (car (nth 4 r))) "arcos"
                              (strcat (itoa (length (nth 4 r))) " vértices"))
                      (rr:flag (rr:troca r 5 (vl-remove 'ARCOS (nth 5 r))) 'MOD))
                     (T r)))
                model))
      (setq model (rr:corrige model)
            log   (reverse *rr-log*))
      (setq arq (rr:grava-csv (rr:arq "_REDE_correcoes.csv") "n;operacao;handle;x;y;antes;depois"
                              (progn (setq n 0)
                                     (mapcar '(lambda (l) (list (itoa (setq n (1+ n))) (car l) (cadr l)
                                                                (rtos (caddr l) 2 3) (rtos (cadddr l) 2 3)
                                                                (nth 4 l) (nth 5 l)))
                                             log))))
      (princ (strcat "\n" (itoa (length log)) " alteração(ões) " (if *RR-SIMULA* "SIMULADA(S)" "planejada(s)")
                     " em " (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s. Log: " (if arq arq "?")))
      (foreach op '("CONVERTER" "ACHATAR_Z" "DENSIFICAR_ARCOS" "UNIR_VERTICE" "ESTENDER_PONTA" "LIGAR_PONTA"
                    "INSERIR_VERTICE" "REMOVER_SOBREPOSICAO" "DIVIDIR" "REMOVER_SEGMENTO_ZERO" "APAGAR_ENTIDADE"
                    "IGNORADO_GRUPO_GRANDE")
        (if (setq n (length (vl-remove-if-not '(lambda (l) (= (car l) op)) log)))
          (if (> n 0) (princ (strcat "\n  " op ": " (itoa n))))))
      (cond
        ((null log) (princ "\nNada a corrigir."))
        (*RR-SIMULA*
         (setq an (rr:analisa model *RR-PONTA* *RR-QUASE*)
               er (rr:erros model an nil))
         (princ (strcat "\nResultado previsto (simulação, nada foi alterado):" (rr:resumo an er))))
        (T
         (initget "Sim Nao")
         (setq ok (getkword (strcat "\nAplicar as " (itoa (length log)) " alterações no desenho? [Sim/Nao] <Nao>: ")))
         (if (= ok "Sim")
           (progn
             (vla-StartUndoMark doc)
             (setq n (rr:grava model))
             (vla-EndUndoMark doc)
             (princ (strcat "\n" (itoa n) " entidade(s) gravada(s) (desfazer: U). Validando de novo..."))
             (rr:valida T))
           (princ "\nNada foi alterado.")))))
    )
  (setvar "DIMZIN" dz)
  (princ)
)

(defun c:REDE_PROXIMO () (rr:vai 1))
(defun c:REDE_ANTERIOR () (rr:vai -1))

(defun c:REDE_EXPORTAR (/ epsg arq r s)
  (if (rr:prepara)
    (progn
      (if (= *RR-CAMADAS* "") (rr:dialogo "ra_validar" nil))
      (if (not (setq epsg (rr:epsg)))
        (progn
          (setq s (getstring "\nEPSG do desenho (ex.: 31983): "))
          (if (setq epsg (rr:epsg-num s)) (progn (setq *RR-EPSG* s) (rr:grava-env)))))
      (cond
        ((not epsg) (princ "\nSem EPSG: exportação cancelada."))
        ((and (not (rr:epsg-aceito epsg))
              (progn (initget "Sim Nao")
                     (/= "Sim" (getkword (strcat "\nEPSG " (itoa epsg) " não é reconhecido pelo Routes Analyzer. Exportar mesmo assim? [Sim/Nao] <Nao>: "))))))
        ((setq arq (getfiled "Exportar rede (GeoJSON)" (rr:arq "_rede.geojson") "geojson" 1))
         (setq r (rr:exporta arq epsg))
         (princ (strcat "\n" (itoa (car r)) " linha(s) exportada(s) em EPSG " (itoa epsg) ": " arq))
         (if (> (cadr r) 0)
           (princ (strcat "\n" (itoa (cadr r)) " objeto(s) não suportado(s) nas camadas NÃO foram exportados (rode REDE_CORRIGIR)."))))
        )))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Outra versão para comparação: routes_analyzer\tools\autocad\RA_REDE.lsp
;;; (fica fora de lisps\, então o LISPS.mnl não a carrega sozinho)
;;; --------------------------------------------------------------------------
(defun rr:arq-ra (/ raiz arq)
  (setq raiz (cond (*LISPS-DIR* (vl-filename-directory *LISPS-DIR*))
                   ((rr:pasta) (vl-filename-directory (rr:pasta))))
        arq  (if raiz (strcat raiz "\\routes_analyzer\\tools\\autocad\\RA_REDE.lsp")))
  (if (and arq (findfile arq)) arq)
)
;;; carrega só se ainda não estiver carregada (força = recarrega)
(defun rr:carrega-ra (forca / arq r)
  (cond
    ((and c:RA_VERIFICAR (not forca)) T)
    ((not (setq arq (rr:arq-ra)))
     (princ "\nRA_REDE.lsp não encontrado em routes_analyzer\\tools\\autocad.") nil)
    ((vl-catch-all-error-p (setq r (vl-catch-all-apply 'load (list arq))))
     (princ (strcat "\nFalha ao carregar RA_REDE.lsp: " (vl-catch-all-error-message r))) nil)
    (T (princ (strcat "\nVersão RA_REDE carregada: " arq)) T))
)
(defun c:REDE_CARREGA_RA ()
  (if (rr:carrega-ra T)
    (princ "\nComandos da outra versão: RA_VERIFICAR, RA_CORRIGIR, RA_QUEBRAR, RA_PONTAS, RA_JUNTAR, RA_SEGMENTAR, RA_SEMCONEXAO, RA_PROXIMO, RA_LIMPAR, RA_DESENHAR, RA_CONFIG, RA_AJUDA"))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Configuração da Rede de Rotas (ferramentas RA_REDE) em diálogo: REDE_CONFIG
;;; Ajusta as variáveis *RA:...* usadas pelo RA_REDE.lsp sem alterar aquele
;;; arquivo (ele só define o padrão de cada variável se ela ainda estiver vazia).
;;; OK grava em config\REDE_RA_CONFIG.lsd, lido ao carregar este arquivo, então
;;; vale para todos os desenhos.
;;; --------------------------------------------------------------------------
(setq *RR-RA-VARS* '(*RA:LAYERS* *RA:DRAWLAYER* *RA:ONEWAY* *RA:TOL* *RA:GAP* *RA:MARK*)
      *RR-RA-PADRAO* '("REDE*" "REDE_ROTAS" "*MAO*UNICA*,*_MU" 0.001 2.0 2.0))

(defun rr:ra-padroes () (mapcar 'set *RR-RA-VARS* *RR-RA-PADRAO*))

;;; completa só as variáveis que ainda estão vazias
(defun rr:ra-garante ()
  (mapcar '(lambda (v p) (if (not (eval v)) (set v p))) *RR-RA-VARS* *RR-RA-PADRAO*)
)

(defun rr:ra-arq (/ p)
  (if (setq p (rr:pasta))
    (progn
      (setq p (strcat p "\\config"))
      (if (not (vl-file-directory-p p)) (vl-mkdir p))
      (strcat p "\\REDE_RA_CONFIG.lsd")))
)

(defun rr:ra-le (/ arq f l v)
  (if (and (setq arq (rr:ra-arq)) (findfile arq) (setq f (open arq "r")))
    (progn
      (setq l (read-line f))
      (close f)
      (setq v (vl-catch-all-apply 'read (list l)))
      (if (and (listp v) (= (length v) (length *RR-RA-VARS*)))
        (progn (mapcar 'set *RR-RA-VARS* v) T))))
)

(defun rr:ra-grava (/ arq f)
  (if (and (setq arq (rr:ra-arq)) (setq f (open arq "w")))
    (progn
      (write-line (vl-prin1-to-string (mapcar 'eval *RR-RA-VARS*)) f)
      (close f)
      T))
)

(defun rr:ra-num (s / v)
  (if s (setq v (distof (vl-string-translate "," "." (vl-string-trim " " s)) 2)))
  v
)

(defun rr:ra-preenche ()
  (set_tile "camadas"  *RA:LAYERS*)
  (set_tile "desenho"  *RA:DRAWLAYER*)
  (set_tile "maounica" *RA:ONEWAY*)
  (set_tile "tol"      (rtos *RA:TOL* 2 4))
  (set_tile "gap"      (rtos *RA:GAP* 2 2))
  (set_tile "marca"    (rtos *RA:MARK* 2 2))
  (set_tile "error"    "")
)

;;; lê e valida os campos; devolve T e grava nas variáveis se estiver tudo certo
(defun rr:ra-le-tiles (/ cam des mu tol gap mar)
  (setq cam (strcase (vl-string-trim " " (get_tile "camadas")))
        des (if tr:nome-padrao (tr:nome-padrao (get_tile "desenho"))
              (strcase (vl-string-trim " " (get_tile "desenho"))))
        mu  (strcase (vl-string-trim " " (get_tile "maounica")))
        tol (rr:ra-num (get_tile "tol"))
        gap (rr:ra-num (get_tile "gap"))
        mar (rr:ra-num (get_tile "marca")))
  (cond
    ((= cam "")                   (set_tile "error" "Informe as camadas da rede.") nil)
    ((not (and (/= des "") (snvalid des))) (set_tile "error" "Nome da camada de desenho inválido.") nil)
    ((not (and tol (> tol 0)))    (set_tile "error" "Tolerância de ponto igual inválida.") nil)
    ((not (and gap (> gap 0)))    (set_tile "error" "Distância de ponta solta inválida.") nil)
    ((not (and mar (> mar 0)))    (set_tile "error" "Raio dos marcadores inválido.") nil)
    (T
     (setq *RA:LAYERS* cam *RA:DRAWLAYER* des *RA:ONEWAY* (if (= mu "") "~*" mu)
           *RA:TOL* tol *RA:GAP* gap *RA:MARK* mar)
     (if (not (wcmatch des cam))
       (set_tile "error" "Aviso: a camada de desenho não está no filtro da rede."))
     T)
  )
)

;;; camadas dos objetos selecionados, separadas por vírgula
(defun rr:ra-camadas-sel (/ ss i lay lays)
  (princ "\nSelecione objetos da rede (as camadas deles formam o filtro): ")
  (if (setq ss (ssget))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq lay (strcase (cdr (assoc 8 (entget (ssname ss i))))) i (1+ i))
        (if (not (member lay lays)) (setq lays (cons lay lays))))
      (setq lays (vl-sort lays '<))
      (apply 'strcat (cons (car lays) (mapcar '(lambda (s) (strcat "," s)) (cdr lays))))))
)

(defun c:REDE_CONFIG (/ dcl arq r loop bak s)
  (rr:ra-garante)
  (setq bak  (mapcar 'eval *RR-RA-VARS*)
        arq  (if (rr:pasta) (strcat (rr:pasta) "\\RedeRotas.dcl"))
        loop T)
  (if (not (and arq (findfile arq)))
    (progn (alert "Arquivo RedeRotas.dcl não encontrado.") (setq loop nil)))
  (while loop
    (setq dcl (load_dialog arq))
    (if (not (new_dialog "rede_config" dcl))
      (progn (unload_dialog dcl) (alert "Erro ao abrir o diálogo.") (setq loop nil r 0))
      (progn
        (rr:ra-preenche)
        (action_tile "selcam" "(if (rr:ra-le-tiles) (done_dialog 2))")
        (action_tile "padrao" "(rr:ra-padroes) (rr:ra-preenche)")
        (action_tile "accept" "(if (rr:ra-le-tiles) (done_dialog 1))")
        (action_tile "cancel" "(done_dialog 0)")
        (setq r (start_dialog))
        (unload_dialog dcl)
        (cond
          ((= r 2) (if (setq s (rr:ra-camadas-sel)) (setq *RA:LAYERS* s)))
          ((= r 1)
           (setq loop nil)
           (if (rr:ra-grava)
             (princ "\nConfiguração da Rede de Rotas gravada (vale para todos os desenhos).")
             (princ "\nConfiguração aplicada, mas não foi possível gravar o arquivo.")))
          (T (setq loop nil) (mapcar 'set *RR-RA-VARS* bak))
        )
      )
    )
  )
  (princ)
)

;;; aplica a configuração gravada assim que este arquivo carrega
(rr:ra-le)

(princ "\nRedeRotas carregado. Comandos: REDE_VALIDAR, REDE_CORRIGIR, REDE_PROXIMO, REDE_ANTERIOR, REDE_EXPORTAR, REDE_CONFIG")
(princ)
