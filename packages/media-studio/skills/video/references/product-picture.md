# Product picture

The contract for any film about a running product. It applies when `job.kind` is `product-screencast`, when `programForm` is a product form, or when a beat is `visualMode: screen`. A running product wins over "briefing", "tutorial" or "walkthrough". If nothing on screen can act, the job is a `briefing`. For `programForm: technical-story`, take the story shape from the technical-story beat map; this file still owns capture and gates.

## The contract

A muted viewer follows start, configure, act, response, result. Voice is not proof; the picture is.

- Screens are real captured WebM plus Recast (`capture` skill). No Ken Burns stills, no auto-cards, no animated screenshots, even when a clip is missing: record it.
- Generative video never replaces product UI.
- Missing `visualMode` on a `product-screencast` beat defaults to `screen`, not `slide`.
- **End-to-end demonstration.** Never cut start to result. If a model, connector, permission, trigger or flag drives later behavior, show it set in this session, then the run, then the result.

| Beat | Picture | Forbidden |
| --- | --- | --- |
| Workflow, config, result | WebM + Recast | PNG, scale-pan on UI |
| Code | Product, then overlay or 5–20 line `render-code.mjs` card, then product result | Code slide as the main picture |
| Flow | `render-overlay.mjs` on the product, or a cutaway ≤8 s | Slides between screens |
| Title, CTA | Card ≤8 s | Card filling a missing clip |
| Diagnostic PNG | Poster, contact sheet | Picture of a `screen` beat |

## Script shape for a demo

Parts in order: cold open, hook on the outcome (5–8 s), before-state shown (3–5 s), action, one staged hero moment, payoff held on the outcome or identity rung, guardrail, end card with one next step.

- First sentence carries the payoff or the pain. Never login, logo, "welcome to", "in this video".
- No feature tour: one idea and one `wiifm` per segment; no `wiifm`, cut it.
- No settings walkthrough: show a setting only when it causes a result the film shows.
- Demo the hard case. Flash the complexity, then the clean result. For AI, show enough reasoning to earn trust, with human control beside it.
- Seed one coherent synthetic mini-story. Verify every visible value against the truth sheet.
- Say the value while the screen shows the mechanism. Never narrate the click. Lead the eye before an action; name a result after it appears.
- One persona, one problem, one outcome. 45–120 s by default, 3 minutes at most.

## Interaction recipe

One action per beat:

`start → locator → pointer lead → action → visible product response → result hold`

1. Capture-plan row (`story/capture-plan.json`): `locator`, `action`, `expectedResult`, WebM `clip`, `startState`, `resultState` (they must differ), `provesClaim` (the spoken claim this take proves). Connect setup to runtime with `causalRole` (`start`, `configuration`, `action`, `system-response`, `result`) and `dependsOnSceneId`.
2. Scene: `h.*` helpers only; end every interaction beat with `h.expect(locator, 'label')`.
3. One session: same user, workspace and data (`carryState`).
4. Keep the states that cause the outcome: hover, menu, input, save, loading, toast. Native feedback is the proof; do not cover it with a fake cursor or title card.
5. Frame: wide to establish, punch-in on the control, hold through the response, pull back when context helps. Recast owns cursor, ripple and punch-in, the only zoom on product UI. `render-overlay.mjs` owns dim, box, arrow, label and flow, at most two at once.
6. A hold is the last frame of the WebM, never a PNG.

**Mute test** (every software scene, before encode): right screen, readable UI, action visible, response visible, driving config shown, intermediates kept, framing on the change, cursor intentional, voice in sync, states connect. Any no: recut.

## Cursor rules

The cursor moves only to the next thing the narration names, in one direction per beat, and rests when the line rests.

