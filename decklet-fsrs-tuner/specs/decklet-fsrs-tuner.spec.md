---
summary: Fine-tune Decklet's FSRS parameters from the persistent review log via an async Python optimizer and a cached JSON handoff
---

# Decklet FSRS Tuner

## Purpose

Consumes `review-log.jsonl` (produced by `decklet-review-log.el`), runs
py-fsrs's `Optimizer` on the effective rating history, and produces an
optimized 21-float parameter vector that replaces the FSRS library
defaults for subsequent Decklet reviews.

## Entry points

### Interactive commands

| Command | Description |
|---|---|
| `decklet-fsrs-tuner-run` | Launch an async run of the Python tool; on success, offer to apply the new parameters |
| `decklet-fsrs-tuner-apply` | Load the cached JSON output and install the parameters now |

### Non-interactive helpers

| Function | Description |
|---|---|
| `decklet-fsrs-tuner--read-parameters` | Parse an output JSON file into a 21-float vector or nil |
| `decklet-fsrs-tuner--install-parameters` | Set `decklet-fsrs-parameters` and clear the cached scheduler |

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `decklet-fsrs-tuner-project-directory` | package dir | Working dir for `uv run` |
| `decklet-fsrs-tuner-log-file` | `nil` (→ `decklet-directory/review-log.jsonl`) | Review log input |
| `decklet-fsrs-tuner-output-file` | `nil` (→ `decklet-directory/fsrs-parameters.json`) | Tuned parameters output |
| `decklet-fsrs-tuner-min-reviews` | `400` | Minimum effective reviews before the optimizer runs |
| `decklet-fsrs-tuner-command` | `"uv"` | Command used to run the Python CLI |
| `decklet-fsrs-tuner-cli-name` | `"decklet-fsrs-tuner"` | Entrypoint name passed to `uv run` |
| `decklet-fsrs-tuner-auto-apply` | `t` | Auto-apply cached parameters on module load when the output file exists |

## Data flow

```
review-log.jsonl  ──► (Python) decklet-fsrs-tuner
                      - read + filter voids
                      - group by card_id
                      - py-fsrs Optimizer
                      - write JSON
                  ──► fsrs-parameters.json
                  ──► (Emacs) decklet-fsrs-tuner-apply
                      - parse JSON
                      - set decklet-fsrs-parameters
                      - clear decklet--fsrs-scheduler
                  ──► next review uses tuned weights
```

## Python tool

### CLI

```
uv run decklet-fsrs-tuner \
    --log    <review-log.jsonl> \
    --output <fsrs-parameters.json> \
    --min-reviews 400 \
    [--dry-run]
```

### Log parsing

One pass through the file:

1. `rated` records accumulate into a list.
2. `void` records accumulate their `voids` target into a set.
3. `rename` and unknown kinds are skipped (card_id is stable across
   renames, so the optimizer doesn't need rename hints).

Effective records are those whose `id` does not appear in the voided
set. They are grouped by `card_id` and sorted chronologically by `t`.

### Optimizer handoff

Each card's chronological record list becomes a `list[ReviewLog]`
handed to `fsrs.Optimizer`, which returns a 21-float parameter list.
`Rating` values come from the `grade` field (1→Again, 2→Hard,
3→Good, 4→Easy). Timestamps are parsed from the `t` field
(`YYYY-MM-DDTHH:MM:SSZ`).

### Output JSON

```json
{
  "parameters": [0.21, 1.29, ..., 0.15],
  "metrics": {
    "effective_reviews": 1234,
    "cards": 567,
    "voided": 3
  },
  "log_file": "/home/user/.emacs.d/decklet/review-log.jsonl",
  "generated_at": "2026-04-09T21:03:00Z"
}
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success (or dry-run with enough data) |
| `2` | Input error (log file missing, py-fsrs missing) |
| `3` | Not enough effective reviews for tuning |

On success, stdout includes a `TUNE_RESULT` line the Emacs side could
parse for metrics (not currently consumed — the JSON output is the
source of truth).

## Core dependency

The extension depends on one defcustom in `decklet-scheduler.el`:

```elisp
(defcustom decklet-fsrs-parameters nil
  "Optional override for the FSRS parameter weight vector."
  :set (lambda (symbol value)
         (set-default symbol value)
         (setq decklet--fsrs-scheduler nil))
  ...)
```

When non-nil, `decklet--get-fsrs-scheduler` passes it as
`:parameters` to `fsrs-make-scheduler`. The tuner sets this and
clears `decklet--fsrs-scheduler` directly, bypassing the
`:set` handler for speed (it would do the same work anyway).

## Error handling

- **Log file missing** — Python tool exits 2, Emacs shows the tuner
  output buffer.
- **Fewer than `min-reviews`** — Python tool exits 3, Emacs shows the
  buffer so the user can see the stderr message.
- **Malformed output JSON** — `decklet-fsrs-tuner--read-parameters`
  catches the parse error, returns nil, and messages the user. Any
  previously-installed parameters remain in effect.
- **Wrong number of parameters** — returns nil rather than installing
  a partial vector; `fsrs-make-scheduler` would reject it anyway.

## Files involved

| File | Role |
|---|---|
| `decklet-fsrs-tuner.el` | Emacs wrapper; run/apply commands; auto-apply-on-load |
| `tools/decklet_fsrs_tuner.py` | Python CLI: parse log, run Optimizer, write JSON |
| `pyproject.toml` | uv project manifest; depends on `fsrs>=5.0.0` |
| `decklet-scheduler.el` (core) | `decklet-fsrs-parameters` defcustom consumed here |
