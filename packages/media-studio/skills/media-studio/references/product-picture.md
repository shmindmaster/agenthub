# Product picture

Single home for “the product is the picture.” Skills point here; they do not restate this table.

Applies when `job.kind` is `product-screencast`, when `programForm` defaults to that kind (`program-forms.md`), or when a beat is `visualMode: screen`. A running product as the subject wins over “briefing”, “tutorial”, “walkthrough”, or “explainer.” If nothing on screen can act, the job is a `briefing` — do not label frozen screens a screencast.

Validators, both fail closed:

| Gate | Runs | Proves |
| --- | --- | --- |
| `scripts/validate-product-picture.mjs <jobRoot>` | `compose-screencast.mjs` runs it first and refuses to compose if it cannot find it | Every screen beat maps to a real clip on disk (ffprobe) that `kit/screencast/record-job.mjs` recorded from a live Playwright session: `capture/receipt.json` binds the clip's sha256 to pointer motion, actions, observed product responses and Recast status. No receipt, no pointer motion, a still, a re-encoded plate, a Recast fallback nobody accepted, or a clip that would be frozen more than 2 s to reach the narration length all fail. `intent: draft` relaxes only the Recast requirement. |
| `scripts/validate-encoded-picture.mjs <jobRoot> <candidate.mp4>` | QA, on the exact encoded candidate | Every encoded screen segment perceptually matches a frame of its receipt-bound clip (dHash); no run of near-identical frames longer than 6 s inside a screen beat (a beat may declare `resultHoldSeconds` ≤ 8); cards ≤ 8 s; ≥70% screen; designed first and last frames. Writes `qa/encoded-picture.json` bound to the candidate's sha256. |

Capture is `kit/screencast/record-job.mjs <jobRoot>` driving `<jobRoot>/capture/scenes.mjs` through the helpers in `record-lib.mjs` (`go`, `approach`, `click`, `typeText`, `pointAt`, `hoverHold`, `smoothScroll`, `expect`, `hold`). Every helper call is logged to the receipt; `h.expect(locator, label)` is the proof that the product responded. Takes recorded by an older recorder can be bound after the fact with `scripts/backfill-capture-receipt.mjs` from their Playwright trace; that receipt is marked `trace-backfill` and is accepted with a warning, not silently.

## Beat grammar

One action per beat:

`start → locator → pointer lead → action → visible product response → result hold`

Recast owns cursor approach, click ripple, punch-in zoom. Timing numbers live in the PDS killer-demo guide (eased pointer 400–600 ms, settle ≥250 ms, click pulse 300–400 ms, hold ≥500 ms, one snap-to-region 300–500 ms per beat, no `zoom.drift`). Do not copy those numbers here.

The compositor overlay (`render-overlay.mjs`) owns dim / box / arrow / label / flow. They stack; neither replaces the other. Native hover/focus/loading/toast is the proof the action worked — do not cover it with a fake cursor or a title card.

A `hold` is the last frame of the preceding WebM, or a storyboard-declared result hold on that video. It is not a PNG still and not `interaction.kind: none` posing as the picture.

## End-to-end demonstration

The picture **proves** the workflow. A muted viewer must still follow:

`start → control → configure/act → system response → UI change → outcome`

Do not cut start → result. Keep the states that cause the outcome (hover, menu, input, save, loading, notification, data update).

- **Cause on screen.** If a model, connector, permission, trigger, prompt, source, or flag drives later behavior, show it being set in this session, then the run, then the result. VO is not proof.
- **Right screen.** The frame contains the thing being said. Same-product chrome, a pretty dashboard, or the wrong settings page fails.
- **Operate.** Pointer lead → hover → click → native response. Recast owns cursor/ripple/punch-in. Native loading/toast is the proof. Every shot establishes context, shows an action, exposes config, shows system behavior, or proves an outcome — else cut it.
- **Frame.** Wide to establish → punch-in on the control → hold through the response → pull back when context is needed. One snap-to-region per beat. Readable labels and results; dense UI is a zoom.
- **One session.** Same user, workspace, selections, and data unless the flow changes them. Setup and runtime: configure → save → initiate → execute → response → result.
- **Sync.** Picture matches the current sentence. Name the result after it appears. Holds cover the wait; Local-AI speaks the locked script and does not rewrite it.

