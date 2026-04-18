;;; decklet-stats.el --- Per-word review history visualizer for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools

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

;; Per-word review history visualizer for Decklet.
;;
;; Reads the persistent review log produced by `decklet-review-log.el'
;; (`decklet-review-log-file', JSONL), filters events for the current
;; word's `card_id' during the read (renames are preserved because
;; filtering is by card id, not word), drops voided ratings, and
;; pops up a buffer showing:
;;
;;   - card metadata (card id, word, state, stability, difficulty,
;;     last review, due)
;;   - a multi-row ASCII chart of post-review stability over time
;;   - a compact `Grades:' digit strip with one per-grade face
;;     (`decklet-stats-grade-1-face' ... `-4-face') inheriting ansi-color
;;     foregrounds
;;   - a table of every effective rating with grade, elapsed days,
;;     and pre/post stability and difficulty
;;
;; The reader does a byte-level pre-filter (`string-search' on
;; `\"card_id\":N' or any `\"kind\":\"void\"') before JSON parsing, so
;; unrelated events never materialize as live plists — this makes
;; the popup fast even on large logs.
;;
;; Entry point:
;;
;;   M-x decklet-stats-show
;;
;; Activation: add `decklet-stats-mode' to
;; `decklet-review-mode-hook' and `decklet-edit-mode-hook'.  The
;; mode owns the `S' key binding via `decklet-stats-mode-map' and
;; loads the package eagerly so the binding is live from the first
;; card.  Press `q' in the popup to kill the buffer.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)

(require 'decklet)
(require 'decklet-review-log)

(defgroup decklet-stats nil
  "Per-word review history visualizer for Decklet."
  :group 'decklet)

(defcustom decklet-stats-log-file nil
  "Override path to the review log JSONL file.
When nil, use `decklet-review-log-file'."
  :type '(choice (const :tag "Use decklet-review-log-file" nil) file)
  :group 'decklet-stats)

(defcustom decklet-stats-chart-height 8
  "Height in rows of the multi-row stability chart."
  :type 'integer
  :group 'decklet-stats)

(defcustom decklet-stats-chart-max-width 60
  "Maximum width in columns of the multi-row stability chart.
Older reviews are dropped from the chart when the series is longer
than this; the full series still shows in the table and sparkline."
  :type 'integer
  :group 'decklet-stats)

(defconst decklet-stats--buffer-name "*Decklet Stats*")

(defface decklet-stats-title-face
  '((t :inherit outline-1))
  "Face for the stats buffer title."
  :group 'decklet-stats)

(defface decklet-stats-label-face
  '((t :inherit default))
  "Face for field labels.
Default is plain text — labels are descriptive and should not
compete visually with the values they introduce."
  :group 'decklet-stats)

(defface decklet-stats-word-face
  `((t :foreground ,(face-attribute 'decklet-color-word :foreground)
       :weight bold))
  "Face for the card word in the title."
  :group 'decklet-stats)

(defface decklet-stats-state-face
  '((t :inherit decklet-edit-state-face))
  "Face for the card state value."
  :group 'decklet-stats)

(defface decklet-stats-stability-face
  '((t :inherit decklet-edit-stability-face))
  "Face for stability values."
  :group 'decklet-stats)

(defface decklet-stats-difficulty-face
  '((t :inherit decklet-edit-difficulty-face))
  "Face for difficulty values."
  :group 'decklet-stats)

(defface decklet-stats-last-review-face
  '((t :inherit decklet-edit-last-review-face))
  "Face for last-review timestamps (card `Last:' and per-rating times)."
  :group 'decklet-stats)

(defface decklet-stats-due-face
  '((t :inherit decklet-edit-due-face))
  "Face for due timestamps."
  :group 'decklet-stats)

(defface decklet-stats-card-id-face
  '((t :inherit shadow))
  "Face for the card id, which is informational rather than meaningful."
  :group 'decklet-stats)

(defface decklet-stats-section-face
  '((t :weight bold))
  "Face for section headers and the table column header.
Bold-only, no color, so headers stand out structurally without
fighting the value colors below them."
  :group 'decklet-stats)

(defface decklet-stats-grade-1-face
  `((t :foreground ,(face-attribute 'ansi-color-magenta :foreground)))
  "Face for FSRS grade 1 (Again) in the stats popup.
Only the foreground is inherited from `ansi-color-magenta' so the
grade digits track the user's terminal palette without picking up
unrelated attributes."
  :group 'decklet-stats)

(defface decklet-stats-grade-2-face
  `((t :foreground ,(face-attribute 'ansi-color-red :foreground)))
  "Face for FSRS grade 2 (Hard) in the stats popup.
Only the foreground is inherited from `ansi-color-red'."
  :group 'decklet-stats)

(defface decklet-stats-grade-3-face
  `((t :foreground ,(face-attribute 'ansi-color-yellow :foreground)))
  "Face for FSRS grade 3 (Good) in the stats popup.
Only the foreground is inherited from `ansi-color-yellow'."
  :group 'decklet-stats)

(defface decklet-stats-grade-4-face
  `((t :foreground ,(face-attribute 'ansi-color-green :foreground)))
  "Face for FSRS grade 4 (Easy) in the stats popup.
Only the foreground is inherited from `ansi-color-green'."
  :group 'decklet-stats)

(defconst decklet-stats--kind-rated "rated")
(defconst decklet-stats--kind-void  "void")

;; Log reading

(defun decklet-stats--log-file ()
  "Return the resolved review log path."
  (or decklet-stats-log-file decklet-review-log-file))

(defun decklet-stats--line-may-match-p (line card-id-needle)
  "Return non-nil when LINE might be a void or a rated event for our card.
CARD-ID-NEEDLE is the pre-formatted literal `\"card_id\":N' to
look for.  This is a byte-level pre-filter that avoids JSON-parsing
lines from unrelated cards — 99% of the log for typical workloads.
The post-parse filter in `decklet-stats--read-log' still verifies
correctness, so a false positive only costs one wasted parse."
  (or (string-search "\"kind\":\"void\"" line)
      (string-search card-id-needle line)))

(defun decklet-stats--read-log (&optional card-id)
  "Parse the review log file into a list of plists, oldest first.
When CARD-ID is non-nil, only events relevant to that card are
retained — rated events for the card plus every void event (voids
can target any card, and we can only correlate them after
reading).  Filtering happens during parsing so unrelated events
never materialize as live plists.  Returns nil if the file is
missing, empty, or unreadable; malformed lines are silently
skipped."
  (let ((file (decklet-stats--log-file))
        (events nil)
        (needle (and card-id (format "\"card_id\":%d" card-id))))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (unless (string-blank-p line)
                (when (or (null needle)
                          (decklet-stats--line-may-match-p line needle))
                  (condition-case nil
                      (let* ((ev (json-parse-string line :object-type 'plist
                                                    :null-object nil))
                             (kind (plist-get ev :kind)))
                        (when (or (null card-id)
                                  (equal kind decklet-stats--kind-void)
                                  (and (equal kind decklet-stats--kind-rated)
                                       (equal (plist-get ev :card_id) card-id)))
                          (push ev events)))
                    (error nil)))))
            (forward-line 1)))
      (file-missing nil)
      (file-error nil))
    (nreverse events)))

(defun decklet-stats--effective-ratings (events card-id)
  "Return (RATINGS . VOIDED-COUNT) for CARD-ID, oldest first.
RATINGS is the list of rated events for CARD-ID with any voided
records removed; VOIDED-COUNT is how many of CARD-ID's rated
records were voided."
  (let ((voided (make-hash-table :test 'eql))
        (rated nil)
        (voided-count 0))
    (dolist (ev events)
      (when (equal (plist-get ev :kind) decklet-stats--kind-void)
        (when-let* ((target (plist-get ev :voids)))
          (puthash target t voided))))
    (dolist (ev events)
      (when (and (equal (plist-get ev :kind) decklet-stats--kind-rated)
                 (equal (plist-get ev :card_id) card-id))
        (if (gethash (plist-get ev :id) voided)
            (cl-incf voided-count)
          (push ev rated))))
    (cons (nreverse rated) voided-count)))

;; Chart helpers

(defun decklet-stats--chart (values height max-width)
  "Render VALUES as an ASCII chart of HEIGHT rows, capped at MAX-WIDTH cols.
Returns a multi-line string with a left-side y-axis showing the max
stability value."
  (when (and values (> height 0))
    (let* ((trimmed (if (> (length values) max-width)
                        (nthcdr (- (length values) max-width) values)
                      values))
           (mx (apply #'max trimmed))
           (mx (if (zerop mx) 1.0 (float mx)))
           (label (format "%6.1f" mx))
           (pad (make-string (length label) ?\s))
           (lines nil))
      (dotimes (row height)
        (let* ((threshold (* mx (/ (float (- height row)) height)))
               (prefix (if (zerop row) (concat label " │") (concat pad " │")))
               (cells (mapconcat
                       (lambda (v)
                         (if (>= v threshold) "█" " "))
                       trimmed "")))
          (push (concat prefix cells) lines)))
      (push (concat pad " └" (make-string (length trimmed) ?─)) lines)
      (mapconcat #'identity (nreverse lines) "\n"))))

;; Rendering

(defun decklet-stats--state-string (meta)
  "Return human state string for META."
  (or (decklet--fsrs-state-string (decklet-card-meta-state meta)) "—"))

(defun decklet-stats--format-time (s)
  "Format ISO-ish timestamp S to YYYY-MM-DD HH:MM.
Return \"—\" when S is not a string, or S unchanged when it cannot
be parsed.  `date-to-time' returns the epoch for unparseable input,
so we probe `parse-time-string' first to distinguish the two."
  (cond
   ((not (stringp s)) "—")
   ;; First 6 fields of `parse-time-string' are sec/min/hour/day/month/year;
   ;; remaining slots default to non-nil sentinels even on garbage input.
   ((not (seq-some #'identity (seq-take (parse-time-string s) 6))) s)
   (t (or (ignore-errors
            (format-time-string "%Y-%m-%d %H:%M" (date-to-time s)))
          s))))

(defun decklet-stats--grade-face (grade)
  "Return the `decklet-stats-grade-N-face' face symbol for GRADE."
  (pcase grade
    (1 'decklet-stats-grade-1-face)
    (2 'decklet-stats-grade-2-face)
    (3 'decklet-stats-grade-3-face)
    (4 'decklet-stats-grade-4-face)))

(defun decklet-stats--grade-cell (grade)
  "Return GRADE rendered with its semantic face."
  (propertize (format "%d" grade)
              'face (decklet-stats--grade-face grade)))

(defun decklet-stats--grade-history (ratings)
  "Return a propertized string of grades for RATINGS, no separator.
Grades are single digits (1-4), so concatenating them directly is
unambiguous and makes the sequence read like a compact timeline."
  (mapconcat (lambda (ev)
               (decklet-stats--grade-cell (plist-get ev :grade)))
             ratings ""))

(defun decklet-stats--field (label value)
  "Insert a `LABEL: VALUE' line with semantic faces."
  (insert (propertize (format "%-12s" label) 'face 'decklet-stats-label-face))
  (insert value "\n"))

(defun decklet-stats--render (word meta ratings voided-count)
  "Render the stats buffer for WORD/META using RATINGS and VOIDED-COUNT."
  (let* ((stab-series (mapcar (lambda (ev)
                                (or (plist-get ev :post_stability) 0))
                              ratings))
         (inhibit-read-only t))
    (erase-buffer)
    (decklet-stats--field
     "Card ID:" (propertize (format "%s" (or (decklet-card-meta-card-id meta) "—"))
                            'face 'decklet-stats-card-id-face))
    (decklet-stats--field
     "Word:" (propertize word 'face 'decklet-stats-word-face))
    (decklet-stats--field
     "State:" (propertize (decklet-stats--state-string meta)
                          'face 'decklet-stats-state-face))
    (decklet-stats--field
     "Stability:" (format "%s d    %s %s"
                          (if-let* ((s (decklet-card-meta-stability meta)))
                              (propertize (format "%.2f" s)
                                          'face 'decklet-stats-stability-face)
                            "—")
                          (propertize "Difficulty:" 'face 'decklet-stats-label-face)
                          (if-let* ((d (decklet-card-meta-difficulty meta)))
                              (propertize (format "%.2f" d)
                                          'face 'decklet-stats-difficulty-face)
                            "—")))
    (decklet-stats--field
     "Last:" (propertize (decklet-stats--format-time
                          (decklet-card-meta-last-review meta))
                         'face 'decklet-stats-last-review-face))
    (decklet-stats--field
     "Due:" (propertize (decklet-stats--format-time
                         (decklet-card-meta-due meta))
                        'face 'decklet-stats-due-face))
    (decklet-stats--field
     "Reviews:" (concat (format "%d effective" (length ratings))
                        (if (> voided-count 0)
                            (format " (%d voided)" voided-count)
                          "")))
    (insert "\n")
    (cond
     ((null ratings)
      (insert "No review history yet.\n"))
     (t
      (insert (propertize "Stability (days) over time\n\n"
                          'face 'decklet-stats-section-face))
      (insert (decklet-stats--chart stab-series
                                    decklet-stats-chart-height
                                    decklet-stats-chart-max-width))
      (insert "\n")
      (insert (propertize "Grades: " 'face 'decklet-stats-label-face))
      (insert (decklet-stats--grade-history ratings) "\n\n")
      (let ((header (format "%-3s %-17s %-5s %-7s %-13s %s"
                            "#" "When" "Grade" "Δdays"
                            "S (pre→post)" "D (pre→post)")))
        (insert (propertize header 'face 'decklet-stats-section-face) "\n")
        (insert (make-string (length header) ?─) "\n"))
      (let ((i 0))
        (dolist (ev ratings)
          (cl-incf i)
          (insert
           (format "%-3d %-17s %-5s %-7s %-13s %s\n"
                   i
                   (propertize (decklet-stats--format-time (plist-get ev :t))
                               'face 'decklet-stats-last-review-face)
                   (decklet-stats--grade-cell (plist-get ev :grade))
                   (if-let* ((d (plist-get ev :elapsed_days)))
                       (format "%.1f" d) "—")
                   (propertize
                    (format "%5.2f→%5.2f"
                            (or (plist-get ev :pre_stability) 0)
                            (or (plist-get ev :post_stability) 0))
                    'face 'decklet-stats-stability-face)
                   (propertize
                    (format "%4.2f→%4.2f"
                            (or (plist-get ev :pre_difficulty) 0)
                            (or (plist-get ev :post_difficulty) 0))
                    'face 'decklet-stats-difficulty-face)))))))
    (goto-char (point-min))))

;; Popup buffer mode

(defvar-keymap decklet-stats-view-mode-map
  :doc "Keymap for `decklet-stats-view-mode'."
  :parent special-mode-map
  "q" #'kill-buffer-and-window)

(define-derived-mode decklet-stats-view-mode special-mode "Decklet-Stats"
  "Major mode for the Decklet Stats popup buffer."
  (setq-local truncate-lines t))

;; Entry point

;;;###autoload
(defun decklet-stats-show (&optional word)
  "Show a review-history popup for WORD.
Interactively, resolve WORD via `decklet-prompt-word' so the
command works from review, edit, or anywhere by prompting.
Selects the popup window so `q' immediately kills the buffer."
  (interactive (list (decklet-prompt-word "Stats for word: ")))
  (let ((card-id (and word (decklet-card-id-for-word word))))
    (unless card-id
      (user-error "Decklet stats: no card for %S" word))
    (let* ((meta (decklet-get-card-meta card-id))
           (events (decklet-stats--read-log card-id))
           (result (decklet-stats--effective-ratings events card-id))
           (buffer (get-buffer-create decklet-stats--buffer-name)))
      (with-current-buffer buffer
        (decklet-stats-view-mode)
        (decklet-stats--render word meta (car result) (cdr result)))
      (pop-to-buffer buffer))))

;; Minor mode

(defvar-keymap decklet-stats-mode-map
  "S" #'decklet-stats-show)

;;;###autoload
(define-minor-mode decklet-stats-mode
  "Buffer-local Decklet stats binding.

Adds `S' to invoke `decklet-stats-show' for the current card.
Add to `decklet-review-mode-hook' and `decklet-edit-mode-hook' to
make the binding active in those buffers — and, as a side effect,
to load the package early so the binding is in place from the
first card."
  :keymap decklet-stats-mode-map)

(provide 'decklet-stats)

;;; decklet-stats.el ends here
