;;; decklet-fsrs-tuner-integration-test.el --- decklet-fsrs-tuner against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub: applied parameters must be accepted
;; by the real FSRS scheduler Decklet builds.

;;; Code:

(require 'ert)
(require 'fsrs)
(require 'decklet-test-helpers)
(require 'decklet-fsrs-tuner)

(ert-deftest decklet-fsrs-tuner-integration/apply-feeds-real-scheduler ()
  "Applying a tuned vector installs it and the FSRS scheduler accepts it."
  (decklet-test--with-temp-db
    (let* ((decklet-fsrs-tuner-output-file nil)
           (file (decklet-fsrs-tuner--output-file))
           ;; Start from the library defaults and nudge the first weight
           ;; within its bounds, so the vector is both distinguishable
           ;; from the defaults and acceptable to the scheduler.
           (params (let ((v (copy-sequence fsrs-default-parameters)))
                     (aset v 0 (+ (aref v 0) 0.01))
                     (append v nil))))
      (should (string-prefix-p (expand-file-name decklet-directory) file))
      (with-temp-file file
        (insert (json-encode `((parameters . ,(vconcat params))))))
      (let ((applied (decklet-fsrs-tuner-apply)))
        (should (= decklet-fsrs-tuner--parameter-count (length applied)))
        (should (equal applied decklet-fsrs-parameters))
        (should-not decklet--fsrs-scheduler)
        ;; The real scheduler is built from the installed vector.
        (should (decklet--get-fsrs-scheduler))
        (let ((meta (make-decklet-card-meta :card-id 1)))
          (should (numberp (decklet--simulate-review-interval meta 3))))))))

(provide 'decklet-fsrs-tuner-integration-test)
;;; decklet-fsrs-tuner-integration-test.el ends here
