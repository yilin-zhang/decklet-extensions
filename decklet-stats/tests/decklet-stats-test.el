;;; decklet-stats-test.el --- Tests for decklet-stats -*- lexical-binding: t; -*-

;; Run interactively in an Emacs that has decklet on the load-path:
;;   M-x ert RET ^decklet-stats- RET
;;
;; Or batch:
;;   emacs -Q --batch \
;;     -L /path/to/decklet \
;;     -L /path/to/decklet-extensions/decklet-stats \
;;     -l decklet-stats-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'decklet-stats)

;; -- Fixtures ----------------------------------------------------------------

(defun decklet-stats-test--rated (id card-id grade &optional ts)
  "Build a rated event plist for tests."
  (list :kind "rated" :id id :card_id card-id :t (or ts "2026-01-01T00:00:00Z")
        :grade grade :pre_stability 0 :post_stability (* 1.0 grade)
        :pre_difficulty 5 :post_difficulty 5 :elapsed_days 0))

(defun decklet-stats-test--void (target)
  (list :kind "void" :voids target :t "2026-01-01T00:00:00Z"))

(defun decklet-stats-test--ids (events card-id)
  "Return the rated event ids for CARD-ID after filtering."
  (mapcar (lambda (e) (plist-get e :id))
          (car (decklet-stats--effective-ratings events card-id))))

(defun decklet-stats-test--voided (events card-id)
  "Return the voided count for CARD-ID."
  (cdr (decklet-stats--effective-ratings events card-id)))

