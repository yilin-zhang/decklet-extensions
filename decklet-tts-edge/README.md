# decklet-tts-edge

Per-word pronunciation audio generator for
[Decklet](https://github.com/yilin-zhang/decklet) flashcards, backed by
Microsoft Edge TTS. Audio is generated offline into a per-deck cache — no
network call at review time.

Playback is handled by the companion
[`decklet-sound`](../decklet-sound/) package. `decklet-tts-edge` writes
into `decklet-sound`'s cache directory (default
`decklet-directory/audio-cache/tts-edge/`) and never touches the audio
playback path.

Audio files are named by card id, `<card-id>.mp3` (via Decklet's
`decklet-card-sidecar-file`), so two cards whose words differ only in case get
separate recordings even on a case-insensitive file system. On load, this
package subscribes to the card lifecycle hooks: deleting a card deletes its
cached audio, and renaming one moves the stale recording to the trash so the
next `decklet-tts-edge-sync` regenerates it.

This repo contains:

- `decklet-tts-edge.el`: Emacs integration, generation commands, sync
  subprocess, card-deleted cleanup hook
- `tools/decklet_tts_edge.py`: Python CLI used by the Emacs package

## Setup

You need [`uv`](https://docs.astral.sh/uv/) on `PATH`. Once the package is
loaded in Emacs, run `M-x decklet-tts-edge-install` to create or update the
Python virtualenv — this shells out to `uv sync` in the project directory.

The shell equivalent, if you prefer:

```bash
cd ~/.emacs.d/site-lisp/decklet-extensions/decklet-tts-edge
uv sync
```

You also need `decklet-sound` loaded for playback; see
[that package's README](../decklet-sound/README.md).

## Emacs configuration

```emacs-lisp
(use-package decklet-tts-edge
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-tts-edge/"
  :after decklet-sound
  :commands (decklet-tts-edge-install
             decklet-tts-edge-sync
             decklet-tts-edge-regenerate-word))
```

By default, `decklet-tts-edge` writes into the cache directory exposed by
`decklet-sound` (`decklet-directory/audio-cache/tts-edge` unless
`decklet-sound-audio-directory` is set).

So if you switch Decklet profiles by changing `decklet-directory`, this
package follows automatically.

## Commands

| Command | Description |
|---|---|
| `M-x decklet-tts-edge-install` | Set up (or refresh) the Python environment via `uv sync` |
| `M-x decklet-tts-edge-regenerate-word` | Rewrite/regenerate one word's audio, with optional spoken-text override |
| `M-x decklet-tts-edge-sync` | Sync the whole cache against the current Decklet DB |
| `C-u M-x decklet-tts-edge-sync` | Dry-run preview of what sync would do |

Sync and install pop up their log buffer (`*Decklet Edge TTS Sync*` /
`*Decklet Edge TTS Install*`). Sync reports how many words it will generate
and then one line per word (`[37/412] ok: abate`), so a long run is visible
as it happens. Set `decklet-tts-edge-display-log` to nil to keep the window
from appearing; the buffer is still written either way, and a failing command
always shows it. One-off regeneration is fast and never pops up a window.

## Automatic sync with card lifecycle

On load, `decklet-tts-edge` subscribes to two lifecycle hooks:

- `decklet-cards-deleted-functions` — the deleted card's cached audio is
  removed immediately.
- `decklet-cards-renamed-functions` — the card keeps its id, so its file now
  holds a recording of the old word. It is moved to the system trash (not
  deleted, so it stays recoverable) and the next `decklet-tts-edge-sync`
  generates audio for the new word.

The batch `decklet-tts-edge-sync` command is also the fallback for other
out-of-band drift — for example, after manually editing the database or
restoring from a backup.

## CLI

Generate missing audio:

```bash
uv run decklet-tts-edge \
  --db ~/.emacs.d/decklet/decklet.sqlite \
  --out-dir ~/.emacs.d/decklet/audio-cache/tts-edge
```

Sync cache against DB:

```bash
uv run decklet-tts-edge \
  --sync \
  --db ~/.emacs.d/decklet/decklet.sqlite \
  --out-dir ~/.emacs.d/decklet/audio-cache/tts-edge
```
