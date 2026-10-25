# decklet-icloud

Guard for a [Decklet](https://github.com/yilin-zhang/decklet) profile stored in
iCloud Drive and used from more than one Mac. It refuses to open the deck while
the profile is out of sync, so two machines never write diverging copies of the
database.

## How it works

Before Decklet opens its SQLite connection, `decklet-icloud-mode` runs two
checks from `decklet-db-pre-connect-hook`. That hook guards every entry point
that touches the database: review, edit, adding cards, import and export.

1. **iCloud state.** `decklet.sqlite` and `review-log.jsonl` must be fully
   downloaded, not downloading, and free of unresolved conflicts. A file that
   iCloud evicted to a `.NAME.icloud` placeholder counts as not downloaded,
   instead of letting Decklet create an empty database in its place. Missing
   downloads are started, so trying again a little later usually works.
2. **Session lock.** While connected, Decklet holds `.decklet-lock` in the
   profile directory, naming this machine. The lock is removed when Decklet
   disconnects (the last session buffer closes) or Emacs exits. A lock held by
   another machine means the deck is open there, or was closed there but has
   not finished uploading yet.

If either check fails, the command stops with a `user-error` that says why.
Profiles outside iCloud Drive, and non-macOS systems, are left alone.

The state comes from Foundation's `NSURLUbiquitousItem*` resource values,
queried through `osascript -l JavaScript`. Each check takes well under 100 ms.

## Limits

iCloud only reports whether this Mac matches the server. It cannot see changes
that another Mac has not uploaded yet, and the lock file itself travels through
iCloud too. The lock closes most of that gap, but not all of it: if you open
the deck on machine B within seconds of starting a session on machine A, B may
not have received A's lock yet. Close Decklet on one machine and give iCloud a
moment before opening it on the other.

## Setup

```emacs-lisp
(use-package decklet-icloud
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-icloud/"
  :after decklet
  :demand t
  :config
  (decklet-icloud-mode 1))
```

Emacs needs access to iCloud Drive (macOS asks the first time, or grant it under
System Settings > Privacy & Security > Files and Folders).

## Commands

| Command | Purpose |
|---|---|
| `decklet-icloud-status` | Report the sync state and the current lock holder |
| `decklet-icloud-override` | Skip the checks for the next connection and take over the lock |

Use `decklet-icloud-override` when a lock is stale, e.g. the other machine
crashed or quit Emacs while offline, or when you know the local copy is the one
to keep.

## Options

| Option | Default | Purpose |
|---|---|---|
| `decklet-icloud-lock-file-name` | `".decklet-lock"` | Lock file name in the profile directory |
| `decklet-icloud-host-name` | `nil` | Machine name in the lock; `nil` uses the macOS `LocalHostName`, falling back to `system-name` |
| `decklet-icloud-osascript-program` | `"osascript"` | Program that runs the status script |

## Requirements

Needs a Decklet core that provides `decklet-db-pre-connect-hook`.
