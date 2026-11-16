;;; ==========================================================================
;;; ImpComum.lsp - Biblioteca comum dos importadores (KML/KMZ, GeoJSON, SHP)
;;; --------------------------------------------------------------------------
;;; Cada formato (ImpKML.lsp, ImpGeoJSON.lsp, ImpSHP.lsp) só LÊ o arquivo e
;;; devolve as feições num formato comum; esta biblioteca faz o resto:
;;;
;;;   feição = (geoms props)
;;;     geoms : ((tipo pts) ...)  tipo PT (ponto), LN (linha), AN (anel fechado)
;;;     props : (("campo" . valor) ...)  valor = string, número ou nil
;;;   leitor -> (feições campos epsg-origem info)
;;;     campos: (("nome" tipo) ...) tipo "Character" "Real" "Integer" ou nil
;;;             (nil = deduzido dos valores)
;;;
;;; Diálogo único: sistema de origem e do desenho (conversão pelo Map 3D,
;;; ade_projptforward; sem o Map, fórmulas próprias UTM/geográfico WGS 84 -
;;; SIRGAS 2000, diferença < 1 m), camada fixa ou uma camada por valor de um
;;; campo, atributos em Object Data do Map (como o AgroCAD) ou XDATA
;;; (app LISPS_ATRIB), rótulo com o valor de um campo, uso da cota Z.
;;;
;;; Entidades: ponto -> POINT; linha -> LWPOLYLINE (POLYLINE 3D se usar Z e a
;;; cota variar); polígono -> uma polilinha fechada por anel (furos também).
;;; Tudo com entmake, num UNDO único.
;;; ==========================================================================

(vl-load-com)

(setq *IC-APP* "LISPS_ATRIB")

;;; --------------------------------------------------------------------------
;;; Parâmetros (persistem via setenv)
;;; --------------------------------------------------------------------------
(setq *IC-CHAVES* '(*IC-ATRIB* *IC-PORCAMPO* *IC-CAMPOCAM* *IC-ROTULO* *IC-CAMPOROT*
                    *IC-ALTURA* *IC-USAZ* *IC-REPROJ* *IC-PASTA*))
