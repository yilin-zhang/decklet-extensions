;;; decklet-edge-tts.el --- Edge TTS integration for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: multimedia, tools

;;; Commentary:

;; Local pronunciation audio for Decklet flashcards using Microsoft
;; Edge TTS.  Generates and caches one audio file per word, plays it
;; on demand, and keeps the cache in sync with the deck via Decklet's
;; card lifecycle hooks — deleting or renaming a word also deletes
;; or renames its audio file.
;;
;; Audio generation, regeneration, and bulk sync are driven by an
;; external Python CLI (`uv run decklet-edge-tts ...') that writes
;; files under `decklet-directory'/audio-cache/tts-edge/ (override
;; via `decklet-edge-tts-audio-directory').
;;
;; Entry points:
;;
;;   M-x decklet-edge-tts-speak            — play cached audio for a word
;;   M-x decklet-edge-tts-regenerate-word  — (re)generate audio for a word
;;   M-x decklet-edge-tts-sync             — bulk regenerate the whole deck
;;
;; Activation: add `decklet-edge-tts-mode' to
;; `decklet-review-mode-hook' and `decklet-edit-mode-hook' in your
;; config.  The mode owns the `s' key binding via
;; `decklet-edge-tts-mode-map' and installs the lifecycle hooks on
;; first enable.
;;
;; Built entirely on Decklet's public extension API.

;;; Code:

(require 'subr-x)
(require 'url-util)
(require 'decklet)

(defgroup decklet-edge-tts nil
  "Edge TTS integration for Decklet."
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

(defcustom decklet-edge-tts-audio-directory nil
  "Override directory containing generated per-word Decklet TTS audio files.
When nil, use `decklet-directory'/audio-cache/tts-edge."
  :type '(choice (const :tag "Use decklet-directory" nil) directory)
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

(defcustom decklet-edge-tts-fallback-sound-file nil
  "Optional fallback sound file used by `decklet-edge-tts-play-next-word-or-fallback'."
  :type '(choice (const :tag "None" nil) file)
  :group 'decklet-edge-tts)

(defcustom decklet-edge-tts-player-function #'decklet-edge-tts-default-player
  "Function used to play local audio files.
The function is called with one absolute file path argument."
  :type 'function
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

(defun decklet-edge-tts--audio-directory ()
  "Return the audio cache directory used by decklet-edge-tts."
  (if decklet-edge-tts-audio-directory
      (expand-file-name decklet-edge-tts-audio-directory)
    (expand-file-name "audio-cache/tts-edge" decklet-directory)))

(defun decklet-edge-tts-default-player (path)
  "Play audio file at PATH using a local player."
  (let ((expanded (expand-file-name path)))
    (cond
     ((executable-find "afplay")
      (start-process "decklet-edge-tts-audio" nil "afplay" expanded))
     ((executable-find "mpv")
      (start-process "decklet-edge-tts-audio" nil "mpv" expanded))
     (t
      (user-error "No audio player found for %s" expanded)))))

(defun decklet-edge-tts--audio-path (word)
  "Return the target edge-tts audio path for WORD regardless of existence.
Internal helper used by lifecycle handlers that need the path to
attempt a delete or rename; the operation itself tolerates a
missing file."
  (expand-file-name
   (format "%s.mp3" (url-hexify-string word))
   (decklet-edge-tts--audio-directory)))

(defun decklet-edge-tts-audio-file (word)
  "Return the cached edge-tts audio file for WORD, or nil when absent.
Matches the existence-aware convention of `decklet-images-file'."
  (let ((path (decklet-edge-tts--audio-path word)))
    (and (file-exists-p path) path)))

;;;###autoload
(defun decklet-edge-tts-play-next-word-or-fallback ()
  "Play current Decklet word audio, falling back to a sound effect if configured."
  (let* ((word (when-let* ((id (bound-and-true-p decklet-current-card-id)))
                 (decklet-card-word-by-id id)))
         (audio-file (and word (decklet-edge-tts-audio-file word))))
    (cond
     (audio-file
      (funcall decklet-edge-tts-player-function audio-file))
     ((and decklet-edge-tts-fallback-sound-file
           (file-exists-p (expand-file-name decklet-edge-tts-fallback-sound-file)))
      (funcall decklet-edge-tts-player-function decklet-edge-tts-fallback-sound-file)))))

;;;###autoload
(defun decklet-edge-tts-speak ()
  "Play the edge-tts audio for the word in current context.
Resolves the word via `decklet-prompt-word' — current review word in
review mode, word at point in edit mode, or minibuffer prompt
otherwise — then plays the cached audio if present.  Messages when
no audio is available for the word."
  (interactive)
  (let* ((word (decklet-prompt-word "Pronounce word: "))
         (audio-file (decklet-edge-tts-audio-file word)))
    (if audio-file
        (progn
          (message "Playing edge-tts audio for \"%s\"..." word)
          (funcall decklet-edge-tts-player-function audio-file))
      (message "No edge-tts audio for \"%s\"" word))))

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
                "--out-dir" (decklet-edge-tts--audio-directory)
                "--lead-in" decklet-edge-tts-lead-in)
          (when dry-run
            (list "--dry-run"))))

(defun decklet-edge-tts--generate-args (word &optional text)
  "Return CLI args to generate audio for WORD.
When TEXT is non-nil, use it as the spoken text override."
  (append (list "run" decklet-edge-tts-cli-name
                "--word" word
                "--out-dir" (decklet-edge-tts--audio-directory)
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
        (delete-file (decklet-edge-tts--audio-path word))))))

(defun decklet-edge-tts--on-cards-renamed (events)
  "Rename cached audio file for each rename event in EVENTS."
  (dolist (event events)
    (when-let* ((old-path (decklet-edge-tts-audio-file (plist-get event :old-word))))
      (rename-file old-path
                   (decklet-edge-tts--audio-path (plist-get event :new-word))
                   t))))

;; Minor mode

(defvar-keymap decklet-edge-tts-mode-map
  :doc "Keymap for `decklet-edge-tts-mode'."
  "s" #'decklet-edge-tts-speak)

;;;###autoload
(define-minor-mode decklet-edge-tts-mode
  "Buffer-local Decklet edge-tts bindings.

Adds `s' to speak the current card's cached audio.  Add to
`decklet-review-mode-hook' and `decklet-edit-mode-hook' to make
the binding active in those buffers — and, as a side effect, to
install the lifecycle hooks (delete/rename audio sync) so they
are active from the very first card.

The lifecycle hooks are installed on enable and deliberately not
torn down on disable: deleting a card should always clean up its
audio cache, even if the mode is off in the calling buffer,
otherwise the cache would accumulate orphans."
  :keymap decklet-edge-tts-mode-map
  (when decklet-edge-tts-mode
    (add-hook 'decklet-cards-deleted-functions #'decklet-edge-tts--on-cards-deleted)
    (add-hook 'decklet-cards-renamed-functions #'decklet-edge-tts--on-cards-renamed)))

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
