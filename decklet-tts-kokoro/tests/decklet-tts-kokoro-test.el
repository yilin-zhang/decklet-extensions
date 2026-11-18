;;; decklet-tts-kokoro-test.el --- Tests for Decklet Kokoro TTS -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-tts-kokoro)

(defmacro decklet-tts-kokoro-test--with-sidecar (&rest body)
  "Run BODY with a temp manifest and audio dir bound.
Provides `manifest-file' and `audio-dir'; both are cleaned up."
  (declare (indent 0) (debug t))
  `(let* ((dir (make-temp-file "decklet-kokoro-test-" t))
          (manifest-file (expand-file-name "kokoro.json" dir))
          (audio-dir (expand-file-name "audio" dir))
          (decklet-tts-kokoro-manifest-file manifest-file)
          (decklet-tts-kokoro-audio-directory audio-dir)
          (trash-dir (expand-file-name "trash" dir)))
     (ignore manifest-file audio-dir)
     (make-directory audio-dir t)
     (make-directory trash-dir t)
     ;; `decklet-tts-kokoro--trash-audio' really trashes.  On macOS
     ;; `move-file-to-trash' prefers `system-move-file-to-trash' over
     ;; `trash-directory', so binding the latter is not enough to keep
     ;; test files out of the user's Trash; stub the whole function.
     (cl-letf (((symbol-function 'move-file-to-trash)
                (lambda (file)
                  (rename-file file (expand-file-name
                                     (file-name-nondirectory file) trash-dir)
                               t))))
       (unwind-protect
           (progn ,@body)
         (delete-directory dir t)))))

(defun decklet-tts-kokoro-test--write-manifest (cards)
  "Write a manifest whose \"cards\" table holds CARDS (an alist)."
  (let ((table (make-hash-table :test #'equal))
        (card-table (make-hash-table :test #'equal)))
    (dolist (entry cards)
      (let ((record (make-hash-table :test #'equal)))
        (dolist (kv (cdr entry))
          (puthash (car kv) (cdr kv) record))
        (puthash (car entry) record card-table)))
    (puthash "version" decklet-tts-kokoro--manifest-version table)
    (puthash "cards" card-table table)
    (decklet-tts-kokoro--save-manifest table)))

(ert-deftest remove-hook/drops-record-and-audio ()
  (decklet-tts-kokoro-test--with-sidecar
    (decklet-tts-kokoro-test--write-manifest
     '(("1" . (("word" . "recorded") ("status" . "valid")))
       ("2" . (("word" . "kept") ("status" . "valid")))))
    (with-temp-file (decklet-tts-kokoro-audio-path 1) (insert "mp3"))
    (decklet-tts-kokoro--remove-cards '((:card-id 1)))
    (should-not (file-exists-p (decklet-tts-kokoro-audio-path 1)))
    (let ((cards (gethash "cards" (decklet-tts-kokoro--load-manifest))))
      (should-not (gethash "1" cards))
      (should (gethash "2" cards)))))

(ert-deftest stale-hook/marks-record-and-drops-audio ()
  (decklet-tts-kokoro-test--with-sidecar
    (decklet-tts-kokoro-test--write-manifest
     '(("1" . (("word" . "recorded") ("status" . "valid")))))
    (with-temp-file (decklet-tts-kokoro-audio-path 1) (insert "mp3"))
    (decklet-tts-kokoro--stale-renamed-cards
     '((:card-id 1 :new-word "presented")))
    (should-not (file-exists-p (decklet-tts-kokoro-audio-path 1)))
    (let ((record (gethash "1" (gethash "cards"
                                        (decklet-tts-kokoro--load-manifest)))))
      (should (equal "presented" (gethash "word" record)))
      (should (equal "recorded" (gethash "previous_word" record)))
      (should (equal "stale" (gethash "status" record))))))

(ert-deftest remove-hook/no-manifest-is-a-noop ()
  (decklet-tts-kokoro-test--with-sidecar
    (decklet-tts-kokoro--remove-cards '((:card-id 7)))
    (should-not (file-exists-p (decklet-tts-kokoro-manifest-path)))))

(ert-deftest sync/passes-paths-runtime-and-dry-run ()
  "Sync runs offline from the existing venv and gets every setting."
  (let ((decklet-directory "/deck/")
        (decklet-db-file "/deck/decklet.sqlite")
        captured)
    (cl-letf (((symbol-function 'decklet-tts-kokoro--start)
               (lambda (_name args _message &optional _show-log)
                 (setq captured args))))
      (decklet-tts-kokoro-sync t))
    (should (equal '("run" "--no-sync" "--offline" "decklet-tts-kokoro" "sync")
                   (seq-take captured 5)))
    (should (equal "/deck/decklet.sqlite" (cadr (member "--db" captured))))
    (should (equal "/deck/kokoro.json" (cadr (member "--manifest" captured))))
    (should (equal "/deck/audio-cache/tts-kokoro" (cadr (member "--out-dir" captured))))
    (should (member "--model-dir" captured))
    (should (member "--trim-threshold=-55dB" captured))
    (should (member "--dry-run" captured))))

(provide 'decklet-tts-kokoro-test)

;;; decklet-tts-kokoro-test.el ends here
