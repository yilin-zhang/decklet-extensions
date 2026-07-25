# decklet-kokoro-tts

Local, per-card English pronunciation audio for Decklet using
[Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M).

Pronunciation decisions are stored by Decklet card ID in
`decklet-directory/kokoro.json`. Generated MP3 files live under
`decklet-directory/audio-cache/tts-kokoro/`. `decklet-sound` tries these
card-specific files first and falls back to the existing word-keyed Edge TTS
cache.

## Setup

The model directory must contain `config.json`, `kokoro-v1_0.pth`, and the
selected voice under `voices/`:

```bash
hf download hexgrad/Kokoro-82M \
  --include config.json kokoro-v1_0.pth 'voices/*.pt' \
  --local-dir ~/Models/Kokoro-82M
```

Create the isolated Python environment:

```text
M-x decklet-kokoro-tts-install
```

## Configuration

```emacs-lisp
(use-package decklet-kokoro-tts
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-kokoro-tts/"
  :after decklet-sound
  :demand t
  :custom
  (decklet-kokoro-tts-accent "en-us")
  (decklet-kokoro-tts-voice "af_heart")
  (decklet-kokoro-tts-model-directory "~/Models/Kokoro-82M/")
  (decklet-kokoro-tts-trim-threshold "-55dB")
  (decklet-kokoro-tts-trim-keep 0.03))
```

`M-x decklet-kokoro-tts-generate-word` generates the current card using its
saved pronunciation or automatic G2P. With a prefix argument, it accepts an
optional Kokoro/Misaki phoneme override.

`M-x decklet-kokoro-tts-trim-audio` removes excess leading silence from
existing Kokoro files. Newly generated files are trimmed automatically.

The bundled Agent Skills can configure the local runtime or resolve stale and
missing pronunciations offline, pausing for review when a pronunciation
remains ambiguous.
