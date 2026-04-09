---
name: english-explainer
description: Explain English words or phrases to the user. Use this skill whenever a user gives you a single word, a phrase, an idiom, a phrasal verb, or any expression in English and wants to understand what it means. Triggers include requests like "explain this word", "what does X mean?", "give me examples of X", "how do I use X?", or when the user simply pastes a word or phrase with no other context. Also triggers when the user writes a word followed by a format hint in parentheses or brackets, e.g. "resilience (org)", "bite the bullet [md]", "pants (markdown)", "schadenfreude [org mode]". Always use this skill for vocabulary and phrase explanation tasks, even if the request is short or simple.
---

# English Word/Phrase Explainer

When the user gives you a word or phrase in English, provide a clear, helpful explanation structured as follows:

## Output Format

### 1. Word / Phrase
State the word or phrase clearly (with pronunciation guide in IPA or simple phonetics if it's tricky to pronounce).

### 2. Part of Speech
Label it: noun, verb, adjective, adverb, idiom, phrasal verb, expression, etc.

### 3. Meaning
**Always lead with the American English meaning.** If the word has multiple meanings, **list them in order of everyday frequency** — the most common, everyday usage comes first; rarer or more specialized meanings come later. Give a clear, plain-English definition for each. Keep definitions concise but complete.

When listing multiple meanings, briefly signal frequency where helpful, e.g.:
- *(most common)* …
- *(also common)* …
- *(less common / more formal / specialized)* …

Don't list obscure meanings just for completeness — focus on what a typical person would actually encounter.

### 4. American vs. British English (include whenever relevant)
This section is important. Cover any of the following that apply:
- **Different meaning**: If the word means something different (or something additional) in British English, explain the British sense clearly. (e.g., "pants" = trousers in AmE, but underwear in BrE)
- **Different spelling**: Note spelling variants (e.g., color/colour, realize/realise)
- **Different word entirely**: If Americans and British people use completely different words for the same thing, note both (e.g., "elevator" AmE = "lift" BrE; "chips" AmE = "crisps" BrE)
- **Mainly British**: If the word/phrase is primarily used in British English and would sound odd or be unfamiliar to Americans, say so clearly
- **Nuance or frequency**: If the word exists in both but carries different connotations, formality levels, or frequency of use in each variety, explain the difference
- **Pronunciation difference**: If AmE and BrE pronounce it noticeably differently, note both (e.g., "schedule": AmE /ˈskɛdʒuːl/, BrE /ˈʃɛdjuːl/)

If there is no meaningful difference between AmE and BrE for this word, skip this section entirely — don't add a note just to say "same in both."

### 5. Example Sentences
Provide **3–5 natural example sentences** that show the word/phrase used in context. Vary the sentences:
- Use different tenses or forms where applicable
- Include both formal and informal registers if the word fits both
- Make the context clear so the meaning is obvious from usage
- If AmE/BrE usage differs significantly, include at least one example for each

### 6. Notes (optional, include when relevant)
Add any of the following if helpful:
- Common collocations (words it often appears with)
- Register/tone: is it formal, informal, slang, etc.?
- Common mistakes or confusions (e.g., "don't confuse with X")
- Synonyms or antonyms
- Etymology or memory tip if it aids understanding

## Tone & Style
- Write as a friendly, knowledgeable English teacher
- Keep explanations accessible — avoid linguistic jargon unless necessary
- If the word/phrase is slang or offensive, note that clearly but still explain it
- If the input is ambiguous (e.g., "bank" could be financial or riverbank), briefly list the main meanings before going deeper, or ask the user to clarify which sense they mean

## Artifact Output (Markdown / Org Mode)

If the user requests a specific output format, generate the explanation as a downloadable artifact file instead of (or in addition to) the inline chat response.

### Detecting the format request

The user signals this by appending a format hint to the word/phrase, in parentheses or brackets. Recognize all of these as equivalent:

| User writes | Format |
|---|---|
| `word (org)` / `word [org]` / `word (org mode)` / `word [org-mode]` | Emacs Org Mode (`.org`) |
| `word (md)` / `word [md]` / `word (markdown)` / `word [markdown]` | Markdown (`.md`) |

### Markdown artifact

No front matter. Use `#` for everything — the word/phrase title and all section headings are all `#` (flat, no hierarchy). List formatting: `-` starts at column 0; do NOT wrap long lines — keep each bullet or paragraph on a single line, no matter how long. Structure:

```markdown
# Word / Phrase

*part of speech* | /pronunciation/

# Meaning

1. *(most common)* Definition here.
2. *(also common)* Another definition.

# American vs. British English

Notes on AmE/BrE differences if relevant.

# Example Sentences

1. First example sentence.
2. Second example sentence.
3. Third example sentence.

# Notes

- Collocation or usage tip
- Synonyms: x, y, z
```

### Org Mode artifact

Use `#+KEYWORD:` file-level directives for metadata — no `*` heading hierarchy. Key conventions:
- `#+TITLE:` for the word/phrase
- `#+SUBTITLE:` for part of speech and pronunciation (on one line, separated by ` | `)
- Use `*` headings for sections (Meaning, Examples, etc.), NOT for the top-level word title — that goes in `#+TITLE:`
- Use `#+BEGIN_EXAMPLE` / `#+END_EXAMPLE` blocks for example sentences
- Italics: `/text/`, bold: `*text*`, inline code: `=text=`
- Frequency labels like `/(most common)/`
- List formatting: `-` starts at column 0; do NOT wrap long lines — keep each bullet or paragraph on a single line, no matter how long

```org
#+TITLE: Word / Phrase
#+SUBTITLE: part of speech | /pronunciation/

* Meaning

1. /(most common)/ Definition here.
2. /(also common)/ Another definition.

* American vs. British English

Notes on differences if relevant.

* Example Sentences

#+BEGIN_EXAMPLE
1. First example sentence.
2. Second example sentence.
3. Third example sentence.
#+END_EXAMPLE

* Notes

- Collocation or usage tip
- Synonyms: x, y, z
```

### Behavior

- Generate the artifact **and** give a brief inline summary in chat (2–3 sentences) — don't just silently drop a file with no explanation.
- Name the file after the word/phrase, e.g. `resilience.org`, `bite-the-bullet.md`.
- If the format hint is unrecognized, default to Markdown and mention it.

## Example Interactions

---

**User input:** "bank"

**Bank**

**Meaning:**
1. *(most common)* A financial institution where people deposit money, take out loans, or make transactions. — *noun*
2. *(very common)* The land along the side of a river or lake. — *noun*
3. *(common)* To rely or count on something; also to store something for future use. — *verb*
4. *(less common)* When a plane or vehicle tilts sideways while turning. — *verb*

**Example sentences:**
1. I need to stop by the bank to deposit this check.
2. We sat on the bank of the river and watched the sunset.
3. She's been banking on getting that promotion for months.
4. The plane banked sharply to the left before landing.

**Notes:**
- "Bank on" (phrasal verb) = to rely on or count on something: *"Don't bank on him showing up on time."*
- Collocations: bank account, bank transfer, river bank, blood bank

---

**User input:** "bite the bullet"

**Bite the bullet**
*(idiom | /baɪt ðə ˈbʊlɪt/)*

**Meaning:** To endure a painful or difficult situation with courage; to force yourself to do something unpleasant that can't be avoided.

**Example sentences:**
1. I hate going to the dentist, but I just had to bite the bullet and make an appointment.
2. The company knew layoffs would be unpopular, but they bit the bullet and announced them anyway.
3. She bit the bullet and apologized, even though she felt she wasn't entirely wrong.

**Notes:**
- Origin: historically, soldiers were given a bullet to bite down on during painful field surgery.
- Synonyms: grin and bear it, tough it out, face the music
- Register: informal; common in everyday speech and writing in both AmE and BrE

---

**User input:** "pants"

**Pants**
*(noun)*

**Meaning (American English):** Trousers; the garment worn on the lower body covering both legs. This is the standard everyday word in the US.

**American vs. British English:**
- In **British English**, "pants" typically means *underwear* (specifically underpants). What Americans call "pants," the British call **trousers**.
- This is a classic false friend between the two varieties — using "pants" in the UK the American way can cause confusion or laughs.
- BrE speakers do understand the American meaning from context (TV, film, etc.), but wouldn't naturally use it themselves.

**Example sentences:**
1. *(AmE)* I need to buy a new pair of pants for the job interview.
2. *(AmE)* He spilled coffee on his pants.
3. *(BrE)* I can't find my pants — have you seen them? *(= underwear)*
4. *(BrE)* You should wear smart trousers to the meeting. *(= what Americans would call "pants")*

**Notes:**
- In BrE, "pants" can also be used informally as an adjective meaning *bad* or *rubbish*: "That film was absolute pants."
- Synonyms (AmE): trousers, slacks, chinos
