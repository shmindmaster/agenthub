# Motion recipes

Timing and easing for moments a film keeps getting wrong. Frames are at 30 fps; ms in brackets. The kit's entrance vocabulary (`settle`, `fade`, `pop`, `rise`, `slide`, `wipe`, `bloom`, `draw`, `push`, `drift`, 5-frame stagger, `out`/`inOut`/`back` easing) lives in `kit/explainer/motion.mjs` and is not repeated here. Timing and easing ideas were studied from the Apache-2.0 video-shotcraft project and restated in our own words; no code or media was taken.

**Readability limit for every recipe.** Text stays on screen at least 1.2 s plus 0.25 s per word, and a result holds at least 30 frames. A recipe never shortens that. Reduced-motion or muted viewing: drop the recipe, show the end state, keep the hold.

| Recipe | Timing | Easing | Use for | Not for | Realized by |
| --- | --- | --- | --- | --- | --- |
| Lead-word enlarge | Key word 2x size 12 f (400 ms), settles to line size over 12 f, rest of line staggered 5 f | `out`, then `inOut` | A name or promise that must be read first | Lines longer than 6 words | not built (type is placed whole in `statement`) |
| Beat-locked hits | Three cuts 18-22 f apart, each on a spoken stress, then 45 f hold | hard cut | One ceremonial moment per film | Anything repeated; it stops landing | Hard cut between shots; cut points follow the cue sheet |
| Pre-punch push | 4 f small pull-back, 6 f push to 1.2-1.4x, hold 45 f | `inOut` | Pointing at one control in a capture | Dense UI where the crop cuts a row | `sourceRegion` per clip; no animated push yet, so not built |
| Freeze and mark | Capture frozen 45 f or more, outline drawn in 10 f, label rises 12 f | linear draw, `out` rise | Making the viewer look at one thing in a moving take | Short clips under 2 s | `render-overlay.mjs` dim-cutout on a held clip |
| Number roll | Count from 0 over 20 f, ring blooms 24 f, label rises 10 f later | `out` | One measured result | Ranges, percentages without a base | `NumberShot` in `kit/explainer/shots.tsx` (`kinetic-number`) |
| Before-to-after roll | Old value held 20 f, strikes through 8 f, new value counts 20 f | `out` | A figure that changed | Two unrelated numbers | not built |
| Rail light | Playhead sweeps the whole shot; each tick lights on its word, 8 f | linear sweep | Ordered steps | Fewer than three steps | `TimelineShot` (`timeline`) |
| Seam reveal | Seam wipes 20 f, left state desaturated, right lit | `inOut` | Two states, one difference | More than two states | `Contrast` (`before-after`, `comparison`) |
| Node-on-word | Node pops 12 f exactly on its spoken word; focus ring follows the voice | `back` | Mechanisms and flows | Words the voice never says | `Mechanism` (`diagram-build`, `process-flow`) with `at` anchors |
| Path trace | Path draws over 30 f or more from the anchor word | `inOut` | Cause leading to effect | Decorative lines | SVG `trace.path` in `kit/src/Visuals.tsx` |
| Checklist land | One item every 20-30 f on its word, drawn check 10 f | `out` | Steps to copy | More than five visible | `Checklist` (`checklist-build`) |
| Outcome hold | Last element lands, then at least 1.0 s (`RULES.minHoldSeconds`, `kit/explainer/grammar.mjs`) of nothing: no camera, no chrome change. A shorter hold is a warning in `build-explainer.mjs` and an advisory in `validate-explainer-release.mjs`, not an error. The brief's `finalHoldSeconds` is not read there: build a longer hold into the last shot's length, and `validate-finished-film.mjs` measures it on the encoded file | none | Every film ending | Never skip | grammar rule in `explainer-grammar.md`, enforced by `build-explainer.mjs` |

## Choosing

- One recipe per shot. Two competing moves read as noise.
- Match intensity to the format: ceremonial recipes (beat-locked hits, pre-punch push) at most once per film; lessons use rail, node and path recipes.
- Place the recipe on a spoken word, not on a timer. An anchor that finds no word fails the build.
- Sound for a hit: a short impact at the cut, nothing under the voice; leave silence on the reveal (`silenceOnReveal`).

## Not built, candidate work

Lead-word enlarge, pre-punch push and before-to-after roll are not built. Use the nearest built recipe (`statement`, `sourceRegion`, `kinetic-number` twice) until one is.
