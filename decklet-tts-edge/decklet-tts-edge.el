;;; decklet-tts-edge.el --- Edge TTS audio generation for Decklet -*- lexical-binding: t; -*-

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

;; Generates per-card pronunciation audio for Decklet flashcards
;; using Microsoft Edge TTS.  Files go to
;; `decklet-tts-edge-audio-directory', and a resolver on
;; `decklet-sound-audio-resolver-functions' lets `decklet-sound' find
;; them.  A companion Python CLI (`uv run decklet-tts-edge ...') does the
;; actual HTTP requests and file writes; this Emacs package wraps
;; the CLI and keeps the cache in sync with Decklet's card hooks.
;;
;; Entry points:
;;
;;   M-x decklet-tts-edge-install           set up the Python environment
;;   M-x decklet-tts-edge-regenerate-word   (re)generate audio for a word
;;   M-x decklet-tts-edge-sync              bulk regenerate the whole deck
;;
;; Playback is not handled here; see `decklet-sound' for that.
;;
;; Audio is keyed by card id (`<card-id>.mp3').  On load, the package
;; subscribes to the card lifecycle hooks.  Deleting a card deletes its
;; cached audio, and renaming one moves the audio to the trash because
;; it still speaks the old word.  The next `decklet-tts-edge-sync'
;; regenerates it.

;;; Code:

(require 'subr-x)
(require 'decklet)
(require 'decklet-sound)

(defgroup decklet-tts-edge nil
  "Edge TTS audio generation for Decklet."
  :group 'multimedia)

(defcustom decklet-tts-edge-project-directory
  (file-name-directory (or load-file-name (locate-library "decklet-tts-edge") default-directory))
  "Directory containing the decklet-tts-edge project."
  :type 'directory
  :group 'decklet-tts-edge)

(defcustom decklet-tts-edge-audio-directory "audio-cache/tts-edge"
  "Directory for Edge TTS audio, keyed by card id.
A relative name is resolved against `decklet-directory'."
  :type 'directory
  :group 'decklet-tts-edge)

(defcustom decklet-tts-edge-command "uv"
  "Command used to invoke the Python CLI."
  :type 'string
  :group 'decklet-tts-edge)

(defcustom decklet-tts-edge-cli-name "decklet-tts-edge"
  "CLI entrypoint name used with `decklet-tts-edge-command'."
  :type 'string
  :group 'decklet-tts-edge)

(defcustom decklet-tts-edge-lead-in ", "
  "Prefix added before each generated word."
  :type 'string
  :group 'decklet-tts-edge)

(defcustom decklet-tts-edge-display-log t
  "Whether sync pops up its log buffer.
A sync can take many minutes, and the log shows its progress.
Generating one word never shows the log."
  :type 'boolean
  :group 'decklet-tts-edge)

(defvar decklet-tts-edge--sync-buffer-name "*Decklet Edge TTS Sync*"
  "Buffer used to capture sync output.")

(defvar decklet-tts-edge--generate-buffer-name "*Decklet Edge TTS Generate*"
  "Buffer used to capture one-off generation output.")

(defvar decklet-tts-edge--install-buffer-name "*Decklet Edge TTS Install*"
  "Buffer used to capture install output.")

;; Running the CLI

(defun decklet-tts-edge--append-log (buffer line)
  "Append LINE to BUFFER with a timestamp."
  (with-current-buffer buffer
    (goto-char (point-max))
    (unless (bolp)
      (insert "\n"))
    (insert (format-time-string "[%Y-%m-%d %H:%M:%S] ") line "\n")))

(defun decklet-tts-edge--display-log (buffer)
  "Display BUFFER and keep its window scrolled to incoming output.
Does nothing when `decklet-tts-edge-display-log' is nil."
  (when decklet-tts-edge-display-log
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

(defun decklet-tts-edge--start (name buffer-name args on-exit &optional show-log)
  "Run `decklet-tts-edge-command' with ARGS as process NAME.
Output goes to BUFFER-NAME.  ON-EXIT is called with the exit code when
the process ends; a failed run also displays its log.  With SHOW-LOG,
display the log while the command runs."
  (let ((default-directory (file-name-as-directory
                            (expand-file-name decklet-tts-edge-project-directory)))
        (buffer (get-buffer-create buffer-name))
        (active (get-process name)))
    (when (and active (process-live-p active))
      (user-error "%s is already running" name))
    (decklet-tts-edge--append-log
     buffer (format "Start: %s %s" decklet-tts-edge-command (string-join args " ")))
    (let ((process (apply #'start-process name buffer decklet-tts-edge-command args)))
      (set-process-query-on-exit-flag process nil)
      (when show-log
        (decklet-tts-edge--display-log buffer))
      (set-process-sentinel
       process
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (let ((code (process-exit-status proc)))
             (decklet-tts-edge--append-log buffer (format "Done: exit code %d" code))
             (funcall on-exit code)
             (unless (= code 0)
               (display-buffer buffer))))))
      process)))

(defun decklet-tts-edge--sync-read-number (key start)
  "Return KEY's number from the SYNC_RESULT line after START, or nil."
  (save-excursion
    (goto-char start)
    (when (re-search-forward
           (format "^SYNC_RESULT.* %s=\\([0-9]+\\)" (regexp-quote key)) nil t)
      (string-to-number (match-string 1)))))

;; Audio files

(defun decklet-tts-edge-audio-dir ()
  "Return the Edge TTS audio directory."
  (expand-file-name decklet-tts-edge-audio-directory decklet-directory))

(defun decklet-tts-edge-audio-path (card-id)
  "Return the Edge TTS audio path for CARD-ID."
  (decklet-card-sidecar-file (decklet-tts-edge-audio-dir) card-id "mp3"))

(defun decklet-tts-edge-audio-resolver (card-id _word)
  "Return the Edge TTS audio path for CARD-ID.
WORD is accepted for the `decklet-sound' resolver contract."
  (decklet-tts-edge-audio-path card-id))

;; Depth 90 lets resolvers added at the default depth run first.
(add-hook 'decklet-sound-audio-resolver-functions
          #'decklet-tts-edge-audio-resolver 90)

;; Card lifecycle

(defun decklet-tts-edge--trash-audio (events)
  "Move the audio of each card in EVENTS to the trash.
A renamed card's audio speaks the old word, and the next
`decklet-tts-edge-sync' regenerates it."
  (let ((delete-by-moving-to-trash t))
    (dolist (event events)
      (let ((path (decklet-tts-edge-audio-path (plist-get event :card-id))))
        ;; Trashing a missing file signals.
        (when (file-exists-p path)
          (delete-file path t))))))

(add-hook 'decklet-cards-deleted-functions #'decklet-tts-edge--trash-audio)
(add-hook 'decklet-cards-renamed-functions #'decklet-tts-edge--trash-audio)

;; Commands

;;;###autoload
(defun decklet-tts-edge-install ()
  "Create or update the Python environment with `uv sync'.
Run it again after `pyproject.toml' changes."
  (interactive)
  (unless (executable-find decklet-tts-edge-command)
    (user-error "%s executable not found on PATH" decklet-tts-edge-command))
  (decklet-tts-edge--start
   "decklet-tts-edge-install" decklet-tts-edge--install-buffer-name
   (list "sync")
   (lambda (code)
     (if (= code 0)
         (message "Decklet edge-tts install finished")
       (message "Decklet edge-tts install failed (code %d)" code)))
   t)
  (message "Decklet edge-tts install started..."))

;;;###autoload
(defun decklet-tts-edge-sync (&optional dry-run)
  "Sync local edge-tts cache with current Decklet DB.
With prefix argument DRY-RUN, report changes without writing files."
  (interactive "P")
  (let* ((buffer (get-buffer-create decklet-tts-edge--sync-buffer-name))
         (start (with-current-buffer buffer (point-max))))
    (decklet-tts-edge--start
     "decklet-tts-edge-sync" decklet-tts-edge--sync-buffer-name
     (append (list "run" decklet-tts-edge-cli-name
                   "--sync"
                   "--db" (expand-file-name decklet-db-file)
                   "--out-dir" (decklet-tts-edge-audio-dir)
                   "--lead-in" decklet-tts-edge-lead-in)
             (when dry-run
               (list "--dry-run")))
     (lambda (code)
       ;; A run that exits with 2 prints no SYNC_RESULT line.
       (with-current-buffer buffer
         (let ((generated (or (decklet-tts-edge--sync-read-number
                               (if dry-run "planned_generate" "generated") start)
                              0))
               (trashed (or (decklet-tts-edge--sync-read-number "trashed" start) 0))
               (failed (or (decklet-tts-edge--sync-read-number "failed" start) 0)))
           (if (= code 0)
               (message "Decklet edge-tts sync %s: +%d generated, -%d trashed"
                        (if dry-run "preview" "finished") generated trashed)
             (message "Decklet edge-tts sync failed (code %d): +%d, -%d, %d failed"
                      code generated trashed failed)))))
     t)
    (message "Decklet edge-tts sync started%s..." (if dry-run " (dry-run)" ""))))

;;;###autoload
(defun decklet-tts-edge-regenerate-word (&optional word text)
  "Regenerate pronunciation audio for WORD.
When TEXT is empty, regenerate from the literal WORD.  Otherwise use
TEXT as the spoken text override for edge-tts."
  (interactive)
  (let* ((word (or word (decklet-prompt-word "Word: ")))
         (card-id (or (decklet-get-card-id-by-word word)
                      (user-error "No Decklet card for \"%s\"" word)))
         (text (string-trim
                (or text
                    (read-string
                     (format "Spoken text for %s (empty for literal): " word))))))
    (decklet-tts-edge--start
     (format "decklet-tts-edge-generate-%s" word)
     decklet-tts-edge--generate-buffer-name
     (append (list "run" decklet-tts-edge-cli-name
                   "--card-id" (number-to-string card-id)
                   "--word" word
                   "--out-dir" (decklet-tts-edge-audio-dir)
                   "--overwrite"
                   "--lead-in" decklet-tts-edge-lead-in)
             (unless (string-empty-p text)
               (list "--text" text)))
     (lambda (code)
       (if (= code 0)
           (message "Regenerated edge-tts audio for %s" word)
         (message "Failed to regenerate edge-tts audio for %s" word))))
    (message "Regenerating edge-tts audio for %s..." word)))

(provide 'decklet-tts-edge)

;;; decklet-tts-edge.el ends here
