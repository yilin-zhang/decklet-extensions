;;; decklet-images-test.el --- ERT tests for decklet-images -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-images)

;;; Fixture

(defmacro decklet-images-test--with-temp-dir (&rest body)
  "Run BODY with `decklet-images-directory' pointing at a fresh tmp dir."
  (declare (indent 0) (debug t))
  `(let* ((decklet-images-directory (make-temp-file "decklet-images-test-" t)))
     (unwind-protect
         (progn ,@body)
       (when (file-directory-p decklet-images-directory)
         (delete-directory decklet-images-directory t)))))

(defun decklet-images-test--touch (card-id ext)
  "Create an empty image file for CARD-ID with EXT and return its path."
  (let ((path (decklet-images--target-path card-id ext)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path)
    path))

;;; Finding a card's image

(ert-deftest decklet-images-test/file-finds-card-image ()
  "The image is found by card id or word, and is nil when absent."
  (decklet-images-test--with-temp-dir
    (should-not (decklet-images-card-file 1))
    (decklet-images-test--touch 1 "png")
    (let ((path (decklet-images-card-file 1)))
      (should (string-suffix-p "/1.png" path))
      (should (equal path (decklet-images-file "test-word"))))
    (cl-letf (((symbol-function 'decklet-get-card-id-by-word) #'ignore))
      (should-not (decklet-images-file "nothing")))))

(ert-deftest decklet-images-test/file-prefers-earlier-listed-extension ()
  "When multiple extensions exist for one card, earlier-listed wins."
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch 1 "jpg")
    (decklet-images-test--touch 1 "png")
    ;; png is first in default `decklet-images-extensions'.
    (should (string-suffix-p "1.png" (decklet-images-card-file 1)))))

;;; Saving

(ert-deftest decklet-images-test/set-file-replaces-obsolete-extension ()
  "A new image in another format removes the old one, which would win."
  (decklet-images-test--with-temp-dir
    (let ((source (make-temp-file "decklet-images-source-" nil ".jpg"))
          (old (decklet-images-test--touch 1 "png")))
      (unwind-protect
          (progn
            (decklet-images-set-file "test-word" source)
            (should (string-suffix-p "1.jpg" (decklet-images-card-file 1)))
            (should-not (file-exists-p old)))
        (delete-file source)))))

(defun decklet-images-test--http-response (status body)
  "Return a buffer shaped like a `url-http' reply with STATUS and BODY.
Like `url-http', header CRs are already stripped, and
`url-http-end-of-headers' sits just before the blank line's newline."
  (let ((buffer (generate-new-buffer " *http*")))
    (with-current-buffer buffer
      (set-buffer-multibyte nil)
      (insert (format "HTTP/1.1 %d X\nContent-Type: image/png\n" status))
      (setq-local url-http-end-of-headers (point-marker))
      (insert "\n")
      (setq-local url-http-response-status status)
      (insert body))
    buffer))

(ert-deftest decklet-images-test/set-url-installs-2xx-body ()
  "The body is saved under the URL path's extension, ignoring the query."
  (decklet-images-test--with-temp-dir
    (cl-letf (((symbol-function 'url-retrieve-synchronously)
               (lambda (&rest _) (decklet-images-test--http-response 200 "JPGDATA"))))
      (decklet-images-set-url "test-word" "https://x/p.jpg?size=large")
      (let ((path (decklet-images-card-file 1)))
        (should (string-suffix-p "1.jpg" path))
        (should (equal "JPGDATA" (with-temp-buffer
                                   (insert-file-contents-literally path)
                                   (buffer-string))))))))

(ert-deftest decklet-images-test/set-url-rejects-error-status ()
  (decklet-images-test--with-temp-dir
    (let ((old (decklet-images-test--touch 1 "png")))
      (with-temp-file old (insert "OLD"))
      (cl-letf (((symbol-function 'url-retrieve-synchronously)
                 (lambda (&rest _) (decklet-images-test--http-response 404 "<html>"))))
        (should-error (decklet-images-set-url "test-word" "https://x/p.png")
                      :type 'user-error))
      ;; The existing image survives and no staging file is left behind.
      (should (equal "OLD" (with-temp-buffer (insert-file-contents old) (buffer-string))))
      (should (equal (list old) (directory-files decklet-images-directory t "\\`[^.]"))))))

(ert-deftest decklet-images-test/save-flushes-replaced-image-cache ()
  "Replacing an image at the same path must invalidate its cached pixels."
  (decklet-images-test--with-temp-dir
    (let ((target (decklet-images-test--touch 1 "png"))
          flushed)
      (cl-letf (((symbol-function 'clear-image-cache)
                 (lambda (filter &optional _animation-cache)
                   (setq flushed filter))))
        (decklet-images--stage-and-install
         1 "png"
         (lambda (tmp)
           (with-temp-file tmp
             (insert "replacement")))))
      (should (equal flushed target)))))

;;; Lifecycle handlers

(ert-deftest decklet-images-test/on-cards-deleted-removes-only-those-cards ()
  "Every deleted card in the event list loses its image; others keep theirs."
  (decklet-images-test--with-temp-dir
    (let ((p1 (decklet-images-test--touch 1 "png"))
          (p2 (decklet-images-test--touch 2 "jpg"))
          (kept (decklet-images-test--touch 3 "png")))
      (decklet-images--on-cards-deleted
       (list (list :card-id 1) (list :card-id 2)))
      (should-not (file-exists-p p1))
      (should-not (file-exists-p p2))
      (should (file-exists-p kept)))))

(provide 'decklet-images-test)

;;; decklet-images-test.el ends here
