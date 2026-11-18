# decklet-fsrs-tuner

Tunes Decklet's FSRS scheduling parameters to your own review history. It
reads the review log, runs
[py-fsrs](https://github.com/open-spaced-repetition/py-fsrs)'s optimizer, and
saves the result to a JSON file that Decklet then uses for scheduling.

## Install

```emacs-lisp
(use-package decklet-fsrs-tuner
  :vc (:url "https://github.com/yilin-zhang/decklet-extensions"
       :lisp-dir "decklet-fsrs-tuner"
       :rev :newest)
  :after decklet
  :commands (decklet-fsrs-tuner-run decklet-fsrs-tuner-apply))
```

Set up the Python side once, with [`uv`](https://docs.astral.sh/uv/):

```
cd ~/.emacs.d/elpa/decklet-fsrs-tuner/decklet-fsrs-tuner
uv sync
```

## Usage

```
M-x decklet-fsrs-tuner-run     ; tune in the background, then offer to apply
M-x decklet-fsrs-tuner-apply   ; apply the saved parameters now
```

Tuning needs at least `decklet-fsrs-tuner-min-reviews` reviews in the log.

Applying takes effect from the next rating. A parameter file with the wrong
length or out-of-range weights is reported and not applied. With
`decklet-fsrs-tuner-auto-apply` on (the default), saved parameters are also
applied whenever the package loads.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `decklet-fsrs-tuner-output-file` | `"fsrs-parameters.json"` | Where to save the tuned parameters; a relative name is inside the Decklet data directory (`decklet-directory`) |
| `decklet-fsrs-tuner-min-reviews` | `400` | Minimum reviews needed to tune |
| `decklet-fsrs-tuner-auto-apply` | `t` | Apply saved parameters when the package loads |
