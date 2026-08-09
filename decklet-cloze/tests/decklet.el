;;; decklet.el --- Minimal Decklet stub for decklet-cloze tests -*- lexical-binding: t; -*-

(defvar decklet-current-card-id nil)
(defvar decklet-review-next-card-hook nil)
(defvar decklet-review-fixed-components '(decklet-review-component-word))
(defvar decklet-review-floating-components '(decklet-review-component-hint))
(defvar decklet-review-fill-column 50)
(defvar decklet-test-card nil)
(defvar decklet-test-render-count 0)

(cl-defstruct decklet-card-meta stability)

(defface decklet-color-word '((t :foreground "red"))
  "Test word color.")

(defface decklet-review-word-face '((t :inherit decklet-color-word))
  "Test review word face.")

(defmacro decklet-defface (face spec doc &rest args)
  "Define FACE with SPEC, DOC, and ARGS for tests."
  (declare (indent defun) (doc-string 3))
  `(defface ,face ,spec ,doc ,@args))

(defun decklet-get-card (_card-id)
  "Return the current test card."
  decklet-test-card)

(defun decklet-center-text (text)
  "Return TEXT unchanged."
  text)

(defun decklet-fill-and-center-text (text _width)
  "Return TEXT unchanged."
  text)

(defun decklet-review-component-word ()
  "Return the unmasked test word."
  (plist-get decklet-test-card :word))

(defun decklet-review-component-hint ()
  "Return the unmasked test hint."
  (plist-get decklet-test-card :hint))

(defun decklet-review-refresh ()
  "Record one test render."
  (setq decklet-test-render-count (1+ decklet-test-render-count)))

(define-derived-mode decklet-review-mode special-mode "Decklet-Review-Test"
  "Test review mode.")

(provide 'decklet)
;;; decklet.el ends here
