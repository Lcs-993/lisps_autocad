;;; ==========================================================================
;;; CriaLinhas.lsp (v2) - Linhas de Sulcação, Plantio e Colheita
;;; --------------------------------------------------------------------------
;;; Ferramenta unificada que junta o CRIALINHAS v1 (GOFUR do AgroCAD) e o
;;; VARSULC (OFVA / CPV do AgroCAD):
;;;
;;;   Linhas a serem criadas : Somente Guias / Guias + Plantio / Somente Plantio
;;;   Linhas Guias           : SEQUÊNCIA de espaçamentos (Quantidade x
;;;                            Distância), cada linha 1x ou (R)epetir, com
;;;                            layer/cor próprios (vazio = layer das guias)
;;;   Linhas de Plantio      : quantidade e espaçamento em torno de cada guia
;;;   Cabeceira              : N passadas Para Dentro / Para Fora do talhão,
;;;                            seguindo a mesma sequência de espaçamentos
;;;   Linhas Internas        : Criar (talhões) / Sem Talhão / Selecionar guias
;;;   Predefinições          : .ofv (lê também .OFV do AgroCAD, .lin do v1 e
;;;                            arquivos do VARSULC)
;;;
;;; Otimizações:
;;;   - toda linha é UM offset da referência (ou do contorno) na distância
;;;     final - guias e plantio -, nunca offset de offset nem offset de
;;;     trecho já recortado: as pontas chegam exatas no limite do talhão;
;;;   - distâncias coincidentes são eliminadas antes de gerar (plantio sobre
;;;     guia, plantio de guias vizinhas): sem linhas duplicadas;
;;;   - para sozinho quando o talhão está coberto;
;;;   - linhas novas ficam com cor/tipo de linha ByLayer.
;;;
;;; Desempenho (v2.1, metodologia "analysis optimization" do REA: oráculo de
;;; correção fixo -> achar o trabalho desnecessário mais cedo -> menor
;;; correção estrutural -> medir):
;;;   - referência RETA (caso típico do GOFUR): varredura analítica em LISP
;;;     puro - nenhuma chamada COM por linha (era Offset + IntersectWith +
;;;     Delete + recorte para cada linha);
;;;   - referência curva: só gera offsets até a extensão real do talhão em
;;;     CADA lado (antes: a maior distância nos dois lados) e recorta por
;;;     paridade, sem teste ponto-no-polígono por trecho;
;;;   - offsets tirados de uma cópia-base já no layer/ByLayer: sem 3 puts COM
;;;     por linha; layers garantidos uma vez por comando;
;;;   - laços O(n²) com nth trocados por percurso de lista O(n);
;;;   - tempo de processamento mostrado ao final de cada ação.
;;;
;;; Comandos: CRIALINHAS (e VARSULC, atalho para o mesmo diálogo)
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Parâmetros
;;; --------------------------------------------------------------------------
(setq *LN-OPC* '(*LN-MODO* *LN-REP* *LN-LAYG* *LN-CORG* *LN-PQTD* *LN-PESP*
                 *LN-LAYP* *LN-CORP* *LN-PASS* *LN-RECUAR* *LN-LADO*
                 *LN-MANUAL* *LN-INCREF*))

(defun ln:defaults ()
  (setq *LN-MODO*   "GC"                 ; "G" guias, "GC" guias+plantio, "C" plantio
        *LN-SEQ*    '((1 3.0 T nil nil)) ; ((qtd dist repetir? layer cor) ...)
        *LN-REP*    T                    ; estado da caixa Repetir
        *LN-LAYG*   "GUIDELINES"         ; layer padrão das guias
        *LN-CORG*   2
        *LN-PQTD*   2                    ; linhas de plantio por guia
        *LN-PESP*   1.5                  ; espaçamento do plantio (m)
        *LN-LAYP*   "CROPLINES"
        *LN-CORP*   3
        *LN-PASS*   4                    ; passadas de cabeceira
        *LN-RECUAR* T                    ; 1a passada a meio espaçamento
        *LN-LADO*   "A"                  ; "A" ambos os lados / "U" um lado
        *LN-MANUAL* nil                  ; clicar a posição final
        *LN-INCREF* T)                   ; a própria referência é uma guia
)
(if (not *LN-SEQ*) (ln:defaults))

;;; --------------------------------------------------------------------------
;;; Utilitários / geometria
;;; --------------------------------------------------------------------------
(defun ln:2d (p) (list (car p) (cadr p)))
(defun ln:tan (x) (/ (sin x) (cos x)))
(defun ln:bpar (b frac) (ln:tan (* (atan b) frac)))   ; bulge de arco parcial

(defun ln:num (s / v)
  (if s (setq v (distof (vl-string-translate "," "." s) 2)))
  v
)

(defun ln:layer (nome cor / lay)
  (if (not (tblsearch "LAYER" nome))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 nome) '(70 . 0)
                   (cons 62 cor) '(6 . "Continuous"))))
  (setq lay (vla-item (vla-get-Layers (vla-get-ActiveDocument (vlax-get-acad-object))) nome))
  (vla-put-LayerOn lay :vlax-true)
  (vl-catch-all-apply 'vla-put-Freeze (list lay :vlax-false))
  (vla-put-Lock lay :vlax-false)
)

;;; põe no layer e deixa cor / tipo de linha ByLayer
(defun ln:poe (o lay)
  (vla-put-Layer o lay)
  (vl-catch-all-apply 'vla-put-Color (list o acByLayer))
  (vl-catch-all-apply 'vla-put-Linetype (list o "ByLayer"))
  o
)

(defun ln:lw-data (e / ed v b)
  (setq ed (entget e))
  (foreach g ed
    (cond ((= (car g) 10) (setq v (cons (ln:2d (cdr g)) v)))
          ((= (car g) 42) (setq b (cons (cdr g) b)))))
  (list (reverse v) (reverse b) (= 1 (logand 1 (cdr (assoc 70 ed)))))
)

(defun ln:mk-lw (pts buls fechada lay)
  (entmake
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
            '(100 . "AcDbPolyline") (cons 90 (length pts))
            (cons 70 (if fechada 1 0)) '(38 . 0.0))
      (apply 'append (mapcar '(lambda (p b) (list (cons 10 p) (cons 42 b))) pts buls))))
  (vlax-ename->vla-object (entlast))
)

;;; offset (distância 0 = cópia); devolve lista de objetos
(defun ln:offset (o d / r)
  (if (equal d 0.0 1e-9)
    (list (vla-Copy o))
    (progn
      (setq r (vl-catch-all-apply 'vlax-invoke (list o 'Offset d)))
      (if (vl-catch-all-error-p r) nil r)))
)

;;; pontos do contorno (arcos discretizados) para "ponto dentro"
;;; (percorre a lista uma vez: nada de nth dentro do laço -> O(n), não O(n²))
(defun ln:amostra (o / d v b n i j res)
  (setq d (ln:lw-data (vlax-vla-object->ename o))
        v (car d) b (cadr d) n (length v) i 0)
  (foreach p v
    (setq res (cons p res))
    (if (and (/= 0.0 (car b)) (or (caddr d) (< i (1- n))))
      (progn
        (setq j 1)
        (repeat 7
          (setq res (cons (ln:2d (vlax-curve-getPointAtParam o (+ i (/ j 8.0)))) res)
                j   (1+ j)))))
    (setq b (cdr b) i (1+ i))
  )
  (reverse res)
)

