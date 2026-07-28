# decklet-sound

Audio playback layer for [Decklet](https://github.com/yilin-zhang/decklet)
flashcards. Looks up cached per-word audio files and plays them via a
long-lived `mpv --idle` daemon so successive plays reuse a single audio
session.

This package **only plays** audio. Generating and managing cache files is the
responsibility of a companion generator package (for example
[`decklet-edge-tts`](../decklet-edge-tts/)) or user scripts that write files
into `decklet-sound-audio-directory` (default:
`decklet-directory/audio-cache/tts-edge/`).

## Why a long-lived mpv daemon?

Spawning a short-lived player (e.g. `afplay`) per playback repeatedly opens
and closes a CoreAudio AudioUnit. On macOS with Bluetooth output, each
open/close can trigger A2DP codec renegotiation — if another app is already
driving the same audio route (Music/Spotify), the contention shows up as
stalls, brief silences, or dropped packets on the Bluetooth link.

Keeping one `mpv` process around and sending it `loadfile` commands lets rapid
successive plays reuse one audio session. The daemon uses `--keep-open=yes`,
`--keep-open-pause=no`, `--audio-stream-silence=yes`, and
`--gapless-audio=yes`; without the keep-open and silence options, mpv closes its
CoreAudio output when each short file reaches EOF even though the idle process
itself remains alive. `--keep-open-pause=no` is equally important: otherwise
mpv pauses at the first EOF and subsequent files loaded over IPC remain paused.
Reopening the output for every card can repeatedly renegotiate a Bluetooth A2DP
route and contend with background audio.

By default, the daemon stops 60 seconds after the last playback and starts
again on demand. This avoids stale-AudioUnit failures: a long-idle daemon can
outlive its audio device handle (for example, after Bluetooth headphones
disconnect) and silently play to nowhere. Customize
`decklet-sound-mpv-idle-timeout` to change the delay, or set it to `nil` to
keep the daemon for the whole Decklet session. The daemon is also torn down
via `decklet-db-pre-disconnect-hook` before Decklet closes its shared SQLite
connection.

mpv must be on `PATH`:

```bash
brew install mpv
```

## Emacs configuration

```emacs-lisp
(use-package decklet-sound
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-sound/"
  :commands (decklet-sound-play-file decklet-sound-stop-daemon)
  :hook ((decklet-review-mode . decklet-sound-mode)
         (decklet-edit-mode   . decklet-sound-mode)))
```

To use a different playback backend (e.g. on a non-macOS setup), override
`decklet-sound-player-function` with a function that takes one absolute
audio file path.

## Key bindings and commands

`decklet-sound-mode` is a buffer-local minor mode that installs one key:

| Key | Command | Description |
|---|---|---|
| `s` | `decklet-sound-pronounce` | Play cached audio for the current word |

Additional commands:

| Command | Description |
|---|---|
| `decklet-sound-play-file` | Play an arbitrary audio file path via the daemon — handy for custom sound effects / orchestration hooks |
| `M-x decklet-sound-stop-daemon` | Manually shut down the mpv audio daemon mid-session (e.g. to free Bluetooth without leaving review/edit). The daemon also auto-shuts after the configured idle timeout and on `decklet-db-pre-disconnect-hook`, then restarts on next play. |

## Orchestration

This package deliberately stays at the "play this file" level.  Higher-level
orchestration — "play the current word, or fall back to a chime if no audio
exists", "play a goal-reached sound", etc. — is the user's concern.  Wire
your own functions onto `decklet-review-next-card-hook`,
`decklet-review-daily-goal-reached-hook`, or whatever else, and call
`decklet-sound-play-file` (or `decklet-sound-audio-file` to look up a word's
audio) from there.

## Public API for generators

Generator packages should use these to locate cache files without reaching
into double-dash internals:

| Function | Purpose |
|---|---|
| `(decklet-sound-audio-dir)` | Absolute path to the cache directory |
| `(decklet-sound-audio-path WORD)` | Canonical file path for WORD regardless of existence — use this when writing a new file or computing a path to delete |
| `(decklet-sound-audio-file WORD)` | Existing file path for WORD, or nil when absent — use this for read/playback code |

The naming convention is `<url-hexify-string WORD>.mp3` under
`decklet-sound-audio-dir`. Generators that write the cache must match this
layout (or override `decklet-sound-audio-directory` to point somewhere
mutually agreed upon).
