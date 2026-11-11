# decklet-images

Per-card image sidecar for [Decklet](https://github.com/yilin-zhang/decklet)
flashcards. Stores one image file per card, supports downloading from a URL
or copying from a local file, and displays images in a popup window on
demand during review.

Built on Decklet's public extension API. Image files stay in sync with the
deck through Decklet's card lifecycle hooks, so deleting a card also deletes
its image file.

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
indicator, the edit column and the lifecycle hook (delete sync) are
active from the very first card. These three are registered once at
load time. The mode itself only provides the key bindings, so turning
it off in one buffer leaves the indicator and the column in place
elsewhere.

By default, `decklet-images` follows `decklet-directory`:

- Image store: `decklet-directory/images/`

Set `decklet-images-directory` to override.

Files are named by card id, `<card-id>.<ext>` (via Decklet's
`decklet-card-sidecar-file`). The id never changes, so renaming
a card needs no file handling, and words that differ only in case (`Polish`
and `polish`) cannot collide on a case-insensitive file system such as macOS's
default. Commands still take a word and resolve it to its card.

## Mode and key bindings

`decklet-images-mode` is a buffer-local minor mode that owns the
package's key bindings via `decklet-images-mode-map`:

| Key | Command | Description |
|---|---|---|
| `i`   | `decklet-images-show`     | Show the image for the current word in a popup |
| `I`   | `decklet-images-set-url`  | Download an image from an `http(s)` URL |
| `M-i` | `decklet-images-set-file` | Copy a local file into the image store |

To rebind, customize `decklet-images-mode-map` directly. The mode
does not choose its buffers, so enable it from the Decklet mode hooks
with `:hook` (or `add-hook`) as above.

Both `set` commands treat an empty input as a request to delete. They
ask for confirmation and then remove any existing image for the word
(no-op if there is none).

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
with ImageMagick or libwebp/libjpeg/etc.). Without it, the image
displays at native size.

If the frame is non-graphic or no image exists for the word, the command
reports it with `message`.

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

To reorder or remove the component, customize the component list
directly.

## Automatic sync with card lifecycle

On load, `decklet-images` subscribes to `decklet-cards-deleted-functions`.
When a card is deleted, its image is removed and any visible popup for it
is closed.

Renames need no hook, because the image is keyed by the card id and a
rename keeps the id.

There is no batch sync command. The folder tracks the deck as cards
change.

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
