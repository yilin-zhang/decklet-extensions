# decklet-stats

Review statistics for [Decklet](https://github.com/yilin-zhang/decklet):

- **Per-word popup** (`S`): the card's state, a chart of its stability over
  time, its grade history and every rating.
- **Deck-wide heatmap** (`C-c H`): a GitHub-style calendar of how many
  reviews you did each day.

## Install

```emacs-lisp
(use-package decklet-stats
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-stats/"
  :hook ((decklet-review-mode . decklet-stats-mode)
         (decklet-edit-mode   . decklet-stats-mode)))
```

## Usage

| Key or command | Action |
|---|---|
| `S` (review or edit buffer) | Show stats for the current card. Press `q` to close. |
| `C-c H` (review or edit buffer) | Show the deck-wide heatmap. |
| `M-x decklet-stats-show` | Works anywhere. Uses the selected text, the current card, or asks for a word. |
| `M-x decklet-stats-heatmap` | A numeric prefix sets the number of weeks for one view, for example `C-u 12 M-x decklet-stats-heatmap`. |

Per-word sample output:

```
Card ID:    1736942112000123
Word:       serendipity
State:      review
Stability:  12.34 d    Difficulty: 5.67
Last:       2026-04-10 09:12
Due:        2026-04-22 09:12
Reviews:    8 effective (1 voided)

Stability (days) over time
  12.3 │           ██
       │          ███
       │         ████
       │        █████
       │       ██████
       │      ███████
       │    █████████
       │ ████████████
       └────────────

Grades: 34431443

#   When              Grade Δdays  S (pre→post) D (pre→post)
──────────────────────────────────────────────────────────────────────
1   2026-01-04 09:12    3   0.0    0.50→ 1.20   5.00→4.95
...
```

Heatmap sample output, with `decklet-stats-heatmap-thresholds` set to
`(26 51 76)`:

```
Decklet review heatmap
Last 52 weeks ending 2026-04-18

    Apr   Jun Jul Aug  Sep Oct Nov  Dec Jan  Feb Mar Apr
Sun ·▓▓█░░▒▒▓▓█░░▒▒▓▓█░░▒▒▓▓█░░▒▓▓█░░▒▒▓▓█░░▒▒▓▓█░░░▒▓▓█
Mon ·▒▓▓█░░▒▒▓▓█░░▒▒▓▓█░░▒▒▓▓█░░▒▓▓█░░▒▒▓▓█░░▒▒▓██░░▒▒▓▓
...

Total: 16031 reviews across 357 active days.  Peak: 89 on 2025-06-04.
Legend:  · 0  ░ 1-25  ▒ 26-50  ▓ 51-75  █ 76+
```

Days with no reviews show as a gray `·`. Hover over a cell to see its date and
count. Days start at Decklet's rollover hour, and rows follow
`calendar-week-start-day`.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `decklet-stats-log-file` | `nil` (uses `decklet-review-log-file`) | Review log to read |
| `decklet-stats-chart-height` | `8` | Rows in the stability chart |
| `decklet-stats-chart-max-width` | `60` | Most columns in the stability chart; older ratings drop off the chart only |
| `decklet-stats-heatmap-weeks` | `52` | Weeks shown in the heatmap |
| `decklet-stats-heatmap-thresholds` | `(50 100 150)` | Three cut-offs that split daily counts into four shades |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
