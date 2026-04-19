## Scope

- `decklet-sound` is the audio **playback** layer.  It looks up cached per-word
  audio files and plays them.
- File generation, sync, and cleanup live in generator packages
  (`decklet-edge-tts`, future backends) or user scripts.  Don't grow those
  responsibilities here.
- Public surface: `decklet-sound-audio-dir`, `decklet-sound-audio-path`,
  `decklet-sound-audio-file` so generators can write and cleanup hooks can
  locate files without relying on double-dash internals.
