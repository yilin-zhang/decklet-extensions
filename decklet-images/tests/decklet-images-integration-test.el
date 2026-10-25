;;; decklet-images-integration-test.el --- decklet-images against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub so the lifecycle hook, the component
;; registration and the card lookups are exercised against the real
;; Decklet core.

;;; Code:

(require 'ert)
(require 'decklet-test-helpers)
(require 'decklet-images)

(ert-deftest decklet-images-integration/registers-ui-components-on-load ()
  "Loading the package registers the review indicator and the edit column."
  (should (memq 'decklet-images-component-indicator
                (default-value 'decklet-review-floating-components)))
  (should (memq decklet-images-edit-column
                (default-value 'decklet-edit-sidecar-columns))))

(ert-deftest decklet-images-integration/set-file-then-delete-card-removes-image ()
  "An installed image is found by word, and the real delete hook removes it."
  (decklet-test--with-temp-db
    (let* ((id (plist-get (decklet--add-card "lucid") :card-id))
           (decklet-images-directory nil)
           (source (expand-file-name "source.png" decklet-directory)))
      (with-temp-file source (insert "png"))
      (decklet-images--save-from-file id source)
      (let ((installed (decklet-images-file "lucid")))
        (should installed)
        (should (equal installed (decklet-images-card-file id)))
        (should (decklet-images-edit-column-value (list :card-id id)))
        (decklet-delete-card id)
        (should-not (file-exists-p installed))
        (should-not (decklet-images-card-file id))))))

(provide 'decklet-images-integration-test)
;;; decklet-images-integration-test.el ends here
