---
summary: Async AI-powered flashcard back-generation for Decklet via OpenCode subprocess with batch/queue concurrency, per-task timeout, and file-based result passing
---

# Decklet Backfill

## Purpose

Generates English word/phrase explanations using OpenCode (AI tool) and writes them to Decklet flashcard "back" fields. Supports single-word and batch (marked words) generation with configurable concurrency.

## Entry Points

| Command | Description |
|---------|-------------|
| `decklet-backfill-current-word` | Generate card back for current word or all marked words in edit mode |
| `decklet-backfill-cancel` | Cancel the active batch |

Both commands work from `decklet-review-mode` or `decklet-edit-mode`.

## Data Structures

### Task (`cl-defstruct`)
```elisp
(cl-defstruct decklet-backfill-task
  word result-file process timer session-id
  status  ; 'pending | 'running | 'success | 'failed | 'cancelled | 'timed-out
  error)
```

### Batch (`cl-defstruct`)
```elisp
(cl-defstruct decklet-backfill-batch
  id tasks source-buffer)
```

Only one batch active at a time (`decklet-backfill--active-batch`).
UI refresh after a successful write is delegated to Decklet core:
`decklet-set-card-back` fires `decklet-card-field-updated-functions`,
and Decklet's review and edit modules subscribe to that hook to
re-render their visible buffers.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `decklet-backfill-opencode-command` | `"opencode"` | OpenCode executable |
| `decklet-backfill-output-format` | `'org` | Output format: `'text`, `'org`, `'markdown` |
| `decklet-backfill-opencode-model` | `nil` | Model override |
| `decklet-backfill-working-directory` | `user-emacs-directory` | Working dir for subprocess |
| `decklet-backfill-skill-file` | `SKILL.md` in package | Prompt template file |
| `decklet-backfill-runtime-directory` | `runtime/` in package | Generated output storage |
| `decklet-backfill-timeout-seconds` | `30` | Per-task timeout; `nil` disables |
| `decklet-backfill-max-concurrent-tasks` | `5` | Max parallel OpenCode processes |

## Key Flows

### Single Word Generation
1. `decklet-backfill-current-word` resolves current word from review/edit buffer
2. `decklet-backfill--prepare-words` checks for existing backs, asks about overwrite
3. `decklet-backfill--ensure-cards-exist` verifies word exists in DB
4. `decklet-backfill--start-batch` creates task, launches OpenCode subprocess

### Batch Generation (Marked Words)
1. `decklet-backfill--marked-edit-words` gets marked words from edit buffer
2. User confirms batch via `yes-or-no-p`
3. Up to `max-concurrent-tasks` started in parallel; rest queued as `'pending`
4. Each completing task triggers `decklet-backfill--maybe-start-next-task`

### OpenCode Subprocess Lifecycle
1. `decklet-backfill--start-task` spawns: `opencode run --format json [--model MODEL] -- PROMPT`
2. Prompt instructs OpenCode to write result to a specific file path
3. Process sentinel handles exit:
   - Exit 0: read result file, write via `decklet-set-card-back`, status `'success`
   - Non-zero: status `'failed` (or `'cancelled`/`'timed-out` if pre-set), show process buffer
4. Cleanup: cancel timer, delete OpenCode session async, start next queued task
5. When all tasks done: display summary, clear batch state (UI refresh happens per-card as each write fires the field-updated hook)

### Timeout Handling
- `run-at-time` schedules kill after `timeout-seconds`
- Timer sets status to `'timed-out` before `delete-process`
- Sentinel sees pre-set status, doesn't overwrite with `'failed`

## Prompt Structure

```
[SKILL.md content]
----
[word] ([format-hint: org|md|text])

Write the final explanation to this exact file path: [runtime/<batch-id>-<slug>.<ext>]
Overwrite the file if it already exists. Do not ask questions.
Do not print the explanation to stdout. Write it to the file instead.
```

## Dependencies

- `decklet` public API: `decklet-current-word`, `decklet-card-exists-p`, `decklet-get-card-back`, `decklet-set-card-back`
- `cl-lib`, `json`, `seq`, `subr-x`
- External: `opencode` CLI

## Integration with Decklet

- Detects context from `decklet-review-mode` or `decklet-edit-mode`
- Reads words via `decklet-current-word` or `tabulated-list-get-id` + `decklet-edit--marked-words`
- Writes card backs via `decklet-set-card-back`, which fires the
  `decklet-card-field-updated-functions` hook so Decklet core auto-refreshes
  any visible review or edit buffer.

## Edge Cases

- Empty result file after OpenCode exits 0 triggers `user-error` and shows process buffer
- Failed single-word task shows process buffer for debugging; batch failure shows summary
- Session cleanup is fire-and-forget async (`opencode session delete`)
- Result files cleaned before each task start to avoid stale content
