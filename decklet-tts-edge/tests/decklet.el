;;; decklet.el --- Minimal stub for decklet-tts-edge tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defvar decklet-db-file "/tmp/decklet-test/decklet.sqlite")
(defvar decklet-cards-deleted-functions nil)
(defvar decklet-cards-renamed-functions nil)
(defun decklet-card-sidecar-file (directory card-id extension)
  (expand-file-name (format "%d.%s" card-id extension) directory))
(defun decklet-prompt-word (&rest _) "test-word")
(defun decklet-get-card-id-by-word (_word) 7)

(provide 'decklet)

;;; decklet.el ends here
