;;; decklet-images-test.el --- ERT tests for decklet-images -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-images)

;;; Fixture

(defmacro decklet-images-test--with-temp-dir (&rest body)
  "Run BODY with `decklet-images-directory' pointing at a fresh tmp dir.
Resets the presence cache both before and after, and deletes the dir
on exit."
  (declare (indent 0) (debug t))
  `(let* ((decklet-images-directory (make-temp-file "decklet-images-test-" t))
          (decklet-images--presence-cache nil))
     (unwind-protect
         (progn ,@body)
       (when (file-directory-p decklet-images-directory)
         (delete-directory decklet-images-directory t)))))

(defun decklet-images-test--touch (word ext)
  "Create an empty image file for WORD with EXT and return its path."
  (let ((path (decklet-images--target-path word ext)))
    (with-temp-file path)
    path))

;;; --slug and --target-path

(ert-deftest decklet-images-test/slug-encodes-space ()
  (should (equal "hello%20world" (decklet-images--slug "hello world"))))

(ert-deftest decklet-images-test/slug-plain-word-unchanged ()
  (should (equal "pitch" (decklet-images--slug "pitch"))))

(ert-deftest decklet-images-test/target-path-under-images-directory ()
  (decklet-images-test--with-temp-dir
    (let ((path (decklet-images--target-path "pitch" "png")))
      (should (string-prefix-p decklet-images-directory path))
      (should (string-suffix-p "pitch.png" path)))))

;;; --build-cache

(ert-deftest decklet-images-test/build-cache-empty-directory ()
  (decklet-images-test--with-temp-dir
    (let ((cache (decklet-images--build-cache)))
      (should (hash-table-p cache))
      (should (= 0 (hash-table-count cache))))))

(ert-deftest decklet-images-test/build-cache-missing-directory ()
  "Cache build handles a non-existent directory gracefully."
  (let ((decklet-images-directory "/nonexistent/decklet-images-test-dir/"))
    (let ((cache (decklet-images--build-cache)))
      (should (= 0 (hash-table-count cache))))))

(ert-deftest decklet-images-test/build-cache-maps-slug-to-extension ()
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "pitch" "png")
    (decklet-images-test--touch "yaw" "jpg")
    (let ((cache (decklet-images--build-cache)))
      (should (equal "png" (gethash "pitch" cache)))
      (should (equal "jpg" (gethash "yaw" cache))))))

(ert-deftest decklet-images-test/build-cache-ignores-unknown-extensions ()
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "note" "txt")
    (let ((cache (decklet-images--build-cache)))
      (should-not (gethash "note" cache)))))

(ert-deftest decklet-images-test/build-cache-extension-preference ()
  "When multiple extensions exist for one slug, earlier-listed wins."
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "pitch" "jpg")
    (decklet-images-test--touch "pitch" "png")
    (let ((cache (decklet-images--build-cache)))
      ;; png is first in default `decklet-images-extensions'.
      (should (equal "png" (gethash "pitch" cache))))))

(ert-deftest decklet-images-test/build-cache-keyed-by-slug ()
  "Cache keys are slugs (url-hexified), not raw words."
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "hello world" "png")
    (let ((cache (decklet-images--build-cache)))
      (should (equal "png" (gethash "hello%20world" cache)))
      (should-not (gethash "hello world" cache)))))

;;; decklet-images-file

(ert-deftest decklet-images-test/file-nil-when-absent ()
  (decklet-images-test--with-temp-dir
    (should-not (decklet-images-file "nothing"))))

(ert-deftest decklet-images-test/file-returns-path-when-present ()
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "pitch" "png")
    (let ((path (decklet-images-file "pitch")))
      (should path)
      (should (string-suffix-p "pitch.png" path))
      (should (file-exists-p path)))))

(ert-deftest decklet-images-test/file-populates-cache ()
  "After first lookup, the cache holds the slug->ext mapping."
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "pitch" "png")
    (decklet-images-file "pitch")
    (should decklet-images--presence-cache)
    (should (equal "png"
                   (gethash "pitch" decklet-images--presence-cache)))))

;;; Cache invalidation

