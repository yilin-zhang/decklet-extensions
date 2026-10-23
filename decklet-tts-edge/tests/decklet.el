;;; decklet.el --- Minimal stub for decklet-tts-edge tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defvar decklet-db-file "/tmp/decklet-test/decklet.sqlite")
(defvar decklet-current-card-id nil)
(defvar decklet-cards-deleted-functions nil)
(defvar decklet-cards-renamed-functions nil)
(defun decklet-card-sidecar-file (directory card-id extension)
  (expand-file-name (format "%d.%s" card-id extension) directory))
(defvar decklet-review-mode-map (make-sparse-keymap))
(defvar decklet-edit-mode-map (make-sparse-keymap))
(defun decklet-prompt-word (&rest _) "test-word")
(defun decklet-get-card-word (_card-id) "test-word")

(provide 'decklet)

;;; decklet.el ends here
