# Card-back generation spec

You will generate thorough Emacs Org-mode card backs for a list of English vocabulary words. Match the depth and structure of the GOLD STANDARD below exactly.

## Steps
1. Read the batch file whose path will be given to you in the agent task. Each non-empty line is one word/phrase.
2. For each line, write one file named `<normalized>.org` into the output directory given in the agent task. Overwrite if it exists.

## Filename normalization
- lowercase
- space → `-`
- en-dash `–` and em-dash `—` → `-`
- keep accented letters (é, à, …) as-is
- keep other characters as-is

Examples: "electric cattle prod" → electric-cattle-prod.org ; "vis-à-vis" → vis-à-vis.org ; "cold–call" → cold-call.org ; "Chaucer" → chaucer.org

## GOLD STANDARD (your output must match this depth)

```
#+TITLE: Fawn
#+SUBTITLE: noun, verb, adjective | /fɔːn/

* Meaning

1. /(most common — noun)/ A young deer, especially one less than a year old.
2. /(also common — verb)/ To try to gain someone's favor by flattering them excessively, being overly attentive, or behaving in a servile way. Usually used with /over/ or /on/, and carries a negative, disapproving tone.
3. /(common — adjective/noun)/ A pale yellowish-brown color, like the coat of a young deer. Often used to describe clothing, animal fur, or paint.
4. /(less common — verb)/ Of a dog: to show affection by crouching, wagging, and licking. This is the original sense from which the flattery meaning developed.
5. /(specialized — psychology)/ A trauma response (alongside fight, flight, and freeze) in which a person copes with threat by people-pleasing, appeasing, or losing themselves in others' needs. Increasingly common in everyday mental-health conversations.

* American vs. British English

No major difference in meaning — all senses are understood on both sides of the Atlantic.

- /Spelling/: same in both (/fawn/).
- /Pronunciation/: essentially identical — AmE /fɔn/ or /fɑn/, BrE /fɔːn/.
- /Color use/: slightly more common in British English when describing clothing or interiors (e.g., "a fawn coat," "fawn carpet"). Americans are more likely to say /tan/ or /beige/ in the same contexts.

* Example Sentences

#+BEGIN_EXAMPLE
1. We spotted a tiny fawn standing beside its mother at the edge of the forest. (young deer)
2. The new employee kept fawning over the CEO, laughing too loudly at all his jokes. (flatter)
3. I can't stand the way he fawns on anyone with money or power. (flatter)
4. She wore a fawn cashmere sweater with dark brown trousers. (color)
5. The puppy fawned at my feet, tail wagging furiously. (dog affection)
6. Therapists now talk about the "fawn response" as a way some people cope with conflict. (psychology)
#+END_EXAMPLE

* Notes

- /Register/: the "flatter" sense is disapproving — to say someone is /fawning/ is almost always an insult. Don't use it about behavior you actually admire.
- /Common collocations/: /fawn over/ (someone), /fawn on/ (someone), /fawning praise/, /fawning attention/, /a fawn-colored/ (coat, dog, etc.).
- /Synonyms for the flattery sense/: grovel, suck up to, butter up, toady, kowtow, bootlick.
- /Don't confuse with/:
  - /faun/ (a mythological half-human, half-goat creature — same pronunciation, different word).
  - /phone/ (similar sound to some ears but unrelated).
- /Etymology tip/: the flattery meaning comes from how dogs fawn on their owners — crouching, licking, wagging — so picture an over-eager puppy when you hear someone described as /fawning/.
- /Plural/ of the noun: /fawns/. The verb conjugates regularly: /fawn, fawned, fawning/.
```

## HARD REQUIREMENTS (non-negotiable)

### `#+TITLE:` and `#+SUBTITLE:`
- `#+TITLE:` = the word/phrase in its ORIGINAL form from the batch file (preserve case, accents, dashes).
- `#+SUBTITLE:` = all applicable parts of speech joined with `, ` (e.g. `noun, verb, adjective`), then ` | ` then IPA in slashes.

