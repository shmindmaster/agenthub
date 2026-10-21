# Direction (visual choice, eye path, performance)

Step 4 of the crew in `SKILL.md`. Translate the locked storyboard into what appears and how it is performed. Decide in this turn; do not present a menu of visual styles. You do not capture, generate, or release.

Read with this step: `engagement.md`, `cursor-flow.md` and `scene-archetypes.md`, unless kind is `product-screencast` (Recast + `product-picture.md` + `cursor-flow.md`). When `programForm` is `technical-story`, read `technical-story.md`: the markup rules there are yours to direct per beat. Marketing cuts also read `marketing-readiness.md`.

Requires `story/storyboard.json` and `visual-bible.json` on viewer-facing jobs. If they are missing, remit to `storyboard.md` / `visuals.md`.

## 1. Visual choice

Prefer the **simplest truthful visual that maintains attention**. A cheaper still that holds across two ideas fails.

| Mode | When |
| --- | --- |
| `screen` | Claim is about a live product — `media-studio-capture` (WebM + Recast). Default on `product-screencast`. |
| `slide` / archetype kit | Type-led argument with **no** product to show — pick an archetype, not "the briefing slide" |
| `diagram` | Structure or flow (Mermaid/D2/SVG, not diffusion) |
| `talking-head` | Face must carry the line |
| `motif` / `broll` | Problem, outcome, or context — not product UI |
| `animation` | Motion itself teaches; Remotion |
| `narration-only` | A visual would decorate |

A slide or diagram that does not build across the line is a still. Call a build, a cut, Motif, or B-roll rather than holding it for a second idea.

Do not use the same `visualArchetype` twice in succession unless the storyboard marked the repeat intentional.

Nothing on screen moves that the narration is not about. No build chip, version chip, environment badge or revision label is ever in frame; if the product shows one, frame it out or dim it.

## 2. The eye path: start, the one move, rest

Every scene is directed as one flow for the eye (`cursor-flow.md`). Write `eyePath` per beat into `direction.json`:

