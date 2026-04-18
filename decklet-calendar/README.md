# decklet-calendar

Calendar integration for [Decklet](https://github.com/yilin-zhang/decklet)
flashcards. Highlights dates on the built-in Emacs calendar with due-card
counts using a four-level color scale, and shows the count for the date
at point.

Built on Decklet's public API (`decklet-db-due-counts-by-date` and
`decklet-day-start-time`), with zero reach into the core's internals.

## Setup

```emacs-lisp
(use-package decklet-calendar
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-calendar/"
  :after decklet
  :config (decklet-calendar-mode 1))
```

`decklet-calendar-mode` is a **global** minor mode. Enabling it installs
itself on `calendar-mode-hook`, `calendar-today-visible-hook`,
`calendar-today-invisible-hook`, and `calendar-move-hook` so Emacs' built-in
calendar picks up Decklet's due highlights automatically the next time
you call `M-x calendar`.

## Behavior

- Dates with due cards are colored by density via four faces:
  - `decklet-calendar-level-1-face` (few)
  - `decklet-calendar-level-2-face` (some)
  - `decklet-calendar-level-3-face` (many)
  - `decklet-calendar-level-4-face` (very many)
- Thresholds are configurable via `decklet-calendar-thresholds`
  (default `'(25 50 75)`).
- Moving point onto a marked date echoes `N cards due on YYYY-MM-DD`
  in the minibuffer.
- Overdue cards (due before today's day-rollover) are folded onto today
  so they remain visible.

## Commands

| Command | Description |
|---|---|
| `M-x decklet-calendar-mode` | Toggle the global mode |
| `M-x decklet-calendar-mark-due-dates` | Re-mark the currently visible calendar |
| `M-x decklet-calendar-show-due-count-at-date` | Echo the count for the cursor date |

## Customization

| Variable | Default | Description |
|---|---|---|
| `decklet-calendar-days-ahead` | `90` | How many days forward to count |
| `decklet-calendar-thresholds` | `(25 50 75)` | Thresholds between the 4 color levels |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
