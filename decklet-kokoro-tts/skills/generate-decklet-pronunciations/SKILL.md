---
name: generate-decklet-pronunciations
description: Resolve, audit, and batch-generate accurate local English pronunciation audio for Decklet cards with Kokoro. Use when the user asks to generate missing Decklet audio, repair stale pronunciations, audit ambiguous word readings, or backfill the card-ID-keyed kokoro.json sidecar and Kokoro MP3 cache.
---

# Generate Decklet Pronunciations

Resolve only stale or missing Decklet Kokoro entries. Prefer offline evidence,
generate high-confidence audio automatically, and stop for user review when the
intended reading remains ambiguous.

## Resolve paths

This skill lives at:

```text
<plugin>/skills/generate-decklet-pronunciations/SKILL.md
```

Resolve `<plugin>` as two directories above this file. Run every CLI command
with `<plugin>` as the working directory.

Resolve the active Decklet directory through Emacs:

```bash
emacsclient --eval '(expand-file-name decklet-directory)'
```

Use these profile-relative paths unless the user's Elisp configuration
overrides them:

```text
DB:       <decklet>/decklet.sqlite
Manifest: <decklet>/kokoro.json
Audio:    <decklet>/audio-cache/tts-kokoro/
Model:    ~/Models/Kokoro-82M/
```

Read the active Elisp values with `emacsclient`; never use `emacs`:

```elisp
(progn
  (require 'decklet-kokoro-tts)
  (list decklet-kokoro-tts-model-directory
        decklet-kokoro-tts-accent
        decklet-kokoro-tts-voice
        decklet-kokoro-tts-device
        decklet-kokoro-tts-speed))
```

## 1. Reconcile and scan

Run sync first. It removes deleted card IDs, marks renamed words stale, and
moves invalidated audio to Trash:

```bash
uv run --offline decklet-kokoro-tts sync \
  --db <decklet>/decklet.sqlite \
  --manifest <decklet>/kokoro.json \
  --out-dir <decklet>/audio-cache/tts-kokoro
```

Write the work queue to a temporary JSONL file:

```bash
uv run --offline decklet-kokoro-tts scan \
  --db <decklet>/decklet.sqlite \
  --manifest <decklet>/kokoro.json \
  --out-dir <decklet>/audio-cache/tts-kokoro
```

Each row includes card ID, word, hint, back, prior record, and one reason:

- `missing-audio`: pronunciation is valid; do not re-resolve it.
- `missing-manifest`: resolve the pronunciation.
- `stale`: the word changed; resolve it from scratch.

Report counts before changing the manifest.

## 2. Resolve pronunciations

For each `missing-manifest` or `stale` card, use this evidence order:

1. IPA in the card back `#+SUBTITLE:` matching the intended sense.
2. IPA or pronunciation information in the hint.
3. Offline Kokoro/Misaki G2P for an unambiguous ordinary word.
4. Card meaning, part of speech, and example sentences to choose among
   heteronyms.
5. Online verification only for proper names, missing entries, conflicting
   evidence, or readings that remain uncertain. Prefer reputable dictionaries
   or Wiktionary and record the URL in `source`.

Never infer the intended reading from spelling alone when the card context
shows a heteronym such as `record`, `present`, `minute`, or `attribute`.

Preview automatic US or UK phonemes without loading the acoustic model:

```bash
uv run --offline decklet-kokoro-tts phonemize --accent en-us --text 'word'
```

To force a reading, use Kokoro's pronunciation annotation and phonemize it:

```bash
uv run --offline decklet-kokoro-tts phonemize \
  --accent en-us \
  --text '[record](/ɹɪkˈɔɹd/)'
```

For one resolution, use `set`:

```bash
uv run --offline decklet-kokoro-tts set \
  --db <decklet>/decklet.sqlite \
  --manifest <decklet>/kokoro.json \
  --out-dir <decklet>/audio-cache/tts-kokoro \
  --card-id CARD_ID \
  --auto \
  --accent en-us \
  --source misaki \
  --confidence high
```

For a selected reading, pass the exact Kokoro/Misaki phoneme output with
`--pronunciation`, a concise source, and `--confidence high`. Use `approved`
only for a user-confirmed pronunciation.

For multiple resolutions, do not invoke `set` once per card. Write a temporary
JSONL file with one object per card:

```json
{"card_id": 42, "pronunciation": "ɹɪkˈoʊɹd", "accent": "en-us", "source": "card-back", "confidence": "high"}
```

Then update the manifest once:

```bash
uv run --offline decklet-kokoro-tts set-batch \
  --db <decklet>/decklet.sqlite \
  --manifest <decklet>/kokoro.json \
  --out-dir <decklet>/audio-cache/tts-kokoro \
  --accent en-us \
  --input /tmp/decklet-kokoro-resolutions.jsonl
```

Do not write low-confidence guesses. Collect unresolved cards with:

- card ID and word;
- possible readings;
- the card context that creates the ambiguity;
- evidence checked;
- one short question for the user.

Pause before generation if unresolved cards remain.

## 3. Generate

After all resolvable records are valid, preview the batch:

```bash
uv run --offline decklet-kokoro-tts batch \
  --db <decklet>/decklet.sqlite \
  --manifest <decklet>/kokoro.json \
  --out-dir <decklet>/audio-cache/tts-kokoro \
  --model-dir <model> \
  --accent en-us \
  --voice af_heart \
  --device mps \
  --speed 1.0 \
  --ffmpeg ffmpeg \
  --dry-run
```

Then remove `--dry-run`. Use the actual Elisp-configured runtime values.
`batch` loads Kokoro once and creates only missing audio for valid manifest
records. Do not pass `--auto-missing` unless the user explicitly accepts
unreviewed default G2P, or `--overwrite` unless they explicitly ask to
regenerate existing Kokoro audio.

## 4. Verify and report

Run `scan` again. Report:

- records resolved;
- MP3 files generated;
- valid records still missing audio;
- unresolved cards awaiting review;
- any generation failures.

Never modify Decklet's SQLite schema. Never put voice, model path, speed, or
device settings in `kokoro.json`; those belong to Elisp configuration.
