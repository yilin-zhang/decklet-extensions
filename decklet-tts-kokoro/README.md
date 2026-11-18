# decklet-tts-kokoro

Generates English pronunciation audio for
[Decklet](https://github.com/yilin-zhang/decklet) cards on your own machine,
with [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M).
[`decklet-sound`](../decklet-sound/) plays it.

## Setup

You need [`uv`](https://docs.astral.sh/uv/) and `ffmpeg` on `PATH`, and
`decklet-sound` for playback. Download the model. The directory needs
`config.json`, `kokoro-v1_0.pth` and your voice under `voices/`:

```bash
hf download hexgrad/Kokoro-82M \
  --include config.json kokoro-v1_0.pth 'voices/*.pt' \
  --local-dir ~/Models/Kokoro-82M
```

```emacs-lisp
(use-package decklet-tts-kokoro
  :vc (:url "https://github.com/yilin-zhang/decklet-extensions"
       :lisp-dir "decklet-tts-kokoro"
       :rev :newest)
  :custom
  ;; Directory with the downloaded model.
  ;; (decklet-tts-kokoro-model-directory "~/Models/Kokoro-82M/")
  ;; "en-us" or "en-gb".
  ;; (decklet-tts-kokoro-accent "en-us")
  ;; Voice name, or the absolute path of a voice .pt file.
  ;; (decklet-tts-kokoro-voice "af_heart")
  ;; Torch device, "mps" or "cpu".
  ;; (decklet-tts-kokoro-device "mps")
  ;; Speech speed multiplier.
  ;; (decklet-tts-kokoro-speed 1.0)
  ;; Silence threshold for trimming the start of a recording, and the
  ;; seconds of silence kept before the word.
  ;; (decklet-tts-kokoro-trim-threshold "-55dB")
  ;; (decklet-tts-kokoro-trim-keep 0.03)
  ;; Pop up the log during long commands. It still shows when a
  ;; command fails.
  ;; (decklet-tts-kokoro-display-log t)
  ;; Pronunciation file and audio folder; relative names are inside
  ;; `decklet-directory'.
  ;; (decklet-tts-kokoro-manifest-file "kokoro.json")
  ;; (decklet-tts-kokoro-audio-directory "audio-cache/tts-kokoro")
  :after decklet-sound
  :demand t)
```

Then run `M-x decklet-tts-kokoro-install` once to set up the Python
environment.

## Usage

| Key or command | Description |
|---|---|
| `M-x decklet-tts-kokoro-install` | Set up or update the Python environment |
| `M-x decklet-tts-kokoro-sync` | Clean up after deleted and renamed cards, then generate audio that is missing or out of date |
| `C-u M-x decklet-tts-kokoro-sync` | Preview what sync would do |
| `M-x decklet-tts-kokoro-regenerate-word` | Regenerate the current word's audio |
| `C-u M-x decklet-tts-kokoro-regenerate-word` | Regenerate it with phonemes you give |

Long commands show their progress in `*Decklet Kokoro TTS*`, one line per card
(`[37/412] ok: abate`).

The bundled agent skills can set up the runtime and fix stale or missing
pronunciations. They stop to ask you when a pronunciation is ambiguous.

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
