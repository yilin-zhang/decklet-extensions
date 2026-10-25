;;; decklet-tts-kokoro-integration-test.el --- decklet-tts-kokoro against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' and `decklet-sound' stubs: the resolver is
;; registered on the real `decklet-sound' hook and the delete hook is
;; driven by a real card deletion.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'decklet-test-helpers)
(require 'decklet-tts-kokoro)

(defmacro decklet-tts-kokoro-integration-test--with-fake-trash (var &rest body)
  "Run BODY with `move-file-to-trash' renaming into the directory bound to VAR.
On macOS `move-file-to-trash' prefers `system-move-file-to-trash' over
`trash-directory', so binding the latter would still put test files in
the user's Trash; the function is stubbed instead."
  (declare (indent 1) (debug t))
  `(progn
     (make-directory ,var t)
     (cl-letf (((symbol-function 'move-file-to-trash)
                (lambda (file)
                  (rename-file file (expand-file-name
                                     (file-name-nondirectory file) ,var)
                               t))))
       ,@body)))

(ert-deftest decklet-tts-kokoro-integration/resolver-wins-over-edge-cache ()
  "`decklet-sound-audio-file' returns the Kokoro file through the resolver."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (decklet-tts-kokoro-audio-directory nil)
           (decklet-sound-audio-directory nil)
           (kokoro (decklet-tts-kokoro-audio-path id)))
      (should (memq #'decklet-tts-kokoro-audio-resolver
                    decklet-sound-audio-resolver-functions))
      (make-directory (file-name-directory kokoro) t)
      (with-temp-file kokoro (insert "mp3"))
      (should (equal kokoro (decklet-sound-audio-file id))))))

(ert-deftest decklet-tts-kokoro-integration/delete-card-removes-record-and-audio ()
  "Deleting a real card drops its manifest record and trashes its audio."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (decklet-tts-kokoro-audio-directory nil)
           (decklet-tts-kokoro-manifest-file nil)
           (trash-dir (expand-file-name "trash" decklet-directory))
           (audio (decklet-tts-kokoro-audio-path id))
           (manifest (decklet-tts-kokoro--load-manifest)))
      (puthash (number-to-string id)
               (let ((record (make-hash-table :test #'equal)))
                 (puthash "word" "lucid" record)
                 (puthash "status" "ok" record)
                 record)
               (gethash "cards" manifest))
      (decklet-tts-kokoro--save-manifest manifest)
      (make-directory (file-name-directory audio) t)
      (with-temp-file audio (insert "mp3"))
      (decklet-tts-kokoro-integration-test--with-fake-trash trash-dir
        (decklet-delete-card id)
        (should-not (file-exists-p audio))
        (should (file-exists-p (expand-file-name (format "%d.mp3" id) trash-dir)))
        (should-not (gethash (number-to-string id)
                             (gethash "cards" (decklet-tts-kokoro--load-manifest))))))))

(provide 'decklet-tts-kokoro-integration-test)
;;; decklet-tts-kokoro-integration-test.el ends here
