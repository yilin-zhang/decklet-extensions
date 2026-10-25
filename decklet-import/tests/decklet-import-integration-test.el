;;; decklet-import-integration-test.el --- decklet-import against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub: the lines the importer produces are
;; handed to the real batch-add buffer and confirmed, so the option plist
;; and the hint syntax are checked against the real `decklet-add-card-batch'.

;;; Code:

(require 'ert)
(require 'decklet-test-helpers)
(require 'decklet-import)

(ert-deftest decklet-import-integration/batch-lines-round-trip-through-core ()
  "Kindle batch lines become cards with hints via the real batch buffer."
  (decklet-test--with-temp-db
    (let* ((decklet-import-kindle-usage t)
           (lines (decklet-import-kindle--rows->batch-lines
                   '(("lucid" "lucid" "A lucid dream")
                     ("dirt" "dirt" ""))))
           (confirmed nil))
      (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
                ((symbol-function 'quit-window) #'ignore))
        (decklet-add-card-batch lines
                                :buffer-name "*decklet-import-integration*"
                                :title "Import test"
                                :on-confirm (lambda (words) (setq confirmed words)))
        (with-current-buffer "*decklet-import-integration*"
          (unwind-protect
              (decklet-add-card-batch-confirm)
            (kill-buffer (current-buffer)))))
      (should (equal '("lucid" "dirt") confirmed))
      (should (equal '("dirt" "lucid") (decklet-list-words)))
      (should (equal "A *lucid* dream"
                     (decklet-get-card-hint (decklet-get-card-id-by-word "lucid"))))
      (should-not (decklet-get-card-hint (decklet-get-card-id-by-word "dirt"))))))

(provide 'decklet-import-integration-test)
;;; decklet-import-integration-test.el ends here
