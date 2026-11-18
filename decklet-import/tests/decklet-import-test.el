;;; decklet-import-test.el --- ERT tests for decklet-import -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-import)

;;; Kindle row → batch lines

(ert-deftest decklet-import-test/kindle-rows-to-batch-lines-with-usage ()
  "Each stem gets its usages as hints, in first-seen order, once each.
A lowercase word is highlighted in any case; any other word only in
its own case.  A lookup without context adds no hint."
  (let ((decklet-import-kindle-usage t))
    (should
     (equal (decklet-import-kindle--rows->batch-lines
             '(("lucid" "lucid" "A lucid dream")
               ("dirt" "dirt" "Dirt road")
               ("lucid" "lucid" "Lucid writing")
               ("lucid" "lucid" "A lucid dream")
               ("iphone" "iPhone" "Iphone iPhone IPHONE")
               ("bare" "bare" "")))
            '("lucid"
              "# A *lucid* dream"
              "# *Lucid* writing"
              "dirt"
              "# *Dirt* road"
              "iphone"
              "# Iphone *iPhone* IPHONE"
              "bare")))))

(ert-deftest decklet-import-test/kindle-rows-to-batch-lines-without-usage ()
  (let ((decklet-import-kindle-usage nil))
    (should
     (equal (decklet-import-kindle--rows->batch-lines
             '(("lucid" "lucid" "A lucid dream")
               ("dirt" "dirt" "soil")))
            '("lucid" "dirt")))))

;;; Kindle read-rows delimiter parsing

(ert-deftest decklet-import-test/kindle-read-rows-either-delimiter ()
  "Some sqlite3 builds print char(31) raw, others as caret notation."
  (dolist (sep (list (string 31) "^_"))
    (cl-letf (((symbol-function 'decklet-import--sqlite-call)
               (lambda (&rest _)
                 (concat "lunge" sep "lunge" sep "example one\n"
                         "parry" sep "parry" sep "example two\n"))))
      (should (equal (decklet-import-kindle--read-rows "dummy.db")
                     '(("lunge" "lunge" "example one")
                       ("parry" "parry" "example two")))))))

(provide 'decklet-import-test)
;;; decklet-import-test.el ends here
