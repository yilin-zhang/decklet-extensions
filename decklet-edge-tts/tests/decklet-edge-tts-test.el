;;; decklet-edge-tts-test.el --- ERT tests for decklet-edge-tts -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-edge-tts)

;;; Helpers

(defun decklet-edge-tts-test--buffer-with (content)
  "Create a temp buffer pre-filled with CONTENT and return it.
Caller is responsible for killing it."
  (let ((buf (generate-new-buffer " *decklet-edge-tts-test*")))
    (with-current-buffer buf (insert content))
    buf))

;;; --append-log

(ert-deftest append-log/creates-buffer-and-inserts-header ()
  (let ((name " *test-append-log*"))
    (when (get-buffer name) (kill-buffer name))
    (unwind-protect
        (progn
          (decklet-edge-tts--append-log name (list "Hello world"))
          (with-current-buffer name
            (should (string-match-p "\\[.*\\] Hello world" (buffer-string)))))
      (when (get-buffer name) (kill-buffer name)))))

(ert-deftest append-log/indents-continuation-lines ()
  (let ((name " *test-append-log-multi*"))
    (when (get-buffer name) (kill-buffer name))
    (unwind-protect
        (progn
          (decklet-edge-tts--append-log name (list "Header" "detail one" "detail two"))
          (with-current-buffer name
            (should (string-match-p "  detail one" (buffer-string)))
            (should (string-match-p "  detail two" (buffer-string)))))
      (when (get-buffer name) (kill-buffer name)))))

;;; --sync-read-number

(ert-deftest sync-read-number/reads-existing-key ()
  (with-temp-buffer
    (insert "SYNC_RESULT total=5 generated=3 trashed=1 failed=0\n")
    (should (= 3 (decklet-edge-tts--sync-read-number "generated" (point-min) (point-max))))))

(ert-deftest sync-read-number/reads-zero-value ()
  (with-temp-buffer
    (insert "SYNC_RESULT total=5 generated=0\n")
    (should (= 0 (decklet-edge-tts--sync-read-number "generated" (point-min) (point-max))))))

(ert-deftest sync-read-number/returns-nil-for-missing-key ()
  (with-temp-buffer
    (insert "SYNC_RESULT total=5 generated=3\n")
    (should-not (decklet-edge-tts--sync-read-number "planned_generate" (point-min) (point-max)))))

(ert-deftest sync-read-number/returns-nil-with-no-sync-result-line ()
  (with-temp-buffer
    (insert "some random output\n")
    (should-not (decklet-edge-tts--sync-read-number "generated" (point-min) (point-max)))))

(ert-deftest sync-read-number/respects-start-boundary ()
  "Only the region from START onwards is searched."
  (with-temp-buffer
    (insert "SYNC_RESULT generated=99\n")
    (let ((after (point-max)))
      (insert "SYNC_RESULT generated=3\n")
      (should (= 3 (decklet-edge-tts--sync-read-number "generated" after (point-max)))))))

;;; --sync-args

(ert-deftest sync-args/includes-required-flags ()
  (cl-letf (((symbol-function 'decklet-edge-tts--db-file) (lambda () "/test.sqlite"))
            ((symbol-function 'decklet-edge-tts--audio-directory) (lambda () "/audio")))
    (let ((args (decklet-edge-tts--sync-args)))
      (should (member "--sync" args))
      (should (member "--db" args))
      (should (member "/test.sqlite" args))
      (should (member "--out-dir" args))
      (should (member "/audio" args))
      (should-not (member "--dry-run" args)))))

(ert-deftest sync-args/adds-dry-run-flag ()
  (cl-letf (((symbol-function 'decklet-edge-tts--db-file) (lambda () "/test.sqlite"))
            ((symbol-function 'decklet-edge-tts--audio-directory) (lambda () "/audio")))
    (should (member "--dry-run" (decklet-edge-tts--sync-args t)))))

;;; --generate-args

(ert-deftest generate-args/includes-required-flags ()
  (cl-letf (((symbol-function 'decklet-edge-tts--audio-directory) (lambda () "/audio")))
    (let ((args (decklet-edge-tts--generate-args "pitch")))
      (should (member "--word" args))
      (should (member "pitch" args))
      (should (member "--out-dir" args))
      (should (member "--overwrite" args))
      (should-not (member "--text" args)))))

(ert-deftest generate-args/includes-text-when-provided ()
  (cl-letf (((symbol-function 'decklet-edge-tts--audio-directory) (lambda () "/audio")))
    (let ((args (decklet-edge-tts--generate-args "pitch" "pit-ch")))
      (should (member "--text" args))
      (should (member "pit-ch" args)))))

(ert-deftest generate-args/omits-text-for-empty-string ()
  (cl-letf (((symbol-function 'decklet-edge-tts--audio-directory) (lambda () "/audio")))
    (should-not (member "--text" (decklet-edge-tts--generate-args "pitch" "")))))

;;; audio-file

(ert-deftest audio-file/encodes-space-in-word ()
  (cl-letf (((symbol-function 'decklet-edge-tts--audio-directory) (lambda () "/audio")))
    (should (string-suffix-p "hello%20world.mp3" (decklet-edge-tts-audio-file "hello world")))))

(ert-deftest audio-file/plain-word-unchanged ()
  (cl-letf (((symbol-function 'decklet-edge-tts--audio-directory) (lambda () "/audio")))
    (should (string-suffix-p "pitch.mp3" (decklet-edge-tts-audio-file "pitch")))))

(ert-deftest audio-file/placed-under-audio-directory ()
  (cl-letf (((symbol-function 'decklet-edge-tts--audio-directory) (lambda () "/audio")))
    (should (string-prefix-p "/audio/" (decklet-edge-tts-audio-file "pitch")))))

;;; --db-file and --audio-directory fallbacks

(ert-deftest db-file/falls-back-to-decklet-directory ()
  (let ((decklet-edge-tts-db-file nil)
        (decklet-directory "/my/decklet/"))
    (should (string-suffix-p "decklet.sqlite" (decklet-edge-tts--db-file)))))

(ert-deftest audio-directory/falls-back-to-decklet-directory ()
  (let ((decklet-edge-tts-audio-directory nil)
        (decklet-directory "/my/decklet/"))
    (should (string-suffix-p "audio-cache/tts-edge" (decklet-edge-tts--audio-directory)))))

(ert-deftest db-file/uses-override-when-set ()
  (let ((decklet-edge-tts-db-file "/custom/db.sqlite"))
    (should (equal (expand-file-name "/custom/db.sqlite") (decklet-edge-tts--db-file)))))

(ert-deftest audio-directory/uses-override-when-set ()
  (let ((decklet-edge-tts-audio-directory "/custom/audio"))
    (should (equal (expand-file-name "/custom/audio") (decklet-edge-tts--audio-directory)))))

(provide 'decklet-edge-tts-test)

;;; decklet-edge-tts-test.el ends here
