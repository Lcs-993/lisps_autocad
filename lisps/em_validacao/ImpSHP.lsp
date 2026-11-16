;;; ==========================================================================
;;; ImpSHP.lsp - Importar Shapefile (.shp + .dbf + .prj + .cpg) com atributos
;;; --------------------------------------------------------------------------
;;; Geometrias: Point, MultiPoint, PolyLine, Polygon e as variantes Z e M
;;; (M é ignorado; Z vira cota se "Usar a cota Z"). Polígono: uma polilinha
;;; fechada por anel (externo e furos).
;;; Atributos: tabela .dbf (C texto, N/F número, D data AAAA-MM-DD, L lógico)
;;; -> Object Data (como o MAPIMPORT/AgroCAD) ou XDATA.
;;; Texto: .cpg (UTF-8 / 1252); sem .cpg, UTF-8 se for válido, senão Latin-1.
;;; Sistema: .prj (AUTHORITY EPSG, ou pelo nome: SIRGAS 2000 / WGS 84 /
;;; SAD 69 UTM, geográfico).
;;; Leitura binária por ADODB.Stream; números IEEE 754 decodificados aqui.
;;; Depende de ImpComum.lsp.            Comando: IMPSHP
;;; ==========================================================================

(vl-load-com)

(defun is:b (buf i) (vlax-safearray-get-element buf i))
(defun is:u16 (buf i) (+ (is:b buf i) (* 256 (is:b buf (1+ i)))))
(defun is:i32le (buf i)
  (fix (+ (is:b buf i) (* 256.0 (is:b buf (+ i 1))) (* 65536.0 (is:b buf (+ i 2)))
          (* 16777216.0 (logand 127 (is:b buf (+ i 3))))))
)
(defun is:i32be (buf i)
  (fix (+ (is:b buf (+ i 3)) (* 256.0 (is:b buf (+ i 2))) (* 65536.0 (is:b buf (+ i 1)))
          (* 16777216.0 (logand 127 (is:b buf i)))))
)
;;; double little-endian (IEEE 754) -> real ; NaN/infinito -> nil
(defun is:f64 (buf i / b6 b7 e m)
  (setq b6 (is:b buf (+ i 6)) b7 (is:b buf (+ i 7))
        e  (+ (* (logand b7 127) 16) (lsh b6 -4))
        m  (+ (* (logand b6 15) 281474976710656.0) (* (is:b buf (+ i 5)) 1099511627776.0)
              (* (is:b buf (+ i 4)) 4294967296.0) (* (is:b buf (+ i 3)) 16777216.0)
              (* (is:b buf (+ i 2)) 65536.0) (* (is:b buf (+ i 1)) 256.0) (is:b buf i)))
  (cond
    ((= e 2047) nil)
    ((= e 0) (* (if (>= b7 128) -1.0 1.0) m (expt 2.0 -1074)))
    (T (* (if (>= b7 128) -1.0 1.0) (+ 1.0 (/ m 4503599627370496.0)) (expt 2.0 (- e 1023)))))
)
(defun is:tam (buf) (1+ (vlax-safearray-get-u-bound buf 1)))

;;; pontos k0..k1-1 a partir de p (16 bytes cada); z a partir de pz (ou nil)
(defun is:pontos (buf p pz k0 k1 / r k z)
  (setq k k0)
  (while (< k k1)
    (setq z (if pz (is:f64 buf (+ pz (* 8 k)))))
    (setq r (cons (list (is:f64 buf (+ p (* 16 k))) (is:f64 buf (+ p (* 16 k) 8)) (if z z 0.0)) r)
          k (1+ k)))
  (reverse r)
)