- `start` — where the eye already is (the previous beat's rest).
- `move` — **the one move** this beat makes, in one direction, to the thing the line names. Not two targets. Not a look around. If the line names two things, split the beat.
- `rest` — where the eye holds while the result is named, ≥ 1.5 s, cursor still.

For `screen` scenes, specify target, pointer lead → action → visible feedback → result hold (`product-picture.md`). Recast owns cursor, ripple, punch-in. Wide → punch-in on the control → hold through the native response. Config beat before the run it causes. The pointer never flicks, never goes up and down, never scrolls past and returns, never moves while nothing is being named; `validate-pointer-path.mjs` measures the take against this plan and the default allowance is zero reversals.

For static scenes (dashboards, diagrams, architecture) the guided cursor or highlight lands on the exact element as it is named and then the next one; never a sweep, never a held frame.

For type-led scenes, emphasis is type color, Remotion build-in, and hold time, not a fake cursor.

Technical stories mark up aggressively, on top of Recast: box the element that matters, dim the rest, arrow cause → effect, zoom, and label with the story vocabulary (`User action`, `Webhook`, `DB write`, `Async job`). When the beat crosses systems, put a tiny flow diagram on screen before the code. Write each beat's overlay spec (`boxes`, `arrows`, `notes`, `dim`) into `direction.json`; `media-studio-compose` renders it with `kit/screencast/render-overlay.mjs` and applies it through the manifest `overlay` hint. Code reveals are `render-code.mjs` cards: the 5–20 lines that matter, one highlight band per card, the commit named. Every visual change is motivated by the story; never add one to fill a quiet stretch.

## 3. Performance and sound

Owner voice: name the style-bank register (`explaining`, `firm`, `serious`, …). Do not write free-text "sound excited" for that speaker.

Honor storyboard `sound` (`musicCue`, `sfxCue`, `silenceOnReveal`, `transitionAudio`). Viewer-facing default is `bed` with `silence` on the hero hold. Marketing cuts: the bed carries the pace, cuts land on its grid, at least one designed cue (riser, hit, sting), end card from the brand kit with one CTA inside the last eight seconds (`marketing-readiness.md`).

## 4. Output

`direction.json` keyed by beat id: visualMode, visualArchetype, on-screen copy, highlight, action, `eyePath`, register, duration, sound, pause/hold. Then `media-studio-generate`.

## 5. Final check

- [ ] Every beat has one `eyePath` (start, the one move, rest); no beat asks the eye to go back
- [ ] Archetypes vary; no accidental consecutive repeat
- [ ] Nothing in frame moves that the line is not about; no build or version chip
- [ ] Hero has silence or a ducked rest
- [ ] Register named per beat
- [ ] Next skill is `media-studio-generate`

## 6. Technical ideas: which visual (decision rules)

For a technical idea, failure or design choice, decide the **simplest truthful visual that maintains attention**. A cheaper still that holds across two ideas is unfinished, not simpler. Walk the list:

```text
actual screen?
terminal?
Slack/UI chrome (synthetic)?
architecture diagram?
sequence diagram?
animated flow?
code?
graph?
avatar?
nothing — narration enough?
```

Decision rules:

1. Prefer real captured UI/terminal when the claim is about product behavior.
2. Prefer diagrams when the claim is about structure or flow.
3. Prefer animation only when motion itself teaches (ordering, fan-out, failure propagation).
4. Prefer narration-only when a visual would decorate without teaching.
5. If the output is a film, a visual that never changes across a scene is unfinished, not cheaper. Builds, cuts, and motion that teach are not decoration; film craft lives in `engagement.md`.
6. Route composition through `media-studio-compose`. Remotion is capability `video.programmatic-composition` (official `remotion-dev/skills`), never vendored here. Mermaid/D2 for static diagrams. Product-UI truth still captures through `media-studio-capture` (Playwright WebM + Recast in `packages/media-studio`). Do not load retired `product-demo*` skills.

Record the decision per beat:

```yaml
visual:
  mode: screen|terminal|diagram|animation|narration
  why: <one sentence>
  provider_hint: capture|mermaid|d2|remotion|none
  truth: FACT|DRAMATIZED|COMPOSITE
```

(`mode` maps onto the §1 `visualMode` table: `terminal` is a captured `screen`; `narration` is `narration-only`.)

## 7. Series technical beats

Choosing capture vs diagram vs animation for a **series** technical beat. You do not generate media or skip the crew in `SKILL.md`.

1. Comprehension first: the explanation block (`story-craft.md` → "Explainer path"; `../../../schemas/explanation.schema.json`).
2. `story-craft.md` for tension / reveal; do not flatten to Core Idea → Takeaway slides.
3. `technical-story.md` when the beat is a product or engineering change: hook on the problem, flow overlay, code reveal of the 5–20 lines that matter, before/after, replay, what it means. Its markup rules (box, dim, arrow, label, flow) apply to the series beat too. A running product as the picture also reads `product-picture.md` — WebM + Recast, not Ken Burns stills.
4. Then hand the locked explanation to the crew. If the picture is a running product, kind is `product-screencast`, not a Remotion `series-episode` slide stack. Writer → storyboard → visuals → direction.

Do not jump explainer → Remotion. The storyboard owns shot plan, archetype, and sound.

Picture: prefer Playwright / `media-studio-capture` + Recast when the claim is a running product (`product-picture.md`). Prefer diagram **build** (overlay on the product, or ≤8s cutaway) when the claim is structure. Prefer Motif / Remotion only when motion itself teaches — never Motif a product screenshot. Simplest truthful visual that **maintains attention**; a still held across two ideas is unfinished.

Final check for a series technical beat:

- [ ] Truth tag on the beat
- [ ] Next step is `storyboard.md`, not a slide dump
- [ ] Live UI is capture, not diffusion
