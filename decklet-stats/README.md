# decklet-stats

Per-word review history visualizer for [Decklet](https://github.com/yilin-zhang/decklet).

Pops up a buffer showing a single card's full review trajectory:
header (card id, word, state, stability, difficulty, due, last
review), an ASCII chart of post-review stability over time, the
grade history, and a per-rating table.

Built on Decklet's public extension API and the persistent review log
(`decklet-review-log-file`, JSONL). No internals are touched; renames
are followed automatically because filtering is by `card_id`, and
voided ratings are skipped.

## Install

```emacs-lisp
(use-package decklet-stats
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-stats/"
  :hook ((decklet-review-mode . decklet-stats-mode)
         (decklet-edit-mode   . decklet-stats-mode)))
```

`decklet-stats-mode` is a buffer-local minor mode that owns the
`S` binding via `decklet-stats-mode-map`. Hooking it into the
Decklet modes loads the package as soon as you enter a review or
edit buffer, so the key is live from the very first card.

## Usage

- `S` (in a review or edit buffer) — pop up the stats for the
  card under point. The popup window is selected automatically;
  press `q` to kill it.
- `M-x decklet-stats-show` — works anywhere; resolves the word via
  `decklet-prompt-word` (current review word, edit list row at
  point, active region, or minibuffer prompt as fallback).

Sample output:

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
from `decklet-word-color` (bold), state `decklet-edit-state-face`,
stability `decklet-edit-stability-face`, difficulty
`decklet-edit-difficulty-face`, timestamps
`decklet-edit-last-review-face`. Labels are default foreground —
only values carry color, so structure reads cleanly.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `decklet-stats-log-file` | `nil` (use `decklet-review-log-file`) | Override log path |
| `decklet-stats-chart-height` | `8` | Rows in the ASCII chart |
| `decklet-stats-chart-max-width` | `60` | Cap on chart columns; older entries trimmed from chart only |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
