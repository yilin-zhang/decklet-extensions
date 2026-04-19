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
;; A second entry point, `decklet-stats-heatmap', renders a
;; GitHub-style calendar of deck-wide review activity (7 rows ×
;; configurable weeks) from the same log — voided ratings are
;; excluded and days bucket by `decklet-day-start-time' so late-night
;; reviews line up with the scheduler.
;;
;; Entry points:
;;
;;   M-x decklet-stats-show      (per-word history popup)
;;   M-x decklet-stats-heatmap   (deck-wide activity heatmap)
;;
;; Activation: add `decklet-stats-mode' to
;; `decklet-review-mode-hook' and `decklet-edit-mode-hook'.  The
;; mode owns the `S' and `H' key bindings via
;; `decklet-stats-mode-map' and loads the package eagerly so the
;; keys are live from the first card.  Press `q' in the popup to
;; kill the buffer.

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

(defun decklet-stats--voided-ids (events)
  "Return a hash table of record-ids that some void in EVENTS targets.
Shared by consumers that need to skip voided rated records."
  (let ((voided (make-hash-table :test 'eql)))
    (dolist (ev events)
      (when (equal (plist-get ev :kind) decklet-stats--kind-void)
        (when-let* ((target (plist-get ev :voids)))
          (puthash target t voided))))
    voided))

(defun decklet-stats--effective-ratings (events card-id)
  "Return (RATINGS . VOIDED-COUNT) for CARD-ID, oldest first.
RATINGS is the list of rated events for CARD-ID with any voided
records removed; VOIDED-COUNT is how many of CARD-ID's rated
records were voided."
  (let ((voided (decklet-stats--voided-ids events))
        (rated nil)
        (voided-count 0))
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

;; Heatmap

(defcustom decklet-stats-heatmap-weeks 52
  "Number of weeks shown by `decklet-stats-heatmap'."
  :type 'integer
  :group 'decklet-stats)

(defcustom decklet-stats-heatmap-thresholds '(50 100 150)
  "Ascending thresholds that split non-zero review counts into heatmap buckets.
A zero-review day is always its own `:zero' bucket (gray `·');
non-zero counts pick a glyph by the first threshold they are
below: 1st → `:low' (░), 2nd → `:mid' (▒), 3rd → `:high' (▓),
otherwise `:max' (█).  Default maps roughly 0-200 reviews/day;
tighten for light use or widen for heavy use."
  :type '(list (integer :tag "low   <")
               (integer :tag "mid   <")
               (integer :tag "high  <"))
  :group 'decklet-stats)

(defconst decklet-stats--heatmap-buffer-name "*Decklet Heatmap*")

(defface decklet-stats-heatmap-zero-face
  '((t :inherit shadow))
  "Face for heatmap cells on days with no reviews."
  :group 'decklet-stats)

(defface decklet-stats-heatmap-bar-face
  `((t :foreground ,(face-attribute 'ansi-color-green :foreground)))
  "Face for heatmap activity cells.
Every non-zero bucket renders with this single face so intensity
is carried by the Unicode shade-block glyph (denser block = more
activity).  Zero-review days use `decklet-stats-heatmap-zero-face'
instead so they stand out as gray against the green activity."
  :group 'decklet-stats)

(defconst decklet-stats--heatmap-cells
  '((:zero ?· . decklet-stats-heatmap-zero-face)
    (:low  ?░ . decklet-stats-heatmap-bar-face)
    (:mid  ?▒ . decklet-stats-heatmap-bar-face)
    (:high ?▓ . decklet-stats-heatmap-bar-face)
    (:max  ?█ . decklet-stats-heatmap-bar-face))
  "Per-bucket glyph and face, entry shape `(KEY GLYPH . FACE)'.
Activity glyphs are the shade-block family (`░▒▓█') under a
single green face; `·' under the shadow face marks zero-review
days so they read as distinct from light activity.")

(defun decklet-stats--day-key (time)
  "Return YYYY-MM-DD for the Decklet review day containing TIME.
Uses `decklet-day-start-time' so late-night reviews fall on the same
day they would in review scheduling."
  (format-time-string "%Y-%m-%d" (decklet-day-start-time time)))

(defun decklet-stats--reviews-by-date (events)
  "Return a hash of date-string to count for effective rated EVENTS.
Voided ratings are skipped to match `decklet-stats--effective-ratings'."
  (let ((voided (decklet-stats--voided-ids events))
        (counts (make-hash-table :test 'equal)))
    (dolist (ev events)
      (when (and (equal (plist-get ev :kind) decklet-stats--kind-rated)
                 (not (gethash (plist-get ev :id) voided)))
        (when-let* ((ts (plist-get ev :t))
                    (time (ignore-errors (date-to-time ts)))
                    (key (decklet-stats--day-key time)))
          (puthash key (1+ (gethash key counts 0)) counts))))
    counts))

(defun decklet-stats--heatmap-bucket (count)
  "Return the bucket keyword for COUNT.
Zero is its own bucket so no-review days read as gray; non-zero
days split by `decklet-stats-heatmap-thresholds'."
  (cond
   ((= count 0) :zero)
   (t (let ((thresholds decklet-stats-heatmap-thresholds))
        (cond
         ((< count (nth 0 thresholds)) :low)
         ((< count (nth 1 thresholds)) :mid)
         ((< count (nth 2 thresholds)) :high)
         (t :max))))))

(defun decklet-stats--heatmap-cell-spec (bucket)
  "Return the `(GLYPH . FACE)' spec for BUCKET."
  (let ((entry (assq bucket decklet-stats--heatmap-cells)))
    (cons (cadr entry) (cddr entry))))

(defun decklet-stats--heatmap-cell (count date)
  "Return a propertized one-char cell for COUNT on DATE."
  (let ((spec (decklet-stats--heatmap-cell-spec
               (decklet-stats--heatmap-bucket count))))
    (propertize (string (car spec))
                'face (cdr spec)
                'help-echo (format "%s — %d review%s"
                                   date count (if (= count 1) "" "s")))))

(defun decklet-stats--heatmap-weekday-offset (time)
  "Return 0..6 weekday offset for TIME relative to `calendar-week-start-day'."
  (mod (- (string-to-number (format-time-string "%w" time))
          (or (bound-and-true-p calendar-week-start-day) 0))
       7))

(defun decklet-stats--heatmap-grid (end-time weeks counts)
  "Build the heatmap grid ending at END-TIME spanning WEEKS columns.
END-TIME is today's `decklet-day-start-time'.  COUNTS is the hash
returned by `decklet-stats--reviews-by-date'.  Returns a list of 7
rows ordered by `calendar-week-start-day'; each row is a list of
WEEKS cells, each cell either `(DATE . COUNT)' or nil for future
days past today in the current week."
  (let* ((end-offset (decklet-stats--heatmap-weekday-offset end-time))
         (last-col-start
          (time-subtract end-time (days-to-time end-offset)))
         (first-col-start
          (time-subtract last-col-start
                         (days-to-time (* 7 (- weeks 1)))))
         (rows (make-vector 7 nil)))
    (dotimes (col weeks)
      (let ((col-start
             (time-add first-col-start (days-to-time (* 7 col)))))
        (dotimes (wd 7)
          (let* ((day-time (time-add col-start (days-to-time wd)))
                 (future-p (time-less-p end-time day-time)))
            (push (unless future-p
                    (let ((key (decklet-stats--day-key day-time)))
                      (cons key (gethash key counts 0))))
                  (aref rows wd))))))
    (mapcar #'nreverse (append rows nil))))

(defun decklet-stats--heatmap-month-header (end-time weeks prefix-width)
  "Return the month-label header string for the heatmap.
END-TIME and WEEKS define the grid; PREFIX-WIDTH is the leading pad
so the labels align with columns rendered under row prefixes.  The
scan is day-by-day so a month label lands in the column that
contains its 1st, not the column whose week-start happens to land
in the new month."
  (let* ((end-offset (decklet-stats--heatmap-weekday-offset end-time))
         (last-col-start
          (time-subtract end-time (days-to-time end-offset)))
         (first-col-start
          (time-subtract last-col-start
                         (days-to-time (* 7 (- weeks 1)))))
         ;; Over-allocate by the label width so a month starting in the
         ;; last column can still print its 3 chars; the extra is
         ;; trimmed back below.
         (row (make-string (+ weeks 3) ?\s))
         (prev-month nil)
         ;; Next column where a fresh label is allowed, so consecutive
         ;; month labels don't overwrite each other when a month
         ;; occupies only 1-2 grid columns.
         (next-free 0)
         (total-days (* 7 weeks)))
    (dotimes (i total-days)
      (let* ((day-time (time-add first-col-start (days-to-time i)))
             (month (format-time-string "%m" day-time))
             (col (/ i 7)))
        (when (and (not (equal month prev-month))
                   (>= col next-free))
          (let ((name (format-time-string "%b" day-time)))
            (dotimes (j (min 3 (length name)))
              (aset row (+ col j) (aref name j)))
            (setq next-free (+ col 3))))
        (setq prev-month month)))
    (concat (make-string prefix-width ?\s)
            (string-trim-right (substring row 0 (+ weeks 3))))))

(defun decklet-stats--heatmap-weekday-labels ()
  "Return 7 weekday abbreviations aligned with the grid rows.
Honors `calendar-week-start-day' so the first label matches the
first grid row."
  (let ((start (or (bound-and-true-p calendar-week-start-day) 0))
        ;; 2024-01-07 is a Sunday in every timezone we care about.
        (sunday (date-to-time "2024-01-07T12:00:00Z")))
    (mapcar (lambda (i)
              (format-time-string
               "%a"
               (time-add sunday (days-to-time (mod (+ start i) 7)))))
            '(0 1 2 3 4 5 6))))

(defun decklet-stats--heatmap-range-label (bucket)
  "Return the count-range label string for BUCKET.
Derived from `decklet-stats-heatmap-thresholds' so the legend always
matches the active bucketing."
  (cl-destructuring-bind (t0 t1 t2) decklet-stats-heatmap-thresholds
    (cl-labels ((range (lo hi)
                  (cond
                   ((= (1+ lo) hi) (number-to-string lo))
                   (t (format "%d-%d" lo (1- hi))))))
      (pcase bucket
        (:zero "0")
        (:low  (range 1 t0))
        (:mid  (range t0 t1))
        (:high (range t1 t2))
        (:max  (format "%d+" t2))))))

(defun decklet-stats--heatmap-legend ()
  "Return the propertized legend string for the heatmap cells."
  (mapconcat
   (lambda (entry)
     (let ((glyph (string (cadr entry)))
           (face (cddr entry))
           (label (decklet-stats--heatmap-range-label (car entry))))
       (concat (propertize glyph 'face face) " " label)))
   decklet-stats--heatmap-cells
   "  "))

(defun decklet-stats--heatmap-summary (counts)
  "Return `(TOTAL ACTIVE-DAYS MAX-COUNT MAX-DATE)' from COUNTS."
  (let ((total 0) (active 0) (mx 0) (mx-date nil))
    (maphash (lambda (date count)
               (cl-incf total count)
               (cl-incf active)
               (when (> count mx)
                 (setq mx count mx-date date)))
             counts)
    (list total active mx mx-date)))

(defun decklet-stats--render-heatmap (events weeks)
  "Render the global heatmap from EVENTS spanning WEEKS columns."
  (let* ((counts (decklet-stats--reviews-by-date events))
         (end-time (decklet-day-start-time))
         (rows (decklet-stats--heatmap-grid end-time weeks counts))
         (labels (decklet-stats--heatmap-weekday-labels))
         (label-width (apply #'max (mapcar #'length labels)))
         (prefix-width (+ label-width 1))
         (prefix-fmt (format "%%-%ds " label-width))
         (prefixes (mapcar (lambda (l) (format prefix-fmt l)) labels))
         (inhibit-read-only t))
    (erase-buffer)
    (insert (propertize "Decklet review heatmap\n"
                        'face 'decklet-stats-title-face))
    (insert (format "Last %d week%s ending %s\n\n"
                    weeks (if (= weeks 1) "" "s")
                    (format-time-string "%Y-%m-%d" end-time)))
    (insert (decklet-stats--heatmap-month-header
             end-time weeks prefix-width)
            "\n")
    (cl-loop for row in rows
             for prefix in prefixes
             do (insert prefix)
             (dolist (cell row)
               (insert (if cell
                           (decklet-stats--heatmap-cell
                            (cdr cell) (car cell))
                         " ")))
             (insert "\n"))
    (insert "\n")
    (cl-destructuring-bind (total active mx mx-date)
        (decklet-stats--heatmap-summary counts)
      (insert (propertize "Total:" 'face 'decklet-stats-label-face)
              (format " %d review%s across %d active day%s"
                      total (if (= total 1) "" "s")
                      active (if (= active 1) "" "s"))
              (if mx-date
                  (format ".  Peak: %d on %s.\n" mx mx-date)
                ".\n")))
    (insert (propertize "Legend:" 'face 'decklet-stats-label-face)
            "  " (decklet-stats--heatmap-legend) "\n")
    (goto-char (point-min))))

;;;###autoload
(defun decklet-stats-heatmap (&optional weeks)
  "Show a calendar heatmap of review activity across the deck.
Counts every non-voided rated event in the review log, bucketed by
review day via `decklet-day-start-time'.  WEEKS defaults to
`decklet-stats-heatmap-weeks'; a numeric prefix argument overrides."
  (interactive (list (when current-prefix-arg
                       (prefix-numeric-value current-prefix-arg))))
  (let* ((weeks (max 1 (or weeks decklet-stats-heatmap-weeks)))
         (events (decklet-stats--read-log))
         (buffer (get-buffer-create decklet-stats--heatmap-buffer-name)))
    (with-current-buffer buffer
      (decklet-stats-view-mode)
      (decklet-stats--render-heatmap events weeks))
    (pop-to-buffer buffer)))

;; Minor mode

(defvar-keymap decklet-stats-mode-map
  "S" #'decklet-stats-show
  "H" #'decklet-stats-heatmap)

;;;###autoload
(define-minor-mode decklet-stats-mode
  "Buffer-local Decklet stats binding.

Adds `S' to invoke `decklet-stats-show' for the current card and
`H' for `decklet-stats-heatmap' across the deck.  Add to
`decklet-review-mode-hook' and `decklet-edit-mode-hook' to make
the bindings active in those buffers — and, as a side effect, to
load the package early so the keys are in place from the first
card."
  :keymap decklet-stats-mode-map)

(provide 'decklet-stats)

;;; decklet-stats.el ends here
