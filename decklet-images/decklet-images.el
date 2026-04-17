;;; decklet-images.el --- Per-word image sidecar for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
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

;; Per-word image sidecar for Decklet flashcards.
;;
;; Stores one image file per word in a local folder, keyed by the
;; word itself, and shows it in a popup during review or edit.  The
;; popup window has a default size; the image is scaled to fit
;; (preserving aspect ratio) via `:max-width'/`:max-height' on the
;; image spec, and re-fits when the window is resized.
;;
;; The image store is kept in sync with the deck via Decklet's card
;; lifecycle hooks — deleting or renaming a word deletes or renames
;; its image file.  A `[IMG]' indicator is added to the review
;; display when the current card has an image.
;;
;; Entry points:
;;
;;   M-x decklet-images-show       — popup the current word's image
;;   M-x decklet-images-set-url    — download from an http(s) URL
;;   M-x decklet-images-set-file   — copy from a local file
;;
;; Both `set' commands treat an empty input as "delete the existing
;; image" (after confirmation).
;;
;; Activation: add `decklet-images-mode' to
;; `decklet-review-mode-hook' and `decklet-edit-mode-hook'.  The
;; mode owns the key bindings (`i'/`I'/`M-i') via
;; `decklet-images-mode-map' and installs the lifecycle hooks and
;; the review indicator on first enable; disabling removes only the
;; indicator so deletes/renames keep cleaning up even when the mode
;; is off in the calling buffer.
;;
;; Built entirely on Decklet's public extension API.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'url)
(require 'url-util)

(require 'decklet)

(defgroup decklet-images nil
  "Per-word image sidecar for Decklet."
  :group 'decklet)

(defcustom decklet-images-directory nil
  "Override directory containing Decklet per-word images.
When nil, use `decklet-directory'/images/."
  :type '(choice (const :tag "Use decklet-directory" nil) directory)
  :group 'decklet-images)

