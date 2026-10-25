;;; decklet-tts-edge.el --- Edge TTS audio generation for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; URL: https://github.com/yilin-zhang/decklet-extensions
;; Package-Requires: ((emacs "30.1") (decklet "0.1.0") (decklet-sound "0.1.0"))
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
;; using Microsoft Edge TTS.  Writes files into the cache directory
;; owned by `decklet-sound' (`decklet-sound-audio-directory').  A
;; companion Python CLI (`uv run decklet-tts-edge ...') does the
;; actual HTTP requests and file writes; this Emacs package wraps
;; the CLI and keeps the cache in sync with Decklet's card hooks.
;;
;; Entry points:
;;
;;   M-x decklet-tts-edge-install          — set up the Python environment
;;   M-x decklet-tts-edge-regenerate-word  — (re)generate audio for a word
;;   M-x decklet-tts-edge-sync             — bulk regenerate the whole deck
;;
;; Playback is not handled here; see `decklet-sound' for that.
;;
;; Audio is keyed by card id (`<card-id>.mp3').  On load, the package
;; subscribes to the card lifecycle hooks: deleting a card deletes its
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

(defcustom decklet-tts-edge-db-file nil
  "Override sqlite DB path used by `decklet-tts-edge-sync'.
When nil, use Decklet's own `decklet-db-file'."
  :type '(choice (const :tag "Use decklet-db-file" nil) file)
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
  "Whether long-running commands pop up their log buffer.
Sync runs asynchronously and can take many minutes; the log reports
every word as it is finished, so showing it is the only feedback on
how far along a batch is.  One-off generation is fast enough not to
need a window and never displays its log."
  :type 'boolean
  :group 'decklet-tts-edge)

(defvar decklet-tts-edge--sync-buffer-name "*Decklet Edge TTS Sync*"
  "Buffer used to capture sync output.")

(defvar decklet-tts-edge--generate-buffer-name "*Decklet Edge TTS Generate*"
  "Buffer used to capture one-off generation output.")

(defvar decklet-tts-edge--install-buffer-name "*Decklet Edge TTS Install*"
  "Buffer used to capture install output.")

(defun decklet-tts-edge--append-log (buffer-name lines)
  "Append LINES to BUFFER-NAME with a timestamp.
LINES should be a list of plain strings."
  (with-current-buffer (get-buffer-create buffer-name)
    (goto-char (point-max))
    (unless (bolp)
      (insert "\n"))
    (insert (format-time-string "[%Y-%m-%d %H:%M:%S] "))
    (insert (car lines) "\n")
    (dolist (line (cdr lines))
      (insert "  " line "\n"))))

(defun decklet-tts-edge--display-log (buffer)
  "Display BUFFER and keep its window scrolled to incoming output.
Does nothing when `decklet-tts-edge-display-log' is nil."
  (when decklet-tts-edge-display-log
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

(defun decklet-tts-edge--db-file ()
  "Return the sqlite DB path used by decklet-tts-edge."
  (expand-file-name (or decklet-tts-edge-db-file decklet-db-file)))

(defun decklet-tts-edge--sync-read-number (key start end)
  "Read integer value for KEY from SYNC_RESULT between START and END."
  (save-excursion
    (goto-char start)
    (when (re-search-forward "^SYNC_RESULT .*$" end t)
      (let ((fields (split-string (match-string 0) "[[:space:]]+" t))
            value)
        (dolist (field fields)
          (when (string-match (format "\\`%s=\\([0-9]+\\)\\'" (regexp-quote key))
                              field)
            (setq value (string-to-number (match-string 1 field)))))
        value))))

(defun decklet-tts-edge--sync-args (&optional dry-run)
  "Return CLI args for sync command.
When DRY-RUN is non-nil, include the dry-run flag."
  (append (list "run" decklet-tts-edge-cli-name
                "--sync"
                "--db" (decklet-tts-edge--db-file)
                "--out-dir" (decklet-sound-audio-dir)
                "--lead-in" decklet-tts-edge-lead-in)
          (when dry-run
            (list "--dry-run"))))

