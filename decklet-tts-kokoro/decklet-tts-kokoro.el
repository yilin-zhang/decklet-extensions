;;; decklet-tts-kokoro.el --- Local Kokoro TTS for Decklet -*- lexical-binding: t; -*-

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

(defgroup decklet-tts-kokoro nil
  "Local Kokoro pronunciation generation for Decklet."
  :group 'multimedia)

(defcustom decklet-tts-kokoro-project-directory
  (file-name-directory
   (or load-file-name (locate-library "decklet-tts-kokoro") default-directory))
  "Directory containing the decklet-tts-kokoro project."
  :type 'directory
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-model-directory "~/Models/Kokoro-82M/"
  "Directory containing the local Kokoro model and voices."
  :type 'directory
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-manifest-file nil
  "Pronunciation sidecar file.
When nil, use kokoro.json under `decklet-directory'."
  :type '(choice (const :tag "Use decklet-directory/kokoro.json" nil) file)
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-audio-directory nil
  "Directory containing Kokoro audio keyed by Decklet card ID.
When nil, use audio-cache/tts-kokoro under `decklet-directory'."
  :type '(choice (const :tag "Use decklet-directory" nil) directory)
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-command "uv"
  "Command used to invoke the Python project."
  :type 'string
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-cli-name "decklet-tts-kokoro"
  "Python CLI entrypoint invoked through `decklet-tts-kokoro-command'."
  :type 'string
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-accent "en-us"
  "English accent used for automatic grapheme-to-phoneme conversion."
  :type '(choice (const "en-us") (const "en-gb"))
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-voice "af_heart"
  "Kokoro voice name or absolute voice .pt file."
  :type 'string
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-device "mps"
  "Torch device used for Kokoro inference."
  :type '(choice (const "mps") (const "cpu"))
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-speed 1.0
  "Kokoro speech speed multiplier."
  :type 'number
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-ffmpeg-command "ffmpeg"
  "FFmpeg executable used to encode generated MP3 files."
  :type 'string
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-trim-threshold "-55dB"
  "Silence threshold used to trim the beginning of generated audio."
  :type 'string
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-trim-keep 0.03
  "Seconds of leading silence retained after onset trimming."
  :type 'number
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-display-log t
  "Whether long-running commands pop up the Kokoro log buffer.
Generation runs asynchronously and can take many minutes; the log
reports every card as it is finished, so showing it is the only
feedback on how far along a batch is.  Short bookkeeping commands
never display it regardless of this setting."
  :type 'boolean
  :group 'decklet-tts-kokoro)

(defvar decklet-tts-kokoro--buffer-name "*Decklet Kokoro TTS*"
  "Buffer used for Kokoro subprocess output.")

(defun decklet-tts-kokoro-manifest-path ()
  "Return the active Decklet Kokoro pronunciation manifest path."
  (expand-file-name
   (or decklet-tts-kokoro-manifest-file
       (expand-file-name "kokoro.json" decklet-directory))))

(defun decklet-tts-kokoro-audio-dir ()
  "Return the active Decklet Kokoro audio directory."
  (expand-file-name
   (or decklet-tts-kokoro-audio-directory
       (expand-file-name "audio-cache/tts-kokoro" decklet-directory))))

(defun decklet-tts-kokoro-audio-path (card-id)
  "Return the Kokoro audio path for CARD-ID."
  (expand-file-name (format "%s.mp3" card-id)
                    (decklet-tts-kokoro-audio-dir)))

(defun decklet-tts-kokoro-audio-resolver (card-id _word)
  "Return existing Kokoro audio for CARD-ID.
WORD is accepted for the `decklet-sound' resolver contract."
  (when card-id
    (decklet-tts-kokoro-audio-path card-id)))

(defun decklet-tts-kokoro--db-file ()
  "Return the active Decklet SQLite database path."
  (expand-file-name decklet-db-file))

(defun decklet-tts-kokoro--command-args (subcommand)
  "Return the uv invocation prefix for SUBCOMMAND."
  (list "run" "--offline" decklet-tts-kokoro-cli-name subcommand))

(defun decklet-tts-kokoro--sidecar-args ()
  "Return CLI arguments for the active manifest and audio directory."
  (list "--manifest" (decklet-tts-kokoro-manifest-path)
        "--out-dir" (decklet-tts-kokoro-audio-dir)))

(defun decklet-tts-kokoro--base-args (subcommand)
  "Return common CLI arguments for SUBCOMMAND."
  (append (decklet-tts-kokoro--command-args subcommand)
          (list "--db" (decklet-tts-kokoro--db-file))
          (decklet-tts-kokoro--sidecar-args)
          (when (equal subcommand "scan")
            (list "--accent" decklet-tts-kokoro-accent))))

(defun decklet-tts-kokoro--runtime-args ()
  "Return CLI arguments describing local Kokoro runtime settings."
  (list "--model-dir" (expand-file-name decklet-tts-kokoro-model-directory)
        "--voice" decklet-tts-kokoro-voice
        "--accent" decklet-tts-kokoro-accent
        "--device" decklet-tts-kokoro-device
        "--speed" (number-to-string decklet-tts-kokoro-speed)
        "--ffmpeg" decklet-tts-kokoro-ffmpeg-command
        (format "--trim-threshold=%s" decklet-tts-kokoro-trim-threshold)
        "--trim-keep" (number-to-string decklet-tts-kokoro-trim-keep)))

(defun decklet-tts-kokoro--display-log (buffer)
  "Display BUFFER and keep its window scrolled to incoming output.
Does nothing when `decklet-tts-kokoro-display-log' is nil."
  (when decklet-tts-kokoro-display-log
    ;; Read when the buffer is put into a window, so it has to be set
    ;; before `display-buffer'.  It is what makes the window follow the
    ;; tail of the output instead of freezing where it was.
    (with-current-buffer buffer
      (setq-local window-point-insertion-type t))
    (let ((window (display-buffer buffer)))
      (when (window-live-p window)
        ;; The buffer is reused across runs, so window point can land in
        ;; the middle of an earlier run's output.
        (with-selected-window window
          (goto-char (point-max)))))))

(defun decklet-tts-kokoro--start (name args success-message &optional show-log)
  "Start subprocess NAME with ARGS and report SUCCESS-MESSAGE.
With SHOW-LOG non-nil, display the log buffer while the command runs
so its per-card progress lines are visible, subject to
`decklet-tts-kokoro-display-log'."
  (let* ((default-directory
          (file-name-as-directory
           (expand-file-name decklet-tts-kokoro-project-directory)))
         (buffer (get-buffer-create decklet-tts-kokoro--buffer-name))
         (active (get-process name)))
    (when (and active (process-live-p active))
      (user-error "%s is already running" name))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert (format "\n[%s] %s %s\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")
                      decklet-tts-kokoro-command
                      (mapconcat #'shell-quote-argument args " "))))
    (let ((process (apply #'start-process name buffer
                          decklet-tts-kokoro-command args)))
      (set-process-query-on-exit-flag process nil)
      (when show-log
        (decklet-tts-kokoro--display-log buffer))
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

(defun decklet-tts-kokoro--current-card ()
  "Return a cons of current Decklet card ID and word."
  (let* ((word (decklet-prompt-word "Word: "))
         (card-id (decklet-get-card-id-by-word word)))
    (unless card-id
      (user-error "No active Decklet card for %s" word))
    (cons card-id word)))

;;;###autoload
(defun decklet-tts-kokoro-install ()
  "Create or update the plugin-local Python environment with uv."
  (interactive)
  (unless (executable-find decklet-tts-kokoro-command)
    (user-error "%s executable not found" decklet-tts-kokoro-command))
  (decklet-tts-kokoro--start
   "decklet-tts-kokoro-install"
   (list "sync")
   "Decklet Kokoro environment is ready"
   t))

;;;###autoload
(defun decklet-tts-kokoro-regenerate-word (&optional prompt-for-pronunciation)
  "Regenerate Kokoro audio for the current card.
With prefix argument PROMPT-FOR-PRONUNCIATION, ask for an optional
Kokoro/Misaki phoneme override.  Empty input uses automatic G2P."
  (interactive "P")
  (pcase-let* ((`(,card-id . ,word) (decklet-tts-kokoro--current-card))
               (pronunciation
                (when prompt-for-pronunciation
                  (string-trim
                   (read-string
                    (format "Pronunciation for %s (empty for automatic): " word)))))
               (args
                (append
                 (decklet-tts-kokoro--base-args "generate")
                 (list "--card-id" (number-to-string card-id))
                 (decklet-tts-kokoro--runtime-args)
                 (when (and pronunciation (not (string-empty-p pronunciation)))
                   (list "--pronunciation" pronunciation)))))
    (decklet-tts-kokoro--start
     "decklet-tts-kokoro-generate"
     args
     (format "Generated Kokoro audio for %s" word))))

;;;###autoload
(defun decklet-tts-kokoro-sync (&optional dry-run)
  "Sync Kokoro audio with the active Decklet DB.
Reconcile deleted and renamed cards, then generate every missing or
stale item using automatic G2P.  With prefix argument DRY-RUN,
report the planned work without modifying files."
  (interactive "P")
  (decklet-tts-kokoro--start
   "decklet-tts-kokoro-sync"
   (append (decklet-tts-kokoro--base-args "sync")
           (decklet-tts-kokoro--runtime-args)
           (when dry-run (list "--dry-run")))
   (if dry-run
       "Decklet Kokoro sync preview finished"
     "Decklet Kokoro sync finished")
   t))

(defun decklet-tts-kokoro--remove-cards (events)
  "Remove Kokoro data for deleted cards described by EVENTS."
  (when events
    (let ((args
           (append
            (decklet-tts-kokoro--command-args "remove")
            (decklet-tts-kokoro--sidecar-args)
            (mapcan
             (lambda (event)
               (list "--card-id"
                     (number-to-string (plist-get event :card-id))))
             events))))
      (decklet-tts-kokoro--start
       "decklet-tts-kokoro-remove"
       args
       "Removed deleted cards from Kokoro sidecar"))))

(defun decklet-tts-kokoro--stale-renamed-cards (events)
  "Mark renamed cards in EVENTS stale and discard their old audio."
  (when events
    (decklet-tts-kokoro--start
     "decklet-tts-kokoro-stale"
     (append
      (decklet-tts-kokoro--command-args "stale")
      (decklet-tts-kokoro--sidecar-args)
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
          #'decklet-tts-kokoro-audio-resolver)
(add-hook 'decklet-cards-deleted-functions
          #'decklet-tts-kokoro--remove-cards)
(add-hook 'decklet-cards-renamed-functions
          #'decklet-tts-kokoro--stale-renamed-cards)

(provide 'decklet-tts-kokoro)

;;; decklet-tts-kokoro.el ends here
