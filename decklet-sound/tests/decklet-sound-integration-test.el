;;; decklet-sound-integration-test.el --- decklet-sound against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub.  `decklet-test-helpers' comes from the
;; core repo's tests/ directory, so these tests catch drift between the
;; stub and the real public API.

;;; Code:

(require 'ert)
(require 'decklet-test-helpers)
(require 'decklet-sound)

(ert-deftest decklet-sound-integration/audio-file-resolves-real-card ()
  "Resolvers get the real card's id and word; with none, there is no audio."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (file (expand-file-name "lucid.mp3" decklet-directory))
           (decklet-sound-audio-resolver-functions nil))
      (with-temp-file file (insert "mp3"))
      (should-not (decklet-sound-audio-file id))
      (let ((decklet-sound-audio-resolver-functions
             (list (lambda (card-id word)
                     (should (eql card-id id))
                     (should (equal word "lucid"))
                     file))))
        (should (equal file (decklet-sound-audio-file id)))))))

(provide 'decklet-sound-integration-test)
;;; decklet-sound-integration-test.el ends here