(defun decklet-tts-edge--generate-args (card-id word &optional text)
  "Return CLI args to generate CARD-ID's audio for WORD.
When TEXT is non-nil, use it as the spoken text override."
  (append (list "run" decklet-tts-edge-cli-name
                "--card-id" (number-to-string card-id)
                "--word" word
                "--out-dir" (decklet-sound-audio-dir)
                "--overwrite"
                "--lead-in" decklet-tts-edge-lead-in)
          (when (and text (not (string-empty-p text)))
            (list "--text" text))))


(defun decklet-tts-edge--on-cards-deleted (events)
  "Delete cached audio for each deleted card in EVENTS."
  (dolist (event events)
    (ignore-errors
      (delete-file (decklet-sound-audio-path (plist-get event :card-id))))))

(defun decklet-tts-edge--on-cards-renamed (events)
  "Move cached audio for each renamed card in EVENTS to the trash.
The file still speaks the old word under the card's unchanged id, so
it is discarded and the next `decklet-tts-edge-sync' regenerates it.
Trashing rather than deleting keeps the old recording recoverable.
`delete-file' only honors its TRASH argument when
`delete-by-moving-to-trash' is non-nil, and that variable is nil by
default, so it is bound here: the recording goes to the trash
regardless of the user's global setting."
  (let ((delete-by-moving-to-trash t))
    (dolist (event events)
      (let ((path (decklet-sound-audio-path (plist-get event :card-id))))
        (when (file-exists-p path)
          (ignore-errors (delete-file path t)))))))

(add-hook 'decklet-cards-deleted-functions #'decklet-tts-edge--on-cards-deleted)
(add-hook 'decklet-cards-renamed-functions #'decklet-tts-edge--on-cards-renamed)

(defun decklet-tts-edge--start-generation (card-id word text)
  "Start async generation of CARD-ID's audio for WORD.
TEXT, when non-nil, overrides the spoken text."
  (let* ((default-directory (file-name-as-directory
                             (expand-file-name decklet-tts-edge-project-directory)))
         (buffer (get-buffer-create decklet-tts-edge--generate-buffer-name))
         (process-name (format "decklet-tts-edge-generate-%s" word))
         (args (decklet-tts-edge--generate-args card-id word text)))
    (decklet-tts-edge--append-log
     decklet-tts-edge--generate-buffer-name
     (list (format "Generate: %s %s" decklet-tts-edge-command (mapconcat #'identity args " "))))
    (let ((process (apply #'start-process process-name buffer decklet-tts-edge-command args)))
      (set-process-query-on-exit-flag process nil)
      (set-process-sentinel
       process
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (let ((exit-code (process-exit-status proc)))
             (decklet-tts-edge--append-log
              decklet-tts-edge--generate-buffer-name
              (list (format "Done: exit code %d" exit-code)))
             (if (= 0 exit-code)
                 (message "Regenerated edge-tts audio for %s" word)
               (message "Failed to regenerate edge-tts audio for %s" word)
               (display-buffer (process-buffer proc)))))))
      process)))

;;;###autoload
(defun decklet-tts-edge-install ()
  "Install the Python environment used by decklet-tts-edge.
Runs `uv sync' (via `decklet-tts-edge-command') in the project
directory to create or update the virtualenv that
`decklet-tts-edge-sync' and `decklet-tts-edge-regenerate-word'
rely on.  Safe to re-run: `uv sync' is idempotent and picks up
any `pyproject.toml' changes."
  (interactive)
  (unless (executable-find decklet-tts-edge-command)
    (user-error "%s executable not found on PATH" decklet-tts-edge-command))
  (let ((project-dir (expand-file-name decklet-tts-edge-project-directory)))
    (unless (file-exists-p (expand-file-name "pyproject.toml" project-dir))
      (user-error "No pyproject.toml in %s" project-dir))
    (let* ((default-directory (file-name-as-directory project-dir))
           (buffer (get-buffer-create decklet-tts-edge--install-buffer-name))
           (active (get-process "decklet-tts-edge-install")))
      (when (and active (process-live-p active))
        (user-error "Decklet edge-tts install is already running"))
      (decklet-tts-edge--append-log
       decklet-tts-edge--install-buffer-name
       (list (format "Start: %s sync" decklet-tts-edge-command)))
      (let ((process (start-process "decklet-tts-edge-install" buffer
                                    decklet-tts-edge-command "sync")))
        (set-process-query-on-exit-flag process nil)
        (decklet-tts-edge--display-log buffer)
        (set-process-sentinel
         process
         (lambda (proc _event)
           (when (memq (process-status proc) '(exit signal))
             (let ((exit-code (process-exit-status proc)))
               (decklet-tts-edge--append-log
                decklet-tts-edge--install-buffer-name
                (list (format "Done: exit code %d" exit-code)))
               (if (= 0 exit-code)
                   (message "Decklet edge-tts install finished")
                 (message "Decklet edge-tts install failed (code %d)" exit-code)
                 (display-buffer (process-buffer proc)))))))
        (message "Decklet edge-tts install started...")))))

