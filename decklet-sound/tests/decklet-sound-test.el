;;; decklet-sound-test.el --- ERT tests for decklet-sound -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-sound)

;;; decklet-sound-audio-dir

(ert-deftest audio-dir/falls-back-to-decklet-directory ()
  (let ((decklet-sound-audio-directory nil)
        (decklet-directory "/my/decklet/"))
    (should (string-suffix-p "audio-cache/tts-edge" (decklet-sound-audio-dir)))))

(ert-deftest audio-dir/uses-override-when-set ()
  (let ((decklet-sound-audio-directory "/custom/audio"))
    (should (equal (expand-file-name "/custom/audio") (decklet-sound-audio-dir)))))

;;; decklet-sound-audio-path

(ert-deftest audio-path/encodes-space-in-word ()
  (cl-letf (((symbol-function 'decklet-sound-audio-dir) (lambda () "/audio")))
    (should (string-suffix-p "hello%20world.mp3" (decklet-sound-audio-path "hello world")))))

(ert-deftest audio-path/plain-word-unchanged ()
  (cl-letf (((symbol-function 'decklet-sound-audio-dir) (lambda () "/audio")))
    (should (string-suffix-p "pitch.mp3" (decklet-sound-audio-path "pitch")))))

(ert-deftest audio-path/placed-under-audio-directory ()
  (cl-letf (((symbol-function 'decklet-sound-audio-dir) (lambda () "/audio")))
    (should (string-prefix-p "/audio/" (decklet-sound-audio-path "pitch")))))

;;; decklet-sound-audio-file (existence-aware)

(ert-deftest audio-file/returns-nil-when-missing ()
  (cl-letf (((symbol-function 'decklet-sound-audio-dir)
             (lambda () (expand-file-name "nonexistent" temporary-file-directory))))
    (should-not (decklet-sound-audio-file "pitch"))))

(provide 'decklet-sound-test)

;;; decklet-sound-test.el ends here
