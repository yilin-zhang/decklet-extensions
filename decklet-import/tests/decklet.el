;;; decklet.el --- Minimal stub for decklet-import tests -*- lexical-binding: t; -*-

;; The import tests only exercise pure helpers (row parsing, highlight,
;; batch-line construction).  They do not touch the Decklet DB, hook
;; system, or interactive commands, so the stub is intentionally tiny.

(defvar decklet-directory "/tmp/decklet-test/")

;; `decklet-add-card-batch' is referenced by the interactive
;; entry-point commands (`decklet-import-kindle', `decklet-import-kobo')
;; but those are not exercised in the test suite.  A stub here keeps
;; load-time references resolvable.
(defun decklet-add-card-batch (&rest _) nil)

(provide 'decklet)

;;; decklet.el ends here
