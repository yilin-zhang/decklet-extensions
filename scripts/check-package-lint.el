;;; check-package-lint.el --- package-lint setup for decklet-extensions -*- lexical-binding: t; -*-

;;; Commentary:

;; Invoked by `check-package-lint.sh' once per extension package.

;;; Code:

(require 'package)
(require 'seq)

(defconst decklet-ext-check-local-packages '(decklet decklet-sound)
  "Dependencies that live in these repos rather than on a package archive.")

(defun decklet-ext-check--skip-local-packages (deps)
  "Return DEPS without `decklet-ext-check-local-packages'.
Used as `:filter-args' advice on the installability check: the local
packages are not on any archive, so package-lint would otherwise report
every extension as depending on an uninstallable package."
  (list (seq-remove (lambda (dep)
                      (memq (car dep) decklet-ext-check-local-packages))
                    (car deps))))

(defun decklet-ext-check-configure-package-lint ()
  "Configure package-lint for the extension packages.
Points package.el at the real archives (for the `emacs' and `fsrs'
version checks) and exempts the local Decklet packages from the
installability check.  `package-lint-batch-and-exit' re-runs
`package-initialize', which would discard any fake archive entry, so
the exemption is advice rather than data."
  (setq package-archives
        '(("gnu" . "https://elpa.gnu.org/packages/")
          ("nongnu" . "https://elpa.nongnu.org/nongnu/")
          ("melpa" . "https://melpa.org/packages/")))
  (package-initialize t)
  (unless (assq 'fsrs package-archive-contents)
    (package-refresh-contents))
  (advice-add 'package-lint--check-packages-installable :filter-args
              #'decklet-ext-check--skip-local-packages)
  (setq package-lint-main-file (getenv "DECKLET_EXT_MAIN_FILE")))

(provide 'check-package-lint)
;;; check-package-lint.el ends here
