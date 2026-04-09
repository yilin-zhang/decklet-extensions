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
;; Stores one image file per Decklet word in a local folder, keyed by
;; the word itself.  Images can be downloaded from a URL or copied
;; from a local file, and are displayed in a popup window on demand
;; during review or edit.  The image store is kept in sync with the
;; deck automatically via Decklet's card lifecycle hooks — deleting
;; or renaming a word also deletes or renames its image file.
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

(defcustom decklet-images-show-indicator t
  "When non-nil, the review UI shows an [IMG] line for cards with images.
Takes effect on the next review render."
  :type 'boolean
  :group 'decklet-images)

(defface decklet-images-indicator-face
  '((t :inherit decklet-card-back-indicator-face))
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

(defun decklet-images--save-from-url (word url)
  "Download URL and save it as WORD's image.  Return the saved path."
  (let* ((ext (decklet-images--extension-for-url url))
         (target (decklet-images--target-path word ext)))
    (decklet-images--ensure-directory)
    ;; Clear any pre-existing image with a possibly different extension.
    (decklet-images--remove-existing word)
    (condition-case err
        (url-copy-file url target t)
      (error
       (user-error "Failed to download image: %s" (error-message-string err))))
    target))

(defun decklet-images--save-from-file (word file)
  "Copy local FILE to become WORD's image.  Return the saved path."
  (unless (file-readable-p file)
    (user-error "Cannot read image file: %s" file))
  (let* ((ext (or (decklet-images--infer-extension-from-path file)
                  decklet-images-default-extension))
         (target (decklet-images--target-path word ext)))
    (decklet-images--ensure-directory)
    (decklet-images--remove-existing word)
    (copy-file file target t)
    target))

;; Notify Decklet UI about an image change

(defun decklet-images--notify-field-updated (word)
  "Fire `decklet-card-field-updated-functions' for WORD's image.
Decklet core's review and edit subscribers ignore the FIELD argument
and simply refresh whatever visible buffer they own, so firing with
the symbol `image' is enough to update the [IMG] indicator in review
and the tabulated list in edit."
  (run-hook-with-args 'decklet-card-field-updated-functions word 'image))

;; Interactive commands

;;;###autoload
(defun decklet-images-set (&optional word source)
  "Set the image for WORD from SOURCE.
SOURCE can be an http or https URL (downloaded) or a local file path
\(copied).  When called interactively, prompts for WORD via
`decklet-prompt-word' and for SOURCE via the minibuffer.
Overwrites any existing image for WORD."
  (interactive)
  (let* ((word (or word (decklet-prompt-word "Set image for word: ")))
         (source (or source
                     (read-string
                      (format "Image URL or file for \"%s\": " word)))))
    (unless (decklet-card-exists-p word)
      (user-error "No Decklet card for \"%s\"" word))
    (cond
     ((decklet-images--url-p source)
      (decklet-images--save-from-url word source)
      (message "Downloaded image for \"%s\"" word))
     ((and (stringp source) (file-readable-p source))
      (decklet-images--save-from-file word source)
      (message "Saved image for \"%s\"" word))
     (t
      (user-error "Source is neither a URL nor a readable file: %s" source)))
    (decklet-images--notify-field-updated word)))

;;;###autoload
(defun decklet-images-delete (&optional word)
  "Delete the image for WORD.
When called interactively, prompts for WORD via `decklet-prompt-word'.
Does nothing when no image exists."
  (interactive)
  (let ((word (or word (decklet-prompt-word "Delete image for word: "))))
    (if (> (decklet-images--remove-existing word) 0)
        (progn
          (decklet-images--kill-popup-buffer word)
          (message "Deleted image for \"%s\"" word)
          (decklet-images--notify-field-updated word))
      (message "No image to delete for \"%s\"" word))))

;; Popup display

(defvar-keymap decklet-images-view-mode-map
  :doc "Keymap for `decklet-images-view-mode'."
  "q" #'quit-window)

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
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert-image (create-image path))
                (goto-char (point-min)))
              (decklet-images-view-mode))
            (pop-to-buffer buffer '(display-buffer-pop-up-window)))))))))

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

;; Setup

(add-hook 'decklet-card-deleted-functions #'decklet-images--on-card-deleted)
(add-hook 'decklet-card-renamed-functions #'decklet-images--on-card-renamed)

;; Auto-register the review indicator at the end of the floating list.
(unless (memq 'decklet-images-review-indicator decklet-review-floating-components)
  (add-to-list 'decklet-review-floating-components
               'decklet-images-review-indicator t))

;; Key bindings in both review and edit modes.
(keymap-set decklet-review-mode-map "i" #'decklet-images-show)
(keymap-set decklet-edit-mode-map "i" #'decklet-images-show)
(keymap-set decklet-review-mode-map "I" #'decklet-images-set)
(keymap-set decklet-edit-mode-map "I" #'decklet-images-set)

(provide 'decklet-images)

;;; decklet-images.el ends here
