# decklet-edge-tts

Per-word pronunciation audio generator for
[Decklet](https://github.com/yilin-zhang/decklet) flashcards, backed by
Microsoft Edge TTS. Audio is generated offline into a per-deck cache — no
network call at review time.

Playback is handled by the companion
[`decklet-sound`](../decklet-sound/) package. `decklet-edge-tts` writes
into `decklet-sound`'s cache directory (default
`decklet-directory/audio-cache/tts-edge/`) and never touches the audio
playback path.

On load, this package subscribes to `decklet-cards-deleted-functions`, so
deleting a card also deletes its cached audio automatically. Renames are
deliberately not auto-handled — the cached audio speaks the old word, and
neither renaming the file nor auto-deleting it is the right call — so
stale audio from renames is reconciled by the next `decklet-edge-tts-sync`.

This repo contains:

- `decklet-edge-tts.el`: Emacs integration, generation commands, sync
  subprocess, card-deleted cleanup hook
- `tools/decklet_tts.py`: Python CLI used by the Emacs package

## Setup

You need [`uv`](https://docs.astral.sh/uv/) on `PATH`. Once the package is
loaded in Emacs, run `M-x decklet-edge-tts-install` to create or update the
Python virtualenv — this shells out to `uv sync` in the project directory.

The shell equivalent, if you prefer:

```bash
cd ~/.emacs.d/site-lisp/decklet-extensions/decklet-edge-tts
uv sync
```

You also need `decklet-sound` loaded for playback; see
[that package's README](../decklet-sound/README.md).

## Emacs configuration

```emacs-lisp
(use-package decklet-edge-tts
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-edge-tts/"
  :after decklet-sound
  :commands (decklet-edge-tts-install
             decklet-edge-tts-sync
             decklet-edge-tts-regenerate-word))
```

By default, `decklet-edge-tts` writes into the cache directory exposed by
`decklet-sound` (`decklet-directory/audio-cache/tts-edge` unless
`decklet-sound-audio-directory` is set).

So if you switch Decklet profiles by changing `decklet-directory`, this
package follows automatically.

## Commands

| Command | Description |
|---|---|
| `M-x decklet-edge-tts-install` | Set up (or refresh) the Python environment via `uv sync` |
| `M-x decklet-edge-tts-regenerate-word` | Rewrite/regenerate one word's audio, with optional spoken-text override |
| `M-x decklet-edge-tts-sync` | Sync the whole cache against the current Decklet DB |
| `C-u M-x decklet-edge-tts-sync` | Dry-run preview of what sync would do |

## Automatic sync with card lifecycle

On load, `decklet-edge-tts` subscribes to `decklet-cards-deleted-functions`
so the cached audio for a deleted card's pre-delete word snapshot is
removed immediately.

Renames are **not** auto-handled.  The cached audio is a recording of the
old word's pronunciation, so renaming the file would leave stale content
under the new slug.  Automatic deletion is also avoided so the file is
preserved until the user explicitly decides what to do.  The stale entry
is cleaned up by the next `decklet-edge-tts-sync` run.

The batch `decklet-edge-tts-sync` command is also the fallback for other
out-of-band drift — for example, after manually editing the database or
restoring from a backup.

## CLI

Generate missing audio:

```bash
uv run decklet-edge-tts \
  --db ~/.emacs.d/decklet/decklet.sqlite \
  --out-dir ~/.emacs.d/decklet/audio-cache/tts-edge
```

Sync cache against DB:

```bash
uv run decklet-edge-tts \
  --sync \
  --db ~/.emacs.d/decklet/decklet.sqlite \
  --out-dir ~/.emacs.d/decklet/audio-cache/tts-edge
```
