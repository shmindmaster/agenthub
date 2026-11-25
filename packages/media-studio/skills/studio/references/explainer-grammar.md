# Explainer shot grammar

Use these composition recipes when they serve the requested explanation. The timing, hero, motion and type-share targets are diagnostics. Give formulas, code, abstract graphics and deliberate silences the time and layout the viewer needs.

Read this before storyboarding any viewer-facing explainer, training film or briefing that is not a product screencast. It is the contract `kit/explainer/` renders and `kit/explainer/validate-explainer-release.mjs` enforces.

The short version: the old board was one document layout — kicker, title, subtitle, body — repeated for every scene. Twenty-two archetypes were declared and the renderer read one of them, so a storyboard could ask for `diagram-build` and still get the same slide. That is the "every beat a type-on-dark slide" failure `story.md` already forbids. This grammar gives every declared archetype a composition, and gives every shot one hero and one light.

Measured on the reference film that set this bar: a weak cut and a strong cut had almost the same amount of motion (0.47 vs 0.56 mean frame change, 72 vs 76 events per minute). The difference was composition — median hero height 172 px vs 219 px, time spent with the hero under 110 px 29% vs 12%, and no halo/sweep/ghost at all in the weak cut. More animation would not have fixed it. Bigger, lit, better-arranged subjects did.

## The five rules

1. **One hero per shot.** The thing the line is about. It is the largest object, it is lit, and it enters on the first or second beat.
2. **One light.** Only the hero glows. Supporting elements never do. When focus moves, the previous glow dies over 8 frames.
3. **One verb action.** Something the line names keeps moving while the line is spoken: a path drawing, a queue compressing, a counter running, an edge landing. Do not add floating or breathing to a static object to move a metric — if the verb has no motion, let it be still.
4. **One hold.** After the last beat lands, hold at least 30 frames (1.0 s) before the cut. No new elements, no camera, no chrome change during the hold.
5. **Hard cuts only.** Do not animate exits. The next shot's entrance is the transition.

## Size tiers

Sizes are fractions of frame height, so they hold at 1600×1000, 1920×1080 and 1280×720.

| Tier | Height | Example | Rule |
| --- | --- | --- | --- |
| Hero | ≥ 23.6% of frame height (236 px at 1600×1000), or type ≥ 11% of height | a 110 px icon with its label reads as the subject; a 150 px headline word; a 300 px number | One per shot. Always lit. Enters by beat 2. |
| Supporting | 8–13% of height (80–130 px) | rows, cards, secondary numbers, diagram nodes | At most four per shot. Never lit. |
| Label | 2.2–3.2% of height (22–32 px) | kickers, source lines, node labels | At most six per shot. |

A subject that is naturally small — a timeline, a formula, a table, a pipeline — must be paired with a hero: a big number, a magnified current row, or a lit focus ring on the current item. A 6 px timeline with 34 px labels standing alone for three seconds is a defect, not a diagram.

**Empty frame.** A hero under 15.3% of frame height for more than 45 frames (1.5 s) is a medium finding; under 11.1% is high. This is the measurable form of "underwhelming".

## Composition families

Every archetype in `kit/scene-archetypes.json` maps to a family in `kit/explainer/grammar.mjs`. The family owns the layout; the archetype is the editorial name the storyboard uses. Four archetypes are polyglot — the catalogue lets them carry more than one visual kind — and for those the kind picks the family: `diagram-build` + `layers` is the layer stack, `cold-open` + a b-roll or still is the media frame, `talking-head-sidecar` + `sidecar` is the evidence frame. Everything else has one family, whatever the visual.

| Family | Archetypes | Composition | Tier |
| --- | --- | --- | --- |
| `statement` | cold-open, kinetic-statement, hero-reveal, lower-third | Type is the picture. Left-aligned, vertically centred, no kicker row, no rule, no scene number. | XL |
| `number` | kinetic-number | One number owns the frame: 300–360 px, tabular, accent, label beneath, halo behind. Counts up over 20 frames. | XL |
| `contrast` | before-after, comparison | A vertical seam wipes in; the left state is desaturated, the right is lit. Two states, one difference. | L |
| `mechanism` | diagram-build (flow, diagram or map visual), process-flow, drawn-mechanism | The diagram bleeds: nodes and arrows fill the frame, each landing on its word, a focus ring moving with the voice. | L |
| `layers` | diagram-build + `layers` visual | A stack rises; the active layer lifts and takes the light. | L |
| `timeline` | timeline | One horizontal rail with the dates evenly spaced, each event landing on its word, the current one lit, and a playhead that reaches each event as it is spoken. | L |
| `evidence` | evidence-proof, speaker-slide, data-chart, talking-head-sidecar + `sidecar` | Claim above at 52–64 px, evidence large below, source in the footer at 22 px. A hairline ties claim to evidence. | M |
| `quote` | quote-problem | One sentence, 64–88 px, no furniture; an oversized quote glyph at 12% opacity; attribution small and low. | L |
| `checklist` | checklist-build | Items land one at a time with a drawn check; a dot rail shows progress. Five visible at most. | M |
| `media` | full-bleed-broll, screen-in-context, cold-open + a b-roll or still | The picture bleeds; text lives in a bottom scrim, never on a card. | XL |
| `sting` | motion-sting | A mark, a beat of motion, gone. | XL |
| `chapter` | chapter-card | Number ghosted at 18%, label at 96 px, rule wipes in. Two seconds. | XL |
| `end` | cta-end-frame | One call to action at 84–112 px, one line under it, nothing else. | XL |

