;;; decklet-icloud-integration-test.el --- decklet-icloud against the real core -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs without the `decklet' stub, so the guard is exercised through
;; the real `decklet-db-pre-connect-hook'.  The iCloud status script
;; is replaced by `decklet-icloud-test--states', which maps a file name
;; to the state the script would report for it.

;;; Code:

(require 'ert)
(require 'decklet-test-helpers)
(require 'decklet-icloud)

(defvar decklet-icloud-test--states nil
  "Alist of (FILE-NAME . PLIST) faking the iCloud status script.
Files not listed report as fully synced.")

(defun decklet-icloud-test--query (files)
  "Fake `decklet-icloud--query' for FILES from `decklet-icloud-test--states'."
  (mapcar (lambda (file)
            (let ((state (make-hash-table :test #'equal))
                  (plist (append (alist-get (file-name-nondirectory
                                             (directory-file-name file))
                                            decklet-icloud-test--states
                                            nil nil #'equal)
                                 '(:ubiquitous t :current t))))
              (puthash "path" file state)
              (dolist (key '(:ubiquitous :current :downloading :conflicts :error))
                (puthash (substring (symbol-name key) 1)
                         (plist-get plist key) state))
              state))
          files))

(defmacro decklet-icloud-test--with-profile (&rest body)
  "Run BODY against a temporary profile that reports as stored in iCloud."
  (declare (indent 0) (debug t))
  `(decklet-test--with-temp-db
     (let ((system-type 'darwin)
           (decklet-icloud-host-name "this-mac")
           (decklet-icloud--lock-file nil)
           (decklet-icloud--override nil)
           (decklet-icloud-test--states nil)
           (decklet-db-pre-connect-hook nil)
           (decklet-db-pre-disconnect-hook nil)
           (kill-emacs-hook nil))
       (cl-letf (((symbol-function 'decklet-icloud--query)
                  #'decklet-icloud-test--query))
         (decklet-icloud-mode 1)
         (unwind-protect
             (progn ,@body)
           (decklet-icloud-mode -1))))))

(defun decklet-icloud-test--write-lock (host)
  "Write a session lock held by HOST."
  (write-region (prin1-to-string (list :host host :time "2026-10-25T09:00:00"))
                nil (decklet-icloud--lock-path) nil 'silent))

(ert-deftest decklet-icloud-integration/in-sync-connects-and-holds-lock ()
  "A synced profile connects, holds the lock, and releases it on disconnect."
  (decklet-icloud-test--with-profile
    (decklet-db--ensure)
    (should decklet-db--conn)
    (should (equal "this-mac"
                   (plist-get (decklet-icloud--read-lock
                               (decklet-icloud--lock-path))
                              :host)))
    (decklet-db--disconnect)
    (should-not (file-exists-p (decklet-icloud--lock-path)))))

(ert-deftest decklet-icloud-integration/downloading-file-refuses ()
  "A database that is still downloading refuses the connection."
  (decklet-icloud-test--with-profile
    (write-region "" nil decklet-db-file nil 'silent)
    (setq decklet-icloud-test--states
          '(("decklet.sqlite" :current nil :downloading t)))
    (should-error (decklet-db--ensure) :type 'user-error)
    (should-not decklet-db--conn)
    (should-not (file-exists-p (decklet-icloud--lock-path)))))

(ert-deftest decklet-icloud-integration/conflicts-refuse ()
  "Unresolved iCloud conflicts refuse the connection."
  (decklet-icloud-test--with-profile
    (write-region "" nil decklet-review-log-file nil 'silent)
    (setq decklet-icloud-test--states
          '(("review-log.jsonl" :conflicts t)))
    (should-error (decklet-db--ensure) :type 'user-error)
    (should-not decklet-db--conn)))

(ert-deftest decklet-icloud-integration/evicted-database-refuses ()
  "An evicted database refuses instead of creating an empty one."
  (decklet-icloud-test--with-profile
    (write-region "" nil (decklet-icloud--placeholder decklet-db-file)
                  nil 'silent)
    (setq decklet-icloud-test--states
          '(("decklet.sqlite" :ubiquitous nil)))
    (should-error (decklet-db--ensure) :type 'user-error)
    (should-not decklet-db--conn)
    (should-not (file-exists-p decklet-db-file))))

(ert-deftest decklet-icloud-integration/foreign-lock-refuses-until-override ()
  "Another machine's lock refuses; an override takes the lock over once."
  (decklet-icloud-test--with-profile
    (decklet-icloud-test--write-lock "other-mac")
    (let ((err (should-error (decklet-db--ensure) :type 'user-error)))
      (should (string-match-p "open on other-mac" (cadr err))))
    (should-not decklet-db--conn)
    (decklet-icloud-override)
    (decklet-db--ensure)
    (should decklet-db--conn)
    (should-not decklet-icloud--override)
    (should (equal "this-mac"
                   (plist-get (decklet-icloud--read-lock
                               (decklet-icloud--lock-path))
                              :host)))))

(ert-deftest decklet-icloud-integration/own-stale-lock-is-taken-over ()
  "A lock left behind by this machine does not block it."
  (decklet-icloud-test--with-profile
    (decklet-icloud-test--write-lock "this-mac")
    (decklet-db--ensure)
    (should decklet-db--conn)))

(ert-deftest decklet-icloud-integration/profile-outside-icloud-is-ignored ()
  "A profile outside iCloud Drive connects without a lock."
  (decklet-icloud-test--with-profile
    (decklet-icloud-test--write-lock "other-mac")
    (let ((decklet-icloud-test--states
           (list (list (file-name-nondirectory
                        (directory-file-name
                         (file-truename (decklet-icloud--profile-directory))))
                       :ubiquitous nil))))
      (decklet-db--ensure)
      (should decklet-db--conn)
      (should (equal "other-mac"
                     (plist-get (decklet-icloud--read-lock
                                 (decklet-icloud--lock-path))
                                :host))))))

(provide 'decklet-icloud-integration-test)
;;; decklet-icloud-integration-test.el ends here
