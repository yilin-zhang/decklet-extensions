# decklet-edge-tts

Local pronunciation audio for [Decklet](https://github.com/yilin-zhang/decklet)
flashcards, generated with Microsoft Edge TTS. Audio is generated offline into
a per-deck cache and played back from that cache during review — no network
call at review time.

Built on Decklet's public extension API: audio files are kept in sync with the
deck automatically via Decklet's card lifecycle hooks, so deleting or renaming
a word also deletes or renames its cached audio.

This repo contains:

- `decklet-edge-tts.el`: Emacs integration, playback command, sync subprocess
- `tools/decklet_tts.py`: Python CLI used by the Emacs package

## Setup

```bash
cd ~/.emacs.d/site-lisp/decklet-edge-tts
uv sync
```

## Emacs configuration

Load the package after Decklet and (optionally) bind the next-card hook to
auto-play audio when each card is shown:

```emacs-lisp
(defun my/decklet-play-sound (path)
  (start-process "decklet-sound" nil "afplay" (expand-file-name path)))

(use-package decklet-edge-tts
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-edge-tts/"
  :after decklet
  :custom
  (decklet-edge-tts-fallback-sound-file "~/.emacs.d/custom/decklet-next-word.mp3")
  (decklet-edge-tts-player-function #'my/decklet-play-sound)
  :hook
  (decklet-review-next-card . decklet-edge-tts-play-next-word-or-fallback))
```

By default, `decklet-edge-tts` follows `decklet-directory`:

- DB: `decklet-directory/decklet.sqlite`
- Audio cache: `decklet-directory/audio-cache/tts-edge`

So if you switch Decklet profiles by changing `decklet-directory`, this package
follows automatically.

## Commands and key bindings

On load, `decklet-edge-tts` binds `s` in both `decklet-review-mode` and
`decklet-edit-mode` to `decklet-edge-tts-speak`. Press `s` to play the cached
audio for the current word; Decklet messages when no audio exists for the
word.

| Command | Description |
|---|---|
| `decklet-edge-tts-speak` (bound to `s`) | Play cached audio for the current word |
| `decklet-edge-tts-play-next-word-or-fallback` | Play current-word audio, falling back to a sound effect; designed for `decklet-review-next-card-hook` |
| `M-x decklet-edge-tts-regenerate-word` | Rewrite/regenerate one word's audio, with optional spoken-text override |
| `M-x decklet-edge-tts-sync` | Sync the whole cache against the current Decklet DB |
| `C-u M-x decklet-edge-tts-sync` | Dry-run preview of what sync would do |

## Automatic sync with card lifecycle

On load, `decklet-edge-tts` subscribes to Decklet's card lifecycle hooks so
the audio cache stays in sync with the deck without any explicit action:

- `decklet-card-deleted-functions` — the cached audio file for a deleted
  word is removed immediately.
- `decklet-card-renamed-functions` — the cached audio file is renamed along
  with the word.

The batch `decklet-edge-tts-sync` command remains available as a fallback
for out-of-band drift — for example, after manually editing the database or
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
