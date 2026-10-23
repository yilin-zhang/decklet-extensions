# decklet-sound

Audio playback layer for [Decklet](https://github.com/yilin-zhang/decklet)
flashcards. It first tries ordered card-specific audio resolvers, then falls
back to the card-keyed Edge TTS cache. Files are played through a long-lived
`mpv --idle` daemon so successive plays reuse a single audio session.

This package **only plays** audio. Generating and managing cache files is the
responsibility of companion generator packages such as
[`decklet-tts-kokoro`](../decklet-tts-kokoro/) and
[`decklet-tts-edge`](../decklet-tts-edge/), or user scripts that provide a
resolver or write files into `decklet-sound-audio-directory` (default:
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
`decklet-sound-play-file` (or `decklet-sound-audio-file` to look up a card's
audio) from there.

## Audio lookup order

`decklet-sound-audio-file` resolves audio in this order:

1. Call each function in `decklet-sound-audio-resolver-functions` with
   `(CARD-ID WORD)`.
2. Use the first returned path that exists.
3. Fall back to the Edge TTS cache in `decklet-sound-audio-dir`.

Resolver errors are reported as warnings and do not prevent later resolvers or
the fallback cache from running. This lets generators with their own cache,
such as Kokoro, take precedence over the Edge TTS cache.

## Public API for generators and resolvers

Generator packages should use these to locate cache files without reaching
into double-dash internals:

| Function | Purpose |
|---|---|
| `(decklet-sound-audio-dir)` | Absolute path to the cache directory |
| `(decklet-sound-audio-path CARD-ID)` | Canonical file path for CARD-ID regardless of existence — use this when writing a new file or computing a path to delete |
| `(decklet-sound-audio-file CARD-ID)` | First existing resolver or fallback file, or nil when absent — use this for read/playback code |
| `decklet-sound-audio-resolver-functions` | Ordered hook of functions accepting `(CARD-ID WORD)` and returning a candidate path or nil |

The fallback cache names files `<CARD-ID>.mp3` under `decklet-sound-audio-dir`,
via Decklet's `decklet-card-sidecar-file`. Generators that write that cache must
match this layout (or override `decklet-sound-audio-directory`). Generators with
their own layout register a resolver instead.

## macOS 27 short-audio workaround

On macOS, playback requests stereo output (`--audio-channels=stereo`).
macOS 27 can reject the mono CoreAudio channel layout with error `-50`,
causing mpv to fall back to AVFoundation, where audio tails can be lost.
Converting mono speech to stereo at playback time avoids that failure on
our tested setup; cached audio files are not modified. Other platforms
keep their normal channel selection.

Upstream reports: [CoreAudio initialization](https://github.com/mpv-player/mpv/issues/18384)
and [AVFoundation truncation](https://github.com/mpv-player/mpv/issues/18461).
