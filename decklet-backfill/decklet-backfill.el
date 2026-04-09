;;; decklet-backfill.el --- Async Decklet backfill via OpenCode -*- lexical-binding: t; -*-

;; Author: yilinzhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: tools, convenience

;;; Commentary:

;; Generate Decklet card back content asynchronously with OpenCode and write it
;; into the current card.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'decklet)

(defconst decklet-backfill-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing the `decklet-backfill' package.")

(defgroup decklet-backfill nil
  "Generate Decklet card back content with OpenCode."
  :group 'decklet)

(defcustom decklet-backfill-opencode-command "opencode"
  "OpenCode executable name or full path."
  :type 'string
  :group 'decklet-backfill)

(defcustom decklet-backfill-output-format 'org
  "Output format used for generated card back content."
  :type '(choice (const :tag "Plain text" text)
                 (const :tag "Org mode" org)
                 (const :tag "Markdown" markdown))
  :group 'decklet-backfill)

(defcustom decklet-backfill-opencode-model nil
  "Optional OpenCode model name for Decklet backfill generation."
  :type '(choice (const :tag "Default" nil) string)
  :group 'decklet-backfill)

(defcustom decklet-backfill-working-directory user-emacs-directory
  "Working directory used when invoking OpenCode."
  :type 'directory
  :group 'decklet-backfill)

(defcustom decklet-backfill-skill-file
  (expand-file-name "SKILL.md" decklet-backfill-directory)
  "Skill file consumed by OpenCode for Decklet backfill generation."
  :type 'file
  :group 'decklet-backfill)

(defcustom decklet-backfill-runtime-directory
  (expand-file-name "runtime/" decklet-backfill-directory)
  "Directory used for generated Decklet backfill files."
  :type 'directory
  :group 'decklet-backfill)

(defcustom decklet-backfill-timeout-seconds 30
  "Maximum number of seconds to wait for one backfill run.
When nil, do not enforce a timeout."
  :type '(choice (const :tag "No timeout" nil) integer)
  :group 'decklet-backfill)

(defcustom decklet-backfill-max-concurrent-tasks 5
  "Maximum number of OpenCode processes to run in parallel."
  :type 'integer
  :group 'decklet-backfill)

(cl-defstruct (decklet-backfill-task
               (:constructor decklet-backfill-task-create))
  word
  result-file
  process
  timer
  session-id
  status
  error)

(cl-defstruct (decklet-backfill-batch
               (:constructor decklet-backfill-batch-create))
  id
  tasks
  source-buffer)

(defvar decklet-backfill--active-batch nil
  "Current active Decklet backfill batch, or nil.")

(defun decklet-backfill--current-word ()
  "Return the current Decklet word from review or edit buffers."
  (cond
   ((derived-mode-p 'decklet-review-mode)
    (or decklet-current-word
        (user-error "No current Decklet review word")))
   ((derived-mode-p 'decklet-edit-mode)
    (or (tabulated-list-get-id)
        (user-error "No Decklet word on this line")))
   (t
    (user-error "Run this command from a Decklet review or edit buffer"))))

(defun decklet-backfill--task-live-p (task)
  "Return non-nil when TASK is still running."
  (when-let ((process (decklet-backfill-task-process task)))
    (memq (process-status process) '(run open listen connect stop))))

(defun decklet-backfill--batch-live-p ()
  "Return non-nil when the active Decklet backfill batch still has live tasks."
  (and decklet-backfill--active-batch
       (seq-some #'decklet-backfill--task-live-p
                 (decklet-backfill-batch-tasks decklet-backfill--active-batch))))

(defun decklet-backfill--task-by-process (process)
  "Return active batch task associated with PROCESS, or nil."
  (when decklet-backfill--active-batch
    (seq-find (lambda (task)
                (eq process (decklet-backfill-task-process task)))
              (decklet-backfill-batch-tasks decklet-backfill--active-batch))))

(defun decklet-backfill--cancel-task-timer (task)
  "Cancel TASK timer if present."
  (when-let ((timer (decklet-backfill-task-timer task)))
    (cancel-timer timer))
  (setf (decklet-backfill-task-timer task) nil))

(defun decklet-backfill--clear-active-batch ()
  "Clear tracked state for the current Decklet backfill batch."
  (when decklet-backfill--active-batch
    (mapc #'decklet-backfill--cancel-task-timer
          (decklet-backfill-batch-tasks decklet-backfill--active-batch)))
  (setq decklet-backfill--active-batch nil))

(defun decklet-backfill--ensure-idle ()
  "Signal a `user-error' when a Decklet backfill batch is already active."
  (when decklet-backfill--active-batch
    (user-error "A Decklet backfill is already running")))

