# decklet-import

Imports saved words from a Kindle (`vocab.db`) or Kobo (`KoboReader.sqlite`)
into [Decklet](https://github.com/yilin-zhang/decklet). The words open in a
batch-add buffer, so you can review them before they are stored.

## Setup

You need the `sqlite3` command-line tool on `PATH`.

```emacs-lisp
(use-package decklet-import
  :vc (:url "https://github.com/yilin-zhang/decklet-extensions"
       :lisp-dir "decklet-import"
       :rev :newest)
  :custom
  ;; `sqlite3' binary to use.
  ;; (decklet-import-sqlite-command "sqlite3")
  ;; Import Kindle usage examples as hint lines.
  ;; (decklet-import-kindle-usage t)
  :after decklet)
```

## Usage

| Key or command | Description |
|---|---|
| `M-x decklet-import-kindle` | Import from a Kindle `vocab.db` |
| `M-x decklet-import-kobo` | Import from a Kobo `KoboReader.sqlite` |

Each command asks for the database file and opens its words in a batch-add
buffer. After a successful import, it offers to clear the source file so the
same words are not imported twice.

Kindle usage examples become hint lines under each word, with the word wrapped
in asterisks. An all-lowercase word matches case-insensitively, and a word with
a capital letter must match exactly.

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
