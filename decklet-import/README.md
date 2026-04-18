# decklet-import

E-reader vocab import for [Decklet](https://github.com/yilin-zhang/decklet).
Extracts saved words from Kindle (`vocab.db`) or Kobo (`KoboReader.sqlite`)
and opens them in a Decklet batch-add buffer for review and confirmation
before storing.

## Requirements

- `sqlite3` command-line tool on `PATH`.

## Setup

```emacs-lisp
(use-package decklet-import
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-import/"
  :after decklet)
```

## Commands

| Command | Source | Description |
|---|---|---|
| `M-x decklet-import-kindle` | `vocab.db` | Import from a Kindle vocab database |
| `M-x decklet-import-kobo` | `KoboReader.sqlite` | Import from a Kobo reader database |

Both commands:

1. Prompt for the e-reader DB file
2. Extract the saved words
3. Open a Decklet batch-add buffer populated with the words
4. After successful batch import, prompt to clear the source file so the
   same words aren't imported twice

### Kindle specifics

For Kindle, usage examples captured on the device are preserved:

- When `decklet-import-kindle-usage` is non-nil (default), usage examples
  become hint lines (`#` prefix) under each word
- The target word in usage sentences is wrapped in asterisks for
  highlighting
- Case-folding on the highlighting match depends on the word's casing:
  lowercase-only words match case-insensitively; mixed-case words must
  match exactly

## Customization

| Variable | Default | Description |
|---|---|---|
| `decklet-import-sqlite-command` | `"sqlite3"` | `sqlite3` binary to use |
| `decklet-import-kindle-usage` | `t` | Import Kindle usage examples as hint lines |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
