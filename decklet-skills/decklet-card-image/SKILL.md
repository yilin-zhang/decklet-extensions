---
name: decklet-card-image
description: Generate or restyle square, text-free Decklet vocabulary illustrations in a consistent loose fountain-pen and transparent-watercolor style, then optionally install them through decklet-images. Use for concrete nouns, hard-to-picture adjectives, replacing inconsistent downloaded art, or backfilling missing card images.
---

# Decklet Card Image

Create one compact mnemonic illustration per vocabulary word. Keep the visual
system consistent across the deck while making the target sense immediately
recognizable.

## Required resources

Read [references/style.md](references/style.md) before generating an image.
Use [assets/style-reference.png](assets/style-reference.png) as a **style
reference only**. Never copy its caliper subject or composition into another
word's image.

Use the image-generation capability available in the current harness. When the
`imagegen` skill is available, follow its instructions. If no image-generation
capability is available, explain that limitation and stop instead of silently
substituting an unrelated external service.

## Workflow

1. Identify the exact target sense from the user's definition, example, or card
   context. Ask only when two plausible senses would produce materially
   different pictures.
2. Check whether the word already has an image before replacing it. Do not
   overwrite an existing image without the user's approval.
3. Choose one memorable subject or micro-scene:
   - For a concrete noun, show the object clearly; show it in use when the
     action helps distinguish it.
   - For an adjective, verb, or abstract idea, translate the meaning into one
     observable human action or physical contrast. Avoid arbitrary symbols.
4. Build the prompt from `references/style.md`. Attach the bundled style image
   when the image tool supports local references, and label it explicitly as a
   style-only reference.
5. Generate one square image per distinct word. Do not request a contact sheet
   or multiple words in one image.
6. Inspect the result at full size. Regenerate once with a targeted correction
   if it contains text, is visibly tilted or cropped, has implausible geometry,
   misses the target sense, or drifts from the style contract.
7. Save the accepted result as PNG. If the user asked to add it to Decklet,
   install it through `decklet-images-set-file`.

## Restyling an existing image

Treat an existing or downloaded image as a semantic reference, not a layout to
trace. Preserve the useful subject, action, and distinguishing features, but
recompose them in the Decklet style. Do not reproduce identifiable people,
logos, branded packaging, or distinctive copyrighted composition details.

## Install into Decklet

Prefer Decklet's public command over copying directly:

```elisp
(decklet-images-set-file WORD PNG-PATH)
```

Call it non-interactively through the user's running Emacs when possible. This
respects `decklet-images-directory`, validates the card, replaces other image
extensions atomically, and refreshes the Decklet UI.

Before installation, query `(decklet-images-file WORD)` or otherwise inspect
the image store. If an image already exists and replacement was not explicitly
requested, leave the new file uninstalled and ask for confirmation.

If a running Emacs is unavailable, keep the generated PNG in a stable path and
report it so the user can run `M-x decklet-images-set-file` manually. Do not
guess a custom Decklet directory.

## Batch behavior

Confirm the style with one representative word before generating a large batch.
Then reuse the same style contract and reference image for every word while
varying only the semantic scene and restrained accent color. Report failures
per word without discarding successful images.

## Deliverable

Report the word, target sense, accepted image path, and whether it was installed
into Decklet. Briefly name the depicted memory scene so the semantic choice is
auditable.
