# decklet-calendar

Shows [Decklet](https://github.com/yilin-zhang/decklet) due cards on the Emacs
calendar. Each date is colored by how many cards fall due that day, and
moving point onto a date shows the count.

## Setup

```emacs-lisp
(use-package decklet-calendar
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-calendar/"
  :after decklet
  :config (decklet-calendar-mode 1))
```

`decklet-calendar-mode` is a global minor mode. With it on, `M-x calendar`
shows the due highlights.

## Behavior

- Dates use four faces, from few to many due cards:
  `decklet-calendar-level-1-face` through `decklet-calendar-level-4-face`.
- Moving point onto a marked date echoes `N cards due on YYYY-MM-DD`.
- Overdue cards are counted on today, so they stay visible.

## Commands

| Command | Description |
|---|---|
| `M-x decklet-calendar-mode` | Toggle the global mode |
| `M-x decklet-calendar-mark-due-dates` | Re-mark the visible calendar |
| `M-x decklet-calendar-show-due-count-at-date` | Echo the count for the date at point |

## Customization

| Variable | Default | Description |
|---|---|---|
| `decklet-calendar-days-ahead` | `90` | How many days forward to count |
| `decklet-calendar-thresholds` | `(25 50 75)` | Cut-offs between the four color levels |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
