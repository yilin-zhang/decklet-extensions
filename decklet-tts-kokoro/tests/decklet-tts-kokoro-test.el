;;; decklet-tts-kokoro-test.el --- Tests for Decklet Kokoro TTS -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." test-dir))
  (add-to-list 'load-path test-dir))

(require 'decklet-tts-kokoro)

(ert-deftest manifest-path/follows-decklet-directory ()
  (let ((decklet-directory "/tmp/my-deck/")
        (decklet-tts-kokoro-manifest-file nil))
    (should (equal "/tmp/my-deck/kokoro.json"
                   (decklet-tts-kokoro-manifest-path)))))

(ert-deftest audio-path/uses-card-id ()
  (cl-letf (((symbol-function 'decklet-tts-kokoro-audio-dir)
             (lambda () "/tmp/kokoro-audio")))
    (should (equal "/tmp/kokoro-audio/42.mp3"
                   (decklet-tts-kokoro-audio-path 42)))))

(ert-deftest resolver/returns-existing-card-audio ()
  (let ((path (make-temp-file "decklet-kokoro-" nil ".mp3")))
    (unwind-protect
        (cl-letf (((symbol-function 'decklet-tts-kokoro-audio-path)
                   (lambda (_card-id) path)))
          (should (equal path (decklet-tts-kokoro-audio-resolver 42 "record"))))
      (delete-file path))))

(ert-deftest db-file/uses-decklet-configuration ()
  (let ((decklet-db-file "/custom/decklet.sqlite"))
    (should (equal "/custom/decklet.sqlite"
                   (decklet-tts-kokoro--db-file)))))

(ert-deftest runtime-args/contains-elisp-configuration ()
  (let ((decklet-tts-kokoro-model-directory "/models/kokoro")
        (decklet-tts-kokoro-voice "af_heart")
        (decklet-tts-kokoro-accent "en-us")
        (decklet-tts-kokoro-device "mps")
        (decklet-tts-kokoro-speed 0.9)
        (decklet-tts-kokoro-ffmpeg-command "ffmpeg")
        (decklet-tts-kokoro-trim-threshold "-50dB")
        (decklet-tts-kokoro-trim-keep 0.04))
    (let ((args (decklet-tts-kokoro--runtime-args)))
      (should (member "/models/kokoro" args))
      (should (member "af_heart" args))
      (should (member "en-us" args))
      (should (member "0.9" args))
      (should (member "--trim-threshold=-50dB" args))
      (should (member "0.04" args)))))

(ert-deftest base-args/uses-card-sidecar-paths ()
  (cl-letf (((symbol-function 'decklet-tts-kokoro--db-file)
             (lambda () "/deck/decklet.sqlite"))
            ((symbol-function 'decklet-tts-kokoro-manifest-path)
             (lambda () "/deck/kokoro.json"))
            ((symbol-function 'decklet-tts-kokoro-audio-dir)
             (lambda () "/deck/audio-cache/tts-kokoro")))
    (let ((args (decklet-tts-kokoro--base-args "scan")))
      (should (equal "--offline" (nth 1 args)))
      (should (equal "scan" (nth 3 args)))
      (should (member "/deck/kokoro.json" args))
      (should (member "/deck/audio-cache/tts-kokoro" args)))))

(ert-deftest stale-hook/batches-all-renames-in-one-command ()
  (let (captured)
    (cl-letf (((symbol-function 'decklet-tts-kokoro--start)
               (lambda (name args message &optional _show-log)
                 (setq captured (list name args message)))))
      (decklet-tts-kokoro--stale-renamed-cards
       '((:card-id 1 :new-word "recorded")
         (:card-id 2 :new-word "presented")))
      (should
       (equal '("--card-id" "1" "--word" "recorded"
                "--card-id" "2" "--word" "presented")
              (last (cadr captured) 8))))))

(ert-deftest sync/includes-runtime-and-dry-run-arguments ()
  (let (captured)
    (cl-letf (((symbol-function 'decklet-tts-kokoro--start)
               (lambda (name args message &optional _show-log)
                 (setq captured (list name args message)))))
      (decklet-tts-kokoro-sync t)
      (should (member "--model-dir" (cadr captured)))
      (should (member "--trim-threshold=-55dB" (cadr captured)))
      (should (member "--dry-run" (cadr captured))))))

(provide 'decklet-tts-kokoro-test)

;;; decklet-tts-kokoro-test.el ends here
