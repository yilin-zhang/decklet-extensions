# decklet-cloze

Active-production prompts for
[Decklet](https://github.com/yilin-zhang/decklet) reviews.  A hinted card is
masked, the user types the word, and the card is revealed before Decklet's
normal `1`–`4` grading.

The prompt never changes scheduling or writes to the review log.

## Setup

```emacs-lisp
(use-package decklet-cloze
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-cloze/"
  :hook (decklet-review-mode . decklet-cloze-mode))
```

Every card whose hint matches `decklet-cloze-marker-regexp` and has at least
21 days of FSRS stability uses cloze by default, keeping new and still-learning
cards in the normal review flow.  Press `C` after a reveal to retry the current
card.

`decklet-cloze-predicate` can replace the stability policy with any function
of the public card plist.  Marker matching is always required.  For example,
to enable every marked card:

```emacs-lisp
(setq decklet-cloze-predicate (lambda (_card) t))
```

## Answers and hint markers

The card's `word` is always accepted.  Text captured by
`decklet-cloze-marker-regexp` is masked and accepted too, including multiple
marked answers in one hint.

The default comparison ignores case and uses Unicode compatibility
normalization and character folding.  Superscript or subscript numeric labels
are discarded, decomposable Latin diacritics are folded to ASCII (`façade`
matches `facade`), and Unicode dash characters are treated as ordinary
hyphens.

The default regexp recognizes the `*answer*` syntax produced by Decklet's
Kindle importer.  Submatch 1 is the answer text.  For another marker style:

```emacs-lisp
(setq decklet-cloze-marker-regexp "{{\\([^}\n]+\\)}}")
```

On an eligible card, remaining bare occurrences of the word and common suffix
forms are also masked and accepted, preventing the rest of the hint from
leaking the answer.  Bare occurrences alone do not enable cloze.

While a cloze card is masked, its hint is shown immediately regardless of
`decklet-review-hint-delay`, because the hint is needed to answer the prompt.

## Attempts and feedback

`decklet-cloze-attempts` defaults to `1`.  Set it higher for retries or to `0`
for unlimited attempts.  Incorrect retries do not reveal the answer.  Empty
`RET` and `C-g` give up.

After reveal, the echo area reports `Cloze: correct`, `Cloze: incorrect`, or
`Cloze: gave up`.

## Customization

| Variable | Default | Description |
|---|---|---|
| `decklet-cloze-marker-regexp` | `\\*\\([^*\n]+\\)\\*` | Marker regexp; submatch 1 is an answer |
| `decklet-cloze-predicate` | `decklet-cloze-predicate-stability` | Card eligibility function |
| `decklet-cloze-attempts` | `1` | Attempts before reveal; `0` is unlimited |
| `decklet-cloze-compare-function` | Unicode/diacritic normalization, case-fold, dash-flexible match | Answer comparison function |
| `decklet-cloze-prompt` | `"Type the word: "` | Initial minibuffer prompt |

## License

GPL v3. See the repository-level [`LICENSE`](../LICENSE).
