;;; ==========================================================================
;;; ConectaLinhas.lsp - Conectar Linhas entre Talhões
;;; --------------------------------------------------------------------------
;;; Equivalente ao GOCON do AgroCAD ("Conectar Linhas entre Talhões"):
;;; linhas da mesma fileira em talhões vizinhos (separados por carreador)
;;; viram UMA polilinha contínua: linha A + ligação reta + linha B + ...
;;; Menos linhas = menos manobras e arquivos menores no piloto automático.
;;;
;;; Critérios (diálogo):
;;;   Ângulo Máximo (°)    - deflexão máxima: entre as direções das duas linhas
;;;                          e entre cada linha e a ligação
;;;   Espaçamento (m)      - espaçamento das linhas: o desvio lateral da ponta
;;;                          seguinte, em relação ao prolongamento da linha,
;;;                          tem de ser <= meio espaçamento (não liga com a
;;;                          fileira vizinha)
;;;   Distância Máxima (m) - maior ligação (largura de carreador) aceita; evita
;;;                          ligar através de um talhão onde falta a fileira
;;;   Apagar Linhas Originais
;;;
;;; Cada ponta liga com a ponta válida MAIS PRÓXIMA (pares mais curtos
;;; primeiro, uma ligação por ponta, sem fechar ciclo).
;;;
;;; Desempenho:
;;;   - tudo em LISP puro sobre os dados DXF (entget / entmake / entdel):
;;;     nenhuma chamada COM por linha;
;;;   - busca de pares por varredura: as pontas são ordenadas pela coordenada
;;;     lateral à direção dominante e cada ponta só compara com as pontas numa
;;;     faixa de largura  Dmax.sen(desvio + Ângulo)  - nada de O(n²);
;;;   - casamento guloso com "outra ponta da cadeia" (evita ciclos em O(1)
;;;     por ligação, sem union-find).
;;;
;;; Linhas aceitas: LINE e LWPOLYLINE aberta (arcos preservados).
;;; Comando: CONECTALINHAS
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Parâmetros (persistem entre sessões via setenv)
;;; --------------------------------------------------------------------------
(defun cn:defaults ()
  (setq *CN-ANG* 15.0 *CN-ESP* 1.5 *CN-DMAX* 30.0 *CN-APAGAR* T)
)

