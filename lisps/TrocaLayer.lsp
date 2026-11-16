;;; ==========================================================================
;;; TrocaLayer.lsp - Troca Rapida de Layer (padronizacao de layers)
;;; --------------------------------------------------------------------------
;;; Recria o comportamento dos comandos TR-SUL / TR-TAL / TR-TER / TR-COL do
;;; AgroCAD (aba AgroCAD > painel Ajustes > "Troca Rapida de Layer"):
;;; "Troca rapidamente o layer dos objetos selecionados para o de <tipo>".
;;;
;;; Comandos (nomes proprios para nao conflitar com os TR-* do AgroCAD):
;;;   TR-LE  -> LIMITE_EXTERNO                       (novo)
;;;   TR-LI  -> LIMITE_INTERNO                       (novo)
;;;   TR-GL  -> GUIDELINES        (equivale a TR-SUL; TR-SU continua valendo)
;;;   TR-TA  -> TALHOES           (equivale a TR-TAL)
;;;   TR-TE  -> TERRACOS          (equivale a TR-TER)
;;;   TR-FI  -> CROPLINES         (equivale a TR-COL; TR-CO continua valendo)
;;;   CRIALAYERS -> cria todos os layers padrão do projeto que faltarem
;;;
;;; Guidelines e Fileiras usam os mesmos layers do CRIALINHAS (*CL-LAYG* e
;;; *CL-LAYP*). Talhões, terraços e carreadores: se o AgroCAD estiver
;;; carregado, nome e cor vêm da configuração dele (NOM_LAY_* e CFGAGROCAD);
;;; senão usam os padrões acima.
;;;
;;; Para criar um novo comando TR-xx basta copiar a defun de C:TR-LE e
;;; trocar o nome do layer / cor / descricao.
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; Configuracao
;;; --------------------------------------------------------------------------
;;; Se T, alem de trocar o layer, as propriedades dos objetos (cor, tipo de
;;; linha e espessura) passam para "ByLayer", ficando 100% padronizados.
(setq *TR-PROPS-BYLAYER* T)

;;; --------------------------------------------------------------------------
;;; Garante que o layer exista, esteja ligado, descongelado e destravado.
;;; nome  = nome do layer
;;; cor   = cor ACI (1-255)
;;; ltype = tipo de linha (precisa estar carregado; senao usa Continuous)
;;; --------------------------------------------------------------------------
(defun tr:garante-layer (nome cor ltype / doc lays lay)
  (setq doc  (vla-get-ActiveDocument (vlax-get-acad-object))
        lays (vla-get-Layers doc))
  (if (not (tblsearch "LTYPE" ltype)) (setq ltype "Continuous"))
  (if (tblsearch "LAYER" nome)
    (setq lay (vla-item lays nome))
    (progn
      (setq lay (vla-add lays nome))
      (vla-put-Color lay cor)
      (vla-put-Linetype lay ltype)
      (princ (strcat "\nLayer \"" nome "\" criado."))
    )
  )
  ;; layer de destino precisa estar visivel e editavel
  (vla-put-LayerOn lay :vlax-true)
  (if (/= (strcase nome) (strcase (getvar "CLAYER")))
    (vla-put-Freeze lay :vlax-false)
  )
  (vla-put-Lock lay :vlax-false)
  lay
)