(defmacro decklet-stats-test--with-tz (tz &rest body)
  "Run BODY with the TZ environment variable set to TZ."
  (declare (indent 1))
  `(let ((old-tz (getenv "TZ")))
     (unwind-protect
         (progn (setenv "TZ" ,tz) ,@body)
       (setenv "TZ" old-tz))))

(defmacro decklet-stats-test--with-log (lines &rest body)
  "Bind `decklet-review-log-file' to a temp file containing LINES, run BODY."
  (declare (indent 1))
  `(let ((tmp (make-temp-file "decklet-stats-test-" nil ".jsonl")))
     (unwind-protect
         (let ((decklet-review-log-file tmp))
           (with-temp-file tmp
             (dolist (line ,lines) (insert line "\n")))
           ,@body)
       (when (file-exists-p tmp) (delete-file tmp)))))

;; -- Effective ratings -------------------------------------------------------

(ert-deftest decklet-stats-test/effective-ratings-filters-by-card-id ()
  "Only the card's own ratings are kept, oldest first."
  (let ((events (list (decklet-stats-test--rated 1 100 3)
                      (decklet-stats-test--rated 2 200 4)
                      (decklet-stats-test--rated 3 100 2))))
    (should (equal '(1 3) (decklet-stats-test--ids events 100)))
    (should (equal '(2)   (decklet-stats-test--ids events 200)))
    (should (null         (decklet-stats-test--ids events 999)))))

(ert-deftest decklet-stats-test/effective-ratings-drops-voided ()
  (let ((events (list (decklet-stats-test--rated 1 100 3)
                      (decklet-stats-test--rated 2 100 1)
                      (decklet-stats-test--void 2)
                      (decklet-stats-test--rated 3 100 4))))
    (should (equal '(1 3) (decklet-stats-test--ids events 100)))
    (should (= 1 (decklet-stats-test--voided events 100)))))

(ert-deftest decklet-stats-test/effective-ratings-voided-count-is-per-card ()
  "A void of another card's record does not count against this card."
  (let ((events (list (decklet-stats-test--rated 1 100 3)
                      (decklet-stats-test--rated 2 200 1)
                      (decklet-stats-test--void 2))))
    (should (= 0 (decklet-stats-test--voided events 100)))
    (should (= 1 (decklet-stats-test--voided events 200)))))

(ert-deftest decklet-stats-test/effective-ratings-ignores-renames ()
  (let ((events (list (list :kind "rename" :card_id 100
                            :old "foo" :new "bar" :t "2026-01-01T00:00:00Z")
                      (decklet-stats-test--rated 1 100 3))))
    (should (equal '(1) (decklet-stats-test--ids events 100)))))

;; -- Reading the log ---------------------------------------------------------

(ert-deftest decklet-stats-test/read-log-skips-blank-and-malformed ()
  "Valid lines parse in order; blank and partial lines are skipped."
  (decklet-stats-test--with-log
      '("{\"kind\":\"rated\",\"id\":1,\"card_id\":100}"
        ""
        "this is not json"
        "{\"kind\":\"void\",\"voids\":1}"
        "{\"kind\":\"rated\",\"id\":2,\"card_id\":100")
    (let ((events (decklet-stats--read-log)))
      (should (equal '("rated" "void")
                     (mapcar (lambda (e) (plist-get e :kind)) events)))
      (should (equal 1 (plist-get (car events) :id))))))

(ert-deftest decklet-stats-test/read-log-missing-file-returns-nil ()
  (let ((decklet-review-log-file
         (expand-file-name "no-such-file.jsonl" temporary-file-directory)))
    (when (file-exists-p decklet-review-log-file)
      (delete-file decklet-review-log-file))
    (should (null (decklet-stats--read-log)))))

(ert-deftest decklet-stats-test/read-log-for-card-keeps-its-voids ()
  "Reading one card's history still sees the voids of its ratings."
  (decklet-stats-test--with-log
      '("{\"kind\":\"rated\",\"id\":1,\"card_id\":100}"
        "{\"kind\":\"rated\",\"id\":2,\"card_id\":200}"
        "{\"kind\":\"void\",\"voids\":1}"
        "{\"kind\":\"rename\",\"card_id\":100,\"old\":\"a\",\"new\":\"b\"}")
    (let ((result (decklet-stats--effective-ratings
                   (decklet-stats--read-log 100) 100)))
      (should (null (car result)))
      (should (= 1 (cdr result))))))

;; -- Rendering helpers -------------------------------------------------------

(ert-deftest decklet-stats-test/chart-trims-to-max-width ()
  (let* ((values (number-sequence 1 100))
         (rendered (decklet-stats--chart values 4 10))
         (last-row (car (last (split-string rendered "\n")))))
    ;; The axis row is "<label> └" followed by one dash per column.
    (should (string-match "└\\(─+\\)$" last-row))
    (should (= 10 (length (match-string 1 last-row))))))

(ert-deftest decklet-stats-test/format-time ()
  (decklet-stats-test--with-tz "UTC0"
    (should (equal "2026-04-13 09:12"
                   (decklet-stats--format-time "2026-04-13T09:12:00Z")))
    (should (equal "—" (decklet-stats--format-time nil)))))

;; -- Heatmap -----------------------------------------------------------------

(ert-deftest decklet-stats-test/reviews-by-date-follows-rollover ()
  "Reviews count toward the review day, which starts at the rollover hour."
  (decklet-stats-test--with-tz "UTC0"
    (let* ((decklet-day-rollover-hour 4)
           (events (list (decklet-stats-test--rated 1 100 3 "2026-04-10T10:00:00Z")
                         ;; 02:00 is before the 04:00 rollover, so it is
                         ;; still the review day of April 10.
                         (decklet-stats-test--rated 2 100 3 "2026-04-11T02:00:00Z")
                         (decklet-stats-test--rated 3 200 3 "2026-04-11T09:00:00Z")))
           (counts (decklet-stats--reviews-by-date events)))
      (should (= 2 (gethash "2026-04-10" counts)))
      (should (= 1 (gethash "2026-04-11" counts)))
      (should (= 2 (hash-table-count counts))))))

(ert-deftest decklet-stats-test/reviews-by-date-excludes-voided ()
  (decklet-stats-test--with-tz "UTC0"
    (let* ((decklet-day-rollover-hour 0)
           (events (list (decklet-stats-test--rated 1 100 3 "2026-04-10T10:00:00Z")
                         (decklet-stats-test--rated 2 100 3 "2026-04-10T11:00:00Z")
                         (decklet-stats-test--void 2)))
           (counts (decklet-stats--reviews-by-date events)))
      (should (= 1 (gethash "2026-04-10" counts))))))

(ert-deftest decklet-stats-test/heatmap-grid-ends-today ()
  "Rows follow the week start; days after today in this week are empty."
  (decklet-stats-test--with-tz "UTC0"
    (let* ((decklet-day-rollover-hour 0)
           (calendar-week-start-day 0)
           ;; 2026-04-15 is a Wednesday, row 3 when Sunday is row 0.
           (end (decklet-day-start-time (date-to-time "2026-04-15T12:00:00Z")))
           (counts (make-hash-table :test 'equal)))
      (puthash "2026-04-15" 7 counts)
      (let ((rows (decklet-stats--heatmap-grid end 1 counts)))
        (should (= 7 (length rows)))
        (should (equal '("2026-04-12" . 0) (car (nth 0 rows))))
        (should (equal '("2026-04-15" . 7) (car (nth 3 rows))))
        (should (equal '(nil nil nil) (mapcar #'car (nthcdr 4 rows))))))))

(ert-deftest decklet-stats-test/heatmap-grid-steps-by-date-across-dst ()
  "Every grid cell is a distinct, consecutive date, even across DST."
  (decklet-stats-test--with-tz "America/Los_Angeles"
    (let* ((end (decklet-day-start-time
                 (encode-time '(0 0 12 23 10 2026 nil -1 nil))))
           (grid (decklet-stats--heatmap-grid
                  end 52 (make-hash-table :test 'equal)))
           (keys (delq nil (mapcar #'car (apply #'append grid)))))
      (should (= (length keys) (length (delete-dups (copy-sequence keys)))))
      ;; The day before spring-forward used to vanish.
      (should (member "2026-03-07" keys))
      (should (member "2026-10-23" keys))
      (should-not (member "2026-10-24" keys)))))

(ert-deftest decklet-stats-test/heatmap-bucket-boundaries ()
  "Zero is its own bucket; each threshold starts the next bucket."
  (let ((decklet-stats-heatmap-thresholds '(5 15 30)))
    (pcase-dolist (`(,count . ,bucket)
                   '((0 . :zero) (1 . :low) (4 . :low) (5 . :mid) (14 . :mid)
                     (15 . :high) (29 . :high) (30 . :max) (500 . :max)))
      (should (eq bucket (decklet-stats--heatmap-bucket count))))))

(ert-deftest decklet-stats-test/heatmap-range-label ()
  (let ((decklet-stats-heatmap-thresholds '(50 100 150)))
    (should (equal "0"       (decklet-stats--heatmap-range-label :zero)))
    (should (equal "1-49"    (decklet-stats--heatmap-range-label :low)))
    (should (equal "50-99"   (decklet-stats--heatmap-range-label :mid)))
    (should (equal "100-149" (decklet-stats--heatmap-range-label :high)))
    (should (equal "150+"    (decklet-stats--heatmap-range-label :max)))))

(provide 'decklet-stats-test)

;;; decklet-stats-test.el ends here
