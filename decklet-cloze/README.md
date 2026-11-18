# decklet-cloze

Asks you to type the word before a
[Decklet](https://github.com/yilin-zhang/decklet) card is revealed. The card
is masked, you type the word, and then you grade it with `1`–`4` as usual. The
prompt does not change scheduling or write to the review log.

## Setup

```emacs-lisp
(use-package decklet-cloze
  :vc (:url "https://github.com/yilin-zhang/decklet-extensions"
       :lisp-dir "decklet-cloze"
       :rev :newest)
  :custom
  ;; Marker regexp; submatch 1 is an answer.
  ;; (decklet-cloze-marker-regexp "\\*\\([^*\n]+\\)\\*")
  ;; Card eligibility function.
  ;; (decklet-cloze-predicate #'decklet-cloze-predicate-stability)
  ;; Attempts before reveal; 0 is unlimited.
  ;; (decklet-cloze-attempts 1)
  ;; Answer comparison function.
  ;; (decklet-cloze-compare-function #'decklet-cloze-default-compare)
  ;; Initial minibuffer prompt.
  ;; (decklet-cloze-prompt "Type the word: ")
  :hook (decklet-review-mode . decklet-cloze-mode))
```

## Usage

A card uses cloze when its hint has a marked answer and
`decklet-cloze-predicate` accepts it. The default predicate needs at least 21
days of FSRS stability, so new and learning cards stay in the normal flow. To
use cloze on every marked card:

```emacs-lisp
(setopt decklet-cloze-predicate (lambda (_card) t))
```

| Key or command | Description |
|---|---|
| `C` | Force cloze for the current card |

While a card is masked, its hint shows at once. Empty `RET` or `C-g` gives up.
A wrong answer reveals the card unless attempts are left, and the echo area
then shows `Cloze: correct`, `Cloze: incorrect` or `Cloze: gave up`.

### Answers and markers

The card's word is always accepted, and so is every marked answer in the hint.
The default comparison ignores case, accents (`façade` matches `facade`), dash
variants and superscript or subscript number labels.

The default marker is `*answer*`. For another style, set a regexp whose
submatch 1 is the answer:

```emacs-lisp
(setopt decklet-cloze-marker-regexp "{{\\([^}\n]+\\)}}")
```

Other forms of the word in the hint, including common suffix forms, are masked
too, so the hint does not give the answer away. They do not turn cloze on by
themselves.

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
