;;; decklet-import.el --- E-reader vocab import for Decklet -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; URL: https://github.com/yilin-zhang/decklet-extensions
;; Package-Requires: ((emacs "31.1") (decklet "0.1.0"))
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

;; Imports saved words from a Kindle (vocab.db) or Kobo
;; (KoboReader.sqlite) into a Decklet batch-add buffer, where the user
;; confirms them.  The databases are read with the `sqlite3' CLI.

;;; Code:

(require 'seq)
(require 'subr-x)

(require 'decklet)

(defgroup decklet-import nil
  "E-reader vocabulary import for Decklet."
  :group 'decklet)

(defcustom decklet-import-sqlite-command "sqlite3"
  "SQLite command used for e-reader vocab extraction."
  :type 'string
  :group 'decklet-import)

(defcustom decklet-import-kindle-usage t
  "When non-nil, import Kindle usage examples as hints.
Usage lines are inserted into batch import buffers as lines starting with
`#', one line per usage example."
  :type 'boolean
  :group 'decklet-import)

(defvar decklet-import-kindle-buffer-name "*Decklet Import Kindle*"
  "Buffer name for Kindle vocab import.")

(defvar decklet-import-kobo-buffer-name "*Decklet Import Kobo*"
  "Buffer name for Kobo vocab import.")

(defun decklet-import--ensure-sqlite ()
  "Ensure sqlite command is available."
  (unless (executable-find decklet-import-sqlite-command)
    (user-error "%s command not found.  Please install SQLite3"
                decklet-import-sqlite-command)))

(defun decklet-import--sqlite-call (db-file sql context)
  "Run SQL against DB-FILE and return command output.
CONTEXT is used as the error message prefix when command execution fails."
  (with-temp-buffer
    (unless (zerop (call-process decklet-import-sqlite-command nil t nil db-file sql))
      (user-error "%s: %s" context (string-trim (buffer-string))))
    (buffer-string)))

(defun decklet-import-kindle--read-rows (db-file)
  "Return Kindle rows as (STEM WORD USAGE) lists from DB-FILE.
Each row comes from a LEFT JOIN between WORDS and LOOKUPS."
  (let* ((sql
          (concat
           "SELECT "
           "ifnull(WORDS.stem, '') || char(31) || "
           "ifnull(WORDS.word, '') || char(31) || "
           "replace(ifnull(LOOKUPS.usage, ''), char(10), ' ') "
           "FROM WORDS "
           "LEFT JOIN LOOKUPS ON LOOKUPS.word_key = WORDS.id "
           "ORDER BY WORDS.rowid, LOOKUPS.rowid;"))
         (raw (decklet-import--sqlite-call db-file sql "Failed to query database")))
    (mapcar (lambda (line)
              ;; Fields are joined with char(31) in the SQL above; some
              ;; sqlite3 builds print it raw, others as caret notation
              ;; ("^_"), so split on either form.
              (pcase-let ((`(,stem ,word . ,usage)
                           (split-string line "\\(?:\x1f\\|\\^_\\)" nil
                                         "[ \t\r]+")))
                (list stem word (string-join usage ""))))
            (split-string raw "\n" t))))

(defun decklet-import-kindle--rows->batch-lines (rows)
  "Build batch buffer lines from Kindle ROWS.
ROWS should be a list of (STEM WORD USAGE)."
  ;; Keep the order stable.  The first time a stem is seen decides where
  ;; its block goes.
  (let ((groups (make-hash-table :test #'equal))
        stems-rev)
    (dolist (row rows)
      (pcase-let ((`(,stem ,word ,usage) row))
        (when (eq (gethash stem groups :missing) :missing)
          (puthash stem nil groups)
          (push stem stems-rev))
        ;; A word looked up without context has no usage to show.
        (when (and decklet-import-kindle-usage
                   (not (string-empty-p usage)))
          ;; Wrap WORD in asterisks.  A word written in lowercase
          ;; matches any case; otherwise its case must match exactly.
          (let* ((case-fold-search (string= word (downcase word)))
                 (hint (replace-regexp-in-string
                        (format "\\b%s\\b" (regexp-quote word))
                        "*\\&*" usage t nil)))
            (unless (member hint (gethash stem groups))
              (push hint (gethash stem groups)))))))
    (let (lines)
      (dolist (stem (nreverse stems-rev))
        (push stem lines)
        (dolist (hint (nreverse (gethash stem groups)))
          (push (concat "# " hint) lines)))
      (nreverse lines))))

;;;###autoload
(defun decklet-import-kindle (db-file)
  "Extract words from Kindle vocab DB-FILE and open a batch add buffer."
  (interactive "fKindle vocab.db file: ")
  (setq db-file (expand-file-name db-file))
  (unless (file-exists-p db-file)
    (user-error "Database file does not exist: %s" db-file))
  (decklet-import--ensure-sqlite)
  (let* ((lines (decklet-import-kindle--rows->batch-lines
                 (decklet-import-kindle--read-rows db-file)))
         (word-count (seq-count (lambda (line) (not (string-prefix-p "#" line))) lines))
         (message-prefix (format "Extracted %d unique words." word-count)))
    (decklet-add-card-batch
     lines
     :buffer-name decklet-import-kindle-buffer-name
     :title "Decklet Kindle Vocab Import"
     :message-prefix message-prefix
     :on-confirm
     (lambda (_words)
       (when (yes-or-no-p (format "Clear all data from %s? "
                                  (file-name-nondirectory db-file)))
         (decklet-import--sqlite-call
          db-file
          "DELETE FROM LOOKUPS; DELETE FROM WORDS; DELETE FROM BOOK_INFO; VACUUM;"
          "Failed to clear database")
         (message "Database cleared successfully"))))))

;;;###autoload
(defun decklet-import-kobo (db-file)
  "Extract words from KoboReader DB-FILE and open a batch add buffer."
  (interactive "fKoboReader.sqlite file: ")
  (setq db-file (expand-file-name db-file))
  (unless (file-exists-p db-file)
    (user-error "Database file does not exist: %s" db-file))
  (decklet-import--ensure-sqlite)
  (let* ((words
          ;; Kobo sometimes keeps a trailing comma, so deduplicate after
          ;; removing it.
          (seq-uniq
           (mapcar (lambda (word) (string-remove-suffix "," word))
                   (split-string (decklet-import--sqlite-call
                                  db-file
                                  "SELECT Text FROM WordList ORDER BY rowid;"
                                  "Failed to query database")
                                 "\n" t))))
         (message-prefix (format "Extracted %d unique words." (length words))))
    (decklet-add-card-batch
     words
     :buffer-name decklet-import-kobo-buffer-name
     :title "Decklet Kobo Vocab Import"
     :message-prefix message-prefix
     :on-confirm
     (lambda (_words)
       (when (yes-or-no-p (format "Clear all words from %s? "
                                  (file-name-nondirectory db-file)))
         (decklet-import--sqlite-call
          db-file "DELETE FROM WordList; VACUUM;" "Failed to clear database")
         (message "WordList cleared successfully"))))))

(provide 'decklet-import)
;;; decklet-import.el ends here
