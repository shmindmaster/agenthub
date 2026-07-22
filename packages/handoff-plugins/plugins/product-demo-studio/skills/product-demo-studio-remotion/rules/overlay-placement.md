---
name: overlay-placement
description: Placing on-screen text (headlines, callouts, captions) so it never covers the product state being shown
metadata:
  tags: overlay, occlusion, callout, headline, safe-area, captions
---

# Dynamic overlay placement

On-screen text must never hide the product state it's explaining. Never hand-guess a headline or
callout's `x`/`y` — derive it from the same capture-manifest geometry `product-demo-studio-capture`
recorded (focus rect, protected regions, cursor path).

## Resolve placement at scene-data prep time, not at render time

Run this once per scene, while assembling the composition's scene data (not inside the React
component, and not per-frame):

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/compute-overlay-placement.mjs" \
  --manifest <path-to-capture-manifest.json> \
  --canvas-width 1920 --canvas-height 1080 \
  --text-width 640 --text-height 160
```

It returns the safe region for that scene's overlay (or `null` if none exists), checking that the
candidate does not overlap:

- the focus rectangle,
- any protected region,
- the cursor's destination point (with a margin),
- the canvas edges (respecting a safe-area margin).

It tries a fixed preference order (upper-left → upper-right → lower-left → lower-right → a
dedicated title-safe strip) and returns the first region that clears all of the above with margin
to spare.

## When it returns `null`

Do not fall back to placing text over the product anyway. Instead, in priority order:

1. Use a dedicated title beat (a moment with no product on screen) for that text instead.
2. Move or re-crop the product frame to open a safe area.
3. Shorten the text until a candidate region fits.
4. Drop the visual headline for that scene — the narration and captions still carry the meaning.

## Aspect-ratio variants need their own placement, not a scaled copy

Re-run `compute-overlay-placement.mjs` per target aspect ratio (wide/vertical/square) with that
format's own canvas dimensions and, where the scene was recomposed rather than cropped, that
format's own capture-manifest focus rect. A safe region in the 16:9 cut is not automatically safe
once reframed to 9:16.

## Cross-check in QA

`product-demo-studio-qa`'s visual reviewer checks the rendered frame against the same
`compute-overlay-placement.mjs` output for that scene — if the two disagree (the text moved from
where the manifest said it was safe), that's a bug in the composition, not a false positive from
the reviewer.
