# Scenes

Storyboard, art-direct and direct a film from the locked screenplay. Decide; never offer a menu.

Contents: Cue sheet, Storyboard, Visual bible, Direction, Studio craft, Scene archetypes, Picking the renderer, Hero shots.

## Cue sheet

The cheap gate before any render. One line per beat:

`S04 | "One bad approval hides in the batch." | dense queue | filter to Exceptions | twelve rows remain | match-cut, chaos to order`

Fields: beat, narration line, screen, action, result, transition. Rewrite a line when the screen names a topic, the result would not read on mute, it holds two actions, or the transition has no reason.

After voice lock, carry lines into `story/cue-plan.json` `beats.<id>` (`actions`, `result`, `expectedState`, `camera`, `transition`). `scripts/build-cue-sheet.mjs <jobRoot>` writes `plan/cue-sheet.json`; rerun after compose with `--compose-map output/<base>-compose-map.json`.

## Storyboard

Needs `story/screenplay.json` and `qa/narration-check.json` with `ok: true`; a missing `hook`, `sceneRole` or `wiifm` goes back to the script. Writes `story/storyboard.json` per `schemas/storyboard.schema.json` (required: `title`, `chosenHook`, `beats`).

**Scored hook.** Write 2 or 3 hook and visual pairs. Score 0 to 100: pain on screen inside five seconds (two for a marketing cut), a picture that is not a title card, WIIFM, truth. `chosenHook` takes `id`, `narration`, `visualArchetype`, `score`, `why`; `rejectedHooks`, at most 2, add `whyRejected`.

**Beats.** Required: `id`, `order`, `sceneRole`, `narration`, `visualArchetype`, `shotPlan` (`framing`, `subject`, `movement`, `focalPoint`), `rhythm` (`energy`, `pauseBefore`, `holdAfter`, `visualRefreshTarget`), `sound` (`musicCue`). Also set `transition` (`type`, `semanticReason`), `visualMode` (omitted means `screen` on `product-screencast`), `eyePath`, `startState`, `expectedState`, `provesClaim`, `onScreen`, `emphasis`, `truth`.

1. Picture first; name the result after it appears. Software beats: screen, control, action, visible response, with `startState` unlike `expectedState`.
2. One `eyePath` per screen or guided beat. Two moves is two beats.
3. Exactly one `heroMoment: true`, named by `protectedHeroBeatId`, with `musicCue: silence` or `silenceOnReveal: true`.
4. No archetype on consecutive beats unless the repeat is the point (checklist, diagram continued with `revealFrom`).
5. `onScreen` is 4 words at most and never repeats the voice. Never a build chip, version chip, environment badge or revision label.
6. Disclose synthetic data with `syntheticDisclosure` `mode` caption or end-card, never spoken.
7. `programForm: technical-story`: code, log and cross-system beats name their markup (box, dim, arrow, label, flow) and one highlight. A flow beat precedes the code reveal.
8. Marketing cut: cuts on the bed's tempo, brand end card with one CTA in the last eight seconds.

**`scripts/validate-storyboard.mjs`** reads the episode form only (`episodeId`, `segments[]`). A `beats` file fails it; check `beats` against the schema. On episodes it requires exactly one each of first-segment `coldOpen` (no "welcome to" or login opening), `heroMoment`, `payoff` at an outcome or identity rung, `endCard`, `guardrail`; `beforeState` of 3 to 5 s; order before, hero, payoff; `attentionReset` on a gap over 15 s; two annotations at most; `cursorLeadSeconds` up to 1.5; result visible before it is spoken; `cursorMoveMs` 400 to 600; clicks with 250 ms settle, 500 ms hold, 300 to 400 ms `radial-pulse`; `snap-to-region` 300 to 500 ms, no zoom drift; waits cut or ramped 4x to 8x; text entry chunked or ramped 3x to 4x.

## Visual bible

Write `visual-bible.json` per `schemas/visual-bible.schema.json`: `jobTitle`, `motif`, `lighting`, `typography`, `compositionRules`, `graphicalLanguage`, `motionTreatment`, `texture`, `continuity`, `brollPlan`.

- `motif` is specific to this job: `dense queue collapsing to twelve exceptions`, not `dark slides, yellow type`.
- `brollPlan` rows: `beatId`, `intent` (problem, outcome, context, proof, texture), `subject`, `prompt`, and `refuse`: what the plate must not invent (product UI, metrics, testimonials).
- `imagePrompts` rows: `id`, `prompt`, `reference` (the style anchor).

Name the beat's job or cut the visual:

| Job | Asset | Refuse |
| --- | --- | --- |
| The thing | Captured WebM (`capture`) | Generated UI, even a "quick mock" |
| The structure | Diagram build | Labels you cannot defend |
| The proof | Chart, annotated capture | A number not in `story/fact-lock.json` |
| People, context | Generated still of the viewer's world | A generated real person, customer or colleague |

No robot hands, glowing brains or sparkle for a capability.

**Stills.** Reuse accepted plates. Otherwise Azure `gpt-image-2.5-flare` through `generate`, low quality to explore, medium to finish. Prompt in order: environment; subject and action; material detail and wear; framing, lens, lighting, negative space for type; the bible's style block verbatim; `no watermark, no extra text, no logos or trademarks, no identifiable real individuals`. For realism say `photorealistic` and `honest and unposed`. Change one thing per iteration. Sizes are multiples of 16: request 1600x1008, crop to 1600x1000. Logos, legal text and numbers are compositor type.