(defun ic:le-env (/ v)
  (setq *IC-ATRIB* "od" *IC-PORCAMPO* nil *IC-CAMPOCAM* "" *IC-ROTULO* nil *IC-CAMPOROT* ""
        *IC-ALTURA* 2.0 *IC-USAZ* nil *IC-REPROJ* T *IC-PASTA* "")
  (if (and (setq v (getenv "LISPS_IMPORTAR"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= (length v) (length *IC-CHAVES*)) (= 'STR (type (car v))) (numberp (nth 5 v)))
    (mapcar 'set *IC-CHAVES* v))
)
(defun ic:grava-env () (setenv "LISPS_IMPORTAR" (vl-prin1-to-string (mapcar 'eval *IC-CHAVES*))))
(if (not *IC-ATRIB*) (ic:le-env))

;;; --------------------------------------------------------------------------
;;; Utilidades
;;; --------------------------------------------------------------------------
(defun ic:pasta ()
  (cond (*FT-DEV-DIR*)
        ((findfile "Importar.dcl") (vl-filename-directory (findfile "Importar.dcl"))))
)
(defun ic:corta (s n) (if (> (strlen s) n) (substr s 1 n) s))
(defun ic:num-tile (k / s) (setq s (get_tile k)) (if s (distof (vl-string-translate "," "." s) 2)))
(defun ic:epsg-num (s) (if (and (= 'STR (type s)) (wcmatch s "#*") (not (wcmatch s "*[~0-9]*"))) (atoi s)))

;;; número -> texto sem notação científica nem zeros sobrando
(defun ic:num->txt (v / s dz)
  (cond
    ((= 'INT (type v)) (itoa v))
    ((and (= v (fix v)) (< (abs v) 1e15)) (rtos v 2 0))
    (T (setq dz (getvar "DIMZIN"))
       (setvar "DIMZIN" 8)                                     ; sem zeros à direita
       (setq s (rtos v 2 10))
       (setvar "DIMZIN" dz)
       s))
)
(defun ic:texto (v)
  (cond ((null v) "") ((= 'STR (type v)) v) ((numberp v) (ic:num->txt v)) (T (vl-princ-to-string v)))
)

;;; troca os caracteres de c por "_"
(defun ic:troca-chars (s c / r)
  (setq r "")
  (foreach k (vl-string->list s)
    (setq r (strcat r (if (vl-string-position k c) "_" (chr k)))))
  r
)
(defun ic:nome-camada (s)
  (setq s (vl-string-trim " " (ic:troca-chars (ic:corta s 200) "<>/\\\":;?*|,=`")))
  (if (= s "") "IMPORTADO" s)
)
;;; nome de tabela/campo de Object Data: letras, dígitos e "_", começa com letra
(defun ic:nome-od (s n / r)
  (setq r "")
  (foreach k (vl-string->list s)
    (setq r (strcat r (if (or (<= 48 k 57) (<= 65 k 90) (<= 97 k 122) (= k 95)) (chr k) "_"))))
  (if (or (= r "") (<= 48 (ascii r) 57)) (setq r (strcat "F" r)))
  (ic:corta r n)
)

;;; arquivo -> texto (ADODB.Stream; charset "utf-8", "windows-1252" ...)
(defun ic:le-texto (arq charset / st r)
  (setq st (vlax-create-object "ADODB.Stream"))
  (setq r (vl-catch-all-apply
            '(lambda ()
               (vlax-put st 'Type 2)
               (vlax-put st 'Charset charset)
               (vlax-invoke st 'Open)
               (vlax-invoke st 'LoadFromFile arq)
               (vlax-invoke st 'ReadText -1))))
  (vl-catch-all-apply 'vlax-invoke (list st 'Close))
  (vlax-release-object st)
  (if (vl-catch-all-error-p r) nil r)
)
;;; arquivo -> safearray de bytes (ou nil)
(defun ic:le-bytes (arq / st r)
  (setq st (vlax-create-object "ADODB.Stream"))
  (setq r (vl-catch-all-apply
            '(lambda ()
               (vlax-put st 'Type 1)
               (vlax-invoke st 'Open)
               (vlax-invoke st 'LoadFromFile arq)
               (vlax-invoke st 'Read -1))))
  (vl-catch-all-apply 'vlax-invoke (list st 'Close))
  (vlax-release-object st)
  (if (or (vl-catch-all-error-p r) (null r)) nil (vlax-variant-value r))
)

;;; bytes UTF-8 (lista de inteiros) -> string
(defun ic:utf8 (bs / r c n)
  (while bs
    (setq c (car bs) bs (cdr bs))
    (cond
      ((< c 128) (setq r (cons c r)))
      ((and (>= c 192) (< c 224) bs)
       (setq r (cons (+ (* (logand c 31) 64) (logand (car bs) 63)) r) bs (cdr bs)))
      ((and (>= c 224) (< c 240) (cdr bs))
       (setq r (cons (+ (* (logand c 15) 4096) (* (logand (car bs) 63) 64) (logand (cadr bs) 63)) r)
             bs (cddr bs)))
      ((>= c 240) (setq r (cons 63 r) bs (cdddr bs)))            ; fora do BMP -> "?"
      (T (setq r (cons c r)))))                                  ; byte solto: Latin-1
  (vl-list->string (reverse r))
)

;;; --------------------------------------------------------------------------
;;; Sistemas de coordenadas
;;; --------------------------------------------------------------------------
(defun ic:z2 (z) (if (< z 10) (strcat "0" (itoa z)) (itoa z)))
;;; EPSG -> código do Map 3D (o mesmo do SISCOORD)
(defun ic:epsg->map (n)
  (cond
    ((member n '(4326 4674)) "LL84")
    ((<= 31977 n 31985) (strcat "SIRGAS2000.UTM-" (itoa (- n 31960)) "S"))
    ((<= 32701 n 32760) (strcat "UTM84-" (ic:z2 (- n 32700)) "S"))
    ((<= 32601 n 32660) (strcat "UTM84-" (ic:z2 (- n 32600)) "N"))
    ((<= 29177 n 29185) (strcat "SAD69.UTM-" (itoa (- n 29160)) "S"))
    ((<= 29191 n 29195) (strcat "SAD69.UTM-" (itoa (- n 29170)) "S")))       ; 29191 = 21S (códigos novos)
)
;;; código do Map -> EPSG
(defun ic:map->epsg (c / z suf)
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
(defun ic:codigo-desenho (/ r)
  (cond
    ((and cs:atual (setq r (vl-catch-all-apply 'cs:atual nil)) (not (vl-catch-all-error-p r)) r) r)
    ((and (= 'EXRXSUBR (type ade_projgetwscode))
          (setq r (vl-catch-all-apply 'ade_projgetwscode nil))
          (not (vl-catch-all-error-p r)) (= 'STR (type r)) (/= r "")) r))
)
;;; WKT (.prj) -> EPSG: AUTHORITY externo, senão pelo nome
(defun ic:wkt->epsg (w / u i z n)
  (if w
    (progn
      (setq u (strcase w))
      (if (and (setq i (vl-string-search "AUTHORITY[\"EPSG\",\"" u (max 0 (- (strlen u) 40))))
               (> (setq n (atoi (substr u (+ i 19)))) 0))
        n
        (progn
          (if (setq i (vl-string-search "ZONE_" (vl-string-translate " " "_" u)))
            (setq z (atoi (substr u (+ i 6) 2))
                  z (if (and (> z 0) (wcmatch (substr u (+ i 6) 3) "##S,#S*")) z
                      (if (> z 0) (- z) nil))))                    ; negativo = norte
          (cond
            ((and z (> z 0) (wcmatch u "*SIRGAS*")) (+ 31960 z))
            ((and z (> z 0) (wcmatch u "*SAD*69*,*SAD_1969*")) (+ 29160 z))
            ((and z (> z 0) (wcmatch u "*WGS*84*,*WGS_1984*")) (+ 32700 z))
            ((and z (< z 0) (wcmatch u "*WGS*84*,*WGS_1984*")) (- 32600 z))
            ((and (not (wcmatch u "PROJCS*")) (wcmatch u "*SIRGAS*")) 4674)
            ((and (not (wcmatch u "PROJCS*")) (wcmatch u "*WGS*84*,*WGS_1984*")) 4326))))))
)
(defun ic:geografico-p (n) (member n '(4326 4674)))

;;; Transversa de Mercator (WGS 84 ~ GRS 80) - usada quando não há o Map 3D
(setq *IC-A* 6378137.0 *IC-F* (/ 1.0 298.257223563) *IC-K0* 0.9996)
(defun ic:tm-zona (n)
  (cond ((<= 31977 n 31985) (list (- n 31960) T))
        ((<= 32701 n 32760) (list (- n 32700) T))
        ((<= 32601 n 32660) (list (- n 32600) nil)))
)
(defun ic:tan (x) (/ (sin x) (cos x)))
;;; (lon lat) graus -> (x y)
(defun ic:tm-fwd (lon lat zona sul / e2 ep2 phi lam0 N TT C A M s c)
  (setq e2  (* *IC-F* (- 2.0 *IC-F*)) ep2 (/ e2 (- 1.0 e2))
        phi (* lat (/ pi 180.0)) lam0 (* (- (* zona 6.0) 183.0) (/ pi 180.0))
        s (sin phi) c (cos phi)
        N (/ *IC-A* (sqrt (- 1.0 (* e2 s s))))
        TT (* (ic:tan phi) (ic:tan phi)) C (* ep2 c c)
        A (* c (- (* lon (/ pi 180.0)) lam0))
        M (* *IC-A* (+ (* (- 1.0 (/ e2 4.0) (/ (* 3.0 e2 e2) 64.0) (/ (* 5.0 e2 e2 e2) 256.0)) phi)
                       (- (* (+ (/ (* 3.0 e2) 8.0) (/ (* 3.0 e2 e2) 32.0) (/ (* 45.0 e2 e2 e2) 1024.0)) (sin (* 2.0 phi))))
                       (* (+ (/ (* 15.0 e2 e2) 256.0) (/ (* 45.0 e2 e2 e2) 1024.0)) (sin (* 4.0 phi)))
                       (- (* (/ (* 35.0 e2 e2 e2) 3072.0) (sin (* 6.0 phi)))))))
  (list (+ 500000.0 (* *IC-K0* N (+ A (/ (* (+ (- 1.0 TT) C) A A A) 6.0)
                                    (/ (* (+ 5.0 (* -18.0 TT) (* TT TT) (* 72.0 C) (* -58.0 ep2)) A A A A A) 120.0))))
        (+ (if sul 10000000.0 0.0)
           (* *IC-K0* (+ M (* N (ic:tan phi)
                              (+ (/ (* A A) 2.0)
                                 (/ (* (+ 5.0 (- TT) (* 9.0 C) (* 4.0 C C)) A A A A) 24.0)
                                 (/ (* (+ 61.0 (* -58.0 TT) (* TT TT) (* 600.0 C) (* -330.0 ep2)) A A A A A A) 720.0)))))))
)
;;; (x y) -> (lon lat) graus
(defun ic:tm-inv (x y zona sul / e2 ep2 e1 M mu phi1 s c C1 T1 N1 R1 D lam0)
  (setq e2  (* *IC-F* (- 2.0 *IC-F*)) ep2 (/ e2 (- 1.0 e2))
        e1  (/ (- 1.0 (sqrt (- 1.0 e2))) (+ 1.0 (sqrt (- 1.0 e2))))
        M   (/ (- y (if sul 10000000.0 0.0)) *IC-K0*)
        mu  (/ M (* *IC-A* (- 1.0 (/ e2 4.0) (/ (* 3.0 e2 e2) 64.0) (/ (* 5.0 e2 e2 e2) 256.0))))
        phi1 (+ mu (* (- (/ (* 3.0 e1) 2.0) (/ (* 27.0 e1 e1 e1) 32.0)) (sin (* 2.0 mu)))
                (* (- (/ (* 21.0 e1 e1) 16.0) (/ (* 55.0 e1 e1 e1 e1) 32.0)) (sin (* 4.0 mu)))
                (* (/ (* 151.0 e1 e1 e1) 96.0) (sin (* 6.0 mu)))
                (* (/ (* 1097.0 e1 e1 e1 e1) 512.0) (sin (* 8.0 mu))))
        s (sin phi1) c (cos phi1)
        C1 (* ep2 c c) T1 (* (ic:tan phi1) (ic:tan phi1))
        N1 (/ *IC-A* (sqrt (- 1.0 (* e2 s s))))
        R1 (/ (* *IC-A* (- 1.0 e2)) (expt (- 1.0 (* e2 s s)) 1.5))
        D  (/ (- x 500000.0) (* N1 *IC-K0*))
        lam0 (- (* zona 6.0) 183.0))
  (list (+ lam0 (* (/ 180.0 pi)
                   (/ (+ D (- (/ (* (+ 1.0 (* 2.0 T1) C1) D D D) 6.0))
                         (/ (* (+ 5.0 (* -2.0 C1) (* 28.0 T1) (* -3.0 C1 C1) (* 8.0 ep2) (* 24.0 T1 T1)) D D D D D) 120.0))
                      c)))
        (* (/ 180.0 pi)
           (- phi1 (* (/ (* N1 (ic:tan phi1)) R1)
                      (+ (/ (* D D) 2.0)
                         (- (/ (* (+ 5.0 (* 3.0 T1) (* 10.0 C1) (* -4.0 C1 C1) (* -9.0 ep2)) D D D D) 24.0))
                         (/ (* (+ 61.0 (* 90.0 T1) (* 298.0 C1) (* 45.0 T1 T1) (* -252.0 ep2) (* -3.0 C1 C1)) D D D D D D) 720.0))))))
)
(defun ic:tm-suporta (n) (or (ic:geografico-p n) (ic:tm-zona n)))

;;; prepara a conversão src -> dst ; devolve o modo ('ADE 'TM 'NADA) e avisa
(defun ic:prepara-transf (src dst dstcod / sc dc)
  (setq *ic-src* src *ic-dst* dst *ic-modo* 'NADA)
  (cond
    ((or (not *IC-REPROJ*) (not src) (not dst) (= src dst)))
    ((and (= 'EXRXSUBR (type ade_projsetsrc)) (= 'EXRXSUBR (type ade_projptforward))
          (setq sc (ic:epsg->map src))
          (setq dc (if (and dstcod (= (ic:map->epsg dstcod) dst)) dstcod (ic:epsg->map dst)))
          (not (vl-catch-all-error-p (vl-catch-all-apply 'ade_projsetsrc (list sc))))
          (not (vl-catch-all-error-p (vl-catch-all-apply 'ade_projsetdest (list dc)))))
     (setq *ic-modo* 'ADE))
    ((and (ic:tm-suporta src) (ic:tm-suporta dst))
     (setq *ic-modo* 'TM))
    (T (princ (strcat "\nAviso: sem conversão de EPSG " (itoa src) " para " (itoa dst)
                      " (Map 3D indisponível e fórmula própria não cobre). Coordenadas originais."))))
  *ic-modo*
)
;;; ponto -> ponto no sistema do desenho (z preservado)
(defun ic:tp (p / q g z)
  (setq z (if (caddr p) (caddr p) 0.0))
  (cond
    ((eq *ic-modo* 'ADE)
     (setq q (vl-catch-all-apply 'ade_projptforward (list (list (car p) (cadr p) z))))
     (if (or (vl-catch-all-error-p q) (not q)) (list (car p) (cadr p) z) (list (car q) (cadr q) z)))
    ((eq *ic-modo* 'TM)
     (setq g (if (ic:geografico-p *ic-src*)
               (list (car p) (cadr p))
               (apply 'ic:tm-inv (append (list (car p) (cadr p)) (ic:tm-zona *ic-src*)))))
     (setq q (if (ic:geografico-p *ic-dst*)
               g
               (apply 'ic:tm-fwd (append g (ic:tm-zona *ic-dst*)))))
     (list (car q) (cadr q) z))
    (T (list (car p) (cadr p) z)))
)

;;; --------------------------------------------------------------------------
;;; Campos e atributos
;;; --------------------------------------------------------------------------
;;; deduz o tipo dos campos sem tipo: todos números inteiros -> Integer,
;;; todos números -> Real, senão Character
(defun ic:deduz-tipos (feats campos / tipo vals)
  (mapcar
    '(lambda (c)
       (if (cadr c)
         c
         (progn
           (setq vals (vl-remove nil (mapcar '(lambda (f) (cdr (assoc (car c) (cadr f)))) feats)))
           (list (car c)
                 (cond ((null vals) "Character")
                       ((not (vl-every 'numberp vals)) "Character")
                       ((vl-every '(lambda (v) (and (= v (fix v)) (< (abs v) 2147483647.0))) vals) "Integer")
                       (T "Real"))))))
    campos)
)
;;; ((nome tipo)) -> ((nome nome-od tipo)) com nomes de OD únicos
(defun ic:campos-od (campos / usados n base r)
  (mapcar '(lambda (c)
             (setq base (ic:nome-od (car c) 28) n base r 1)
             (while (member (strcase n) usados) (setq r (1+ r) n (strcat (ic:corta base 25) "_" (itoa r))))
             (setq usados (cons (strcase n) usados))
             (list (car c) n (cadr c)))
          campos)
)
(defun ic:od-ok ()
  (and (= 'EXRXSUBR (type ade_oddefinetab)) (= 'EXRXSUBR (type ade_odaddrecord))
       (= 'EXRXSUBR (type ade_odsetfield)) (= 'EXRXSUBR (type ade_odnewrecord))
       (= 'EXRXSUBR (type ade_odtablelist)))
)
(defun ic:od-tabelas (/ r) (setq r (vl-catch-all-apply 'ade_odtablelist nil)) (if (vl-catch-all-error-p r) nil (mapcar 'strcase r)))
(defun ic:od-colunas (nome / d c)
  (setq d (vl-catch-all-apply 'ade_odtabledefn (list nome)))
  (if (and (not (vl-catch-all-error-p d)) (setq c (cdr (assoc "columns" d))))
    (mapcar '(lambda (x) (strcase (cdr (assoc "colname" x)))) c))
)
(defun ic:od-padrao (tp) (cond ((= tp "Real") 0.0) ((= tp "Integer") 0) (T "")))
;;; cria (ou reaproveita, se tiver os mesmos campos) a tabela; -> nome ou nil
(defun ic:od-tabela (base cods / nome raiz n tabs)
  (setq tabs (ic:od-tabelas) raiz (ic:nome-od base 25) nome raiz n 1)
  (while (and (member (strcase nome) tabs)
              (not (equal (ic:od-colunas nome) (mapcar '(lambda (c) (strcase (cadr c))) cods))))
    (setq n (1+ n) nome (strcat raiz "_" (itoa n))))
  (if (not (member (strcase nome) tabs))
    (vl-catch-all-apply 'ade_oddefinetab
      (list (list (cons "tablename" nome)
                  (cons "tabledesc" (ic:corta (strcat "Importado de " base) 120))
                  (cons "columns"
                        (mapcar '(lambda (c) (list (cons "colname" (cadr c))
                                                   (cons "coldesc" (ic:corta (car c) 120))
                                                   (cons "coltype" (caddr c))
                                                   (cons "defaultval" (ic:od-padrao (caddr c)))))
                                cods))))))
  (if (member (strcase nome) (ic:od-tabelas)) nome)
)
(defun ic:od-valor (v tp)
  (cond
    ((= tp "Real") (cond ((numberp v) (float v)) ((distof (ic:texto v) 2)) (T 0.0)))
    ((= tp "Integer") (cond ((numberp v) (fix v)) ((distof (ic:texto v) 2) (fix (distof (ic:texto v) 2))) (T 0)))
    (T (ic:corta (ic:texto v) 254)))
)
(defun ic:od-anexa (e tab cods props / rec v ok)
  (setq rec (vl-catch-all-apply 'ade_odnewrecord (list tab)))
  (if (and (not (vl-catch-all-error-p rec))
           (setq ok (vl-catch-all-apply 'ade_odaddrecord (list e tab rec)))
           (not (vl-catch-all-error-p ok)) ok)
    (progn
      (foreach c cods
        (if (setq v (cdr (assoc (car c) props)))
          (vl-catch-all-apply 'ade_odsetfield (list e tab (cadr c) 0 (ic:od-valor v (caddr c))))))
      T))
)
;;; XDATA: (LISPS_ATRIB (1000 . campo) (1000 . valor) ...) até ~15 KB
(defun ic:xd-anexa (e cods props / xd tam s v)
  (setq tam 0)
  (foreach c cods
    (if (setq v (cdr (assoc (car c) props)))
      (progn
        (setq s (ic:corta (ic:texto v) 250) tam (+ tam (strlen (car c)) (strlen s) 8))
        (if (< tam 15000)
          (setq xd (cons (cons 1000 s) (cons (cons 1000 (ic:corta (car c) 250)) xd)))))))
  (if xd (entmod (append (entget e) (list (list -3 (cons *IC-APP* (reverse xd)))))))
)

;;; --------------------------------------------------------------------------
;;; Criação das entidades
;;; --------------------------------------------------------------------------
(defun ic:camada (nome)
  (if (not (tblsearch "LAYER" nome))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 nome) '(70 . 0) '(62 . 7) '(6 . "Continuous"))))
  (if (tblsearch "LAYER" nome) nome "0")
)
(defun ic:mk-ponto (p lay usaz)
  (entmakex (list '(0 . "POINT") (cons 8 lay) (list 10 (car p) (cadr p) (if usaz (caddr p) 0.0))))
)
(defun ic:mk-linha (pts fech lay usaz / z0)
  (setq z0 (caddr (car pts)))
  (if (and usaz (vl-some '(lambda (p) (> (abs (- (caddr p) z0)) 1e-6)) pts))
    (progn
      (entmake (list '(0 . "POLYLINE") '(100 . "AcDbEntity") (cons 8 lay) '(100 . "AcDb3dPolyline")
                     '(66 . 1) '(10 0.0 0.0 0.0) (cons 70 (if fech 9 8))))
      (foreach p pts
        (entmake (list '(0 . "VERTEX") '(100 . "AcDbEntity") (cons 8 lay) '(100 . "AcDbVertex")
                       '(100 . "AcDb3dPolylineVertex") (cons 10 p) '(70 . 32))))
      (if (entmake (list '(0 . "SEQEND") '(100 . "AcDbEntity") (cons 8 lay))) (entlast)))
    (entmakex (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay) '(100 . "AcDbPolyline")
                            (cons 90 (length pts)) (cons 70 (if fech 1 0)) (cons 38 (if usaz z0 0.0)))
                      (mapcar '(lambda (p) (list 10 (car p) (cadr p))) pts))))
)
(defun ic:mk-texto (txt p alt lay)
  (if (/= txt "")
    (entmakex (list '(0 . "TEXT") (cons 8 lay) (list 10 (car p) (cadr p) 0.0) (cons 40 alt)
                    (cons 1 (ic:corta txt 250)))))
)
;;; posição do rótulo: o ponto, o vértice do meio da linha, a média do anel
(defun ic:pos-rotulo (tipo pts / n)
  (setq n (length pts))
  (cond
    ((eq tipo 'LN) (nth (/ n 2) pts))
    ((eq tipo 'AN) (list (/ (apply '+ (mapcar 'car pts)) n) (/ (apply '+ (mapcar 'cadr pts)) n) 0.0))
    (T (car pts)))
)
;;; tira o ponto final repetido do anel e os vértices repetidos em seguida
(defun ic:limpa (pts fech / r)
  (foreach p pts
    (if (not (and r (equal (list (car p) (cadr p)) (list (car (car r)) (cadr (car r))) 1e-9)))
      (setq r (cons p r))))
  (setq r (reverse r))
  (if (and fech (cdr r) (equal (list (car (car r)) (cadr (car r))) (list (car (last r)) (cadr (last r))) 1e-9))
    (setq r (reverse (cdr (reverse r)))))
  r
)

;;; cria tudo -> (n-ents n-pontos n-linhas n-aneis n-atrib n-sem-geom)
(defun ic:cria (feats cods base / lay tab modo e ents np nl na nat nsg pts tipo v usaz)
  (setq usaz *IC-USAZ* np 0 nl 0 na 0 nat 0 nsg 0 modo *IC-ATRIB*)
  (if (and (= modo "od") (not (ic:od-ok)))
    (progn (princ "\nObject Data indisponível (sem Map 3D): atributos em XDATA.") (setq modo "xd")))
  (if (and (= modo "od") cods (not (setq tab (ic:od-tabela base cods))))
    (progn (princ "\nNão foi possível criar a tabela de Object Data: atributos em XDATA.") (setq modo "xd")))
  (if (= modo "xd") (if (not (tblsearch "APPID" *IC-APP*)) (regapp *IC-APP*)))
  (foreach f feats
    (setq lay (ic:camada (ic:nome-camada
                           (if (and *IC-PORCAMPO* (/= *IC-CAMPOCAM* "")
                                    (/= "" (setq v (ic:texto (cdr (assoc *IC-CAMPOCAM* (cadr f)))))))
                             (strcat base "-" v)
                             base)))
          ents nil)
    (if (null (car f)) (setq nsg (1+ nsg)))
    (foreach g (car f)
      (setq e    nil
            tipo (car g)
            pts  (ic:limpa (mapcar 'ic:tp (cadr g)) (eq tipo 'AN)))
      (cond
        ((and (eq tipo 'PT) pts)
         (if (setq e (ic:mk-ponto (car pts) lay usaz)) (setq ents (cons e ents) np (1+ np))))
        ((and (eq tipo 'LN) (cdr pts))
         (if (setq e (ic:mk-linha pts nil lay usaz)) (setq ents (cons e ents) nl (1+ nl))))
        ((and (eq tipo 'AN) (cddr pts))
         (if (setq e (ic:mk-linha pts T lay usaz)) (setq ents (cons e ents) na (1+ na))))
        ((and (eq tipo 'AN) (cdr pts))                          ; anel degenerado -> linha
         (if (setq e (ic:mk-linha pts nil lay usaz)) (setq ents (cons e ents) nl (1+ nl)))))
      (if (and e *IC-ROTULO* (/= *IC-CAMPOROT* "") pts (eq e (car ents)))
        (ic:mk-texto (ic:texto (cdr (assoc *IC-CAMPOROT* (cadr f)))) (ic:pos-rotulo tipo pts) *IC-ALTURA* lay)))
    (if (and ents cods (/= modo "nao"))
      (foreach e ents
        (if (if (= modo "od") (ic:od-anexa e tab cods (cadr f)) (ic:xd-anexa e cods (cadr f)))
          (setq nat (1+ nat))))))
  (list (+ np nl na) np nl na nat nsg (if (= modo "od") tab modo))
)

;;; --------------------------------------------------------------------------
;;; Diálogo
;;; --------------------------------------------------------------------------
(defun ic:lista (k itens sel / i)
  (start_list k)
  (mapcar 'add_list itens)
  (end_list)
  (setq i (vl-position sel itens))
  (set_tile k (itoa (if i i 0)))
)
(defun ic:hab ()
  (mode_tile "campocam" (if (= "1" (get_tile "porcampo")) 0 1))
  (mode_tile "camporot" (if (= "1" (get_tile "rotulo")) 0 1))
  (mode_tile "altura"   (if (= "1" (get_tile "rotulo")) 0 1))
)
(defun ic:ok (nomes / a s d)
  (setq a (ic:num-tile "altura")
        s (vl-string-trim " " (get_tile "src"))
        d (vl-string-trim " " (get_tile "dst")))
  (cond
    ((= "" (vl-string-trim " " (get_tile "camada"))) (set_tile "error" "Informe a camada.") nil)
    ((and (/= s "") (not (ic:epsg-num s))) (set_tile "error" "EPSG de origem inválido.") nil)
    ((and (/= d "") (not (ic:epsg-num d))) (set_tile "error" "EPSG do desenho inválido.") nil)
    ((not (and a (> a 0.0))) (set_tile "error" "Altura do texto inválida.") nil)
    (T (setq *ic-r-src* (ic:epsg-num s) *ic-r-dst* (ic:epsg-num d)
             *ic-r-camada* (vl-string-trim " " (get_tile "camada"))
             *IC-REPROJ*   (= "1" (get_tile "reproj"))
             *IC-PORCAMPO* (and nomes (= "1" (get_tile "porcampo")))
             *IC-CAMPOCAM* (if nomes (nth (atoi (get_tile "campocam")) nomes) "")
             *IC-ROTULO*   (and nomes (= "1" (get_tile "rotulo")))
             *IC-CAMPOROT* (if nomes (nth (atoi (get_tile "camporot")) nomes) "")
             *IC-ATRIB*    (get_tile "atrib")
             *IC-ALTURA*   a
             *IC-USAZ*     (= "1" (get_tile "usaz")))
       (ic:grava-env)
       T))
)
(defun ic:dialogo (titulo info src srcinfo dst dstinfo base nomes / dcl arq r)
  (setq arq (if (ic:pasta) (strcat (ic:pasta) "\\Importar.dcl")))
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo Importar.dcl não encontrado.") (exit)))
  (setq dcl (load_dialog arq))
  (if (not (new_dialog "importar" dcl)) (progn (unload_dialog dcl) (alert "Erro ao abrir o diálogo.") (exit)))
  (set_tile "titulo" titulo)
  (set_tile "info" (ic:corta info 90))
  (set_tile "src" (if src (itoa src) ""))
  (set_tile "srcinfo" srcinfo)
  (set_tile "dst" (if dst (itoa dst) ""))
  (set_tile "dstinfo" dstinfo)
  (set_tile "reproj" (if *IC-REPROJ* "1" "0"))
  (set_tile "camada" base)
  (ic:lista "campocam" nomes *IC-CAMPOCAM*)
  (ic:lista "camporot" nomes *IC-CAMPOROT*)
  (set_tile "porcampo" (if (and nomes *IC-PORCAMPO*) "1" "0"))
  (set_tile "rotulo" (if (and nomes *IC-ROTULO*) "1" "0"))
  (set_tile "altura" (rtos *IC-ALTURA* 2 2))
  (set_tile "atrib" (if (member *IC-ATRIB* '("od" "xd" "nao")) *IC-ATRIB* "od"))
  (set_tile "usaz" (if *IC-USAZ* "1" "0"))
  (if (not nomes) (progn (mode_tile "porcampo" 1) (mode_tile "rotulo" 1)))
  (if (not (ic:od-ok)) (mode_tile "od" 1))
  (ic:hab)
  (action_tile "porcampo" "(ic:hab)")
  (action_tile "rotulo" "(ic:hab)")
  (action_tile "accept" "(if (ic:ok *ic-nomes*) (done_dialog 1))")
  (action_tile "cancel" "(done_dialog 0)")
  (setq r (start_dialog))
  (unload_dialog dcl)
  (= r 1)
)

;;; --------------------------------------------------------------------------
;;; Fluxo comum: escolher arquivo -> ler -> diálogo -> criar (UNDO único)
;;;   leitor: função (arquivo) -> (feições campos epsg-origem info)
;;; --------------------------------------------------------------------------
;;; arquivo nil = pergunta (getfiled); senão usa o arquivo dado (GEOIMPORTAR)
(defun ic:importa (nome ext leitor / arq) (ic:importa-arq nome ext leitor nil))
(defun ic:importa-arq (nome ext leitor arq0 / *error* doc arq t0 r feats campos src info dstcod dst base cods res nt)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vla-EndUndoMark doc)
    (cond (*ic-erro* (princ (strcat "\nFalha ao ler o arquivo: " *ic-erro*)))
          ((not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg))))
    (princ)
  )
  (setq *ic-erro* nil)
  (if (= 0 (getvar "TILEMODE")) (setvar "TILEMODE" 1))
  (if (setq arq (cond (arq0) ((getfiled (strcat "Importar " nome) (if (/= *IC-PASTA* "") (strcat *IC-PASTA* "\\") "") ext 0))))
    (progn
      (setq *IC-PASTA* (vl-filename-directory arq) t0 (getvar "MILLISECS"))
      (princ (strcat "\nLendo " arq "..."))
      (setq r (vl-catch-all-apply leitor (list arq)))
      (cond
        ((vl-catch-all-error-p r)
         (princ (strcat "\nFalha ao ler o arquivo: " (if *ic-erro* *ic-erro* (vl-catch-all-error-message r)))))
        ((null (car r)) (princ (strcat "\nNenhuma feição encontrada." (if (cadddr r) (strcat " " (cadddr r)) ""))))
        (T
         (setq feats  (car r)
               campos (ic:deduz-tipos feats (cadr r))
               src    (caddr r)
               info   (cadddr r)
               dstcod (ic:codigo-desenho)
               dst    (ic:map->epsg dstcod)
               base   (ic:nome-camada (strcase (vl-filename-base arq)))
               *ic-nomes* (mapcar 'car campos))
         (princ (strcat " " (itoa (length feats)) " feição(ões), " (itoa (length campos)) " campo(s)."))
         (if (ic:dialogo (strcat "Importar " nome ": " (vl-filename-base arq) (vl-filename-extension arq))
                         (strcat (itoa (length feats)) " feições, " (itoa (length campos)) " campos. " (if info info ""))
                         src (cond ((not src) "não identificado: informe ou fica sem conversão")
                                   ((ic:epsg->map src) (ic:epsg->map src)) (T ""))
                         dst (cond (dstcod dstcod) (T "desenho sem sistema (SISCOORD)"))
                         base *ic-nomes*)
           (progn
             (setq t0 (getvar "MILLISECS"))
             (ic:prepara-transf *ic-r-src* *ic-r-dst* dstcod)
             (setq cods (if (/= *IC-ATRIB* "nao") (ic:campos-od campos)))
             (vla-StartUndoMark doc)
             (setq res (ic:cria feats cods *ic-r-camada*))
             (vla-EndUndoMark doc)
             (princ (strcat "\n" (itoa (car res)) " entidade(s): " (itoa (nth 1 res)) " ponto(s), "
                            (itoa (nth 2 res)) " linha(s), " (itoa (nth 3 res)) " polígono(s)/anel(éis)"
                            (if (> (nth 5 res) 0) (strcat "; " (itoa (nth 5 res)) " feição(ões) sem geometria") "")
                            "\nAtributos: "
                            (cond ((= *IC-ATRIB* "nao") "não importados")
                                  ((= (nth 6 res) "xd") (strcat "XDATA (" *IC-APP* ") em " (itoa (nth 4 res)) " entidade(s)"))
                                  ((nth 6 res) (strcat "Object Data, tabela " (nth 6 res) ", em " (itoa (nth 4 res)) " entidade(s)"))
                                  (T "nenhum"))
                            "\nCoordenadas: "
                            (cond ((eq *ic-modo* 'ADE) "convertidas pelo Map 3D")
                                  ((eq *ic-modo* 'TM) "convertidas (fórmula UTM própria)")
                                  (T "sem conversão"))
                            " [" (rtos (/ (- (getvar "MILLISECS") t0) 1000.0) 2 2) " s]"))
             (if (and (> (nth 1 res) 0) (= 0 (getvar "PDMODE")))
               (princ "\nDica: PDMODE = 0 deixa os pontos quase invisíveis (use PDMODE 35 / PDSIZE)."))
             (if (> (car res) 0) (vla-ZoomExtents (vlax-get-acad-object)))))))))
  (princ)
)

(princ)
