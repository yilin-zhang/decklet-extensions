# decklet-extensions

Extensions for [Decklet](https://github.com/yilin-zhang/decklet), an Emacs
spaced-repetition system for language learners. Each subdirectory is a
separate Emacs Lisp package with its own README and install snippet.

## Packages

| Package | Purpose |
|---|---|
| [`decklet-calendar`](./decklet-calendar/) | Color the Emacs calendar by how many cards fall due each day |
| [`decklet-cloze`](./decklet-cloze/) | Hide the word on hinted cards and ask you to type it before grading |
| [`decklet-tts-edge`](./decklet-tts-edge/) | Generate pronunciation audio with Microsoft Edge TTS |
| [`decklet-fsrs-tuner`](./decklet-fsrs-tuner/) | Tune Decklet's FSRS parameters from your own review history with [py-fsrs](https://github.com/open-spaced-repetition/py-fsrs) |
| [`decklet-icloud`](./decklet-icloud/) | Refuse to open a deck stored in iCloud Drive while it is out of sync or open on another Mac |
| [`decklet-images`](./decklet-images/) | Attach an image to a card from a URL or a file and show it during review |
| [`decklet-import`](./decklet-import/) | Import saved words from Kindle (`vocab.db`) or Kobo (`KoboReader.sqlite`) |
| [`decklet-tts-kokoro`](./decklet-tts-kokoro/) | Generate local pronunciation audio with Kokoro, with reviewable pronunciations |
| [`decklet-skills`](./decklet-skills/) | Agent skills (Claude Code and compatible) for card backs and card illustrations |
| [`decklet-sound`](./decklet-sound/) | Play a card's pronunciation audio with `s` |
| [`decklet-stats`](./decklet-stats/) | Per-word review history and a deck-wide review heatmap |

## Checks

`./scripts/check-all.sh` runs indentation, byte-compile, checkdoc,
package-lint and ERT. CI runs the same script. It expects the Decklet core
checkout next to this repo (or at `DECKLET_CORE_DIR`).

Unit tests (`*-test.el`) run against a stub `decklet.el` in each package's
`tests/` directory. Integration tests (`*-integration-test.el`) run against
the real Decklet core.

## License

GPL v3. The repo-level [`LICENSE`](./LICENSE) covers every package.
