# decklet-tts-edge

Generates pronunciation audio for
[Decklet](https://github.com/yilin-zhang/decklet) cards with Microsoft Edge
TTS. Audio is generated ahead of time, so review needs no network.
[`decklet-sound`](../decklet-sound/) plays it.

## Setup

You need [`uv`](https://docs.astral.sh/uv/) on `PATH`, and `decklet-sound`
for playback.

```emacs-lisp
(use-package decklet-tts-edge
  :vc (:url "https://github.com/yilin-zhang/decklet-extensions"
       :lisp-dir "decklet-tts-edge"
       :rev :newest)
  :after decklet-sound
  :commands (decklet-tts-edge-install
             decklet-tts-edge-sync
             decklet-tts-edge-regenerate-word))
```

Then run `M-x decklet-tts-edge-install` once to set up the Python environment.

Audio goes into the `audio-cache/tts-edge` folder inside your Decklet data
directory (`decklet-directory`). Set `decklet-tts-edge-audio-directory` to use
another folder. A relative name is taken inside the Decklet data directory.
Edge audio plays only when no other generator has a file for the card.

## Commands

| Command | Description |
|---|---|
| `M-x decklet-tts-edge-install` | Set up or refresh the Python environment |
| `M-x decklet-tts-edge-sync` | Generate audio for every card that lacks it, and move audio for cards that are gone to the trash |
| `C-u M-x decklet-tts-edge-sync` | Preview what sync would do |
| `M-x decklet-tts-edge-regenerate-word` | Regenerate one word's audio, optionally with different text to speak |

Sync and install show their progress in a log buffer, one line per word
(`[37/412] ok: abate`). Set `decklet-tts-edge-display-log` to nil to keep that
window from popping up. It still shows when a command fails.

Deleting a card deletes its audio. Renaming a card moves the old recording to
the trash, and the next sync records the new word. Run a sync after editing
the database by hand or restoring a backup.

## CLI

The same tool runs from a shell. Generate missing audio:

```bash
uv run decklet-tts-edge \
  --db ~/.emacs.d/decklet/decklet.sqlite \
  --out-dir ~/.emacs.d/decklet/audio-cache/tts-edge
```

Sync the audio folder with the database:

```bash
uv run decklet-tts-edge \
  --sync \
  --db ~/.emacs.d/decklet/decklet.sqlite \
  --out-dir ~/.emacs.d/decklet/audio-cache/tts-edge
```
