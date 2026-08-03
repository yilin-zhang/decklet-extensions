---
name: configure-local-kokoro
description: Install, configure, verify, update, or uninstall the local Kokoro-82M runtime used by Decklet's decklet-tts-kokoro extension. Use when setting up the model under ~/Models, repairing the plugin-local uv environment, changing voice/accent/device settings in Elisp, testing offline synthesis, or documenting clean removal. Do not use this skill to resolve card pronunciations or batch-generate the user's real card audio.
---

# Configure Local Kokoro

Manage Decklet's Kokoro runtime without changing card pronunciation records.
Keep dependencies isolated in the extension's `.venv`, model artifacts in
`~/Models/Kokoro-82M`, and runtime preferences in Elisp.

## Locate the installation

Use these defaults unless the user's Elisp configuration overrides them:

```text
Plugin: ~/.emacs.d/site-lisp/decklet-extensions/decklet-tts-kokoro
Model:  ~/Models/Kokoro-82M
Config: ~/.emacs.d/custom/custom-post.el
```

Inspect `decklet-tts-kokoro-model-directory`,
`decklet-tts-kokoro-voice`, `decklet-tts-kokoro-accent`,
`decklet-tts-kokoro-device`, and `decklet-tts-kokoro-speed` with
`emacsclient`. Always use `emacsclient`, never a separate batch Emacs.

## Install or repair

Before installing, inspect `pyproject.toml` and `uv.lock`. Use Python 3.12:

```sh
cd ~/.emacs.d/site-lisp/decklet-extensions/decklet-tts-kokoro
uv sync --python 3.12
```

Download only runtime model files through the authenticated Hugging Face CLI:

```sh
hf download hexgrad/Kokoro-82M \
  config.json kokoro-v1_0.pth 'voices/*.pt' \
  --local-dir ~/Models/Kokoro-82M
```

Do not install Python packages globally, modify shell startup files, use
`sudo`, or duplicate the model inside the plugin.

## Configure Emacs

Put runtime choices in Elisp, never in `decklet/kokoro.json`. A typical US
English configuration is:

```elisp
(setq decklet-tts-kokoro-model-directory "~/Models/Kokoro-82M/"
      decklet-tts-kokoro-accent "en-us"
      decklet-tts-kokoro-voice "af_heart"
      decklet-tts-kokoro-device "mps"
      decklet-tts-kokoro-speed 1.0)
```

Preserve user customizations. On Apple Silicon prefer `mps`; use `cpu` only
when MPS is unavailable or a model operation is incompatible.

## Verify offline

Check required artifacts:

```sh
test -f ~/Models/Kokoro-82M/config.json
test -f ~/Models/Kokoro-82M/kokoro-v1_0.pth
test -f ~/Models/Kokoro-82M/voices/af_heart.pt
```

Then verify that the environment can phonemize without network access:

```sh
cd ~/.emacs.d/site-lisp/decklet-extensions/decklet-tts-kokoro
uv run --offline decklet-tts-kokoro phonemize \
  --accent en-us --text record
```

For synthesis testing, create a temporary SQLite database and temporary
output directory. Do not write to the real Decklet manifest or audio cache
unless the user explicitly asks for card generation. Confirm the result with
`ffprobe` or `file`.

## Update safely

Review dependency and model changes before updating. Keep `uv.lock` in sync
with `pyproject.toml`. After an update, repeat the offline phonemization and
temporary synthesis checks. Do not overwrite the user's runtime choices.

## Uninstall cleanly

Explain scope before removal. The isolated runtime can be removed by deleting:

```text
~/.emacs.d/site-lisp/decklet-extensions/decklet-tts-kokoro/.venv
~/Models/Kokoro-82M
```

Removing the plugin itself or generated Decklet audio is separate and requires
explicit user authorization. Prefer recoverable deletion for model files when
practical.
