;;; decklet-tts-edge-integration-test.el --- decklet-tts-edge against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub: the CLI arguments are built from the
;; real DB path and the real audio directory, and the lifecycle hooks are
;; driven by real card mutations.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'decklet-test-helpers)
(require 'decklet-tts-edge)

(defmacro decklet-tts-edge-integration-test--with-fake-trash (var &rest body)
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

(ert-deftest decklet-tts-edge-integration/args-follow-core-paths ()
  "Sync and generate arguments point at Decklet's DB and the sound cache."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (decklet-tts-edge-db-file nil)
           (decklet-sound-audio-directory nil)
           (sync (decklet-tts-edge--sync-args))
           (gen (decklet-tts-edge--generate-args id "lucid" nil)))
      (should (member (expand-file-name decklet-db-file) sync))
      (should (member (decklet-sound-audio-dir) sync))
      (should (member (number-to-string id) gen))
      (should (member (decklet-sound-audio-dir) gen)))))

(ert-deftest decklet-tts-edge-integration/delete-and-rename-hooks-drop-audio ()
  "Deleting a card deletes its audio; renaming trashes it into `trash-directory'."
  (decklet-test--with-temp-db
    (let* ((decklet-sound-audio-directory nil)
           (trash-dir (expand-file-name "trash" decklet-directory))
           (deleted (plist-get (decklet--add-card "lucid") :card-id))
           (renamed (plist-get (decklet--add-card "colour") :card-id)))
      (dolist (id (list deleted renamed))
        (let ((path (decklet-sound-audio-path id)))
          (make-directory (file-name-directory path) t)
          (with-temp-file path (insert "mp3"))))
      (decklet-tts-edge-integration-test--with-fake-trash trash-dir
        (decklet-delete-card deleted)
        (should-not (file-exists-p (decklet-sound-audio-path deleted)))
        (decklet-set-card-word renamed "color")
        (should-not (file-exists-p (decklet-sound-audio-path renamed)))
        (should (equal (list (format "%d.mp3" renamed))
                       (directory-files trash-dir nil "\\.mp3\\'")))))))

(provide 'decklet-tts-edge-integration-test)
;;; decklet-tts-edge-integration-test.el ends here
