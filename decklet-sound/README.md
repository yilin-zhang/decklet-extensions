# decklet-sound

Plays a [Decklet](https://github.com/yilin-zhang/decklet) card's pronunciation
with `s`. It only plays audio. To generate it, use
[`decklet-tts-kokoro`](../decklet-tts-kokoro/),
[`decklet-tts-edge`](../decklet-tts-edge/), or your own scripts.

## Setup

Playback uses [mpv](https://mpv.io/), which must be on `PATH`:

```bash
brew install mpv
```

```emacs-lisp
(use-package decklet-sound
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-sound/"
  :commands (decklet-sound-play-file decklet-sound-stop-daemon)
  :hook ((decklet-review-mode . decklet-sound-mode)
         (decklet-edit-mode   . decklet-sound-mode)))
```

## Keys and commands

| Key or command | Description |
|---|---|
| `s` | Play the current word's audio |
| `decklet-sound-play-file` | Play any audio file, for your own sound effects |
| `M-x decklet-sound-stop-daemon` | Stop the background mpv process now, for example to free Bluetooth headphones |

One mpv process stays running between plays, so quick plays do not cut in and
out on Bluetooth headphones. It stops after 60 seconds without playback and
starts again on the next play.

To play your own sounds, for example a chime when the daily goal is reached,
call `decklet-sound-play-file` from a Decklet hook such as
`decklet-review-daily-goal-reached-hook`.

## Options

| Option | Default | Description |
|---|---|---|
| `decklet-sound-audio-directory` | `nil` (uses `decklet-directory/audio-cache/tts-edge/`) | Folder of Edge TTS audio files |
| `decklet-sound-mpv-idle-timeout` | `60` | Seconds without playback before mpv stops; `nil` keeps it running |
| `decklet-sound-player-function` | `decklet-sound-mpv-player` | Function that plays one file; replace it to use another player |

## For generator authors

A generator either writes `<card-id>.mp3` into `(decklet-sound-audio-dir)`
(use `decklet-sound-audio-path` for the file name), or adds a function to
`decklet-sound-audio-resolver-functions` that takes `(CARD-ID WORD)` and
returns a file path or nil. Resolvers are tried first, in order.
