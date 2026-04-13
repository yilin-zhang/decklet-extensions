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

;; -- decklet-stats--effective-ratings ----------------------------------------
;;
;; Core filter logic: must (a) keep only rated events for the given
;; card-id, (b) drop any rated record whose id is targeted by a void,
;; (c) preserve oldest-first order, (d) ignore unrelated rename events.

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

(ert-deftest decklet-stats-test/effective-ratings-filters-by-card-id ()
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
  ;; A void targeting a different card's record must not inflate this
  ;; card's voided count.
  (let ((events (list (decklet-stats-test--rated 1 100 3)
                      (decklet-stats-test--rated 2 200 1)
                      (decklet-stats-test--void 2))))
    (should (= 0 (decklet-stats-test--voided events 100)))
    (should (= 1 (decklet-stats-test--voided events 200)))))

(ert-deftest decklet-stats-test/effective-ratings-honors-void-out-of-order ()
  ;; A void appearing before its rated record (shouldn't happen in practice
  ;; but the implementation does a two-pass scan) must still take effect.
  (let ((events (list (decklet-stats-test--void 2)
                      (decklet-stats-test--rated 1 100 3)
                      (decklet-stats-test--rated 2 100 1))))
    (should (equal '(1) (decklet-stats-test--ids events 100)))))

(ert-deftest decklet-stats-test/effective-ratings-ignores-renames ()
  (let ((events (list (list :kind "rename" :card_id 100
                            :old "foo" :new "bar" :t "2026-01-01T00:00:00Z")
                      (decklet-stats-test--rated 1 100 3))))
    (should (equal '(1) (decklet-stats-test--ids events 100)))))

(ert-deftest decklet-stats-test/effective-ratings-preserves-order ()
  (let ((events (list (decklet-stats-test--rated 10 100 3)
                      (decklet-stats-test--rated 20 100 4)
                      (decklet-stats-test--rated 30 100 2))))
    (should (equal '(10 20 30) (decklet-stats-test--ids events 100)))))

;; -- decklet-stats--read-log -------------------------------------------------

(defmacro decklet-stats-test--with-log (lines &rest body)
  "Bind `decklet-stats-log-file' to a temp file containing LINES, run BODY."
  (declare (indent 1))
  `(let ((tmp (make-temp-file "decklet-stats-test-" nil ".jsonl")))
     (unwind-protect
         (let ((decklet-stats-log-file tmp))
           (with-temp-file tmp
             (dolist (line ,lines) (insert line "\n")))
           ,@body)
       (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest decklet-stats-test/read-log-parses-jsonl ()
  (decklet-stats-test--with-log
      '("{\"kind\":\"rated\",\"id\":1,\"card_id\":100,\"grade\":3}"
        "{\"kind\":\"void\",\"voids\":1}")
    (let ((events (decklet-stats--read-log)))
      (should (= 2 (length events)))
      (should (equal "rated" (plist-get (nth 0 events) :kind)))
      (should (equal 1 (plist-get (nth 0 events) :id)))
      (should (equal "void" (plist-get (nth 1 events) :kind))))))

(ert-deftest decklet-stats-test/read-log-skips-blank-and-malformed ()
  (decklet-stats-test--with-log
      '("{\"kind\":\"rated\",\"id\":1,\"card_id\":100}"
        ""
        "this is not json"
        "{\"kind\":\"rated\",\"id\":2,\"card_id\":100}")
    (let ((events (decklet-stats--read-log)))
      (should (= 2 (length events)))
      (should (equal '(1 2) (mapcar (lambda (e) (plist-get e :id)) events))))))

(ert-deftest decklet-stats-test/read-log-missing-file-returns-nil ()
  (let ((decklet-stats-log-file
         (expand-file-name "no-such-file.jsonl" temporary-file-directory)))
    (when (file-exists-p decklet-stats-log-file)
      (delete-file decklet-stats-log-file))
    (should (null (decklet-stats--read-log)))))

;; -- decklet-stats--chart ----------------------------------------------------

(ert-deftest decklet-stats-test/chart-has-height-plus-axis-rows ()
  (let* ((rendered (decklet-stats--chart '(1 2 3 4 5) 4 60))
         (rows (split-string rendered "\n")))
    ;; height rows + one axis row
    (should (= 5 (length rows)))))

(ert-deftest decklet-stats-test/chart-trims-to-max-width ()
  (let* ((values (number-sequence 1 100))
         (rendered (decklet-stats--chart values 4 10))
         (last-row (car (last (split-string rendered "\n")))))
    ;; axis row is "<label> └" + N dashes; N must be 10
    (should (string-match "└\\(─+\\)$" last-row))
    (should (= 10 (length (match-string 1 last-row))))))

(ert-deftest decklet-stats-test/chart-handles-all-zero ()
  ;; Zero-only series must not divide by zero or crash.
  (let ((rendered (decklet-stats--chart '(0 0 0) 3 60)))
    (should (stringp rendered))
    (should (> (length rendered) 0))))

(ert-deftest decklet-stats-test/chart-empty-returns-nil ()
  (should (null (decklet-stats--chart nil 4 60))))

;; -- decklet-stats--format-time ----------------------------------------------

(ert-deftest decklet-stats-test/format-time-iso ()
  (let ((s (decklet-stats--format-time "2026-04-13T09:12:00Z")))
    (should (stringp s))
    (should (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} " s))))

(ert-deftest decklet-stats-test/format-time-nil-returns-dash ()
  (should (equal "—" (decklet-stats--format-time nil))))

(ert-deftest decklet-stats-test/format-time-garbage-returns-input ()
  (should (equal "not-a-time" (decklet-stats--format-time "not-a-time"))))

(provide 'decklet-stats-test)

;;; decklet-stats-test.el ends here
