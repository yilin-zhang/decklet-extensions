;;; decklet-fsrs-tuner-test.el --- ERT tests for decklet-fsrs-tuner -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

;; Neutralize the auto-apply-on-load behavior during test loading; we
;; test the function directly with fixtures instead.
(setq decklet-fsrs-tuner-auto-apply nil)
(require 'decklet-fsrs-tuner)

;;; Helpers ------------------------------------------------------------------

(defun decklet-fsrs-tuner-test--write (path content)
  "Write CONTENT to PATH, creating parent directories as needed."
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert content)))

(defmacro decklet-fsrs-tuner-test--with-tmp-output (var &rest body)
  "Bind VAR to a fresh temp output path and run BODY, cleaning up on exit."
  (declare (indent 1) (debug t))
  `(let* ((tmp (make-temp-file "decklet-fsrs-tuner-test-" nil ".json"))
          (,var tmp)
          (decklet-fsrs-tuner-output-file tmp)
          (decklet-fsrs-parameters nil)
          (decklet--fsrs-scheduler :stale-sentinel))
     (unwind-protect
         (progn ,@body)
       (when (file-exists-p tmp) (delete-file tmp)))))

(defconst decklet-fsrs-tuner-test--valid-json
  "{\"parameters\":[0.21,1.29,2.31,8.29,6.41,0.83,3.01,0.001,1.87,0.16,0.79,1.48,0.06,0.26,1.64,0.60,1.87,0.54,0.09,0.06,0.15],\"metrics\":{\"effective_reviews\":500,\"cards\":120,\"voided\":0},\"log_file\":\"/x\",\"generated_at\":\"2026-04-09T21:00:00Z\"}")

;;; apply --------------------------------------------------------------------

(ert-deftest apply/valid-file-installs-float-vector ()
  "Valid output installs 21 floats and drops the cached scheduler."
  (decklet-fsrs-tuner-test--with-tmp-output out
    (decklet-fsrs-tuner-test--write out decklet-fsrs-tuner-test--valid-json)
    (let ((result (decklet-fsrs-tuner-apply)))
      (should (equal result decklet-fsrs-parameters))
      (should (= 21 (length decklet-fsrs-parameters)))
      (should (cl-every #'floatp decklet-fsrs-parameters))
      (should (null decklet--fsrs-scheduler)))))

(ert-deftest apply/bad-file-leaves-parameters-alone ()
  "Output that would break scheduling is rejected and nothing changes."
  (dolist (content
           '(;; Too few weights, or none at all.
             "{\"parameters\":[1.0,2.0,3.0]}"
             "{\"metrics\":{}}"
             ;; A weight outside the FSRS bounds.  The scheduler asserts
             ;; the bounds when built, so it would break the first review.
             "{\"parameters\":[0.21,1.29,2.31,8.29,6.41,0.83,3.01,0.001,1.87,0.16,0.79,1.48,0.06,0.26,1.64,0.60,1.87,0.54,0.09,0.06,99.0]}"
             ;; Not JSON.
             "{not json"))
    (decklet-fsrs-tuner-test--with-tmp-output out
      (decklet-fsrs-tuner-test--write out content)
      (should-not (decklet-fsrs-tuner-apply))
      (should-not decklet-fsrs-parameters)
      (should (eq decklet--fsrs-scheduler :stale-sentinel)))))

(ert-deftest apply/missing-output-returns-nil-and-leaves-state ()
  (let ((decklet-fsrs-tuner-output-file "/nonexistent-decklet-fsrs-tuner-test.json")
        (decklet-fsrs-parameters :unchanged)
        (decklet--fsrs-scheduler :unchanged))
    (should-not (decklet-fsrs-tuner-apply))
    (should (eq decklet-fsrs-parameters :unchanged))
    (should (eq decklet--fsrs-scheduler :unchanged))))

(provide 'decklet-fsrs-tuner-test)

;;; decklet-fsrs-tuner-test.el ends here
