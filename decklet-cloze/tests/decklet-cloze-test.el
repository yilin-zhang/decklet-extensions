;;; decklet-cloze-test.el --- Tests for decklet-cloze -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-cloze)

(ert-deftest decklet-cloze-test/default-marker-collects-multiple-answers ()
  (should
   (equal (decklet-cloze--prepare
           "secrete" "It *secretes* and was *secreted*.")
          '(:hint "It *________* and was *________*."
                  :answers ("secrete" "secretes" "secreted")))))

(ert-deftest decklet-cloze-test/custom-marker-preserves-delimiters ()
  (let ((decklet-cloze-marker-regexp "{{\\([^}\n]+\\)}}"))
    (should
     (equal (decklet-cloze--prepare "choose" "{{chose}} or {{chosen}}")
            '(:hint "{{_____}} or {{______}}"
                    :answers ("choose" "chose" "chosen"))))))

(ert-deftest decklet-cloze-test/bare-inflection-is-masked-and-accepted ()
  (should
   (equal (decklet-cloze--prepare
           "secrete" "Insulin is secreted in response to glucose.")
          '(:hint "Insulin is ________ in response to glucose."
                  :answers ("secrete" "secreted")))))

(ert-deftest decklet-cloze-test/word-is-accepted-when-hint-has-no-answer ()
  (should
   (equal (decklet-cloze--prepare "egret" "a long-legged wading bird")
          '(:hint "a long-legged wading bird"
                  :answers ("egret")))))

(ert-deftest decklet-cloze-test/default-predicate-accepts-mature-card ()
  (let ((card (list :word "egret"
                    :hint "an *egret*"
                    :meta (make-decklet-card-meta :stability 21))))
    (should (decklet-cloze--eligible-p card))))

(ert-deftest decklet-cloze-test/custom-predicate-enables-card ()
  (let ((card (list :word "egret"
                    :hint "an *egret*"
                    :meta (make-decklet-card-meta :stability 1)))
        (decklet-cloze-predicate (lambda (_card) t)))
    (should (decklet-cloze--eligible-p card))))

(ert-deftest decklet-cloze-test/default-comparison-trims-and-folds-case ()
  (should (decklet-cloze-default-compare "  Secreted " "secreted")))

(ert-deftest decklet-cloze-test/default-comparison-folds-diacritics ()
  (dolist (input '("facade" "FACADE" "façade"))
    (should (decklet-cloze-default-compare input "façade")))
  (should (decklet-cloze-default-compare "strasse" "straße")))

(ert-deftest decklet-cloze-test/default-comparison-normalizes-scripts ()
  (should (decklet-cloze-default-compare "test" "ᵀᴱˢᵀ"))
  (should (decklet-cloze-default-compare "facade" "façade²"))
  (should-not (decklet-cloze-default-compare "ratio" "ratio½")))

(ert-deftest decklet-cloze-test/default-comparison-allows-hyphen-variants ()
  (dolist (input '("topsy-turvy" "topsy–turvy" "topsy⸺turvy"
                   "topsy−turvy" "topsy turvy" "topsyturvy"
                   "  TOPSY TURVY  "))
    (should (decklet-cloze-default-compare input "topsy-turvy")))
  (should-not (decklet-cloze-default-compare "secret ed" "secreted")))

(ert-deftest decklet-cloze-test/bare-match-normalizes-and-ignores-case ()
  (should
   (equal (decklet-cloze--prepare
           "Façade²" "The *facade* hid a FAÇADE and another FACADE.")
          '(:hint "The *______* hid a ______ and another ______."
                  :answers ("Façade²" "facade" "FAÇADE" "FACADE")))))

(ert-deftest decklet-cloze-test/retry-accepts-a-marked-answer ()
  (let ((decklet-current-card-id 7)
        (decklet-cloze--presentation
         '(:word "_______" :hint "a clue"
                 :answers ("secrete" "secreted")))
        (decklet-cloze-attempts 2)
        (decklet-test-render-count 0)
        (inputs '("wrong" "secreted"))
        prompts
        final-message)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt)
                 (push prompt prompts)
                 (pop inputs)))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (setq final-message (apply #'format format-string args)))))
      (should (eq (decklet-cloze--read-answer 7) 'correct)))
    (should (= decklet-test-render-count 1))
    (should (= (length prompts) 2))
    (should (string-match-p "correct" final-message))
    (should (eq (get-text-property
                 (string-match "correct" final-message) 'face final-message)
                'decklet-cloze-correct-face))))

(ert-deftest decklet-cloze-test/result-labels-have-distinct-faces ()
  (dolist (case '((correct "correct" decklet-cloze-correct-face)
                  (incorrect "incorrect" decklet-cloze-incorrect-face)
                  (gave-up "gave up" decklet-cloze-gave-up-face)))
    (let ((label (decklet-cloze--result-label (car case))))
      (should (equal label (cadr case)))
      (should (eq (get-text-property 0 'face label) (caddr case))))))

(ert-deftest decklet-cloze-test/default-one-attempt-reveals-on-failure ()
  (let ((decklet-current-card-id 7)
        (decklet-cloze--presentation
         '(:word "_______" :hint "a clue" :answers ("secrete")))
        (decklet-cloze-attempts 1)
        (decklet-test-render-count 0))
    (cl-letf (((symbol-function 'read-string) (lambda (_prompt) "wrong"))
              ((symbol-function 'message) #'ignore))
      (should (eq (decklet-cloze--read-answer 7) 'incorrect)))
    (should (= decklet-test-render-count 1))))

(ert-deftest decklet-cloze-test/mode-preserves-local-components-when-disabled ()
  (let ((decklet-current-card-id nil)
        (fixed decklet-review-fixed-components)
        (floating decklet-review-floating-components))
    (with-temp-buffer
      (decklet-review-mode)
      (setq-local decklet-review-fixed-components
                  '(before decklet-review-component-word after))
      (setq-local decklet-review-floating-components
                  '(decklet-review-component-hint extra))
      (decklet-cloze-mode 1)
      (setq decklet-cloze--presentation
            '(:word "_____" :hint "a clue" :answers ("word")))
      (should (equal (funcall (nth 1 decklet-review-fixed-components))
                     "_____"))
      (decklet-cloze-mode -1)
      (should (equal decklet-review-fixed-components
                     '(before decklet-review-component-word after)))
      (should (equal decklet-review-floating-components
                     '(decklet-review-component-hint extra))))
    (should (equal decklet-review-fixed-components fixed))
    (should (equal decklet-review-floating-components floating))))

(provide 'decklet-cloze-test)
;;; decklet-cloze-test.el ends here
