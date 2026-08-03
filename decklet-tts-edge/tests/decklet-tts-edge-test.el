;;; decklet-tts-edge-test.el --- ERT tests for decklet-tts-edge -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-tts-edge)

;;; --sync-read-number

(ert-deftest sync-read-number/reads-existing-key ()
  (with-temp-buffer
    (insert "SYNC_RESULT total=5 generated=3 trashed=1 failed=0\n")
    (should (= 3 (decklet-tts-edge--sync-read-number "generated" (point-min) (point-max))))))

(ert-deftest sync-read-number/reads-zero-value ()
  (with-temp-buffer
    (insert "SYNC_RESULT total=5 generated=0\n")
    (should (= 0 (decklet-tts-edge--sync-read-number "generated" (point-min) (point-max))))))

(ert-deftest sync-read-number/returns-nil-for-missing-key ()
  (with-temp-buffer
    (insert "SYNC_RESULT total=5 generated=3\n")
    (should-not (decklet-tts-edge--sync-read-number "planned_generate" (point-min) (point-max)))))

(ert-deftest sync-read-number/returns-nil-with-no-sync-result-line ()
  (with-temp-buffer
    (insert "some random output\n")
    (should-not (decklet-tts-edge--sync-read-number "generated" (point-min) (point-max)))))

(ert-deftest sync-read-number/respects-start-boundary ()
  "Only the region from START onwards is searched."
  (with-temp-buffer
    (insert "SYNC_RESULT generated=99\n")
    (let ((after (point-max)))
      (insert "SYNC_RESULT generated=3\n")
      (should (= 3 (decklet-tts-edge--sync-read-number "generated" after (point-max)))))))

;;; --sync-args

(ert-deftest sync-args/includes-required-flags ()
  (cl-letf (((symbol-function 'decklet-tts-edge--db-file) (lambda () "/test.sqlite"))
            ((symbol-function 'decklet-sound-audio-dir) (lambda () "/audio")))
    (let ((args (decklet-tts-edge--sync-args)))
      (should (member "--sync" args))
      (should (member "--db" args))
      (should (member "/test.sqlite" args))
      (should (member "--out-dir" args))
      (should (member "/audio" args))
      (should-not (member "--dry-run" args)))))

(ert-deftest sync-args/adds-dry-run-flag ()
  (cl-letf (((symbol-function 'decklet-tts-edge--db-file) (lambda () "/test.sqlite"))
            ((symbol-function 'decklet-sound-audio-dir) (lambda () "/audio")))
    (should (member "--dry-run" (decklet-tts-edge--sync-args t)))))

;;; --generate-args

(ert-deftest generate-args/includes-required-flags ()
  (cl-letf (((symbol-function 'decklet-sound-audio-dir) (lambda () "/audio")))
    (let ((args (decklet-tts-edge--generate-args "pitch")))
      (should (member "--word" args))
      (should (member "pitch" args))
      (should (member "--out-dir" args))
      (should (member "--overwrite" args))
      (should-not (member "--text" args)))))

(ert-deftest generate-args/includes-text-when-provided ()
  (cl-letf (((symbol-function 'decklet-sound-audio-dir) (lambda () "/audio")))
    (let ((args (decklet-tts-edge--generate-args "pitch" "pit-ch")))
      (should (member "--text" args))
      (should (member "pit-ch" args)))))

(ert-deftest generate-args/omits-text-for-empty-string ()
  (cl-letf (((symbol-function 'decklet-sound-audio-dir) (lambda () "/audio")))
    (should-not (member "--text" (decklet-tts-edge--generate-args "pitch" "")))))

;;; --db-file fallback

(ert-deftest db-file/falls-back-to-decklet-directory ()
  (let ((decklet-tts-edge-db-file nil)
        (decklet-directory "/my/decklet/"))
    (should (string-suffix-p "decklet.sqlite" (decklet-tts-edge--db-file)))))

(ert-deftest db-file/uses-override-when-set ()
  (let ((decklet-tts-edge-db-file "/custom/db.sqlite"))
    (should (equal (expand-file-name "/custom/db.sqlite") (decklet-tts-edge--db-file)))))

(provide 'decklet-tts-edge-test)

;;; decklet-tts-edge-test.el ends here
