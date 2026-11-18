;;; decklet-cloze-integration-test.el --- decklet-cloze against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub.  Eligibility and masking are fed the
;; card plist the real `decklet-get-card' returns.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'decklet-test-helpers)
(require 'decklet-cloze)

(ert-deftest decklet-cloze-integration/eligibility-reads-real-card-plist ()
  "A mature card with a marked hint is eligible; a fresh one is not."
  (decklet-test--with-temp-db
    (let ((mature (decklet-test--add-card-meta "lucid" :stability 30.0
                                               :difficulty 5.0))
          (fresh (plist-get (decklet--add-card "vivid") :card-id)))
      (decklet-set-card-hint mature "clear, *lucid* prose")
      (decklet-set-card-hint fresh "bright, *vivid* color")
      (cl-letf (((symbol-function 'decklet-cloze--schedule-prompt) #'ignore))
        (let ((decklet-cloze--seen-card-ids nil)
              (decklet-current-card-id mature))
          (decklet-cloze--on-next-card)
          (should decklet-cloze--presentation))
        (let ((decklet-cloze--seen-card-ids nil)
              (decklet-current-card-id fresh))
          (decklet-cloze--on-next-card)
          (should-not decklet-cloze--presentation)))
      (let* ((card (decklet-get-card mature))
             (prepared (decklet-cloze--prepare (plist-get card :word)
                                               (plist-get card :hint))))
        (should (equal "clear, *_____* prose" (plist-get prepared :hint)))
        (should (equal '("lucid") (plist-get prepared :answers)))))))

(provide 'decklet-cloze-integration-test)
;;; decklet-cloze-integration-test.el ends here
