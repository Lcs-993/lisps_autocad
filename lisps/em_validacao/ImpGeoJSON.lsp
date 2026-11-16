;;; ==========================================================================
;;; ImpGeoJSON.lsp - Importar GeoJSON (.geojson / .json) com atributos
;;; --------------------------------------------------------------------------
;;; FeatureCollection, Feature ou geometria solta; Point, MultiPoint,
;;; LineString, MultiLineString, Polygon (furos), MultiPolygon e
;;; GeometryCollection. "properties" viram atributos (Object Data ou XDATA);
;;; objetos/listas aninhados entram como texto JSON.
;;; Sistema: membro "crs" (urn:ogc:def:crs:EPSG::31983, EPSG:4326, CRS84);
;;; sem ele, WGS 84 (RFC 7946).
;;;
;;; Leitor JSON próprio, por índice no texto (vl-string-elt), sem converter o
;;; arquivo em lista de caracteres. Texto lido em UTF-8 (ADODB.Stream).
;;; Depende de ImpComum.lsp.            Comando: IMPGEOJSON
;;; ==========================================================================

(vl-load-com)

(defun ij:falha (msg) (setq *ic-erro* (strcat "GeoJSON inválido (posição " (itoa *ij-i*) "): " msg)) (exit))
(defun ij:c () (if (< *ij-i* *ij-n*) (vl-string-elt *ij-t* *ij-i*)))
(defun ij:ws ()
  (while (and (< *ij-i* *ij-n*) (member (vl-string-elt *ij-t* *ij-i*) '(32 9 10 13 65279)))
    (setq *ij-i* (1+ *ij-i*)))
)
(defun ij:hex (s / n)
  (setq n 0)
  (foreach c (vl-string->list (strcase s))
    (setq n (+ (* n 16) (cond ((<= 48 c 57) (- c 48)) ((<= 65 c 70) (- c 55)) (T 0)))))
  n
)

(defun ij:valor (/ c)
  (ij:ws)
  (setq c (ij:c))
  (cond
    ((null c) (ij:falha "fim inesperado"))
    ((= c 123) (ij:objeto))
    ((= c 91)  (ij:lista))
    ((= c 34)  (ij:string))
    ((= c 116) (setq *ij-i* (+ *ij-i* 4)) "true")
    ((= c 102) (setq *ij-i* (+ *ij-i* 5)) "false")
    ((= c 110) (setq *ij-i* (+ *ij-i* 4)) nil)
    (T (ij:numero)))
)

(defun ij:string (/ ini j s r c cod)
  (if (/= (ij:c) 34) (ij:falha "texto esperado"))
  (setq ini (1+ *ij-i*)
        j   (vl-string-position 34 *ij-t* ini))
  (if (not j) (ij:falha "texto sem aspas de fechamento"))
  (setq s (substr *ij-t* (1+ ini) (- j ini)))
  (if (not (vl-string-position 92 s))
    (progn (setq *ij-i* (1+ j)) s)                       ; caso comum: sem escapes
    (progn
      (setq *ij-i* ini)
      (while (/= (setq c (vl-string-elt *ij-t* *ij-i*)) 34)
        (if (= c 92)
          (progn
            (setq *ij-i* (1+ *ij-i*) c (vl-string-elt *ij-t* *ij-i*))
            (cond
              ((= c 110) (setq r (cons 10 r)))
              ((= c 116) (setq r (cons 9 r)))
              ((= c 114) (setq r (cons 13 r)))
              ((= c 98)  (setq r (cons 8 r)))
              ((= c 102) (setq r (cons 12 r)))
              ((= c 117)
               (setq cod (ij:hex (substr *ij-t* (+ *ij-i* 2) 4)) *ij-i* (+ *ij-i* 4)
                     r   (cons (if (<= 55296 cod 57343) 63 cod) r)))   ; fora do BMP -> "?"
              (T (setq r (cons c r)))))
          (setq r (cons c r)))
        (setq *ij-i* (1+ *ij-i*))
        (if (>= *ij-i* *ij-n*) (ij:falha "texto sem aspas de fechamento")))
      (setq *ij-i* (1+ *ij-i*))
      (vl-list->string (reverse r))))
)

(defun ij:numero (/ ini c s e)
  (setq ini *ij-i*)
  (while (and (setq c (ij:c)) (or (<= 48 c 57) (member c '(45 43 46 101 69))))
    (setq *ij-i* (1+ *ij-i*)))
  (if (= ini *ij-i*) (ij:falha "valor inválido"))
  (setq s (substr *ij-t* (1+ ini) (- *ij-i* ini)))
  (if (setq e (vl-string-position 101 (strcase s T)))
    (* (atof (substr s 1 e)) (expt 10.0 (atoi (vl-string-left-trim "+" (substr s (+ e 2))))))
    (atof s))
)

(defun ij:objeto (/ r k v)
  (setq *ij-i* (1+ *ij-i*))
  (ij:ws)
  (if (= (ij:c) 125)
    (setq *ij-i* (1+ *ij-i*))
    (while (progn
             (ij:ws)
             (setq k (ij:string))
             (ij:ws)
             (if (/= (ij:c) 58) (ij:falha "':' esperado"))
             (setq *ij-i* (1+ *ij-i*)
                   v (ij:valor)
                   r (cons (cons k v) r))
             (ij:ws)
             (cond ((= (ij:c) 44) (setq *ij-i* (1+ *ij-i*)) T)
                   ((= (ij:c) 125) (setq *ij-i* (1+ *ij-i*)) nil)
                   (T (ij:falha "',' ou '}' esperado"))))))
  (cons 'OBJ (reverse r))
)

(defun ij:lista (/ r)
  (setq *ij-i* (1+ *ij-i*))
  (ij:ws)
  (if (= (ij:c) 93)
    (setq *ij-i* (1+ *ij-i*))
    (while (progn
             (setq r (cons (ij:valor) r))
             (ij:ws)
             (cond ((= (ij:c) 44) (setq *ij-i* (1+ *ij-i*)) T)
                   ((= (ij:c) 93) (setq *ij-i* (1+ *ij-i*)) nil)
                   (T (ij:falha "',' ou ']' esperado"))))))
  (cons 'ARR (reverse r))
)

;;; --------------------------------------------------------------------------
;;; GeoJSON -> feições
;;; --------------------------------------------------------------------------
(defun ij:obj-p (x) (and (listp x) (eq (car x) 'OBJ)))
(defun ij:arr-p (x) (and (listp x) (eq (car x) 'ARR)))
(defun ij:get (o k) (if (ij:obj-p o) (cdr (assoc k (cdr o)))))

;;; valor aninhado -> texto JSON compacto
(defun ij:json (v)
  (cond
    ((null v) "null")
    ((= 'STR (type v)) (strcat "\"" v "\""))
    ((numberp v) (ic:num->txt v))
    ((ij:obj-p v)
     (strcat "{" (ij:junta (mapcar '(lambda (p) (strcat "\"" (car p) "\":" (ij:json (cdr p)))) (cdr v))) "}"))
    ((ij:arr-p v) (strcat "[" (ij:junta (mapcar 'ij:json (cdr v))) "]"))
    (T (vl-princ-to-string v)))
)
(defun ij:junta (l) (if l (apply 'strcat (cons (car l) (mapcar '(lambda (s) (strcat "," s)) (cdr l)))) ""))

(defun ij:pt (a / c)
  (if (and (ij:arr-p a) (numberp (cadr a)) (numberp (caddr a)))
    (progn
      (setq c (cdr a))
      (list (car c) (cadr c) (if (numberp (caddr c)) (caddr c) 0.0))))
)
(defun ij:pts (a) (if (ij:arr-p a) (vl-remove nil (mapcar 'ij:pt (cdr a)))))
(defun ij:aneis (pg) (if (ij:arr-p pg) (mapcar '(lambda (r) (list 'AN (ij:pts r))) (cdr pg))))

(defun ij:geom (g / tp c)
  (setq tp (ij:get g "type") c (ij:get g "coordinates"))
  (cond
    ((= tp "Point") (if (ij:pt c) (list (list 'PT (list (ij:pt c))))))
    ((= tp "MultiPoint") (mapcar '(lambda (p) (list 'PT (list p))) (ij:pts c)))
    ((= tp "LineString") (list (list 'LN (ij:pts c))))
    ((= tp "MultiLineString") (if (ij:arr-p c) (mapcar '(lambda (l) (list 'LN (ij:pts l))) (cdr c))))
    ((= tp "Polygon") (ij:aneis c))
    ((= tp "MultiPolygon") (if (ij:arr-p c) (apply 'append (mapcar 'ij:aneis (cdr c)))))
    ((= tp "GeometryCollection")
     (if (ij:arr-p (ij:get g "geometries")) (apply 'append (mapcar 'ij:geom (cdr (ij:get g "geometries")))))))
)

(defun ij:props (o)
  (if (ij:obj-p o)
    (mapcar '(lambda (p) (cons (car p) (cond ((or (null (cdr p)) (numberp (cdr p)) (= 'STR (type (cdr p)))) (cdr p))
                                             (T (ij:json (cdr p))))))
            (cdr o)))
)

;;; "urn:ogc:def:crs:EPSG::31983" / "EPSG:4326" / "...CRS84" -> EPSG
(defun ij:crs (raiz / nome i)
  (setq nome (ij:get (ij:get (ij:get raiz "crs") "properties") "name"))
  (cond
    ((not (= 'STR (type nome))) 4326)
    ((wcmatch (strcase nome) "*CRS84*") 4326)
    ((setq i (vl-string-position (ascii ":") nome 0 T)) (atoi (substr nome (+ i 2))))
    (T (atoi nome)))
)

(defun ij:le (arq / raiz lista feats campos tp n g)
  (setq *ij-t* (ic:le-texto arq "utf-8"))
  (if (not *ij-t*) (progn (setq *ic-erro* "não foi possível ler o arquivo.") (exit)))
  (setq *ij-n* (strlen *ij-t*) *ij-i* 0
        raiz   (ij:valor)
        *ij-t* nil
        tp     (ij:get raiz "type"))
  (setq lista (cond
                ((= tp "FeatureCollection") (if (ij:arr-p (ij:get raiz "features")) (cdr (ij:get raiz "features"))))
                ((= tp "Feature") (list raiz))
                (T (list (list 'OBJ (cons "type" "Feature") (cons "geometry" raiz))))))
  (foreach f lista
    (setq g (ij:props (ij:get f "properties")))
    (foreach p g (if (not (member (car p) campos)) (setq campos (cons (car p) campos))))
    (setq feats (cons (list (ij:geom (ij:get f "geometry")) g) feats)))
  (list (reverse feats) (mapcar 'list (reverse campos)) (ij:crs raiz)
        (strcat "GeoJSON " (if tp tp "?")))
)

(defun c:IMPGEOJSON ()
  (if (not ic:importa) (load (strcat (if *FT-DEV-DIR* (strcat *FT-DEV-DIR* "\\") "") "ImpComum.lsp")))
  (ic:importa "GeoJSON" "geojson;json" 'ij:le)
)

(princ)
