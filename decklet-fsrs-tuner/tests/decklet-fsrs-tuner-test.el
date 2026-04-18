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

;;; read-parameters ----------------------------------------------------------

(ert-deftest read-parameters/valid-file-returns-21-float-vector ()
  (decklet-fsrs-tuner-test--with-tmp-output out
					    (decklet-fsrs-tuner-test--write out decklet-fsrs-tuner-test--valid-json)
					    (let ((params (decklet-fsrs-tuner--read-parameters out)))
					      (should (vectorp params))
					      (should (= 21 (length params)))
					      (should (cl-every #'floatp params)))))

(ert-deftest read-parameters/missing-file-returns-nil ()
  (should-not (decklet-fsrs-tuner--read-parameters "/nonexistent-decklet-fsrs-tuner-test.json")))

(ert-deftest read-parameters/wrong-length-returns-nil ()
  (decklet-fsrs-tuner-test--with-tmp-output out
					    (decklet-fsrs-tuner-test--write out "{\"parameters\":[1.0,2.0,3.0]}")
					    (should-not (decklet-fsrs-tuner--read-parameters out))))

(ert-deftest read-parameters/malformed-json-returns-nil ()
  (decklet-fsrs-tuner-test--with-tmp-output out
					    (decklet-fsrs-tuner-test--write out "{not json")
					    (should-not (decklet-fsrs-tuner--read-parameters out))))

(ert-deftest read-parameters/missing-parameters-field-returns-nil ()
  (decklet-fsrs-tuner-test--with-tmp-output out
					    (decklet-fsrs-tuner-test--write out "{\"metrics\":{}}")
					    (should-not (decklet-fsrs-tuner--read-parameters out))))

;;; install-parameters -------------------------------------------------------

(ert-deftest install-parameters/sets-variable-and-clears-scheduler ()
  (let ((decklet-fsrs-parameters nil)
        (decklet--fsrs-scheduler :stale))
    (decklet-fsrs-tuner--install-parameters [0.1 0.2 0.3])
    (should (equal decklet-fsrs-parameters [0.1 0.2 0.3]))
    (should (null decklet--fsrs-scheduler))))

;;; apply --------------------------------------------------------------------

(ert-deftest apply/success-installs-parameters-and-returns-vector ()
  (decklet-fsrs-tuner-test--with-tmp-output out
					    (decklet-fsrs-tuner-test--write out decklet-fsrs-tuner-test--valid-json)
					    (let ((result (decklet-fsrs-tuner-apply)))
					      (should (vectorp result))
					      (should (vectorp decklet-fsrs-parameters))
					      (should (= 21 (length decklet-fsrs-parameters)))
					      (should (null decklet--fsrs-scheduler)))))

(ert-deftest apply/missing-output-returns-nil-and-leaves-state ()
  (let ((decklet-fsrs-tuner-output-file "/nonexistent-decklet-fsrs-tuner-test.json")
        (decklet-fsrs-parameters :unchanged)
        (decklet--fsrs-scheduler :unchanged))
    (should-not (decklet-fsrs-tuner-apply))
    (should (eq decklet-fsrs-parameters :unchanged))
    (should (eq decklet--fsrs-scheduler :unchanged))))

;;; run-args -----------------------------------------------------------------

(ert-deftest run-args/includes-log-output-and-min-reviews ()
  (let ((decklet-fsrs-tuner-log-file "/log.jsonl")
        (decklet-fsrs-tuner-output-file "/params.json")
        (decklet-fsrs-tuner-min-reviews 123))
    (let ((args (decklet-fsrs-tuner--run-args)))
      (should (member "--log" args))
      (should (member "/log.jsonl" args))
      (should (member "--output" args))
      (should (member "/params.json" args))
      (should (member "--min-reviews" args))
      (should (member "123" args))
      (should (equal "decklet-fsrs-tuner" (nth 1 args)))
      (should (equal "run" (car args))))))

(provide 'decklet-fsrs-tuner-test)

;;; decklet-fsrs-tuner-test.el ends here
