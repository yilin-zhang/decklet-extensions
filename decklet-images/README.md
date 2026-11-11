# decklet-images

Attach an image to a [Decklet](https://github.com/yilin-zhang/decklet) card,
from a URL or a local file, and view it in a popup during review.

## Setup

```emacs-lisp
(use-package decklet-images
  :ensure nil
  :load-path "~/.emacs.d/site-lisp/decklet-extensions/decklet-images/"
  :hook ((decklet-review-mode . decklet-images-mode)
         (decklet-edit-mode   . decklet-images-mode)))
```

Images are stored in `decklet-directory/images/`, one file per card, named by
card id. Set `decklet-images-directory` to use another folder.

## Keys

| Key | Command | Description |
|---|---|---|
| `i`   | `decklet-images-show`     | Show the current word's image in a popup |
| `I`   | `decklet-images-set-url`  | Download an image from an `http(s)` URL |
| `M-i` | `decklet-images-set-file` | Copy a local file as the image |

To rebind, customize `decklet-images-mode-map`.

Leaving the input empty in either `set` command deletes the word's image,
after confirmation. The file extension comes from the URL or file name, or
`decklet-images-default-extension` when it cannot be told.

## Popup

The popup scales the image to fit the window and keeps it centered when the
window is resized. Press `q` to close it. Scaling needs an Emacs built with
image transform support; otherwise the image shows at its own size.

The popup buffer is named `*Decklet Image: WORD*`, so you can place it with
`display-buffer-alist`.

## Indicators

When a card has an image, review shows `♣` below the hint, and the edit table
shows it in an `Image` column. Set `decklet-images-indicator` to nil to hide
both.

Deleting a card deletes its image. Renaming a card keeps it.

## Customization

| Variable | Default | Description |
|---|---|---|
| `decklet-images-directory` | `nil` | Image folder; `nil` uses `decklet-directory/images/` |
| `decklet-images-extensions` | `("png" "jpg" "jpeg" "gif" "webp")` | Extensions recognized when looking up images |
| `decklet-images-default-extension` | `"png"` | Extension used when it cannot be inferred |
| `decklet-images-popup-padding` | `1` | Space, in characters, between the image and the window edge |
| `decklet-images-indicator` | `"♣"` | Indicator string; `nil` hides it |
| `decklet-images-indicator-face` | green foreground, bold | Face for the indicator |

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
