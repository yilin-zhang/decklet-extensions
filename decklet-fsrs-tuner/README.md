# decklet-fsrs-tuner

Fine-tunes Decklet's FSRS scheduling parameters from the persistent review log
(`review-log.jsonl`), using [py-fsrs](https://github.com/open-spaced-repetition/py-fsrs)'s
built-in optimizer.

It reads the log, filters out voided records, groups effective ratings by
`card_id`, hands the per-card review histories to the optimizer, and writes
the resulting 21-float parameter vector to a JSON file. The Emacs side then
installs the vector into `decklet-fsrs-parameters` and invalidates the
cached FSRS scheduler so subsequent reviews use the tuned weights.

## Usage

```
M-x decklet-fsrs-tuner-run     ; async tune; on success, offers to apply
M-x decklet-fsrs-tuner-apply   ; apply the cached output JSON now
```

The first run requires at least `decklet-fsrs-tuner-min-reviews` effective
reviews in the log (default 400). The Python tool will refuse to optimize with
fewer, matching py-fsrs's own guidance.

## Install

```emacs-lisp
(use-package decklet-fsrs-tuner
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-fsrs-tuner/"
  :after decklet
  :commands (decklet-fsrs-tuner-run decklet-fsrs-tuner-apply))
```

The first time you invoke `decklet-fsrs-tuner-run`, the Python side needs to
be set up once:

```
cd ~/.emacs.d/site-lisp/decklet-extensions/decklet-fsrs-tuner
uv sync
```

## Configuration

| Variable                             | Default                                   | Description                                                        |
|--------------------------------------|-------------------------------------------|--------------------------------------------------------------------|
| `decklet-fsrs-tuner-log-file`        | `nil` (→ `decklet-directory/review-log.jsonl`) | Review log input file                                         |
| `decklet-fsrs-tuner-output-file`     | `nil` (→ `decklet-directory/fsrs-parameters.json`) | Where to write the tuned parameters                       |
| `decklet-fsrs-tuner-min-reviews`     | `400`                                     | Minimum effective reviews the optimizer requires                   |
| `decklet-fsrs-tuner-command`         | `"uv"`                                    | Runner for the Python CLI                                          |
| `decklet-fsrs-tuner-cli-name`        | `"decklet-fsrs-tuner"`                    | CLI entrypoint name                                                |
| `decklet-fsrs-tuner-auto-apply`      | `t`                                       | Auto-apply cached parameters on load if the output file exists     |

## How applying works

`decklet-fsrs-parameters` lives in Decklet core (in `decklet-scheduler.el`).
When non-nil, it is passed as `:parameters` to `fsrs-make-scheduler`, overriding
the FSRS library's built-in default weights. Setting it clears the cached
scheduler instance so the next rating picks up the new weights.

`decklet-fsrs-tuner-apply` reads the JSON output file, validates the parameter
vector, sets `decklet-fsrs-parameters`, and invalidates the cached scheduler.
With `decklet-fsrs-tuner-auto-apply` set (the default), this also runs on
module load so Emacs sessions start pre-tuned.

## How the tuner handles the log

- **Voided ratings are skipped.** A `void` record nullifies the `rated` record
  with the matching `id`; the optimizer never sees it.
- **Renames are ignored.** `card_id` is stable across renames, so the optimizer
  groups by `card_id` and doesn't need rename hints.
- **Delete-and-re-add** creates two card histories (old `card_id`, new `card_id`)
  rather than one stitched-together chain — which is the correct thing for FSRS,
  since the "new" card's memory is genuinely independent of the deleted one's.