(defcustom decklet-images-extensions
  '("png" "jpg" "jpeg" "gif" "webp")
  "Image file extensions recognized by `decklet-images'.
When multiple files exist for the same word, the earliest match in
this list wins."
  :type '(repeat string)
  :group 'decklet-images)

(defcustom decklet-images-default-extension "png"
  "Fallback file extension used when a download URL does not carry one."
  :type 'string
  :group 'decklet-images)

(defcustom decklet-images-popup-padding 1
  "Inset, in characters, between the scaled image and the window edges.
Applied symmetrically on each axis when scaling the image to fit."
  :type 'integer
  :group 'decklet-images)

(defcustom decklet-images-show-indicator t
  "When non-nil, the review UI shows an [IMG] line for cards with images.
Takes effect on the next review render."
  :type 'boolean
  :group 'decklet-images)

(defface decklet-images-indicator-face
  `((t :foreground ,(face-attribute 'decklet-card-back-indicator-color :foreground)
       :weight bold))
  "Face used for the [IMG] review indicator."
  :group 'decklet-images)

(defconst decklet-images--buffer-name-prefix "*Decklet Image: "
  "Prefix for per-word image popup buffer names.")

;; Storage paths

(defun decklet-images--directory ()
  "Return the absolute directory used for per-word image storage."
  (if decklet-images-directory
      (expand-file-name decklet-images-directory)
    (expand-file-name "images" decklet-directory)))

(defun decklet-images--ensure-directory ()
  "Ensure the image directory exists."
  (make-directory (decklet-images--directory) t))

(defun decklet-images--slug (word)
  "Return a filesystem-safe slug for WORD."
  (url-hexify-string word))

(defun decklet-images--target-path (word ext)
  "Return the target path for WORD with extension EXT."
  (expand-file-name (format "%s.%s" (decklet-images--slug word) ext)
                    (decklet-images--directory)))

(defun decklet-images-file (word)
  "Return the image file path for WORD, or nil when no image exists.
Checks each extension in `decklet-images-extensions' in order and
returns the first existing file."
  (let ((slug (decklet-images--slug word))
        (dir (decklet-images--directory)))
    (seq-some (lambda (ext)
                (let ((path (expand-file-name (format "%s.%s" slug ext) dir)))
                  (and (file-exists-p path) path)))
              decklet-images-extensions)))

(defun decklet-images--remove-existing (word)
  "Delete every image file for WORD.  Return the number of files removed."
  (let ((removed 0))
    (dolist (ext decklet-images-extensions)
      (let ((path (decklet-images--target-path word ext)))
        (when (file-exists-p path)
          (delete-file path)
          (cl-incf removed))))
    removed))

;; Source dispatch: URL vs local file

(defun decklet-images--url-p (source)
  "Return non-nil when SOURCE is a string beginning with http:// or https://."
  (and (stringp source)
       (string-match-p "\\`https?://" source)))

(defun decklet-images--infer-extension-from-path (path)
  "Return the lowercased extension of PATH, or nil.
Only returns an extension listed in `decklet-images-extensions'."
  (when path
    (let ((ext (file-name-extension path)))
      (when (and ext (member (downcase ext) decklet-images-extensions))
        (downcase ext)))))

(defun decklet-images--extension-for-url (url)
  "Return an extension for URL, falling back to the default.
Prefers the URL path's extension when it is a known image extension;
otherwise returns `decklet-images-default-extension'."
  (or (decklet-images--infer-extension-from-path
       (url-filename (url-generic-parse-url url)))
      decklet-images-default-extension))

(defun decklet-images--temp-target-path (ext)
  "Return a fresh temp file path in the image directory with EXT.
Keeping the staging path on the same filesystem as the final
target means `rename-file' is an atomic inode swap and cannot fail
with a cross-device error."
  (concat (make-temp-name
           (expand-file-name ".decklet-images-tmp-"
                             (decklet-images--directory)))
          "." ext))

(defun decklet-images--save-from-url (word url)
  "Download URL and save it as WORD's image.  Return the saved path.
Downloads to a sibling temp file first and only renames into place
on success, so a failed download leaves any existing image
untouched."
  (decklet-images--ensure-directory)
  (let* ((ext (decklet-images--extension-for-url url))
         (target (decklet-images--target-path word ext))
         (tmp (decklet-images--temp-target-path ext)))
    (unwind-protect
        (progn
          (condition-case err
              (url-copy-file url tmp t)
            (error
             (user-error "Failed to download image: %s"
                         (error-message-string err))))
          (rename-file tmp target t)
          (setq tmp nil)
          target)
      (when (and tmp (file-exists-p tmp))
        (delete-file tmp)))))

(defun decklet-images--save-from-file (word file)
  "Copy local FILE to become WORD's image.  Return the saved path.
Copies to a sibling temp file first and only renames into place on
success, so a failed copy leaves any existing image untouched."
  (unless (file-readable-p file)
    (user-error "Cannot read image file: %s" file))
  (decklet-images--ensure-directory)
  (let* ((ext (or (decklet-images--infer-extension-from-path file)
                  decklet-images-default-extension))
         (target (decklet-images--target-path word ext))
         (tmp (decklet-images--temp-target-path ext)))
    (unwind-protect
        (progn
          (copy-file file tmp t)
          (rename-file tmp target t)
          (setq tmp nil)
          target)
      (when (and tmp (file-exists-p tmp))
        (delete-file tmp)))))

;; Notify Decklet UI about an image change

(defun decklet-images--notify-field-updated (word)
  "Fire `decklet-card-field-updated-functions' for WORD's image.
Decklet core's review and edit subscribers ignore the FIELD argument
and simply refresh whatever visible buffer they own, so firing with
the symbol `image' is enough to update the [IMG] indicator in review
and the tabulated list in edit."
  (run-hook-with-args 'decklet-card-field-updated-functions word 'image))

;; Interactive commands

(defun decklet-images--delete-for (word)
  "Delete WORD's image, close any popup, and notify the UI.
Returns non-nil when something was actually removed."
  (let ((removed (decklet-images--remove-existing word)))
    (decklet-images--kill-popup-buffer word)
    (when (> removed 0)
      (decklet-images--notify-field-updated word))
    (> removed 0)))

(defun decklet-images--maybe-delete (word)
  "Confirm and delete WORD's image, or report that nothing exists."
  (cond
   ((not (decklet-images-file word))
    (message "No image to delete for \"%s\"" word))
   ((yes-or-no-p (format "Delete image for \"%s\"? " word))
    (decklet-images--delete-for word)
    (message "Deleted image for \"%s\"" word))
   (t
    (message "Cancelled"))))

(defun decklet-images--require-card (word)
  "Signal a `user-error' when WORD has no Decklet card."
  (unless (decklet-card-exists-p word)
    (user-error "No Decklet card for \"%s\"" word)))

;;;###autoload
(defun decklet-images-set-url (&optional word url)
  "Download URL and set it as WORD's image.
When called interactively, prompts for WORD via
`decklet-prompt-word' and for URL via the minibuffer.  An empty
URL asks for confirmation and then deletes the existing image."
  (interactive)
  (let* ((word (or word (decklet-prompt-word "Set image URL for word: ")))
         (url (or url
                  (read-string
                   (format "Image URL for \"%s\" (empty to delete): " word)))))
    (decklet-images--require-card word)
    (cond
     ((string-empty-p url)
      (decklet-images--maybe-delete word))
     ((not (decklet-images--url-p url))
      (user-error "Not an http(s) URL: %s" url))
     (t
      (decklet-images--save-from-url word url)
      (decklet-images--notify-field-updated word)
      (message "Downloaded image for \"%s\"" word)))))

;;;###autoload
(defun decklet-images-set-file (&optional word file)
  "Copy local FILE into the image store as WORD's image.
When called interactively, prompts for WORD via
`decklet-prompt-word' and for FILE via `read-file-name' (so paths
get TAB-completion and `~' is expanded).  An empty path asks for
confirmation and then deletes the existing image."
  (interactive)
  (let* ((word (or word (decklet-prompt-word "Set image file for word: ")))
         (file (or file
                   (read-file-name
                    (format "Image file for \"%s\" (empty to delete): " word)
                    nil "" nil))))
    (decklet-images--require-card word)
    (cond
     ((or (null file) (string-empty-p file))
      (decklet-images--maybe-delete word))
     ((not (file-readable-p file))
      (user-error "Cannot read image file: %s" file))
     (t
      (decklet-images--save-from-file word file)
      (decklet-images--notify-field-updated word)
      (message "Saved image for \"%s\"" word)))))

;; Popup display

(defvar-keymap decklet-images-view-mode-map
  :doc "Keymap for `decklet-images-view-mode'."
  "q" #'kill-buffer-and-window)

(defvar-local decklet-images--current-path nil
  "Absolute path of the image displayed in this view buffer.")

(defvar-local decklet-images--last-window-pixels nil
  "Cons (PIXEL-WIDTH . PIXEL-HEIGHT) of this buffer's window at the last render.
Used by the configuration-change hook to skip no-op re-renders when
the window dimensions have not actually changed.")

(define-derived-mode decklet-images-view-mode special-mode "Decklet-Image"
  "Major mode for viewing a Decklet word image in a popup buffer."
  (buffer-disable-undo)
  (setq-local cursor-type nil))

(defun decklet-images--buffer-name (word)
  "Return the popup buffer name for WORD."
  (format "%s%s*" decklet-images--buffer-name-prefix word))

(defun decklet-images--kill-popup-buffer (word)
  "Kill any open popup buffer currently showing WORD's image."
  (when-let ((buffer (get-buffer (decklet-images--buffer-name word))))
    (when (buffer-live-p buffer)
      (when-let ((window (get-buffer-window buffer)))
        (delete-window window))
      (kill-buffer buffer))))

(defun decklet-images--render-centered (buffer)
  "Render `decklet-images--current-path' centered in BUFFER's window.
The image is scaled (preserving aspect ratio) to fit within the
window minus `decklet-images-popup-padding' chars on each side,
then padded vertically with blank lines and horizontally with a
`space' display property for pixel-crisp centering.  No-op when
BUFFER has no visible window."
  (when-let* ((window (get-buffer-window buffer))
              (path (buffer-local-value 'decklet-images--current-path buffer)))
    (with-current-buffer buffer
      (let* ((win-w-px (window-pixel-width window))
             (win-h-px (window-text-height window t))
             (pad-px-w (* decklet-images-popup-padding (frame-char-width)))
             (pad-px-h (* decklet-images-popup-padding (default-line-height)))
             (max-w (max 1 (- win-w-px (* 2 pad-px-w))))
             (max-h (max 1 (- win-h-px (* 2 pad-px-h))))
             (image (create-image path nil nil
                                  :max-width max-w
                                  :max-height max-h))
             (image-pixels (image-size image t))
             (image-width (car image-pixels))
             (image-height (cdr image-pixels))
             (image-lines (max 1 (ceiling image-height (default-line-height))))
             (window-lines (window-text-height window))
             (left-pad (max 0 (/ (- win-w-px image-width) 2)))
             (top-pad (max 0 (/ (- window-lines image-lines) 2)))
             (inhibit-read-only t))
        (erase-buffer)
        (dotimes (_ top-pad)
          (insert "\n"))
        (insert (propertize " " 'display `(space :width (,left-pad))))
        (insert-image image)
        (goto-char (point-min))
        (setq decklet-images--last-window-pixels (cons win-w-px win-h-px))))))

(defun decklet-images--on-window-configuration-change ()
  "Re-render the image when the window's pixel dimensions actually change.
Installed buffer-locally on `decklet-images-view-mode' buffers."
  (when-let ((window (get-buffer-window (current-buffer))))
    (let ((dims (cons (window-pixel-width window)
                      (window-text-height window t))))
      (unless (equal dims decklet-images--last-window-pixels)
        (decklet-images--render-centered (current-buffer))))))

;;;###autoload
(defun decklet-images-show (&optional word)
  "Show the image for WORD in a popup window.
When called interactively, resolves WORD via `decklet-prompt-word'.
In a non-graphic frame or when no image exists for WORD, reports via
`message' instead of creating a buffer."
  (interactive)
  (let ((word (or word (decklet-prompt-word "Show image for word: "))))
    (cond
     ((not (display-graphic-p))
      (message "Decklet-images popup requires a graphical frame"))
     (t
      (let ((path (decklet-images-file word)))
        (if (not path)
            (message "No image for \"%s\"" word)
          (let ((buffer (get-buffer-create (decklet-images--buffer-name word))))
            (with-current-buffer buffer
              (decklet-images-view-mode)
              (setq decklet-images--current-path path)
              (add-hook 'window-configuration-change-hook
                        #'decklet-images--on-window-configuration-change
                        nil t))
            (pop-to-buffer buffer '(display-buffer-pop-up-window))
            (decklet-images--render-centered buffer))))))))

;; Review UI indicator

(defun decklet-images-review-indicator ()
  "Review UI component.  Return an [IMG] line when the current card has an image.
Respects `decklet-images-show-indicator'.  Intended for
`decklet-review-floating-components'."
  (when (and decklet-images-show-indicator
             decklet-current-word
             (decklet-images-file decklet-current-word))
    (decklet-center-text
     (propertize "[IMG]" 'face 'decklet-images-indicator-face))))

;; Lifecycle hook handlers

(defun decklet-images--on-card-deleted (word)
  "Remove image files for the deleted WORD."
  (decklet-images--kill-popup-buffer word)
  (decklet-images--remove-existing word))

(defun decklet-images--on-card-renamed (old-word new-word)
  "Rename the image file when OLD-WORD becomes NEW-WORD."
  (decklet-images--kill-popup-buffer old-word)
  (when-let ((old-path (decklet-images-file old-word)))
    (let* ((ext (file-name-extension old-path))
           (new-path (decklet-images--target-path new-word ext)))
      (decklet-images--ensure-directory)
      (rename-file old-path new-path t))))

;; Minor mode

(defvar-keymap decklet-images-mode-map
  :doc "Keymap for `decklet-images-mode'."
  "i"   #'decklet-images-show
  "I"   #'decklet-images-set-url
  "M-i" #'decklet-images-set-file)

;;;###autoload
(define-minor-mode decklet-images-mode
  "Buffer-local Decklet image bindings.

Provides keys to show, set, and delete the per-word image attached
to the current card.  Add to `decklet-review-mode-hook' and
`decklet-edit-mode-hook' to enable the bindings — and, as a side
effect, to install the lifecycle hooks and the [IMG] review
indicator so both are active from the very first card.

The [IMG] review indicator is registered on enable and removed on
disable so it tracks the mode state.  The lifecycle hooks
(delete/rename image sync) are installed on enable but
deliberately *not* torn down on disable: deleting a card should
always clean up its image, even if the mode is off in the calling
buffer, otherwise the image store would accumulate orphans."
  :keymap decklet-images-mode-map
  (cond
   (decklet-images-mode
    (add-hook 'decklet-card-deleted-functions #'decklet-images--on-card-deleted)
    (add-hook 'decklet-card-renamed-functions #'decklet-images--on-card-renamed)
    (add-to-list 'decklet-review-floating-components
                 'decklet-images-review-indicator t))
   (t
    (cl-callf2 delq 'decklet-images-review-indicator
               decklet-review-floating-components))))

(provide 'decklet-images)

;;; decklet-images.el ends here
