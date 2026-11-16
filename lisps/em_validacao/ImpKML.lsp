;;; ==========================================================================
;;; ImpKML.lsp - Importar KML / KMZ (Google Earth) com atributos
;;; --------------------------------------------------------------------------
;;; Cada Placemark vira uma feição: Point, LineString, Polygon (anel externo
;;; e furos), LinearRing e MultiGeometry. Atributos: nome, descricao, pasta
;;; (caminho das Folders - serve para "uma camada por valor do campo") e os
;;; campos de ExtendedData (Data e SchemaData/SimpleData).
;;; Sistema: sempre WGS 84 (EPSG 4326), padrão do formato.
;;; KMZ: descompactado numa pasta temporária (Expand-Archive) e lido o
;;; doc.kml (ou o primeiro .kml). Leitura do XML pelo MSXML (Windows).
;;; Depende de ImpComum.lsp.            Comando: IMPKML
;;; ==========================================================================

(vl-load-com)

(defun ik:local (nome / i) (if (setq i (vl-string-position (ascii ":") nome)) (substr nome (+ i 2)) nome))
(defun ik:nome (no) (ik:local (vlax-get no 'nodeName)))
(defun ik:texto (no) (if no (vl-string-trim " \t\n\r" (vlax-get no 'text)) ""))

;;; filhos ELEMENTO (nodeType 1) de no, opcionalmente só os com esse nome
(defun ik:filhos (no nome / l n i r c)
  (setq l (vlax-get no 'childNodes) n (vlax-get l 'length) i 0)
  (while (< i n)
    (setq c (vlax-invoke l 'item i))
    (if (and (= 1 (vlax-get c 'nodeType)) (or (not nome) (= (ik:nome c) nome)))
      (setq r (cons c r)))
    (setq i (1+ i)))
  (reverse r)
)
(defun ik:filho (no nome) (car (ik:filhos no nome)))
;;; todos os descendentes com o nome local dado
(defun ik:desc (no nome / r)
  (foreach c (ik:filhos no nil)
    (if (= (ik:nome c) nome) (setq r (cons c r)))
    (setq r (append (reverse (ik:desc c nome)) r)))
  (reverse r)
)

;;; "lon,lat[,alt] lon,lat ..." -> ((x y z) ...)
(defun ik:coords (s / i j n tok v r)
  (setq s (vl-string-translate "\t\n\r" "   " s) n (strlen s) i 0)
  (while (< i n)
    (while (and (< i n) (= (vl-string-elt s i) 32)) (setq i (1+ i)))
    (if (< i n)
      (progn
        (setq j (cond ((vl-string-position 32 s i)) (T n))
              tok (substr s (1+ i) (- j i))
              v (mapcar 'atof (ik:separa tok ","))
              i j)
        (if (cdr v) (setq r (cons (list (car v) (cadr v) (if (caddr v) (caddr v) 0.0)) r))))))
  (reverse r)
)
(defun ik:separa (s d / i r)
  (while (setq i (vl-string-search d s))
    (setq r (cons (substr s 1 i) r) s (substr s (+ i 1 (strlen d)))))
  (reverse (cons s r))
)

;;; geometrias do Placemark: pelo pai de cada <coordinates>
(defun ik:geoms (pm / pai tp pts r)
  (foreach c (ik:desc pm "coordinates")
    (setq pai (ik:nome (vlax-get c 'parentNode))
          pts (ik:coords (ik:texto c)))
    (cond
      ((null pts))
      ((= pai "Point") (setq r (cons (list 'PT (list (car pts))) r)))
      ((= pai "LineString") (setq r (cons (list 'LN pts) r)))
      ((= pai "LinearRing") (setq r (cons (list 'AN pts) r)))))
  (reverse r)
)

;;; caminho das pastas (Folder) acima do Placemark
(defun ik:pasta (pm / p r)
  (setq p (vlax-get pm 'parentNode))
  (while (and p (= 1 (vlax-get p 'nodeType)) (member (ik:nome p) '("Folder" "Document")))
    (if (= (ik:nome p) "Folder") (setq r (cons (ik:texto (ik:filho p "name")) r)))
    (setq p (vlax-get p 'parentNode)))
  (if r (apply 'strcat (cons (car r) (mapcar '(lambda (s) (strcat "/" s)) (cdr r)))) "")
)

(defun ik:placemark (pm / props nome v)
  (setq props (list (cons "nome" (ik:texto (ik:filho pm "name")))
                    (cons "descricao" (ic:corta (ik:texto (ik:filho pm "description")) 254))
                    (cons "pasta" (ik:pasta pm))))
  (foreach d (ik:desc pm "Data")
    (if (setq nome (vlax-invoke d 'getAttribute "name"))
      (setq props (append props (list (cons nome (ik:valor (ik:texto (ik:filho d "value")))))))))
  (foreach d (ik:desc pm "SimpleData")
    (if (setq nome (vlax-invoke d 'getAttribute "name"))
      (setq props (append props (list (cons nome (ik:valor (ik:texto d))))))))
  (list (ik:geoms pm) props)
)
;;; texto numérico -> número (para o tipo do campo sair Real/Integer)
(defun ik:valor (s)
  (cond ((= s "") nil)
        ((and (wcmatch s "#*,`-#*,.#*,`-.#*") (not (wcmatch s "*[~0-9.eE+`-]*")) (distof s 2)) (distof s 2))
        (T s))
)

(defun ik:aspas (s) (vl-string-subst "''" "'" s))
;;; KMZ -> caminho do .kml extraído
(defun ik:kmz (arq / tmp zip sh l)
  (setq tmp (strcat (getvar "TEMPPREFIX") "lisps_kmz_" (itoa (getvar "MILLISECS")))
        zip (strcat tmp ".zip"))
  (vl-file-copy arq zip)
  (setq sh (vlax-create-object "WScript.Shell"))
  (vl-catch-all-apply 'vlax-invoke
    (list sh 'Run (strcat "powershell -NoProfile -ExecutionPolicy Bypass -Command \"Expand-Archive -LiteralPath '"
                          (ik:aspas zip) "' -DestinationPath '" (ik:aspas tmp) "' -Force\"")
          0 :vlax-true))
  (vlax-release-object sh)
  (vl-file-delete zip)
  (cond ((findfile (strcat tmp "\\doc.kml")))
        ((setq l (vl-directory-files tmp "*.kml" 1)) (strcat tmp "\\" (car l))))
)

(defun ik:le (arq / kml doc ok pms nl n i feats campos)
  (setq kml (if (= (strcase (vl-filename-extension arq)) ".KMZ") (ik:kmz arq) arq))
  (if (not kml) (progn (setq *ic-erro* "KMZ sem arquivo .kml.") (exit)))
  (setq doc (vlax-create-object "MSXML2.DOMDocument.6.0"))
  (vlax-put doc 'async :vlax-false)
  (vlax-put doc 'validateOnParse :vlax-false)
  (vlax-put doc 'resolveExternals :vlax-false)
  (setq ok (vlax-invoke doc 'load kml))
  (if (not (member ok (list :vlax-true T -1)))
    (progn (setq *ic-erro* (strcat "XML inválido: " (vlax-get (vlax-get doc 'parseError) 'reason)))
           (vlax-release-object doc)
           (exit)))
  (setq nl (vlax-invoke doc 'getElementsByTagName "Placemark") n (vlax-get nl 'length) i 0)
  (while (< i n)
    (setq feats (cons (ik:placemark (vlax-invoke nl 'item i)) feats) i (1+ i)))
  (vlax-release-object doc)
  (foreach f feats
    (foreach p (cadr f) (if (not (member (car p) campos)) (setq campos (cons (car p) campos)))))
  (list (reverse feats)
        (mapcar '(lambda (c) (list c (if (member c '("nome" "descricao" "pasta")) "Character"))) (reverse campos))
        4326 (if (/= kml arq) "KMZ (WGS 84)" "KML (WGS 84)"))
)

(defun c:IMPKML ()
  (if (not ic:importa) (load (strcat (if *FT-DEV-DIR* (strcat *FT-DEV-DIR* "\\") "") "ImpComum.lsp")))
  (ic:importa "KML / KMZ" "kml;kmz" 'ik:le)
)

(princ)
