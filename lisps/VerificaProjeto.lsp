;;; ==========================================================================
;;; VerificaProjeto.lsp - Verificação geral do projeto
;;; --------------------------------------------------------------------------
;;; VERIFICAPROJ  (equivalente ao CHECKDWG do AgroCAD - "Checagem Geral do
;;;               Projeto", sem a opção de simplificar talhões e terraços)
;;;
;;; Correções (alteram o desenho, tudo num único desfazer):
;;;   - Polilinhas 3D -> 2D: cada POLYLINE 3D vira LWPOLYLINE na elevação 0,
;;;     mesmas propriedades, XDATA e Object Data (Map); vértices repetidos
;;;     depois do achatamento são removidos;
;;;   - Linhas -> polilinhas: cada LINE vira LWPOLYLINE; com "Unir linhas
;;;     conectadas", linhas da mesma camada que se encontram ponta a ponta
;;;     num nó com só duas pontas viram uma polilinha só (fechada se formar
;;;     anel). Nós com 3 ou mais pontas não são unidos (não há escolha certa);
;;;   - Segmentar arcos: usa o SEGMENTARCOS (Simplifica.lsp) com a
;;;     configuração gravada nele (flecha ou medida fixa, arcos avulsos);
;;;   - Remover nós (RNOS): tira os laços dos auto-cruzamentos e os espinhos
;;;     (também como comando REMOVENOS, por seleção);
;;;   - Fechar talhões: polilinhas abertas nas camadas de talhões ficam
;;;     fechadas; se as pontas coincidem o vértice repetido sai, senão o
;;;     fechamento é feito e marcado em VERIFICA_FECHAMENTO para conferência.
;;;
;;; Verificações (só marcam, com círculos, para o usuário corrigir):
;;;   - Auto-cruzamentos (VERIFICA_AUTOCRUZAMENTO): onde uma polilinha cruza,
;;;     toca ou volta sobre si mesma (espinho). Arcos entram como cordas;
;;;   - Pseudo-nós (VERIFICA_PSEUDONO): ponto onde exatamente duas pontas de
;;;     curvas abertas da mesma camada se encontram (deviam ser uma curva só),
;;;     inclusive polilinha aberta com as duas pontas no mesmo lugar;
;;;   - Splines (VERIFICA_SPLINE): marcadas e deixadas selecionadas para a
;;;     conversão manual (SPLINEDIT > Converter em polilinha).
;;;
;;; Abrangência: desenho inteiro (espaço do modelo) ou seleção. Objetos em
;;; camadas travadas são verificados mas não alterados.
;;;
;;; Comandos: VERIFICAPROJ (diálogo), VERIFICAPROJ_LIMPA (apaga as marcas),
;;;           REMOVENOS (equivalente ao RNOS do AgroCAD)
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Parâmetros (persistem via setenv)
;;; --------------------------------------------------------------------------
(setq *VP-CHAVES* '(*VP-3D* *VP-LIN* *VP-JUNTA* *VP-ARC* *VP-FECHA* *VP-CRUZ* *VP-PSEUDO*
                    *VP-SPL* *VP-SEL* *VP-TOL* *VP-RAIO* *VP-CAMTAL* *VP-LIMPA* *VP-NOS*)
      *VP-MARCAS* '(("VERIFICA_AUTOCRUZAMENTO" 1) ("VERIFICA_PSEUDONO" 2)
                    ("VERIFICA_SPLINE" 6) ("VERIFICA_FECHAMENTO" 4)))