The film-level guards in `grammar.mjs`:

- a shot is 1.5–12 s; longer needs `longShotReason`;
- no two consecutive shots share a family unless `repeatIsPoint`;
- type-only families (`statement`, `quote`, `number`) are at most 35% of shots, and a shot in one of them may not carry a visual: the family draws with type alone, so a visual it cannot compose is refused at build time rather than dropped at render time;
- every chapter contains at least one L or XL shot;
- a film over three minutes needs chapters of 45 s or more.

## Set pieces

At most one per chapter, and it is the chapter's thesis, the hero's debut or the closing payoff. A set piece is choreographed, not decorated: at least 90 frames, a clear frame, an entrance the rest of the film does not use, and one held conclusion. A normal shot with an icon and a line is not a set piece.

The ending is a set piece that reframes the opening, not a caption. In the reference, the weak ending was the smallest, dimmest frame in the film; the strong one returned to the opening metaphor at 260 px with a drawn ring.

## Chapters

- Under 3 minutes: one chapter, no chapter cards.
- 3–5 minutes: three or four chapters, each at least 45 s (the reference asks 60 s).
- 5–8 minutes: four to six chapters.
- A chapter opens with a `chapter` shot and then a shot that continues the previous chapter's subject where possible. A chapter that starts cold on a wholly new picture reads as a new film.

## From a line to a shot

`story/explainer-plan.json`:

```json
{
  "film": { "id": "revision-drift", "title": "One revision, three broken commitments", "backdrop": "dots" },
  "chapters": [
    { "id": "c1", "label": "The break", "shots": ["S01", "S02", "S03"] },
    { "id": "c2", "label": "The repair", "shots": ["S04", "S05", "S06"] }
  ],
  "shots": [
    {
      "id": "S02",
      "archetype": "diagram-build",
      "kicker": "THE BREAK",
      "title": "Three commitments break at once.",
      "visual": {
        "kind": "flow",
        "nodes": [
          { "label": "Revision", "at": 0.8 },
          { "label": "Plan", "at": 1.9 },
          { "label": "Commitments", "at": 2.9, "mark": "risk" }
        ]
      }
    }
  ]
}
```

- The shot `id` **is** the cue id. One cue, one shot, in cue order; chapters partition the film in that order.
- `title` is the line the shot is about, not the narration repeated. It is what the viewer reads if they watch on mute.
- `at` is seconds from the shot start, or an anchor: `@word`, `@word#2`, `@word+0.3`. Anchors resolve against the accepted take's word boundaries; an anchor that finds no word fails the build and never guesses.
- A timeline event prints its `at` as the date, so its time goes in `beat`: `{ "at": "Week 3", "label": "Run side by side", "beat": "@three" }`.
- The last beat must land at least 1.0 s before the shot ends. `build-explainer.mjs` refuses a film that lands and cuts.
- Themes, accents and visual payloads come from `kit/explainer/theme.json` and the existing `Visual` union in `kit/src/Visuals.tsx`. Do not invent a second content model.

### Openings and size

