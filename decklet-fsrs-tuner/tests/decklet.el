;;; decklet.el --- Minimal stub for decklet-fsrs-tuner tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defvar decklet--fsrs-scheduler nil)

(defvar decklet-fsrs-parameters nil)

;; Mirror the real `decklet-set-fsrs-parameters': set the value and
;; clear the cached scheduler, matching production behaviour.
(defun decklet-set-fsrs-parameters (params)
  (set-default 'decklet-fsrs-parameters params)
  (setq decklet--fsrs-scheduler nil))

(provide 'decklet)

;;; decklet.el ends here
