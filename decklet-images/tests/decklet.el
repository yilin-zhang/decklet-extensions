;;; decklet.el --- Minimal stub for decklet-images tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defvar decklet-current-card-id nil)
(defvar decklet-cards-deleted-functions nil)
(defvar decklet-cards-renamed-functions nil)
(defvar decklet-cards-field-updated-functions nil)
(defvar decklet-review-floating-components nil)
(defvar decklet-edit-sidecar-columns nil)
(defvar decklet-review-mode-map (make-sparse-keymap))
(defvar decklet-edit-mode-map (make-sparse-keymap))

(defun decklet-prompt-word (&rest _) "test-word")
(defun decklet-get-card-word (_card-id) "test-word")
(defun decklet-get-card-id-by-word (_word) 1)
(defun decklet-center-text (text) text)

(provide 'decklet)

;;; decklet.el ends here
