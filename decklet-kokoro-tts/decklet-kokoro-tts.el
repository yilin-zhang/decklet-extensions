;;; decklet-kokoro-tts.el --- Local Kokoro TTS for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (decklet-sound "0.1.0"))
;; Keywords: multimedia, tools

;;; Commentary:

;; Generate per-card English pronunciation audio locally with Kokoro.
;; Pronunciation decisions live in decklet-directory/kokoro.json and
;; audio lives in audio-cache/tts-kokoro/<card-id>.mp3.  Playback is
;; provided by decklet-sound; this package registers a card-ID-aware
;; resolver ahead of the legacy Edge TTS word cache.

;;; Code:

(require 'subr-x)
(require 'decklet)
(require 'decklet-sound)

(defgroup decklet-kokoro-tts nil
  "Local Kokoro pronunciation generation for Decklet."
  :group 'multimedia)

(defcustom decklet-kokoro-tts-project-directory
  (file-name-directory
   (or load-file-name (locate-library "decklet-kokoro-tts") default-directory))
  "Directory containing the decklet-kokoro-tts project."
  :type 'directory
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-model-directory "~/Models/Kokoro-82M/"
  "Directory containing the local Kokoro model and voices."
  :type 'directory
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-manifest-file nil
  "Pronunciation sidecar file.
When nil, use kokoro.json under `decklet-directory'."
  :type '(choice (const :tag "Use decklet-directory/kokoro.json" nil) file)
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-audio-directory nil
  "Directory containing Kokoro audio keyed by Decklet card ID.
When nil, use audio-cache/tts-kokoro under `decklet-directory'."
  :type '(choice (const :tag "Use decklet-directory" nil) directory)
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-command "uv"
  "Command used to invoke the Python project."
  :type 'string
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-cli-name "decklet-kokoro-tts"
  "Python CLI entrypoint invoked through `decklet-kokoro-tts-command'."
  :type 'string
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-accent "en-us"
  "English accent used for automatic grapheme-to-phoneme conversion."
  :type '(choice (const "en-us") (const "en-gb"))
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-voice "af_heart"
  "Kokoro voice name or absolute voice .pt file."
  :type 'string
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-device "mps"
  "Torch device used for Kokoro inference."
  :type '(choice (const "mps") (const "cpu"))
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-speed 1.0
  "Kokoro speech speed multiplier."
  :type 'number
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-ffmpeg-command "ffmpeg"
  "FFmpeg executable used to encode generated MP3 files."
  :type 'string
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-trim-threshold "-55dB"
  "Silence threshold used to trim the beginning of generated audio."
  :type 'string
  :group 'decklet-kokoro-tts)

(defcustom decklet-kokoro-tts-trim-keep 0.03
  "Seconds of leading silence retained after onset trimming."
  :type 'number
  :group 'decklet-kokoro-tts)

(defvar decklet-kokoro-tts--buffer-name "*Decklet Kokoro TTS*"
  "Buffer used for Kokoro subprocess output.")

(defun decklet-kokoro-tts-manifest-path ()
  "Return the active Decklet Kokoro pronunciation manifest path."
  (expand-file-name
   (or decklet-kokoro-tts-manifest-file
       (expand-file-name "kokoro.json" decklet-directory))))

(defun decklet-kokoro-tts-audio-dir ()
  "Return the active Decklet Kokoro audio directory."
  (expand-file-name
   (or decklet-kokoro-tts-audio-directory
       (expand-file-name "audio-cache/tts-kokoro" decklet-directory))))

(defun decklet-kokoro-tts-audio-path (card-id)
  "Return the Kokoro audio path for CARD-ID."
  (expand-file-name (format "%s.mp3" card-id)
                    (decklet-kokoro-tts-audio-dir)))

(defun decklet-kokoro-tts-audio-resolver (card-id _word)
  "Return existing Kokoro audio for CARD-ID.
WORD is accepted for the `decklet-sound' resolver contract."
  (when card-id
    (decklet-kokoro-tts-audio-path card-id)))

(defun decklet-kokoro-tts--db-file ()
  "Return the active Decklet SQLite database path."
  (expand-file-name decklet-db-file))

(defun decklet-kokoro-tts--command-args (subcommand)
  "Return the uv invocation prefix for SUBCOMMAND."
  (list "run" "--offline" decklet-kokoro-tts-cli-name subcommand))

(defun decklet-kokoro-tts--sidecar-args ()
  "Return CLI arguments for the active manifest and audio directory."
  (list "--manifest" (decklet-kokoro-tts-manifest-path)
        "--out-dir" (decklet-kokoro-tts-audio-dir)))

(defun decklet-kokoro-tts--base-args (subcommand)
  "Return common CLI arguments for SUBCOMMAND."
  (append (decklet-kokoro-tts--command-args subcommand)
          (list "--db" (decklet-kokoro-tts--db-file))
          (decklet-kokoro-tts--sidecar-args)
          (when (equal subcommand "scan")
            (list "--accent" decklet-kokoro-tts-accent))))

(defun decklet-kokoro-tts--runtime-args ()
  "Return CLI arguments describing local Kokoro runtime settings."
  (list "--model-dir" (expand-file-name decklet-kokoro-tts-model-directory)
        "--voice" decklet-kokoro-tts-voice
        "--accent" decklet-kokoro-tts-accent
        "--device" decklet-kokoro-tts-device
        "--speed" (number-to-string decklet-kokoro-tts-speed)
        "--ffmpeg" decklet-kokoro-tts-ffmpeg-command
        "--trim-threshold" decklet-kokoro-tts-trim-threshold
        "--trim-keep" (number-to-string decklet-kokoro-tts-trim-keep)))

(defun decklet-kokoro-tts--start (name args success-message)
  "Start subprocess NAME with ARGS and report SUCCESS-MESSAGE."
  (let* ((default-directory
          (file-name-as-directory
           (expand-file-name decklet-kokoro-tts-project-directory)))
         (buffer (get-buffer-create decklet-kokoro-tts--buffer-name))
         (active (get-process name)))
    (when (and active (process-live-p active))
      (user-error "%s is already running" name))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert (format "\n[%s] %s %s\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")
                      decklet-kokoro-tts-command
                      (mapconcat #'shell-quote-argument args " "))))
    (let ((process (apply #'start-process name buffer
                          decklet-kokoro-tts-command args)))
      (set-process-query-on-exit-flag process nil)
      (set-process-sentinel
       process
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (if (= 0 (process-exit-status proc))
               (message "%s" success-message)
             (message "Decklet Kokoro command failed (code %d)"
                      (process-exit-status proc))
             (display-buffer (process-buffer proc))))))
      process)))

(defun decklet-kokoro-tts--current-card ()
  "Return a cons of current Decklet card ID and word."
  (let* ((word (decklet-prompt-word "Word: "))
         (card-id (decklet-get-card-id-by-word word)))
    (unless card-id
      (user-error "No active Decklet card for %s" word))
    (cons card-id word)))

;;;###autoload
(defun decklet-kokoro-tts-install ()
  "Create or update the plugin-local Python environment with uv."
  (interactive)
  (unless (executable-find decklet-kokoro-tts-command)
    (user-error "%s executable not found" decklet-kokoro-tts-command))
  (decklet-kokoro-tts--start
   "decklet-kokoro-tts-install"
   (list "sync")
   "Decklet Kokoro environment is ready"))

;;;###autoload
(defun decklet-kokoro-tts-generate-word (&optional prompt-for-pronunciation)
  "Generate Kokoro audio for the current card.
With prefix argument PROMPT-FOR-PRONUNCIATION, ask for an optional
Kokoro/Misaki phoneme override.  Empty input uses automatic G2P."
  (interactive "P")
  (pcase-let* ((`(,card-id . ,word) (decklet-kokoro-tts--current-card))
               (pronunciation
                (when prompt-for-pronunciation
                  (string-trim
                   (read-string
                    (format "Pronunciation for %s (empty for automatic): " word)))))
               (args
                (append
                 (decklet-kokoro-tts--base-args "generate")
                 (list "--card-id" (number-to-string card-id))
                 (decklet-kokoro-tts--runtime-args)
                 (when (and pronunciation (not (string-empty-p pronunciation)))
                   (list "--pronunciation" pronunciation)))))
    (decklet-kokoro-tts--start
     "decklet-kokoro-tts-generate"
     args
     (format "Generated Kokoro audio for %s" word))))

;;;###autoload
(defun decklet-kokoro-tts-sync ()
  "Reconcile Kokoro manifest and audio with the active Decklet DB."
  (interactive)
  (decklet-kokoro-tts--start
   "decklet-kokoro-tts-sync"
   (decklet-kokoro-tts--base-args "sync")
   "Decklet Kokoro sidecar synchronized"))

;;;###autoload
(defun decklet-kokoro-tts-trim-audio ()
  "Trim excess leading silence from all generated Kokoro audio."
  (interactive)
  (decklet-kokoro-tts--start
   "decklet-kokoro-tts-trim"
   (append
    (decklet-kokoro-tts--command-args "trim")
    (list
         "--out-dir" (decklet-kokoro-tts-audio-dir)
         "--ffmpeg" decklet-kokoro-tts-ffmpeg-command
         "--trim-threshold" decklet-kokoro-tts-trim-threshold
         "--trim-keep" (number-to-string decklet-kokoro-tts-trim-keep)))
   "Trimmed leading silence from Kokoro audio"))

(defun decklet-kokoro-tts--remove-cards (events)
  "Remove Kokoro data for deleted cards described by EVENTS."
  (when events
    (let ((args
           (append
            (decklet-kokoro-tts--command-args "remove")
            (decklet-kokoro-tts--sidecar-args)
            (mapcan
             (lambda (event)
               (list "--card-id"
                     (number-to-string (plist-get event :card-id))))
             events))))
      (decklet-kokoro-tts--start
       "decklet-kokoro-tts-remove"
       args
       "Removed deleted cards from Kokoro sidecar"))))

(defun decklet-kokoro-tts--stale-renamed-cards (events)
  "Mark renamed cards in EVENTS stale and discard their old audio."
  (when events
    (decklet-kokoro-tts--start
     "decklet-kokoro-tts-stale"
     (append
      (decklet-kokoro-tts--command-args "stale")
      (decklet-kokoro-tts--sidecar-args)
      (mapcan
       (lambda (event)
         (list "--card-id"
               (number-to-string (plist-get event :card-id))
               "--word"
               (plist-get event :new-word)))
       events))
     (format "Marked %d Kokoro pronunciation%s stale"
             (length events)
             (if (= (length events) 1) "" "s")))))

(add-hook 'decklet-sound-audio-resolver-functions
          #'decklet-kokoro-tts-audio-resolver)
(add-hook 'decklet-cards-deleted-functions
          #'decklet-kokoro-tts--remove-cards)
(add-hook 'decklet-cards-renamed-functions
          #'decklet-kokoro-tts--stale-renamed-cards)

(provide 'decklet-kokoro-tts)

;;; decklet-kokoro-tts.el ends here