### `* Meaning` (always present)
- Cover all genuinely common senses. For multi-sense words, aim for 3–5 senses. For truly single-sense words, one is fine — but think hard first (many "simple" words have verb/adjective/figurative uses).
- Every sense numbered, starting with frequency label like `/(most common)/`, `/(also common — verb)/`, `/(less common)/`, `/(specialized — psychology)/`, `/(slang)/`, `/(figurative)/`. Tag the part of speech inside the frequency label when senses cross POS.
- Each definition is 1–3 sentences with enough context to actually understand the word (not a bare gloss).
- Include specialized / slang / psychology / tech / finance / medical senses when they exist and are encountered in modern usage.

### `* American vs. British English` (ALWAYS PRESENT — do NOT omit)
- This section appears on every card, even when there is no major semantic difference.
- Structure: a one-sentence lead, then a bulleted list covering the applicable axes:
  - `/Spelling/:` (e.g. color/colour, realize/realise, program/programme)
  - `/Pronunciation/:` give both AmE and BrE IPA if they differ noticeably; still note it when nearly identical
  - `/Meaning/:` any sense that is AmE-only, BrE-only, or carries different connotations
  - `/Frequency/:` is the word more common on one side
  - `/Different word/:` if Americans and Brits use different everyday words (elevator/lift, pants/trousers)
  - `/Register/:` formality / slang differences between varieties
- If genuinely no meaningful difference, still write the lead sentence and a short list noting spelling same, pronunciation same, usage equivalent — do not omit the section.

### `* Example Sentences` (always present)
- **Example count >= Meaning count.** Every sense listed under `* Meaning` MUST get at least one example. If you have 5 senses, write at least 5 examples; 6 is ideal. If one sense is especially common, give it two.
- All inside `#+BEGIN_EXAMPLE` … `#+END_EXAMPLE`.
- Numbered `1.`, `2.`, … at column 0.
- Each sentence ends with a parenthetical tag naming the sense it illustrates, separated by a SINGLE SPACE — e.g. `... the edge of the forest. (young deer)`. Do NOT pad with multiple spaces for column alignment.
- Use AmE/BrE variety labels like `(AmE)` / `(BrE)` inside or alongside when the example showcases a variety-specific usage.

### `* Notes` (always present, rich)
- Bulleted list. Must cover at least 4 of the following categories:
  - `/Register/:` formal/informal/slang/offensive, tone, appropriateness
  - `/Common collocations/:` list several real collocations the learner will encounter
  - `/Synonyms/:` AND/OR `/Antonyms/:` for the main sense(s)
  - `/Don't confuse with/:` homophones, near-misses, easily-confused words (with brief disambiguation)
  - `/Etymology tip/:` when it aids memory
  - `/Inflections/:` plural form for nouns, irregular verb forms, comparative/superlative for adjectives (skip if trivially regular and unremarkable)
  - `/Common mistakes/:` typical learner errors
- Nest sub-items with 2-space indentation for things like the homophone list in the gold standard.

### Formatting
- Italics `/text/`, bold `*text*`, inline code `=text=`.
- Every numbered meaning, every bullet, every example sentence is ONE single line — never wrap.
- `-` and `1.` start at column 0 (sub-items indent 2 spaces).
- Blank line before and after each `*` heading.
- Single space between example sentence ending and the `(sense tag)` — no multi-space column alignment.

### Proper nouns & phrases
- Proper nouns (Chaucer, Frisbee, Lutheran): the Meaning section explains who/what it refers to and why it's culturally known. Still include AmE/BrE and Notes (origin, related terms, pronunciation quirks).
- Multi-word phrases / idioms (je ne sais quoi, penny arcade, electric cattle prod): treat as a single entry; the `#+TITLE:` is the full phrase; part-of-speech is `idiom`, `noun phrase`, etc.

## Deliverable
Write all files from the batch. At the end, report in under 60 words:
- files written count
- for each file, a one-token sanity flag: "full" (meets all hard requirements) or name the missing piece (e.g. "missing-notes", "amebre-thin")
- any word you could not handle and why

Do NOT skip any word. Do NOT shortcut the `* American vs. British English` section.
