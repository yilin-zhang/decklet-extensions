# decklet-backfill

Fills in Decklet card backs using [opencode](https://opencode.ai). Run it from a
review or edit buffer and it sends the current word to an AI agent, which writes
a structured explanation into the card's `back` field.

The agent's behavior is defined by `SKILL.md` in this directory. The default
skill explains English words and phrases — meanings, AmE/BrE differences,
example sentences, and usage notes — in whatever output format you configure
(plain text, Org, or Markdown).

`decklet-backfill` is built entirely on Decklet's public extension API: it
reads and writes card content through `decklet-get-card-back` /
`decklet-set-card-back` and never touches Decklet internals. The
`*Decklet Review*` and `*Decklet Edit*` buffers refresh themselves as each
generated card back lands, because `decklet-set-card-back` fires the
`decklet-card-field-updated-functions` hook and Decklet core subscribes
to it.

## Usage

### Single word

Run `M-x decklet-backfill-current-word` from any Decklet review or edit
buffer. It targets the current word and starts a generation in the background.
A minibuffer message confirms when it finishes, and the visible review or edit
buffer re-renders the card as soon as the new back is written.

If the word already has a card back, you'll be asked whether to overwrite it.

### Batch generation

In `decklet-edit-mode`, mark multiple words with `m` and then run
`decklet-backfill-current-word`. The command asks whether to generate card backs
for all marked words. If you confirm, it starts one `opencode` process per word
in parallel. Each word has its own output file and timeout; one word failing
doesn't affect the others. A summary appears when the whole batch settles.

If some marked words already have card backs, you'll be asked once whether to
overwrite them. Declining skips only the words that have backs — the rest still
run.

### Cancellation

`M-x decklet-backfill-cancel` stops all running tasks in the active batch and
marks them cancelled. Only one batch can be active at a time; starting a new one
while another is running is an error.

## Install

```emacs-lisp
(use-package decklet-backfill
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-backfill/"
  :after decklet
  :commands (decklet-backfill-current-word
             decklet-backfill-cancel)
  :custom
  (decklet-backfill-output-format 'org)
  (decklet-backfill-working-directory user-emacs-directory)
  (decklet-backfill-timeout-seconds 30))
```

## Configuration

| Variable                             | Default                    | Description                                    |
|--------------------------------------|----------------------------|------------------------------------------------|
| `decklet-backfill-output-format`     | `org`                      | Output format: `text`, `org`, or `markdown`    |
| `decklet-backfill-opencode-command`  | `"opencode"`               | Executable name or full path                   |
| `decklet-backfill-opencode-model`    | `nil`                      | Model override; `nil` uses opencode's default  |
| `decklet-backfill-working-directory` | `user-emacs-directory`     | Working directory when invoking opencode       |
| `decklet-backfill-skill-file`        | `SKILL.md` in this package | Prompt source file                             |
| `decklet-backfill-runtime-directory` | `runtime/` in this package | Where per-word output files are written        |
| `decklet-backfill-timeout-seconds`   | `30`                       | Per-task timeout in seconds; `nil` disables it |

## How the prompt is built

The package is self-contained and does not depend on any skills outside this
directory.

For each word, the prompt is assembled as:

1. The contents of `SKILL.md`
2. A separator: `----`
3. The target word with a format hint, e.g. `pitch (org)`
4. An instruction telling the agent the exact file path to write the result to

The Elisp side doesn't parse any conversational output from opencode. It simply
waits for the process to exit, then reads the result file from `runtime/`. If
the file is missing or empty, the task is treated as a failure and the process
buffer is shown for inspection.

Result files are named `<batch-id>-<word>.<ext>`
(e.g. `20260327T120000123456789-pitch.org`) and are never shared across words or
runs.
