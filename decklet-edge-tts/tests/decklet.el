;;; decklet.el --- Minimal stub for decklet-edge-tts tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defvar decklet-current-card-id nil)
(defvar decklet-cards-deleted-functions nil)
(defvar decklet-review-mode-map (make-sparse-keymap))
(defvar decklet-edit-mode-map (make-sparse-keymap))
(defun decklet-prompt-word (&rest _) "test-word")
(defun decklet-card-word-by-id (_card-id) "test-word")

(provide 'decklet)

;;; decklet.el ends here