(defun decklet-backfill--existing-back (word)
  "Return WORD's current Decklet back content, or nil."
  (decklet-get-card-back word))

(defun decklet-backfill--batch-id ()
  "Return a unique id string for one backfill batch."
  (format-time-string "%Y%m%dT%H%M%S%N"))

(defun decklet-backfill--sanitize-word-for-file (word)
  "Return a filesystem-friendly name derived from WORD."
  (let ((slug (downcase (replace-regexp-in-string "[^[:alnum:]]+" "-" word))))
    (let ((trimmed (string-trim slug "-+" "-+")))
      (if (string-empty-p trimmed) "word" trimmed))))

(defun decklet-backfill--task-result-file (batch-id word)
  "Return unique result file path for BATCH-ID and WORD."
  (expand-file-name
   (format "%s-%s%s"
           batch-id
           (decklet-backfill--sanitize-word-for-file word)
           (decklet-backfill--format-extension))
   decklet-backfill-runtime-directory))

(defun decklet-backfill--format-extension ()
  "Return the temp file extension for `decklet-backfill-output-format'."
  (pcase decklet-backfill-output-format
    ('org ".org")
    ('markdown ".md")
    (_ ".txt")))

(defun decklet-backfill--format-hint ()
  "Return the format hint appended to the target word."
  (pcase decklet-backfill-output-format
    ('org "org")
    ('markdown "md")
    (_ "text")))

(defun decklet-backfill--skill-text ()
  "Return the Decklet backfill skill text."
  (unless (file-readable-p decklet-backfill-skill-file)
    (user-error "Decklet backfill skill file not found: %s" decklet-backfill-skill-file))
  (with-temp-buffer
    (insert-file-contents decklet-backfill-skill-file)
    (buffer-string)))

(defun decklet-backfill--prompt (word)
  "Return the OpenCode prompt used to explain WORD."
  (concat (decklet-backfill--skill-text)
          "\n----\n"
          word
          " ("
          (decklet-backfill--format-hint)
          ")\n"))

(defun decklet-backfill--ensure-runtime-directory ()
  "Ensure `decklet-backfill-runtime-directory' exists."
  (make-directory decklet-backfill-runtime-directory t))

(defun decklet-backfill--clear-result-file (path)
  "Delete prior generated result file at PATH if it exists."
  (when (file-exists-p path)
    (delete-file path)))

(defun decklet-backfill--prompt-with-output-file (word path)
  "Return the OpenCode prompt used to explain WORD and write it to PATH."
  (concat
   (decklet-backfill--prompt word)
   "\n"
   "Write the final explanation to this exact file path: " path "\n"
   "Overwrite the file if it already exists. Do not ask questions.\n"
   "Do not print the explanation to stdout. Write it to the file instead.\n"))

(defun decklet-backfill--read-result-file (path)
  "Return generated content from PATH, or nil if empty."
  (when (file-readable-p path)
    (let ((content (with-temp-buffer
                     (insert-file-contents path)
                     (buffer-string))))
      (unless (string-empty-p (string-trim content))
        content))))

(defun decklet-backfill--parse-opencode-event (line)
  "Return parsed JSON event from LINE, or nil on failure."
  (when (string-prefix-p "{" (string-trim-left line))
    (condition-case nil
        (json-parse-string line :object-type 'plist :array-type 'list :null-object nil :false-object nil)
      (error nil))))

(defun decklet-backfill--extract-session-id (buffer)
  "Return the last OpenCode session id seen in BUFFER, or nil."
  (with-current-buffer buffer
    (let (session-id)
      (dolist (line (split-string (buffer-string) "\n" t))
        (when-let ((event (decklet-backfill--parse-opencode-event line))
                   (value (plist-get event :sessionID)))
          (setq session-id value)))
      session-id)))

(defun decklet-backfill--save-file-to-card-back (word path)
  "Write PATH contents into WORD's card back.
Uses `decklet-set-card-back', which fires the field-updated hook;
Decklet core subscribes to that hook to refresh any visible review
or edit buffer automatically."
  (let ((content (decklet-backfill--read-result-file path)))
    (unless content
      (user-error "Backfill output file is empty: %s" path))
    (decklet-set-card-back word content)))

(defun decklet-backfill--batch-summary (batch)
  "Return human-readable summary string for BATCH."
  (let ((tasks (decklet-backfill-batch-tasks batch))
        (success 0)
        (failed 0)
        (cancelled 0)
        (timed-out 0))
    (dolist (task tasks)
      (pcase (decklet-backfill-task-status task)
        ('success (setq success (1+ success)))
        ('failed (setq failed (1+ failed)))
        ('cancelled (setq cancelled (1+ cancelled)))
        ('timed-out (setq timed-out (1+ timed-out)))))
    (format "Decklet backfill finished: %d succeeded, %d failed, %d cancelled, %d timed out"
            success failed cancelled timed-out)))

(defun decklet-backfill--batch-done-count (batch)
  "Return the number of finished tasks in BATCH."
  (seq-count (lambda (task)
               (not (memq (decklet-backfill-task-status task) '(pending running))))
             (decklet-backfill-batch-tasks batch)))

(defun decklet-backfill--all-tasks-finished-p (batch)
  "Return non-nil when every task in BATCH is finished."
  (not (seq-some (lambda (task)
                   (memq (decklet-backfill-task-status task) '(pending running)))
                 (decklet-backfill-batch-tasks batch))))

(defun decklet-backfill--finish-batch-if-done (batch)
  "Finalize BATCH when all its tasks are done."
  (when (and (eq batch decklet-backfill--active-batch)
             (decklet-backfill--all-tasks-finished-p batch))
    (when (> (length (decklet-backfill-batch-tasks batch)) 1)
      (message "%s" (decklet-backfill--batch-summary batch)))
    (decklet-backfill--clear-active-batch)))

(defun decklet-backfill--cleanup-process-sentinel (process _event)
  "Kill cleanup PROCESS buffer when it exits."
  (when (memq (process-status process) '(exit signal))
    (when-let ((buffer (process-buffer process)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun decklet-backfill--cleanup-session (task)
  "Delete the temporary OpenCode session associated with TASK."
  (when-let ((session-id (decklet-backfill-task-session-id task)))
    (let* ((buffer (generate-new-buffer (format " *decklet-backfill-cleanup-%s*"
                                                (decklet-backfill-task-word task))))
           (process (start-process
                     (format "decklet-backfill-cleanup-%s" session-id)
                     buffer
                     decklet-backfill-opencode-command
                     "session" "delete" session-id)))
      (set-process-query-on-exit-flag process nil)
      (set-process-sentinel process #'decklet-backfill--cleanup-process-sentinel))))

(defun decklet-backfill--maybe-start-next-task (batch)
  "Start the next pending task in BATCH if the concurrency limit allows."
  (when (eq batch decklet-backfill--active-batch)
    (let ((running (seq-count (lambda (task)
                                (eq (decklet-backfill-task-status task) 'running))
                              (decklet-backfill-batch-tasks batch)))
          (next (seq-find (lambda (task)
                            (eq (decklet-backfill-task-status task) 'pending))
                          (decklet-backfill-batch-tasks batch))))
      (when (and next (< running decklet-backfill-max-concurrent-tasks))
        (decklet-backfill--start-task next batch)))))

(defun decklet-backfill--marked-edit-words ()
  "Return marked words in `decklet-edit-mode', or nil otherwise."
  (when (derived-mode-p 'decklet-edit-mode)
    (decklet-edit--marked-words)))

(defun decklet-backfill--target-words ()
  "Return list of words to backfill based on current context."
  (let ((marked (decklet-backfill--marked-edit-words)))
    (cond
     ((null marked)
      (list (decklet-backfill--current-word)))
     ((= (length marked) 1)
      marked)
     ((yes-or-no-p (format "Generate card backs for %d marked words? " (length marked)))
      marked)
     (t
      (user-error "Backfill cancelled")))))

(defun decklet-backfill--ensure-cards-exist (words)
  "Signal when any item in WORDS is missing from Decklet DB."
  (dolist (word words)
    (unless (decklet-card-exists-p word)
      (user-error "No Decklet card found for %s" word))))

(defun decklet-backfill--prepare-words (words)
  "Return WORDS filtered by overwrite choice.
When some words already have card backs, prompt once whether to override them.
If the user declines, only words without existing card backs are returned."
  (let ((existing (seq-filter #'decklet-backfill--existing-back words)))
    (cond
     ((null existing) words)
     ((= (length words) 1)
      (when (not (yes-or-no-p (format "Card back already exists for %s. Override it? " (car words))))
        (user-error "Backfill cancelled"))
      words)
     ((yes-or-no-p (format "Override existing card backs for %d of %d words? "
                           (length existing) (length words)))
      words)
     (t
      (let ((remaining (seq-remove (lambda (word) (member word existing)) words)))
        (unless remaining
          (user-error "Backfill cancelled"))
        remaining)))))

(defun decklet-backfill--start-timeout (task batch)
  "Start timeout timer for TASK in BATCH."
  (when decklet-backfill-timeout-seconds
    (setf (decklet-backfill-task-timer task)
          (run-at-time
           decklet-backfill-timeout-seconds nil
           (lambda ()
             (when (and (eq batch decklet-backfill--active-batch)
                        (eq (decklet-backfill-task-status task) 'running)
                        (process-live-p (decklet-backfill-task-process task)))
               (setf (decklet-backfill-task-status task) 'timed-out)
               (delete-process (decklet-backfill-task-process task))))))))

(defun decklet-backfill--task-failure-message (task exit-code)
  "Return a failure message for TASK with EXIT-CODE."
  (pcase (decklet-backfill-task-status task)
    ('cancelled (format "Decklet backfill cancelled for \"%s\"" (decklet-backfill-task-word task)))
    ('timed-out (format "Decklet backfill timed out for \"%s\"" (decklet-backfill-task-word task)))
    (_ (format "Decklet backfill failed for \"%s\" (exit %d)"
               (decklet-backfill-task-word task)
               exit-code))))

(defun decklet-backfill--make-task (batch-id word)
  "Create a new backfill task for BATCH-ID and WORD."
  (decklet-backfill-task-create
   :word word
   :result-file (decklet-backfill--task-result-file batch-id word)
   :status 'pending))

(defun decklet-backfill--start-task (task batch)
  "Start TASK within BATCH."
  (decklet-backfill--clear-result-file (decklet-backfill-task-result-file task))
  (let* ((default-directory (file-name-as-directory (expand-file-name decklet-backfill-working-directory)))
         (buffer (generate-new-buffer (format " *decklet-backfill-%s*"
                                              (decklet-backfill-task-word task))))
         (args (append (list "run" "--format" "json")
                       (when decklet-backfill-opencode-model
                         (list "--model" decklet-backfill-opencode-model))
                       (list "--"
                             (decklet-backfill--prompt-with-output-file
                              (decklet-backfill-task-word task)
                              (decklet-backfill-task-result-file task)))))
         (process (apply #'start-process
                         (format "decklet-backfill-%s" (decklet-backfill-task-word task))
                         buffer
                         decklet-backfill-opencode-command
                         args)))
    (setf (decklet-backfill-task-process task) process
          (decklet-backfill-task-status task) 'running)
    (process-put process :decklet-batch batch)
    (process-put process :decklet-task task)
    (set-process-query-on-exit-flag process nil)
    (set-process-sentinel process #'decklet-backfill--process-sentinel)
    (decklet-backfill--start-timeout task batch)
    task))

(defun decklet-backfill--process-sentinel (process _event)
  "Handle async OpenCode completion for PROCESS."
  (when (memq (process-status process) '(exit signal))
    (let* ((batch (process-get process :decklet-batch))
           (task (process-get process :decklet-task))
           (exit-code (process-exit-status process))
           (buffer (process-buffer process)))
      (setf (decklet-backfill-task-session-id task)
            (or (decklet-backfill-task-session-id task)
                (decklet-backfill--extract-session-id buffer)))
      (unwind-protect
          (if (= exit-code 0)
              (condition-case err
                  (progn
                    (decklet-backfill--save-file-to-card-back
                     (decklet-backfill-task-word task)
                     (decklet-backfill-task-result-file task))
                    (setf (decklet-backfill-task-status task) 'success)
                    (let ((total (length (decklet-backfill-batch-tasks batch))))
                      (if (= total 1)
                          (message "Backfilled \"%s\"" (decklet-backfill-task-word task))
                        (message "Backfilled \"%s\" [%d/%d]"
                                 (decklet-backfill-task-word task)
                                 (decklet-backfill--batch-done-count batch)
                                 total))))
                (error
                  (setf (decklet-backfill-task-status task) 'failed
                        (decklet-backfill-task-error task) (error-message-string err))
                  (display-buffer buffer)
                  (message "Decklet backfill failed for \"%s\": %s"
                           (decklet-backfill-task-word task)
                           (error-message-string err))))
            (unless (memq (decklet-backfill-task-status task) '(cancelled timed-out))
              (setf (decklet-backfill-task-status task) 'failed))
            (unless (eq (decklet-backfill-task-status task) 'cancelled)
              (display-buffer buffer))
            (let ((total (length (decklet-backfill-batch-tasks batch))))
              (if (= total 1)
                  (message "%s" (decklet-backfill--task-failure-message task exit-code))
                (message "%s [%d/%d]"
                         (decklet-backfill--task-failure-message task exit-code)
                         (decklet-backfill--batch-done-count batch)
                         total))))
        (decklet-backfill--cancel-task-timer task)
        (when (and (buffer-live-p buffer)
                   (memq (decklet-backfill-task-status task) '(success cancelled)))
          (kill-buffer buffer))
        (decklet-backfill--cleanup-session task)
        (when batch
          (decklet-backfill--maybe-start-next-task batch)
          (decklet-backfill--finish-batch-if-done batch))))))

(defun decklet-backfill--start-batch (words)
  "Start async OpenCode backfill processes for WORDS as one batch."
  (decklet-backfill--ensure-idle)
  (decklet-backfill--ensure-runtime-directory)
  (let* ((batch-id (decklet-backfill--batch-id))
         (tasks (mapcar (lambda (word) (decklet-backfill--make-task batch-id word)) words))
         (batch (decklet-backfill-batch-create
                 :id batch-id
                 :tasks tasks
                 :source-buffer (current-buffer))))
    (setq decklet-backfill--active-batch batch)
    (mapc (lambda (task) (decklet-backfill--start-task task batch))
          (seq-take tasks decklet-backfill-max-concurrent-tasks))
    (message "Generating card backs for %d word%s..."
             (length tasks)
             (if (= (length tasks) 1) "" "s"))
    batch))

;;;###autoload
(defun decklet-backfill-cancel ()
  "Cancel the currently running Decklet backfill batch."
  (interactive)
  (unless decklet-backfill--active-batch
    (user-error "No Decklet backfill is currently running"))
  (dolist (task (decklet-backfill-batch-tasks decklet-backfill--active-batch))
    (pcase (decklet-backfill-task-status task)
      ('running
       (setf (decklet-backfill-task-status task) 'cancelled)
       (delete-process (decklet-backfill-task-process task)))
      ('pending
       (setf (decklet-backfill-task-status task) 'cancelled)))))

;;;###autoload
(defun decklet-backfill-current-word ()
  "Generate Decklet card back content for the current review/edit word.
When multiple words are marked in `decklet-edit-mode', offer batch generation."
  (interactive)
  (let* ((words (decklet-backfill--target-words))
         (prepared (decklet-backfill--prepare-words words)))
    (decklet-backfill--ensure-cards-exist prepared)
    (decklet-backfill--start-batch prepared)))

(provide 'decklet-backfill)

;;; decklet-backfill.el ends here
