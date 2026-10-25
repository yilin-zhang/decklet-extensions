;;; check-indent.el --- Indentation check for decklet-extensions -*- lexical-binding: t; -*-

;;; Commentary:

;; Indentation check invoked by `scripts/check-indent.sh'.
;;
;; The check re-indents each file in a scratch buffer and compares the
;; result against the file on disk.  Because it never evaluates the
;; sources, `declare' forms inside `defmacro' are invisible to it, and
;; macro call sites would be measured against Emacs' fallback rule
;; (align under the opening paren) instead of the rule the macro
;; actually declares.  `decklet-check-indent--register-specs' closes
;; that gap by reading the declarations straight out of the source.

;;; Code:

;; Load the libraries whose macros appear in the sources, so their own
;; `declare' specs are registered.  Without `cl-lib', for instance,
;; `cl-letf' bodies get measured against the fallback rule.
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst decklet-check-indent--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute path to the repository root.")

(defun decklet-check-indent--files ()
  "Return absolute paths of the repo's Elisp files, excluding virtualenvs.
Untracked files are included so a new test or package is checked before
its first commit."
  (let ((default-directory decklet-check-indent--root))
    (delq nil
          (mapcar (lambda (file)
                    ;; `--cached' still lists files deleted from the
                    ;; work tree but not yet committed.
                    (unless (or (string-match-p "/\\.venv/" file)
                                (not (file-exists-p file)))
                      (expand-file-name file decklet-check-indent--root)))
                  (process-lines "git" "ls-files" "--cached" "--others"
                                 "--exclude-standard" "*.el")))))

(defun decklet-check-indent--core-files ()
  "Return the Decklet core's Elisp files, or nil when the core is absent.
The core lives at DECKLET_CORE_DIR, falling back to a sibling checkout,
as in `check-tests.sh'.  Integration tests call core macros such as
`decklet-test--with-temp-db', whose `declare' specs must be registered
for their call sites to be measured against the right rule."
  (let ((core (or (getenv "DECKLET_CORE_DIR")
                  (expand-file-name "../decklet" decklet-check-indent--root))))
    (when (file-directory-p core)
      (append (directory-files core t "\\`decklet.*\\.el\\'")
              (directory-files (expand-file-name "tests" core) t
                               "\\`decklet.*\\.el\\'")))))

(defun decklet-check-indent--register-declaration (form)
  "Register the `lisp-indent-function' spec FORM declares, if it declares one."
  (when (and (proper-list-p form)
             (memq (car form) '(defmacro cl-defmacro))
             (symbolp (nth 1 form)))
    (let ((declaration (seq-find (lambda (subform)
                                   (and (consp subform)
                                        (eq (car subform) 'declare)))
                                 (nthcdr 3 form))))
      (when-let* ((spec (assq 'indent (cdr declaration))))
        (put (nth 1 form) 'lisp-indent-function (cadr spec))))))

(defun decklet-check-indent--register-form (form)
  "Register `lisp-indent-function' specs declared anywhere within FORM.
Walks FORM recursively so macros wrapped in conditionals are found too.
The spine is walked iteratively and dotted pairs are tolerated, so
quoted test data cannot abort the scan."
  (when (consp form)
    (decklet-check-indent--register-declaration form)
    (while (consp form)
      (decklet-check-indent--register-form (car form))
      (setq form (cdr form)))))

(defun decklet-check-indent--register-specs (files)
  "Register indentation specs declared by macros defined in FILES."
  (dolist (file files)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (condition-case nil
          (while t
            (decklet-check-indent--register-form (read (current-buffer))))
        (end-of-file nil)
        ;; A file we cannot fully read still contributes whatever it
        ;; declared before the unreadable form; indentation is checked
        ;; separately and will report the real problem.
        (error nil)))))

(defun decklet-check-indent ()
  "Check or fix indentation in every tracked Elisp file.
When DECKLET_FIX_INDENT is set, rewrite files instead of failing."
  (let ((files (decklet-check-indent--files))
        bad-files)
    (decklet-check-indent--register-specs
     (append (decklet-check-indent--core-files) files))
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (let ((original (buffer-string)))
          (let ((emacs-lisp-mode-hook nil))
            (emacs-lisp-mode))
          ;; Keep the result independent of host and user defaults.
          (setq-local indent-tabs-mode nil)
          (indent-region (point-min) (point-max))
          (unless (string-equal original (buffer-string))
            (if (getenv "DECKLET_FIX_INDENT")
                (write-region (point-min) (point-max) file nil 'silent)
              (push file bad-files))))))
    (if bad-files
        (progn
          (princ "Indentation check failed for:\n")
          (dolist (file (nreverse bad-files))
            (princ (format "  %s\n"
                           (file-relative-name file decklet-check-indent--root))))
          (princ "Run ./scripts/check-indent.sh --fix to correct them.\n")
          (kill-emacs 1))
      (princ "Indentation looks good.\n"))))

(provide 'check-indent)

;;; check-indent.el ends here
