;;; decklet-tts-edge-integration-test.el --- decklet-tts-edge against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub.  The CLI arguments are built from the
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
  "Sync and generate use Decklet's DB and audio-cache/tts-edge under it."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (out-dir (expand-file-name "audio-cache/tts-edge" decklet-directory))
           (decklet-tts-edge-display-log nil)
           calls)
      (cl-letf (((symbol-function 'start-process)
                 (lambda (name buffer _program &rest args)
                   (push args calls)
                   (make-process :name name :buffer buffer :command '("true")))))
        (decklet-tts-edge-sync)
        (decklet-tts-edge-regenerate-word "lucid" ""))
      (pcase-let ((`(,gen ,sync) calls))
        (should (member (expand-file-name decklet-db-file) sync))
        (should (member out-dir sync))
        (should (member (number-to-string id) gen))
        (should (member out-dir gen))))))

(ert-deftest decklet-tts-edge-integration/delete-and-rename-trash-audio ()
  "Deleting or renaming a card moves its audio to the trash."
  (decklet-test--with-temp-db
    (let* ((trash-dir (expand-file-name "trash" decklet-directory))
           (deleted (plist-get (decklet--add-card "lucid") :card-id))
           (renamed (plist-get (decklet--add-card "colour") :card-id)))
      (dolist (id (list deleted renamed))
        (let ((path (decklet-tts-edge-audio-path id)))
          (make-directory (file-name-directory path) t)
          (with-temp-file path (insert "mp3"))))
      (decklet-tts-edge-integration-test--with-fake-trash trash-dir
        (decklet-delete-card deleted)
        (decklet-set-card-word renamed "color")
        (should-not (file-exists-p (decklet-tts-edge-audio-path deleted)))
        (should-not (file-exists-p (decklet-tts-edge-audio-path renamed)))
        (should (equal (sort (list (format "%d.mp3" deleted)
                                   (format "%d.mp3" renamed))
                             #'string<)
                       (directory-files trash-dir nil "\\.mp3\\'")))))))

(ert-deftest decklet-tts-edge-integration/other-resolvers-win ()
  "A card plays its Edge file unless a resolver at the default depth has one.
This holds even when the other generator was loaded first."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (edge (expand-file-name (format "audio-cache/tts-edge/%d.mp3" id)
                                   decklet-directory))
           (other (expand-file-name "other.mp3" decklet-directory))
           (other-resolver (lambda (_id _word) other))
           (decklet-sound-audio-resolver-functions nil))
      (make-directory (file-name-directory edge) t)
      (with-temp-file edge (insert "mp3"))
      (with-temp-file other (insert "mp3"))
      (add-hook 'decklet-sound-audio-resolver-functions other-resolver)
      (load "decklet-tts-edge" nil t)
      (should (equal other (decklet-sound-audio-file id)))
      (delete-file other)
      (should (equal edge (decklet-sound-audio-file id))))))

(provide 'decklet-tts-edge-integration-test)
;;; decklet-tts-edge-integration-test.el ends here
