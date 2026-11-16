;;; ==========================================================================
;;; VarSulc.lsp - Sulcação com Espaçamentos Variáveis
;;; --------------------------------------------------------------------------
;;; Recria o fluxo do OFVA ("[NOVO] Offset Variável Avançado") do AgroCAD
;;; (aba AgroCAD > painel Sistematização): cópias paralelas de uma curva de
;;; referência a espaçamentos variáveis, definidos numa tabela
;;; Quantidade x Distância, com predefinições que podem ser salvas/carregadas.
;;;
;;; Otimizações em relação ao original:
;;;   - cada linha é UM offset da referência na distância acumulada (não
;;;     offset de offset): sem acúmulo de erro nem inchaço de vértices;
;;;   - modo "nos talhões": prolonga a referência pelas tangentes, para
;;;     sozinho quando o talhão está coberto e recorta pelo limite;
;;;   - ambos os lados de uma vez, sequência repetível, reordenação;
;;;   - lê os arquivos .OFV do AgroCAD (Config\OFV) como predefinição.
;;;
;;; Depende das rotinas de geometria do CriaLinhas.lsp (cl:*).
;;; Comando: VARSULC
;;; ==========================================================================

(vl-load-com)

(if (and (not cl:clip) *LISPS-DIR* (findfile (strcat *LISPS-DIR* "\\CriaLinhas.lsp")))
  (load (strcat *LISPS-DIR* "\\CriaLinhas.lsp")))

;;; --------------------------------------------------------------------------
;;; Parâmetros
;;; --------------------------------------------------------------------------
(setq *VS-OPC* '(*VS-REP* *VS-LADO* *VS-LAY* *VS-COR* *VS-INCREF*))

(defun vs:defaults ()
  (setq *VS-SEQ*    '((1 3.0 T nil nil)) ; ((qtd dist repetir? layer cor) ...)
                                         ; layer nil = layer padrão
        *VS-REP*    T               ; estado da caixa "Repetir" p/ novas linhas
        *VS-LADO*   "U"             ; "U" um lado (indicar) / "A" ambos
        *VS-LAY*    (if (and (boundp 'NOM_LAY_PLANTIO) (= 'STR (type NOM_LAY_PLANTIO))
                             (snvalid NOM_LAY_PLANTIO))
                      NOM_LAY_PLANTIO
                      "SULCOS MESTRES")
        *VS-COR*    2
        *VS-INCREF* nil)            ; incluir cópia da própria referência
)
(if (not *VS-SEQ*) (vs:defaults))
;; sequência de versão anterior (sem a flag de repetição) na sessão
(setq *VS-SEQ* (mapcar '(lambda (r)
                          (list (car r) (cadr r)
                                (if (cddr r) (caddr r) *VS-REP*)
                                (nth 3 r) (nth 4 r)))
                       *VS-SEQ*))

;;; layer / cor efetivos de uma linha da sequência
(defun vs:r-lay (r) (if (and (nth 3 r) (/= "" (nth 3 r))) (nth 3 r) *VS-LAY*))
(defun vs:r-cor (r) (if (and (nth 3 r) (/= "" (nth 3 r)) (nth 4 r)) (nth 4 r) *VS-COR*))

;;; --------------------------------------------------------------------------
;;; Predefinições (.ofv no mesmo formato do .OFV do AgroCAD):
;;;   quantidade<TAB>distancia<TAB>0 (R)   -> linha repete até o fim
;;;   quantidade<TAB>distancia<TAB>1x      -> linha aplicada uma vez
;;; Colunas extras do LISPS (separadas por TAB): <TAB>layer<TAB>cor
;;; Arquivos antigos sem a 3a coluna usam a opção global gravada no "#".
;;; --------------------------------------------------------------------------
(defun vs:arq-padrao () (strcat (cl:pasta-config) "\\VARSULC_PADRAO.ofv"))

