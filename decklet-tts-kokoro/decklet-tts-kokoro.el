;;; decklet-tts-kokoro.el --- Local Kokoro TTS for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; URL: https://github.com/yilin-zhang/decklet-extensions
;; Package-Requires: ((emacs "31.1") (decklet "0.1.0") (decklet-sound "0.1.0"))
;; Keywords: multimedia, tools

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:

;; Generate per-card English pronunciation audio locally with Kokoro.
;; Pronunciation decisions live in decklet-directory/kokoro.json and
;; audio lives in audio-cache/tts-kokoro/<card-id>.mp3.  Playback is
;; provided by decklet-sound; this package registers a resolver that
;; runs before the Edge TTS one.

;;; Code:

(require 'json)
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

(defcustom decklet-tts-kokoro-manifest-file "kokoro.json"
  "Pronunciation sidecar file.
A relative name is resolved against `decklet-directory'."
  :type 'file
  :group 'decklet-tts-kokoro)

(defcustom decklet-tts-kokoro-audio-directory "audio-cache/tts-kokoro"
  "Directory for Kokoro audio, keyed by card id.
A relative name is resolved against `decklet-directory'."
  :type 'directory
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
  (expand-file-name decklet-tts-kokoro-manifest-file decklet-directory))

(defun decklet-tts-kokoro-audio-dir ()
  "Return the active Decklet Kokoro audio directory."
  (expand-file-name decklet-tts-kokoro-audio-directory decklet-directory))

(defun decklet-tts-kokoro-audio-path (card-id)
  "Return the Kokoro audio path for CARD-ID."
  (decklet-card-sidecar-file (decklet-tts-kokoro-audio-dir) card-id "mp3"))

(defconst decklet-tts-kokoro--manifest-version 1
  "Manifest format version shared with the Python CLI.")

(defun decklet-tts-kokoro--load-manifest ()
  "Return the pronunciation manifest as nested hash tables.
A missing file yields an empty manifest.  An unrecognized format
signals an error, so the file is left as it is."
  (let ((path (decklet-tts-kokoro-manifest-path)))
    (if (not (file-exists-p path))
        (let ((manifest (make-hash-table :test #'equal)))
          (puthash "version" decklet-tts-kokoro--manifest-version manifest)
          (puthash "cards" (make-hash-table :test #'equal) manifest)
          manifest)
      ;; Parse false as `:json-false' so `json-encode' round-trips
      ;; booleans; nil round-trips as null on its own.
      (let ((data (with-temp-buffer
                    (insert-file-contents path)
                    (json-parse-buffer :null-object nil
                                       :false-object :json-false))))
        (unless (and (hash-table-p data)
                     (equal (gethash "version" data)
                            decklet-tts-kokoro--manifest-version)
                     (hash-table-p (gethash "cards" data)))
          (error "Unsupported Kokoro manifest format: %s" path))
        data))))

(defun decklet-tts-kokoro--save-manifest (manifest)
  "Write MANIFEST back to the manifest path, keeping a .bak copy."
  (let ((path (decklet-tts-kokoro-manifest-path))
        (json-encoding-pretty-print t)
        (json-encoding-default-indentation "  "))
    (make-directory (file-name-directory path) t)
    (when (file-exists-p path)
      (copy-file path (concat path ".bak") t t t))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file path
        (insert (json-encode manifest) "\n")))))

(defun decklet-tts-kokoro--trash-audio (card-id)
  "Move CARD-ID's cached audio to the trash, if present.
`delete-file' only honors its TRASH argument when
`delete-by-moving-to-trash' is non-nil, and that variable is nil by
default, so binding it here sends the recording to the trash
regardless of the user's global setting."
  (let ((path (decklet-tts-kokoro-audio-path card-id))
        (delete-by-moving-to-trash t))
    (when (file-exists-p path)
      (delete-file path t))))

(defun decklet-tts-kokoro-audio-resolver (card-id _word)
  "Return the Kokoro audio path for CARD-ID.
WORD is accepted for the `decklet-sound' resolver contract."
  (decklet-tts-kokoro-audio-path card-id))

(defun decklet-tts-kokoro--args (subcommand)
  "Return the uv arguments that run SUBCOMMAND with the current settings."
  ;; `--no-sync' runs straight from the existing .venv.  Without it uv
  ;; re-resolves the project first, and resolving the direct-URL
  ;; en-core-web-sm dependency needs that wheel's metadata from the uv
  ;; cache.  A pruned cache then breaks every command under `--offline',
  ;; even though the package is already installed.  Rebuilding the
  ;; environment after a dependency change is an explicit `uv sync'.
  (list "run" "--no-sync" "--offline" decklet-tts-kokoro-cli-name subcommand
        "--db" (expand-file-name decklet-db-file)
        "--manifest" (decklet-tts-kokoro-manifest-path)
        "--out-dir" (decklet-tts-kokoro-audio-dir)
        "--model-dir" (expand-file-name decklet-tts-kokoro-model-directory)
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
    ;; tail of the output as it grows.
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
  (let* ((word (decklet-prompt-word "Word: "))
         (card-id (or (decklet-get-card-id-by-word word)
                      (user-error "No Decklet card for \"%s\"" word)))
         (pronunciation
          (when prompt-for-pronunciation
            (string-trim
             (read-string
              (format "Pronunciation for %s (empty for automatic): " word)))))
         (args
          (append
           (decklet-tts-kokoro--args "generate")
           (list "--card-id" (number-to-string card-id))
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
   (append (decklet-tts-kokoro--args "sync")
           (when dry-run (list "--dry-run")))
   (if dry-run
       "Decklet Kokoro sync preview finished"
     "Decklet Kokoro sync finished")
   t))

(defun decklet-tts-kokoro--remove-cards (events)
  "Remove Kokoro records and cached audio for deleted cards in EVENTS.
Simple bookkeeping done directly in Emacs; a concurrent CLI sync can
in principle overwrite the manifest edit, in which case that same
sync reconciles the deletion from the DB anyway."
  (let* ((manifest (decklet-tts-kokoro--load-manifest))
         (cards (gethash "cards" manifest))
         (changed nil))
    (dolist (event events)
      (let* ((card-id (plist-get event :card-id))
             (key (number-to-string card-id)))
        (when (gethash key cards)
          (remhash key cards)
          (setq changed t))
        (decklet-tts-kokoro--trash-audio card-id)))
    (when changed
      (decklet-tts-kokoro--save-manifest manifest))))

(defun decklet-tts-kokoro--stale-renamed-cards (events)
  "Mark renamed cards in EVENTS stale and discard their old audio.
This matches the CLI's stale command.  The record keeps its history
and is flagged for regeneration by the next sync."
  (let* ((manifest (decklet-tts-kokoro--load-manifest))
         (cards (gethash "cards" manifest))
         (changed nil))
    (dolist (event events)
      (let* ((card-id (plist-get event :card-id))
             (key (number-to-string card-id))
             (record (gethash key cards)))
        (when record
          (puthash "previous_word" (gethash "word" record) record)
          (puthash "word" (plist-get event :new-word) record)
          (puthash "status" "stale" record)
          (puthash "updated_at"
                   (format-time-string "%FT%T%:z" nil t) record)
          (setq changed t))
        (decklet-tts-kokoro--trash-audio card-id)))
    (when changed
      (decklet-tts-kokoro--save-manifest manifest))))

(add-hook 'decklet-sound-audio-resolver-functions
          #'decklet-tts-kokoro-audio-resolver)
(add-hook 'decklet-cards-deleted-functions
          #'decklet-tts-kokoro--remove-cards)
(add-hook 'decklet-cards-renamed-functions
          #'decklet-tts-kokoro--stale-renamed-cards)

(provide 'decklet-tts-kokoro)

;;; decklet-tts-kokoro.el ends here
