;;; decklet.el --- Minimal stub for decklet-import tests -*- lexical-binding: t; -*-

;; The import tests only exercise the row parsing and batch-line
;; building.  `decklet-add-card-batch' is called by the interactive
;; commands, which the tests do not run.
(defun decklet-add-card-batch (&rest _) nil)

(provide 'decklet)

;;; decklet.el ends here
