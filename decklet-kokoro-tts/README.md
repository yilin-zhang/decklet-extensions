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

`M-x decklet-kokoro-tts-sync` reconciles deleted and renamed cards, then
generates every missing or stale item using automatic G2P. With a prefix
argument, it previews the work without changing files.

`M-x decklet-kokoro-tts-regenerate-word` is the targeted override command.
With a prefix argument, it accepts an optional Kokoro/Misaki phoneme override.

Newly generated files automatically remove excess leading silence using the
configured threshold while retaining a short buffer before speech.

The bundled Agent Skills can configure the local runtime or resolve stale and
missing pronunciations offline, pausing for review when a pronunciation
remains ambiguous.
