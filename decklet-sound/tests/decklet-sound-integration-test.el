;;; decklet-sound-integration-test.el --- decklet-sound against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub: `decklet-test-helpers' comes from the
;; core repo's tests/ directory, so these tests catch drift between the
;; stub and the real public API.

;;; Code:

(require 'ert)
(require 'decklet-test-helpers)
(require 'decklet-sound)

(ert-deftest decklet-sound-integration/audio-path-uses-core-sidecar-scheme ()
  "The audio path is the core's per-card sidecar file under `decklet-directory'."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (decklet-sound-audio-directory nil)
           (path (decklet-sound-audio-path id)))
      (should (equal path
                     (decklet-card-sidecar-file (decklet-sound-audio-dir) id "mp3")))
      (should (string-prefix-p (expand-file-name decklet-directory) path)))))

(ert-deftest decklet-sound-integration/audio-file-resolves-real-card ()
  "A cached file for a real card id is found; a resolver can override it."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (decklet-sound-audio-directory nil)
           (decklet-sound-audio-resolver-functions nil)
           (fallback (decklet-sound-audio-path id)))
      (should-not (decklet-sound-audio-file id))
      (make-directory (file-name-directory fallback) t)
      (with-temp-file fallback (insert "mp3"))
      (should (equal fallback (decklet-sound-audio-file id)))
      (let ((other (expand-file-name "other.mp3" decklet-directory)))
        (with-temp-file other (insert "mp3"))
        (let ((decklet-sound-audio-resolver-functions
               (list (lambda (card-id word)
                       (should (eql card-id id))
                       (should (equal word "lucid"))
                       other))))
          (should (equal other (decklet-sound-audio-file id))))))))

(provide 'decklet-sound-integration-test)
;;; decklet-sound-integration-test.el ends here
