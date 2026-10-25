;;; decklet-icloud.el --- Keep Decklet closed while iCloud is out of sync -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; URL: https://github.com/yilin-zhang/decklet-extensions
;; Package-Requires: ((emacs "30.1") (decklet "0.1.0"))
;; Keywords: tools

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

;; Guard for a Decklet profile stored in iCloud Drive and used from
;; more than one Mac.  Before Decklet opens its database, two checks
;; run on `decklet-db-pre-connect-hook':
;;
;; 1. iCloud state.  The database and the review log must be fully
;;    downloaded, not downloading, and free of unresolved conflicts.
;;    A file that iCloud evicted to a placeholder counts as not
;;    downloaded.  Missing downloads are started on the way out.
;;
;; 2. Session lock.  While connected, Decklet holds a lock file in the
;;    profile directory naming this machine.  A lock held by another
;;    machine means the deck is open there, or was closed there but
;;    has not finished uploading.
;;
;; When either check fails, the connection is refused with a
;; `user-error', so no command that needs the database can run.
;; `decklet-icloud-override' skips the checks for the next connection.
;;
;; Profiles outside iCloud Drive are left alone.  Enable with
;; `M-x decklet-icloud-mode' (global minor mode).

;;; Code:

(require 'decklet)

(defgroup decklet-icloud nil
  "Keep Decklet closed while iCloud is out of sync."
  :group 'decklet)

(defcustom decklet-icloud-lock-file-name ".decklet-lock"
  "Name of the session lock file in the profile directory."
  :type 'string
  :group 'decklet-icloud)

(defcustom decklet-icloud-host-name nil
  "Name identifying this machine in the session lock.
When nil, use the macOS local host name, falling back to the
function `system-name'.  Set it if that name is not stable."
  :type '(choice (const :tag "Automatic" nil) string)
  :group 'decklet-icloud)

(defcustom decklet-icloud-osascript-program "osascript"
  "Program used to run the iCloud status script."
  :type 'string
  :group 'decklet-icloud)

;; Status query

(defconst decklet-icloud--status-script
  "ObjC.import('Foundation');
function value(url, key) {
  const ref = Ref();
  if (!url.getResourceValueForKeyError(ref, key, null)) return null;
  const v = ref[0];
  return (v === undefined || v.isNil()) ? null : v;
}
function flag(url, key) {
  const v = value(url, key);
  return v ? !!v.boolValue : false;
}
function run(argv) {
  const fm = $.NSFileManager.defaultManager;
  return JSON.stringify(argv.map(function (p) {
    const url = $.NSURL.fileURLWithPath(p);
    const r = {path: p, ubiquitous: flag(url, $.NSURLIsUbiquitousItemKey)};
    if (!r.ubiquitous) return r;
    const st = value(url, $.NSURLUbiquitousItemDownloadingStatusKey);
    const err = value(url, $.NSURLUbiquitousItemDownloadingErrorKey);
    r.current = st ? st.js === $.NSURLUbiquitousItemDownloadingStatusCurrent.js : false;
    r.downloading = flag(url, $.NSURLUbiquitousItemIsDownloadingKey);
    r.conflicts = flag(url, $.NSURLUbiquitousItemHasUnresolvedConflictsKey);
    r.error = err ? err.localizedDescription.js : null;
    if (!r.current && !r.downloading)
      fm.startDownloadingUbiquitousItemAtURLError(url, null);
    return r;
  }));
}"
  "JavaScript for Automation that reports iCloud state as JSON.
Takes file paths as arguments and prints one object per path.  It
starts the download of any ubiquitous file that is not current.")

(defun decklet-icloud--query (files)
  "Return the iCloud state of FILES as a list of hash tables.
Each table has the keys \"path\", \"ubiquitous\", \"current\",
\"downloading\", \"conflicts\" and \"error\".  Signal an error if the
status script fails."
  (with-temp-buffer
    (let ((status (apply #'call-process decklet-icloud-osascript-program
                         nil '(t nil) nil
                         "-l" "JavaScript" "-e" decklet-icloud--status-script
                         files)))
      (unless (eq status 0)
        (error "Decklet iCloud status script failed (%s)" status))
      (append (json-parse-string (buffer-string) :false-object nil
                                 :null-object nil)
              nil))))

;; Checks

(defun decklet-icloud--profile-directory ()
  "Return the directory holding the Decklet database."
  (file-name-directory (expand-file-name decklet-db-file)))

(defun decklet-icloud--checked-files ()
  "Return the files whose iCloud state gates the connection."
  (list (expand-file-name decklet-db-file)
        (expand-file-name decklet-review-log-file)))

(defun decklet-icloud--placeholder (file)
  "Return the iCloud placeholder that stands in for an evicted FILE."
  (expand-file-name (concat "." (file-name-nondirectory file) ".icloud")
                    (file-name-directory file)))

(defun decklet-icloud--in-icloud-p ()
  "Return non-nil when the profile directory lives in iCloud Drive."
  (and (eq system-type 'darwin)
       (let ((dir (decklet-icloud--profile-directory)))
         (and (file-directory-p dir)
              (gethash "ubiquitous"
                       (car (decklet-icloud--query
                             (list (directory-file-name
                                    (file-truename dir))))))))))

(defun decklet-icloud--sync-problems ()
  "Return a list of strings describing why the profile is out of sync."
  (let (problems present)
    (dolist (file (decklet-icloud--checked-files))
      (cond
       ((file-exists-p file) (push file present))
       ((file-exists-p (decklet-icloud--placeholder file))
        (push (format "%s is not downloaded" (file-name-nondirectory file))
              problems)
        ;; Querying the real path starts the download.
        (push file present))))
    (dolist (state (and present
                        (decklet-icloud--query
                         (mapcar #'file-truename (nreverse present)))))
      (let ((name (file-name-nondirectory (gethash "path" state))))
        (when (gethash "ubiquitous" state)
          (cond
           ((gethash "conflicts" state)
            (push (format "%s has unresolved conflicts" name) problems))
           ((gethash "error" state)
            (push (format "%s failed to download: %s"
                          name (gethash "error" state))
                  problems))
           ((gethash "downloading" state)
            (push (format "%s is downloading" name) problems))
           ((not (gethash "current" state))
            (push (format "%s is not up to date" name) problems))))))
    (delete-dups (nreverse problems))))

;; Session lock

(defvar decklet-icloud--lock-file nil
  "Lock file this Emacs holds, or nil.")

(defvar decklet-icloud--override nil
  "Non-nil means the next connection skips the checks.")

(defvar decklet-icloud--host nil
  "Cached default host name, see `decklet-icloud-host-name'.")

(defun decklet-icloud--host ()
  "Return the name identifying this machine in the session lock."
  (or decklet-icloud-host-name
      decklet-icloud--host
      (setq decklet-icloud--host
            (or (and (eq system-type 'darwin)
                     (ignore-errors
                       (car (process-lines "scutil" "--get" "LocalHostName"))))
                (system-name)))))

(defun decklet-icloud--lock-path ()
  "Return the path of the session lock file."
  (expand-file-name decklet-icloud-lock-file-name
                    (decklet-icloud--profile-directory)))

(defun decklet-icloud--read-lock (file)
  "Return the lock plist stored in FILE, or nil when there is none.
An unreadable lock reads as held by an unknown host."
  (when (file-exists-p file)
    (or (ignore-errors
          (with-temp-buffer
            (insert-file-contents file)
            (let ((lock (read (current-buffer))))
              (and (plist-get lock :host) lock))))
        (list :host "an unknown host"))))

(defun decklet-icloud--foreign-lock ()
  "Return the session lock when another machine holds it."
  (let ((lock (decklet-icloud--read-lock (decklet-icloud--lock-path))))
    (and lock
         (not (equal (plist-get lock :host) (decklet-icloud--host)))
         lock)))

(defun decklet-icloud--acquire-lock ()
  "Write the session lock for this machine."
  (let ((file (decklet-icloud--lock-path)))
    (write-region (prin1-to-string
                   (list :host (decklet-icloud--host)
                         :pid (emacs-pid)
                         :time (format-time-string "%FT%T%z")))
                  nil file nil 'silent)
    (setq decklet-icloud--lock-file file)))

(defun decklet-icloud--release-lock ()
  "Delete the session lock if this machine still holds it."
  (when-let* ((file decklet-icloud--lock-file))
    (setq decklet-icloud--lock-file nil)
    (when (equal (plist-get (decklet-icloud--read-lock file) :host)
                 (decklet-icloud--host))
      (ignore-errors (delete-file file)))))

;; Hooks

(defun decklet-icloud--check ()
  "Refuse the Decklet connection while the profile is out of sync.
Installed on `decklet-db-pre-connect-hook' by `decklet-icloud-mode'."
  (when (decklet-icloud--in-icloud-p)
    (if decklet-icloud--override
        (setq decklet-icloud--override nil)
      (let ((problems (decklet-icloud--sync-problems))
            (lock (decklet-icloud--foreign-lock)))
        (when lock
          (push (format "Decklet is open on %s since %s"
                        (plist-get lock :host)
                        (or (plist-get lock :time) "an unknown time"))
                problems))
        (when problems
          (user-error "Decklet iCloud: %s (M-x decklet-icloud-override \
to open anyway)"
                      (string-join problems "; ")))))
    (decklet-icloud--acquire-lock)))

;;;###autoload
(defun decklet-icloud-override ()
  "Skip the iCloud checks for the next Decklet connection.
Use when the lock is stale, e.g. after the other machine crashed, or
when working offline.  The next connection takes over the lock."
  (interactive)
  (setq decklet-icloud--override t)
  (message "Decklet iCloud: the next connection skips the checks"))

;;;###autoload
(defun decklet-icloud-status ()
  "Report whether the Decklet profile is in sync with iCloud."
  (interactive)
  (if (not (decklet-icloud--in-icloud-p))
      (message "Decklet iCloud: profile is not in iCloud Drive")
    (let ((problems (decklet-icloud--sync-problems))
          (lock (decklet-icloud--read-lock (decklet-icloud--lock-path))))
      (message "Decklet iCloud: %s; lock: %s"
               (if problems (string-join problems "; ") "in sync")
               (if lock
                   (format "%s since %s" (plist-get lock :host)
                           (or (plist-get lock :time) "an unknown time"))
                 "none")))))

;;;###autoload
(define-minor-mode decklet-icloud-mode
  "Refuse to open Decklet while its iCloud profile is out of sync."
  :global t
  :group 'decklet-icloud
  (if decklet-icloud-mode
      (progn
        (add-hook 'decklet-db-pre-connect-hook #'decklet-icloud--check)
        (add-hook 'decklet-db-pre-disconnect-hook #'decklet-icloud--release-lock)
        (add-hook 'kill-emacs-hook #'decklet-icloud--release-lock))
    (remove-hook 'decklet-db-pre-connect-hook #'decklet-icloud--check)
    (remove-hook 'decklet-db-pre-disconnect-hook #'decklet-icloud--release-lock)
    (remove-hook 'kill-emacs-hook #'decklet-icloud--release-lock)
    (decklet-icloud--release-lock)))

(provide 'decklet-icloud)
;;; decklet-icloud.el ends here
