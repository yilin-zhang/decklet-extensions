# decklet-extensions

A monorepo of extensions for [Decklet](https://github.com/yilin-zhang/decklet),
an Emacs spaced-repetition system for language learners.

Every package here is built on Decklet's public extension API. They all live in
this single repo for ease of maintenance, but each subdirectory is a
self-contained Emacs Lisp package with its own README and install snippet.

## Packages

| Package | Purpose |
|---|---|
| [`decklet-images`](./decklet-images/) | Per-word image sidecar: download from URL or copy from file, display in a popup, auto-sync via lifecycle hooks |
| [`decklet-edge-tts`](./decklet-edge-tts/) | Local pronunciation audio using Microsoft Edge TTS, with automatic cache sync via lifecycle hooks |
| [`decklet-backfill`](./decklet-backfill/) | Async AI-generated card backs using [opencode](https://opencode.ai) |
| [`decklet-fsrs-tuner`](./decklet-fsrs-tuner/) | Fine-tune Decklet's FSRS parameters from the persistent review log using [py-fsrs](https://github.com/open-spaced-repetition/py-fsrs)'s Optimizer |
| [`decklet-stats`](./decklet-stats/) | Per-word review history popup: stability chart, grade history, and full ratings table from the review log |

## License

GPL v3. The repo-level [`LICENSE`](./LICENSE) covers every package.
