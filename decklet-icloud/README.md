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

### Trashing files in iCloud Drive

Several extensions move stale files to the trash instead of deleting them (for
example, TTS audio for deleted or renamed cards). For files in iCloud Drive,
Emacs's built-in macOS trash (`system-move-file-to-trash`) fails with
`Removing old name: Attribute not found` and leaves the file where it was.
`/usr/bin/trash` fails the same way when Emacs runs it. Finder succeeds,
because it manages iCloud's trash. To make Emacs fall back to Finder, add this
to your init file:

```emacs-lisp
(when (eq system-type 'darwin)
  (defun my/trash-with-finder-fallback (orig file)
    "Call ORIG on FILE; on `file-error', retry by asking Finder."
    (condition-case err
        (funcall orig file)
      (file-error
       (unless (and (not (file-remote-p file))
                    (zerop (call-process
                            "osascript" nil nil nil
                            "-e" "on run argv"
                            "-e" "tell application \"Finder\" to delete ((POSIX file (item 1 of argv)) as alias)"
                            "-e" "end run"
                            (expand-file-name file))))
         (signal (car err) (cdr err))))))
  (advice-add 'move-file-to-trash :around #'my/trash-with-finder-fallback))
```

Advise `move-file-to-trash`, not `system-move-file-to-trash`: the natively
compiled `files.el` calls that primitive directly and skips any advice on it.
macOS may ask once to let Emacs control Finder.

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
