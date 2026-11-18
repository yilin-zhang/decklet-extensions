# decklet-fsrs-tuner

Fits [Decklet](https://github.com/yilin-zhang/decklet)'s FSRS parameters to
your own review history. It runs
[py-fsrs](https://github.com/open-spaced-repetition/py-fsrs)'s optimizer on
the review log and saves the result to a JSON file, which Decklet then uses
for scheduling.

## Setup

You need [`uv`](https://docs.astral.sh/uv/) on `PATH`.

```emacs-lisp
(use-package decklet-fsrs-tuner
  :vc (:url "https://github.com/yilin-zhang/decklet-extensions"
       :lisp-dir "decklet-fsrs-tuner"
       :rev :newest)
  :after decklet
  :custom
  ;; Where to save the tuned parameters; a relative name is inside
  ;; `decklet-directory'.
  ;; (decklet-fsrs-tuner-output-file "fsrs-parameters.json")
  ;; Minimum reviews needed to tune.
  ;; (decklet-fsrs-tuner-min-reviews 400)
  ;; Apply saved parameters when the package loads.
  ;; (decklet-fsrs-tuner-auto-apply t)
  :commands (decklet-fsrs-tuner-run decklet-fsrs-tuner-apply))
```

Then set up the Python environment once:

```bash
cd ~/.emacs.d/elpa/decklet-fsrs-tuner/decklet-fsrs-tuner
uv sync
```

## Usage

| Key or command | Description |
|---|---|
| `M-x decklet-fsrs-tuner-run` | Tune in the background, then offer to apply the result |
| `M-x decklet-fsrs-tuner-apply` | Apply the saved parameters now |

Tuning needs at least `decklet-fsrs-tuner-min-reviews` reviews in the log. New
parameters take effect from the next rating. A file with the wrong length or
out-of-range weights is reported and not applied.

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
