;;; decklet-tts-edge-test.el --- ERT tests for decklet-tts-edge -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-tts-edge)

;;; Fixtures

(defmacro decklet-tts-edge-test--capturing-args (var &rest body)
  "Run BODY with `start-process' recording its program arguments in VAR.
The recorded call runs `true' instead, so nothing is generated."
  (declare (indent 1))
  `(let ((decklet-tts-edge-display-log nil)
         (process nil))
     (cl-letf (((symbol-function 'start-process)
                (lambda (name buffer _program &rest program-args)
                  (setq ,var program-args)
                  (setq process (make-process :name name :buffer buffer
                                              :command '("true"))))))
       ,@body)
     ;; Let the stand-in exit, so the next run is not "already running".
     (while (process-live-p process)
       (accept-process-output process 0.05))))

(defmacro decklet-tts-edge-test--with-audio-dir (&rest body)
  "Run BODY with the audio directory and the trash in fresh temp dirs.
`move-file-to-trash' is replaced, so test files never reach the real
Trash, and renames into the directory bound to `trash'."
  (declare (indent 0))
  `(let ((decklet-sound-audio-directory (make-temp-file "decklet-tts-edge-" t))
         (trash (make-temp-file "decklet-tts-edge-trash-" t)))
     (unwind-protect
         (cl-letf (((symbol-function 'move-file-to-trash)
                    (lambda (file)
                      (rename-file file (expand-file-name
                                         (file-name-nondirectory file) trash)))))
           ,@body)
       (delete-directory decklet-sound-audio-directory t)
       (delete-directory trash t))))

;;; Reading sync results

(ert-deftest sync-read-number/reads-existing-key ()
  "Each key is read by its full name; generated is not planned_generate."
  (with-temp-buffer
    (insert "SYNC_RESULT total=5 planned_generate=4 generated=0 trashed=1\n")
    (should (= 4 (decklet-tts-edge--sync-read-number "planned_generate" (point-min))))
    (should (= 0 (decklet-tts-edge--sync-read-number "generated" (point-min))))
    (should (= 1 (decklet-tts-edge--sync-read-number "trashed" (point-min))))))

(ert-deftest sync-read-number/returns-nil-when-absent ()
  "A missing key or a run with no SYNC_RESULT line reads as nil."
  (with-temp-buffer
    (insert "SYNC_RESULT total=5 generated=3\n")
    (should-not (decklet-tts-edge--sync-read-number "failed" (point-min))))
  (with-temp-buffer
    (insert "some random output\n")
    (should-not (decklet-tts-edge--sync-read-number "generated" (point-min)))))

(ert-deftest sync-read-number/respects-start-boundary ()
  "An earlier run's result before START is not read."
  (with-temp-buffer
    (insert "SYNC_RESULT generated=99\n")
    (let ((after (point-max)))
      (insert "SYNC_RESULT generated=3\n")
      (should (= 3 (decklet-tts-edge--sync-read-number "generated" after))))))

;;; Commands

(ert-deftest sync/dry-run-passes-flag ()
  "A dry run must reach the CLI as --dry-run, or it would trash files."
  (let (args)
    (decklet-tts-edge-test--capturing-args args
      (decklet-tts-edge-sync t))
    (should (member "--dry-run" args))
    (decklet-tts-edge-test--capturing-args args
      (decklet-tts-edge-sync))
    (should-not (member "--dry-run" args))))

(ert-deftest regenerate-word/passes-card-and-text ()
  "The card id and a non-empty spoken text reach the CLI."
  (let (args)
    (decklet-tts-edge-test--capturing-args args
      (decklet-tts-edge-regenerate-word "pitch" " pit-ch "))
    (should (equal "7" (cadr (member "--card-id" args))))
    (should (equal "pit-ch" (cadr (member "--text" args))))
    (decklet-tts-edge-test--capturing-args args
      (decklet-tts-edge-regenerate-word "pitch" ""))
    (should-not (member "--text" args))))

;;; Lifecycle hooks

(ert-deftest hooks/trash-only-that-cards-audio ()
  "The changed card's audio goes to the trash; other cards keep theirs."
  (decklet-tts-edge-test--with-audio-dir
    (make-directory decklet-sound-audio-directory t)
    (with-temp-file (decklet-sound-audio-path 1))
    (with-temp-file (decklet-sound-audio-path 2))
    (decklet-tts-edge--trash-audio (list (list :card-id 1)))
    (should-not (file-exists-p (decklet-sound-audio-path 1)))
    (should (file-exists-p (decklet-sound-audio-path 2)))
    (should (equal '("1.mp3") (directory-files trash nil "\\.mp3\\'")))))

(provide 'decklet-tts-edge-test)

;;; decklet-tts-edge-test.el ends here
