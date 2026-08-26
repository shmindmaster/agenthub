# Viewer engagement

Load this for every **viewer-facing** media-studio job. `intent: draft` still writes for the ear (hook, one idea, pauses) but skips GPU plates (music, Motif, lipsync).

This file is the only home for these rules. Skills name the action they own; they do not restate this table.

**Product screencasts** do not use this file as a second rubric. Their craft authority is `$Pds\pipeline\product-demo-studio\references\killer-demo-production-guide.md` plus the story-experience reviewer. Recast owns cursor, click ripple, and punch-in zoom. Do not invent another overlay stack.

Goal: the viewer keeps watching. Important moments feel important. Polish is intentional, not decorative.

## Diagnose first

A stretch is failing if any of these are true:

- Wall-to-wall speech with no pause before or after the point
- One visual held across more than one idea
- Narration that repeats words already on screen
- No contrast (old/new, cost/relief, setup/payoff)
- Payoff rushed or followed by a long denouement
- Same rhythm every scene
- Opening is a greeting, logo reel, or agenda

Fix the failing stretch. Do not sprinkle effects on a cut that already lands.

## Tools we actually have

| Technique | Use when | Provider | Refuse |
| --- | --- | --- | --- |
| Music bed | Viewer-facing briefing, training, explainer, talking-head, series-episode, audio-only | `ai.ps1 music` then `Finish-Media.ps1 -Speech -Music` (sidechain duck, felt not heard) | Bed under a product-screencast hero (PDS owns that mix). One-pass loudnorm. Studio Sound on owner voice. |
| Silence | Payoff, title card, CTA | `musicCue: silence` plus `pauseBeforeSeconds` / `holdAfterSeconds` | Filling every gap with music |
| Register / tone | Owner voice | Sarosh style-bank register (`explaining`, `firm`, `serious`, …) | Free-text "sound excited". Cloud TTS for Sarosh. |
| Zoom | Live product (`screen`) | Recast punch-in, one per beat | Ken Burns on slides. Fake cursor on type. |
| Text callout | Naming, not explaining | `onScreen` ≤4 words, color emphasis, hold `wordCount / 2.5 + 0.5s` | Callouts that repeat the narration |
| B-roll | Problem, outcome, or context — not product UI | Visual Bank / `ai.ps1 image` / Motif from an enrolled still | Synthesized product UI, metrics, testimonials |
| Motion graphics | Slide/explainer build, one kinetic number | Remotion `useCurrentFrame()` / `interpolate()` | CSS/Tailwind animation classes. A new Remotion app. |
| Cut / rhythm | Idea change, old-way → new-way | New scene; speed-ramp waits 4–8× | Cutting before the result is readable. Hiding a product defect. |
| Click / whoosh | Product action, major scene join | Recast click ripple; optional sting (`musicCue: sting`) | SFX that covers missing product feedback |

## Defaults by kind (`intent: viewer-facing`)

| Kind | Default plates | Rhythm |
| --- | --- | --- |
| `briefing` | Bed + Remotion builds (headline in, emphasis color, hold to speech) | Hook in 5–8s. Hold after the takeaway. Not a static card for the whole line. |
| `training` | Bed + one idea per card | Pattern interrupt between cards. Shorter than a briefing. |
| `explainer` | Bed + diagram **build** (or screen if the claim is a running product) | Show then tell. Animate only when motion itself teaches. |
| `talking-head` | Bed + lipsync | Register change on the payoff line. Face stays visible. |
| `animation` | Motif and/or Remotion; bed unless the motion is the music | Do not regenerate motion to fit duration; trim or hold. |
| `audio-only` | Voice + bed unless the user asked for dry speech | Duck the bed. Silence on the key line. |
| `series-episode` | `story-series` owns drama; this studio still mixes bed and holds | Truth tags stay on every beat. |
| `product-screencast` | PDS path | Do not apply this table. |

`intent: draft` (user asked for a scratch, proxy, or timing pass): TTS + stills/slides only. Record what was skipped.

## Writer owns

1. First sentence is payoff or pain — never "welcome" or an agenda.
2. One idea per scene. Tag `DRAMATIZED` / `COMPOSITE` when you heighten.
3. Set `hook` and `emotionalTarget` on the screenplay. Per scene: one `emphasis` word, `pauseBeforeSeconds` (payoff setup), `holdAfterSeconds` (0.5–1.5s after a landing).
4. Do not narrate visible chrome ("click the blue button"). Name the result after it appears.
5. Kill repeated scenes and a long close after the takeaway.

## Director owns

1. The picture changes when the idea changes. A slide that does not build is a still; call Motif, a diagram build, B-roll, or a cut instead of holding it.
2. One emphasis per scene (color **or** zoom **or** callout, not all three unless the hold is the hero).
3. Set `musicCue` (`bed` / `sting` / `silence` / `none`) per scene. Viewer-facing default is `bed` with `silence` on the hero hold.
4. Name the Sarosh register. Role voices may use `--instruction`.
5. Then `media-studio-generate`.

## Generate / compose / QA own

- Generate: TTS always. Viewer-facing `musicCue: bed|sting` → `ai.ps1 music`. Directed Motif/lipsync/portrait only. Score owner voice before compose.
- Compose: honor pause/hold; duck the bed; Remotion builds rather than static holds; Recast for `screen`. Two-pass linear loudnorm only.
- QA: walk the encoded file. Fail missing hook, wall-to-wall static, rushed payoff, unducked bed, or narration that reads the slide. Remit to the owner above. Non-screencast kinds do not claim PDS arbitration.