;;; registro de geometria em c (início do conteúdo) -> geoms
(defun is:geom (buf c / tp np npt partes pp pz k r tipo)
  (setq tp (is:i32le buf c))
  (cond
    ((= tp 0) nil)
    ((member tp '(1 11 21))
     (list (list 'PT (list (list (is:f64 buf (+ c 4)) (is:f64 buf (+ c 12))
                                 (if (= tp 11) (cond ((is:f64 buf (+ c 20))) (0.0)) 0.0))))))
    ((member tp '(8 18 28))
     (setq npt (is:i32le buf (+ c 36)))
     (mapcar '(lambda (p) (list 'PT (list p)))
             (is:pontos buf (+ c 40) (if (= tp 18) (+ c 40 (* 16 npt) 16)) 0 npt)))
    ((member tp '(3 13 23 5 15 25))
     (setq np  (is:i32le buf (+ c 36))
           npt (is:i32le buf (+ c 40))
           pp  (+ c 44 (* 4 np))
           pz  (if (member tp '(13 15)) (+ pp (* 16 npt) 16))
           tipo (if (member tp '(5 15 25)) 'AN 'LN)
           k 0)
     (while (< k np) (setq partes (cons (is:i32le buf (+ c 44 (* 4 k))) partes) k (1+ k)))
     (setq partes (reverse partes))
     (mapcar '(lambda (a b) (list tipo (is:pontos buf pp pz a b)))
             partes (append (cdr partes) (list npt)))))
)

;;; .shp -> lista de geoms (na ordem dos registros)
(defun is:shp (arq / buf fim pos clen r)
  (if (not (setq buf (ic:le-bytes arq))) (progn (setq *ic-erro* "não foi possível ler o .shp.") (exit)))
  (if (or (< (is:tam buf) 100) (/= 9994 (is:i32be buf 0)))
    (progn (setq *ic-erro* "arquivo .shp inválido.") (exit)))
  (setq fim (min (is:tam buf) (* 2 (is:i32be buf 24))) pos 100)
  (while (<= (+ pos 12) fim)
    (setq clen (* 2 (is:i32be buf (+ pos 4)))
          r    (cons (is:geom buf (+ pos 8)) r)
          pos  (+ pos 8 clen)))
  (reverse r)
)

;;; bytes válidos como UTF-8?
(defun is:utf8-p (bs / ok c n)
  (setq ok T)
  (while (and ok bs)
    (setq c (car bs) bs (cdr bs)
          n (cond ((< c 128) 0) ((= (logand c 224) 192) 1) ((= (logand c 240) 224) 2) ((= (logand c 248) 240) 3) (T -1)))
    (if (< n 0) (setq ok nil))
    (repeat (max n 0)
      (if (and bs (= (logand (car bs) 192) 128)) (setq bs (cdr bs)) (setq ok nil))))
  ok
)
(defun is:txt (bs cod)
  (setq bs (vl-remove 0 bs))
  (vl-string-trim " "
    (cond ((not (vl-some '(lambda (c) (> c 127)) bs)) (vl-list->string bs))
          ((or (= cod 'UTF8) (and (null cod) (is:utf8-p bs))) (ic:utf8 bs))
          (T (vl-list->string bs))))
)

;;; .dbf -> (campos registros) ; campos ((nome tipo-dbf tam dec desloc) ...)
(defun is:dbf (arq cod / buf nrec hdr rlen pos off campos nome k regs base bs v i)
  (if (not (setq buf (ic:le-bytes arq))) (progn (setq *ic-erro* "não foi possível ler o .dbf.") (exit)))
  (setq nrec (is:i32le buf 4) hdr (is:u16 buf 8) rlen (is:u16 buf 10) pos 32 off 1)
  (while (and (< pos (1- hdr)) (/= 13 (is:b buf pos)))
    (setq bs nil k 0)
    (while (and (< k 11) (/= 0 (is:b buf (+ pos k)))) (setq bs (cons (is:b buf (+ pos k)) bs) k (1+ k)))
    (setq nome   (is:txt (reverse bs) cod)
          campos (cons (list nome (chr (is:b buf (+ pos 11))) (is:b buf (+ pos 16)) (is:b buf (+ pos 17)) off) campos)
          off    (+ off (is:b buf (+ pos 16)))
          pos    (+ pos 32)))
  (setq campos (reverse campos) i 0)
  (while (and (< i nrec) (<= (+ hdr (* (1+ i) rlen)) (is:tam buf)))
    (setq base (+ hdr (* i rlen)))
    (setq regs (cons (mapcar '(lambda (c / s k bs)
                                (setq k 0 bs nil)
                                (while (< k (caddr c))
                                  (setq bs (cons (is:b buf (+ base (nth 4 c) k)) bs) k (1+ k)))
                                (setq s (is:txt (reverse bs) cod))
                                (cons (car c) (is:valor s (cadr c))))
                             campos)
                     regs)
          i (1+ i)))
  (list campos (reverse regs))
)
(defun is:valor (s tp)
  (cond
    ((= s "") nil)
    ((member tp '("N" "F")) (is:num-dbf s))                  ; "****" (vazio) -> nil
    ((and (= tp "D") (= s "00000000")) nil)
    ((and (= tp "D") (= (strlen s) 8)) (strcat (substr s 1 4) "-" (substr s 5 2) "-" (substr s 7 2)))
    ((= tp "L") (if (wcmatch (strcase s) "T,Y,S") "true" (if (wcmatch (strcase s) "F,N") "false" nil)))
    (T s))
)
;;; número do DBF: "  12.50", "-3", "1.2E+03"; asteriscos/lixo -> nil
(defun is:num-dbf (s / e)
  (cond
    ((wcmatch s "*[~0-9.eE+`- ]*") nil)
    ((setq e (vl-string-position 101 (strcase s T)))
     (if (distof (substr s 1 e) 2)
       (* (distof (substr s 1 e) 2) (expt 10.0 (atoi (vl-string-left-trim "+" (substr s (+ e 2))))))))
    (T (distof s 2)))
)
(defun is:tipo (c)
  (cond ((and (= (cadr c) "N") (= (cadddr c) 0) (< (caddr c) 10)) "Integer")
        ((member (cadr c) '("N" "F")) "Real")
        (T "Character"))
)

(defun is:irmao (arq ext / b f)
  (setq b (strcat (vl-filename-directory arq) "\\" (vl-filename-base arq)))
  (cond ((findfile (strcat b "." ext))) ((findfile (strcat b "." (strcase ext)))))
)

(defun is:le (arq / geoms dbf prj cpg cod tab feats n)
  (setq geoms (is:shp arq)
        cpg   (is:irmao arq "cpg")
        cod   (if cpg (if (wcmatch (strcase (cond ((ic:le-texto cpg "windows-1252")) (""))) "*UTF*8*,*65001*") 'UTF8 'LATIN)))
  (if (setq dbf (is:irmao arq "dbf")) (setq tab (is:dbf dbf cod)))
  (setq prj (is:irmao arq "prj") n 0)
  ;; registro i do .shp <-> registro i do .dbf
  (setq feats (mapcar '(lambda (g / p) (setq p (nth n (cadr tab)) n (1+ n)) (list g p)) geoms))
  (list feats
        (mapcar '(lambda (c) (list (car c) (is:tipo c))) (car tab))
        (if prj (ic:wkt->epsg (ic:le-texto prj "windows-1252")))
        (strcat "Shapefile" (if dbf " + .dbf" " (sem .dbf)") (if prj " + .prj" " (sem .prj)")
                (if cpg (if (eq cod 'UTF8) " + .cpg UTF-8" " + .cpg") "")))
)

(defun c:IMPSHP ()
  (if (not ic:importa) (load (strcat (if *FT-DEV-DIR* (strcat *FT-DEV-DIR* "\\") "") "ImpComum.lsp")))
  (ic:importa "Shapefile" "shp" 'is:le)
)

(princ)
