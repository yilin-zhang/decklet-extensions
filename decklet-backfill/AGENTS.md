## Specs

- `specs/` contains a detailed feature spec. Read the front matter (`summary` field) for a quick overview.
- When making code changes, check whether the spec covers the affected area and update it to stay in sync.
- When implementing a new feature, sketch the spec first and align with the user before writing code.

## Verification

Run the tests with `emacsclient`:

```elisp
(progn
  (add-to-list 'load-path "/Users/yilinzhang/.emacs.d/site-lisp/decklet")
  (add-to-list 'load-path "/Users/yilinzhang/.emacs.d/site-lisp/decklet-backfill")
  (load "/Users/yilinzhang/.emacs.d/site-lisp/decklet-backfill/tests/decklet-backfill-test.el" nil t)
  (ert-run-tests-batch-and-exit t))
```