;;; flecha máxima entre o arco real e a amostra (8 subdivisões por arco):
;;; folga para a extensão do talhão medida pela amostra
(defun ln:folga-arcos (o / d f th v)
  (setq d (ln:lw-data (vlax-vla-object->ename o)) f 0.0 v (car d))
  (mapcar '(lambda (p q b)
             (if (not (equal b 0.0 1e-9))
               (setq th (* 4.0 (atan (abs b)))
                     f  (max f (* (/ (* (distance p q) (1+ (* b b))) (* 4.0 (abs b)))
                                  (- 1.0 (cos (/ th 16.0))))))))
          v (append (cdr v) (list (car v))) (cadr d))
  (+ f 1e-6)
)

(defun ln:dentro-bb (p poly bb)
  (and (<= (car (car bb)) (car p) (car (cadr bb)))
       (<= (cadr (car bb)) (cadr p) (cadr (cadr bb)))
       (ln:dentro p poly))
)

(defun ln:cauda (l k) (repeat k (setq l (cdr l))) l)

(defun ln:tempo (t0) (strcat " [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))

(defun ln:dentro (p poly / x y in pb)
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

;;; trecho [a,b] de uma LWPOLYLINE, preservando arcos
;;; d = (ln:lw-data o), lido uma vez por curva (e não uma vez por trecho)
(defun ln:sub-lw (o d a b lay / v bl n ia fa ib fb pts buls k vv bb)
  (setq v  (car d) bl (cadr d) n (length v)
        ia (fix a) fa (- a ia) ib (fix b) fb (- b ib))
  (if (> fa (- 1.0 1e-9)) (setq ia (1+ ia) fa 0.0))
  (if (and (< fb 1e-9) (> ib ia)) (setq ib (1- ib) fb 1.0))
  (setq pts (list (ln:2d (vlax-curve-getPointAtParam o a))))
  (if (= ia ib)
    (setq buls (list (ln:bpar (nth (rem ia n) bl) (- fb fa))))
    (progn
      (setq buls (list (ln:bpar (nth (rem ia n) bl) (- 1.0 fa)))
            k    (1+ ia)
            vv   (ln:cauda v k)
            bb   (ln:cauda bl k))
      (while (< k ib)
        (setq pts  (cons (car vv) pts)
              buls (cons (car bb) buls)
              vv   (cdr vv)
              bb   (cdr bb)
              k    (1+ k)))
      (setq pts  (cons (nth (rem ib n) v) pts)
            buls (cons (ln:bpar (nth (rem ib n) bl) fb) buls))))
  (setq pts  (cons (ln:2d (vlax-curve-getPointAtParam o b)) pts)
        buls (cons 0.0 buls))
  (ln:mk-lw (reverse pts) (reverse buls) nil lay)
)

;;; recorta a curva o pelo talhão; apaga o e devolve os pedaços internos
;;; Curva aberta com as duas pontas fora e número de cruzamentos par: os
;;; trechos alternam fora/dentro (paridade) e o teste "ponto dentro"
;;; (O(contorno) por trecho) é dispensado. Tangência (número ímpar) ou curva
;;; fechada: volta ao teste do ponto médio de cada trecho.
(defun ln:clip (o bnd poly bb lay / ints pt pr prms a b res d fech par st)
  (setq ints (vl-catch-all-apply 'vlax-invoke (list o 'IntersectWith bnd acExtendNone)))
  (if (vl-catch-all-error-p ints) (setq ints nil))
  (while ints
    (setq pt   (list (car ints) (cadr ints) (caddr ints)) ints (cdddr ints)
          pr   (vlax-curve-getParamAtPoint o (vlax-curve-getClosestPointTo o pt)))
    (if pr (setq prms (cons pr prms))))
  (setq fech (vlax-curve-isClosed o))
  (cond
    ((and (null prms) fech)
     (if (ln:dentro-bb (ln:2d (vlax-curve-getStartPoint o)) poly bb)
       (list (ln:poe o lay))
       (progn (vla-delete o) nil)))
    ((null prms) (vla-delete o) nil)             ; aberta sem cruzar: fora
    (T
     (setq prms (vl-sort prms '<)
           par  (and (not fech)
                     (= 0 (rem (length prms) 2))
                     (not (ln:dentro-bb (ln:2d (vlax-curve-getStartPoint o)) poly bb))
                     (not (ln:dentro-bb (ln:2d (vlax-curve-getEndPoint o)) poly bb)))
           prms (append (list (vlax-curve-getStartParam o)) prms
                        (list (vlax-curve-getEndParam o)))
           d    (ln:lw-data (vlax-vla-object->ename o))
           st   nil)                             ; 1o trecho: fora
     (while (cdr prms)
       (setq a (car prms) b (cadr prms) prms (cdr prms))
       (if (and (> (- b a) 1e-6)
                (if par
                  st
                  (ln:dentro (ln:2d (vlax-curve-getPointAtParam o (/ (+ a b) 2.0))) poly)))
         (setq res (cons (ln:sub-lw o d a b lay) res)))
       (setq st (not st)))
     (vla-delete o)
     res)
  )
)

;;; referência convertida em LWPOLYLINE e prolongada pelas tangentes
(defun ln:ref-ext (e ext / o typ d pts buls t0 tn)
  (setq o (vlax-ename->vla-object e) typ (cdr (assoc 0 (entget e))))
  (cond
    ((= typ "LWPOLYLINE")
     (setq d (ln:lw-data e) pts (car d) buls (cadr d))
     (if (caddr d) (setq ext nil)))
    ((= typ "LINE")
     (setq pts  (list (ln:2d (vlax-curve-getStartPoint o)) (ln:2d (vlax-curve-getEndPoint o)))
           buls (list 0.0 0.0)))
    ((= typ "ARC")
     (setq pts  (list (ln:2d (vlax-curve-getStartPoint o)) (ln:2d (vlax-curve-getEndPoint o)))
           buls (list (ln:tan (/ (vla-get-TotalAngle o) 4.0)) 0.0)))
  )
  (if ext
    (progn
      (setq t0 (vlax-curve-getFirstDeriv o (vlax-curve-getStartParam o))
            tn (vlax-curve-getFirstDeriv o (vlax-curve-getEndParam o)))
      (setq pts  (append (list (polar (car pts) (+ (angle '(0 0) (ln:2d t0)) pi) ext))
                         pts
                         (list (polar (last pts) (angle '(0 0) (ln:2d tn)) ext)))
            buls (append '(0.0) (reverse (cdr (reverse buls))) '(0.0 0.0)))
      (ln:mk-lw pts buls nil "0"))
    (ln:mk-lw pts buls (= typ "LWPOLYLINE") "0"))
)

;;; +1 ou -1: sinal do offset que vai para o lado do ponto pt
(defun ln:sinal (o pt / r s)
  (setq s 1.0)
  (if (setq r (ln:offset o 1.0))
    (progn
      (if (> (distance pt (vlax-curve-getClosestPointTo (car r) pt))
             (distance pt (vlax-curve-getClosestPointTo o pt)))
        (setq s -1.0))
      (mapcar 'vla-delete r)))
  s
)

;;; --------------------------------------------------------------------------
;;; Caminho rápido: referência RETA (LINE ou LWPOLYLINE colinear sem arcos)
;;; --------------------------------------------------------------------------
;;; Toda guia/plantio de uma referência reta é a reta  v = d  no sistema
;;; local (u ao longo da referência, v perpendicular, positivo à esquerda).
;;; O contorno do talhão é quebrado em trechos MONÓTONOS em v (segmentos e
;;; arcos partidos nos pontos de v máximo/mínimo); cada trecho só visita as
;;; distâncias dentro da sua faixa [vmin, vmax) - busca binária na lista
;;; ordenada - e calcula o u do cruzamento por fórmula. Ordenando os
;;; cruzamentos de cada distância, os pares (u1 u2) (u3 u4)... são os trechos
;;; internos (regra par/ímpar; faixa semiaberta = vértice contado uma vez).
;;; Custo O(lados + cruzamentos) em LISP puro, sem Offset / IntersectWith /
;;; Delete via COM, e as pontas ficam exatas sobre o contorno (inclusive arcos).

(defun ln:u (p o dir) (+ (* (- (car p) (car o)) (car dir)) (* (- (cadr p) (cadr o)) (cadr dir))))
(defun ln:v (p o dir) (- (* (- (cadr p) (cadr o)) (car dir)) (* (- (car p) (car o)) (cadr dir))))
(defun ln:mundo (o dir u v)
  (list (- (+ (car o) (* u (car dir))) (* v (cadr dir)))
        (+ (cadr o) (* u (cadr dir)) (* v (car dir))))
)

;;; (origem direção-unitária) se a curva for reta; senão nil
(defun ln:reta (e / ed typ d pts p0 p1 len dir)
  (setq ed (entget e) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (setq p0 (ln:2d (cdr (assoc 10 ed))) p1 (ln:2d (cdr (assoc 11 ed)))))
    ((= typ "LWPOLYLINE")
     (setq d (ln:lw-data e) pts (car d))
     (if (and (not (caddr d))
              (vl-every '(lambda (b) (equal b 0.0 1e-9)) (reverse (cdr (reverse (cadr d))))))
       (setq p0 (car pts) p1 (last pts)))))
  (if (and p0 p1 (> (setq len (distance p0 p1)) 1e-6))
    (progn
      (setq dir (list (/ (- (car p1) (car p0)) len) (/ (- (cadr p1) (cadr p0)) len)))
      (if (vl-every '(lambda (p) (< (abs (ln:v p p0 dir)) 1e-4)) pts)   ; colinear
        (list p0 dir))))
)

;;; trechos monótonos do contorno, no sistema local:
;;;   reta : (vlo vhi 0 u0 v0 du/dv)
;;;   arco : (vlo vhi 1 cu cv R sinal-do-cos)
(defun ln:trechos (bnd o dir / d pts bl p0 p1 bu v0 v1 th c r a0 a1 amin amax
                           vmin vmax e k angs res as ae vs ve)
  (setq d   (ln:lw-data (vlax-vla-object->ename bnd))
        pts (mapcar '(lambda (p) (list (ln:u p o dir) (ln:v p o dir))) (car d))
        bl  (cadr d)
        pts (append pts (list (car pts))))
  (while (cdr pts)
    (setq p0 (car pts) p1 (cadr pts) bu (car bl) pts (cdr pts) bl (cdr bl)
          v0 (cadr p0) v1 (cadr p1))
    (cond
      ((< (distance p0 p1) 1e-9))
      ((equal bu 0.0 1e-9)
       (if (/= v0 v1)
         (setq res (cons (list (min v0 v1) (max v0 v1) 0 (car p0) v0
                               (/ (- (car p1) (car p0)) (- v1 v0)))
                         res))))
      (T
       (setq th   (* 4.0 (atan bu))
             c    (polar p0 (+ (angle p0 p1) (- (/ pi 2.0) (/ th 2.0)))
                         (/ (* (distance p0 p1) (1+ (* bu bu))) (* 4.0 bu)))
             r    (distance c p0)
             a0   (angle c p0)
             a1   (+ a0 th)
             amin (min a0 a1) amax (max a0 a1)
             ;; v exato dos vértices nas pontas (coerente com os vizinhos)
             vmin (if (> th 0) v0 v1) vmax (if (> th 0) v1 v0)
             angs (list (cons amin vmin))
             k    (1+ (fix (/ (- amin (/ pi 2.0)) pi))))
       (if (< (- amin (/ pi 2.0)) 0) (setq k (fix (/ (- amin (/ pi 2.0)) pi))))
       ;; pontos de v extremo (pi/2 + k.pi) dentro do arco
       (while (< (setq e (+ (/ pi 2.0) (* k pi))) (- amax 1e-12))
         (if (> e (+ amin 1e-12))
           (setq angs (cons (cons e (+ (cadr c) (* r (sin e)))) angs)))
         (setq k (1+ k)))
       (setq angs (reverse (cons (cons amax vmax) angs)))
       (while (cdr angs)
         (setq as (car angs) ae (cadr angs) angs (cdr angs)
               vs (cdr as) ve (cdr ae))
         (if (/= vs ve)
           (setq res (cons (list (min vs ve) (max vs ve) 1 (car c) (cadr c) r
                                 (if (< (cos (/ (+ (car as) (car ae)) 2.0)) 0) -1.0 1.0))
                           res)))))))
  res
)

;;; primeiro índice i com (nth i ds) >= x  (ds crescente)
(defun ln:busca (ds n x / lo hi m)
  (setq lo 0 hi n)
  (while (< lo hi)
    (setq m (/ (+ lo hi) 2))
    (if (< (nth m ds) x) (setq lo (1+ m)) (setq hi m)))
  lo
)

;;; cria as linhas de itens (ordenados por distância) dentro do talhão
(defun ln:varre (trs itens o dir / ds tl l n hits seq i tail dd u tr cur us it lay cnt)
  (setq ds (mapcar 'car itens) n (length ds) l ds seq 0 cnt 0)
  (while l (setq tl (cons l tl) l (cdr l)))
  (setq tl (reverse tl))
  (foreach tr trs
    (setq i (ln:busca ds n (car tr)) tail (nth i tl))
    (while (and tail (< (setq dd (car tail)) (cadr tr)))
      (setq u (if (= 0 (caddr tr))
                (+ (nth 3 tr) (* (- dd (nth 4 tr)) (nth 5 tr)))
                (+ (nth 3 tr)
                   (* (nth 6 tr)
                      (sqrt (max 0.0 (- (* (nth 5 tr) (nth 5 tr))
                                        (* (- dd (nth 4 tr)) (- dd (nth 4 tr)))))))))
            hits (cons (list i u seq) hits)           ; seq: chave única p/ vl-sort
            seq  (1+ seq) i (1+ i) tail (cdr tail))))
  (setq hits (vl-sort hits '(lambda (a b) (if (= (car a) (car b))
                                            (if (= (cadr a) (cadr b))
                                              (< (caddr a) (caddr b))
                                              (< (cadr a) (cadr b)))
                                            (< (car a) (car b))))))
  ;; agrupa por distância e liga os pares de cruzamentos
  (while hits
    (setq cur (caar hits) us nil)
    (while (and hits (= (caar hits) cur))
      (setq us (cons (cadar hits) us) hits (cdr hits)))
    (setq us (reverse us) it (nth cur itens) dd (car it) lay (cadr it))
    (while (cdr us)
      (if (> (- (cadr us) (car us)) 1e-6)
        (progn
          (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                         '(100 . "AcDbPolyline") '(90 . 2) '(70 . 0) '(38 . 0.0)
                         (cons 10 (ln:mundo o dir (car us) dd)) '(42 . 0.0)
                         (cons 10 (ln:mundo o dir (cadr us) dd)) '(42 . 0.0)))
          (setq cnt (1+ cnt))))
      (setq us (cddr us))))
  cnt
)

;;; LINHAS INTERNAS, referência reta: devolve a quantidade criada
(defun ln:internas-reta (bnd rt lado limite / o dir trs vmin vmax lados lim)
  (setq o (car rt) dir (cadr rt) trs (ln:trechos bnd o dir))
  (if trs
    (progn
      (setq vmin  (apply 'min (mapcar 'car trs))
            vmax  (apply 'max (mapcar 'cadr trs))
            lados (if (listp lado)
                    (list (if (< (ln:v (ln:2d lado) o dir) 0.0) -1.0 1.0))
                    '(1.0 -1.0))
            lim   (if limite limite (+ (max vmax (- vmin)) (ln:meia-largura-plantio))))
      (ln:varre trs
                (vl-remove-if '(lambda (x) (or (< (car x) (- vmin 1e-6)) (> (car x) (+ vmax 1e-6))))
                              (ln:itens (ln:distancias lim nil) lados *LN-INCREF*))
                o dir))
    0)
)

;;; LINHAS INTERNAS, referência curva: offsets COM da referência prolongada,
;;; só até a extensão REAL do talhão em cada lado, + recorte por paridade
(defun ln:internas-curva (bnd ref lado limite / poly xs ys bb ext refo pm tm sl
                                                lmax rmax cp pr tg dd cr folga
                                                lim itens tot)
  (setq poly (ln:amostra bnd)
        xs   (mapcar 'car poly)
        ys   (mapcar 'cadr poly)
        bb   (list (list (apply 'min xs) (apply 'min ys))
                   (list (apply 'max xs) (apply 'max ys)))
        ext  (* 1.5 (distance (car bb) (cadr bb)))
        refo (ln:ref-ext ref ext)
        lmax 0.0 rmax 0.0 tot 0)
  ;; extensão do talhão à esquerda / à direita da referência
  (foreach p poly
    (setq cp (vlax-curve-getClosestPointTo refo p)
          dd (distance p (ln:2d cp))
          pr (vlax-curve-getParamAtPoint refo cp)
          tg (if pr (vlax-curve-getFirstDeriv refo pr)))
    (if tg
      (if (> (- (* (car tg) (- (cadr p) (cadr cp))) (* (cadr tg) (- (car p) (car cp)))) 0)
        (setq lmax (max lmax dd))
        (setq rmax (max rmax dd)))
      (setq lmax (max lmax dd) rmax (max rmax dd))))
  (setq folga (ln:folga-arcos bnd) lmax (+ lmax folga) rmax (+ rmax folga))
  ;; sinal do offset que vai para a esquerda
  (setq pr (/ (+ (vlax-curve-getStartParam refo) (vlax-curve-getEndParam refo)) 2.0)
        pm (vlax-curve-getPointAtParam refo pr)
        tm (vlax-curve-getFirstDeriv refo pr)
        sl (ln:sinal refo (polar pm (+ (angle '(0 0) (ln:2d tm)) (/ pi 2.0)) 1.0)))
  (setq lim   (if limite limite (+ (max lmax rmax) (ln:meia-largura-plantio)))
        itens (vl-remove-if
                '(lambda (x) (> (abs (car x)) (if (> (* (car x) sl) 0.0) lmax rmax)))
                (ln:itens (ln:distancias lim nil) (ln:lados refo lado) *LN-INCREF*)))
  (foreach it itens
    (foreach o (ln:offset refo (car it))
      (setq tot (+ tot (length (ln:clip o bnd poly bb (cadr it)))))))
  (vla-delete refo)
  tot
)

;;; garante (uma vez por comando) os layers que o modo atual pode usar
(defun ln:garante-todos (/ l)
  (if (member *LN-MODO* '("G" "GC"))
    (setq l (cons (list 0 *LN-LAYG* *LN-CORG*)
                  (mapcar '(lambda (r) (list 0 (ln:r-lay r) (ln:r-cor r))) *LN-SEQ*))))
  (if (member *LN-MODO* '("GC" "C"))
    (setq l (cons (list 0 *LN-LAYP* *LN-CORP*) l)))
  (ln:garante-layers l)
)

;;; offsets de o com as linhas já no layer certo e ByLayer: copia o UMA vez
;;; por layer (cópia-base) e tira os offsets dela -> 0 chamadas COM de
;;; propriedade por linha criada (antes eram 3: Layer, Color, Linetype)
(defun ln:offsets-em (o itens / bases b n)
  (setq n 0)
  (foreach it itens
    (if (not (setq b (cdr (assoc (cadr it) bases))))
      (setq b     (ln:poe (vla-Copy o) (cadr it))
            bases (cons (cons (cadr it) b) bases)))
    (setq n (+ n (length (ln:offset b (car it))))))
  (foreach b bases (vla-delete (cdr b)))
  n
)

;;; --------------------------------------------------------------------------
;;; Sequência de espaçamentos
;;; --------------------------------------------------------------------------
(defun ln:r-lay (r) (if (and (nth 3 r) (/= "" (nth 3 r))) (nth 3 r) *LN-LAYG*))
(defun ln:r-cor (r) (if (and (nth 3 r) (/= "" (nth 3 r)) (nth 4 r)) (nth 4 r) *LN-CORG*))
(defun ln:tem-rep () (vl-some 'caddr *LN-SEQ*))

(defun ln:bloco-rep (rows / b)
  (while (and rows (caddr (car rows)))
    (setq b (cons (car rows) b) rows (cdr rows)))
  (reverse b)
)

;;; distâncias acumuladas das guias: ((dist layer cor) ...)
;;; lim  = distância máxima (nil = sem limite)
;;; nmax = quantidade máxima (nil = sem limite)
;;; Linhas 1x entram uma vez; a partir da primeira (R), ela e as (R)
;;; seguidas formam um ciclo repetido até lim/nmax (sem limites: um ciclo).
(defun ln:distancias (lim nmax / d n res go rows bloco passo infinito)
  (setq d 0.0 n 0 go T rows *LN-SEQ* infinito (and (not lim) (not nmax)))
  (if (not nmax) (setq nmax 20000))
  (defun passo (r)
    (repeat (car r)
      (if go
        (progn
          (setq d (+ d (cadr r)))
          (if (or (and lim (> d (+ lim 1e-6))) (>= n nmax))
            (setq go nil)
            (setq res (cons (list d (ln:r-lay r) (ln:r-cor r)) res) n (1+ n)))))))
  (while (and go rows)
    (if (caddr (car rows))
      (progn
        (setq bloco (ln:bloco-rep rows) rows nil)
        (while go
          (foreach r bloco (passo r))
          (if infinito (setq go nil))))
      (progn (passo (car rows)) (setq rows (cdr rows)))))
  (reverse res)
)

(defun ln:plantio-offs (/ i res)
  (setq i 0)
  (repeat *LN-PQTD*
    (setq res (cons (* (- i (/ (- *LN-PQTD* 1) 2.0)) *LN-PESP*) res) i (1+ i)))
  (reverse res)
)

(defun ln:meia-largura-plantio ()
  (if (member *LN-MODO* '("GC" "C")) (* (/ (- *LN-PQTD* 1) 2.0) *LN-PESP*) 0.0)
)

;;; itens a gerar a partir de uma curva base:
;;;   ((distancia-assinada layer cor guia?) ...) ordenados e sem duplicatas
;;; lados  = (1.0) ou (1.0 -1.0);  comref = a própria base conta como guia
(defun ln:itens (dists lados comref / bruto ant res)
  (if (member *LN-MODO* '("G" "GC"))
    (progn
      (if comref (setq bruto (list (list 0.0 *LN-LAYG* *LN-CORG* T))))
      (foreach d dists
        (foreach s lados
          (setq bruto (cons (list (* s (car d)) (cadr d) (caddr d) T) bruto))))))
  (if (member *LN-MODO* '("GC" "C"))
    (foreach d (if comref (cons '(0.0) dists) dists)
      (foreach s lados
        (foreach p (ln:plantio-offs)
          (setq bruto (cons (list (+ (* s (car d)) p) *LN-LAYP* *LN-CORP* nil) bruto))))))
  ;; ordena por distância; na mesma posição a guia vem antes do plantio
  (setq bruto (vl-sort bruto
                       '(lambda (a b)
                          (if (equal (car a) (car b) 1e-4)
                            (and (cadddr a) (not (cadddr b)))
                            (< (car a) (car b))))))
  (foreach x bruto
    (if (not (and ant (equal (car x) (car ant) 1e-4)))
      (setq res (cons x res) ant x)))
  (reverse res)
)

(defun ln:garante-layers (itens / feitos)
  (foreach x itens
    (if (not (member (strcase (cadr x)) feitos))
      (progn (ln:layer (cadr x) (caddr x)) (setq feitos (cons (strcase (cadr x)) feitos)))))
)

;;; --------------------------------------------------------------------------
;;; Predefinições (.ofv)
;;;   qtd<TAB>dist<TAB>0 (R)|1x[<TAB>layer<TAB>cor]   linhas da sequência
;;;   #LINHAS (opções...)                             opções do diálogo
;;; Lê também: .OFV do AgroCAD, .lin do CRIALINHAS v1, .ofv do VARSULC.
;;; --------------------------------------------------------------------------
(defun ln:pasta-lisps ()
  (cond (*LISPS-DIR*)
        ((findfile "CriaLinhas.dcl") (vl-filename-directory (findfile "CriaLinhas.dcl"))))
)

(defun ln:pasta-config (/ p)
  (setq p (if (ln:pasta-lisps)
            (strcat (ln:pasta-lisps) "\\config")
            (strcat (getvar "TEMPPREFIX") "lisps_config")))
  (if (not (vl-file-directory-p p)) (vl-mkdir p))
  p
)

(defun ln:arq-padrao () (strcat (ln:pasta-config) "\\CRIALINHAS_PADRAO.ofv"))

(defun ln:campos (s / r cur c i)
  (setq i 1 cur "")
  (repeat (strlen s)
    (setq c (substr s i 1) i (1+ i))
    (if (member c '("\t" " " ";"))
      (progn (if (/= cur "") (setq r (cons cur r))) (setq cur ""))
      (setq cur (strcat cur c))))
  (if (/= cur "") (setq r (cons cur r)))
  (reverse r)
)

(defun ln:split-tab (s / r p)
  (if (vl-string-search "\t" s)
    (progn
      (while (setq p (vl-string-search "\t" s))
        (setq r (cons (vl-string-trim " " (substr s 1 p)) r) s (substr s (+ p 2))))
      (reverse (cons (vl-string-trim " " s) r)))
    (ln:campos s))
)

(defun ln:salvar (arq / f)
  (if (setq f (open arq "w"))
    (progn
      (foreach r *LN-SEQ*
        (write-line (strcat (itoa (car r)) "\t" (rtos (cadr r) 2 4) "\t"
                            (if (caddr r) "0 (R)" "1x")
                            (if (and (nth 3 r) (/= "" (nth 3 r)))
                              (strcat "\t" (nth 3 r) "\t" (itoa (ln:r-cor r)))
                              ""))
                    f))
      (write-line (strcat "#LINHAS " (vl-prin1-to-string (mapcar 'eval *LN-OPC*))) f)
      (close f)
      T))
)

(defun ln:ler (s / v)
  (setq v (vl-catch-all-apply 'read (list s)))
  (if (and (not (vl-catch-all-error-p v)) (listp v)) v)
)

(defun ln:carregar (arq / f l c d seq opc ovs ocl lay cor rep)
  (if (and arq (findfile arq) (setq f (open arq "r")))
    (progn
      (while (setq l (read-line f))
        (cond
          ((= (substr l 1 7) "#LINHAS") (setq opc (ln:ler (substr l 8))))
          ((= (substr l 1 1) "#") (setq ovs (ln:ler (substr l 2))))        ; VARSULC
          ((= (substr l 1 1) "(") (setq ocl (ln:ler l)))                    ; CRIALINHAS v1
          ((and (setq c (ln:split-tab l)) (cdr c)
                (> (atoi (car c)) 0)
                (setq d (ln:num (cadr c))) (> d 0))
           (setq lay (nth 3 c) cor (if (nth 4 c) (atoi (nth 4 c))))
           (if (not (and lay (snvalid lay))) (setq lay nil cor nil))
           (if (and cor (not (< 0 cor 256))) (setq cor nil))
           (setq rep (cond ((or (null (caddr c)) (= "" (caddr c))) 'X)
                           ((wcmatch (strcase (caddr c)) "*R*") T)))
           (setq seq (cons (list (atoi (car c)) d rep lay cor) seq)))))
      (close f)
      (cond
        ;; CRIALINHAS v1: (modo espg manual qtd espp pass recuar ambos layg corg layp corp)
        ((and ocl (= 12 (length ocl)))
         (mapcar 'set '(*LN-MODO* d *LN-MANUAL* *LN-PQTD* *LN-PESP* *LN-PASS* *LN-RECUAR*
                        rep *LN-LAYG* *LN-CORG* *LN-LAYP* *LN-CORP*) ocl)
         (setq *LN-SEQ* (list (list 1 d T nil nil)) *LN-LADO* (if rep "A" "U"))
         T)
        (seq
         (if (= (length opc) (length *LN-OPC*)) (mapcar 'set *LN-OPC* opc))
         ;; VARSULC: (rep lado layer cor incref)
         (if (= 5 (length ovs))
           (setq *LN-REP* (nth 0 ovs) *LN-LADO* (nth 1 ovs) *LN-LAYG* (nth 2 ovs)
                 *LN-CORG* (nth 3 ovs) *LN-INCREF* (nth 4 ovs)
                 *LN-MODO* "G"))                 ; o VARSULC só criava guias
         ;; sem 3a coluna (arquivo antigo): usa o Repetir global
         (setq *LN-SEQ* (mapcar '(lambda (r)
                                   (list (car r) (cadr r)
                                         (if (eq (caddr r) 'X) *LN-REP* (caddr r))
                                         (nth 3 r) (nth 4 r)))
                                (reverse seq)))
         T))))
)

;;; --------------------------------------------------------------------------
;;; Ações
;;; --------------------------------------------------------------------------
(defun ln:sel-talhoes (/ ss i res)
  (princ "\nSelecione os talhões: ")
  (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq res (cons (vlax-ename->vla-object (ssname ss i)) res) i (1+ i)))))
  res
)

(defun ln:sel-ref (tipos / ent)
  (while (and (setq ent (entsel "\nSelecione a curva de referência: "))
              (not (member (cdr (assoc 0 (entget (car ent)))) tipos)))
    (princ "\nTipo de curva não suportado."))
  (if ent (car ent))
)

;;; lado: devolve T para "ambos", o ponto indicado para "um lado", ou nil
(defun ln:pede-lado ()
  (if (= *LN-LADO* "A") T (getpoint "\nIndique o lado das linhas: "))
)

;;; sinais de offset para a base o
(defun ln:lados (o lado) (if (listp lado) (list (ln:sinal o lado)) '(1.0 -1.0)))

(defun ln:pos-final (o / pt)
  (if (setq pt (getpoint "\nIndique a posição final das linhas: "))
    (distance (ln:2d pt) (ln:2d (vlax-curve-getClosestPointTo o pt T))))
)

;;; CABECEIRA: offsets do contorno seguindo a sequência (N passadas)
(defun ln:cabeceira (dentro / talhoes dists sh itens a0 r sinal tot t0)
  (if (setq talhoes (ln:sel-talhoes))
    (progn
      (setq t0    (getvar "MILLISECS")
            dists (ln:distancias nil *LN-PASS*))
      (if (and *LN-RECUAR* dists)
        (setq sh    (/ (car (car dists)) 2.0)
              dists (mapcar '(lambda (d) (cons (- (car d) sh) (cdr d))) dists)))
      ;; só o que fica do lado certo do contorno
      (setq itens (vl-remove-if '(lambda (x) (<= (car x) 1e-6))
                                (ln:itens dists '(1.0) nil))
            tot   0)
      (ln:garante-layers itens)
      (foreach bnd talhoes
        (setq a0 (vla-get-Area bnd) sinal 1.0)
        (if (setq r (ln:offset bnd 1.0))
          (progn (if (> (vla-get-Area (car r)) a0) (setq sinal -1.0)) (mapcar 'vla-delete r)))
        (if (not dentro) (setq sinal (- sinal)))
        (setq tot (+ tot (ln:offsets-em bnd (mapcar '(lambda (it) (cons (* sinal (car it)) (cdr it)))
                                                    itens)))))
      (princ (strcat "\n" (itoa tot) " linha(s) de cabeceira criada(s)." (ln:tempo t0)))))
)

;;; LINHAS INTERNAS nos talhões
;;;   referência reta  -> varredura analítica (ln:internas-reta)
;;;   referência curva -> offsets COM + recorte (ln:internas-curva)
(defun ln:internas (/ talhoes ref lado limite rt tot t0)
  (if (and (setq talhoes (ln:sel-talhoes))
           (setq ref (ln:sel-ref '("LINE" "LWPOLYLINE" "ARC")))
           (setq lado (ln:pede-lado))
           (or (not *LN-MANUAL*)
               (setq limite (ln:pos-final (vlax-ename->vla-object ref)))))
    (progn
      (setq t0  (getvar "MILLISECS")
            rt  (ln:reta ref)
            tot 0)
      (ln:garante-todos)
      (foreach bnd talhoes
        (setq tot (+ tot (if rt
                           (ln:internas-reta bnd rt lado limite)
                           (ln:internas-curva bnd ref lado limite)))))
      (princ (strcat "\n" (itoa tot) " linha(s) criada(s) em "
                     (itoa (length talhoes)) " talhão(ões)"
                     (if rt " - referência reta, modo rápido." ".")
                     (ln:tempo t0)))))
)

;;; SEM TALHÃO: offsets da própria referência (qualquer curva)
(defun ln:livre (/ ref o lado lim itens n t0)
  (if (and (setq ref (ln:sel-ref '("LINE" "LWPOLYLINE" "ARC" "SPLINE" "POLYLINE"
                                   "CIRCLE" "ELLIPSE")))
           (setq o (vlax-ename->vla-object ref))
           (setq lado (ln:pede-lado))
           (or (not (or *LN-MANUAL* (ln:tem-rep)))
               (setq lim (ln:pos-final o))))
    (progn
      (setq t0 (getvar "MILLISECS"))
      ;; a referência já existe: não cria guia por cima dela (distância 0)
      (setq itens (vl-remove-if '(lambda (x) (and (cadddr x) (equal (car x) 0.0 1e-9)))
                                (ln:itens (ln:distancias lim nil) (ln:lados o lado) *LN-INCREF*)))
      (ln:garante-layers itens)
      (setq n (ln:offsets-em o itens))
      (princ (strcat "\n" (itoa n) " linha(s) criada(s)." (ln:tempo t0)))))
)

;;; SELECIONAR: plantio em torno de guias já existentes
(defun ln:selecionar (/ ss i offs itens n o t0)
  (if (= *LN-MODO* "G")
    (princ "\nNo modo 'Somente Guias' não há plantio a criar a partir de guias.")
    (progn
      (princ "\nSelecione as linhas guias: ")
      (if (setq ss (ssget '((0 . "LINE,LWPOLYLINE,ARC,SPLINE,POLYLINE"))))
        (progn
          (setq t0 (getvar "MILLISECS"))
          ;; plantio sobre a própria guia só no modo "Somente Plantio"
          (setq offs  (vl-remove-if '(lambda (p) (and (equal p 0.0 1e-9) (/= *LN-MODO* "C")))
                                    (ln:plantio-offs))
                itens (mapcar '(lambda (p) (list p *LN-LAYP*)) offs)
                i 0 n 0)
          (ln:layer *LN-LAYP* *LN-CORP*)
          (repeat (sslength ss)
            (setq o (vlax-ename->vla-object (ssname ss i)) i (1+ i))
            (if (cdr offs)
              (setq n (+ n (ln:offsets-em o itens)))         ; 2+ linhas: cópia-base
              (foreach p offs
                (foreach x (ln:offset o p) (ln:poe x *LN-LAYP*) (setq n (1+ n))))))
          (princ (strcat "\n" (itoa n) " linha(s) de plantio criada(s)." (ln:tempo t0))))))
  )
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun ln:set-nth (i v l / k) (setq k -1) (mapcar '(lambda (x) (if (= (setq k (1+ k)) i) v x)) l))
(defun ln:del-nth (i l / k) (setq k -1) (vl-remove-if '(lambda (x) (= (setq k (1+ k)) i)) l))
(defun ln:troca (i j l / a b)
  (setq a (nth i l) b (nth j l))
  (ln:set-nth j a (ln:set-nth i b l))
)

;;; linha vertical tracejada na imagem
(defun ln:vtrac (x h cor passo / c)
  (setq c 0)
  (while (< c h)
    (vector_image x c x (min h (+ c passo)) cor)
    (setq c (+ c (* 2 passo))))
)

;;; pré-visualização: o padrão real das primeiras guias, com as cores
(defun ln:desenha (/ w h itens dmin dmax px)
  (setq w (dimx_tile "img") h (dimy_tile "img"))
  (start_image "img")
  (fill_image 0 0 w h -15)
  (setq itens (ln:itens (ln:distancias nil 6) '(1.0) *LN-INCREF*))
  (if itens
    (progn
      (setq dmin (min 0.0 (apply 'min (mapcar 'car itens)))
            dmax (max (+ dmin 1e-6) (apply 'max (mapcar 'car itens))))
      (defun px (d) (fix (+ 6 (* (/ (- d dmin) (- dmax dmin)) (- w 12)))))
      (ln:vtrac (px 0.0) h 7 1)                                    ; referência
      (foreach it itens
        (if (cadddr it)
          (ln:vtrac (px (car it)) h (caddr it) 4)                  ; guia
          (vector_image (px (car it)) 0 (px (car it)) h (caddr it))))))  ; plantio
  (end_image)
)

(defun ln:resumo (/ rows n larg bloco ciclo sobra)
  (setq rows *LN-SEQ* n 0 larg 0.0)
  (while (and rows (not (caddr (car rows))))
    (setq n    (+ n (car (car rows)))
          larg (+ larg (* (car (car rows)) (cadr (car rows))))
          rows (cdr rows)))
  (if rows
    (progn
      (setq bloco (ln:bloco-rep rows) ciclo 0.0
            sobra (- (length rows) (length bloco)))
      (foreach r bloco (setq ciclo (+ ciclo (* (car r) (cadr r)))))
      (set_tile "resumo"
        (strcat (itoa n) " fixa(s) (" (rtos larg 2 2) " m) + ciclo (R) de " (rtos ciclo 2 2) " m"
                (if (> sobra 0) (strcat " | " (itoa sobra) " linha(s) após o ciclo ignorada(s)") ""))))
    (set_tile "resumo" (strcat (itoa n) " guia(s), largura total " (rtos larg 2 2) " m")))
)

(defun ln:mostra (i / r)
  (if (setq r (nth i *LN-SEQ*))
    (progn
      (set_tile "qtd"     (itoa (car r)))
      (set_tile "dist"    (rtos (cadr r) 2 4))
      (set_tile "repetir" (if (caddr r) "1" "0"))
      (set_tile "lnlay"   (if (nth 3 r) (nth 3 r) ""))
      (set_tile "lncor"   (if (and (nth 3 r) (nth 4 r)) (itoa (nth 4 r)) ""))
      (setq *LN-REP* (caddr r))))
)

(defun ln:lista (sel)
  (start_list "lista")
  (foreach r *LN-SEQ*
    (add_list (strcat (itoa (car r)) "\tx\t" (rtos (cadr r) 2 3) " m\t"
                      (if (caddr r) "(R)" "1x") "\t"
                      (if (and (nth 3 r) (/= "" (nth 3 r))) (nth 3 r) "(layer das guias)"))))
  (end_list)
  (if (and sel *LN-SEQ*)
    (progn
      (setq sel (max 0 (min sel (1- (length *LN-SEQ*)))))
      (set_tile "lista" (itoa sel))
      (ln:mostra sel)))
  (mode_tile "del" (if *LN-SEQ* 0 1))
  (ln:resumo)
  (ln:desenha)
)

(defun ln:sel (/ s) (if (/= "" (setq s (get_tile "lista"))) (atoi s)))

(defun ln:le-linha (/ q d lay cs cor)
  (setq q   (atoi (get_tile "qtd"))
        d   (ln:num (get_tile "dist"))
        lay (vl-string-trim " " (get_tile "lnlay"))
        cs  (vl-string-trim " " (get_tile "lncor"))
        cor (if (/= cs "") (atoi cs)))
  (cond
    ((not (and (> q 0) d (> d 0)))
     (set_tile "status" "Quantidade (>= 1) ou distância (> 0) inválida.") nil)
    ((and (/= lay "") (not (snvalid lay)))
     (set_tile "status" "Nome de layer da linha inválido.") nil)
    ((and cor (not (< 0 cor 256)))
     (set_tile "status" "Cor da linha inválida (1-255).") nil)
    (T
     (set_tile "status" "")
     (list q d (= (get_tile "repetir") "1") (if (/= lay "") lay) (if (/= lay "") cor))))
)

(defun ln:acao (op / i r)
  (setq i (ln:sel))
  (cond
    ((= op "add")
     (if (setq r (ln:le-linha))
       (progn (setq *LN-SEQ* (append *LN-SEQ* (list r))) (ln:lista (1- (length *LN-SEQ*))))))
    ((not i) (set_tile "status" "Selecione uma linha da sequência."))
    ((= op "alt")
     (if (setq r (ln:le-linha)) (progn (setq *LN-SEQ* (ln:set-nth i r *LN-SEQ*)) (ln:lista i))))
    ((= op "del") (setq *LN-SEQ* (ln:del-nth i *LN-SEQ*)) (ln:lista i))
    ((and (= op "up") (> i 0)) (setq *LN-SEQ* (ln:troca i (1- i) *LN-SEQ*)) (ln:lista (1- i)))
    ((and (= op "down") (< i (1- (length *LN-SEQ*))))
     (setq *LN-SEQ* (ln:troca i (1+ i) *LN-SEQ*)) (ln:lista (1+ i)))
  )
)

;;; caixa Repetir: vale na hora para a linha selecionada
(defun ln:acao-rep (v / i r)
  (setq *LN-REP* (= v "1"))
  (if (and (setq i (ln:sel)) (setq r (nth i *LN-SEQ*)))
    (progn
      (setq *LN-SEQ* (ln:set-nth i (list (car r) (cadr r) *LN-REP* (nth 3 r) (nth 4 r)) *LN-SEQ*))
      (ln:lista i)))
)

(defun ln:habilita ()
  (foreach k '("pqtd" "pesp" "layp" "corp") (mode_tile k (if (= *LN-MODO* "G") 1 0)))
  (mode_tile "selecionar" (if (= *LN-MODO* "G") 1 0))
  (ln:desenha)
)

(defun ln:preenche ()
  (set_tile "modo"     *LN-MODO*)
  (set_tile "layg"     *LN-LAYG*)
  (set_tile "corg"     (itoa *LN-CORG*))
  (set_tile "pqtd"     (itoa *LN-PQTD*))
  (set_tile "pesp"     (rtos *LN-PESP* 2 4))
  (set_tile "layp"     *LN-LAYP*)
  (set_tile "corp"     (itoa *LN-CORP*))
  (set_tile "passadas" (itoa *LN-PASS*))
  (set_tile "recuar"   (if *LN-RECUAR* "1" "0"))
  (set_tile "lado"     *LN-LADO*)
  (set_tile "manual"   (if *LN-MANUAL* "1" "0"))
  (set_tile "incref"   (if *LN-INCREF* "1" "0"))
  (ln:lista 0)
  (set_tile "repetir"  (if *LN-REP* "1" "0"))
  (ln:habilita)
)

;;; lê e valida as opções; devolve T se tudo certo
(defun ln:le-tiles (/ corg corp pqtd pesp pass)
  (setq corg (atoi (get_tile "corg")) corp (atoi (get_tile "corp"))
        pqtd (atoi (get_tile "pqtd")) pesp (ln:num (get_tile "pesp"))
        pass (atoi (get_tile "passadas")))
  (cond
    ((null *LN-SEQ*) (set_tile "status" "A sequência de espaçamentos está vazia.") nil)
    ((not (snvalid (get_tile "layg"))) (set_tile "status" "Layer das guias inválido.") nil)
    ((not (< 0 corg 256)) (set_tile "status" "Cor das guias inválida (1-255).") nil)
    ((< pqtd 1) (set_tile "status" "Quantidade de linhas de plantio inválida.") nil)
    ((not (and pesp (> pesp 0))) (set_tile "status" "Espaçamento do plantio inválido.") nil)
    ((not (snvalid (get_tile "layp"))) (set_tile "status" "Layer do plantio inválido.") nil)
    ((not (< 0 corp 256)) (set_tile "status" "Cor do plantio inválida (1-255).") nil)
    ((< pass 1) (set_tile "status" "Número de passadas inválido.") nil)
    (T
     (setq *LN-MODO*   (get_tile "modo")
           *LN-LAYG*   (get_tile "layg")   *LN-CORG* corg
           *LN-PQTD*   pqtd                *LN-PESP* pesp
           *LN-LAYP*   (get_tile "layp")   *LN-CORP* corp
           *LN-PASS*   pass
           *LN-RECUAR* (= (get_tile "recuar") "1")
           *LN-LADO*   (get_tile "lado")
           *LN-MANUAL* (= (get_tile "manual") "1")
           *LN-INCREF* (= (get_tile "incref") "1"))
     (set_tile "status" "")
     T)
  )
)

;;; campo alterado: atualiza parâmetros e a pré-visualização
(defun ln:mudou () (if (ln:le-tiles) (progn (ln:resumo) (ln:habilita))))

(defun c:CRIALINHAS (/ *error* doc dcl arqdcl r loop arq)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*"))
      (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (setq arqdcl (if (ln:pasta-lisps) (strcat (ln:pasta-lisps) "\\CriaLinhas.dcl")))
  (if (not (and arqdcl (findfile arqdcl)))
    (progn (alert "Arquivo CriaLinhas.dcl não encontrado.") (exit)))
  (if (not *LN-INIT*)
    (progn
      ;; padrão da v2; senão migra o padrão do VARSULC ou do CRIALINHAS v1
      (or (ln:carregar (ln:arq-padrao))
          (ln:carregar (strcat (ln:pasta-config) "\\VARSULC_PADRAO.ofv"))
          (ln:carregar (strcat (ln:pasta-config) "\\CRIALINHAS_PADRAO.lin")))
      (setq *LN-INIT* T)))

  (setq loop T)
  (while loop
    (setq dcl (load_dialog arqdcl))
    (if (not (new_dialog "crialinhas" dcl))
      (progn (alert "Erro ao abrir o diálogo.") (exit)))
    (ln:preenche)
    (action_tile "modo"       "(ln:mudou)")
    (foreach k '("layg" "corg" "pqtd" "pesp" "layp" "corp" "incref")
      (action_tile k "(ln:mudou)"))
    (action_tile "lista"      "(ln:mostra (atoi $value))")
    (action_tile "repetir"    "(ln:acao-rep $value)")
    (action_tile "add"        "(ln:acao \"add\")")
    (action_tile "alt"        "(ln:acao \"alt\")")
    (action_tile "del"        "(ln:acao \"del\")")
    (action_tile "up"         "(ln:acao \"up\")")
    (action_tile "down"       "(ln:acao \"down\")")
    (action_tile "dentro"     "(if (ln:le-tiles) (done_dialog 2))")
    (action_tile "fora"       "(if (ln:le-tiles) (done_dialog 3))")
    (action_tile "criar"      "(if (ln:le-tiles) (done_dialog 4))")
    (action_tile "livre"      "(if (ln:le-tiles) (done_dialog 5))")
    (action_tile "selecionar" "(if (ln:le-tiles) (done_dialog 6))")
    (action_tile "carregar"   "(done_dialog 7)")
    (action_tile "salvar"     "(if (ln:le-tiles) (done_dialog 8))")
    (action_tile "padrao"
      "(if (ln:le-tiles) (set_tile \"status\" (if (ln:salvar (ln:arq-padrao)) \"Gravado como padrão.\" \"Não foi possível gravar o padrão.\")))")
    (action_tile "cancel"     "(done_dialog 0)")
    (setq r (start_dialog))
    (unload_dialog dcl)
    (setq dcl nil)
    (cond
      ((member r '(2 3 4 5 6))
       (vla-StartUndoMark doc)
       (cond ((= r 2) (ln:cabeceira T))
             ((= r 3) (ln:cabeceira nil))
             ((= r 4) (ln:internas))
             ((= r 5) (ln:livre))
             ((= r 6) (ln:selecionar)))
       (vla-EndUndoMark doc))                    ; volta ao diálogo
      ((= r 7)
       (if (setq arq (getfiled "Carregar predefinição (.ofv do LISPS/AgroCAD ou .lin)"
                               (strcat (ln:pasta-config) "\\") "ofv;lin" 0))
         (if (ln:carregar arq)
           (princ (strcat "\nPredefinição carregada: " arq))
           (alert "Arquivo de predefinição inválido."))))
      ((= r 8)
       (if (setq arq (getfiled "Salvar predefinição" (strcat (ln:pasta-config) "\\") "ofv" 1))
         (if (ln:salvar arq) (princ (strcat "\nPredefinição salva: " arq)))))
      (T (setq loop nil))
    )
  )
  (princ)
)

;;; atalho: o antigo VARSULC agora é o mesmo diálogo
(defun c:VARSULC () (c:CRIALINHAS))

(princ "\nCriaLinhas v2.1 carregado. Comandos: CRIALINHAS (VARSULC)")
(princ)
