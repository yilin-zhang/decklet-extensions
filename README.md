# decklet-extensions

A monorepo of extensions for [Decklet](https://github.com/yilin-zhang/decklet),
the Emacs spaced-repetition system for language learners.

Every package here is built on Decklet's public extension API — card
accessors, mutation wrappers, and card lifecycle hooks — without reaching
into Decklet internals. They all live in this single repo for ease of
maintenance, but each subdirectory is a self-contained Emacs Lisp package
with its own README and install snippet.

## Packages

| Package | Purpose |
|---|---|
| [`decklet-images`](./decklet-images/) | Per-word image sidecar: download from URL or copy from file, display in a popup, auto-sync via lifecycle hooks |
| [`decklet-edge-tts`](./decklet-edge-tts/) | Local pronunciation audio using Microsoft Edge TTS, with automatic cache sync via lifecycle hooks |
| [`decklet-backfill`](./decklet-backfill/) | Async AI-generated card backs using [opencode](https://opencode.ai) |
| [`decklet-fsrs-tuner`](./decklet-fsrs-tuner/) | Fine-tune Decklet's FSRS parameters from the persistent review log using [py-fsrs](https://github.com/open-spaced-repetition/py-fsrs)'s Optimizer |
| [`decklet-stats`](./decklet-stats/) | Per-word review history popup: stability chart, grade history, and full ratings table from the review log |

See each package's own README for usage details.

## Install

Each package is independent. Point `load-path` at whichever ones you want
and `require` them after Decklet:

```emacs-lisp
(use-package decklet-images
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-images/"
  :hook ((decklet-review-mode . decklet-images-mode)
         (decklet-edit-mode   . decklet-images-mode)))

(use-package decklet-edge-tts
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-edge-tts/"
  :after decklet)

(use-package decklet-backfill
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-backfill/"
  :after decklet)

(use-package decklet-fsrs-tuner
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-fsrs-tuner/"
  :after decklet
  :commands (decklet-fsrs-tuner-run decklet-fsrs-tuner-apply))

(use-package decklet-stats
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-stats/"
  :hook ((decklet-review-mode . decklet-stats-mode)
         (decklet-edit-mode   . decklet-stats-mode)))
```

## Layout

```
decklet-extensions/
├── README.md                 (this file)
├── LICENSE                   (GPL v3, covers every package)
├── decklet-images/
│   ├── README.md
│   └── decklet-images.el
├── decklet-edge-tts/
│   ├── README.md
│   ├── decklet-edge-tts.el
│   ├── pyproject.toml
│   ├── uv.lock
│   └── tools/
│       └── ...
├── decklet-backfill/
│   ├── README.md
│   ├── SKILL.md
│   └── decklet-backfill.el
├── decklet-fsrs-tuner/
│   ├── README.md
│   ├── decklet-fsrs-tuner.el
│   ├── pyproject.toml
│   ├── uv.lock
│   └── tools/
│       └── ...
└── decklet-stats/
    ├── README.md
    └── decklet-stats.el
```

## License

GPL v3. The repo-level [`LICENSE`](./LICENSE) covers every package.
