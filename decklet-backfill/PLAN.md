# decklet-backfill Batch Backfill Plan

## Goal

Extend `decklet-backfill` so that when the user is in `decklet-edit-mode` and has marked multiple words, one command can generate card backs for all marked words in parallel.

## Design Summary

Use one active batch at a time.

- A batch is a collection of one or more per-word tasks.
- Each task starts its own `opencode run` process.
- Each task gets its own result file under `runtime/`.
- Each task keeps its own timeout timer.
- The batch is considered active until all tasks finish, fail, or are cancelled.

This keeps the runtime model close to the current single-word implementation while making batch behavior explicit and manageable.

## Why This Design

### Chosen approach: multiple `opencode` processes

Pros:

- Matches the current one-word workflow closely.
- Each word has isolated process state, timeout, result file, and writeback target.
- One word failing does not corrupt another word.
- Easier to cancel, report progress, and debug.

Cons:

- Requires replacing the current single-process global state.

### Rejected for now: one `opencode` process with internal subagents

Reasons:

- Too much correctness is delegated to prompt-following.
- Harder to guarantee one file per word and reliable partial failure handling.
- Harder to cancel and to attribute failures per word.

## Runtime Spec

### Entry behavior

Command: `decklet-backfill-current-word`

Behavior:

1. If current buffer is not a Decklet review/edit buffer: signal a user error.
2. If current buffer is `decklet-edit-mode` and there are more than one marked words:
   - ask: `Generate card backs for N marked words?`
   - if user says yes, start a batch for marked words
   - if user says no, fall back to the current line word
3. Otherwise, run the existing one-word flow as a batch of size 1.

### Existing back handling

Single word:

- keep current behavior: ask whether to override when a back already exists.

Batch:

- inspect all target words before starting processes.
- if none have an existing back: continue directly.
- if some have existing backs: ask once whether to override those words.
- if the user declines override:
  - skip only the words that already have a back
  - continue with words that do not have a back
- if skipping leaves zero words to process: abort with a user-facing message.

### Active batch model

Only one active batch is allowed at a time.

- Starting a new single or batch run while another batch is active signals a user error.
- An active batch tracks all in-flight tasks.
- The old single-process globals are replaced with batch-aware state.

### Task model

Each task stores at least:

- `:word`
- `:result-file`
- `:process`
- `:timer`
- `:status` (`pending`, `running`, `success`, `failed`, `cancelled`, `timed-out`)
- `:error` (optional message)

### Result files

Every task must use a unique result file.

Format:

- under `decklet-backfill-runtime-directory`
- include batch id and sanitized word
- include the configured output extension

Example shape:

- `runtime/20260327T120000-pitch.org`
- `runtime/20260327T120000-catechism.org`

Rules:

- delete any pre-existing file for that exact task path before starting the process
- never share one result path across words

### Prompt contract

For each word, build the prompt from:

1. package-local `SKILL.md`
2. separator line `----`
3. word request such as `pitch (org)`
4. explicit instruction with the exact result file path

The agent is responsible for writing the final answer to that file.
The Elisp side does not parse conversational stdout.

### Timeout

- timeout remains per task, not per batch
- default timeout: `30` seconds
- when a task times out:
  - kill that task's process
  - mark the task `timed-out`
  - keep the rest of the batch running

### Cancellation

Command: `decklet-backfill-cancel`

Behavior:

- if no active batch exists: signal a user error
- otherwise cancel all running tasks in the active batch
- mark unfinished tasks as `cancelled`
- clear timers

### Correct writeback target

Every task writes back to the word captured when the task was created.

- UI movement or current-word changes after start must not affect the destination word.

### Refresh behavior

Refresh Decklet buffers once after the whole batch settles, not after each word.

Reasons:

- less flicker
- lower UI churn
- simpler to reason about

If at least one word succeeded, refresh open review/edit buffers once at batch completion.

### User feedback

Provide clear minibuffer messages:

- batch start: number of words
- per-word failure messages when helpful
- batch completion summary: success / failed / cancelled / timed out counts

## API / Internal Refactor Plan

### Replace single-run globals

Current:

- `decklet-backfill--active-process`
- `decklet-backfill--active-timer`

Replace with:

- `decklet-backfill--active-batch`

Batch plist should contain:

- `:id`
- `:tasks`
- `:started-at`
- `:source-buffer`
- `:completed-count`
- `:success-count`
- `:failure-count`
- `:cancelled-count`
- `:timed-out-count`

### New helpers

Planned helpers:

- `decklet-backfill--target-words`
- `decklet-backfill--marked-edit-words`
- `decklet-backfill--prepare-words-for-backfill`
- `decklet-backfill--batch-id`
- `decklet-backfill--task-result-file`
- `decklet-backfill--make-task`
- `decklet-backfill--start-batch`
- `decklet-backfill--start-task`
- `decklet-backfill--finish-task`
- `decklet-backfill--maybe-finish-batch`
- `decklet-backfill--cancel-batch`
- `decklet-backfill--refresh-buffers-once`

## README Updates Needed

Update README to document:

- marked-word batch generation in edit mode
- one active batch at a time
- `decklet-backfill-cancel` cancels the whole batch
- per-word unique runtime output files

## Test Plan

Add or update tests for:

1. marked words detection in edit mode
2. prompt logic when multiple marked words exist and user confirms batch mode
3. fallback to current line word when user declines batch mode
4. existing-back filtering for batch mode
5. one unique result file path per word
6. starting a batch creates one task per word
7. active batch blocks new requests
8. cancelling a batch cancels all unfinished tasks
9. timeout only affects the timed-out task, not the whole batch
10. writeback still targets the original word even if UI state changes
11. buffers refresh once after batch completion when at least one task succeeds
12. batch summary counts are correct

## Review Checklist

Before implementation is considered done:

- no nested result-file collisions
- no reliance on current UI word during sentinel/writeback
- no stale active batch left behind after success, failure, timeout, or cancel
- no extra refresh per word in batch mode
- single-word flow still works
- README matches actual behavior
