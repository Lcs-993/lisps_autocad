;;; ==========================================================================
;;; GeoImpExp.lsp - Importação e Exportação Avançada (equivalentes ao
;;;                 GOIMP / GOEXP do AgroCAD)
;;; --------------------------------------------------------------------------
;;; Como o AgroCAD, usa o motor do Map 3D (incluído no Civil 3D): gera um
;;; perfil (.ipf / .epf, o mesmo XML dos perfis em C:\Tecgraf\AgroCAD\Config)
;;; e roda -MAPIMPORT / -MAPEXPORT pela linha de comando:
;;;     formato -> arquivo -> "Load Profile? Yes" -> perfil -> Proceed
;;;
;;; GEOIMPORTAR  (GOIMP)  SHP, KML/KMZ, MIF, TAB, GML, DGN, SDF, SQLite... pelo
;;;   MAPIMPORT; GeoJSON (e qualquer um, se escolhido) pelos leitores próprios
;;;   (ImpGeoJSON / ImpKML / ImpSHP). "Importar Atributos - deseja trazer
;;;   também os dados dos objetos?" -> Object Data. Conversão do sistema do
;;;   arquivo (.prj, KML = LL84) para o do desenho; camada = nome do arquivo
;;;   ou o valor de um campo; polígonos como polilinhas fechadas.
;;;   O nome que liga o Object Data no perfil de importação não é documentado:
;;;   o comando confere se as entidades novas ganharam Object Data e, se não,
;;;   GEOCALIBRA copia os valores de um .ipf salvo no diálogo do MAPIMPORT.
;;; GEOEXPORTAR  (GOEXP)  por camadas ou objetos selecionados:
;;;   SHP / SDF / MIF / GML pelo MAPEXPORT (SHP: um arquivo por tipo de
;;;   geometria - _pontos/_linhas/_poligonos), com os campos de Object Data
;;;   (:CAMPO@TABELA, tipos Character/Integer/Double) e a camada (.LAYER);
;;;   KML e GeoJSON por escritores próprios, em WGS 84, com os mesmos
;;;   atributos (Object Data, XDATA LISPS_ATRIB e camada).
;;; Depende de ImpComum.lsp (sistemas), Simplifica.lsp (arcos) e, para o
;;; motor próprio, ImpKML/ImpGeoJSON/ImpSHP.
;;; Comandos: GEOIMPORTAR, GEOEXPORTAR, GEOCALIBRA
;;; ==========================================================================

(vl-load-com)

(setq *GX-CHAVES* '(*GX-ATRIB* *GX-POLIG* *GX-CONV* *GX-PORCAMPO* *GX-CAMPOCAM* *GX-PASTA*
                    *GX-OD-CRIA* *GX-OD-MAPA* *GX-EXPFMT* *GX-EXPMODO* *GX-EXPCAMADAS*
                    *GX-EXPCRS* *GX-EXPCONV* *GX-EXPATRIB*))
