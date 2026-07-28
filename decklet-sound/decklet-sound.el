;;; decklet-sound.el --- Audio playback layer for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: multimedia, tools

;;; Commentary:

;; Local audio playback layer for Decklet flashcards.  Looks up
;; cached per-word audio files and plays them via a long-lived mpv
;; daemon.  Also provides `decklet-sound-mode', a buffer-local
;; minor mode that binds `s' to speak the current card's audio in
;; review and edit buffers.
;;
;; This package **only plays** audio files.  Generating and
;; managing cache files is the responsibility of a companion
;; generator package (e.g. `decklet-edge-tts') or user scripts.
;;
;; Entry points:
;;
;;   M-x decklet-sound-pronounce        — play cached audio for a word
;;   M-x decklet-sound-stop-daemon  — shut down the mpv audio daemon
;;
;; Activation: add `decklet-sound-mode' to `decklet-review-mode-hook'
;; and `decklet-edit-mode-hook' in your config.  The mode owns the
;; `s' key binding via `decklet-sound-mode-map'.
;;
;; Playback uses an `mpv --idle' process started lazily on first
;; play.  Rapid successive plays reuse both the process and its
;; CoreAudio output, then an inactivity timer tears them down so the
;; next play opens a fresh audio device handle.
;; This avoids stale-AudioUnit failures: a daemon left running
;; across long idle periods can outlive its audio device handle
;; (e.g. Bluetooth headphones disconnect), at which point `loadfile'
;; succeeds but no sound comes out.  Short-term reuse still avoids
;; the Bluetooth codec renegotiation churn that comes from
;; short-lived per-play players like `afplay'.  mpv must be on PATH.
;;
;; Built on Decklet's public extension API.

;;; Code:

(require 'json)
(require 'subr-x)
(require 'url-util)
(require 'decklet)

(defgroup decklet-sound nil
  "Audio playback for Decklet."
  :group 'multimedia)

(defcustom decklet-sound-audio-directory nil
  "Directory containing cached per-word Decklet audio files.
When nil, use `decklet-directory'/audio-cache/tts-edge.

Generator packages (e.g. `decklet-edge-tts') write into this
directory; this package reads from it."
  :type '(choice (const :tag "Use decklet-directory" nil) directory)
  :group 'decklet-sound)

(defcustom decklet-sound-audio-resolver-functions nil
  "Ordered functions used to find card-specific audio.
Each function receives CARD-ID and WORD and returns an existing
audio file path or nil.  Resolvers run before the legacy
word-keyed cache in `decklet-sound-audio-directory'.  This lets
generator packages use different cache keys while preserving the
existing Edge TTS cache as a fallback."
  :type 'hook
  :group 'decklet-sound)

(defcustom decklet-sound-player-function #'decklet-sound-mpv-player
  "Function used to play local audio files.
The function is called with one absolute file path argument.

The default uses a long-lived mpv daemon so rapid successive
playbacks reuse one audio session.  This avoids the Bluetooth
codec renegotiation churn that happens when each play spawns a
short-lived player (e.g. `afplay') and reopens the system audio
unit.  The daemon stops after
`decklet-sound-mpv-idle-timeout' seconds of inactivity and no
later than the end of the active session via
`decklet-db-pre-disconnect-hook'.  Use
`decklet-sound-stop-daemon' to release it earlier."
  :type 'function
  :group 'decklet-sound)

(defcustom decklet-sound-mpv-socket
  (expand-file-name "decklet-sound-mpv.sock" temporary-file-directory)
  "Unix socket path used to control the long-lived mpv daemon."
  :type 'file
  :group 'decklet-sound)

(defcustom decklet-sound-mpv-idle-timeout 60
  "Seconds to keep the mpv daemon alive after the last playback.
After this interval the daemon is stopped, so the next playback
opens a fresh audio device handle.  This prevents a long-idle
daemon from silently retaining a stale CoreAudio device after an
output-device change.  Set to nil to keep the daemon alive until
the Decklet session ends."
  :type '(choice (const :tag "Keep alive for session" nil)
                 (number :tag "Idle seconds"))
  :group 'decklet-sound)

(defun decklet-sound-audio-dir ()
  "Return the canonical audio cache directory.
Resolves the `decklet-sound-audio-directory' custom, falling back
to `decklet-directory'/audio-cache/tts-edge when unset.  Generator
packages should write files into this directory."
  (if decklet-sound-audio-directory
      (expand-file-name decklet-sound-audio-directory)
    (expand-file-name "audio-cache/tts-edge" decklet-directory)))

(defun decklet-sound-audio-path (word)
  "Return the canonical audio file path for WORD regardless of existence.
Useful for generator packages that need to know the write location
or for cleanup hooks that want to delete a file by word."
  (expand-file-name
   (format "%s.mp3" (url-hexify-string word))
   (decklet-sound-audio-dir)))

(defun decklet-sound--resolve-extra-audio (card-id word)
  "Return the first resolver-provided audio file for CARD-ID and WORD."
  (catch 'found
    (dolist (resolver decklet-sound-audio-resolver-functions)
      (condition-case err
          (when-let* ((path (funcall resolver card-id word))
                      (expanded (expand-file-name path))
                      ((file-exists-p expanded)))
            (throw 'found expanded))
        (error
         (display-warning
          'decklet-sound
          (format "Audio resolver %S failed: %s"
                  resolver (error-message-string err))
          :warning))))
    nil))

(defun decklet-sound-audio-file (word &optional card-id)
  "Return cached audio for WORD and optional CARD-ID, or nil.
Card-specific resolvers are tried in
`decklet-sound-audio-resolver-functions' order.  The legacy
word-keyed cache is the final fallback."
  (let* ((resolved-id (or card-id (decklet-get-card-id-by-word word)))
         (extra (decklet-sound--resolve-extra-audio resolved-id word))
         (legacy (decklet-sound-audio-path word)))
    (or extra (and (file-exists-p legacy) legacy))))

;;; mpv daemon

(defvar decklet-sound--mpv-process nil
  "Long-lived mpv process used by `decklet-sound-mpv-player'.
Started lazily on first playback; shut down on
`decklet-db-pre-disconnect-hook' before Decklet closes the shared
SQLite connection, or via `decklet-sound-stop-daemon'.")

(defvar decklet-sound--mpv-idle-timer nil
  "Timer that stops the mpv daemon after playback inactivity.")

(defun decklet-sound--mpv-send (command)
  "Send COMMAND alist to mpv's IPC socket as a single JSON line.
COMMAND looks like `((command . (CMD ARG ...)))'.  Returns nil on
success; errors if the socket is unreachable."
  (let ((proc (make-network-process
               :name "decklet-sound-mpv-cmd"
               :family 'local
               :service decklet-sound-mpv-socket
               :noquery t)))
    (unwind-protect
        (process-send-string proc (concat (json-encode command) "\n"))
      (delete-process proc))))

(defun decklet-sound--mpv-ensure ()
  "Ensure the long-lived mpv player is running and its IPC socket is ready."
  (unless (and decklet-sound--mpv-process
               (process-live-p decklet-sound--mpv-process))
    (unless (executable-find "mpv")
      (user-error "mpv executable not found on PATH"))
    ;; Clean up any stale socket file from a previous, no-longer-running
    ;; daemon so `bind' in the new mpv doesn't trip over it.
    (when (file-exists-p decklet-sound-mpv-socket)
      (ignore-errors (delete-file decklet-sound-mpv-socket)))
    (setq decklet-sound--mpv-process
          (make-process :name "decklet-sound-mpv"
                        :command (list "mpv" "--idle=yes" "--no-video"
                                       "--no-terminal" "--input-terminal=no"
                                       ;; Keeping only the mpv process alive is
                                       ;; insufficient: by default mpv closes
                                       ;; its audio output at EOF.  Keep the
                                       ;; output alive and feed silence so rapid
                                       ;; short clips share one CoreAudio
                                       ;; session.  Do not retain mpv's default
                                       ;; paused state at EOF: it would also
                                       ;; pause the next file loaded over IPC.
                                       "--keep-open=yes"
                                       "--keep-open-pause=no"
                                       "--audio-stream-silence=yes"
                                       "--gapless-audio=yes"
                                       (format "--input-ipc-server=%s"
                                               decklet-sound-mpv-socket))
                        :connection-type 'pipe
                        :noquery t))
    ;; Wait for mpv to create the socket (typically under 50 ms).
    (let ((deadline (+ (float-time) 2.0)))
      (while (and (not (file-exists-p decklet-sound-mpv-socket))
                  (process-live-p decklet-sound--mpv-process)
                  (< (float-time) deadline))
        (sleep-for 0.02)))))

(defun decklet-sound-mpv-player (path)
  "Play PATH via a long-lived mpv daemon.
Each call sends `{\"command\": [\"loadfile\", PATH, \"replace\"]}' to
mpv's IPC socket, interrupting any still-playing audio.  Reusing
one audio session across plays avoids the Bluetooth codec
renegotiation churn that comes from short-lived per-play players."
  (decklet-sound--mpv-ensure)
  (decklet-sound--mpv-send
   `((command . ("loadfile" ,(expand-file-name path) "replace"))))
  (when (timerp decklet-sound--mpv-idle-timer)
    (cancel-timer decklet-sound--mpv-idle-timer))
  (setq decklet-sound--mpv-idle-timer
        (when decklet-sound-mpv-idle-timeout
          (run-at-time decklet-sound-mpv-idle-timeout nil
                       (lambda ()
                         (setq decklet-sound--mpv-idle-timer nil)
                         (decklet-sound--mpv-cleanup))))))

(defun decklet-sound--mpv-cleanup ()
  "Shut down the long-lived mpv daemon if running."
  (when (timerp decklet-sound--mpv-idle-timer)
    (cancel-timer decklet-sound--mpv-idle-timer))
  (setq decklet-sound--mpv-idle-timer nil)
  (when (and decklet-sound--mpv-process
             (process-live-p decklet-sound--mpv-process))
    ;; Prefer a clean IPC quit so mpv can tear down its audio unit
    ;; gracefully; fall back to `delete-process' if the socket is gone.
    (ignore-errors (decklet-sound--mpv-send '((command . ("quit")))))
    (accept-process-output decklet-sound--mpv-process 0.1)
    (when (process-live-p decklet-sound--mpv-process)
      (delete-process decklet-sound--mpv-process)))
  (setq decklet-sound--mpv-process nil)
  (when (file-exists-p decklet-sound-mpv-socket)
    (ignore-errors (delete-file decklet-sound-mpv-socket))))

;;;###autoload
(defun decklet-sound-stop-daemon ()
  "Shut down the long-lived mpv audio daemon.
Call this to free the Bluetooth audio link (letting headphones
idle-disconnect) or to reset the daemon if playback misbehaves.
The daemon restarts automatically on the next play."
  (interactive)
  (decklet-sound--mpv-cleanup)
  (message "Decklet sound daemon stopped"))

(add-hook 'decklet-db-pre-disconnect-hook #'decklet-sound--mpv-cleanup)

;;; Playback commands

(defun decklet-sound-play-file (path)
  "Play audio file at PATH via `decklet-sound-player-function'."
  (funcall decklet-sound-player-function path))

;;;###autoload
(defun decklet-sound-pronounce ()
  "Play the cached audio for the word in current context.
Resolves the word via `decklet-prompt-word' — current review word
in review mode, word at point in edit mode, or minibuffer prompt
otherwise — then plays the cached audio if present.  Messages
when no audio is available for the word."
  (interactive)
  (let* ((word (decklet-prompt-word "Pronounce word: "))
         (card-id (decklet-get-card-id-by-word word))
         (audio-file (decklet-sound-audio-file word card-id)))
    (if audio-file
        (progn
          (message "Playing audio for \"%s\"..." word)
          (decklet-sound-play-file audio-file))
      (message "No audio for \"%s\"" word))))

;;; Minor mode

(defvar-keymap decklet-sound-mode-map
  :doc "Keymap for `decklet-sound-mode'."
  "s" #'decklet-sound-pronounce)

;;;###autoload
(define-minor-mode decklet-sound-mode
  "Buffer-local Decklet sound playback bindings.

Adds `s' to speak the current card's cached audio.  Add to
`decklet-review-mode-hook' and `decklet-edit-mode-hook' to make
the binding active in those buffers."
  :keymap decklet-sound-mode-map)

(provide 'decklet-sound)

;;; decklet-sound.el ends here
