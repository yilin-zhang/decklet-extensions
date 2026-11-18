;;; decklet-sound.el --- Audio playback layer for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; URL: https://github.com/yilin-zhang/decklet-extensions
;; Package-Requires: ((emacs "31.1") (decklet "0.1.0"))
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

;; Local audio playback layer for Decklet flashcards.  Looks up
;; cached per-card audio files and plays them via a long-lived mpv
;; daemon.  Also provides `decklet-sound-mode', a buffer-local
;; minor mode that binds `s' to speak the current card's audio in
;; review and edit buffers.
;;
;; This package only plays audio files.  Generator packages own their
;; caches and tell this package where a card's file is through
;; `decklet-sound-audio-resolver-functions'.
;;
;; Entry points:
;;
;;   M-x decklet-sound-pronounce      play cached audio for a word
;;   M-x decklet-sound-stop-daemon    shut down the mpv audio daemon
;;
;; To activate, add `decklet-sound-mode' to `decklet-review-mode-hook'
;; and `decklet-edit-mode-hook' in your config.  The mode owns the
;; `s' key binding via `decklet-sound-mode-map'.
;;
;; Playback goes through one `mpv --idle' process, started on the
;; first play.  Starting a player per clip, as `afplay' does, makes
;; Bluetooth headphones renegotiate their codec every time.  A daemon
;; kept too long can lose its audio device, for example when the
;; headphones disconnect, and then plays nothing.  So the daemon stops
;; after `decklet-sound-mpv-idle-timeout' seconds without playback.
;; mpv must be on PATH.
;;
;; Built on Decklet's public extension API.

;;; Code:

(require 'json)
(require 'subr-x)
(require 'decklet)

(defgroup decklet-sound nil
  "Audio playback for Decklet."
  :group 'multimedia)

(defcustom decklet-sound-audio-resolver-functions nil
  "Functions that find the audio file for a card.
Each function receives CARD-ID and WORD and returns a file path or
nil.  The first path that exists wins.  Generator packages add
their resolvers here."
  :type 'hook
  :group 'decklet-sound)

(defcustom decklet-sound-player-function #'decklet-sound-mpv-player
  "Function that plays one audio file.
It is called with the file's absolute path."
  :type 'function
  :group 'decklet-sound)

(defcustom decklet-sound-mpv-socket
  (expand-file-name "decklet-sound-mpv.sock" temporary-file-directory)
  "Unix socket path used to control the long-lived mpv daemon."
  :type 'file
  :group 'decklet-sound)

(defcustom decklet-sound-mpv-idle-timeout 60
  "Seconds to keep the mpv daemon alive after the last playback.
The next playback then opens the audio device again.  Nil keeps the
daemon alive until Decklet disconnects."
  :type '(choice (const :tag "Keep alive for session" nil)
                 (number :tag "Idle seconds"))
  :group 'decklet-sound)

(defun decklet-sound-audio-file (card-id)
  "Return the audio file for CARD-ID, or nil.
Resolvers are tried in `decklet-sound-audio-resolver-functions'
order."
  (let ((word (decklet-get-card-word card-id)))
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
      nil)))

;;; mpv daemon

(defvar decklet-sound--mpv-process nil
  "The mpv process used by `decklet-sound-mpv-player', or nil.")

(defvar decklet-sound--mpv-idle-timer nil
  "Timer that stops the mpv daemon after playback inactivity.")

(defun decklet-sound--mpv-send (command)
  "Send COMMAND to mpv's IPC socket as one JSON line.
COMMAND looks like `((command . (CMD ARG ...)))'.  Signal an error
when the socket is unreachable."
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
      (user-error "The mpv executable was not found on PATH"))
    ;; A socket file left by a dead daemon would make mpv's bind fail.
    (ignore-errors (delete-file decklet-sound-mpv-socket))
    (setq decklet-sound--mpv-process
          (make-process :name "decklet-sound-mpv"
                        :command (append (list "mpv" "--idle=yes" "--no-video"
                                               "--no-terminal" "--input-terminal=no"
                                               ;; Keep the audio output open between
                                               ;; clips.  Without keep-open-pause=no,
                                               ;; the next loaded file starts paused.
                                               "--keep-open=yes"
                                               "--keep-open-pause=no"
                                               "--audio-stream-silence=yes"
                                               "--gapless-audio=yes"
                                               (format "--input-ipc-server=%s"
                                                       decklet-sound-mpv-socket))
                                         ;; macOS 27 rejects mono layouts and
                                         ;; truncates short clips.  See mpv
                                         ;; issues #18384 and #18461.
                                         (when (eq system-type 'darwin)
                                           '("--audio-channels=stereo")))
                        :connection-type 'pipe
                        :noquery t))
    ;; Wait for mpv to create the socket (typically under 50 ms).
    (let ((deadline (+ (float-time) 2.0)))
      (while (and (not (file-exists-p decklet-sound-mpv-socket))
                  (process-live-p decklet-sound--mpv-process)
                  (< (float-time) deadline))
        (sleep-for 0.02)))))

(defun decklet-sound-mpv-player (path)
  "Play PATH through the mpv daemon, cutting off any clip still playing.
Each call restarts the idle timer."
  (decklet-sound--mpv-ensure)
  (decklet-sound--mpv-send
   `((command . ("loadfile" ,(expand-file-name path) "replace"))))
  (when (timerp decklet-sound--mpv-idle-timer)
    (cancel-timer decklet-sound--mpv-idle-timer))
  (setq decklet-sound--mpv-idle-timer
        (when decklet-sound-mpv-idle-timeout
          (run-at-time decklet-sound-mpv-idle-timeout nil
                       #'decklet-sound--mpv-cleanup))))

(defun decklet-sound--mpv-cleanup ()
  "Shut down the long-lived mpv daemon if running."
  (when (timerp decklet-sound--mpv-idle-timer)
    (cancel-timer decklet-sound--mpv-idle-timer))
  (setq decklet-sound--mpv-idle-timer nil)
  (when (and decklet-sound--mpv-process
             (process-live-p decklet-sound--mpv-process))
    ;; Ask mpv to quit so it closes the audio device cleanly.
    (ignore-errors (decklet-sound--mpv-send '((command . ("quit")))))
    (accept-process-output decklet-sound--mpv-process 0.1)
    (when (process-live-p decklet-sound--mpv-process)
      (delete-process decklet-sound--mpv-process)))
  (setq decklet-sound--mpv-process nil)
  (ignore-errors (delete-file decklet-sound-mpv-socket)))

;;;###autoload
(defun decklet-sound-stop-daemon ()
  "Stop the mpv audio daemon.
This frees the headphones' audio link, or resets a daemon that
stopped playing.  The next play starts it again."
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
  "Play the audio of the current word.
The word comes from `decklet-prompt-word'."
  (interactive)
  (let* ((word (decklet-prompt-word "Pronounce word: "))
         (card-id (or (decklet-get-card-id-by-word word)
                      (user-error "No Decklet card for \"%s\"" word)))
         (audio-file (decklet-sound-audio-file card-id)))
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
  "Bind `s' to play the current card's audio.
Enable it from `decklet-review-mode-hook' and `decklet-edit-mode-hook'."
  :keymap decklet-sound-mode-map)

(provide 'decklet-sound)

;;; decklet-sound.el ends here
