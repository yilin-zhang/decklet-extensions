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

See each package's own README for usage details.

## Install

Each package is independent. Point `load-path` at whichever ones you want
and `require` them after Decklet:

```emacs-lisp
(use-package decklet-images
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-images/"
  :after decklet)

(use-package decklet-edge-tts
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-edge-tts/"
  :after decklet)

(use-package decklet-backfill
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-backfill/"
  :after decklet)
```

## Layout

```
decklet-extensions/
├── README.md                 (this file)
├── decklet-images/
│   ├── README.md
│   ├── LICENSE
│   └── decklet-images.el
├── decklet-edge-tts/
│   ├── README.md
│   ├── LICENSE
│   ├── decklet-edge-tts.el
│   ├── pyproject.toml
│   ├── uv.lock
│   └── tools/
│       └── ...
└── decklet-backfill/
    ├── README.md
    ├── LICENSE
    ├── SKILL.md
    └── decklet-backfill.el
```

## License

Each package is GPL v3. See each package's own `LICENSE` file.
