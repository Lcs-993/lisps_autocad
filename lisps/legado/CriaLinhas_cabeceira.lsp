;;; CriaLinhas_cabeceira.lsp - NAO CARREGADO (pasta legado).
;;; Bordadura/cabeceira retirada do CRIALINHAS em 2026-11-14; referencia para a
;;; futura ferramenta de Bordadura. Depende dos helpers cl: do CriaLinhas.lsp
;;; (cl:offset, cl:poe-layer, cl:layer, cl:plantio) e de *CL-PASS* / *CL-RECUAR*.

;;; CABECEIRA: offsets do contorno dos talhões (já selecionados)
(defun cl:cabeceira (dentro talhoes / bnd a0 r sinal k d objs guias tot)
  (if talhoes
    (progn
      (cl:layer *CL-LAYG* *CL-CORG*)
      (setq tot 0)
      (foreach bnd talhoes
        (setq a0 (vla-get-Area bnd) sinal 1.0 guias nil)
        (if (setq r (cl:offset bnd 1.0))
          (progn
            (if (> (vla-get-Area (car r)) a0) (setq sinal -1.0))
            (mapcar 'vla-delete r)))
        (if (not dentro) (setq sinal (- sinal)))
        (setq k 1)
        (repeat *CL-PASS*
          (setq d (* *CL-ESPG* (if *CL-RECUAR* (- k 0.5) k)))
          (setq objs (cl:offset bnd (* sinal d)))
          (if (null objs)
            (princ (strcat "\nPassada " (itoa k) " não coube no talhão; parando."))
          )
          (setq guias (append (cl:poe-layer objs *CL-LAYG*) guias) k (1+ k))
        )
        (if (member *CL-MODO* '("GC" "C"))
          (setq tot (+ tot (length (cl:plantio guias nil nil)))))
        (if (= *CL-MODO* "C")
          (mapcar 'vla-delete guias)
          (setq tot (+ tot (length guias))))
      )
      (princ (strcat "\n" (itoa tot) " linha(s) de cabeceira criada(s)."))
    )
  )
)

