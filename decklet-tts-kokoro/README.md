# decklet-tts-kokoro

Generates English pronunciation audio for
[Decklet](https://github.com/yilin-zhang/decklet) cards on your own machine,
with [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M).
[`decklet-sound`](../decklet-sound/) plays it, and prefers it over Edge TTS
audio when both exist.

Pronunciations are saved in `decklet-directory/kokoro.json`, and audio in
`decklet-directory/audio-cache/tts-kokoro/`.

## Setup

Download the model. The directory needs `config.json`, `kokoro-v1_0.pth`, and
your voice under `voices/`:

```bash
hf download hexgrad/Kokoro-82M \
  --include config.json kokoro-v1_0.pth 'voices/*.pt' \
  --local-dir ~/Models/Kokoro-82M
```

```emacs-lisp
(use-package decklet-tts-kokoro
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-tts-kokoro/"
  :after decklet-sound
  :demand t
  :custom
  (decklet-tts-kokoro-accent "en-us")
  (decklet-tts-kokoro-voice "af_heart")
  (decklet-tts-kokoro-model-directory "~/Models/Kokoro-82M/")
  (decklet-tts-kokoro-trim-threshold "-55dB")
  (decklet-tts-kokoro-trim-keep 0.03))
```

Then run `M-x decklet-tts-kokoro-install` once to set up the Python
environment.

## Usage

`M-x decklet-tts-kokoro-sync` cleans up after deleted and renamed cards, then
generates audio for every card whose audio is missing or out of date. With a
prefix argument, it only previews the work.

`M-x decklet-tts-kokoro-regenerate-word` regenerates one word. With a prefix
argument, you can give the exact phonemes to use.

Sync and install show their progress in `*Decklet Kokoro TTS*`, one line per
card (`[37/412] ok: abate`). Set `decklet-tts-kokoro-display-log` to nil to
keep that window from popping up. It still shows when a command fails.

New recordings have their leading silence trimmed, keeping a short pause
before the word (`decklet-tts-kokoro-trim-threshold` and
`decklet-tts-kokoro-trim-keep`).

The bundled agent skills can set up the runtime and fix stale or missing
pronunciations, and stop to ask you when a pronunciation is ambiguous.
