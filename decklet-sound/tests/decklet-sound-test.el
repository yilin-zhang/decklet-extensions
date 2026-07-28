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
  (let ((decklet-sound-audio-resolver-functions nil))
    (cl-letf (((symbol-function 'decklet-sound-audio-dir)
               (lambda () (expand-file-name "nonexistent" temporary-file-directory))))
      (should-not (decklet-sound-audio-file "pitch")))))

(ert-deftest audio-file/prefers-ordered-resolver ()
  (let* ((file (make-temp-file "decklet-sound-resolver-" nil ".mp3"))
         (calls nil)
         (decklet-sound-audio-resolver-functions
          (list (lambda (card-id word)
                  (push (list card-id word) calls)
                  file))))
    (unwind-protect
        (progn
          (should (equal file (decklet-sound-audio-file "pitch" 42)))
          (should (equal '((42 "pitch")) calls)))
      (delete-file file))))

(ert-deftest audio-file/falls-back-after-missing-resolver ()
  (let* ((legacy (make-temp-file "decklet-sound-legacy-" nil ".mp3"))
         (decklet-sound-audio-resolver-functions (list (lambda (_id _word) nil))))
    (unwind-protect
        (cl-letf (((symbol-function 'decklet-sound-audio-path)
                   (lambda (_word) legacy)))
          (should (equal legacy (decklet-sound-audio-file "pitch" 42))))
      (delete-file legacy))))

(ert-deftest audio-file/resolver-error-does-not-block-fallback ()
  (let* ((legacy (make-temp-file "decklet-sound-error-" nil ".mp3"))
         (decklet-sound-audio-resolver-functions
          (list (lambda (_id _word) (error "boom")))))
    (unwind-protect
        (cl-letf (((symbol-function 'decklet-sound-audio-path)
                   (lambda (_word) legacy))
                  ((symbol-function 'display-warning) #'ignore))
          (should (equal legacy (decklet-sound-audio-file "pitch" 42))))
      (delete-file legacy))))

;;; mpv daemon

(ert-deftest mpv-ensure/keeps-audio-output-open-between-clips ()
  (let ((decklet-sound--mpv-process nil)
        (decklet-sound-mpv-socket "/tmp/decklet-sound-test.sock")
        command)
    (cl-letf (((symbol-function 'executable-find) (lambda (_program) "/opt/homebrew/bin/mpv"))
              ((symbol-function 'file-exists-p) (lambda (_path) t))
              ((symbol-function 'make-process)
               (lambda (&rest args)
                 (setq command (plist-get args :command))
                 'decklet-sound-test-process)))
      (decklet-sound--mpv-ensure)
      (should (member "--keep-open=yes" command))
      (should (member "--audio-stream-silence=yes" command))
      (should (member "--gapless-audio=yes" command)))))

(ert-deftest mpv-player/resets-idle-cleanup-timer ()
  (let ((old-timer 'old-timer)
        (new-timer 'new-timer)
        (decklet-sound--mpv-idle-timer 'old-timer)
        (decklet-sound-mpv-idle-timeout 60)
        cancelled scheduled)
    (cl-letf (((symbol-function 'decklet-sound--mpv-ensure) #'ignore)
              ((symbol-function 'decklet-sound--mpv-send) #'ignore)
              ((symbol-function 'timerp) (lambda (timer) (eq timer old-timer)))
              ((symbol-function 'cancel-timer)
               (lambda (timer) (setq cancelled timer)))
              ((symbol-function 'run-at-time)
               (lambda (seconds repeat function)
                 (setq scheduled (list seconds repeat function))
                 new-timer)))
      (decklet-sound-mpv-player "/audio/pitch.mp3")
      (should (eq cancelled old-timer))
      (should (equal (seq-take scheduled 2) '(60 nil)))
      (should (functionp (nth 2 scheduled)))
      (should (eq decklet-sound--mpv-idle-timer new-timer)))))

(ert-deftest mpv-player/nil-timeout-keeps-session-daemon ()
  (let ((decklet-sound--mpv-idle-timer nil)
        (decklet-sound-mpv-idle-timeout nil)
        scheduled)
    (cl-letf (((symbol-function 'decklet-sound--mpv-ensure) #'ignore)
              ((symbol-function 'decklet-sound--mpv-send) #'ignore)
              ((symbol-function 'run-at-time)
               (lambda (&rest _args) (setq scheduled t))))
      (decklet-sound-mpv-player "/audio/pitch.mp3")
      (should-not scheduled)
      (should-not decklet-sound--mpv-idle-timer))))

(provide 'decklet-sound-test)

;;; decklet-sound-test.el ends here
