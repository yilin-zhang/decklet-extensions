---
name: decklet-card-back
description: Generate thorough Emacs Org-mode card backs for decklet vocabulary words (one .org file per word) plus a one-sentence hint per card, then optionally write them into the decklet SQLite DB. Use when the user asks to generate, add, or backfill card backs or hints. Handles an explicit word list, today's due/reviewed cards for a given state (new, learning, or review), or the whole backlog of cards with empty backs or empty hints.
---

# decklet-card-back

Generate rich Org-mode card backs for [decklet](https://github.com/yilin-zhang/decklet)
vocabulary by fanning out many parallel subagents. One `.org` file per word
under `<decklet-dir>/card-backs/`, plus a one-line `.hint` beside it, then write
the generated content back into the SQLite DB on the user's signal.

Cards carry two generated columns: `back` (the full Org card) and `hint` (a
single example sentence with the word wrapped in `*asterisks*`). **Both are
filled by default** — whenever a card's `hint` is empty, generate one. Neither
is ever overwritten when already non-empty.

## Paths

Decklet stores files under `decklet-directory`, whose default is
`~/.emacs.d/decklet/`. Resolve the user's actual value before proceeding:

```bash
emacsclient --eval '(expand-file-name decklet-directory)' 2>/dev/null \
  | sed 's/^"//;s/"$//'
```

If `emacsclient` is unavailable or the query fails, fall back to
`~/.emacs.d/decklet/`. In the rest of this document, substitute `<decklet-dir>`
with the resolved path.

Paths used by this skill:

- DB: `<decklet-dir>/decklet.sqlite`
- Output dir: `<decklet-dir>/card-backs/`
- Backup dir: `<decklet-dir>/backups/`
- Specs: the siblings `card-spec.md` and `hint-spec.md` next to this
  `SKILL.md`. Resolve them to absolute paths (from this file's own location, or
  via the skill harness' plugin-root variable when available) before dispatching
  subagents.
- Hint files: `<decklet-dir>/card-backs/<normalized>.hint`, written alongside
  each `.org`.
- Batch scratch dir: `/tmp/decklet-batches/<timestamp>/`

## Step 0 — Understand decklet's scheduling model

Read this before writing any query. Getting "which cards" wrong wastes a whole
generation run.

### The `state` column vs. the *effective* state

`cards.state` holds only `learning`, `relearning`, or `review`. There is no
`new` row value — **new** is an effective state derived at read time:

| Effective state | Condition |
|-----------------|-----------|
| `new` | `last_review IS NULL` (whatever `state` says) |
| `learning` | `state='learning' AND last_review IS NOT NULL` |
| `relearning` | `state='relearning' AND last_review IS NOT NULL` |
| `review` | `state='review'` (graduated; always has a `last_review`) |

See `decklet-card-effective-state` in `decklet-scheduler.el`. So
`state='learning'` alone mixes never-seen new cards with cards mid-way through
the intraday learning steps.

### The review day is not the calendar day

`decklet-day-rollover-hour` (default 4) defines the day boundary in **local**
time, while `due` / `last_review` are stored as UTC `YYYY-MM-DDTHH:MM:SSZ`.
Resolve the current window rather than assuming midnight or UTC:

```bash
emacsclient --eval '(list (format-time-string "%FT%TZ" (decklet-day-start-time) t)
                          (format-time-string "%FT%TZ" (decklet--next-day-start-time) t))'
```

Call the results `<day-start>` and `<next-day-start>`.

### "Due" means different things per state

From `decklet-db--counts` in `decklet-db.el`:

| Bucket | Due condition |
|--------|---------------|
| review | `state='review' AND due <= <next-day-start>` — **day granularity**: anything due later today already counts |
| learning / relearning | `due <= now` — **intraday steps**, minute granularity |
| new | `last_review IS NULL` |
| reviewed today | `last_review >= <day-start> AND last_review < <next-day-start>` |

Using `due <= now` for review cards is wrong and silently under-reports.

### Answering a card moves it out of the due set

Once a card is graded, its `due` jumps into the future. So "today's review
cards" is **not** just the still-due set — cards already answered today have
future `due` values and are only findable via `last_review`. When the user
says "today's cards", they mean the union:

```sql
-- today's review-state cards, missing backs
SELECT word FROM cards
WHERE archived_at IS NULL
  AND state = 'review'
  AND (due <= '<next-day-start>'
       OR (last_review >= '<day-start>' AND last_review < '<next-day-start>'))
  AND (back IS NULL OR back = '');
```

## Step 1 — Collect the word list

Pick the mode from what the user asked. If their wording maps to more than one
of these, ask rather than guess — a wrong bucket is a wasted run.

**A. Explicit list** (e.g. "add card backs for: cat, dog, pig", or a
newline-separated list): use exactly what the user gave. Do NOT query the DB.

**B. Today's cards** (e.g. "今天需要复习的", "today's review words", "the cards
I'm reviewing today"): use the Step 0 union query. Ask which bucket if
unclear — `review` and `learning` are different sets, and the user usually
means one specific bucket:

- review state → the union query above.
- learning/relearning → `state IN ('learning','relearning') AND last_review IS
  NOT NULL AND (due <= now OR last_review >= '<day-start>')`.
- new → `last_review IS NULL`.

**C. Whole backlog** (e.g. "backfill all card backs", "fill in the missing card
backs" with no time qualifier): every non-archived card with an empty back,
optionally narrowed by state:

```sql
SELECT word FROM cards
WHERE archived_at IS NULL AND (back IS NULL OR back = '');
```

Whatever mode you are in, also survey the `hint` column over the same set —
`hint IS NULL OR trim(hint) = ''`. A card can need a hint without needing a
back, which is the common case once backs are backfilled:

```sql
SELECT word,
       (back IS NULL OR back = '')             AS needs_back,
       (hint IS NULL OR trim(hint) = '')       AS needs_hint
FROM cards
WHERE archived_at IS NULL AND word IN (...);
```

Split the words into two groups — **needs a back** (generate back + hint
together, Step 4) and **has a back but no hint** (hint only, Step 5b).

Report both counts and the exact bucket you used back to the user before
dispatching, so a misread is caught before agents burn tokens.

## Step 2 — Ask about review

Ask once, up front (before any agent runs):

> Pause for review after generation, or go straight through to DB write-back?

Do NOT ask whether to generate hints — hints are filled by default wherever the
column is empty. Mention it in the same breath as the counts instead
("N backs, M hints"), so the user can wave it off if they don't want it.

- If the user wants to review → stop after Step 5 and wait for natural-language
  "write back" / "commit to DB" / equivalent.
- If the user declines → proceed through Step 6 automatically once all agents
  finish.

## Step 3 — Batch the words

- Write the word list to `/tmp/decklet-batches/<ts>/all-words.txt` (one per
  line).
- Split the **needs-a-back** group into batch files of **5 words each**, named
  `batch-r000`, `batch-r001`, … (a full card back is slow to write).
- Split the **hint-only** group into files of **9 words each**, named
  `hint-r000`, `hint-r001`, … (extracting a sentence is cheap).
- The last batch in each series may be short. Either group may be empty.

## Step 4 — Dispatch subagents (wave strategy)

For each batch file, spawn one **background** Agent (general-purpose). Dispatch
in **waves of ~30** — after each wave's notifications trickle in, fire the next.
Do NOT try to launch 100+ agents in one message.

Each subagent prompt is small — just file paths:

> Read the spec at `<absolute-path-to-card-spec.md>` and the batch at
> `/tmp/decklet-batches/<ts>/batch-rNNN`. Generate card-back `.org` files and
> their `.hint` files per the spec and write them to
> `<decklet-dir>/card-backs/`. Report per the spec's Deliverable section.

`card-spec.md` sends the agent to `hint-spec.md` for the hint rules, so one
agent produces both files per word — no second wave needed for these.

Wait for all agents (notifications arrive automatically — do not poll).

## Step 5 — Post-generation cleanup

- Scan generated files for `  +\(` (multi-space before sense tag) and collapse
  to a single space:

  ```python
  import re, glob, os
  card_dir = '<decklet-dir>/card-backs/'
  for p in glob.glob(os.path.join(card_dir, '*.org')):
      with open(p) as f: s = f.read()
      new = re.sub(r' {2,}\(', ' (', s)
      if new != s:
          with open(p, 'w') as f: f.write(new)
  ```

- If any agent reports a word it could not handle (content-filter false
  positives on innocuous words like "grotesquerie" or food/preservation terms):
  retry that single word with a fresh agent and a slight rewording of the
  dispatch message.

Tell the user how many files were written and any anomalies flagged. If in
review mode, stop here.

## Step 5b — Hints for cards that already had backs

For the "has a back but no hint" group from Step 1, no card back needs
generating — the hint is extracted from the `.org` that already exists. Batch
those words ~9 per agent and dispatch the same way:

> Read the spec at `<absolute-path-to-hint-spec.md>` and the batch at
> `/tmp/decklet-batches/<ts>/hint-rNNN`. For each word, read its card back at
> `<decklet-dir>/card-backs/<normalized>.org`, derive the hint per the spec, and
> write it to `<decklet-dir>/card-backs/<normalized>.hint` — hint text only, no
> headings or commentary. Report files written and any word you skipped, with
> the reason, in under 10 lines.

If a word's `.org` is missing, the agent skips it and says so; that word belongs
in the Step 4 group instead.

Before writing back, spot-check the generated `.hint` files: each should be
non-empty, contain `*asterisks*`, and carry no leading `N. ` numbering and no
leftover sense tag.

## Step 6 — Write back to DB (on user signal, or automatic if review was declined)

Triggered by natural language "write back" / "commit to DB" — or automatically
if the user declined review in Step 2.

**Always back up first.** Write both columns in the same pass — `back` from
`<normalized>.org`, `hint` from `<normalized>.hint` — each guarded so a
non-empty value is never clobbered. A card may get only one of the two (a hint
for a card whose back already existed); that is normal. Match files to DB rows
by normalized word = filename:

```python
import os, sqlite3, shutil
from datetime import datetime

decklet_dir = '<decklet-dir>'
db = os.path.join(decklet_dir, 'decklet.sqlite')
cb_dir = os.path.join(decklet_dir, 'card-backs/')
backup_dir = os.path.join(decklet_dir, 'backups/')
os.makedirs(backup_dir, exist_ok=True)
ts = datetime.now().strftime('%Y%m%dT%H%M%S')
backup = os.path.join(backup_dir, f'decklet.sqlite.bak-pre-backfill-{ts}')
shutil.copy2(db, backup)

import re

def norm(w):
    w = w.lower().replace('–', '-').replace('—', '-')
    w = re.sub(r'\s*/\s*', '-', w)   # 'a / b' -> 'a-b'; '/' is illegal in a filename
    return w.replace(' ', '-')

conn = sqlite3.connect(db, timeout=30)
# Target ONLY the words from Step 1 (either the DB queue or the explicit
# list).  Never overwrite a non-empty back or hint.
words = [...]  # fill in from Step 1
backs = hints = 0
for w in words:
    stem = os.path.join(cb_dir, norm(w))

    if os.path.exists(stem + '.org'):
        with open(stem + '.org') as f:
            content = f.read()
        cur = conn.execute(
            "UPDATE cards SET back = ? "
            "WHERE word = ? AND archived_at IS NULL AND (back IS NULL OR back = '')",
            (content, w),
        )
        backs += cur.rowcount

    if os.path.exists(stem + '.hint'):
        with open(stem + '.hint') as f:
            hint = f.read().strip()
        if hint:
            cur = conn.execute(
                "UPDATE cards SET hint = ? "
                "WHERE word = ? AND archived_at IS NULL "
                "AND (hint IS NULL OR trim(hint) = '')",
                (hint, w),
            )
            hints += cur.rowcount

conn.commit()
conn.close()
print(f'updated {backs} backs, {hints} hints; backup at {backup}')
```

After the write-back, tell the user:

- how many `back` rows and how many `hint` rows were updated,
- the backup path, and
- a reminder to refresh any open decklet buffer (press `g`) to see the change.

## Notes & gotchas

- See Step 0 for the state / due semantics. The two mistakes that actually
  happen: filtering review cards with `due <= now` instead of
  `due <= <next-day-start>`, and forgetting that cards already answered today
  have left the due set entirely.
- Filename normalization edge cases: en-dash `–` and em-dash `—` → `-`; spaces
  → `-`; accented letters preserved. See `card-spec.md` for the full rules. A
  word containing `/` (e.g. `first-day anxiety / last day jitters`) cannot go in
  a POSIX filename — collapse the slash and its spaces to a single `-` for the
  file, and keep the DB `word` untouched.
- Never skip the spec's HARD REQUIREMENTS. The AmE/BrE section is always
  present, example count >= meaning count, single space before sense tag.
- Hints are filled by default, not on request — see `hint-spec.md`. The two
  mistakes to avoid: stripping the `(AmE)` / `(BrE)` variety label along with
  the sense tag (keep the variety label), and writing two sentences when the
  word has only one common sense (one is the default).
- NEVER commit generated `.org` files or the SQLite DB via git unless the user
  explicitly asks.
