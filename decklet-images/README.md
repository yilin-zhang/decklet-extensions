# decklet-images

Attach an image to a [Decklet](https://github.com/yilin-zhang/decklet) card,
from a URL or a local file, and view it in a popup during review.

## Setup

```emacs-lisp
(use-package decklet-images
  :vc (:url "https://github.com/yilin-zhang/decklet-extensions"
       :lisp-dir "decklet-images"
       :rev :newest)
  :custom
  ;; Image folder; a relative name is inside `decklet-directory'.
  ;; (decklet-images-directory "images")
  ;; Extensions recognized when looking up images.
  ;; (decklet-images-extensions '("png" "jpg" "jpeg" "gif" "webp"))
  ;; Extension used when it cannot be inferred.
  ;; (decklet-images-default-extension "png")
  ;; Space, in characters, between the image and the window edge.
  ;; (decklet-images-popup-padding 1)
  ;; Review and edit-table indicators; nil hides them.
  ;; (decklet-images-review-indicator "[IMAGE]")
  ;; (decklet-images-edit-indicator "♣")
  :hook ((decklet-review-mode . decklet-images-mode)
         (decklet-edit-mode   . decklet-images-mode)))
```

Both indicators use `decklet-images-indicator-face`.

## Usage

| Key or command | Description |
|---|---|
| `i` | Show the current word's image in a popup |
| `I` | Download an image from an `http(s)` URL |
| `M-i` | Copy a local file as the image |

Leaving the input empty in `I` or `M-i` deletes the image, after confirmation.
To rebind the keys, customize `decklet-images-mode-map`.

The popup scales the image to fit the window, and `q` closes it. Scaling needs
an Emacs built with image transform support. The popup buffer is named
`*Decklet Image: WORD*`, so you can place it with `display-buffer-alist`.

## License

GPL v3. See the repo-level [`LICENSE`](../LICENSE).
