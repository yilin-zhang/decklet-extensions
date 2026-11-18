;;; decklet.el --- Minimal stub for decklet-sound tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defun decklet-prompt-word (&rest _) "test-word")
(defun decklet-get-card-word (_card-id) "test-word")
(defun decklet-get-card-id-by-word (_word) 1)
(defun decklet-card-sidecar-file (directory card-id extension)
  (expand-file-name (format "%d.%s" card-id extension) directory))

(provide 'decklet)

;;; decklet.el ends here