(defun vp:camtal-padrao (/ v)
  (setq v (if tr:cfg-nome (vl-catch-all-apply 'tr:cfg-nome (list 'NOM_LAY_TALHOES "TALHOES"))))
  (if (= 'STR (type v)) v "TALHOES")
)

(defun vp:padroes ()
  (mapcar 'set *VP-CHAVES* (list T T T T T T T T nil 0.001 2.0 (vp:camtal-padrao) T nil))
)

(defun vp:le-cfg (/ v)
  (vp:padroes)
  (if (and (setq v (getenv "LISPS_VERIFICAPROJ"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= (length v) (length *VP-CHAVES*))
           (numberp (nth 9 v)) (numberp (nth 10 v)) (= 'STR (type (nth 11 v))))
    (mapcar 'set *VP-CHAVES* v))
  (if (= *VP-CAMTAL* "TALHÕES") (setq *VP-CAMTAL* "TALHOES"))
)

(defun vp:grava-cfg () (setenv "LISPS_VERIFICAPROJ" (vl-prin1-to-string (mapcar 'eval *VP-CHAVES*))))

;;; --------------------------------------------------------------------------
;;; Utilidades
;;; --------------------------------------------------------------------------
(defun vp:2d (p) (list (car p) (cadr p)))
(defun vp:d2 (a b) (distance (vp:2d a) (vp:2d b)))
(defun vp:tipo (e) (cdr (assoc 0 (entget e))))
(defun vp:flags (e) (cond ((cdr (assoc 70 (entget e)))) (0)))
(defun vp:camada-de (e) (strcase (cdr (assoc 8 (entget e)))))

(defun vp:lista (ss / i l)
  (if ss (repeat (setq i (sslength ss)) (setq l (cons (ssname ss (setq i (1- i))) l))))
  l
)

(defun vp:vivos (l) (vl-remove-if-not 'entget l))

(defun vp:pasta ()
  (cond (*LISPS-DIR*)
        ((findfile "VerificaProjeto.lsp") (vl-filename-directory (findfile "VerificaProjeto.lsp"))))
)

;;; camadas travadas (em maiúsculas)
(defun vp:travadas (/ r l prim)
  (setq prim T)
  (while (setq r (tblnext "LAYER" prim))
    (setq prim nil)
    (if (= 4 (logand 4 (cdr (assoc 70 r)))) (setq l (cons (strcase (cdr (assoc 2 r))) l))))
  l
)

;;; T se o objeto pode ser alterado; senão conta como ignorado
(defun vp:editavel (e)
  (if (member (vp:camada-de e) trav)
    (progn (ssadd e travss) nil)
    T)
)

(defun vp:marca-p (e) (wcmatch (vp:camada-de e) "VERIFICA_*"))

;;; POLYLINE comum (2D ou 3D), sem malhas
(defun vp:pl-p (e) (and (= "POLYLINE" (vp:tipo e)) (zerop (logand 80 (vp:flags e)))))
(defun vp:3d-p (e) (and (vp:pl-p e) (= 8 (logand 8 (vp:flags e)))))
(defun vp:curva-pl-p (e) (or (= "LWPOLYLINE" (vp:tipo e)) (vp:pl-p e)))
(defun vp:fechada-p (e) (= 1 (logand 1 (vp:flags e))))

(defun vp:camada (nome cor)
  (if (not (tblsearch "LAYER" nome))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 nome) '(70 . 0) (cons 62 cor) '(6 . "Continuous"))))
)

;;; círculo de marcação na camada VERIFICA_* (k = índice em *VP-MARCAS*)
(defun vp:marca (k p / c)
  (setq c (nth k *VP-MARCAS*))
  (vp:camada (car c) (cadr c))
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 (car c)) '(100 . "AcDbCircle")
                 (list 10 (car p) (cadr p) 0.0) (cons 40 *VP-RAIO*)))
)

(defun vp:limpa-marcas (/ l)
  (setq l (vp:lista (ssget "_X" '((8 . "VERIFICA_*")))))
  (foreach e l (entdel e))
  (length l)
)

;;; propriedades gerais copiadas para o objeto novo
(defun vp:props (ed)
  (vl-remove-if-not '(lambda (g) (member (car g) '(6 8 39 48 62 67 370 420 430 440))) ed)
)

;;; LWPOLYLINE nova -> ename (pts 2D/3D, sem arcos)
(defun vp:mk-lw (props pts fech elev xd)
  (if (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity"))
                       props
                       (list '(100 . "AcDbPolyline") (cons 90 (length pts)) (cons 70 (if fech 1 0))
                             (cons 38 elev))
                       (mapcar '(lambda (p) (cons 10 (vp:2d p))) pts)
                       (if xd (list xd))))
    (entlast))
)

;;; Object Data do Map 3D (se houver) de um objeto para outro
(defun vp:copia-od (de para)
  (if ade_odgettables
    (vl-catch-all-apply
      '(lambda (/ i rec)
         (foreach tb (ade_odgettables de)
           (setq i 0)
           (repeat (ade_odrecordqty de tb)
             (if (setq rec (ade_odgetrecord de tb i)) (ade_odaddrecord para tb rec))
             (setq i (1+ i)))))))
)

;;; tira pontos consecutivos repetidos (e o último, se fechada e igual ao 1º)
(defun vp:sem-dup (pts fech / out)
  (foreach p pts
    (if (not (and out (< (vp:d2 p (car out)) *VP-TOL*))) (setq out (cons p out))))
  (setq out (reverse out))
  (if (and fech (> (length out) 2) (< (vp:d2 (car out) (last out)) *VP-TOL*))
    (setq out (reverse (cdr (reverse out)))))
  out
)

;;; vértices: ((ponto bulge) ...) ; vértices de controle de spline ignorados
(defun vp:lw-recs (ed / recs p b)
  (foreach g ed
    (cond ((= 10 (car g)) (if p (setq recs (cons (list p b) recs))) (setq p (cdr g) b 0.0))
          ((= 42 (car g)) (setq b (cdr g)))))
  (if p (setq recs (cons (list p b) recs)))
  (reverse recs)
)

(defun vp:pl-recs (e / v vd recs)
  (setq v (entnext e))
  (while (and v (= "VERTEX" (cdr (assoc 0 (setq vd (entget v))))))
    (if (zerop (logand 16 (cdr (assoc 70 vd))))
      (setq recs (cons (list (cdr (assoc 10 vd)) (cond ((cdr (assoc 42 vd))) (0.0))) recs)))
    (setq v (entnext v)))
  (reverse recs)
)

(defun vp:recs (e) (if (= "LWPOLYLINE" (vp:tipo e)) (vp:lw-recs (entget e)) (vp:pl-recs e)))

;;; arco do bulge b entre p0 e p1 -> (centro raio ang0 theta)
(defun vp:arco (p0 p1 b / c ux uy h cen)
  (setq c   (vp:d2 p0 p1)
        ux  (/ (- (car p1) (car p0)) c)
        uy  (/ (- (cadr p1) (cadr p0)) c)
        h   (/ (* c (- 1.0 (* b b))) (* 4.0 b))
        cen (list (- (/ (+ (car p0) (car p1)) 2.0) (* h uy))
                  (+ (/ (+ (cadr p0) (cadr p1)) 2.0) (* h ux))))
  (list cen (/ (* c (+ 1.0 (* b b))) (* 4.0 (abs b)))
        (atan (- (cadr p0) (cadr cen)) (- (car p0) (car cen))) (* 4.0 (atan b)))
)

;;; pontos 2D da polilinha, arcos como cordas (16 por meia-volta)
(defun vp:pontos (recs fech / prox out geo m k a)
  (setq prox (append (mapcar 'car (cdr recs)) (list (if fech (car (car recs))))))
  (mapcar
    '(lambda (r q)
       (setq out (cons (vp:2d (car r)) out))
       (if (and q (> (abs (cadr r)) 1e-9) (> (vp:d2 (car r) q) 1e-9))
         (progn
           (setq geo (vp:arco (car r) q (cadr r))
                 m   (max 2 (1+ (fix (/ (abs (cadddr geo)) (/ pi 16.0)))))
                 k   1)
           (while (< k m)
             (setq a   (+ (caddr geo) (/ (* (cadddr geo) k) m))
                   out (cons (list (+ (car (car geo)) (* (cadr geo) (cos a)))
                                   (+ (cadr (car geo)) (* (cadr geo) (sin a))))
                             out)
                   k   (1+ k))))))
    recs prox)
  (reverse out)
)

;;; --------------------------------------------------------------------------
;;; Pontas de curvas abertas, agrupadas por proximidade (mesma camada)
;;; registro: (x y CAMADA ename ponta)  ponta 0 = início, 1 = fim
;;; --------------------------------------------------------------------------
(defun vp:pontas (ents / tp out p q)
  (foreach e ents
    (setq tp (vp:tipo e))
    (if (or (member tp '("LINE" "ARC"))
            (and (vp:curva-pl-p e) (not (vp:fechada-p e))))
      (progn
        (setq p (vlax-curve-getStartPoint e) q (vlax-curve-getEndPoint e))
        (if (and p q (or (/= tp "LINE") (> (vp:d2 p q) *VP-TOL*)))
          (setq out (cons (list (car q) (cadr q) (vp:camada-de e) e 1)
                          (cons (list (car p) (cadr p) (vp:camada-de e) e 0) out)))))))
  out
)

;;; -> lista de grupos (cada grupo = lista de registros a <= tolerância)
(defun vp:agrupa (recs / rest a q grp ja res)
  (setq rest (vl-sort recs '(lambda (a b) (< (car a) (car b)))))
  (while rest
    (setq a    (car rest)
          rest (cdr rest)
          ja   (vl-remove-if '(lambda (r) (> (- (car a) (car r)) *VP-TOL*)) ja))
    (if (not (member a ja))
      (progn
        (setq grp (list a) q rest)
        (while (and q (<= (- (car (car q)) (car a)) *VP-TOL*))
          (if (and (= (caddr (car q)) (caddr a))
                   (not (member (car q) ja))
                   (<= (distance (vp:2d a) (vp:2d (car q))) *VP-TOL*))
            (setq grp (cons (car q) grp) ja (cons (car q) ja)))
          (setq q (cdr q)))
        (setq res (cons grp res)))))
  res
)

;;; --------------------------------------------------------------------------
;;; 1. Polilinhas 3D -> 2D
;;; --------------------------------------------------------------------------
(defun vp:passo-3d (ents / out ed fech pts novo)
  (foreach e ents
    (if (and (vp:3d-p e) (vp:editavel e))
      (progn
        (setq ed   (entget e '("*"))
              fech (= 1 (logand 1 (cdr (assoc 70 ed))))
              pts  (vp:sem-dup (mapcar 'car (vp:pl-recs e)) fech))
        (if (and (>= (length pts) 2)
                 (setq novo (vp:mk-lw (vp:props ed) pts (and fech (> (length pts) 2)) 0.0 (assoc -3 ed))))
          (progn (vp:copia-od e novo) (entdel e) (setq n3d (1+ n3d) out (cons novo out)))
          (setq out (cons e out))))
      (setq out (cons e out))))
  (reverse out)
)

;;; --------------------------------------------------------------------------
;;; 2. Linhas -> polilinhas (unindo as conectadas)
;;; --------------------------------------------------------------------------
;;; lig: ((ename . ponta) . (ename2 . ponta2)) para nós com exatamente 2 pontas
;;; de LINE (nenhuma outra curva da camada terminando ali)
(defun vp:ligacoes (ents / lig a b)
  (foreach g (vp:agrupa (vp:pontas ents))
    (if (= 2 (length g))
      (progn
        (setq a (car g) b (cadr g))
        (if (and (not (eq (nth 3 a) (nth 3 b)))
                 (= "LINE" (vp:tipo (nth 3 a))) (= "LINE" (vp:tipo (nth 3 b))))
          (setq lig (cons (cons (cons (nth 3 a) (nth 4 a)) (cons (nth 3 b) (nth 4 b)))
                          (cons (cons (cons (nth 3 b) (nth 4 b)) (cons (nth 3 a) (nth 4 a))) lig)))))))
  lig
)

(defun vp:prox (e ponta) (cdr (assoc (cons e ponta) lig)))

;;; corrente de linhas a partir de e0 -> (fechada? (e . sentido) ...)
;;; sentido 0 = p10 -> p11, 1 = invertida
(defun vp:corrente (e0 / seq sai nx vai fech)
  (setq seq (list (cons e0 0)) sai 1 vai T)
  (ssadd e0 vis)
  ;; para frente, saindo pela ponta 1 de e0
  (while (and vai (setq nx (vp:prox (car (last seq)) sai)))
    (cond ((eq (car nx) e0) (setq fech T vai nil))
          ((ssmemb (car nx) vis) (setq vai nil))
          ((not (vp:editavel (car nx))) (setq vai nil))
          (T (ssadd (car nx) vis)
             (setq seq (append seq (list (cons (car nx) (cdr nx))))
                   sai (- 1 (cdr nx))))))
  ;; para trás, a partir da ponta 0 de e0
  (if (not fech)
    (progn
      (setq sai 0 vai T)
      (while (and vai (setq nx (vp:prox (car (car seq)) sai)))
        (cond ((ssmemb (car nx) vis) (setq vai nil))
              ((not (vp:editavel (car nx))) (setq vai nil))
              (T (ssadd (car nx) vis)
                 (setq seq (cons (cons (car nx) (- 1 (cdr nx))) seq)
                       sai (- 1 (cdr nx))))))))
  (cons fech seq)
)

(defun vp:passo-linhas (ents / lig vis out lin ch fech seq pts ed z novo)
  (setq lin (vl-remove-if-not '(lambda (e) (= "LINE" (vp:tipo e))) ents)
        out (vl-remove-if '(lambda (e) (= "LINE" (vp:tipo e))) ents)
        vis (ssadd))
  (if *VP-JUNTA* (setq lig (vp:ligacoes ents)))
  (foreach e lin
    (if (and (not (ssmemb e vis)) (vp:editavel e))
      (progn
        (setq ch   (vp:corrente e)
              fech (car ch)
              seq  (cdr ch)
              pts  nil)
        (foreach s seq
          (setq ed (entget (car s)))
          (if (= 0 (cdr s))
            (setq pts (cons (cdr (assoc 11 ed)) (if pts pts (list (cdr (assoc 10 ed))))))
            (setq pts (cons (cdr (assoc 10 ed)) (if pts pts (list (cdr (assoc 11 ed))))))))
        (setq pts (vp:sem-dup (reverse pts) fech)
              z   (caddr (car pts)))
        (if (vl-some '(lambda (p) (> (abs (- (caddr p) z)) *VP-TOL*)) pts) (setq z 0.0))
        (setq ed (entget (car (car seq)) '("*")))
        (if (and (>= (length pts) 2)
                 (setq novo (vp:mk-lw (vp:props ed) pts (and fech (> (length pts) 2)) z (assoc -3 ed))))
          (progn
            (vp:copia-od (car (car seq)) novo)
            (foreach s seq (entdel (car s)))
            (setq nlin (+ nlin (length seq)) npl (1+ npl) out (cons novo out)))
          (foreach s seq (setq out (cons (car s) out)))))
      (if (entget e) (if (not (ssmemb e vis)) (setq out (cons e out))))))
  (vp:vivos out)
)

;;; --------------------------------------------------------------------------
;;; 3. Segmentar arcos (SEGMENTARCOS / Simplifica.lsp)
;;; --------------------------------------------------------------------------
(defun vp:carrega-sp (/ arq)
  (if (and (not sp:aplica) (vp:pasta) (setq arq (findfile (strcat (vp:pasta) "\\Simplifica.lsp"))))
    (vl-catch-all-apply 'load (list arq)))
  (and sp:aplica sp:f-segmenta sp:arco-ent)
)

(defun vp:txt-arcos ()
  (cond ((not (vp:carrega-sp)) "Simplifica.lsp não encontrado")
        (*SA-FIXA* (strcat "Medida fixa " (rtos *SA-MEDIDA* 2 2) " m"
                           (if *SA-AVULSOS* ", com arcos/círculos avulsos" "") " (SEGMENTARCOS)"))
        (T (strcat "Flecha máx. " (rtos *SA-FLECHA* 2 3) " m"
                   (if *SA-AVULSOS* ", com arcos/círculos avulsos" "") " (SEGMENTARCOS)")))
)

(defun vp:passo-arcos (ents / out tp r ok)
  (foreach e ents
    (setq tp (vp:tipo e) ok nil)
    (cond
      ((and (or (= tp "LWPOLYLINE")
                (and (vp:pl-p e) (zerop (logand 14 (vp:flags e)))))
            (vl-some '(lambda (r) (> (abs (cadr r)) 1e-12)) (vp:recs e))
            (vp:editavel e))
       (if (setq r (sp:aplica e 'sp:f-segmenta nil))
         (setq narc (+ narc (caddr r)) ok T))
       (setq out (cons (if (and ok (= tp "POLYLINE")) (entlast) e) out)))
      ((and *SA-AVULSOS* (member tp '("ARC" "CIRCLE")) (vp:editavel e))
       (if (sp:arco-ent e (if *SA-FIXA* 'MEDIDA 'FLECHA) (if *SA-FIXA* *SA-MEDIDA* *SA-FLECHA*) nil)
         (setq narc (1+ narc) out (cons (entlast) out))
         (setq out (cons e out))))
      (T (setq out (cons e out)))))
  (vp:vivos (reverse out))
)

;;; --------------------------------------------------------------------------
;;; 4. Fechar talhões
;;; --------------------------------------------------------------------------
;;; LWPOLYLINE: tira o último vértice (grupo 10 e seus 40/41/42/91)
(defun vp:lw-sem-ultimo (ed / n i out pula)
  (setq n (length (vl-remove-if-not '(lambda (g) (= 10 (car g))) ed)) i 0)
  (foreach g ed
    (cond ((= 10 (car g)) (setq i (1+ i) pula (= i n)) (if (not pula) (setq out (cons g out))))
          ((and pula (member (car g) '(40 41 42 91))))
          (T (setq out (cons g out)))))
  (subst (cons 90 (1- n)) (assoc 90 ed) (reverse out))
)

(defun vp:fecha (e tira nv / ed o c k)
  (if (= "LWPOLYLINE" (vp:tipo e))
    (progn
      (setq ed (entget e))
      (if tira (setq ed (vp:lw-sem-ultimo ed)))
      (setq ed (subst (cons 70 (logior 1 (cdr (assoc 70 ed)))) (assoc 70 ed) ed))
      (entmod ed))
    (progn
      (setq o (vlax-ename->vla-object e))
      (if tira
        (vl-catch-all-apply
          '(lambda ()
             (setq c (reverse (vlax-get o 'Coordinates)) k (/ (length c) nv))
             (repeat k (setq c (cdr c)))
             (vlax-put o 'Coordinates (reverse c)))))
      (vla-put-Closed o :vlax-true)))
  (entupd e)
)

(defun vp:passo-fechar (ents / filtro recs p q)
  (setq filtro (strcase *VP-CAMTAL*))
  (foreach e ents
    (if (and (vp:curva-pl-p e) (not (vp:fechada-p e)) (zerop (logand 6 (vp:flags e)))
             (wcmatch (vp:camada-de e) filtro)
             (>= (length (setq recs (vp:recs e))) 3)
             (vp:editavel e))
      (progn
        (setq p (car (car recs)) q (car (last recs)))
        (if (<= (vp:d2 p q) *VP-TOL*)
          (vp:fecha e (> (length recs) 3) (length recs))
          (progn
            (vp:fecha e nil (length recs))
            (vp:marca 3 (list (/ (+ (car p) (car q)) 2.0) (/ (+ (cadr p) (cadr q)) 2.0)))
            (setq nlongo (1+ nlongo))))
        (setq nfec (1+ nfec)))))
  ents
)

;;; --------------------------------------------------------------------------
;;; 5. Auto-cruzamentos
;;; --------------------------------------------------------------------------
;;; interseção dos segmentos ab e cd (inclui toque e sobreposição) -> ponto/nil
(defun vp:cruza (a b c d / rx ry sx sy qx qy den la ls tt u e1 e2 t0 t1 lo hi)
  (setq rx (- (car b) (car a)) ry (- (cadr b) (cadr a))
        sx (- (car d) (car c)) sy (- (cadr d) (cadr c))
        qx (- (car c) (car a)) qy (- (cadr c) (cadr a))
        den (- (* rx sy) (* ry sx))
        la (sqrt (+ (* rx rx) (* ry ry)))
        ls (sqrt (+ (* sx sx) (* sy sy))))
  (cond
    ((or (< la 1e-12) (< ls 1e-12)) nil)
    ((> (abs den) (* 1e-9 la ls))
     (setq tt (/ (- (* qx sy) (* qy sx)) den)
           u  (/ (- (* qx ry) (* qy rx)) den)
           e1 (/ *VP-TOL* la)
           e2 (/ *VP-TOL* ls))
     (if (and (>= tt (- e1)) (<= tt (+ 1.0 e1)) (>= u (- e2)) (<= u (+ 1.0 e2)))
       (list (+ (car a) (* tt rx)) (+ (cadr a) (* tt ry)))))
    ;; paralelos: só interessa se colineares e sobrepostos
    ((< (/ (abs (- (* qx ry) (* qy rx))) la) *VP-TOL*)
     (setq t0 (/ (+ (* qx rx) (* qy ry)) (* la la))
           t1 (/ (+ (* (- (car d) (car a)) rx) (* (- (cadr d) (cadr a)) ry)) (* la la))
           lo (max 0.0 (min t0 t1))
           hi (min 1.0 (max t0 t1)))
     (if (>= (* (- hi lo) la) (- *VP-TOL*))
       (list (+ (car a) (* (/ (+ lo hi) 2.0) rx)) (+ (cadr a) (* (/ (+ lo hi) 2.0) ry)))))
  )
)

;;; espinho: c volta sobre o segmento ab (ângulo de ~180 graus em b)
(defun vp:espinho (a b c / ux uy l vx vy)
  (setq ux (- (car b) (car a)) uy (- (cadr b) (cadr a)) l (sqrt (+ (* ux ux) (* uy uy)))
        vx (- (car c) (car b)) vy (- (cadr c) (cadr b)))
  (and (> l 1e-12)
       (< (+ (* ux vx) (* uy vy)) 0.0)
       (< (/ (abs (- (* ux vy) (* uy vx))) l) *VP-TOL*))
)

;;; pontos onde a polilinha (pts 2D) cruza/toca a si mesma
(defun vp:autocruz (pts fech / n segs i a b ativos achou add)
  (defun add (p)
    (if (not (vl-some '(lambda (q) (< (distance p q) (max (* 10.0 *VP-TOL*) 0.01))) achou))
      (setq achou (cons p achou))))
  (setq i 0)
  (while (cdr pts)
    (setq a (car pts) b (cadr pts) pts (cdr pts))
    (setq segs (cons (list (min (car a) (car b)) (max (car a) (car b))
                           (min (cadr a) (cadr b)) (max (cadr a) (cadr b)) i a b)
                     segs)
          i    (1+ i)))
  (if (and fech (> i 1))
    (setq b    (nth 5 (last segs))           ; início da polilinha
          a    (nth 6 (car segs))            ; última ponta
          segs (cons (list (min (car a) (car b)) (max (car a) (car b))
                           (min (cadr a) (cadr b)) (max (cadr a) (cadr b)) i a b)
                     segs)
          i    (1+ i)))
  (setq n i)
  (foreach s (vl-sort segs '(lambda (x y) (< (car x) (car y))))
    (setq ativos (vl-remove-if '(lambda (o) (< (cadr o) (- (car s) *VP-TOL*))) ativos))
    (foreach o ativos
      (if (and (<= (caddr o) (+ (cadddr s) *VP-TOL*)) (>= (cadddr o) (- (caddr s) *VP-TOL*)))
        (cond
          ;; o antes de s (vizinhos)
          ((or (= (nth 4 s) (1+ (nth 4 o))) (and fech (= (nth 4 o) (1- n)) (= (nth 4 s) 0)))
           (if (vp:espinho (nth 5 o) (nth 6 o) (nth 6 s)) (add (nth 6 o))))
          ;; s antes de o (vizinhos)
          ((or (= (nth 4 o) (1+ (nth 4 s))) (and fech (= (nth 4 s) (1- n)) (= (nth 4 o) 0)))
           (if (vp:espinho (nth 5 s) (nth 6 s) (nth 6 o)) (add (nth 6 s))))
          ((setq a (vp:cruza (nth 5 o) (nth 6 o) (nth 5 s) (nth 6 s))) (add a)))))
    (setq ativos (cons s ativos)))
  achou
)

(defun vp:passo-cruz (ents / fech pts)
  (foreach e ents
    (if (and (vp:curva-pl-p e) (zerop (logand 6 (vp:flags e))))
      (progn
        (setq fech (vp:fechada-p e)
              pts  (vp:sem-dup (vp:pontos (vp:recs e) fech) fech))
        ;; aberta com as pontas juntas: tratada como anel (o pseudo-nó acusa)
        (if (and (not fech) (> (length pts) 3) (< (vp:d2 (car pts) (last pts)) *VP-TOL*))
          (setq fech T pts (reverse (cdr (reverse pts)))))
        (if (>= (length pts) 3)
          (foreach p (vp:autocruz pts fech)
            (vp:marca 0 p)
            (setq ncruz (1+ ncruz)))))))
  ents
)

;;; --------------------------------------------------------------------------
;;; Remover nós (equivalente ao RNOS do AgroCAD)
;;; Cada auto-cruzamento entre os segmentos i < j vira um vértice no ponto de
;;; cruzamento e o laço entre eles sai. Aberta: sai o trecho i+1..j. Fechada:
;;; fica a parte de maior área (o laço/nó é a parte menor). Espinho (volta
;;; sobre o próprio traço): sai o vértice da ponta. Repete até não haver nós.
;;; Polilinhas com arcos são puladas (use SEGMENTARCOS antes).
;;; --------------------------------------------------------------------------
;;; elementos i..j (inclusive) da lista
(defun vp:fatia (l i j / out)
  (repeat i (setq l (cdr l)))
  (repeat (max 0 (1+ (- j i))) (setq out (cons (car l) out) l (cdr l)))
  (reverse out)
)

(defun vp:area (pts / a)
  (setq a 0.0)
  (mapcar '(lambda (p q) (setq a (+ a (- (* (car p) (cadr q)) (* (car q) (cadr p))))))
          pts (append (cdr pts) (list (car pts))))
  (abs (/ a 2.0))
)

;;; ponto p com o z de ref (se ref tiver z)
(defun vp:com-z (p ref) (if (caddr ref) (list (car p) (cadr p) (caddr ref)) (vp:2d p)))

;;; primeiro nó -> ('CRUZ i j p) com i < j, ('ESPINHO k) vértice k, ou nil
(defun vp:primeiro-no (pts fech / i a b segs n srt s ativos lst o p res)
  (setq i 0)
  (while (cdr pts)
    (setq a (car pts) b (cadr pts) pts (cdr pts))
    (setq segs (cons (list (min (car a) (car b)) (max (car a) (car b))
                           (min (cadr a) (cadr b)) (max (cadr a) (cadr b)) i a b)
                     segs)
          i    (1+ i)))
  (if (and fech (> i 1))
    (setq b    (nth 5 (last segs))
          a    (nth 6 (car segs))
          segs (cons (list (min (car a) (car b)) (max (car a) (car b))
                           (min (cadr a) (cadr b)) (max (cadr a) (cadr b)) i a b)
                     segs)
          i    (1+ i)))
  (setq n i srt (vl-sort segs '(lambda (x y) (< (car x) (car y)))))
  (while (and srt (not res))
    (setq s      (car srt)
          srt    (cdr srt)
          ativos (vl-remove-if '(lambda (o) (< (cadr o) (- (car s) *VP-TOL*))) ativos)
          lst    ativos)
    (while (and lst (not res))
      (setq o (car lst) lst (cdr lst))
      (if (and (<= (caddr o) (+ (cadddr s) *VP-TOL*)) (>= (cadddr o) (- (caddr s) *VP-TOL*)))
        (cond
          ((or (= (nth 4 s) (1+ (nth 4 o))) (and fech (= (nth 4 o) (1- n)) (= (nth 4 s) 0)))
           (if (vp:espinho (nth 5 o) (nth 6 o) (nth 6 s)) (setq res (list 'ESPINHO (nth 4 s)))))
          ((or (= (nth 4 o) (1+ (nth 4 s))) (and fech (= (nth 4 s) (1- n)) (= (nth 4 o) 0)))
           (if (vp:espinho (nth 5 s) (nth 6 s) (nth 6 o)) (setq res (list 'ESPINHO (nth 4 o)))))
          ((setq p (vp:cruza (nth 5 o) (nth 6 o) (nth 5 s) (nth 6 s)))
           (setq res (list 'CRUZ (min (nth 4 o) (nth 4 s)) (max (nth 4 o) (nth 4 s)) p))))))
    (setq ativos (cons s ativos)))
  res
)

;;; -> (pontos . nós-removidos)
(defun vp:tira-nos (pts fech / no n k a b cont lim)
  (setq cont 0 lim (length pts))
  (while (and (> lim 0) (>= (length pts) (if fech 4 3)) (setq no (vp:primeiro-no pts fech)))
    (setq n (length pts) lim (1- lim))
    (if (eq (car no) 'ESPINHO)
      (setq k   (cadr no)
            pts (append (vp:fatia pts 0 (1- k)) (vp:fatia pts (1+ k) (1- n))))
      (progn
        (setq a (append (vp:fatia pts 0 (cadr no))
                        (list (vp:com-z (cadddr no) (nth (cadr no) pts)))
                        (vp:fatia pts (1+ (caddr no)) (1- n))))
        (if fech
          (progn
            (setq b (cons (vp:com-z (cadddr no) (nth (cadr no) pts))
                          (vp:fatia pts (1+ (cadr no)) (caddr no))))
            (if (> (vp:area b) (vp:area a)) (setq a b))))
        (setq pts a)))
    (setq pts (vp:sem-dup pts fech) cont (1+ cont)))
  (cons pts cont)
)

;;; regrava os vértices (polilinha sem arcos); nv = nº de vértices original
(defun vp:grava-pts (e pts nv / ed cab cau est o c k z)
  (if (= "LWPOLYLINE" (vp:tipo e))
    (progn
      (setq ed (entget e))
      (foreach g ed
        (cond ((= 10 (car g)) (setq est T))
              ((member (car g) '(40 41 42 91)) (if (not est) (setq cab (cons g cab))))
              (est (setq cau (cons g cau)))
              (T (setq cab (cons g cab)))))
      (setq cab (reverse cab))
      (if (entmod (append (subst (cons 90 (length pts)) (assoc 90 cab) cab)
                          (mapcar '(lambda (p) (cons 10 (vp:2d p))) pts)
                          (reverse cau)))
        (progn (entupd e) T)))
    (not (vl-catch-all-error-p
           (vl-catch-all-apply
             '(lambda ()
                (setq o (vlax-ename->vla-object e)
                      c (vlax-get o 'Coordinates)
                      k (/ (length c) nv)
                      z (if (> k 2) (caddr c) 0.0))
                (vlax-put o 'Coordinates
                          (apply 'append
                                 (mapcar '(lambda (p)
                                            (cond ((< k 3) (vp:2d p))
                                                  ((vp:3d-p e) (list (car p) (cadr p) (if (caddr p) (caddr p) 0.0)))
                                                  (T (list (car p) (cadr p) z))))
                                         pts)))
                (entupd e))))))
)

;;; -> nº de nós removidos, 'ARCO (tem nós mas tem arcos) ou nil
(defun vp:remove-nos-ent (e / recs fech anel pts r)
  (if (and (vp:curva-pl-p e) (zerop (logand 6 (vp:flags e))))
    (progn
      (setq recs (vp:recs e) fech (vp:fechada-p e))
      (if (vl-some '(lambda (x) (> (abs (cadr x)) 1e-12)) recs)
        (progn
          (setq pts (vp:sem-dup (vp:pontos recs fech) fech))
          (if (and (>= (length pts) 3) (vp:autocruz pts fech)) 'ARCO))
        (progn
          (setq pts (vp:sem-dup (mapcar 'car recs) fech))
          ;; aberta com as pontas juntas: trata como anel e devolve aberta
          (if (and (not fech) (> (length pts) 3) (< (vp:d2 (car pts) (last pts)) *VP-TOL*))
            (setq anel T fech T pts (reverse (cdr (reverse pts)))))
          (setq r (vp:tira-nos pts fech))
          (if (and (> (cdr r) 0) (>= (length (car r)) (if fech 3 2)))
            (progn
              (setq pts (car r))
              (if anel (setq pts (append pts (list (car pts)))))
              (if (vp:grava-pts e pts (length recs)) (cdr r))))))))
)

(defun vp:passo-nos (ents / r)
  (foreach e ents
    (if (and (vp:curva-pl-p e) (vp:editavel e))
      (cond ((eq (setq r (vp:remove-nos-ent e)) 'ARCO) (setq nnarco (1+ nnarco)))
            (r (setq nnos (+ nnos r) nnpl (1+ nnpl))))))
  ents
)

(defun c:REMOVENOS (/ *error* doc l r t0 nnos nnpl nnarco)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ))
  (vp:le-cfg)
  (princ "\nSelecione as polilinhas para remover os nós (auto-cruzamentos): ")
  (if (setq l (vp:lista (ssget "_:L" '((0 . "LWPOLYLINE,POLYLINE")))))
    (progn
      (vla-StartUndoMark doc)
      (setq t0 (getvar "MILLISECS") nnos 0 nnpl 0 nnarco 0)
      (foreach e l
        (cond ((eq (setq r (vp:remove-nos-ent e)) 'ARCO) (setq nnarco (1+ nnarco)))
              (r (setq nnos (+ nnos r) nnpl (1+ nnpl)))))
      (vla-EndUndoMark doc)
      (princ (strcat "\n" (itoa nnos) " nó(s) removido(s) em " (itoa nnpl) " de " (itoa (length l))
                     " polilinha(s) [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))
      (if (> nnarco 0)
        (princ (strcat "\n" (itoa nnarco) " polilinha(s) com arcos e nós não alterada(s): use SEGMENTARCOS antes.")))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; 6. Pseudo-nós   7. Splines
;;; --------------------------------------------------------------------------
(defun vp:passo-pseudo (ents)
  (foreach g (vp:agrupa (vp:pontas ents))
    (if (= 2 (length g))
      (progn (vp:marca 1 (car g)) (setq npseudo (1+ npseudo)))))
  ents
)

(defun vp:passo-splines (ents / meio)
  (foreach e ents
    (if (= "SPLINE" (vp:tipo e))
      (progn
        (setq meio (vl-catch-all-apply
                     '(lambda ()
                        (vlax-curve-getPointAtDist
                          e (/ (vlax-curve-getDistAtParam e (vlax-curve-getEndParam e)) 2.0)))))
        (if (or (null meio) (vl-catch-all-error-p meio)) (setq meio (vlax-curve-getStartPoint e)))
        (vp:marca 2 meio)
        (ssadd e splss)
        (setq nspl (1+ nspl)))))
  ents
)

;;; --------------------------------------------------------------------------
;;; Execução
;;; --------------------------------------------------------------------------
(defun vp:executa (/ *error* doc t0 ents trav travss splss n3d nlin npl narc nfec nlongo
                     ncruz npseudo nspl nlimpas nnos nnpl nnarco linha)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ))
  (setq ents (vp:lista (if *VP-SEL*
                         (progn (princ "\nSelecione os objetos a verificar: ") (ssget '((410 . "Model"))))
                         (ssget "_X" '((410 . "Model"))))))
  (if (null ents)
    (princ "\nNenhum objeto para verificar.")
    (progn
      (vla-StartUndoMark doc)
      (setq t0 (getvar "MILLISECS")
            trav (vp:travadas) travss (ssadd) splss (ssadd)
            n3d 0 nlin 0 npl 0 narc 0 nfec 0 nlongo 0 ncruz 0 npseudo 0 nspl 0 nlimpas 0 nnos 0 nnpl 0 nnarco 0)
      (if *VP-LIMPA* (setq nlimpas (vp:limpa-marcas)))
      (setq ents (vl-remove-if 'vp:marca-p (vp:vivos ents)))
      (princ "\nVerificando o projeto...")
      (if *VP-3D*    (setq ents (vp:passo-3d ents)))
      (if *VP-LIN*   (setq ents (vp:passo-linhas ents)))
      (if *VP-ARC*
        (if (vp:carrega-sp)
          (setq ents (vp:passo-arcos ents))
          (princ "\nSegmentar arcos ignorado: Simplifica.lsp (SEGMENTARCOS) não encontrado.")))
      (if *VP-FECHA* (setq ents (vp:passo-fechar ents)))
      (if *VP-NOS*   (setq ents (vp:passo-nos ents)))
      (if *VP-CRUZ*   (vp:passo-cruz ents))
      (if *VP-PSEUDO* (vp:passo-pseudo ents))
      (if *VP-SPL*    (vp:passo-splines ents))
      (vla-EndUndoMark doc)
      ;; relatório
      (defun linha (ok txt) (if ok (princ (strcat "\n  " txt))))
      (princ (strcat "\nVerificação do projeto concluída: " (itoa (length ents)) " objeto(s) ["
                     (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))
      (linha (> nlimpas 0) (strcat (itoa nlimpas) " marca(s) da verificação anterior apagada(s)"))
      (linha *VP-3D*  (strcat "Polilinhas 3D -> 2D: " (itoa n3d)))
      (linha *VP-LIN* (strcat "Linhas -> polilinhas: " (itoa nlin) " linha(s) em " (itoa npl) " polilinha(s)"))
      (linha *VP-ARC* (strcat "Arcos segmentados: " (itoa narc)))
      (linha *VP-FECHA* (strcat "Talhões fechados: " (itoa nfec)
                                (if (> nlongo 0)
                                  (strcat " (" (itoa nlongo) " com pontas afastadas, marcados em VERIFICA_FECHAMENTO)")
                                  "")))
      (linha *VP-NOS* (strcat "Nós removidos: " (itoa nnos) " em " (itoa nnpl) " polilinha(s)"
                              (if (> nnarco 0) (strcat "; " (itoa nnarco) " com arcos não alterada(s)") "")))
      (linha *VP-CRUZ*   (strcat "Auto-cruzamentos: " (itoa ncruz) (if (> ncruz 0) " (VERIFICA_AUTOCRUZAMENTO)" "")))
      (linha *VP-PSEUDO* (strcat "Pseudo-nós: " (itoa npseudo) (if (> npseudo 0) " (VERIFICA_PSEUDONO)" "")))
      (linha *VP-SPL*    (strcat "Splines: " (itoa nspl)
                                 (if (> nspl 0) " (VERIFICA_SPLINE; ficaram selecionadas - converta com SPLINEDIT > Converter em polilinha)" "")))
      (linha (> (sslength travss) 0)
             (strcat (itoa (sslength travss)) " objeto(s) em camadas travadas não foram alterados"))
      (if (> nspl 0) (sssetfirst nil splss))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(setq *VP-TILES* '(("c3d" . *VP-3D*) ("clin" . *VP-LIN*) ("cjun" . *VP-JUNTA*) ("carc" . *VP-ARC*)
                   ("cfec" . *VP-FECHA*) ("ccruz" . *VP-CRUZ*) ("cpseudo" . *VP-PSEUDO*)
                   ("cspl" . *VP-SPL*) ("limpa" . *VP-LIMPA*) ("cnos" . *VP-NOS*)))
(setq *VP-OPCOES* '("c3d" "clin" "carc" "cfec" "cnos" "ccruz" "cpseudo" "cspl"))

(defun vp:hab ()
  (mode_tile "cjun"   (if (= "1" (get_tile "clin")) 0 1))
  (mode_tile "camtal" (if (= "1" (get_tile "cfec")) 0 1))
)

(defun vp:preenche ()
  (foreach p *VP-TILES* (set_tile (car p) (if (eval (cdr p)) "1" "0")))
  (set_tile (if *VP-SEL* "sel" "tudo") "1")
  (set_tile "tol"    (rtos *VP-TOL* 2 4))
  (set_tile "raio"   (rtos *VP-RAIO* 2 2))
  (set_tile "camtal" *VP-CAMTAL*)
  (set_tile "txtarc" (vp:txt-arcos))
  (set_tile "error"  "")
  (vp:hab)
)

(defun vp:num (s / v)
  (if s (setq v (distof (vl-string-translate "," "." (vl-string-trim " " s)) 2)))
  v
)

(defun vp:le-tiles (/ tol raio cam)
  (setq tol  (vp:num (get_tile "tol"))
        raio (vp:num (get_tile "raio"))
        cam  (vl-string-trim " " (get_tile "camtal")))
  (cond
    ((not (vl-some '(lambda (k) (= "1" (get_tile k))) *VP-OPCOES*))
     (set_tile "error" "Escolha pelo menos uma operação.") nil)
    ((not (and tol (> tol 0) (< tol 1)))  (set_tile "error" "Tolerância inválida (entre 0 e 1 m).") nil)
    ((not (and raio (> raio 0)))          (set_tile "error" "Raio das marcas inválido.") nil)
    ((and (= "1" (get_tile "cfec")) (= cam ""))
     (set_tile "error" "Informe as camadas dos talhões.") nil)
    (T
     (foreach p *VP-TILES* (set (cdr p) (= "1" (get_tile (car p)))))
     (setq *VP-SEL* (= "1" (get_tile "sel")) *VP-TOL* tol *VP-RAIO* raio)
     (if (/= cam "") (setq *VP-CAMTAL* cam))
     T))
)

;;; -> 1 = verificar, 0 = cancelado
(defun vp:dialogo (/ arq dcl r loop n)
  (setq arq (if (vp:pasta) (findfile (strcat (vp:pasta) "\\VerificaProjeto.dcl"))) loop T r 0)
  (if (not arq) (progn (alert "Arquivo VerificaProjeto.dcl não encontrado.") (setq loop nil)))
  (while loop
    (setq dcl (load_dialog arq))
    (if (not (new_dialog "verificaproj" dcl))
      (progn (unload_dialog dcl) (alert "Erro ao abrir o diálogo.") (setq loop nil r 0))
      (progn
        (vp:preenche)
        (action_tile "clin"    "(vp:hab)")
        (action_tile "cfec"    "(vp:hab)")
        (action_tile "todas"   "(foreach k *VP-OPCOES* (set_tile k \"1\")) (vp:hab)")
        (action_tile "nenhuma" "(foreach k *VP-OPCOES* (set_tile k \"0\")) (vp:hab)")
        (action_tile "padrao"  "(vp:padroes) (vp:preenche)")
        (action_tile "apagar"  "(done_dialog 2)")
        (action_tile "accept"  "(if (vp:le-tiles) (done_dialog 1))")
        (action_tile "cancel"  "(done_dialog 0)")
        (setq r (start_dialog))
        (unload_dialog dcl)
        (cond
          ((= r 2)
           (setq n (vp:limpa-marcas))
           (princ (strcat "\n" (itoa n) " marca(s) apagada(s).")))
          (T (setq loop nil))))))
  (if (= r 1) (vp:grava-cfg))
  r
)

;;; --------------------------------------------------------------------------
;;; Comandos
;;; --------------------------------------------------------------------------
(defun c:VERIFICAPROJ ()
  (vp:le-cfg)
  (if (= 1 (vp:dialogo)) (vp:executa))
  (princ)
)

(defun c:VERIFICAPROJ_LIMPA ()
  (princ (strcat "\n" (itoa (vp:limpa-marcas)) " marca(s) da verificação apagada(s)."))
  (princ)
)

(vp:le-cfg)
(princ)
