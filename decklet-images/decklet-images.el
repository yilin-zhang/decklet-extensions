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
;; its image file.  A configurable review indicator is added when the
;; current card has an image.
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

(require 'ansi-color)
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

(defcustom decklet-images-indicator "♣"
  "When non-nil, the review UI shows this indicator for cards with images.
Takes effect on the next review render."
  :type '(choice (const :tag "Hide indicator" nil)
                 string)
  :group 'decklet-images)

(defface decklet-images-indicator-face
  `((t :foreground ,(face-attribute 'ansi-color-green :foreground)
       :weight bold))
  "Face used for the review indicator."
  :group 'decklet-images)

(defconst decklet-images--buffer-name-prefix "*Decklet Image: "
  "Prefix for per-word image popup buffer names.")

;; Presence cache

(defvar decklet-images--presence-cache nil
  "Hash table mapping slug → extension for images on disk, or nil.
Nil means the cache is cold and will be rebuilt on next read.
Every in-package mutation (save/delete/rename) drops the cache via
`decklet-images--invalidate-cache'; the next read does one
`directory-files' scan and repopulates.

The cache is deliberately optimistic — entries are returned without
re-checking the filesystem.  Files changed outside this package
(e.g. in Finder) are not visible until
`decklet-images-refresh-cache' is invoked.")

(defun decklet-images--build-cache ()
  "Scan the image directory once and return a freshly built cache.
When multiple extensions exist for the same slug, the earliest
match in `decklet-images-extensions' wins, matching
`decklet-images-file's lookup order."
  (let ((cache (make-hash-table :test 'equal))
        (dir (decklet-images--directory)))
    (when (file-directory-p dir)
      ;; Map extension → preference index (lower is better).
      (let ((pref (let ((i 0) (h (make-hash-table :test 'equal)))
                    (dolist (ext decklet-images-extensions)
                      (puthash (downcase ext) i h)
                      (cl-incf i))
                    h)))
        (dolist (f (directory-files dir nil "\\.[^.]+\\'"))
          (let* ((ext (downcase (or (file-name-extension f) "")))
                 (rank (gethash ext pref)))
            (when rank
              (let* ((slug (file-name-sans-extension f))
                     (existing-rank (and-let* ((cur (gethash slug cache)))
                                      (gethash cur pref))))
                (when (or (null existing-rank) (< rank existing-rank))
                  (puthash slug ext cache))))))))
    cache))

(defun decklet-images--presence-cache ()
  "Return the presence cache, building it lazily on first access."
  (or decklet-images--presence-cache
      (setq decklet-images--presence-cache (decklet-images--build-cache))))

(defun decklet-images--invalidate-cache ()
  "Drop the presence cache.  Called by every in-package file mutation.
Strategy B: null it out, rebuild lazily on next read.  Simpler and
safer than surgical updates — impossible to miss a field.  For
`decklet-images' the rebuild is one `directory-files' call, which
is cheap for the scales this package targets."
  (setq decklet-images--presence-cache nil))

;;;###autoload
(defun decklet-images-refresh-cache ()
  "Invalidate the image-presence cache so the next read rebuilds it.
Use this after manually adding, removing, or renaming files in
`decklet-images-directory' outside of this package."
  (interactive)
  (decklet-images--invalidate-cache)
  (message "Decklet image cache invalidated"))

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
Answered from the in-memory presence cache; see
`decklet-images-refresh-cache' if external file changes make the
cache stale."
  (let ((slug (decklet-images--slug word)))
    (when-let* ((ext (gethash slug (decklet-images--presence-cache))))
      (expand-file-name (format "%s.%s" slug ext)
                        (decklet-images--directory)))))

(defun decklet-images--remove-existing (word)
  "Delete every image file for WORD.  Return the number of files removed."
  (let ((removed 0))
    (dolist (ext decklet-images-extensions)
      (let ((path (decklet-images--target-path word ext)))
        (when (file-exists-p path)
          (delete-file path)
          (cl-incf removed))))
    ;; Mutation point: drop cache on any removal.
    (when (> removed 0)
      (decklet-images--invalidate-cache))
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
          ;; Mutation point: drop cache after a new file is in place.
          (decklet-images--invalidate-cache)
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
          ;; Mutation point: drop cache after a new file is in place.
          (decklet-images--invalidate-cache)
          target)
      (when (and tmp (file-exists-p tmp))
        (delete-file tmp)))))

;; Notify Decklet UI about an image change

(defun decklet-images--notify-field-updated (word)
  "Fire `decklet-cards-field-updated-functions' for WORD's image."
  (when-let* ((card-id (decklet-card-id-for-word word)))
    (decklet-run-cards-hook 'decklet-cards-field-updated-functions
                            (list (list :card-id card-id :field 'image)))))

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
  (unless (decklet-card-id-for-word word)
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
  (when-let* ((buffer (get-buffer (decklet-images--buffer-name word))))
    (when (buffer-live-p buffer)
      (when-let* ((window (get-buffer-window buffer)))
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
  (when-let* ((window (get-buffer-window (current-buffer))))
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

(defun decklet-images-component-indicator ()
  "Review UI component.  Return an indicator line when the current card has an image."
  (when (and decklet-images-indicator
             decklet-current-card-id)
    (when-let* ((word (decklet-card-word-by-id decklet-current-card-id)))
      (when (decklet-images-file word)
        (decklet-center-text
         (propertize decklet-images-indicator 'face 'decklet-images-indicator-face))))))

(defun decklet-images-edit-column-value (row)
  "Return the edit-view image indicator cell for ROW."
  (when (decklet-images-file (plist-get row :word))
    (propertize decklet-images-indicator 'face 'decklet-images-indicator-face)))

(defconst decklet-images-edit-column
  (list :name "Image"
        :width 5
        :value #'decklet-images-edit-column-value)
  "Edit-table column descriptor for image presence.")

;; Lifecycle hook handlers

(defun decklet-images--on-cards-deleted (events)
  "Remove image files for each deleted card in EVENTS."
  (dolist (event events)
    (when-let* ((word (plist-get (plist-get event :card) :word)))
      (decklet-images--kill-popup-buffer word)
      (decklet-images--remove-existing word))))

(defun decklet-images--on-cards-renamed (events)
  "Rename the image file for each rename event in EVENTS."
  (dolist (event events)
    (let ((old-word (plist-get event :old-word))
          (new-word (plist-get event :new-word)))
      (decklet-images--kill-popup-buffer old-word)
      (when-let* ((old-path (decklet-images-file old-word)))
        (let* ((ext (file-name-extension old-path))
               (new-path (decklet-images--target-path new-word ext)))
          (decklet-images--ensure-directory)
          (rename-file old-path new-path t)
          ;; Mutation point: drop cache after the slug has moved.
          (decklet-images--invalidate-cache))))))

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
effect, to install the lifecycle hooks and the review indicator so
both are active from the very first card.

The review indicator is registered on enable and removed on disable
so it tracks the mode state.  The lifecycle hooks
(delete/rename image sync) are installed on enable but
deliberately *not* torn down on disable: deleting a card should
always clean up its image, even if the mode is off in the calling
buffer, otherwise the image store would accumulate orphans."
  :keymap decklet-images-mode-map
  (cond
   (decklet-images-mode
    (add-hook 'decklet-cards-deleted-functions #'decklet-images--on-cards-deleted)
    (add-hook 'decklet-cards-renamed-functions #'decklet-images--on-cards-renamed)
    (add-to-list 'decklet-edit-sidecar-columns decklet-images-edit-column t)
    (add-to-list 'decklet-review-floating-components
                 'decklet-images-component-indicator t))
   (t
    (cl-callf2 delq decklet-images-edit-column decklet-edit-sidecar-columns)
    (cl-callf2 delq 'decklet-images-component-indicator
               decklet-review-floating-components))))

(provide 'decklet-images)

;;; decklet-images.el ends here