;;; --------------------------------------------------------------------------
;;; Rotina generica de troca rapida de layer.
;;; --------------------------------------------------------------------------
(defun tr:troca-layer (nome cor ltype descr / *error* doc ss i obj ok travados)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))

  (defun *error* (msg)
    (vla-EndUndoMark doc)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*"))
      (princ (strcat "\nErro: " msg))
    )
    (princ)
  )

  ;; usa a selecao previa (pickfirst) ou pede uma nova
  (setq ss (ssget "_I"))
  (if ss
    (sssetfirst nil nil)
    (progn
      (princ (strcat "\nSelecione os objetos para transformar em " descr ": "))
      (setq ss (ssget))
    )
  )

  (if ss
    (progn
      (vla-StartUndoMark doc)
      (tr:garante-layer nome cor ltype)
      (setq i 0 ok 0 travados 0)
      (repeat (sslength ss)
        (setq obj (vlax-ename->vla-object (ssname ss i)))
        (if (vl-catch-all-error-p
              (vl-catch-all-apply 'vla-put-Layer (list obj nome)))
          (setq travados (1+ travados)) ; objeto em layer travado, etc.
          (progn
            (setq ok (1+ ok))
            ;; cada propriedade isolada: alguns objetos (ex.: Civil 3D)
            ;; nao aceitam todas, e isso nao deve impedir a troca de layer
            (if *TR-PROPS-BYLAYER*
              (progn
                (vl-catch-all-apply 'vla-put-Color (list obj acByLayer))
                (vl-catch-all-apply 'vla-put-Linetype (list obj "ByLayer"))
                (vl-catch-all-apply 'vla-put-Lineweight (list obj acLnWtByLayer))
              )
            )
          )
        )
        (setq i (1+ i))
      )
      (vla-EndUndoMark doc)
      (princ (strcat "\n" (itoa ok) " objeto(s) transformado(s) em " descr
                     " (layer \"" nome "\")."))
      (if (> travados 0)
        (princ (strcat "\n" (itoa travados)
                       " objeto(s) nao alterado(s) (layer de origem travado"
                       " ou objeto somente leitura)."))
      )
    )
    (princ "\nNenhum objeto selecionado.")
  )
  (princ)
)

;;; --------------------------------------------------------------------------
;;; Comandos
;;; --------------------------------------------------------------------------

;;; nome/cor do layer: configuracao do AgroCAD se existir, senao o padrao
;;; Padrão de nomes de layer do FarmTools: só A-Z, 0-9 e "_" (sem acento,
;;; sem ç, sem espaço, sem caractere especial). Ex.: "Linhas de Cana" ->
;;; "LINHAS_DE_CANA", "TALHÕES" -> "TALHOES".
(defun tr:nome-padrao (s / r c)
  (setq s (strcase (vl-string-translate "áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ"
                                        "aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN" s))
        r "")
  (foreach c (vl-string->list s)
    (setq r (strcat r (if (or (<= 65 c 90) (<= 48 c 57) (= c 95)) (chr c) "_"))))
  (while (vl-string-search "__" r) (setq r (vl-string-subst "_" "__" r)))
  (vl-string-trim "_" r)
)

;;; nome do layer: configuração (AgroCAD/CRIALINHAS) se houver, senão o
;;; padrão - sempre no padrão de nomes acima
(defun tr:cfg-nome (sym padrao / v)
  (if (and (boundp sym) (= 'STR (type (setq v (eval sym)))) (/= "" (setq v (tr:nome-padrao v))))
    v
    (tr:nome-padrao padrao))
)
(defun tr:cfg-cor (chave padrao / v)
  (if (and (boundp 'CFGAGROCAD) (listp CFGAGROCAD)
           (setq v (cadr (assoc chave CFGAGROCAD)))
           (= 'INT (type v)) (< 0 v 256))
    v padrao)
)

;;; TR-LE - Transformar em Limite Externo
(defun c:TR-LE ()
  (tr:troca-layer "LIMITE_EXTERNO" 1 "Continuous" "Limite Externo")
)

;;; TR-LI - Transformar em Limite Interno
(defun c:TR-LI ()
  (tr:troca-layer "LIMITE_INTERNO" 5 "Continuous" "Limite Interno")
)

;;; cor guardada numa variável (ex.: *CL-CORG* do CRIALINHAS) ou o padrão
(defun tr:cor-var (sym padrao / v)
  (if (and (boundp sym) (= 'INT (type (setq v (eval sym)))) (< 0 v 256)) v padrao)
)

;;; TR-GL - Transformar em Guidelines (AgroCAD: TR-SUL; antigo TR-SU)
(defun c:TR-GL ()
  (tr:troca-layer (tr:cfg-nome '*CL-LAYG* "GUIDELINES")
                  (tr:cor-var '*CL-CORG* 2) "Continuous" "Guidelines")
)
(defun c:TR-SU () (c:TR-GL))

;;; TR-TA - Transformar em Talhao (AgroCAD: TR-TAL)
(defun c:TR-TA ()
  (tr:troca-layer (tr:cfg-nome 'NOM_LAY_TALHOES "TALHOES")
                  (tr:cfg-cor "COR_LAY_TALHOES" 3) "Continuous" "Talhão")
)

;;; TR-TE - Transformar em Terraco (AgroCAD: TR-TER)
(defun c:TR-TE ()
  (tr:troca-layer (tr:cfg-nome 'NOM_LAY_TERRACOS "TERRACOS")
                  (tr:cfg-cor "COR_LAY_TERRACOS" 6) "Continuous" "Terraço")
)

;;; TR-FI - Transformar em Fileiras (AgroCAD: TR-COL; antigo TR-CO)
(defun c:TR-FI ()
  (tr:troca-layer (tr:cfg-nome '*CL-LAYP* "CROPLINES")
                  (tr:cor-var '*CL-CORP* 3) "Continuous" "Fileiras")
)
(defun c:TR-CO () (c:TR-FI))

;;; --------------------------------------------------------------------------
;;; CRIALAYERS - Criar Padrão de Layers
;;; Cria os layers usados pelas ferramentas do FarmTools que ainda não
;;; existirem no desenho. Os que já existem ficam como estão.
;;; --------------------------------------------------------------------------
;;; (nome cor descrição)
(defun tr:padrao ()
  (list
    (list "LIMITE_EXTERNO" 1 "Limite externo da área")
    (list "LIMITE_INTERNO" 5 "Limites internos (ilhas, áreas não plantadas)")
    (list (tr:cfg-nome 'NOM_LAY_TALHOES "TALHOES") (tr:cfg-cor "COR_LAY_TALHOES" 3)
          "Talhões (polilinhas fechadas)")
    (list (tr:cfg-nome 'NOM_LAY_TERRACOS "TERRACOS") (tr:cfg-cor "COR_LAY_TERRACOS" 6) "Terraços")
    (list (tr:cfg-nome '*CL-LAYG* "GUIDELINES") (tr:cor-var '*CL-CORG* 2)
          "Guidelines (linhas guia)")
    (list (tr:cfg-nome '*CL-LAYP* "CROPLINES") (tr:cor-var '*CL-CORP* 3) "Fileiras de plantio")
    (list (tr:cfg-nome 'NOM_LAY_CARREADORES "CARREADORES") (tr:cfg-cor "COR_LAY_CARREADORES" 7)
          "Carreadores")
    (list (tr:cfg-nome '*RA:DRAWLAYER* "REDE_ROTAS") 30 "Rede de rotas (eixos das estradas)"))
)

(defun c:CRIALAYERS (/ doc lays lay novos existe)
  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        lays  (vla-get-Layers doc)
        novos 0
        existe 0)
  (vla-StartUndoMark doc)
  (foreach l (tr:padrao)
    (if (tblsearch "LAYER" (car l))
      (setq existe (1+ existe))
      (progn
        (setq lay (vla-add lays (car l)))
        (vla-put-Color lay (cadr l))
        (vl-catch-all-apply 'vla-put-Description (list lay (caddr l)))
        (setq novos (1+ novos))
        (princ (strcat "\n  + " (car l) " (cor " (itoa (cadr l)) ") - " (caddr l))))))
  (vla-EndUndoMark doc)
  (princ (strcat "\n" (itoa novos) " layer(s) criado(s); " (itoa existe)
                 " já existia(m) e foram mantido(s) como estava(m)."))
  (princ)
)

(princ "\nTrocaLayer carregado. Comandos: TR-LE TR-LI TR-GL TR-TA TR-TE TR-FI CRIALAYERS")
(princ)
