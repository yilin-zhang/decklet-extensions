;;; decklet-edge-tts.el --- Edge TTS audio generation for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (decklet-sound "0.1.0"))
;; Keywords: multimedia, tools

;;; Commentary:

;; Generates per-word pronunciation audio for Decklet flashcards
;; using Microsoft Edge TTS.  Writes files into the cache directory
;; owned by `decklet-sound' (`decklet-sound-audio-directory').  A
;; companion Python CLI (`uv run decklet-edge-tts ...') does the
;; actual HTTP requests and file writes; this Emacs package wraps
;; the CLI and keeps the cache in sync with Decklet's card hooks.
;;
;; Entry points:
;;
;;   M-x decklet-edge-tts-regenerate-word  — (re)generate audio for a word
;;   M-x decklet-edge-tts-sync             — bulk regenerate the whole deck
;;
;; Playback is not handled here; see `decklet-sound' for that.
;;
;; On load, the package subscribes to `decklet-cards-deleted-functions'
;; so deleting a card also deletes its cached audio.  Renames are
;; deliberately NOT auto-handled — the cached audio speaks the old
;; word, so renaming the file would leave stale content under the
;; new slug.  `decklet-edge-tts-sync' reconciles any such drift.

;;; Code:

(require 'subr-x)
(require 'decklet)
(require 'decklet-sound)

(defgroup decklet-edge-tts nil
  "Edge TTS audio generation for Decklet."
  :group 'multimedia)

(defcustom decklet-edge-tts-project-directory
  (file-name-directory (or load-file-name (locate-library "decklet-edge-tts") default-directory))
  "Directory containing the decklet-edge-tts project."
  :type 'directory
  :group 'decklet-edge-tts)

(defcustom decklet-edge-tts-db-file nil
  "Override sqlite DB path used by `decklet-edge-tts-sync'.
When nil, use `decklet-directory'/decklet.sqlite."
  :type '(choice (const :tag "Use decklet-directory" nil) file)
  :group 'decklet-edge-tts)

(defcustom decklet-edge-tts-command "uv"
  "Command used to invoke the Python CLI."
  :type 'string
  :group 'decklet-edge-tts)

(defcustom decklet-edge-tts-cli-name "decklet-edge-tts"
  "CLI entrypoint name used with `decklet-edge-tts-command'."
  :type 'string
  :group 'decklet-edge-tts)

(defcustom decklet-edge-tts-lead-in ", "
  "Prefix added before each generated word."
  :type 'string
  :group 'decklet-edge-tts)

(defvar decklet-edge-tts--sync-buffer-name "*Decklet Edge TTS Sync*"
  "Buffer used to capture sync output.")

(defvar decklet-edge-tts--generate-buffer-name "*Decklet Edge TTS Generate*"
  "Buffer used to capture one-off generation output.")

(defun decklet-edge-tts--append-log (buffer-name lines)
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

(defun decklet-edge-tts--db-file ()
  "Return the sqlite DB path used by decklet-edge-tts."
  (if decklet-edge-tts-db-file
      (expand-file-name decklet-edge-tts-db-file)
    (expand-file-name "decklet.sqlite" decklet-directory)))

(defun decklet-edge-tts--sync-read-number (key start end)
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

(defun decklet-edge-tts--sync-args (&optional dry-run)
  "Return CLI args for sync command.
When DRY-RUN is non-nil, include the dry-run flag."
  (append (list "run" decklet-edge-tts-cli-name
                "--sync"
                "--db" (decklet-edge-tts--db-file)
                "--out-dir" (decklet-sound-audio-dir)
                "--lead-in" decklet-edge-tts-lead-in)
          (when dry-run
            (list "--dry-run"))))

(defun decklet-edge-tts--generate-args (word &optional text)
  "Return CLI args to generate audio for WORD.
When TEXT is non-nil, use it as the spoken text override."
  (append (list "run" decklet-edge-tts-cli-name
                "--word" word
                "--out-dir" (decklet-sound-audio-dir)
                "--overwrite"
                "--lead-in" decklet-edge-tts-lead-in)
          (when (and text (not (string-empty-p text)))
            (list "--text" text))))

(defun decklet-edge-tts--current-word ()
  "Return the Decklet word from current context."
  (decklet-prompt-word "Word: "))

(defun decklet-edge-tts--on-cards-deleted (events)
  "Delete cached audio for each deleted card in EVENTS."
  (dolist (event events)
    (when-let* ((word (plist-get (plist-get event :card) :word)))
      (ignore-errors
        (delete-file (decklet-sound-audio-path word))))))

;; No on-cards-renamed handler: the cached audio speaks the OLD word,
;; so renaming the file would leave stale content under the new slug.
;; Automatically deleting is also undesirable (irreversible, and the
;; user may want the file around).  `decklet-edge-tts-sync' already
;; reconciles the cache against the DB, so leave it alone here and let
;; the next explicit sync take care of the orphan.
(add-hook 'decklet-cards-deleted-functions #'decklet-edge-tts--on-cards-deleted)

(defun decklet-edge-tts--start-generation (word text)
  "Start async generation for WORD using optional TEXT override."
  (let* ((default-directory (file-name-as-directory
                             (expand-file-name decklet-edge-tts-project-directory)))
         (buffer (get-buffer-create decklet-edge-tts--generate-buffer-name))
         (process-name (format "decklet-edge-tts-generate-%s" word))
         (args (decklet-edge-tts--generate-args word text)))
    (decklet-edge-tts--append-log
     decklet-edge-tts--generate-buffer-name
     (list (format "Generate: %s %s" decklet-edge-tts-command (mapconcat #'identity args " "))))
    (let ((process (apply #'start-process process-name buffer decklet-edge-tts-command args)))
      (set-process-query-on-exit-flag process nil)
      (set-process-sentinel
       process
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (let ((exit-code (process-exit-status proc)))
             (decklet-edge-tts--append-log
              decklet-edge-tts--generate-buffer-name
              (list (format "Done: exit code %d" exit-code)))
             (if (= 0 exit-code)
                 (message "Regenerated edge-tts audio for %s" word)
               (message "Failed to regenerate edge-tts audio for %s" word)
               (display-buffer (process-buffer proc)))))))
      process)))

;;;###autoload
(defun decklet-edge-tts-sync (&optional dry-run)
  "Sync local edge-tts cache with current Decklet DB.
With prefix argument DRY-RUN, report changes without writing files."
  (interactive "P")
  (let* ((default-directory (file-name-as-directory
                             (expand-file-name decklet-edge-tts-project-directory)))
         (buffer (get-buffer-create decklet-edge-tts--sync-buffer-name))
         (active (get-process "decklet-edge-tts-sync"))
         (args (decklet-edge-tts--sync-args dry-run)))
    (when (and active (process-live-p active))
      (user-error "Decklet edge-tts sync is already running"))
    (decklet-edge-tts--append-log
     decklet-edge-tts--sync-buffer-name
     (list (format "Start: %s %s" decklet-edge-tts-command (mapconcat #'identity args " "))))
    (let ((process (apply #'start-process "decklet-edge-tts-sync" buffer decklet-edge-tts-command args)))
      (set-process-query-on-exit-flag process nil)
      (process-put process 'decklet-edge-tts-sync-start-pos
                   (with-current-buffer buffer (point-max)))
      (process-put process 'decklet-edge-tts-sync-dry-run dry-run)
      (set-process-sentinel
       process
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (let ((exit-code (process-exit-status proc))
                 (is-dry-run (process-get proc 'decklet-edge-tts-sync-dry-run))
                 (start-pos (or (process-get proc 'decklet-edge-tts-sync-start-pos) (point-min)))
                 trashed generated planned failed)
             (decklet-edge-tts--append-log
              decklet-edge-tts--sync-buffer-name
              (list (format "Done: exit code %d" exit-code)))
             (with-current-buffer (process-buffer proc)
               (setq trashed (or (decklet-edge-tts--sync-read-number "trashed" start-pos (point-max)) 0)
                     generated (or (decklet-edge-tts--sync-read-number "generated" start-pos (point-max)) 0)
                     planned (or (decklet-edge-tts--sync-read-number "planned_generate" start-pos (point-max)) 0)
                     failed (or (decklet-edge-tts--sync-read-number "failed" start-pos (point-max)) 0)))
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
(defun decklet-edge-tts-regenerate-word (&optional word text)
  "Regenerate pronunciation audio for WORD.
When TEXT is empty, regenerate from the literal WORD.  Otherwise use
TEXT as the spoken text override for edge-tts."
  (interactive)
  (let* ((word (or word (decklet-edge-tts--current-word)))
         (text (or text
                   (read-string (format "Spoken text for %s (empty for literal): " word))))
         (trimmed-text (string-trim text)))
    (decklet-edge-tts--start-generation word (if (string-empty-p trimmed-text) nil trimmed-text))
    (message "Regenerating edge-tts audio for %s..." word)))

(provide 'decklet-edge-tts)

;;; decklet-edge-tts.el ends here
