;;; decklet-cloze-test.el --- Tests for decklet-cloze -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-cloze)

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

(ert-deftest decklet-cloze-test/eligibility-requires-marker-and-predicate ()
  (let ((card (lambda (hint stability)
                (list :hint hint
                      :meta (make-decklet-card-meta
                             :stability stability)))))
    (should (decklet-cloze--eligible-p (funcall card "an *egret*" 21)))
    (should-not (decklet-cloze--eligible-p (funcall card "an *egret*" 20)))
    (should-not (decklet-cloze--eligible-p (funcall card "a wading bird" 99)))
    (should-not (decklet-cloze--eligible-p (funcall card nil 99)))
    (should-not (decklet-cloze--eligible-p (funcall card "an *egret*" nil)))
    (let ((decklet-cloze-predicate (lambda (_card) t)))
      (should (decklet-cloze--eligible-p
               (funcall card "an *egret*" 1))))))

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

(ert-deftest decklet-cloze-test/empty-marker-match-is-rejected ()
  (should-error
   (decklet-cloze--mask-matches "word" "\\(\\)" 1)
   :type 'user-error))

(ert-deftest decklet-cloze-test/folded-comparison-preserves-match-data ()
  (string-match "b" "abc")
  (let ((before (match-data)))
    (should (decklet-cloze-default-compare "strasse" "straße"))
    (should (equal before (match-data)))))

(ert-deftest decklet-cloze-test/second-attempt-accepts-a-marked-answer ()
  (let ((decklet-current-card-id 7)
        (decklet-cloze--presentation
         '(:word "_______" :hint "a clue"
                 :answers ("secrete" "secreted")))
        (decklet-cloze-attempts 2)
        (decklet-test-render-count 0)
        (inputs '("wrong" "secreted"))
        prompts)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt)
                 (push prompt prompts)
                 (pop inputs)))
              ((symbol-function 'message) #'ignore))
      (should (eq (decklet-cloze--read-answer 7) 'correct)))
    (should (= decklet-test-render-count 1))
    (should (= (length prompts) 2))))

(ert-deftest decklet-cloze-test/unlimited-attempts-continue-until-correct ()
  (let ((decklet-current-card-id 7)
        (decklet-cloze--presentation
         '(:word "_______" :hint "a clue" :answers ("secrete")))
        (decklet-cloze-attempts 0)
        (decklet-test-render-count 0)
        (inputs '("wrong" "still wrong" "secrete"))
        prompts)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt)
                 (push prompt prompts)
                 (pop inputs))))
      (let ((inhibit-message t))
        (should (eq (decklet-cloze--read-answer 7) 'correct))))
    (should (= (length prompts) 3))
    (should (= decklet-test-render-count 1))))

(ert-deftest decklet-cloze-test/result-labels-carry-expected-faces ()
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

(ert-deftest decklet-cloze-test/empty-input-or-quit-gives-up ()
  (dolist (reader (list (lambda (_prompt) "  ")
                        (lambda (_prompt) (signal 'quit nil))))
    (let ((decklet-current-card-id 7)
          (decklet-cloze--presentation
           '(:word "_______" :hint "a clue" :answers ("secrete")))
          (decklet-test-render-count 0))
      (cl-letf (((symbol-function 'read-string) reader)
                ((symbol-function 'message) #'ignore))
        (should (eq (decklet-cloze--read-answer 7) 'gave-up)))
      (should-not decklet-cloze--presentation)
      (should (= decklet-test-render-count 1)))))

(ert-deftest decklet-cloze-test/stale-answer-does-not-reveal-current-card ()
  (let* ((decklet-current-card-id 7)
         (new-presentation
          '(:word "___" :hint "a new clue" :answers ("new")))
         (decklet-cloze--presentation
          '(:word "_______" :hint "an old clue" :answers ("secrete")))
         (decklet-cloze-attempts 1)
         (decklet-test-render-count 0))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt)
                 (setq decklet-current-card-id 8
                       decklet-cloze--presentation new-presentation)
                 "wrong")))
      (let ((inhibit-message t))
        (should (eq (decklet-cloze--read-answer 7) 'incorrect))))
    (should (eq decklet-cloze--presentation new-presentation))
    (should (= decklet-test-render-count 0))))

(ert-deftest decklet-cloze-test/prompt-defers-while-minibuffer-is-active ()
  (let ((decklet-current-card-id 7)
        rescheduled-p
        read-card-id)
    (with-temp-buffer
      (setq-local decklet-cloze--presentation
                  '(:word "____" :hint "a clue" :answers ("word")))
      (cl-letf (((symbol-function 'active-minibuffer-window)
                 (lambda () t))
                ((symbol-function 'decklet-cloze--schedule-prompt)
                 (lambda (&optional _delay)
                   (setq rescheduled-p t)))
                ((symbol-function 'decklet-cloze--read-answer)
                 (lambda (card-id)
                   (setq read-card-id card-id))))
        (decklet-cloze--prompt-card (current-buffer) 7))
      (should rescheduled-p)
      (should-not read-card-id))))

(ert-deftest decklet-cloze-test/same-card-is-not-armed-twice ()
  (let ((decklet-current-card-id 7)
        (decklet-cloze--seen-card-ids nil)
        (decklet-cloze--presentation nil)
        (decklet-test-card
         (list :word "egret"
               :hint "an *egret*"
               :meta (make-decklet-card-meta :stability 21)))
        (arm-count 0))
    (cl-letf (((symbol-function 'decklet-cloze--arm-card)
               (lambda (_card)
                 (setq arm-count (1+ arm-count)
                       decklet-cloze--presentation :armed))))
      (decklet-cloze--on-next-card)
      (should (= arm-count 1))
      (should (equal decklet-cloze--seen-card-ids '(7)))
      (should (eq decklet-cloze--presentation :armed))
      (decklet-cloze--on-next-card)
      (should (= arm-count 1))
      (should-not decklet-cloze--presentation))))

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
