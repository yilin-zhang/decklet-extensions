# decklet-stats

Review visualizer for [Decklet](https://github.com/yilin-zhang/decklet).
Two entry points:

- **Per-word popup** (`decklet-stats-show`, bound to `S`) — a card's
  full review trajectory: header (card id, word, state, stability,
  difficulty, due, last review), an ASCII chart of post-review
  stability over time, the grade history, and a per-rating table.
- **Deck-wide heatmap** (`decklet-stats-heatmap`, bound to `H`) — a
  GitHub-style calendar of review activity across all cards. Days
  bucket by `decklet-day-start-time` so late-night reviews match the
  scheduler's day boundary.

Both read the persistent review log (`decklet-review-log-file`,
JSONL) and skip voided ratings. No Decklet internals are touched;
per-word renames are followed automatically because filtering is by
`card_id`.

## Install

```emacs-lisp
(use-package decklet-stats
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-stats/"
  :hook ((decklet-review-mode . decklet-stats-mode)
         (decklet-edit-mode   . decklet-stats-mode)))
```

`decklet-stats-mode` is a buffer-local minor mode that owns the
`S` and `H` bindings via `decklet-stats-mode-map`. Hooking it into
the Decklet modes loads the package as soon as you enter a review
or edit buffer, so the keys are live from the very first card.

## Usage

- `S` (in a review or edit buffer) — pop up the per-word stats for
  the card under point. The popup window is selected automatically;
  press `q` to kill it.
- `H` (in a review or edit buffer) — pop up the deck-wide
  heatmap.
- `M-x decklet-stats-show` — works anywhere; resolves the word via
  `decklet-prompt-word` (current review word, edit list row at
  point, active region, or minibuffer prompt as fallback).
- `M-x decklet-stats-heatmap` — deck-wide heatmap; a numeric prefix
  overrides `decklet-stats-heatmap-weeks` for one-off views
  (e.g. `C-u 12 M-x decklet-stats-heatmap` for the last quarter).

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

Colors follow Decklet's main palette: the word pulls its foreground
from `decklet-color-word` (bold), state `decklet-edit-state-face`,
stability `decklet-edit-stability-face`, difficulty
`decklet-edit-difficulty-face`, timestamps
`decklet-edit-last-review-face`. Labels are default foreground —
only values carry color, so structure reads cleanly.

Heatmap sample output:

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

Cells bucket by count using `decklet-stats-heatmap-thresholds`
(default `(50 100 150)` — three cut-offs for four non-zero
buckets: `░ 1-49`, `▒ 50-99`, `▓ 100-149`, `█ 150+`). Zero-review
days render separately as a gray `·` so rest days stand out
against activity; all non-zero buckets share a single green face
and convey intensity through shade-block density alone. Each cell
carries a `help-echo` with the date and count. Month labels sit
above the column that contains the 1st of the month; narrow views
may drop a label or two when months are adjacent. Weekday rows
honor `calendar-week-start-day`.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `decklet-stats-log-file` | `nil` (use `decklet-review-log-file`) | Override log path |
| `decklet-stats-chart-height` | `8` | Rows in the per-word ASCII chart |
| `decklet-stats-chart-max-width` | `60` | Cap on per-word chart columns; older entries trimmed from chart only |
| `decklet-stats-heatmap-weeks` | `52` | Columns (weeks) shown in the heatmap |
| `decklet-stats-heatmap-thresholds` | `(50 100 150)` | Three ascending cut-offs that split counts into four buckets (low/mid/high/max) |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
