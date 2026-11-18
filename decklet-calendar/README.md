# decklet-calendar

Colors the Emacs calendar by how many
[Decklet](https://github.com/yilin-zhang/decklet) cards fall due each day.

## Setup

```emacs-lisp
(use-package decklet-calendar
  :vc (:url "https://github.com/yilin-zhang/decklet-extensions"
       :lisp-dir "decklet-calendar"
       :rev :newest)
  :after decklet
  :custom
  ;; How many days forward to count.
  ;; (decklet-calendar-days-ahead 90)
  ;; Cut-offs between the four color levels.
  ;; (decklet-calendar-thresholds '(25 50 75))
  :config (decklet-calendar-mode 1))
```

## Usage

With `decklet-calendar-mode` on, `M-x calendar` colors each date with
`decklet-calendar-level-1-face` through `decklet-calendar-level-4-face`, from
few to many due cards. Overdue cards count toward today. Moving point onto a
marked date shows `N cards due on YYYY-MM-DD`.

| Key or command | Description |
|---|---|
| `M-x decklet-calendar-mode` | Toggle the global mode |
| `M-x decklet-calendar-mark-due-dates` | Re-mark the visible calendar |
| `M-x decklet-calendar-show-due-count-at-date` | Show the count for the date at point |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
