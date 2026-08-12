;;; decklet-cloze.el --- Active-production review for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (decklet "0.1.0"))
;; Keywords: learning, tools

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:

;; Masks hinted Decklet review cards and asks the user to produce an
;; acceptable answer before normal grading continues.

;;; Code:

(require 'cl-lib)
(require 'char-fold)
(require 'subr-x)
(require 'ucs-normalize)

(require 'decklet)

(defgroup decklet-cloze nil
  "Active-production review for Decklet."
  :group 'decklet)

(defcustom decklet-cloze-marker-regexp "\\*\\([^*\n]+\\)\\*"
  "Regexp marking acceptable answers in a hint.
Submatch 1 must capture a non-empty answer."
  :type 'regexp
  :group 'decklet-cloze)

(defcustom decklet-cloze-attempts 1
  "Number of answer attempts before revealing the card.
Zero means unlimited attempts."
  :type 'natnum
  :group 'decklet-cloze)

(defun decklet-cloze-predicate-stability (card)
  "Return non-nil when CARD has at least 21 days of stability."
  (when-let* ((stability
               (decklet-card-meta-stability (plist-get card :meta))))
    (>= stability 21)))

(defcustom decklet-cloze-predicate #'decklet-cloze-predicate-stability
  "Function deciding whether CARD is mature enough for cloze.
The function receives the public card plist and returns non-nil to enable
cloze.  The hint must still match `decklet-cloze-marker-regexp'."
  :type 'function
  :group 'decklet-cloze)

(defcustom decklet-cloze-prompt "Type the word: "
  "Prompt used for the first answer attempt."
  :type 'string
  :group 'decklet-cloze)

(defun decklet-cloze--script-number-p (character)
  "Return non-nil when CHARACTER is a superscript or subscript number."
  (let ((decomposition
         (get-char-code-property character 'decomposition)))
    (and (eq (get-char-code-property character 'general-category) 'No)
         (memq (car-safe decomposition) '(super sub)))))

(defun decklet-cloze--normalize-for-match (text)
  "Normalize TEXT for cloze matching.
Normalize compatibility forms, decomposable Latin diacritics, and
dash variants.  Superscript and subscript numeric labels are discarded."
  (let ((normalized
         (ucs-normalize-NFKD-string
          (cl-remove-if #'decklet-cloze--script-number-p text))))
    (string-trim
     (mapconcat
      (lambda (character)
        (let ((category
               (get-char-code-property character 'general-category)))
          (cond
           ((memq category '(Mn Mc Me)) "")
           ((or (eq category 'Pd) (= character #x2212)) "-")
           (t (char-to-string character)))))
      normalized ""))))

(defun decklet-cloze--fold-equal-p (left right)
  "Return non-nil when normalized strings LEFT and RIGHT char-fold equally."
  (or (string-equal-ignore-case left right)
      (let ((case-fold-search t))
        (string-match-p
         (concat "\\`\\(?:" (char-fold-to-regexp right) "\\)\\'")
         left))))

(defun decklet-cloze-default-compare (input answer)
  "Return non-nil when INPUT and ANSWER match.
Comparison normalizes compatibility forms, Latin diacritics, dash
variants, superscript or subscript numeric labels, whitespace, and
case.  When ANSWER contains a hyphen, INPUT may replace each hyphen
with a space or omit the hyphen entirely."
  (let* ((input (decklet-cloze--normalize-for-match input))
         (answer (decklet-cloze--normalize-for-match answer))
         (variants (if (string-search "-" answer)
                       (list answer
                             (string-replace "-" " " answer)
                             (string-replace "-" "" answer))
                     (list answer))))
    (cl-some (lambda (variant)
               (decklet-cloze--fold-equal-p input variant))
             variants)))

(defcustom decklet-cloze-compare-function #'decklet-cloze-default-compare
  "Function used to compare user input with an acceptable answer.
The function receives two strings: the user input and one answer."
  :type 'function
  :group 'decklet-cloze)

(decklet-defface decklet-cloze-blank-face
  '((t :inherit decklet-review-word-face))
  "Face used for the masked review word."
  :group 'decklet-cloze)

(decklet-defface decklet-cloze-correct-face
  '((t :inherit success))
  "Face used for a correct cloze result."
  :group 'decklet-cloze)

(decklet-defface decklet-cloze-incorrect-face
  '((t :inherit error))
  "Face used for an incorrect cloze result."
  :group 'decklet-cloze)

(decklet-defface decklet-cloze-gave-up-face
  '((t :inherit warning))
  "Face used when giving up on a cloze prompt."
  :group 'decklet-cloze)

(defvar-local decklet-cloze--presentation nil
  "Masked word, hint, and answers for the current review card.")

(defvar-local decklet-cloze--prompt-timer nil
  "Pending prompt timer for the current review card.")

(defvar-local decklet-cloze--seen-card-ids nil
  "Card IDs already presented during this review session.")

;; Masking

(defun decklet-cloze--mask-text (text)
  "Replace word characters in TEXT with underscores."
  (replace-regexp-in-string "\\sw\\|\\s_" "_" text))

(defun decklet-cloze--mask-matches (text regexp subexp)
  "Mask SUBEXP of every REGEXP match in TEXT.
Return a cons of the transformed text and the matched strings."
  (let ((start 0)
        pieces
        matches)
    (while (string-match regexp text start)
      (let ((begin (match-beginning subexp))
            (end (match-end subexp))
            (whole-begin (match-beginning 0))
            (whole-end (match-end 0)))
        (unless (and begin end (< begin end)
                     whole-begin whole-end (< whole-begin whole-end))
          (user-error "Cloze regexp matched empty text: %S" regexp))
        (push (substring text start begin) pieces)
        (push (decklet-cloze--mask-text (substring text begin end)) pieces)
        (push (substring text end whole-end) pieces)
        (push (substring text begin end) matches)
        (setq start whole-end)))
    (push (substring text start) pieces)
    (cons (apply #'concat (nreverse pieces))
          (nreverse matches))))

(defun decklet-cloze--word-regexp (word)
  "Return a regexp matching WORD and its common suffix forms."
  (format "\\b\\(?:%s\\)\\(?:ing\\|ed\\|es\\|ly\\|s\\|d\\)?\\b"
          (char-fold-to-regexp (decklet-cloze--normalize-for-match word))))

(defun decklet-cloze--prepare (word hint)
  "Return the masked hint and acceptable answers for WORD and HINT."
  (let* ((marked (decklet-cloze--mask-matches
                  hint decklet-cloze-marker-regexp 1))
         (case-fold-search t)
         (bare (decklet-cloze--mask-matches
                (car marked) (decklet-cloze--word-regexp word) 0)))
    (list :hint (car bare)
          :answers (delete-dups
                    (cons word (append (cdr marked) (cdr bare)))))))

(defun decklet-cloze--eligible-p (card)
  "Return non-nil when CARD is ready for cloze review."
  (let ((hint (plist-get card :hint)))
    (and hint
         (string-match-p decklet-cloze-marker-regexp hint)
         (funcall decklet-cloze-predicate card))))

;; Rendering

(defun decklet-cloze-component-word ()
  "Return the current review word, masked when cloze is active."
  (if decklet-cloze--presentation
      (decklet-center-text
       (propertize (plist-get decklet-cloze--presentation :word)
                   'face 'decklet-cloze-blank-face))
    (decklet-review-component-word)))

(defun decklet-cloze-component-hint ()
  "Return the current review hint, masked when cloze is active.
Active cloze review displays its hint immediately, ignoring hint delay."
  (if decklet-cloze--presentation
      (decklet-fill-and-center-text
       (plist-get decklet-cloze--presentation :hint)
       decklet-review-fill-column)
    (decklet-review-component-hint)))

;; Prompt flow

(defun decklet-cloze--cancel-prompt ()
  "Cancel the pending cloze prompt."
  (when decklet-cloze--prompt-timer
    (cancel-timer decklet-cloze--prompt-timer)
    (setq decklet-cloze--prompt-timer nil)))

(defun decklet-cloze--correct-p (input)
  "Return non-nil when INPUT matches an acceptable answer."
  (cl-some (lambda (answer)
             (funcall decklet-cloze-compare-function input answer))
           (plist-get decklet-cloze--presentation :answers)))

(defun decklet-cloze--result-label (result)
  "Return a colored minibuffer label for RESULT."
  (pcase result
    ('correct (propertize "correct" 'face 'decklet-cloze-correct-face))
    ('incorrect (propertize "incorrect" 'face 'decklet-cloze-incorrect-face))
    ('gave-up (propertize "gave up" 'face 'decklet-cloze-gave-up-face))))

(defun decklet-cloze--read-answer (card-id)
  "Read attempts for CARD-ID, reveal it, and return the result symbol."
  (let ((attempt 0)
        result)
    (condition-case nil
        (while (not result)
          (let ((input
                 (read-string
                  (cond
                   ((zerop attempt) decklet-cloze-prompt)
                   ((zerop decklet-cloze-attempts)
                    "Incorrect. Try again: ")
                   (t
                    (format "Incorrect (%d/%d). Try again: "
                            attempt decklet-cloze-attempts))))))
            (setq attempt (1+ attempt))
            (cond
             ((string-empty-p (string-trim input))
              (setq result 'gave-up))
             ((decklet-cloze--correct-p input)
              (setq result 'correct))
             ((and (> decklet-cloze-attempts 0)
                   (>= attempt decklet-cloze-attempts))
              (setq result 'incorrect)))))
      (quit (setq result 'gave-up)))
    (when (and (eql card-id decklet-current-card-id)
               decklet-cloze--presentation)
      (setq decklet-cloze--presentation nil)
      (decklet-review-refresh)
      (message "Cloze: %s" (decklet-cloze--result-label result)))
    result))

(defun decklet-cloze--prompt-card (buffer card-id)
  "Prompt for CARD-ID in review BUFFER when it is still current."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq decklet-cloze--prompt-timer nil)
      (when (and (eql card-id decklet-current-card-id)
                 decklet-cloze--presentation)
        (if (active-minibuffer-window)
            (decklet-cloze--schedule-prompt 0.1)
          (decklet-cloze--read-answer card-id))))))

(defun decklet-cloze--schedule-prompt (&optional delay)
  "Schedule a prompt for the current review card after DELAY seconds."
  (setq decklet-cloze--prompt-timer
        (run-at-time (or delay 0) nil #'decklet-cloze--prompt-card
                     (current-buffer) decklet-current-card-id)))

(defun decklet-cloze--arm-card (card)
  "Prepare and prompt for CARD."
  (let* ((word (plist-get card :word))
         (prepared (decklet-cloze--prepare word (or (plist-get card :hint) ""))))
    (setq decklet-cloze--presentation
          (list :word (decklet-cloze--mask-text word)
                :hint (plist-get prepared :hint)
                :answers (plist-get prepared :answers)))
    (decklet-cloze--schedule-prompt)))

(defun decklet-cloze--on-next-card ()
  "Prepare cloze state when Decklet presents a new card."
  (decklet-cloze--cancel-prompt)
  (let ((card-id decklet-current-card-id))
    (if (memql card-id decklet-cloze--seen-card-ids)
        (setq decklet-cloze--presentation nil)
      (let ((card (decklet-get-card card-id)))
        (if (decklet-cloze--eligible-p card)
            (progn
              (push card-id decklet-cloze--seen-card-ids)
              (decklet-cloze--arm-card card))
          (setq decklet-cloze--presentation nil))))))

;;;###autoload
(defun decklet-cloze-retry ()
  "Force or re-arm cloze for the current review card."
  (interactive)
  (let* ((card-id (or decklet-current-card-id
                      (user-error "No current review card")))
         (card (decklet-get-card card-id)))
    (decklet-cloze--cancel-prompt)
    (decklet-cloze--arm-card card)
    (decklet-review-refresh)))

;; Minor mode

(defvar-keymap decklet-cloze-mode-map
  :doc "Keymap for `decklet-cloze-mode'."
  "C" #'decklet-cloze-retry)

(defun decklet-cloze--swap-component (variable from to)
  "Replace FROM with TO in buffer-local component list VARIABLE."
  (let ((components (symbol-value variable)))
    (when (memq from components)
      (set (make-local-variable variable)
           (cl-substitute to from components)))))

;;;###autoload
(define-minor-mode decklet-cloze-mode
  "Mask hinted cards and prompt for active production during review."
  :lighter " Cloze"
  :keymap decklet-cloze-mode-map
  (if decklet-cloze-mode
      (progn
        (decklet-cloze--swap-component
         'decklet-review-fixed-components
         'decklet-review-component-word
         'decklet-cloze-component-word)
        (decklet-cloze--swap-component
         'decklet-review-floating-components
         'decklet-review-component-hint
         'decklet-cloze-component-hint)
        (setq decklet-cloze--seen-card-ids nil)
        (add-hook 'decklet-review-next-card-hook
                  #'decklet-cloze--on-next-card nil t)
        (when decklet-current-card-id
          (decklet-cloze--on-next-card)
          (decklet-review-refresh)))
    (remove-hook 'decklet-review-next-card-hook
                 #'decklet-cloze--on-next-card t)
    (decklet-cloze--cancel-prompt)
    (decklet-cloze--swap-component
     'decklet-review-fixed-components
     'decklet-cloze-component-word
     'decklet-review-component-word)
    (decklet-cloze--swap-component
     'decklet-review-floating-components
     'decklet-cloze-component-hint
     'decklet-review-component-hint)
    (setq decklet-cloze--presentation nil)
    (when decklet-current-card-id
      (decklet-review-refresh))))

(provide 'decklet-cloze)
;;; decklet-cloze.el ends here
