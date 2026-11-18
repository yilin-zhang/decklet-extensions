;;; decklet.el --- Minimal stub for decklet-images tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defvar decklet-current-card-id nil)
(defvar decklet-cards-deleted-functions nil)
(defvar decklet-review-fixed-components nil)
(defvar decklet-review-floating-components nil)
(defvar decklet-edit-sidecar-columns nil)

(defun decklet-prompt-word (&rest _) "test-word")
(defun decklet-fire-one-card-event (&rest _))
(defun decklet-get-card-id-by-word (_word) 1)
(defun decklet-card-sidecar-file (directory card-id extension)
  (expand-file-name (format "%d.%s" card-id extension) directory))

(provide 'decklet)

;;; decklet.el ends here