**Consistency.** Lock one style block. Make one anchor, set it as `reference`, and make variants through image edits, restating the preserve list each time. Redraw only off-family plates. One accent, one type ramp, one card language.

## Direction

Prefer the **simplest truthful visual that maintains attention**. A cheaper still held across two ideas is unfinished.

| `visualMode` | When |
| --- | --- |
| `screen` | Claim about a running product or terminal |
| `slide` | Type-led argument, no product |
| `diagram` | Structure or flow: Mermaid, D2, SVG |
| `talking-head` | A face must carry the line |
| `motif`, `broll` | Problem, outcome or context, never product UI |
| `animation` | Motion itself teaches |
| `narration-only` | A visual would only decorate |

Nothing moves that the line is not about.

Write `direction.json` keyed by beat id: visual mode, archetype, on-screen copy, highlight, action, `eyePath`, register, duration, sound, holds, overlay (`boxes`, `arrows`, `notes`, `dim` per `kit/screencast/render-overlay.mjs`).

**Eye path.** `start` is the last beat's rest; `move` is one move to what the line names; `rest` holds 1.5 s or more, cursor still. `validate-pointer-path.mjs` defaults: zero reversals, zero scroll returns, travel up to 1.35 times direct, zero unnamed moves; loosening needs `pointer` with `reason`. On `screen`, go wide, punch in on the control, hold through the response. Static scenes: a highlight lands on each element as named. Type-led scenes: no fake cursor.

**Register.** Per beat, a style the cast voice supports (`StyleList`), never "sound excited". Change it on the payoff.

**Sound cues.** Default `bed`, `silence` on the hero hold. `sfxCue` is a sting from an accepted asset, a Recast click on `screen`, otherwise silence.

**J-cuts and L-cuts.** J: the next beat's voice starts before its picture. L: the voice runs over the next picture. Note it in `transition.semanticReason`. `screen` beats take L-cuts only: `validate-sync.mjs` wants the screen up before the first content word, at most 40 ms late.

**Emphasis.** `emphasis` is one word or short phrase, matched in the picture by a build, punch-in or hold.

## Studio craft

1. Coverage, not one locked frame. Change the picture when the idea changes.
2. Hard cuts by default; one transition language.
3. Slow push on the before-state; hold on the reveal.
4. Texture over void. The motif returns.
5. No Ken Burns on a screenshot or type. `Inspect-MediaVisualQuality.ps1` flags it, and static runs of 6 s or more.
6. Composition: everything serves `focalPoint`; first and last frames are designed; lower-thirds keep headroom.

Sound: voice is the anchor. The bed is ducked, felt not heard (`Finish-Media.ps1 -Speech -Music`), never wall-to-wall under a hero. Stings are sparse; `silenceOnReveal` is true quiet. Hold pauses in the edit, never pad TTS.

## Scene archetypes

Ids from `kit/scene-archetypes.json`, rendered by composition `Briefing`.

| Id | Use when |
| --- | --- |
| `cold-open` | First seconds, image before context |
| `full-bleed-broll` | Problem, outcome or place |
| `kinetic-statement` | One sentence is the picture |
| `kinetic-number` | One number to remember |
| `before-after` | Old way against new |
| `comparison` | Two options, two costs |
| `diagram-build` | Structure arriving in order |
| `timeline` | Sequence over time |
| `process-flow` | Request path, pipeline |
| `screen-in-context` | Real capture in a designed frame |
| `talking-head-sidecar` | Face plus one claim |
| `quote-problem` | The viewer's objection; `speaker` makes it a question card |
| `evidence-proof` | Cited fact, table, code |
| `checklist-build` | Steps the viewer will steal |
| `hero-reveal` | The one protected payoff |
| `cta-end-frame` | Last frame, one next step |
| `chapter-card` | Section break |
| `lower-third` | Speaker identification |
| `speaker-slide` | Face plus a slide |

## Dialogue and simulated calls

A two-party call, interview or rehearsal is one scene per turn on `Briefing`. The kicker names the speaker and the accent colour changes with the speaker. The body shows the thing under discussion, never the speaker alone: `timeline` for dates and deadlines, `stat` for one number, `table` for status, `checklist` for commitments, `flow` for who does what, `proof` for the named document. Give each item an `at` (seconds from scene start) from the synthesizer's own word clock so it appears as the word is spoken. Set `visualScale` (about 1.4 to 1.9) on short bodies so they fill the frame; keep `flow` near 1.4 so three nodes stay on one row. Run `scripts/check_picture_relevance.py <props> <cue-sheet>` before rendering.

Remotion's mp4 carries a silent audio track, and ffmpeg prefers it. Mux with `-map 0:v:0 -map 1:a:0`, or the loudness finish measures silence and fails with `measured_I -inf`.

## Picking the renderer

One per job. Remotion for typed React, parametrised templates and the archetype kit: use its official agent skills (`remotion-dev/skills`), do not restate their rules. HyperFrames for HTML with a paused GSAP timeline, when the job names it. Product UI is captured WebM, neither.

## Hero shots with generative video

Approved hero shots only. Never a product screenshot, not even "to add motion". Higgsfield and Runway credits are frozen unless the owner approves.

Veo 3.1 prompt, in order: camera work; subject and action, with up to three reference images for identity; setting and light from the bible; dialogue and audio inside the prompt. For a transition, give first and last frame.
