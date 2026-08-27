# Hint generation spec

A decklet card's `hint` is a single example sentence (occasionally two) shown as
a memory aid, with the target word wrapped in asterisks per the deck's
convention:

```
We climbed a *rickety* wooden staircase up to the attic.
```

Hints are derived from the card back's `* Example Sentences` block, so a card
back must exist before its hint can be written.

## Choosing the sentence(s)

1. Read the card back's `* Meaning` section and find the sense marked most
   common (senses carry frequency labels like `/(most common)/`,
   `/(also common)/`, `/(less common)/`).
2. From `* Example Sentences`, pick **one** sentence illustrating that sense.
3. Pick a **second** sentence only when the word genuinely has two distinct
   high-frequency senses a learner must keep apart — typically a POS split or a
   contronym: `scab` (wound crust / strikebreaker), `temple` (building / side of
   the head), `mull` (mull over / mulled wine), `nonplussed` (bewildered /
   AmE unfazed). One sentence is the default; two is the exception.
4. Separate two sentences with a single blank line.

## Transforming the sentence

- Delete the leading `N. ` numbering.
- Delete the trailing **sense tag** — e.g. ` (young deer)`, ` (flatter)`.
- **Keep variety labels** `(AmE)` / `(BrE)`. When an example ends with both, as
  in `... tear up the floor. (sports shoes) (AmE)`, drop only the sense tag and
  keep the variety label at the end:
  `Don't wear your *cleats* inside the house — they'll tear up the floor. (AmE)`
- Keep parentheses that belong to the sentence itself.
- Wrap the target word in single asterisks, exactly as it appears, including
  inflection: `insular` → `*insular*`, `cleats` → `*cleats*`, `prima donna` →
  `*prima donna*`. Wrap the whole multi-word phrase, not each word. Wrap only
  the first occurrence if the word appears twice.
- Change nothing else about the sentence's wording or punctuation.

## Never overwrite an existing hint

Some cards already carry a hand-written hint — a plural note (`lice (plural)`),
a Chinese gloss (`虞美人/丽春花`), or a sentence the user chose themselves.
Generate a hint only where the column is NULL or blank, and let the DB write
enforce it with `AND (hint IS NULL OR trim(hint) = '')`.