(defun vs:campos (s / r cur c i)
  (setq i 1 cur "")
  (repeat (strlen s)
    (setq c (substr s i 1) i (1+ i))
    (if (member c '("\t" " " ";"))
      (progn (if (/= cur "") (setq r (cons cur r))) (setq cur ""))
      (setq cur (strcat cur c))))
  (if (/= cur "") (setq r (cons cur r)))
  (reverse r)
)

(defun vs:salvar (arq / f)
  (if (setq f (open arq "w"))
    (progn
      (foreach r *VS-SEQ*
        (write-line (strcat (itoa (car r)) "\t" (rtos (cadr r) 2 4) "\t"
                            (if (caddr r) "0 (R)" "1x")
                            (if (and (nth 3 r) (/= "" (nth 3 r)))
                              (strcat "\t" (nth 3 r) "\t" (itoa (vs:r-cor r)))
                              ""))
                    f))
      (write-line (strcat "#" (vl-prin1-to-string (mapcar 'eval *VS-OPC*))) f)
      (close f)
      T))
)

;;; 3a coluna: 'R (repete), 'U (uma vez) ou nil (ausente, arquivo antigo)
(defun vs:flag-rep (campo)
  (cond ((or (null campo) (= "" campo)) nil)
        ((wcmatch (strcase campo) "*R*") 'R)
        (T 'U))
)

;;; divide por TAB (layers podem ter espaço); sem TAB, divide por espaço
(defun vs:split-tab (s / r p)
  (if (vl-string-search "\t" s)
    (progn
      (while (setq p (vl-string-search "\t" s))
        (setq r (cons (vl-string-trim " " (substr s 1 p)) r) s (substr s (+ p 2))))
      (reverse (cons (vl-string-trim " " s) r)))
    (vs:campos s))
)

(defun vs:carregar (arq / f l c d seq opc lay cor)
  (if (and arq (findfile arq) (setq f (open arq "r")))
    (progn
      (while (setq l (read-line f))
        (cond
          ((= (substr l 1 1) "#")
           (setq opc (vl-catch-all-apply 'read (list (substr l 2)))))
          ((and (setq c (vs:split-tab l)) (cdr c)
                (> (atoi (car c)) 0)
                (setq d (cl:num (cadr c))) (> d 0))
           (setq lay (nth 3 c)
                 cor (if (nth 4 c) (atoi (nth 4 c))))
           (if (not (and lay (snvalid lay))) (setq lay nil cor nil))
           (if (and cor (not (< 0 cor 256))) (setq cor nil))
           (setq seq (cons (list (atoi (car c)) d (vs:flag-rep (caddr c)) lay cor) seq)))))
      (close f)
      (if seq
        (progn
          (if (and (listp opc) (= (length opc) (length *VS-OPC*)))
            (mapcar 'set *VS-OPC* opc))
          ;; linhas sem 3a coluna herdam a opção global antiga
          (setq *VS-SEQ*
                (mapcar '(lambda (r)
                           (list (car r) (cadr r)
                                 (cond ((eq (caddr r) 'R) T)
                                       ((eq (caddr r) 'U) nil)
                                       (T *VS-REP*))
                                 (nth 3 r) (nth 4 r)))
                        (reverse seq)))
          T))))
)

;;; --------------------------------------------------------------------------
;;; Distâncias acumuladas da sequência, até o limite lim (nil = sem limite)
;;; Linhas "1x" são aplicadas uma vez, na ordem. Ao chegar numa linha (R),
;;; ela e as linhas (R) seguidas formam um ciclo repetido até o limite;
;;; o que vier depois desse bloco não é alcançado.
;;; --------------------------------------------------------------------------
(defun vs:tem-rep () (vl-some 'caddr *VS-SEQ*))

;;; bloco (R) que começa no início de rows
(defun vs:bloco-rep (rows / b)
  (while (and rows (caddr (car rows)))
    (setq b (cons (car rows) b) rows (cdr rows)))
  (reverse b)
)

(defun vs:distancias (lim / d n res go rows bloco passo)
  (setq d 0.0 n 0 go T rows *VS-SEQ*)
  (if (not lim) (setq lim 1e99))
  ;; soma uma linha da tabela (q copias de dist)
  (defun passo (r)
    (repeat (car r)
      (if go
        (progn
          (setq d (+ d (cadr r)))
          (if (or (> d (+ lim 1e-6)) (>= n 20000))
            (setq go nil)
            (setq res (cons (list d (vs:r-lay r) (vs:r-cor r)) res) n (1+ n)))))))
  (while (and go rows)
    (if (caddr (car rows))
      (progn
        (setq bloco (vs:bloco-rep rows) rows nil)
        (while go
          (foreach r bloco (passo r))
          (if (>= lim 1e98) (setq go nil))))     ; sem limite: um ciclo so
      (progn (passo (car rows)) (setq rows (cdr rows))))
  )
  (reverse res)
)

;;; --------------------------------------------------------------------------
;;; Aplicação  (dists = ((distancia layer cor) ...))
;;; --------------------------------------------------------------------------
(defun vs:garante-layers (dists / feitos)
  (cl:layer *VS-LAY* *VS-COR*)
  (setq feitos (list (strcase *VS-LAY*)))
  (foreach x dists
    (if (not (member (strcase (cadr x)) feitos))
      (progn (cl:layer (cadr x) (caddr x)) (setq feitos (cons (strcase (cadr x)) feitos)))))
)

(defun vs:sel-ref (tipos / ent)
  (while (and (setq ent (entsel "\nSelecione a curva de referência: "))
              (not (member (cdr (assoc 0 (entget (car ent)))) tipos)))
    (princ "\nTipo de curva não suportado.")
  )
  (if ent (car ent))
)

;;; nos talhões: referência prolongada, offsets até cobrir, recorte no limite
(defun vs:aplicar-talhoes (/ talhoes ref ptlado lados bnd poly xs ys ext refo
                             maxd dists linhas tot)
  (if (and (setq talhoes (cl:sel-talhoes))
           (setq ref (vs:sel-ref '("LINE" "LWPOLYLINE" "ARC"))))
    (progn
      (if (= *VS-LADO* "A")
        (setq lados '(1.0 -1.0))
        (setq ptlado (getpoint "\nIndique o lado das linhas: ")))
      (if (or lados ptlado)
        (progn
          (setq tot 0)
          (foreach bnd talhoes
            (setq poly (cl:amostra bnd)
                  xs   (mapcar 'car poly)
                  ys   (mapcar 'cadr poly)
                  ext  (* 1.5 (distance (list (apply 'min xs) (apply 'min ys))
                                        (list (apply 'max xs) (apply 'max ys))))
                  refo (cl:ref-ext ref ext)
                  linhas nil)
            (if ptlado (setq lados (list (cl:sinal refo ptlado))))
            (setq maxd 0.0)
            (foreach p poly
              (setq maxd (max maxd (distance p (cl:2d (vlax-curve-getClosestPointTo refo p))))))
            (setq dists (vs:distancias maxd))
            (vs:garante-layers dists)
            (if *VS-INCREF*
              (setq linhas (cl:clip (vla-Copy refo) bnd poly *VS-LAY*)))
            (foreach d dists
              (foreach s lados
                (foreach o (cl:offset refo (* s (car d)))
                  (setq linhas (append (cl:clip o bnd poly (cadr d)) linhas)))))
            (vla-delete refo)
            (setq tot (+ tot (length linhas)))
          )
          (princ (strcat "\n" (itoa tot) " linha(s) criada(s) em "
                         (itoa (length talhoes)) " talhão(ões)."))
        )
      )
    )
  )
)

;;; sem talhão: offsets da própria referência; com "repetir", até a posição final
(defun vs:aplicar-livre (/ ref o ptlado ptfim lados lim dists n)
  (if (setq ref (vs:sel-ref '("LINE" "LWPOLYLINE" "ARC" "SPLINE" "POLYLINE" "CIRCLE" "ELLIPSE")))
    (progn
      (setq o (vlax-ename->vla-object ref))
      (if (= *VS-LADO* "A")
        (setq lados '(1.0 -1.0))
        (if (setq ptlado (getpoint "\nIndique o lado das linhas: "))
          (setq lados (list (cl:sinal o ptlado)))))
      (if (and lados (vs:tem-rep))
        (if (setq ptfim (getpoint "\nIndique a posição final das linhas: "))
          (setq lim (distance (cl:2d ptfim) (cl:2d (vlax-curve-getClosestPointTo o ptfim T))))
          (setq lados nil)))
      (if lados
        (progn
          (setq dists (vs:distancias lim) n 0)
          (vs:garante-layers dists)
          (if *VS-INCREF*
            (progn (vla-put-Layer (vla-Copy o) *VS-LAY*) (setq n 1)))
          (foreach d dists
            (foreach s lados
              (foreach x (cl:offset o (* s (car d)))
                (vla-put-Layer x (cadr d))
                (setq n (1+ n)))))
          (princ (strcat "\n" (itoa n) " linha(s) criada(s)."))
        )
      )
    )
  )
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun vs:set-nth (i v l / k)
  (setq k -1)
  (mapcar '(lambda (x) (if (= (setq k (1+ k)) i) v x)) l)
)
(defun vs:del-nth (i l / k)
  (setq k -1)
  (vl-remove-if '(lambda (x) (= (setq k (1+ k)) i)) l)
)
(defun vs:troca (i j l / a b)
  (setq a (nth i l) b (nth j l))
  (vs:set-nth j a (vs:set-nth i b l))
)

;;; resumo: linhas fixas (1x) antes do ciclo + largura do ciclo (R)
(defun vs:resumo (/ rows n larg bloco ciclo sobra)
  (setq rows *VS-SEQ* n 0 larg 0.0)
  (while (and rows (not (caddr (car rows))))
    (setq n    (+ n (car (car rows)))
          larg (+ larg (* (car (car rows)) (cadr (car rows))))
          rows (cdr rows)))
  (if rows
    (progn
      (setq bloco (vs:bloco-rep rows) ciclo 0.0
            sobra (- (length rows) (length bloco)))
      (foreach r bloco (setq ciclo (+ ciclo (* (car r) (cadr r)))))
      (set_tile "resumo"
        (strcat (itoa n) " fixa(s) (" (rtos larg 2 2) " m) + ciclo (R) de "
                (rtos ciclo 2 2) " m"
                (if (> sobra 0) (strcat " | " (itoa sobra) " linha(s) após o ciclo ignorada(s)") ""))))
    (set_tile "resumo" (strcat (itoa n) " linha(s), largura total " (rtos larg 2 2) " m")))
)

(defun vs:lista (sel)
  (start_list "lista")
  (foreach r *VS-SEQ*
    (add_list (strcat (itoa (car r)) "\tx\t" (rtos (cadr r) 2 3) " m\t"
                      (if (caddr r) "(R)" "1x") "\t"
                      (if (and (nth 3 r) (/= "" (nth 3 r))) (nth 3 r) "(padrão)"))))
  (end_list)
  (if (and sel *VS-SEQ*)
    (progn
      (setq sel (max 0 (min sel (1- (length *VS-SEQ*)))))
      (set_tile "lista" (itoa sel))
      (vs:mostra sel)))
  (mode_tile "del" (if *VS-SEQ* 0 1))
  (vs:resumo)
)

(defun vs:sel (/ s) (if (/= "" (setq s (get_tile "lista"))) (atoi s)))

(defun vs:mostra (i / r)
  (if (setq r (nth i *VS-SEQ*))
    (progn (set_tile "qtd" (itoa (car r)))
           (set_tile "dist" (rtos (cadr r) 2 4))
           (set_tile "repetir" (if (caddr r) "1" "0"))
           (set_tile "lnlay" (if (nth 3 r) (nth 3 r) ""))
           (set_tile "lncor" (if (and (nth 3 r) (nth 4 r)) (itoa (nth 4 r)) ""))
           (setq *VS-REP* (caddr r))))
)

(defun vs:le-linha (/ q d lay cs cor)
  (setq q   (atoi (get_tile "qtd"))
        d   (cl:num (get_tile "dist"))
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

;;; caixa Repetir: vale na hora para a linha selecionada
(defun vs:acao-rep (v / i r)
  (setq *VS-REP* (= v "1"))
  (if (and (setq i (vs:sel)) (setq r (nth i *VS-SEQ*)))
    (progn
      (setq *VS-SEQ* (vs:set-nth i (list (car r) (cadr r) *VS-REP* (nth 3 r) (nth 4 r)) *VS-SEQ*))
      (vs:lista i)))
)

(defun vs:acao (op / i r)
  (setq i (vs:sel))
  (cond
    ((= op "add")
     (if (setq r (vs:le-linha))
       (progn (setq *VS-SEQ* (append *VS-SEQ* (list r))) (vs:lista (1- (length *VS-SEQ*))))))
    ((not i) (set_tile "status" "Selecione uma linha da sequência."))
    ((= op "alt")
     (if (setq r (vs:le-linha)) (progn (setq *VS-SEQ* (vs:set-nth i r *VS-SEQ*)) (vs:lista i))))
    ((= op "del") (setq *VS-SEQ* (vs:del-nth i *VS-SEQ*)) (vs:lista i))
    ((and (= op "up") (> i 0)) (setq *VS-SEQ* (vs:troca i (1- i) *VS-SEQ*)) (vs:lista (1- i)))
    ((and (= op "down") (< i (1- (length *VS-SEQ*))))
     (setq *VS-SEQ* (vs:troca i (1+ i) *VS-SEQ*)) (vs:lista (1+ i)))
  )
)

(defun vs:preenche ()
  (vs:lista 0)
  (set_tile "repetir" (if *VS-REP* "1" "0"))
  (set_tile "lado"    *VS-LADO*)
  (set_tile "lay"     *VS-LAY*)
  (set_tile "cor"     (itoa *VS-COR*))
  (set_tile "incref"  (if *VS-INCREF* "1" "0"))
)

;;; lê e valida as opções; devolve T se tudo certo
(defun vs:le-tiles (/ cor)
  (setq cor (atoi (get_tile "cor")))
  (cond
    ((null *VS-SEQ*) (set_tile "status" "A sequência de espaçamentos está vazia.") nil)
    ((not (snvalid (get_tile "lay"))) (set_tile "status" "Nome de layer inválido.") nil)
    ((not (< 0 cor 256)) (set_tile "status" "Cor inválida (1-255).") nil)
    (T
     (setq *VS-REP*    (= (get_tile "repetir") "1")
           *VS-LADO*   (get_tile "lado")
           *VS-LAY*    (get_tile "lay")
           *VS-COR*    cor
           *VS-INCREF* (= (get_tile "incref") "1"))
     (set_tile "status" "")
     T)
  )
)

(defun c:VARSULC (/ *error* doc dcl arqdcl r loop arq)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (if dcl (unload_dialog dcl))
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*"))
      (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (if (not cl:clip)
    (progn (alert "CriaLinhas.lsp precisa estar carregado (rotinas de geometria).") (exit)))
  (setq arqdcl (if (cl:pasta-lisps) (strcat (cl:pasta-lisps) "\\VarSulc.dcl")))
  (if (not (and arqdcl (findfile arqdcl)))
    (progn (alert "Arquivo VarSulc.dcl não encontrado.") (exit)))
  (if (not *VS-INIT*)
    (progn (vs:carregar (vs:arq-padrao)) (setq *VS-INIT* T)))

  (setq loop T)
  (while loop
    (setq dcl (load_dialog arqdcl))
    (if (not (new_dialog "varsulc" dcl))
      (progn (alert "Erro ao abrir o diálogo.") (exit)))
    (vs:preenche)
    (action_tile "lista"    "(vs:mostra (atoi $value))")
    (action_tile "repetir"  "(vs:acao-rep $value)")
    (action_tile "add"      "(vs:acao \"add\")")
    (action_tile "alt"      "(vs:acao \"alt\")")
    (action_tile "del"      "(vs:acao \"del\")")
    (action_tile "up"       "(vs:acao \"up\")")
    (action_tile "down"     "(vs:acao \"down\")")
    (action_tile "talhao"   "(if (vs:le-tiles) (done_dialog 2))")
    (action_tile "livre"    "(if (vs:le-tiles) (done_dialog 3))")
    (action_tile "carregar" "(done_dialog 7)")
    (action_tile "salvar"   "(if (vs:le-tiles) (done_dialog 8))")
    (action_tile "padrao"
      "(if (vs:le-tiles) (set_tile \"status\" (if (vs:salvar (vs:arq-padrao)) \"Sequência gravada como padrão.\" \"Não foi possível gravar o padrão.\")))")
    (action_tile "cancel"   "(done_dialog 0)")
    (setq r (start_dialog))
    (unload_dialog dcl)
    (setq dcl nil)
    (cond
      ((member r '(2 3))
       (vla-StartUndoMark doc)
       (if (= r 2) (vs:aplicar-talhoes) (vs:aplicar-livre))
       (vla-EndUndoMark doc)
       (setq loop nil))
      ((= r 7)
       (if (setq arq (getfiled "Carregar sequência (.ofv do LISPS ou do AgroCAD)"
                               (strcat (cl:pasta-config) "\\") "ofv" 0))
         (if (vs:carregar arq)
           (princ (strcat "\nSequência carregada: " arq))
           (alert "Arquivo de sequência inválido."))))
      ((= r 8)
       (if (setq arq (getfiled "Salvar sequência" (strcat (cl:pasta-config) "\\") "ofv" 1))
         (if (vs:salvar arq) (princ (strcat "\nSequência salva: " arq)))))
      (T (setq loop nil))
    )
  )
  (princ)
)

(princ "\nVarSulc carregado. Comando: VARSULC")
(princ)
