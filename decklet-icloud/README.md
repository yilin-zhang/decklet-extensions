# decklet-icloud

For a [Decklet](https://github.com/yilin-zhang/decklet) profile kept in
iCloud Drive and used from more than one Mac. Decklet refuses to open the deck
while it is out of sync, so two machines never write diverging copies.

## What it checks

Every time Decklet opens the database (review, edit, adding cards, import and
export), two checks run:

1. **iCloud state.** The database and review log must be fully downloaded and
   free of conflicts. If a download is missing, it is started, so trying again
   a little later usually works.
2. **Session lock.** While Decklet is open, it leaves a lock file naming this
   machine. A lock from another machine means the deck is open there, or was
   just closed and has not finished uploading.

If a check fails, the command stops and says why. Profiles outside iCloud
Drive, and systems other than macOS, are left alone.

iCloud can only see what the other Mac has already uploaded. If you open the
deck on one Mac seconds after starting on the other, the lock may not have
arrived yet. Close Decklet on one machine and give iCloud a moment.

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

Emacs needs access to iCloud Drive. macOS asks the first time, or grant it
under System Settings > Privacy & Security > Files and Folders.

### Trashing files in iCloud Drive

Some extensions move stale files to the trash, such as TTS audio for deleted or
renamed cards. In iCloud Drive this fails in Emacs with `Removing old name:
Attribute not found`. To fall back to Finder, add this to your init file:

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

macOS may ask once to let Emacs control Finder.

## Commands

| Command | Purpose |
|---|---|
| `decklet-icloud-status` | Show the sync state and who holds the lock |
| `decklet-icloud-override` | Skip the checks for the next connection and take over the lock |

Use `decklet-icloud-override` when a lock is stale, say because the other Mac
crashed or quit Emacs while offline, or when you know the local copy is the one
to keep.

## Options

| Option | Default | Purpose |
|---|---|---|
| `decklet-icloud-lock-file-name` | `".decklet-lock"` | Lock file name in the profile directory |
| `decklet-icloud-host-name` | `nil` | Machine name written in the lock; `nil` uses the macOS `LocalHostName`, then `system-name` |
| `decklet-icloud-osascript-program` | `"osascript"` | Program that runs the status script |

## Requirements

A Decklet core that provides `decklet-db-pre-connect-hook`.
