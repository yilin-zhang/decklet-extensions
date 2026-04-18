;;; decklet-import-test.el --- ERT tests for decklet-import -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-import)

;;; Kindle row → batch lines

(ert-deftest decklet-import-test/kindle-rows-to-batch-lines-with-usage ()
  (let ((decklet-import-kindle-usage t))
    (should
     (equal (decklet-import-kindle--rows->batch-lines
             '(("lucid" "lucid" "A lucid dream")
               ("lucid" "lucid" "Lucid writing")
               ("dirt" "dirt" "Dirt road")))
            '("lucid"
              "# A *lucid* dream"
              "# *Lucid* writing"
              "dirt"
              "# *Dirt* road")))))

(ert-deftest decklet-import-test/kindle-rows-to-batch-lines-without-usage ()
  (let ((decklet-import-kindle-usage nil))
    (should
     (equal (decklet-import-kindle--rows->batch-lines
             '(("lucid" "lucid" "A lucid dream")
               ("dirt" "dirt" "soil")))
            '("lucid" "dirt")))))

;;; Kindle read-rows — delimiter parsing

(ert-deftest decklet-import-test/kindle-read-rows-delimited-output ()
  (cl-letf (((symbol-function 'decklet-import--sqlite-call)
             (lambda (&rest _)
               (let ((sep (string 31)))
                 (concat "lunge" sep "lunge" sep "example one\n"
                         "parry" sep "parry" sep "example two\n")))))
    (should (equal (decklet-import-kindle--read-rows "dummy.db")
                   '(("lunge" "lunge" "example one")
                     ("parry" "parry" "example two"))))))

(ert-deftest decklet-import-test/kindle-read-rows-caret-delimited-output ()
  (cl-letf (((symbol-function 'decklet-import--sqlite-call)
             (lambda (&rest _)
               (concat "lunge^_lunge^_example one\n"
                       "parry^_parry^_example two\n"))))
    (should (equal (decklet-import-kindle--read-rows "dummy.db")
                   '(("lunge" "lunge" "example one")
                     ("parry" "parry" "example two"))))))

;;; Kindle highlight case semantics

(ert-deftest decklet-import-test/kindle-highlight-lowercase-case-insensitive ()
  (should
   (equal (decklet-import-kindle--highlight-usage-word
           "Apple apple APPLE"
           "apple")
          "*Apple* *apple* *APPLE*")))

(ert-deftest decklet-import-test/kindle-highlight-uppercase-exact-match ()
  (should
   (equal (decklet-import-kindle--highlight-usage-word
           "Iphone iPhone IPHONE"
           "iPhone")
          "Iphone *iPhone* IPHONE")))

(provide 'decklet-import-test)
;;; decklet-import-test.el ends here
