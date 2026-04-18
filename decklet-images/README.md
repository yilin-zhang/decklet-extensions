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
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-images/"
  :hook ((decklet-review-mode . decklet-images-mode)
         (decklet-edit-mode   . decklet-images-mode)))
```

Adding `decklet-images-mode` to the review/edit hooks loads the
package as soon as you enter a Decklet buffer, so the review
indicator and the lifecycle hooks (delete/rename sync) are active
from the very first card — not deferred until you invoke a command.

By default, `decklet-images` follows `decklet-directory`:

- Image store: `decklet-directory/images/`

Set `decklet-images-directory` to override.

## Mode and key bindings

`decklet-images-mode` is a buffer-local minor mode that owns the
package's key bindings via `decklet-images-mode-map`:

| Key | Command | Description |
|---|---|---|
| `i`   | `decklet-images-show`     | Show the image for the current word in a popup |
| `I`   | `decklet-images-set-url`  | Download an image from an `http(s)` URL |
| `M-i` | `decklet-images-set-file` | Copy a local file into the image store |

To rebind, customize `decklet-images-mode-map` directly. The mode
itself ships no opinions about which buffers it belongs in — pin it
to the relevant Decklet modes via `:hook` (or `add-hook`) as above.

Both `set` commands accept an **empty input** as the deletion sentinel:
they ask for confirmation and then remove any existing image for the
word (no-op if there is none).

- `decklet-images-set-url` reads via `read-string` and rejects anything
  that does not start with `http://` or `https://`.
- `decklet-images-set-file` reads via `read-file-name`, so paths get
  TAB-completion and `~` is expanded automatically.

The extension is inferred from the URL path or the source file name, and
falls back to `decklet-images-default-extension` (default `png`) when it
can't be determined.

## Popup display

`decklet-images-show` opens a default-sized popup window and **scales
the image** (preserving aspect ratio, via `:max-width`/`:max-height`)
to fit within the window minus `decklet-images-popup-padding`
characters of inset on each axis. The scaled image is then centered
in the buffer. Resizing or re-splitting the popup re-fits and
re-centers it automatically. Press `q` to close.

Image scaling requires `image-transforms-p` support in Emacs (built
with ImageMagick or libwebp/libjpeg/etc.); without it the image
displays at native size.

If the frame is non-graphic or no image exists for the word, the command
reports via `message` instead of creating a buffer.

You can reshape how the popup is displayed via `display-buffer-alist`.
The buffer name starts with `*Decklet Image: ` followed by the word.

## Review indicator

When a card has an image, the review UI shows a centered indicator line
below the hint area. The default string is `♣`, and setting
`decklet-images-indicator` to nil hides it entirely. The component is
added to `decklet-review-floating-components` automatically on load.

In edit mode, `decklet-images` also inserts an `Image` column after the
built-in `Back` column and shows the same indicator for rows that have an
image.

Change the indicator string at runtime with `decklet-images-indicator`,
set it to `nil` to hide it entirely, or reorder / remove the component
by customizing the component list directly.

## Automatic sync with card lifecycle

On load, `decklet-images` subscribes to Decklet's card lifecycle hooks so
the image store stays in sync with the deck without any explicit action:

- `decklet-cards-deleted-functions` — the image for the deleted card's
  pre-delete word snapshot is removed immediately and any visible popup for
  it is closed.
- `decklet-cards-renamed-functions` — the image file is renamed along with
  the word.

No drift patrol, no batch sync command — the folder tracks the deck in
real time.

## Customization

| Variable | Default | Description |
|---|---|---|
| `decklet-images-directory` | `nil` | Override image store directory; `nil` uses `decklet-directory/images/` |
| `decklet-images-extensions` | `("png" "jpg" "jpeg" "gif" "webp")` | Extensions recognized when looking up images |
| `decklet-images-default-extension` | `"png"` | Fallback extension when one cannot be inferred from a URL |
| `decklet-images-popup-padding` | `1` | Char-cell inset between the scaled image and the window edges |
| `decklet-images-indicator` | `"♣"` | Review indicator string; set to `nil` to hide it |
| `decklet-images-indicator-face` | green foreground, bold | Face for the review indicator |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
