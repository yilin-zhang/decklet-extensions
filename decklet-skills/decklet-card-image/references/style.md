# Decklet card-image style contract

Use this contract for every generated image. The goal is a coherent deck, not a
pixel-identical series.

## Visual identity

- Square, compact vocabulary-card illustration.
- Plain white or very lightly warm paper; no drawn card, border, tabletop, or
  surrounding scene unless it explains the meaning.
- Human-drawn black fountain-pen contours with varied pressure, subtle doubled
  searching lines, occasional unfinished edges, and sparse cross-hatching.
- Pale transparent watercolor with uneven wash edges, small blooms, slight
  pigment pooling, dry-brush gaps, and plenty of untouched paper.
- Restrained palette: black ink, cool gray-blue, and at most one muted warm
  accent appropriate to the subject.
- Designed and readable, but visibly analog. Avoid both polished technical
  rendering and deliberately crude doodling.
- One clear focal subject or action, fully inside the frame, upright and level,
  with balanced negative space.

Never include the vocabulary word, title, caption, letters, numbers,
pseudo-writing, annotations, logos, signatures, or watermarks.

## Base prompt

Replace the bracketed fields. If the bundled reference image is attached, call
it “Image 1” and retain the first paragraph.

```text
Image 1 is a STYLE REFERENCE ONLY. Use its loose fountain-pen line quality,
transparent watercolor behavior, restrained palette, paper texture, and amount
of visual refinement. Do not reproduce its caliper subject or composition.

Create a square vocabulary-card illustration for “[WORD]” in the sense
“[TARGET SENSE]”. Do not show the word. Depict [ONE CONCRETE MEMORY SCENE]. Make
the meaning immediately understandable, with one clear focal subject or action
and only the supporting details needed to disambiguate it.

Draw on plain white or very lightly warm paper. Use human-drawn black
fountain-pen contours with varied pressure, slight searching/doubled lines,
occasional incomplete edges, and sparse cross-hatching. Add pale transparent
watercolor washes with uneven edges, small blooms, subtle pigment pooling,
dry-brush gaps, and generous untouched paper. Use black ink, muted cool
gray-blue, and at most one quiet warm accent.

Keep the composition square, balanced, upright, and level. Keep the complete
subject comfortably inside the frame. The result should feel designed and
readable but unmistakably hand made—not a polished technical rendering and not
a crude doodle.

No text, title, caption, letters, numbers, pseudo-writing, labels, annotations,
logos, signatures, or watermark. No drawn card border, photorealism, glossy
digital finish, thick marker outlines, flat vector fills, warped geometry,
dramatic lighting, clutter, or cropped subject.
```

## Choosing the memory scene

- Prefer a characteristic use over an isolated catalog pose: a caliper gently
  measuring a small metal cylinder is clearer than a caliper floating alone.
- For opposites or gradable adjectives, show one decisive physical contrast,
  not a collage of examples.
- For emotions and social qualities, show posture, gesture, distance, or an
  interaction whose meaning survives without facial detail.
- For verbs, freeze the instant that best distinguishes the action from nearby
  verbs.
- Use metaphor only when a literal observable scene cannot communicate the
  sense. Avoid stock icons such as lightbulbs, hearts, and floating punctuation.

## Existing-image prompt addition

When a second image supplies the subject, add:

```text
Image 2 is a SEMANTIC REFERENCE ONLY. Preserve the useful object/action and its
meaning, but create a new composition. Do not trace its layout, people, branding,
or distinctive decorative details.
```

## Acceptance checklist

- The target sense is understandable without reading a caption.
- The canvas is square, level, and not accidentally rotated.
- The focal subject is complete, plausible, and comfortably framed.
- The linework is delicate and human; the wash remains translucent and sparse.
- The page contains generous untouched paper and no decorative card border.
- There is no visible or pseudo-text anywhere in the image.
