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

;;; decklet-sound-audio-file

(defmacro decklet-sound-test--with-audio-dir (&rest body)
  "Run BODY with `decklet-sound-audio-directory' at a fresh temp dir."
  (declare (indent 0))
  `(let ((decklet-sound-audio-directory (make-temp-file "decklet-sound-" t)))
     (unwind-protect (progn ,@body)
       (delete-directory decklet-sound-audio-directory t))))

(ert-deftest audio-file/falls-back-when-resolver-file-is-missing ()
  "A resolver path that does not exist yet falls through to the cache.
Kokoro's resolver returns its path without checking that it exists."
  (decklet-sound-test--with-audio-dir
    (let ((decklet-sound-audio-resolver-functions
           (list (lambda (_id _word)
                   (expand-file-name "missing.mp3" decklet-sound-audio-directory)))))
      (with-temp-file (decklet-sound-audio-path 42))
      (should (equal (decklet-sound-audio-path 42) (decklet-sound-audio-file 42))))))

(ert-deftest audio-file/resolver-error-does-not-block-fallback ()
  (decklet-sound-test--with-audio-dir
    (let ((decklet-sound-audio-resolver-functions
           (list (lambda (_id _word) (error "boom")))))
      (with-temp-file (decklet-sound-audio-path 42))
      (cl-letf (((symbol-function 'display-warning) #'ignore))
        (should (equal (decklet-sound-audio-path 42)
                       (decklet-sound-audio-file 42)))))))

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
      (should (member "--keep-open-pause=no" command))
      (should (member "--audio-stream-silence=yes" command))
      (should (member "--gapless-audio=yes" command)))))

(ert-deftest mpv-player/resets-idle-cleanup-timer ()
  "Each clip restarts the idle countdown, so only the newest timer is live."
  (let ((decklet-sound--mpv-idle-timer nil)
        (decklet-sound-mpv-idle-timeout 60))
    (cl-letf (((symbol-function 'decklet-sound--mpv-ensure) #'ignore)
              ((symbol-function 'decklet-sound--mpv-send) #'ignore))
      (unwind-protect
          (progn
            (decklet-sound-mpv-player "/audio/a.mp3")
            (let ((first decklet-sound--mpv-idle-timer))
              (decklet-sound-mpv-player "/audio/b.mp3")
              (should (memq decklet-sound--mpv-idle-timer timer-list))
              (should-not (eq first decklet-sound--mpv-idle-timer))
              (should-not (memq first timer-list))))
        (cancel-timer decklet-sound--mpv-idle-timer)))))

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

(ert-deftest mpv-cleanup/forces-process-that-ignores-quit ()
  "A daemon that ignores the quit command is killed and forgotten."
  (let* ((process (make-process :name "decklet-sound-test" :command '("sleep" "30")))
         (decklet-sound--mpv-process process)
         (decklet-sound--mpv-idle-timer nil)
         (decklet-sound-mpv-socket
          (expand-file-name "decklet-sound-no-such.sock" temporary-file-directory)))
    (decklet-sound--mpv-cleanup)
    (should-not (process-live-p process))
    (should-not decklet-sound--mpv-process)))

(provide 'decklet-sound-test)

;;; decklet-sound-test.el ends here
