# decklet-tts-kokoro

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
M-x decklet-tts-kokoro-install
```

## Configuration

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

`M-x decklet-tts-kokoro-sync` reconciles deleted and renamed cards, then
generates every missing or stale item using automatic G2P. With a prefix
argument, it previews the work without changing files.

Sync and install pop up `*Decklet Kokoro TTS*`, which reports how many cards
it will generate, then that it is loading the model, then one line per card
(`[37/412] ok: abate`), so a long run is visible as it happens. Set
`decklet-tts-kokoro-display-log` to nil to keep the window from appearing; the
buffer is still written either way, and a failing command always shows it.

`M-x decklet-tts-kokoro-regenerate-word` is the targeted override command.
With a prefix argument, it accepts an optional Kokoro/Misaki phoneme override.

Newly generated files automatically remove excess leading silence using the
configured threshold while retaining a short buffer before speech.

The bundled Agent Skills can configure the local runtime or resolve stale and
missing pronunciations offline, pausing for review when a pronunciation
remains ambiguous.
