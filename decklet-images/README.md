# decklet-images

Per-word image sidecar for [Decklet](https://github.com/yilin-zhang/decklet)
flashcards. Stores one image file per word, supports downloading from a URL
or copying from a local file, and displays images in a popup window on
demand during review.

Built on Decklet's public extension API: image files are kept in sync with
the deck automatically via Decklet's card lifecycle hooks, so deleting or
renaming a word also deletes or renames its image file.

## Setup

```emacs-lisp
(use-package decklet-images
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-images/"
  :after decklet)
```

By default, `decklet-images` follows `decklet-directory`:

- Image store: `decklet-directory/images/`

Set `decklet-images-directory` to override.

## Commands and key bindings

On load, `decklet-images` binds `i` and `I` in both `decklet-review-mode`
and `decklet-edit-mode`:

| Key | Command | Description |
|---|---|---|
| `i` | `decklet-images-show` | Show the image for the current word in a popup |
| `I` | `decklet-images-set` | Download or copy an image for the current word |
| — | `decklet-images-delete` | Remove the image for the current word |

`decklet-images-set` prompts for a single source string:

- If it starts with `http://` or `https://`, the image is **downloaded**
  (via `url-copy-file`).
- Otherwise, it is treated as a **local file path** and copied into the
  image store.

The extension is inferred from the URL path or the source file name, and
falls back to `decklet-images-default-extension` (default `png`) when it
can't be determined.

## Popup display

Press `i` during review or edit to open a popup window showing the current
word's image. The buffer uses `decklet-images-view-mode`, a read-only mode
derived from `special-mode`; press `q` to close.

If the frame is non-graphic or no image exists for the word, the command
reports via `message` instead of creating a buffer.

You can reshape how the popup is displayed via `display-buffer-alist`.
The buffer name starts with `*Decklet Image: ` followed by the word.

## Review indicator

When a card has an image, the review UI shows a centered `[IMG]` line
below the hint area. The component is added to
`decklet-review-floating-components` automatically on load.

Toggle the indicator at runtime with `decklet-images-show-indicator`, or
reorder / remove it by customizing the component list directly.

## Automatic sync with card lifecycle

On load, `decklet-images` subscribes to Decklet's card lifecycle hooks so
the image store stays in sync with the deck without any explicit action:

- `decklet-card-deleted-functions` — the image for a deleted word is
  removed immediately and any visible popup for it is closed.
- `decklet-card-renamed-functions` — the image file is renamed along with
  the word.

No drift patrol, no batch sync command — the folder tracks the deck in
real time.

## Customization

| Variable | Default | Description |
|---|---|---|
| `decklet-images-directory` | `nil` | Override image store directory; `nil` uses `decklet-directory/images/` |
| `decklet-images-extensions` | `("png" "jpg" "jpeg" "gif" "webp")` | Extensions recognized when looking up images |
| `decklet-images-default-extension` | `"png"` | Fallback extension when one cannot be inferred from a URL |
| `decklet-images-show-indicator` | `t` | Show `[IMG]` in the review UI |
| `decklet-images-indicator-face` | inherits `decklet-card-back-indicator-face` | Face for the `[IMG]` indicator |

## License

GNU General Public License v3.0. See the header of `decklet-images.el`.