Scene: `context → correct screen → control → action → visible response → hold on the change → next`.

**Mute test** (every software scene, before encode): right screen, readable UI, action visible, response visible, driving config shown, intermediates kept, framing on the change, cursor intentional, VO in sync, states connect. Any no → recut.

## Allowed picture

| Beat | Picture | Forbidden |
| --- | --- | --- |
| Workflow, config, result | Playwright WebM + Recast | PNG still, Ken Burns / scale-pan on UI, Motif/I2V of a screenshot |
| Code | Product first, then overlay or a 5–20 line `render-code.mjs` card, then product result | A 40s+ Remotion code slide as the main picture |
| Flow / diagram | Overlay on the product, or ≤8s cutaway, then back | A chapter of slides between two screenshots |
| Title / CTA / Q card | Remotion card, ≤8s each | Auto-card filling a missing screen clip; a 40s card on a screencast |
| Diagnostic PNG | Poster, contact sheet, capture-plan note | The encoded picture of a `screen` beat |

Missing `visualMode` on a `product-screencast` beat **defaults to `screen`**, not `slide`.

## Ratio

≥70% of timeline duration is `visualMode: screen` with a `.webm` / `.mp4` clip. The rest may be cards, overlays, and code reveals. Below 70%, compose fails.

## Capture plan

`story/capture-plan.json` matches `schemas/capture-plan.schema.json`. Every `interaction` row names `locator`, `action`, `expectedResult`, `startState`, `resultState`, `provesClaim`, and a video `clip` (source WebM). `startState` and `resultState` must differ — that is the visible change. `provesClaim` is the narration claim this take proves on screen. `causalRole` (`start` | `configuration` | `action` | `system-response` | `result`) and `dependsOnSceneId` connect setup to runtime. Keep the Playwright `trace` as metadata; do not encode trace JPEGs. `plateName: *.png` is not a capture for an interaction or hold row. `hold` is not a substitute for interaction on a workflow beat.

## Gates that must not pass a stills-and-slides cut

- `compose-screencast.mjs` throws when its validator is not resolvable (beside it, `../../scripts`, or `AGENTHUB_ROOT`). A silent skip is how the 2026-08 ABACare cuts shipped.
- `compose-screencast.mjs` does not auto-card a `screen` beat. No clip → throw. A `.png` clip on a `screen` beat → throw.
- `fit: hold` may pad a screen clip by at most 2 s; a longer gap needs the storyboard beat's `resultHoldSeconds` (≤ 6 s). `fit: fit` may retime product footage only 0.8–1.25x. `speed` > 1 needs `speedReason`. The 2026-08-31 ABACare 250-01 cold open was a 3.3 s take frozen across 37 s of narration; none of these rules existed.
- A screen clip without a matching `capture/receipt.json` entry fails. `animate-stills.mjs`, a looped PNG, or a hand-typed manifest cannot produce one.
- Ken Burns on `screen-in-context` is off in the Remotion kit. Recast punch-in is the only zoom on product UI.
- `validate-encoded-picture.mjs` on the candidate: dead screen > 6 s in a screen beat fails; a segment whose frames do not come from the receipt-bound clip fails.
- `Inspect-MediaVisualQuality.ps1` flags `ken-burns-on-still` (tiny grayscale hash frozen while full-frame hashes change).
- `media-story-experience-reviewer` refuses `kind: product-screencast` (`MALFORMED_INPUT`). Story review runs on the **encoded** file only. A pre-capture text score is not a craft pass.
- Motif / image-to-video of a product screenshot is refused (`local-ai-stack` `references/video.md`).
- Card / `slide` / `diagram` beats on a `product-screencast` are each ≤8s.
- Recast (`playwright-recast@0.21.0`, declared in `kit/package.json`) is required pointer finishing (`policy/product-video-policy.json` `pointerFinishing`). If its ffmpeg render fails on a long many-click clip, `record-job.mjs` retries without `autoZoom`, then records `recast: fallback`; the validator accepts a fallback only when `job.json` says `recastFallbackAllowed: true` with a reason. Split the take instead.