(ert-deftest decklet-images-test/invalidate-drops-cache ()
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "pitch" "png")
    (decklet-images-file "pitch")
    (should decklet-images--presence-cache)
    (decklet-images--invalidate-cache)
    (should-not decklet-images--presence-cache)))

(ert-deftest decklet-images-test/cache-rebuilds-after-invalidate ()
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "pitch" "png")
    (decklet-images-file "pitch")
    (decklet-images--invalidate-cache)
    (should (decklet-images-file "pitch"))
    (should decklet-images--presence-cache)))

(ert-deftest decklet-images-test/refresh-cache-command-invalidates ()
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "pitch" "png")
    (decklet-images-file "pitch")
    (should decklet-images--presence-cache)
    (decklet-images-refresh-cache)
    (should-not decklet-images--presence-cache)))

;;; --remove-existing

(ert-deftest decklet-images-test/remove-existing-deletes-file ()
  (decklet-images-test--with-temp-dir
    (let ((path (decklet-images-test--touch "pitch" "png")))
      (decklet-images--remove-existing "pitch")
      (should-not (file-exists-p path)))))

(ert-deftest decklet-images-test/remove-existing-invalidates-cache ()
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "pitch" "png")
    (decklet-images-file "pitch")
    (decklet-images--remove-existing "pitch")
    (should-not decklet-images--presence-cache)))

(ert-deftest decklet-images-test/remove-existing-no-op-preserves-cache ()
  "Removing a non-existent image must not invalidate the cache."
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "other" "png")
    (decklet-images-file "other")
    (let ((had-cache decklet-images--presence-cache))
      (should (= 0 (decklet-images--remove-existing "pitch")))
      (should (eq had-cache decklet-images--presence-cache)))))

;;; Lifecycle handlers

(ert-deftest decklet-images-test/on-cards-deleted-removes-file ()
  (decklet-images-test--with-temp-dir
    (let ((path (decklet-images-test--touch "pitch" "png")))
      (decklet-images--on-cards-deleted
       (list (list :card-id 1 :card (list :word "pitch"))))
      (should-not (file-exists-p path)))))

(ert-deftest decklet-images-test/on-cards-deleted-batch ()
  "A single events list with several cards processes all of them."
  (decklet-images-test--with-temp-dir
    (let ((p1 (decklet-images-test--touch "one" "png"))
          (p2 (decklet-images-test--touch "two" "jpg")))
      (decklet-images--on-cards-deleted
       (list (list :card-id 1 :card (list :word "one"))
             (list :card-id 2 :card (list :word "two"))))
      (should-not (file-exists-p p1))
      (should-not (file-exists-p p2)))))

(ert-deftest decklet-images-test/on-cards-deleted-tolerates-missing-word ()
  "Handler must not error when a :card snapshot has no :word."
  (decklet-images-test--with-temp-dir
    (decklet-images--on-cards-deleted
     (list (list :card-id 1 :card nil)))))

(ert-deftest decklet-images-test/on-cards-renamed-moves-file ()
  (decklet-images-test--with-temp-dir
    (let ((old-path (decklet-images-test--touch "old-word" "png")))
      (decklet-images--on-cards-renamed
       (list (list :card-id 1 :old-word "old-word" :new-word "new-word")))
      (should-not (file-exists-p old-path))
      (should (file-exists-p (decklet-images--target-path "new-word" "png"))))))

(ert-deftest decklet-images-test/on-cards-renamed-no-op-when-absent ()
  "Rename must not error when there is no image to move."
  (decklet-images-test--with-temp-dir
    (decklet-images--on-cards-renamed
     (list (list :card-id 1 :old-word "absent" :new-word "still-absent")))))

(ert-deftest decklet-images-test/on-cards-renamed-invalidates-cache ()
  "After rename, a cached entry under the old slug must no longer hit."
  (decklet-images-test--with-temp-dir
    (decklet-images-test--touch "old-word" "png")
    (decklet-images-file "old-word")
    (decklet-images--on-cards-renamed
     (list (list :card-id 1 :old-word "old-word" :new-word "new-word")))
    (should (decklet-images-file "new-word"))
    (should-not (decklet-images-file "old-word"))))

(provide 'decklet-images-test)

;;; decklet-images-test.el ends here
