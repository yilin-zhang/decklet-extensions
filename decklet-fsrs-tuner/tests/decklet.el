;;; decklet.el --- Minimal stub for decklet-fsrs-tuner tests -*- lexical-binding: t; -*-

(defvar decklet-directory "/tmp/decklet-test/")
(defvar decklet--fsrs-scheduler nil)

;; Mirror the real `decklet-fsrs-parameters' `:set' handler so
;; `customize-set-variable' from the tuner clears the cached scheduler,
;; matching production behaviour.
(defcustom decklet-fsrs-parameters nil
  "Test-stub mirror of the FSRS parameter defcustom."
  :type '(choice (const nil) (vector))
  :set (lambda (symbol value)
         (set-default symbol value)
         (setq decklet--fsrs-scheduler nil)))

(provide 'decklet)

;;; decklet.el ends here
