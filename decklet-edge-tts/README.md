# decklet-edge-tts

Local pronunciation audio for [Decklet](https://github.com/yilin-zhang/decklet)
flashcards, generated with Microsoft Edge TTS. Audio is generated offline into
a per-deck cache and played back from that cache during review — no network
call at review time.

Built on Decklet's public extension API.  Deleting a card drops its cached
audio automatically via the `decklet-cards-deleted-functions` hook.  Renames
are deliberately not auto-handled — the cached audio speaks the old word,
and neither renaming the file nor auto-deleting it is the right call — so
stale audio from renames is reconciled by the next `decklet-edge-tts-sync`.

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
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-edge-tts/"
  :custom
  (decklet-edge-tts-fallback-sound-file "~/.emacs.d/custom/decklet-next-word.mp3")
  (decklet-edge-tts-player-function #'my/decklet-play-sound)
  :hook ((decklet-review-mode . decklet-edge-tts-mode)
         (decklet-edit-mode   . decklet-edge-tts-mode)
         (decklet-review-next-card . decklet-edge-tts-play-next-word-or-fallback)))
```

By default, `decklet-edge-tts` follows `decklet-directory`:

- DB: `decklet-directory/decklet.sqlite`
- Audio cache: `decklet-directory/audio-cache/tts-edge`

So if you switch Decklet profiles by changing `decklet-directory`, this package
follows automatically.

## Mode and key bindings

`decklet-edge-tts-mode` is a buffer-local minor mode that owns the
package's key binding via `decklet-edge-tts-mode-map`. Hooking it
into review/edit loads the package eagerly — the lifecycle hooks
(delete/rename audio sync) become active from the first card.

| Key | Command | Description |
|---|---|---|
| `s` | `decklet-edge-tts-speak` | Play cached audio for the current word |
| `decklet-edge-tts-play-next-word-or-fallback` | Play audio for the current review card, falling back to a sound effect; designed for `decklet-review-next-card-hook` |
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