(defun cn:le-env (/ v)
  (cn:defaults)
  (if (and (setq v (getenv "LISPS_CONECTALINHAS"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= 4 (length v))
           (vl-every 'numberp (list (car v) (cadr v) (caddr v))))
    (setq *CN-ANG* (car v) *CN-ESP* (cadr v) *CN-DMAX* (caddr v) *CN-APAGAR* (cadddr v)))
)

(defun cn:grava-env ()
  (setenv "LISPS_CONECTALINHAS"
          (vl-prin1-to-string (list *CN-ANG* *CN-ESP* *CN-DMAX* *CN-APAGAR*)))
)

(if (not *CN-ANG*) (cn:le-env))

;;; --------------------------------------------------------------------------
;;; Geometria
;;; --------------------------------------------------------------------------
(defun cn:2d (p) (list (car p) (cadr p)))

;;; diferença absoluta entre ângulos, em [0, pi]
(defun cn:dang (a b / d)
  (setq d (rem (abs (- a b)) (* 2.0 pi)))
  (if (> d pi) (- (* 2.0 pi) d) d)
)

;;; tangente no início (ini = T) ou no fim de um segmento p->q de bulge b
(defun cn:tang (p q b ini)
  (if ini (- (angle p q) (* 2.0 (atan b))) (+ (angle p q) (* 2.0 (atan b))))
)

;;; (pts bulges-dos-segmentos ed) de uma LINE / LWPOLYLINE aberta, sem
;;; vértices repetidos; nil se degenerada
(defun cn:dados (e / ed pts buls res ant)
  (setq ed (entget e))
  (if (= "LINE" (cdr (assoc 0 ed)))
    (setq pts  (list (cn:2d (cdr (assoc 10 ed))) (cn:2d (cdr (assoc 11 ed))))
          buls '(0.0 0.0))
    (foreach g ed
      (cond ((= (car g) 10) (setq pts (cons (cdr g) pts)))
            ((= (car g) 42) (setq buls (cons (cdr g) buls))))))
  (if (/= "LINE" (cdr (assoc 0 ed))) (setq pts (reverse pts) buls (reverse buls)))
  ;; tira vértices repetidos (o segmento nulo some; vale o bulge seguinte)
  (mapcar '(lambda (p b)
             (if (and ant (< (distance p (car ant)) 1e-9))
               (setq res (cons (cons (car ant) b) (cdr res)) ant (car res))
               (setq res (cons (cons p b) res) ant (car res))))
          pts buls)
  (setq res (reverse res))
  (if (cdr res)
    (list (mapcar 'car res)
          (reverse (cdr (reverse (mapcar 'cdr res)))) ; n-1 bulges de segmento
          ed))
)

;;; geometria orientada: fwd = T no sentido original
(defun cn:orienta (d fwd)
  (if fwd
    (list (car d) (cadr d))
    (list (reverse (car d)) (mapcar '- (reverse (cadr d)))))
)

;;; --------------------------------------------------------------------------
;;; Pontas e pares
;;; --------------------------------------------------------------------------
;;; ponta: (id y P ang)  id = 2.linha + (0 início | 1 fim)
;;;   ang = direção "para fora" da linha naquela ponta
(defun cn:pontas (dados / i res pts sb n)
  (setq i 0)
  (foreach d dados
    (setq pts (car d) sb (cadr d) n (length pts))
    (setq res (cons (list (* 2 i) 0.0 (car pts)
                          (+ pi (cn:tang (car pts) (cadr pts) (car sb) T)))
                    res)
          res (cons (list (1+ (* 2 i)) 0.0 (last pts)
                          (cn:tang (nth (- n 2) pts) (last pts) (last sb) nil))
                    res)
          i   (1+ i)))
  (reverse res)
)

;;; direção dominante (média axial ponderada pelo comprimento)
(defun cn:dominante (dados / c s a l)
  (setq c 0.0 s 0.0)
  (foreach d dados
    (setq a (angle (car (car d)) (last (car d))) l (distance (car (car d)) (last (car d)))
          c (+ c (* l (cos (* 2.0 a)))) s (+ s (* l (sin (* 2.0 a))))))
  (if (and (equal c 0.0 1e-12) (equal s 0.0 1e-12)) 0.0 (/ (atan s c) 2.0))
)

;;; comprimento da ligação a->b se as duas pontas casam; senão nil
(defun cn:par (a b amax meia dmax / pa pb v l av)
  (setq pa (caddr a) pb (caddr b) l (distance pa pb))
  (cond
    ((= (/ (car a) 2) (/ (car b) 2)) nil)                    ; mesma linha
    ((> l dmax) nil)
    ((> (cn:dang (cadddr a) (+ pi (cadddr b))) amax) nil)    ; direções
    ((< l 1e-6) 0.0)                                         ; já se tocam
    (T
     (setq av (angle pa pb))
     (if (and (<= (cn:dang (cadddr a) av) amax)              ; deflexão em a
              (<= (cn:dang (cadddr b) (+ av pi)) amax)       ; deflexão em b
              (<= (* l (abs (sin (- av (cadddr a))))) meia)  ; desvio lateral
              (<= (* l (abs (sin (- av (cadddr b))))) meia))
       l)))
)

;;; candidatos ((L ida idb) ...) ordenados por L
(defun cn:candidatos (pontas th0 amax meia dmax / ux uy fmax w ps tail b l res)
  (setq ux (cos th0) uy (sin th0) fmax 0.0)
  ;; coordenada lateral y e maior desvio das pontas em relação ao eixo
  (setq ps (mapcar '(lambda (p / q dv)
                      (setq q (caddr p) dv (cn:dang (cadddr p) th0))
                      (setq fmax (max fmax (min dv (- pi dv))))
                      (list (car p) (- (* (cadr q) ux) (* (car q) uy)) q (cadddr p)))
                   pontas))
  (setq w  (+ 1e-6 (* dmax (sin (min (/ pi 2.0) (+ fmax amax)))))
        ps (vl-sort ps '(lambda (a b) (if (= (cadr a) (cadr b)) (< (car a) (car b)) (< (cadr a) (cadr b))))))
  ;; varredura: cada ponta só olha as seguintes dentro da faixa w
  (while ps
    (setq tail (cdr ps))
    (while (and tail (<= (- (cadr (car tail)) (cadr (car ps))) w))
      (setq b (car tail) tail (cdr tail))
      (if (setq l (cn:par (car ps) b amax meia dmax))
        (setq res (cons (list l (car (car ps)) (car b)) res))))
    (setq ps (cdr ps)))
  (vl-sort res '(lambda (a b) (if (= (car a) (car b))
                                (if (= (cadr a) (cadr b)) (< (caddr a) (caddr b)) (< (cadr a) (cadr b)))
                                (< (car a) (car b)))))
)

;;; casamento guloso; devolve alist de ligações ((ponta . parceira) ...)
(defun cn:casa (cands nlin / outra usado lig i a b oa ob)
  (setq i 0)
  (repeat nlin
    (setq outra (cons (cons (* 2 i) (1+ (* 2 i))) (cons (cons (1+ (* 2 i)) (* 2 i)) outra))
          i     (1+ i)))
  (foreach c cands
    (setq a (cadr c) b (caddr c))
    (if (and (not (member a usado)) (not (member b usado))
             (/= b (setq oa (cdr (assoc a outra)))))          ; não fecha ciclo
      (setq ob    (cdr (assoc b outra))
            outra (cons (cons oa ob) (cons (cons ob oa) outra))
            usado (cons a (cons b usado))
            lig   (cons (cons a b) (cons (cons b a) lig)))))
  lig
)

;;; --------------------------------------------------------------------------
;;; Montagem das polilinhas
;;; --------------------------------------------------------------------------
;;; une as peças ((pts segbuls) ...) numa lista (pts bulges-por-vértice)
(defun cn:une (pecas / rp rb ult)
  (foreach pc pecas
    (cond
      ((null rp) (setq rp (reverse (car pc)) rb (reverse (cadr pc))))
      ((< (distance (car rp) (car (car pc))) 1e-6)           ; já se tocam
       (setq rp (append (reverse (cdr (car pc))) rp) rb (append (reverse (cadr pc)) rb)))
      (T
       (setq rb (cons 0.0 rb)                                 ; ligação reta
             rp (append (reverse (car pc)) rp)
             rb (append (reverse (cadr pc)) rb)))))
  (list (reverse rp) (reverse (cons 0.0 rb)))
)

(defun cn:mk-lw (pts buls ed / props)
  (foreach k '(8 62 6 370 48 420 440)
    (if (assoc k ed) (setq props (cons (assoc k ed) props))))
  (entmake
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity"))
      (reverse props)
      (list '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 0)
            (cons 38 (cond ((cdr (assoc 38 ed))) ((caddr (cdr (assoc 10 ed)))) (0.0))))
      (apply 'append (mapcar '(lambda (p b) (list (cons 10 p) (cons 42 b))) pts buls))))
)

;;; percorre as cadeias e cria as polilinhas; devolve (novas linhas-unidas)
(defun cn:monta (dados enames lig / livres visit novas ligadas compr e i x p pecas)
  (setq novas 0 ligadas 0 compr 0.0 i 0)
  (repeat (length dados)
    ;; começa por uma ponta livre de uma linha ainda não visitada
    (if (and (not (member i visit)) (or (not (assoc (* 2 i) lig)) (not (assoc (1+ (* 2 i)) lig))))
      (progn
        (setq e (if (assoc (* 2 i) lig) (1+ (* 2 i)) (* 2 i)) pecas nil)
        (while e
          (setq visit (cons (/ e 2) visit)
                pecas (cons (list (/ e 2) (= 0 (rem e 2))) pecas)
                x     (if (= 0 (rem e 2)) (1+ e) (1- e))       ; ponta de saída
                e     (cdr (assoc x lig))))
        (if (cdr pecas)
          (progn
            (setq pecas (reverse pecas)
                  p     (cn:une (mapcar '(lambda (pc) (cn:orienta (nth (car pc) dados) (cadr pc)))
                                        pecas)))
            (cn:mk-lw (car p) (cadr p) (caddr (nth (car (car pecas)) dados)))
            (setq novas (1+ novas) ligadas (+ ligadas (length pecas)))
            (if *CN-APAGAR*
              (foreach pc pecas (entdel (nth (car pc) enames))))))))
    (setq i (1+ i)))
  (list novas ligadas)
)

;;; --------------------------------------------------------------------------
;;; Ação
;;; --------------------------------------------------------------------------
(defun cn:executa (/ ss i e d dados enames pontas th0 cands lig r t0 nlig)
  (princ "\nSelecione as linhas para otimizar: ")
  (if (setq ss (ssget '((-4 . "<OR")
                          (0 . "LINE")
                          (-4 . "<AND") (0 . "LWPOLYLINE") (-4 . "<NOT") (-4 . "&") (70 . 1) (-4 . "NOT>") (-4 . "AND>")
                        (-4 . "OR>"))))
    (progn
      (setq t0 (getvar "MILLISECS") i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i))
        (if (setq d (cn:dados e))
          (setq dados (cons d dados) enames (cons e enames))))
      (setq dados (reverse dados) enames (reverse enames))
      (if (cdr dados)
        (progn
          (setq pontas (cn:pontas dados)
                th0    (cn:dominante dados)
                cands  (cn:candidatos pontas th0 (* pi (/ *CN-ANG* 180.0)) (/ *CN-ESP* 2.0) *CN-DMAX*)
                lig    (cn:casa cands (length dados))
                nlig   (/ (length lig) 2)
                r      (cn:monta dados enames lig))
          (princ (strcat "\n" (itoa (length dados)) " linha(s) analisada(s): "
                         (itoa nlig) " ligação(ões) = " (itoa nlig) " manobra(s) a menos; "
                         (itoa (cadr r)) " linha(s) unida(s) em " (itoa (car r)) " polilinha(s)"
                         (if *CN-APAGAR* "" " (originais mantidas)") "."
                         " [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]")))
        (princ "\nSelecione pelo menos duas linhas."))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun cn:pasta ()
  (cond (*LISPS-DIR*)
        ((findfile "ConectaLinhas.dcl") (vl-filename-directory (findfile "ConectaLinhas.dcl"))))
)

(defun cn:num (s / v) (if s (setq v (distof (vl-string-translate "," "." s) 2))) v)

(defun cn:le-tiles (/ a s m)
  (setq a (cn:num (get_tile "ang")) s (cn:num (get_tile "esp")) m (cn:num (get_tile "dmax")))
  (cond
    ((not (and a (< 0.0 a 90.0))) (set_tile "status" "Ângulo máximo inválido (0 a 90°).") nil)
    ((not (and s (> s 0.0)))      (set_tile "status" "Espaçamento inválido (> 0).") nil)
    ((not (and m (> m 0.0)))      (set_tile "status" "Distância máxima inválida (> 0).") nil)
    (T (setq *CN-ANG* a *CN-ESP* s *CN-DMAX* m *CN-APAGAR* (= "1" (get_tile "apagar")))
       (cn:grava-env)
       T))
)

(defun c:CONECTALINHAS (/ *error* doc dcl arq r)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*"))
      (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (setq arq (if (cn:pasta) (strcat (cn:pasta) "\\ConectaLinhas.dcl")))
  (if (not (and arq (findfile arq)))
    (progn (alert "Arquivo ConectaLinhas.dcl não encontrado.") (exit)))
  (setq dcl (load_dialog arq))
  (if (not (new_dialog "conectalinhas" dcl))
    (progn (alert "Erro ao abrir o diálogo.") (exit)))
  (set_tile "ang"    (rtos *CN-ANG* 2 2))
  (set_tile "esp"    (rtos *CN-ESP* 2 3))
  (set_tile "dmax"   (rtos *CN-DMAX* 2 2))
  (set_tile "apagar" (if *CN-APAGAR* "1" "0"))
  (action_tile "sel"    "(if (cn:le-tiles) (done_dialog 1))")
  (action_tile "cancel" "(done_dialog 0)")
  (setq r (start_dialog))
  (unload_dialog dcl)
  (setq dcl nil)
  (if (= r 1)
    (progn
      (vla-StartUndoMark doc)
      (cn:executa)
      (vla-EndUndoMark doc)))
  (princ)
)

(princ "\nConectaLinhas carregado. Comando: CONECTALINHAS")
(princ)
