;;; decklet.el --- Minimal Decklet stub for Kokoro tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defvar decklet-db-file "/tmp/decklet-test/decklet.sqlite")
(defvar decklet-cards-deleted-functions nil)
(defvar decklet-cards-renamed-functions nil)
(defvar decklet-sound-audio-resolver-functions nil)

(defun decklet-prompt-word (&rest _) "record")
(defun decklet-get-card-id-by-word (_word) 42)

(provide 'decklet)

;;; decklet.el ends here