Every shot opens on its own furniture. The kicker, the title and the outline of what is coming (dashed boxes, dim dates, empty check boxes, bar labels, the number's ring) are on screen from the first tenths of a second, whatever the first spoken beat is. An item still lands on its word. Do not add a fake early beat to avoid an empty frame.

Pictures fill their region by calculation, not by hand. `kit/explainer/fit.mjs` works out how large each body, title, list and rail can be drawn, and the renderer uses the same numbers. `visualScale` below 1 makes a body smaller; above 1 it does nothing, because a larger body would leave its region.

`build-explainer.mjs` checks the layout of every shot before any render:

- `layout-overflow` (refused): a title, headline, list, table or diagram does not fit even at its smallest size. Shorten it or split the shot.
- `diagram-...` (refused): an unknown icon, an arrow that names no box, two boxes in one cell, words that do not fit their box, an arrow with no clear path, or an arrow label that covers something.
- `layout-small` (advice): the smallest type in the picture is under 22 px on a 1000 px high frame.

### Linked diagrams

Use `diagram` when the relation between parts is not a straight line: things that join, split, loop or report back.

```json
{ "kind": "diagram",
  "nodes": [
    { "id": "sky", "label": "Weather", "icon": "cloud-sun", "col": 0, "row": 0, "at": "@weather" },
    { "id": "orders", "label": "Orders", "icon": "clipboard-list", "col": 0, "row": 1, "at": "@orders" },
    { "id": "fc", "label": "Forecast", "icon": "chart-line", "col": 1, "row": 0, "at": "@forecast", "mark": "emphasis" }
  ],
  "edges": [ { "from": "sky", "to": "fc" }, { "from": "orders", "to": "fc", "label": "by noon", "dashed": true } ] }
```

`col` and `row` start at 0 and place a box on the grid. An arrow names its ends by `id`, is routed round the other boxes, and draws as its target lands unless it has its own `at`. `icon` is a name from `kit/explainer/icons.json` (204 Lucide icons, ISC); a wrong name is refused with the closest ones. A `flow` is drawn the same way in reading order.

### Choosing the family

Choose by the **visual relation**, not by the topic:

| The line does this | Family | Hero |
| --- | --- | --- |
| Names one idea and stops | `statement` | the headline word |
| Gives a magnitude | `number` | the number |
| Compares two states | `contrast` | the changed side |
| Shows how something works | `mechanism` | the node being spoken |
| Shows hierarchy or depth | `layers` (`diagram-build` + a `layers` visual) | the active layer |
| Orders events | `timeline` | the current tick, magnified |
| Proves a claim | `evidence` | the evidence object |
| States a false belief | `quote` | one sentence |
| Lists what to check | `checklist` | the item being spoken |
| Shows the real thing | `media` | the captured frame |
| Marks a movement | `chapter` | the chapter number |
| Asks for one action | `end` | the call to action |

Two shots with the same family next to each other must have `repeatIsPoint: true`, and a continued diagram should use `revealFrom` rather than two shots.

## The diagnostic ladder

When a cut feels weak, measure in this order before adding anything:

1. **Median hero height.** Under 23.6% of frame height means the subject is too small.
2. **Share of time with the hero under 15.3%.** Over ~12% of the film is the "sparse, drifting" feel.
3. **Is the hero lit?** A white outline on black with no glow is not a hero.
4. **Set-piece choreography.** Is the most important moment given the same grammar as an ordinary beat?
5. **Background debris.** Ambient mini-icons shrink the perceived hero. If you need "many", use a regular matrix that lights on the beat.
6. **Ending scale.** If the payoff is the smallest frame in the film, the film has no ending.

Motion quantity is not on this list. Adding animation to a badly composed frame makes a busy weak frame.

## Gates

```powershell
node <package>/kit/explainer/build-explainer.mjs <jobRoot> --cue-sheet story/cue-sheet.json
node <kit>/explainer/still-explainer.mjs <jobRoot>            # on the render box, before the film: one sheet of openings and holds
node <package>/kit/explainer/measure-explainer-frames.mjs --props <jobRoot>/picture/explainer-props.json --frames <jobRoot>/frames --encoded <candidate.mp4>
node <package>/kit/explainer/validate-explainer-release.mjs <jobRoot> --encoded <candidate.mp4> --require-metrics
```

`still-explainer.mjs` draws single frames without rendering the film: `--at open,beats,hold`, `--shots S02,S03`, `--public-dir`. It writes `sheet.png` and `stills.json`; a frame caught while something is entering is framed red and listed, so a half-drawn word is not read as a defect. It needs the kit's own install, so it runs on the render lane (`render-lanes.md`).

Remotion downloads the headless browser pinned to its own version. A film rendered on two hosts is frame-identical only when both use that browser and the same fonts, so do not point Remotion at another Chrome.

The explainer uses the same narration cue sheet as `build-picture.mjs`: `{ totalSeconds, cues: [{ id, start, end, gapAfter, text }] }`. The product action EDL generated by `build-cue-sheet.mjs` serves a different purpose. Export all candidate frames at native size in order starting at 1, and pass that exact candidate to measurement and release.

The release validator checks renderable inputs, exact cue and frame coverage, the shot and chapter clock, encoded duration and receipt binding. Composition and pacing metrics direct the encoded review. Keep purposeful reading or thinking time where it serves the explanation.


## What this is not

- Not a second content model. `kit/src/Visuals.tsx` and `kit/src/Diagram.tsx` still draw the diagrams, charts, code and tables.
- Not a caption system. Captions stay a sidecar `.srt`; nothing is burned into the picture.
- Not a licence to copy the reference implementation. Anything2Explainer is PolyForm Noncommercial; this is an independent implementation of a published method, with its own code, tokens and sample fixture.
- Use real product capture as proof of verified current behavior (`product-picture.md`). Use designed diagrams, illustrative UI and simulations where they help explain the product, with visible context when needed.