(defun gx:le-env (/ v)
  (setq *GX-ATRIB* T *GX-POLIG* T *GX-CONV* T *GX-PORCAMPO* nil *GX-CAMPOCAM* "" *GX-PASTA* ""
        *GX-OD-CRIA* "NewODTable" *GX-OD-MAPA* "NewObjectDataOnly"
        *GX-EXPFMT* "SHP" *GX-EXPMODO* "cam" *GX-EXPCAMADAS* "" *GX-EXPCRS* "LL84" *GX-EXPCONV* T
        *GX-EXPATRIB* T)
  (if (and (setq v (getenv "LISPS_GEOIMPEXP"))
           (setq v (vl-catch-all-apply 'read (list v)))
           (not (vl-catch-all-error-p v))
           (listp v) (= (length v) (length *GX-CHAVES*)) (= 'STR (type (nth 6 v))))
    (mapcar 'set *GX-CHAVES* v))
)
(defun gx:grava-env () (setenv "LISPS_GEOIMPEXP" (vl-prin1-to-string (mapcar 'eval *GX-CHAVES*))))
(if (not *GX-OD-CRIA*) (gx:le-env))

;;; --------------------------------------------------------------------------
;;; Utilidades
;;; --------------------------------------------------------------------------
(defun gx:pasta ()
  (cond (*FT-DEV-DIR*)
        ((findfile "GeoImpExp.dcl") (vl-filename-directory (findfile "GeoImpExp.dcl"))))
)
(defun gx:requer (/ p)
  (setq p (if (gx:pasta) (strcat (gx:pasta) "\\") ""))
  (foreach x '(("ic:importa-arq" "ImpComum.lsp") ("sp:lw-le" "Simplifica.lsp")
               ("ij:le" "ImpGeoJSON.lsp") ("ik:le" "ImpKML.lsp") ("is:le" "ImpSHP.lsp"))
    (if (and (not (eval (read (car x)))) (findfile (strcat p (cadr x)))) (load (strcat p (cadr x)))))
  (and ic:importa-arq sp:lw-le)
)
(defun gx:map-ok () (and (getcname "-MAPIMPORT") (getcname "-MAPEXPORT")))
(defun gx:xml (s / r)
  (setq r "")
  (foreach c (vl-string->list (if s s ""))
    (setq r (strcat r (cond ((= c 38) "&amp;") ((= c 60) "&lt;") ((= c 62) "&gt;") ((= c 34) "&quot;")
                            ((> c 126) (strcat "&#" (itoa c) ";")) (T (chr c))))))
  r
)
(defun gx:tag (nome valor) (strcat "<" nome ">" (gx:xml valor) "</" nome ">"))
;;; conteúdo da primeira <tag>...</tag> depois de ini
(defun gx:le-tag (txt tag ini / a b)
  (if (and (setq a (vl-string-search (strcat "<" tag ">") txt ini))
           (setq b (vl-string-search (strcat "</" tag ">") txt a)))
    (substr txt (+ a (strlen tag) 3) (- b a (strlen tag) 2)))
)
(defun gx:grava-txt (arq txt / f)
  (if (setq f (open arq "w")) (progn (princ txt f) (close f) arq))
)
(defun gx:temp (nome) (strcat (getvar "TEMPPREFIX") "lisps_" (itoa (getvar "MILLISECS")) "_" nome))
(defun gx:separa (s d / i r)
  (while (setq i (vl-string-search d s))
    (setq r (cons (substr s 1 i) r) s (substr s (+ i 1 (strlen d)))))
  (reverse (cons s r))
)

;;; roda um comando do Map com FILEDIA 0; encerra prompts pendentes
(defun gx:comando (args / fd ce r n)
  (setq fd (getvar "FILEDIA") ce (getvar "CMDECHO"))
  (setvar "FILEDIA" 0)
  (setvar "CMDECHO" 0)
  (setq r (vl-catch-all-apply 'command args) n 0)
  (while (and (> (getvar "CMDACTIVE") 0) (< n 8)) (command "") (setq n (1+ n)))
  (if (> (getvar "CMDACTIVE") 0) (command))
  (setvar "FILEDIA" fd)
  (setvar "CMDECHO" ce)
  (not (vl-catch-all-error-p r))
)

;;; entidades criadas depois de ult (sem subentidades)
(defun gx:novas (ult / e r)
  (setq e (if ult (entnext ult) (entnext)))
  (while e
    (if (not (member (cdr (assoc 0 (entget e))) '("VERTEX" "SEQEND" "ATTRIB"))) (setq r (cons e r)))
    (setq e (entnext e)))
  (reverse r)
)
(defun gx:od-tabelas-de (e / r)
  (if (= 'EXRXSUBR (type ade_odgettables))
    (progn (setq r (vl-catch-all-apply 'ade_odgettables (list e))) (if (vl-catch-all-error-p r) nil r)))
)

;;; --------------------------------------------------------------------------
;;; Formatos
;;; --------------------------------------------------------------------------
;;; extensão -> (código do Map, leitor próprio ou nil)
(setq *GX-FORMATOS*
  '(("SHP" "SHP" is:le) ("KML" "OGCKML" ik:le) ("KMZ" "OGCKML" ik:le) ("MIF" "MIF" nil)
    ("TAB" "MAPINFO" nil) ("GML" "GML" nil) ("DGN" "DGN" nil) ("SDF" "FDO_SDF" nil)
    ("SQLITE" "FDO_SQLITE" nil) ("GPX" "GPX" nil) ("E00" "E00" nil)
    ("GEOJSON" nil ij:le) ("JSON" nil ij:le)))
(defun gx:formato (arq) (assoc (strcase (vl-string-left-trim "." (vl-filename-extension arq))) *GX-FORMATOS*))

;;; campos do .dbf (só o cabeçalho) -> ((nome tipo-dbf tamanho decimais) ...)
(defun gx:campos-dbf (shp / dbf buf pos k bs r)
  (if (and (setq dbf (is:irmao shp "dbf")) (setq buf (ic:le-bytes dbf)))
    (progn
      (setq pos 32)
      (while (and (< pos (- (is:u16 buf 8) 1)) (/= 13 (is:b buf pos)))
        (setq k 0 bs nil)
        (while (and (< k 11) (/= 0 (is:b buf (+ pos k)))) (setq bs (cons (is:b buf (+ pos k)) bs) k (1+ k)))
        (setq r (cons (list (is:txt (reverse bs) nil) (chr (is:b buf (+ pos 11))) (is:b buf (+ pos 16)) (is:b buf (+ pos 17))) r)
              pos (+ pos 32)))))
  (reverse r)
)
;;; colunas do SHP mapeadas para Object Data (como no TAXAS.ipf do AgroCAD):
;;; cria a tabela com os mesmos campos e devolve (tabela ((campo-dbf campo-od) ...))
(defun gx:od-shp (tabela campos / cods tab)
  (setq cods (mapcar '(lambda (c) (list (car c) (ic:nome-od (car c) 31) (is:tipo (list (car c) (cadr c) (caddr c) (cadddr c)))))
                     campos))
  (if (and cods (ic:od-ok) (setq tab (ic:od-tabela tabela cods)))
    (list tab (mapcar '(lambda (c) (list (car c) (cadr c))) cods)))
)
(defun gx:colunas-ipf (tab cols)
  (apply 'strcat
         (mapcar '(lambda (c) (strcat "<ProfileColumn><ColumnMappingType>MappedToOD</ColumnMappingType>"
                                      (gx:tag "ColumnName" (car c)) (gx:tag "OutputColumnName" (cadr c))
                                      (gx:tag "OutputTableName" tab)
                                      "<ClassColumnMappingType>NotMapped</ClassColumnMappingType><OutputClassPropertyName></OutputClassPropertyName></ProfileColumn>"))
                 cols))
)

;;; --------------------------------------------------------------------------
;;; Perfil de importação (.ipf)
;;; --------------------------------------------------------------------------
(setq *GX-KML-CLASSES* '("AnimatedUpdate" "Document" "FlyTo" "Folder" "GroundOverlay" "NetworkLink"
                         "PhotoOverlay" "Placemark" "ScreenOverlay" "SoundCue" "Style" "StyleMap"
                         "Tour" "TourControl" "Wait"))
;;; tabela: nil (sem dados), (tab cols) = colunas mapeadas (SHP, padrão AgroCAD)
;;; ou um nome = tabela nova pelos valores calibrados (outros formatos)
(defun gx:tabela-ipf (nome usar camada indireta dst src tabela / lista)
  (setq lista (and (listp tabela) tabela))
  (strcat "<ProfileTable>" (gx:tag "UniqueName" nome) (gx:tag "UseThisFeature" (if usar "1" "0"))
          "<FeatureClassName></FeatureClassName><ContainsSubtables>0</ContainsSubtables>"
          (gx:tag "LayerName" camada) (gx:tag "LayerNameType" (if indireta "Indirect" "Direct"))
          (gx:tag "NewCoordSysName" dst) (gx:tag "OrigCoordSysName" src)
          (gx:tag "ObjectDataName" (if (= 'STR (type tabela)) tabela ""))
          (gx:tag "CreateObjectData" (if (= 'STR (type tabela)) *GX-OD-CRIA* "NoODTable"))
          (gx:tag "DataMappingType" (if (= 'STR (type tabela)) *GX-OD-MAPA* "ImportMappingInvalid"))
          "<UseUniqueKeyFieldName></UseUniqueKeyFieldName><UseUniqueKeyField>0</UseUniqueKeyField>"
          "<BlockName></BlockName><UseForBlockAttributes>0</UseForBlockAttributes><PointMapping>ToPoint</PointMapping>"
          (if (and lista usar) (gx:colunas-ipf (car lista) (cadr lista)) "")
          "</ProfileTable>")
)
(defun gx:ipf (fmt base camada indireta dst src tabela conv)
  (strcat "<AdMapImportProfile version=\"2.1.2\"><LoadedProfileName></LoadedProfileName>"
          (gx:tag "DoCoordinateConversion" (if conv "1" "0"))
          (gx:tag "ImportPolygonsAsClosedPolylines" (if *GX-POLIG* "1" "0"))
          "<AuditClassifiedAfterImport>1</AuditClassifiedAfterImport>"
          (gx:tag "FormatName" fmt)
          "<DriverOptions/><LocationWindowValues><LocationWindowOption>DontUse</LocationWindowOption></LocationWindowValues>"
          (if (= fmt "OGCKML")
            (apply 'strcat (mapcar '(lambda (c) (gx:tabela-ipf c (= c "Placemark") camada indireta dst src tabela))
                                   *GX-KML-CLASSES*))
            (gx:tabela-ipf (strcat "Default:" base) T camada indireta dst src tabela))
          "</AdMapImportProfile>")
)

;;; --------------------------------------------------------------------------
;;; GEOIMPORTAR
;;; --------------------------------------------------------------------------
(defun gx:ini-imp (arq fm campos dstcod)
  (set_tile "arquivo" (strcat "Arquivo: " arq))
  (set_tile "fmt" (if (cadr fm) (cadr fm) ""))
  (set_tile "motor" (cond ((not (gx:map-ok)) "proprio") ((not (cadr fm)) "proprio") (T "map")))
  (if (not (gx:map-ok)) (mode_tile "map" 1))
  (if (not (caddr fm)) (mode_tile "proprio" 1))
  (set_tile "atrib" (if *GX-ATRIB* "1" "0"))
  (set_tile "tabela" (ic:nome-od (vl-filename-base arq) 25))
  (set_tile "camada" (ic:nome-camada (strcase (vl-filename-base arq))))
  (ic:lista "campocam" campos *GX-CAMPOCAM*)
  (set_tile "porcampo" (if (and campos *GX-PORCAMPO*) "1" "0"))
  (if (not campos) (mode_tile "porcampo" 1))
  (set_tile "src" (if (= (cadr fm) "OGCKML") "LL84" ""))
  (set_tile "dstinfo" (strcat "Sistema do desenho: " (if dstcod dstcod "(nenhum - SISCOORD)")))
  (set_tile "conv" (if (and dstcod *GX-CONV*) "1" "0"))
  (if (not dstcod) (mode_tile "conv" 1))
  (set_tile "polig" (if *GX-POLIG* "1" "0"))
  (gx:hab-imp)
)
(defun gx:hab-imp (/ m)
  (setq m (= (get_tile "motor") "map"))
  (foreach k '("fmt" "tabela" "camada" "porcampo" "campocam" "src" "conv" "polig") (mode_tile k (if m 0 1)))
  (if m (mode_tile "tabela" (if (= "1" (get_tile "atrib")) 0 1)))
  (if (and m (not *gx-campos*)) (progn (mode_tile "porcampo" 1) (mode_tile "campocam" 1)))
  (if (and m *gx-campos*) (mode_tile "campocam" (if (= "1" (get_tile "porcampo")) 0 1)))
)
(defun gx:ok-imp ()
  (cond
    ((and (= (get_tile "motor") "map") (= "" (vl-string-trim " " (get_tile "fmt"))))
     (set_tile "error" "Informe o código do formato do Map (? no -MAPIMPORT lista os códigos).") nil)
    ((and (= (get_tile "motor") "map") (= "" (vl-string-trim " " (get_tile "camada"))))
     (set_tile "error" "Informe a camada.") nil)
    (T (setq *gx-r* (list (get_tile "motor") (strcase (vl-string-trim " " (get_tile "fmt")))
                          (ic:nome-od (vl-string-trim " " (get_tile "tabela")) 25)
                          (ic:nome-camada (vl-string-trim " " (get_tile "camada")))
                          (vl-string-trim " " (get_tile "src")))
             *GX-ATRIB*    (= "1" (get_tile "atrib"))
             *GX-PORCAMPO* (and *gx-campos* (= "1" (get_tile "porcampo")))
             *GX-CAMPOCAM* (if *gx-campos* (nth (atoi (get_tile "campocam")) *gx-campos*) "")
             *GX-CONV*     (= "1" (get_tile "conv"))
             *GX-POLIG*    (= "1" (get_tile "polig")))
       (gx:grava-env)
       T))
)
(defun gx:dialogo (nome ini ok / dcl arq r)
  (setq arq (if (gx:pasta) (strcat (gx:pasta) "\\GeoImpExp.dcl")))
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo GeoImpExp.dcl não encontrado.") (exit)))
  (setq dcl (load_dialog arq))
  (if (not (new_dialog nome dcl)) (progn (unload_dialog dcl) (alert "Erro ao abrir o diálogo.") (exit)))
  (apply (car ini) (cdr ini))
  (action_tile "motor" "(gx:hab-imp)")
  (action_tile "atrib" "(if (= (get_tile \"motor\") \"map\") (gx:hab-imp))")
  (action_tile "porcampo" "(gx:hab-imp)")
  (action_tile "accept" (strcat "(if (" (vl-symbol-name ok) ") (done_dialog 1))"))
  (action_tile "cancel" "(done_dialog 0)")
  (setq r (start_dialog))
  (unload_dialog dcl)
  (= r 1)
)

(defun gx:importa-map (arq fmt tabela camada src dstcod / *error* doc ipf ult novas comod tps txt od)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ)
  )
  ;; SHP: colunas do .dbf mapeadas para uma tabela criada aqui; outros: calibrado
  (setq od (cond ((not *GX-ATRIB*) nil)
                 ((and (= fmt "SHP") *gx-dbf*) (gx:od-shp tabela *gx-dbf*))
                 (T tabela)))
  (if (listp od) (if od (setq tabela (car od))))
  (setq ipf (gx:grava-txt (gx:temp "importar.ipf")
                          (gx:ipf fmt (vl-filename-base arq)
                                  (if *GX-PORCAMPO* *GX-CAMPOCAM* camada) *GX-PORCAMPO*
                                  (if (and *GX-CONV* dstcod) dstcod "") src
                                  od (and *GX-CONV* dstcod)))
        ult (entlast))
  (vla-StartUndoMark doc)
  (princ (strcat "\nMAPIMPORT " fmt ": " arq))
  (gx:comando (list "_-MAPIMPORT" fmt arq "_Yes" ipf "_Proceed"))
  (vla-EndUndoMark doc)
  (setq novas (gx:novas ult))
  (foreach e novas
    (setq txt (cdr (assoc 0 (entget e)))
          tps (if (assoc txt tps) (subst (cons txt (1+ (cdr (assoc txt tps)))) (assoc txt tps) tps) (cons (cons txt 1) tps)))
    (if (gx:od-tabelas-de e) (setq comod (1+ (if comod comod 0)))))
  (cond
    ((null novas)
     (princ (strcat "\nNada foi importado. Rode -MAPIMPORT manualmente para ver os prompts deste formato"
                    " (o código \"" fmt "\" pode ser outro: ? lista os códigos).")))
    (T
     (princ (strcat "\n" (itoa (length novas)) " entidade(s) importada(s): "
                    (apply 'strcat (mapcar '(lambda (x) (strcat (car x) " " (itoa (cdr x)) "  ")) tps))))
     (cond
       ((not *GX-ATRIB*))
       (comod (princ (strcat "\nObject Data em " (itoa comod) " entidade(s) (tabela " tabela ").")))
       ((= fmt "SHP") (princ "\nAs entidades vieram SEM Object Data (colunas MappedToOD não aplicadas). Confira a tabela no Map (ADEDEFDATA) ou use o motor LISPS."))
       (T (princ (strcat "\nAs entidades vieram SEM Object Data: o nome da opção no perfil (\"" *GX-OD-CRIA*
                         "\" / \"" *GX-OD-MAPA* "\") não é o desta versão do Map."
                         "\nUma vez só: rode MAPIMPORT, marque \"Create Object Data\" na coluna Data, salve o perfil"
                         " (.ipf) e rode GEOCALIBRA com ele. Ou use o motor LISPS (leitor próprio)."))))
     (vla-ZoomExtents (vlax-get-acad-object))))
  (vl-file-delete ipf)
)

(defun c:GEOIMPORTAR (/ arq fm dstcod r)
  (if (= 0 (getvar "TILEMODE")) (setvar "TILEMODE" 1))
  (if (and (gx:requer)
           (setq arq (getfiled "Importação Avançada" (if (/= *GX-PASTA* "") (strcat *GX-PASTA* "\\") "")
                               "shp;kml;kmz;geojson;json;mif;tab;gml;dgn;sdf;sqlite;gpx;e00;*" 0)))
    (progn
      (setq *GX-PASTA* (vl-filename-directory arq)
            fm         (cond ((gx:formato arq)) ((list "" "" nil)))
            dstcod     (ic:codigo-desenho)
            *gx-dbf*    (if (= (car fm) "SHP") (gx:campos-dbf arq))
            *gx-campos* (mapcar 'car *gx-dbf*))
      (if (gx:dialogo "gx_importar" (list 'gx:ini-imp arq fm *gx-campos* dstcod) 'gx:ok-imp)
        (if (= (car *gx-r*) "map")
          (gx:importa-map arq (nth 1 *gx-r*) (nth 2 *gx-r*) (nth 3 *gx-r*) (nth 4 *gx-r*) dstcod)
          (progn
            (if (not *GX-ATRIB*) (setq *IC-ATRIB* "nao") (if (= *IC-ATRIB* "nao") (setq *IC-ATRIB* "od")))
            (ic:importa-arq (car fm) (strcase (car fm) T) (caddr fm) arq))))))
  (princ)
)

;;; calibra os nomes do Object Data a partir de um .ipf salvo no MAPIMPORT
(defun c:GEOCALIBRA (/ arq txt i a b)
  (if (setq arq (getfiled "Perfil de importação salvo no MAPIMPORT (com Create Object Data)" "" "ipf" 0))
    (progn
      (setq txt (ic:le-texto arq "utf-8") i 0)
      (while (and txt (setq i (vl-string-search "<CreateObjectData>" txt i))
                  (= "NoODTable" (gx:le-tag txt "CreateObjectData" i)))
        (setq i (1+ i)))
      (if (and i (setq a (gx:le-tag txt "CreateObjectData" i)) (setq b (gx:le-tag txt "DataMappingType" i)))
        (progn (setq *GX-OD-CRIA* a *GX-OD-MAPA* b) (gx:grava-env)
               (princ (strcat "\nCalibrado: CreateObjectData = " a ", DataMappingType = " b)))
        (princ "\nO perfil não tem nenhuma tabela com Object Data ligado (marque Create Object Data e salve de novo)."))))
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Exportação: geometria e atributos das entidades
;;; --------------------------------------------------------------------------
;;; entidade -> (tipo pts) tipo PT / LN / AN, pts no WCS
(defun gx:geom (e / ed tp fech recs z L n k pts)
  (setq ed (entget e) tp (cdr (assoc 0 ed)))
  (cond
    ((member tp '("POINT" "INSERT" "TEXT" "MTEXT")) (list 'PT (list (cdr (assoc 10 ed)))))
    ((= tp "LINE") (list 'LN (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)))))
    ((= tp "LWPOLYLINE")
     (setq fech (= 1 (logand 1 (cdr (assoc 70 ed)))) z (sp:num 38 ed)
           recs (car (sp:segmenta-recs (cadr (sp:lw-le ed)) fech 'FLECHA 0.05)))
     (list (if (and fech *gx-polig*) 'AN 'LN) (mapcar '(lambda (r) (list (car (car r)) (cadr (car r)) z)) recs)))
    ((and (= tp "POLYLINE") (= 0 (logand 86 (cdr (assoc 70 ed)))))
     (setq fech (= 1 (logand 1 (cdr (assoc 70 ed))))
           recs (car (sp:segmenta-recs (sp:pl-le e) fech 'FLECHA 0.05)))
     (list (if (and fech *gx-polig*) 'AN 'LN) (mapcar 'car recs)))
    ((and (member tp '("ARC" "CIRCLE" "SPLINE" "ELLIPSE" "POLYLINE")) (or (/= tp "POLYLINE") (= 0 (logand 80 (cdr (assoc 70 ed))))))
     (setq fech (vlax-curve-isClosed e)
           L (vlax-curve-getDistAtParam e (vlax-curve-getEndParam e))
           n (max 16 (fix (/ L 1.0))) n (min n 2000) k 0)
     (while (<= k (if fech (1- n) n))
       (setq pts (cons (vlax-curve-getPointAtDist e (min L (/ (* L k) n))) pts) k (1+ k)))
     (list (if (and fech *gx-polig*) 'AN 'LN) (reverse pts))))
)
;;; atributos: camada, handle, Object Data (todas as tabelas) e XDATA LISPS_ATRIB
(defun gx:props (e / ed r tabs cols v xd)
  (setq ed (entget e '("LISPS_ATRIB"))
        r  (list (cons "camada" (cdr (assoc 8 ed))) (cons "handle" (cdr (assoc 5 ed)))))
  (foreach t1 (gx:od-tabelas-de e)
    (foreach c (gx:od-cols t1)
      (setq v (vl-catch-all-apply 'ade_odgetfield (list e t1 (car c) 0)))
      (if (not (vl-catch-all-error-p v))
        (setq r (append r (list (cons (if (assoc (car c) r) (strcat t1 "_" (car c)) (car c)) v)))))))
  (if (setq xd (cdr (assoc "LISPS_ATRIB" (cdr (assoc -3 ed)))))
    (while (cdr xd)
      (setq r (append r (list (cons (cdr (car xd)) (cdr (cadr xd))))) xd (cddr xd))))
  r
)
;;; colunas (nome tipo) de uma tabela de Object Data
(defun gx:od-cols (nome / d)
  (setq d (vl-catch-all-apply 'ade_odtabledefn (list nome)))
  (if (and (not (vl-catch-all-error-p d)) (assoc "columns" d))
    (mapcar '(lambda (x) (list (cdr (assoc "colname" x)) (cdr (assoc "coltype" x)))) (cdr (assoc "columns" d))))
)

;;; escritores próprios: KML e GeoJSON (WGS 84)
(defun gx:num (v) (rtos v 2 8))
(defun gx:coords-kml (pts) (apply 'strcat (mapcar '(lambda (p) (strcat (gx:num (car p)) "," (gx:num (cadr p)) ",0 ")) pts)))
(defun gx:json-str (s / r)
  (setq r "")
  (foreach c (vl-string->list s)
    (setq r (strcat r (cond ((= c 34) "\\\"") ((= c 92) "\\\\") ((< c 32) " ")
                            ((> c 126) (strcat "\\u" (gx:hex4 c))) (T (chr c))))))
  (strcat "\"" r "\"")
)
(defun gx:hex4 (n / s d)
  (setq s "")
  (repeat 4 (setq d (rem n 16) s (strcat (substr "0123456789ABCDEF" (1+ d) 1) s) n (/ n 16)))
  s
)
(defun gx:json-val (v) (cond ((null v) "null") ((numberp v) (ic:num->txt v)) (T (gx:json-str (ic:texto v)))))
(defun gx:coords-json (pts) (strcat "[" (gx:junta (mapcar '(lambda (p) (strcat "[" (gx:num (car p)) "," (gx:num (cadr p)) "]")) pts)) "]"))
(defun gx:junta (l) (if l (apply 'strcat (cons (car l) (mapcar '(lambda (s) (strcat "," s)) (cdr l)))) ""))

(defun gx:exporta-texto (ents arq fmt / f g pts props camadas prim n fech)
  (setq n 0 f (open arq "w"))
  (if (= fmt "KML")
    (progn
      (write-line "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" f)
      (write-line (strcat "<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>" (gx:xml (vl-filename-base arq)) "</name>") f)
      (foreach e ents (if (not (member (cdr (assoc 8 (entget e))) camadas)) (setq camadas (cons (cdr (assoc 8 (entget e))) camadas))))
      (foreach c (reverse camadas)
        (write-line (strcat "<Folder><name>" (gx:xml c) "</name>") f)
        (foreach e ents
          (if (and (= c (cdr (assoc 8 (entget e)))) (setq g (gx:geom e)))
            (progn
              (setq pts (mapcar 'ic:tp (cadr g)) props (gx:props e) n (1+ n))
              (write-line (strcat "<Placemark><name>" (gx:xml (strcat c " " (cdr (assoc "handle" props)))) "</name><ExtendedData>"
                                  (apply 'strcat (mapcar '(lambda (p) (strcat "<Data name=\"" (gx:xml (car p)) "\"><value>"
                                                                              (gx:xml (ic:texto (cdr p))) "</value></Data>"))
                                                         props))
                                  "</ExtendedData>"
                                  (cond ((eq (car g) 'PT) (strcat "<Point><coordinates>" (gx:coords-kml pts) "</coordinates></Point>"))
                                        ((eq (car g) 'LN) (strcat "<LineString><tessellate>1</tessellate><coordinates>" (gx:coords-kml pts) "</coordinates></LineString>"))
                                        (T (strcat "<Polygon><outerBoundaryIs><LinearRing><coordinates>"
                                                   (gx:coords-kml (append pts (list (car pts))))
                                                   "</coordinates></LinearRing></outerBoundaryIs></Polygon>")))
                                  "</Placemark>") f))))
        (write-line "</Folder>" f))
      (write-line "</Document></kml>" f))
    (progn
      (write-line "{\"type\":\"FeatureCollection\",\"features\":[" f)
      (setq prim T)
      (foreach e ents
        (if (setq g (gx:geom e))
          (progn
            (setq pts (mapcar 'ic:tp (cadr g)) props (gx:props e) n (1+ n))
            (if (not prim) (write-line "," f))
            (setq prim nil)
            (princ (strcat "{\"type\":\"Feature\",\"properties\":{"
                           (gx:junta (mapcar '(lambda (p) (strcat (gx:json-str (car p)) ":" (gx:json-val (cdr p)))) props))
                           "},\"geometry\":"
                           (cond ((eq (car g) 'PT) (strcat "{\"type\":\"Point\",\"coordinates\":[" (gx:num (car (car pts))) "," (gx:num (cadr (car pts))) "]}"))
                                 ((eq (car g) 'LN) (strcat "{\"type\":\"LineString\",\"coordinates\":" (gx:coords-json pts) "}"))
                                 (T (strcat "{\"type\":\"Polygon\",\"coordinates\":[" (gx:coords-json (append pts (list (car pts)))) "]}")))
                           "}") f))))
      (write-line "" f)
      (write-line "]}" f)))
  (close f)
  n
)

;;; --------------------------------------------------------------------------
;;; Exportação pelo Map (.epf)
;;; --------------------------------------------------------------------------
;;; tipo de geometria do Map para a entidade
(defun gx:tipo-map (e / g) (if (setq g (gx:tipo-rapido e)) g))
(defun gx:tipo-rapido (e / ed tp)
  (setq ed (entget e) tp (cdr (assoc 0 ed)))
  (cond
    ((member tp '("POINT" "INSERT" "TEXT" "MTEXT")) "Point")
    ((member tp '("LINE" "ARC")) "Line")
    ((member tp '("LWPOLYLINE" "POLYLINE" "CIRCLE" "SPLINE" "ELLIPSE"))
     (if (and *gx-polig* (vlax-curve-isClosed e)) "Polygon" "Line"))
    ((member tp '("HATCH" "MPOLYGON")) "Polygon"))
)
;;; nomes de campo do DBF: até 10 caracteres, únicos
(defun gx:nome-dbf (s usados / b n r)
  (setq b (strcase (ic:nome-od s 10)) n b r 1)
  (while (member n usados) (setq r (1+ r) n (strcat (substr b 1 (- 9 (strlen (itoa r)))) "_" (itoa r))))
  n
)
;;; mapeamentos de campos: (nome expressão tipo)
(defun gx:mapeamentos (ents modo / tabs maps usados nome)
  (foreach e ents (foreach t1 (gx:od-tabelas-de e) (if (not (or (member t1 tabs) (= (strcase t1) "LISPS_EXP"))) (setq tabs (cons t1 tabs)))))
  (setq nome (gx:nome-dbf "CAMADA" nil) usados (list nome)
        maps (list (list nome (if (= modo "sel") ":CAMADA@LISPS_EXP" ".LAYER") "CharacterDataType")))
  (foreach t1 (reverse tabs)
    (foreach c (gx:od-cols t1)
      (setq nome (gx:nome-dbf (car c) usados) usados (cons nome usados)
            maps (append maps (list (list nome (strcat ":" (car c) "@" t1)
                                          (cond ((wcmatch (strcase (cadr c)) "INT*") "IntegerDataType")
                                                ((wcmatch (strcase (cadr c)) "REAL*") "DoubleDataType")
                                                (T "CharacterDataType"))))))))
  maps
)
(defun gx:epf (fmt geom camadas maps conv crs)
  (strcat "<AdMapExportProfile version=\"2.1.3\"><LoadedProfileName></LoadedProfileName>"
          "<StorageOptions><StorageType>FileOneEntityType</StorageType>" (gx:tag "GeometryType" geom)
          "<FilePrefix></FilePrefix></StorageOptions>"
          "<SelectionOptions><UseSelectionSet>1</UseSelectionSet><UseAutoSelection>1</UseAutoSelection></SelectionOptions>"
          "<TranslationOptions>" (gx:tag "TreatClosedPolylinesAsPolygons" (if *gx-polig* "1" "0"))
          "<ExplodeBlocks>1</ExplodeBlocks><LayersToLevels><MapLayersToLevels>0</MapLayersToLevels><LayerToLevelMapping/></LayersToLevels></TranslationOptions>"
          "<TopologyOptions><GroupComplexPolygons>0</GroupComplexPolygons><TopologyName></TopologyName></TopologyOptions>"
          "<LayerOptions><DoFilterByLayer>1</DoFilterByLayer>" (gx:tag "LayerList" camadas) "</LayerOptions>"
          "<FeatureClassOptions><DoFilterByFeatureClass>0</DoFilterByFeatureClass><FeatureClassList></FeatureClassList></FeatureClassOptions>"
          "<TableDataOptions><TableDataType>None</TableDataType><Name></Name><SQLKeyOnly>0</SQLKeyOnly></TableDataOptions>"
          "<CoordSysOptions>" (gx:tag "DoCoordinateConversion" (if conv "1" "0")) (gx:tag "CoordSysName" (if conv crs ""))
          "</CoordSysOptions><TargetNameOptions>" (gx:tag "FormatName" fmt) "</TargetNameOptions>"
          (if (= fmt "SHP")
            "<DriverOptions><NameValuePair><Name>FME_ARC_CHORD_DISTANCE</Name><Value>0.0</Value></NameValuePair><NameValuePair><Name>FDO_SHAPE_DIMENSION</Name><Value>2D</Value></NameValuePair></DriverOptions>"
            "<DriverOptions/>")
          "<UseUniqueKeyField>0</UseUniqueKeyField><UseUniqueKeyFieldName>AdMapKey</UseUniqueKeyFieldName>"
          "<ExpressionFieldMappings>"
          (apply 'strcat (mapcar '(lambda (m) (strcat "<NameValuePair>" (gx:tag "Name" (car m)) (gx:tag "Value" (cadr m))
                                                      (gx:tag "Datatype" (caddr m)) "</NameValuePair>"))
                                 maps))
          "</ExpressionFieldMappings></AdMapExportProfile>")
)
(defun gx:apaga-shp (base) (foreach x '(".shp" ".shx" ".dbf" ".prj" ".cpg") (if (findfile (strcat base x)) (vl-file-delete (strcat base x)))))

;;; objetos selecionados: cópias numa camada temporária + Object Data com a camada original
(defun gx:copias (ents / lay copias c tab)
  (setq lay "LISPS_EXPORTA")
  (if (not (tblsearch "LAYER" lay))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                   (cons 2 lay) '(70 . 0) '(62 . 7) '(6 . "Continuous"))))
  (if (and (ic:od-ok) (not (member "LISPS_EXP" (ic:od-tabelas))))
    (vl-catch-all-apply 'ade_oddefinetab
      (list (list '("tablename" . "LISPS_EXP") '("tabledesc" . "Camada original (GEOEXPORTAR)")
                  (list "columns" '(("colname" . "CAMADA") ("coldesc" . "camada") ("coltype" . "character") ("defaultval" . "")))))))
  (foreach e ents
    (setq c (vl-catch-all-apply 'vla-Copy (list (vlax-ename->vla-object e))))
    (if (not (vl-catch-all-error-p c))
      (progn
        (vla-put-Layer c lay)
        (setq c (vlax-vla-object->ename c) copias (cons c copias))
        (if (ic:od-anexa c "LISPS_EXP" '(("CAMADA" "CAMADA" "Character")) (list (cons "CAMADA" (cdr (assoc 8 (entget e))))))
          nil))))
  copias
)

(defun gx:ini-exp ()
  (set_tile "modo" *GX-EXPMODO*)
  (set_tile "camadas" *GX-EXPCAMADAS*)
  (ic:lista "fmt" '("SHP (Map)" "KML" "GeoJSON" "SDF (Map)" "MIF (Map)" "GML (Map)") *gx-fmt-nome*)
  (set_tile "conv" (if *GX-EXPCONV* "1" "0"))
  (set_tile "crs" *GX-EXPCRS*)
  (set_tile "atrib" (if *GX-EXPATRIB* "1" "0"))
  (set_tile "polig" (if *GX-POLIG* "1" "0"))
  (set_tile "dstinfo" (strcat "Sistema do desenho: " (cond ((ic:codigo-desenho)) ("(nenhum - SISCOORD)"))))
  (gx:hab-exp)
)
(defun gx:hab-exp (/ f)
  (setq f (atoi (get_tile "fmt")))
  (mode_tile "camadas" (if (= (get_tile "modo") "cam") 0 1))
  (mode_tile "selcam" (if (= (get_tile "modo") "cam") 0 1))
  (mode_tile "conv" (if (member f '(1 2)) 1 0))
  (mode_tile "crs" (if (or (member f '(1 2)) (= "0" (get_tile "conv"))) 1 0))
)
(defun gx:ok-exp ()
  (setq *GX-EXPMODO* (get_tile "modo")
        *GX-EXPCAMADAS* (strcase (vl-string-trim " " (get_tile "camadas")))
        *GX-EXPFMT* (nth (atoi (get_tile "fmt")) '("SHP" "KML" "GEOJSON" "FDO_SDF" "MIF" "GML"))
        *gx-fmt-nome* (nth (atoi (get_tile "fmt")) '("SHP (Map)" "KML" "GeoJSON" "SDF (Map)" "MIF (Map)" "GML (Map)"))
        *GX-EXPCONV* (= "1" (get_tile "conv"))
        *GX-EXPCRS* (vl-string-trim " " (get_tile "crs"))
        *GX-EXPATRIB* (= "1" (get_tile "atrib"))
        *GX-POLIG* (= "1" (get_tile "polig")))
  (cond
    ((and (= *GX-EXPMODO* "cam") (= *GX-EXPCAMADAS* "")) (set_tile "error" "Informe as camadas.") nil)
    ((and *GX-EXPCONV* (= *GX-EXPCRS* "") (member *GX-EXPFMT* '("SHP" "FDO_SDF" "MIF" "GML")))
     (set_tile "error" "Informe o código do sistema (ex.: LL84, SIRGAS2000.UTM-23S).") nil)
    (T (gx:grava-env) T))
)
(defun gx:dialogo-exp (/ dcl arq r ss l c arq0)
  (setq arq (if (gx:pasta) (strcat (gx:pasta) "\\GeoImpExp.dcl")) r 2)
  (if (not (and arq (findfile arq))) (progn (alert "Arquivo GeoImpExp.dcl não encontrado.") (exit)))
  (if (not *gx-fmt-nome*) (setq *gx-fmt-nome* "SHP (Map)"))
  (while (= r 2)
    (setq dcl (load_dialog arq))
    (if (not (new_dialog "gx_exportar" dcl)) (progn (unload_dialog dcl) (exit)))
    (gx:ini-exp)
    (action_tile "modo" "(gx:hab-exp)")
    (action_tile "fmt" "(gx:hab-exp)")
    (action_tile "conv" "(gx:hab-exp)")
    (action_tile "selcam" "(gx:ok-exp) (done_dialog 2)")
    (action_tile "accept" "(if (gx:ok-exp) (done_dialog 1))")
    (action_tile "cancel" "(done_dialog 0)")
    (setq r (start_dialog))
    (unload_dialog dcl)
    (if (= r 2)
      (progn
        (princ "\nSelecione um objeto de cada camada: ")
        (if (setq ss (ssget))
          (progn
            (setq l (if (/= *GX-EXPCAMADAS* "") (gx:separa *GX-EXPCAMADAS* ",")))
            (repeat (setq c (sslength ss))
              (setq c (1- c) arq0 (strcase (cdr (assoc 8 (entget (ssname ss c))))))
              (if (not (member arq0 l)) (setq l (append l (list arq0)))))
            (setq *GX-EXPCAMADAS* (gx:junta l)))))))
  (= r 1)
)

(defun c:GEOEXPORTAR (/ *error* doc ss ents arq base tipos copias camadas maps fmt n geo epf saidas txt dst)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (defun *error* (msg)
    (if copias (foreach c copias (if (entget c) (entdel c))))
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")) (princ (strcat "\nErro: " msg)))
    (princ)
  )
  (if (= 0 (getvar "TILEMODE")) (setvar "TILEMODE" 1))
  (if (and (gx:requer) (gx:dialogo-exp))
    (progn
      (setq *gx-polig* *GX-POLIG*
            ss (if (= *GX-EXPMODO* "cam")
                 (ssget "_X" (list (cons 8 *GX-EXPCAMADAS*) '(410 . "Model")))
                 (progn (princ "\nSelecione os objetos a exportar: ") (ssget))))
      (if ss (repeat (setq n (sslength ss)) (setq ents (cons (ssname ss (setq n (1- n))) ents))))
      (setq fmt *GX-EXPFMT*
            txt (cdr (assoc fmt '(("SHP" . "shp") ("KML" . "kml") ("GEOJSON" . "geojson") ("FDO_SDF" . "sdf") ("MIF" . "mif") ("GML" . "gml")))))
      (cond
        ((null ents) (princ "\nNenhum objeto para exportar."))
        ((and (member fmt '("SHP" "FDO_SDF" "MIF" "GML")) (not (gx:map-ok)))
         (princ "\nMap 3D indisponível: use KML ou GeoJSON (escritores próprios)."))
        ((not (setq arq (getfiled "Exportação Avançada" (strcat (getvar "DWGPREFIX") (vl-filename-base (getvar "DWGNAME")) "." txt) txt 1))))
        ((member fmt '("KML" "GEOJSON"))
         ;; WGS 84: do sistema do desenho para 4326
         (setq dst (ic:map->epsg (ic:codigo-desenho)))
         (if (not dst) (princ "\nAviso: desenho sem sistema conhecido (SISCOORD): coordenadas exportadas SEM conversão para WGS 84."))
         (setq *IC-REPROJ* T)
         (ic:prepara-transf dst 4326 nil)
         (setq n (gx:exporta-texto ents arq fmt))
         (princ (strcat "\n" (itoa n) " feição(ões) exportada(s) em " fmt " (WGS 84): " arq)))
        (T
         (vla-StartUndoMark doc)
         (if (= *GX-EXPMODO* "sel") (setq copias (gx:copias ents) camadas "LISPS_EXPORTA") (setq camadas *GX-EXPCAMADAS*))
         (setq maps (if *GX-EXPATRIB* (gx:mapeamentos (if copias copias ents) *GX-EXPMODO*)))
         (foreach e ents (if (and (setq geo (gx:tipo-rapido e)) (not (member geo tipos))) (setq tipos (cons geo tipos))))
         (setq base (strcat (vl-filename-directory arq) "\\" (vl-filename-base arq)))
         (foreach geo (reverse tipos)
           (setq arq (if (cdr tipos)
                       (strcat base (cdr (assoc geo '(("Point" . "_pontos") ("Line" . "_linhas") ("Polygon" . "_poligonos")))) "." txt)
                       (strcat base "." txt)))
           (if (= fmt "SHP") (gx:apaga-shp (strcat (vl-filename-directory arq) "\\" (vl-filename-base arq)))
             (if (findfile arq) (vl-file-delete arq)))
           (setq epf (gx:grava-txt (gx:temp "exportar.epf") (gx:epf fmt geo camadas maps *GX-EXPCONV* *GX-EXPCRS*)))
           (princ (strcat "\nMAPEXPORT " fmt " " geo ": " arq))
           (gx:comando (list "_-MAPEXPORT" fmt arq "_Yes" epf "_Proceed"))
           (vl-file-delete epf)
           (setq saidas (cons (list arq (if (findfile arq) T)) saidas)))
         (if copias (progn (foreach c copias (if (entget c) (entdel c))) (setq copias nil)))
         (vla-EndUndoMark doc)
         (foreach s (reverse saidas)
           (princ (strcat "\n  " (car s) (if (cadr s) "  - ok" "  - NÃO gerado (rode -MAPEXPORT manualmente para ver os prompts)"))))
         (princ (strcat "\nCampos: " (if maps (gx:junta (mapcar 'car maps)) "nenhum")
                        (if (cdr tipos) " | um arquivo por tipo de geometria (o Map exporta um tipo por arquivo)" "")))))))
  (princ)
)

(princ)
