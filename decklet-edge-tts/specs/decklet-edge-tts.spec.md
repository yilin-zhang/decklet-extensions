---
summary: Edge TTS audio generation and sync for Decklet flashcards with async subprocess management and multi-level audio fallback
---

# Decklet Edge TTS

## Purpose

Provides TTS audio generation and synchronization for the Decklet flashcard system using Microsoft Edge TTS. Supports bulk sync (generate missing / remove stale audio), per-word regeneration with optional pronunciation text override, and playback integration.

## Entry Points

### Interactive Commands

| Command | Description |
|---------|-------------|
| `decklet-edge-tts-sync` | Sync local audio cache with DB (C-u for dry-run) |
| `decklet-edge-tts-regenerate-word` | Regenerate audio for a word with optional spoken text override |
| `decklet-edge-tts-speak` | Play cached audio for the word in current context; bound to `s` in review and edit modes on load |

### Non-Interactive API

| Function | Description |
|---------|-------------|
| `decklet-edge-tts-play-next-word-or-fallback` | Play current word audio or fallback sound |
| `decklet-edge-tts-audio-file` | Return cache path for word (no existence check) |
| `decklet-edge-tts-audio-function` | Return cache path if file exists, else nil |
| `decklet-edge-tts-default-player` | Play audio via `afplay` (macOS) or `mpv` |

### Lifecycle hook handlers

Registered on load, these keep the audio cache in sync with the deck:

| Function | Hook | Behavior |
|---|---|---|
| `decklet-edge-tts--on-card-deleted` | `decklet-card-deleted-functions` | Delete cached audio for the removed word |
| `decklet-edge-tts--on-card-renamed` | `decklet-card-renamed-functions` | Rename cached audio when a word is renamed |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `decklet-edge-tts-project-directory` | package dir | Installation root |
| `decklet-edge-tts-db-file` | `nil` (-> `decklet-directory/decklet.sqlite`) | SQLite DB path |
| `decklet-edge-tts-audio-directory` | `nil` (-> `decklet-directory/audio-cache/tts-edge`) | Audio cache location |
| `decklet-edge-tts-command` | `"uv"` | Python invocation command |
| `decklet-edge-tts-cli-name` | `"decklet-edge-tts"` | CLI entrypoint name |
| `decklet-edge-tts-lead-in` | `", "` | Prefix for TTS pronunciation |
| `decklet-edge-tts-fallback-sound-file` | `nil` | Optional fallback audio path |
| `decklet-edge-tts-player-function` | `#'decklet-edge-tts-default-player` | Audio playback function |

## Key Flows

### Sync
1. `decklet-edge-tts-sync` checks no sync already running
2. Spawns: `uv run decklet-edge-tts --sync --db <path> --out-dir <path> --lead-in ", "` [+ `--dry-run`]
3. Async subprocess generates missing audio, removes stale files
4. Sentinel parses `SYNC_RESULT` line for metrics: `trashed`, `generated`, `planned_generate`, `failed`
5. Displays summary message

### Regenerate Word
1. `decklet-edge-tts-regenerate-word` prompts for word and optional spoken text
2. If text is empty: direct generation using the literal word
3. If text provided: generation using the text as spoken override via `--text`

### Audio Playback
1. `decklet-edge-tts-play-next-word-or-fallback` checks `decklet-current-word`
2. Looks up `<audio-dir>/<url-encoded-word>.mp3`
3. Falls back to `decklet-edge-tts-fallback-sound-file` if cache miss
4. Calls `decklet-edge-tts-player-function` (auto-detects `afplay` or `mpv`)

### Lifecycle-driven cache sync
1. On card delete: `decklet-edge-tts--on-card-deleted` removes the cached file.
2. On card rename: `decklet-edge-tts--on-card-renamed` renames the cached file.
3. The explicit `decklet-edge-tts-sync` command remains the fallback for
   out-of-band DB edits (manual changes, backup restore).

## Process Architecture

Two dedicated output buffers for independent monitoring:
- `*Decklet Edge TTS Sync*` — sync subprocess output
- `*Decklet Edge TTS Generate*` — audio generation output

All use timestamped logging with `decklet-edge-tts--append-log`.

## Dependencies

- `decklet` public API: `decklet-directory`, `decklet-prompt-word`, `decklet-current-word`, `decklet-card-deleted-functions`, `decklet-card-renamed-functions`
- `subr-x`, `url-util`
- External: `uv` (Python), `afplay`/`mpv`
- Python CLI: `tools/decklet_tts.py` (invoked via `uv run`)

## Edge Cases

- Concurrent sync prevented by checking process liveness
- Failed process buffers displayed for debugging; successful ones killed
- Configuration cascades: explicit override > derived from `decklet-directory` > hardcoded