- Plan `eyePath: { start, move, rest }` per beat. `rest` holds ≥1.5 s. Two moves means two beats. No named target means no motion.
- One `h.approach`, `h.click` or `h.pointAt` per named target, from wherever the pointer is. Never pre-position, park or circle.
- One `h.smoothScroll` toward the element, then stop. Find it before the take, not during.
- Static scenes: `h.pointAt` each element as it is named, then hold.
- `h.hoverHold` logs no named action: follow it with `h.click` or `h.pointAt` on that target.
- Typing: click the field, type, stop. The cursor stays until the result is named.
- Hide build chips, version chips, environment badges and debug labels.

## Timing targets

Starting points, not gates. Helpers build in the first row.

| Move | Target |
| --- | --- |
| Pointer, settle, hold after click | 400–600 ms eased, ≥250 ms, ≥500 ms |
| Click pulse, snap to region | 300–400 ms, 300–500 ms; one zoom per beat, no drift |
| Bounded wait, text entry | Cut or 4–8×, chunk or 3–4×; set `speedReason` |
| After a payoff | 0.5–1.5 s of near-silence |
| On-screen text | `word count / 2.5 + 0.5` seconds |

## Product-readiness feedback

Two valid outcomes: a killer video, or feedback and no video. A mediocre accurate video is neither.

Before production, walk the real workflow and score with evidence in `feedback/`: single clear outcome, fast to value, clean believable states, visual stability, legibility, bounded waits with feedback, discoverable primary action, deterministic reset, visible guardrail, a real hero moment, polish baseline.

- **Capture-fixable:** zoom readable small UI, cut idle time, ramp a bounded wait, spotlight a busy screen. Record the treatment and proceed.
- **Product-fix-required:** no crisp outcome, heavy mandatory setup, broken states, layout instability, unreadable density, unbounded silent wait, hidden primary action, flaky flow, no guardrail, no hero moment.

Verdict: `PASS`, `CONDITIONAL` (capture-fixable only), or `FAIL` (stop production). When unsure, record a short sample and judge what a viewer would see.

One report entry per defect: ID and flow, principle violated, observed behavior with frame, console, trace or timing evidence, viewer impact, severity (`blocks`, `degrades`, `minor`), buildable fix. End with the shortest fix set to `PASS`. File tickets only when the request authorizes it.

## Validators

- `validate-capture-preflight.mjs <jobRoot>`, run by `record-job.mjs`: scene functions match `order`, plan and timeline; cue-plan keywords are in the line; typing (chars × 55 ms + 0.85 s per call) fits the narration.
- `validate-storyboard.mjs <storyboard.json>`: first segment `coldOpen`; one each of `heroMoment`, `payoff`, `guardrail`, `endCard`; `beforeState` 3–5 s; a gap over 15 s needs `attentionReset`.
- `validate-product-picture.mjs <jobRoot>`, run by `compose-screencast.mjs`: screen ≥70%; cards ≤8 s; hash-bound `capture/receipt.json`; pointer or touch motion; interaction beats have an action and an observed `h.expect`; Recast `full` or `noZoom`; freeze pad ≤2 s, or declared `resultHoldSeconds` ≤6 s; `fit` 0.8–1.25×; `speed` > 1 needs `speedReason`. `intent: draft` relaxes only skipped Recast.
- `validate-pointer-path.mjs <jobRoot>`: 0 turns sharper than 120°, travel ≤1.35× direct path, 0 scroll reversals or returns, 0 unnamed moves. Loosen with `pointer: { ..., reason }` on the beat, else re-record.
- `validate-encoded-picture.mjs <jobRoot> <candidate.mp4>`: duration ±1.0 s; frames match the clip (dHash ≤12, ≤18 with overlay); dead screen ≤6 s, or `resultHoldSeconds` up to 8; cards ≤8 s; screen ≥70%; first and last frames not black.
- `validate-sync.mjs <jobRoot> <candidate.mp4>`: screen ≤40 ms late on the first content word; action ±300 ms of its word; result held ≥1.5 s; A/V drift ≤40 ms; ≤3 dropped frames; freeze ≤4 s, declared hold ≤6.5 s; at least one narrated action.
