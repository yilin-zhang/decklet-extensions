;;; decklet-fsrs-tuner.el --- Fine-tune Decklet FSRS parameters -*- lexical-binding: t; -*-

;; Author: Yilin Zhang
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools

;;; Commentary:

;; Fine-tunes Decklet's FSRS scheduling parameters from the
;; persistent review log (`review-log.jsonl') produced by
;; `decklet-review-log.el'.
;;
;; Runs an external Python tool (via `uv run decklet-fsrs-tuner ...')
;; that uses py-fsrs's Optimizer to compute an optimal 21-float
;; parameter vector, writes it to a JSON file, and optionally
;; applies it back into Decklet by setting `decklet-fsrs-parameters'
;; and invalidating the cached scheduler.
;;
;; Entry points:
;;
;;   M-x decklet-fsrs-tuner-run   — async tune; on success, offer to apply
;;   M-x decklet-fsrs-tuner-apply — load the output JSON into Decklet now
;;
;; On load, if `decklet-fsrs-tuner-auto-apply' is non-nil (default)
;; and the output file already exists, the parameters are applied
;; immediately so Decklet starts the session with tuned weights.

;;; Code:

(require 'json)
(require 'subr-x)

(require 'decklet)

(defgroup decklet-fsrs-tuner nil
  "Fine-tune Decklet FSRS parameters from the review log."
  :group 'tools)

(defcustom decklet-fsrs-tuner-project-directory
  (file-name-directory
   (or load-file-name (locate-library "decklet-fsrs-tuner") default-directory))
  "Directory containing the decklet-fsrs-tuner project."
  :type 'directory
  :group 'decklet-fsrs-tuner)

(defcustom decklet-fsrs-tuner-log-file nil
  "Override path to the review log JSONL file.
When nil, use `decklet-directory'/review-log.jsonl."
  :type '(choice (const :tag "Use decklet-directory" nil) file)
  :group 'decklet-fsrs-tuner)

(defcustom decklet-fsrs-tuner-output-file nil
  "Override path to the tuned parameters JSON output file.
When nil, use `decklet-directory'/fsrs-parameters.json."
  :type '(choice (const :tag "Use decklet-directory" nil) file)
  :group 'decklet-fsrs-tuner)

(defcustom decklet-fsrs-tuner-min-reviews 400
  "Minimum effective (non-voided) reviews required before tuning runs.
Passed through to the Python tool as `--min-reviews'.  py-fsrs
recommends at least a few hundred reviews before tuning produces
meaningful results."
  :type 'integer
  :group 'decklet-fsrs-tuner)

(defcustom decklet-fsrs-tuner-command "uv"
  "Command used to invoke the Python CLI."
  :type 'string
  :group 'decklet-fsrs-tuner)

(defcustom decklet-fsrs-tuner-cli-name "decklet-fsrs-tuner"
  "CLI entrypoint name used with `decklet-fsrs-tuner-command'."
  :type 'string
  :group 'decklet-fsrs-tuner)

(defcustom decklet-fsrs-tuner-auto-apply t
  "When non-nil, apply the cached parameters on load if the output file exists.
Set to nil to require an explicit `M-x decklet-fsrs-tuner-apply'."
  :type 'boolean
  :group 'decklet-fsrs-tuner)

(defvar decklet-fsrs-tuner--run-buffer-name "*Decklet FSRS Tuner*"
  "Buffer used to capture tuner output.")

(defun decklet-fsrs-tuner--log-file ()
  "Return the resolved review log path."
  (expand-file-name
   (or decklet-fsrs-tuner-log-file
       (expand-file-name "review-log.jsonl" decklet-directory))))

(defun decklet-fsrs-tuner--output-file ()
  "Return the resolved output parameters JSON path."
  (expand-file-name
   (or decklet-fsrs-tuner-output-file
       (expand-file-name "fsrs-parameters.json" decklet-directory))))

(defun decklet-fsrs-tuner--append-log (lines)
  "Append LINES to the tuner output buffer with a timestamp header."
  (with-current-buffer (get-buffer-create decklet-fsrs-tuner--run-buffer-name)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert (format-time-string "[%Y-%m-%d %H:%M:%S] "))
    (insert (car lines) "\n")
    (dolist (line (cdr lines))
      (insert "  " line "\n"))))

(defun decklet-fsrs-tuner--read-parameters (file)
  "Parse FILE and return the parameters vector, or nil on malformed input."
  (when (file-exists-p file)
    (condition-case err
        (let* ((json-object-type 'alist)
               (json-array-type 'vector)
               (data (with-temp-buffer
                       (insert-file-contents file)
                       (json-read)))
               (params (alist-get 'parameters data)))
          (when (and (vectorp params) (= 21 (length params)))
            (let ((floats (make-vector 21 0.0))
                  (i 0))
              (while (< i 21)
                (aset floats i (float (aref params i)))
                (setq i (1+ i)))
              floats)))
      (error
       (message "Decklet FSRS tuner: failed to parse %s: %s"
                file (error-message-string err))
       nil))))

(defun decklet-fsrs-tuner--install-parameters (params)
  "Install PARAMS as the active FSRS parameter vector and rebuild the scheduler."
  (setq decklet-fsrs-parameters params)
  (setq decklet--fsrs-scheduler nil))

(defun decklet-fsrs-tuner--run-args ()
  "Return the CLI args to run the tuner."
  (list "run" decklet-fsrs-tuner-cli-name
        "--log" (decklet-fsrs-tuner--log-file)
        "--output" (decklet-fsrs-tuner--output-file)
        "--min-reviews" (number-to-string decklet-fsrs-tuner-min-reviews)))

;;;###autoload
(defun decklet-fsrs-tuner-apply ()
  "Load the cached tuned parameters and apply them to Decklet.
Returns the parameter vector on success, nil if no output file is
available or it could not be parsed."
  (interactive)
  (let* ((file (decklet-fsrs-tuner--output-file))
         (params (decklet-fsrs-tuner--read-parameters file)))
    (cond
     ((null params)
      (when (called-interactively-p 'any)
        (message "Decklet FSRS tuner: no usable parameters at %s" file))
      nil)
     (t
      (decklet-fsrs-tuner--install-parameters params)
      (when (called-interactively-p 'any)
        (message "Decklet FSRS tuner: applied %d parameters from %s"
                 (length params) file))
      params))))

;;;###autoload
(defun decklet-fsrs-tuner-run ()
  "Run the FSRS parameter tuner asynchronously.
On success, offer to apply the new parameters immediately."
  (interactive)
  (let* ((default-directory (file-name-as-directory
                             (expand-file-name decklet-fsrs-tuner-project-directory)))
         (buffer (get-buffer-create decklet-fsrs-tuner--run-buffer-name))
         (active (get-process "decklet-fsrs-tuner"))
         (args (decklet-fsrs-tuner--run-args)))
    (when (and active (process-live-p active))
      (user-error "Decklet FSRS tuner is already running"))
    (decklet-fsrs-tuner--append-log
     (list (format "Start: %s %s"
                   decklet-fsrs-tuner-command
                   (mapconcat #'identity args " "))))
    (let ((process (apply #'start-process
                          "decklet-fsrs-tuner" buffer
                          decklet-fsrs-tuner-command args)))
      (set-process-query-on-exit-flag process nil)
      (set-process-sentinel
       process
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (let ((exit-code (process-exit-status proc)))
             (decklet-fsrs-tuner--append-log
              (list (format "Done: exit code %d" exit-code)))
             (cond
              ((= 0 exit-code)
               (message "Decklet FSRS tuner finished — %s to apply"
                        (substitute-command-keys
                         "use \\[decklet-fsrs-tuner-apply]"))
               (when (y-or-n-p "Apply new FSRS parameters now? ")
                 (decklet-fsrs-tuner-apply)))
              (t
               (message "Decklet FSRS tuner failed (exit %d); see %s"
                        exit-code decklet-fsrs-tuner--run-buffer-name)
               (display-buffer (process-buffer proc))))))))
      (message "Decklet FSRS tuner started..."))))

;; Auto-apply cached parameters on load.

(when (and decklet-fsrs-tuner-auto-apply
           (file-exists-p (decklet-fsrs-tuner--output-file)))
  (decklet-fsrs-tuner-apply))

(provide 'decklet-fsrs-tuner)

;;; decklet-fsrs-tuner.el ends here
