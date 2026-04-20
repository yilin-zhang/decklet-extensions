---
name: decklet-card-back
description: Generate thorough Emacs Org-mode card backs for decklet vocabulary words (one .org file per word), then optionally write them into the decklet SQLite DB. Use when the user asks to generate, add, or backfill card backs. Handles either the full DB queue (cards in `learning` state with empty back) or an explicit word list from the user.
---

# decklet-card-back

Generate rich Org-mode card backs for [decklet](https://github.com/yilin-zhang/decklet)
vocabulary by fanning out many parallel subagents. One `.org` file per word
under `<decklet-dir>/card-backs/`, then write the generated content back into
the SQLite DB on the user's signal.

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
- Spec: the sibling `card-spec.md` next to this `SKILL.md`. Resolve it to an
  absolute path (from this file's own location, or via the skill harness'
  plugin-root variable when available) before dispatching subagents.
- Batch scratch dir: `/tmp/decklet-batches/<timestamp>/`

## Step 1 — Collect the word list

Two modes:

**A. No explicit list** (e.g. "backfill card backs", "fill in the missing card
backs"): query the DB for cards in `learning` state with empty back.

```sql
SELECT word FROM cards
WHERE archived_at IS NULL
  AND state = 'learning'
  AND (back IS NULL OR back = '');
```

**B. Explicit list** (e.g. "add card backs for: cat, dog, pig", or a
newline-separated list): use exactly what the user gave. Do NOT query the DB.

Report the count back to the user before dispatching.

## Step 2 — Ask about review

Ask once, up front (before any agent runs):

> Pause for review after generation, or go straight through to DB write-back?

- If the user wants to review → stop after Step 5 and wait for natural-language
  "write back" / "commit to DB" / equivalent.
- If the user declines → proceed through Step 6 automatically once all agents
  finish.

## Step 3 — Batch the words

- Write the word list to `/tmp/decklet-batches/<ts>/all-words.txt` (one per
  line).
- Split into batch files of **5 words each**, named `batch-r000`,
  `batch-r001`, …
- The last batch may be short.

## Step 4 — Dispatch subagents (wave strategy)

For each batch file, spawn one **background** Agent (general-purpose). Dispatch
in **waves of ~30** — after each wave's notifications trickle in, fire the next.
Do NOT try to launch 100+ agents in one message.

Each subagent prompt is small — just file paths:

> Read the spec at `<absolute-path-to-card-spec.md>` and the batch at
> `/tmp/decklet-batches/<ts>/batch-rNNN`. Generate card-back `.org` files per
> the spec and write them to `<decklet-dir>/card-backs/`. Report per the spec's
> Deliverable section.

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

## Step 6 — Write back to DB (on user signal, or automatic if review was declined)

Triggered by natural language "write back" / "commit to DB" — or automatically
if the user declined review in Step 2.

**Always back up first.** Match files to DB rows by normalized word = filename:

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

def norm(w):
    return w.lower().replace('–', '-').replace('—', '-').replace(' ', '-')

conn = sqlite3.connect(db, timeout=30)
# Target ONLY the words from Step 1 (either the DB queue or the explicit
# list).  Never overwrite a non-empty back.
words = [...]  # fill in from Step 1
updated = 0
for w in words:
    path = os.path.join(cb_dir, norm(w) + '.org')
    if not os.path.exists(path):
        continue
    with open(path) as f:
        content = f.read()
    cur = conn.execute(
        "UPDATE cards SET back = ? "
        "WHERE word = ? AND archived_at IS NULL AND (back IS NULL OR back = '')",
        (content, w),
    )
    updated += cur.rowcount
conn.commit()
conn.close()
print(f'updated {updated} rows; backup at {backup}')
```

After the write-back, tell the user:

- how many rows were updated,
- the backup path, and
- a reminder to refresh any open decklet buffer (press `g`) to see the change.

## Notes & gotchas

- `state='learning' AND last_review IS NULL` corresponds to "new" cards in
  decklet terminology; they share the same state column. For generation
  purposes we don't need to distinguish.
- Filename normalization edge cases: en-dash `–` and em-dash `—` → `-`; spaces
  → `-`; accented letters preserved. See `card-spec.md` for the full rules.
- Never skip the spec's HARD REQUIREMENTS. The AmE/BrE section is always
  present, example count >= meaning count, single space before sense tag.
- NEVER commit generated `.org` files or the SQLite DB via git unless the user
  explicitly asks.