;;;###autoload
(defun decklet-tts-edge-sync (&optional dry-run)
  "Sync local edge-tts cache with current Decklet DB.
With prefix argument DRY-RUN, report changes without writing files."
  (interactive "P")
  (let* ((default-directory (file-name-as-directory
                             (expand-file-name decklet-tts-edge-project-directory)))
         (buffer (get-buffer-create decklet-tts-edge--sync-buffer-name))
         (active (get-process "decklet-tts-edge-sync"))
         (args (decklet-tts-edge--sync-args dry-run)))
    (when (and active (process-live-p active))
      (user-error "Decklet edge-tts sync is already running"))
    (decklet-tts-edge--append-log
     decklet-tts-edge--sync-buffer-name
     (list (format "Start: %s %s" decklet-tts-edge-command (mapconcat #'identity args " "))))
    (let ((process (apply #'start-process "decklet-tts-edge-sync" buffer decklet-tts-edge-command args)))
      (set-process-query-on-exit-flag process nil)
      (decklet-tts-edge--display-log buffer)
      (process-put process 'decklet-tts-edge-sync-start-pos
                   (with-current-buffer buffer (point-max)))
      (process-put process 'decklet-tts-edge-sync-dry-run dry-run)
      (set-process-sentinel
       process
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (let ((exit-code (process-exit-status proc))
                 (is-dry-run (process-get proc 'decklet-tts-edge-sync-dry-run))
                 (start-pos (process-get proc 'decklet-tts-edge-sync-start-pos))
                 trashed generated planned failed)
             (decklet-tts-edge--append-log
              decklet-tts-edge--sync-buffer-name
              (list (format "Done: exit code %d" exit-code)))
             (with-current-buffer (process-buffer proc)
               (setq trashed (or (decklet-tts-edge--sync-read-number "trashed" start-pos (point-max)) 0)
                     generated (or (decklet-tts-edge--sync-read-number "generated" start-pos (point-max)) 0)
                     planned (or (decklet-tts-edge--sync-read-number "planned_generate" start-pos (point-max)) 0)
                     failed (or (decklet-tts-edge--sync-read-number "failed" start-pos (point-max)) 0)))
             (if (= 0 exit-code)
                 (message "Decklet edge-tts sync %s: +%d generated, -%d trashed"
                          (if is-dry-run "preview" "finished")
                          (if is-dry-run planned generated)
                          trashed)
               (message "Decklet edge-tts sync failed (code %d): +%d, -%d"
                        exit-code
                        (if is-dry-run planned generated)
                        trashed)
               (when (> failed 0)
                 (message "Decklet edge-tts sync had %d generation failures" failed))
               (display-buffer (process-buffer proc)))))))
      (message "Decklet edge-tts sync started%s..."
               (if dry-run " (dry-run)" "")))))

;;;###autoload
(defun decklet-tts-edge-regenerate-word (&optional word text)
  "Regenerate pronunciation audio for WORD.
When TEXT is empty, regenerate from the literal WORD.  Otherwise use
TEXT as the spoken text override for edge-tts."
  (interactive)
  (let* ((word (or word (decklet-prompt-word "Word: ")))
         (card-id (or (decklet-get-card-id-by-word word)
                      (user-error "No Decklet card for \"%s\"" word)))
         (text (or text
                   (read-string (format "Spoken text for %s (empty for literal): " word))))
         (trimmed-text (string-trim text)))
    (decklet-tts-edge--start-generation
     card-id word (if (string-empty-p trimmed-text) nil trimmed-text))
    (message "Regenerating edge-tts audio for %s..." word)))

(provide 'decklet-tts-edge)

;;; decklet-tts-edge.el ends here
