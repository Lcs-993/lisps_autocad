;;; ==========================================================================
;;; TrocaLayer.lsp - Troca Rapida de Layer (padronizacao de layers)
;;; --------------------------------------------------------------------------
;;; Recria o comportamento dos comandos TR-SUL / TR-TAL / TR-TER / TR-COL do
;;; AgroCAD (aba AgroCAD > painel Ajustes > "Troca Rapida de Layer"):
;;; "Troca rapidamente o layer dos objetos selecionados para o de <tipo>".
;;;
;;; Comandos:
;;;   TR-LE  -> move os objetos selecionados para o layer LIMITE_EXTERNO
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

;;; TR-LE - Transformar em Limite Externo
(defun c:TR-LE ()
  (tr:troca-layer "LIMITE_EXTERNO" 1 "Continuous" "Limite Externo")
)

(princ "\nTrocaLayer carregado. Comandos: TR-LE")
(princ)
