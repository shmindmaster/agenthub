# Viewer engagement

Load this for every **viewer-facing** media-studio job. `intent: draft` still writes for the ear (hook, one idea, pauses) but skips GPU plates (music, Motif, lipsync). Product-screencast picture rules live in `product-picture.md`.

This file is the home for diagnose / tools / kind defaults / ownership. Dramatic structure lives in `story-craft.md`. Studio picture/sound/voice in `studio-craft.md`. Formats in `program-forms.md`. Archetype ids live in `scene-archetypes.md`. Scoring lives in `story-review-rubric.md`. Skills name the action they own; they do not restate those catalogs.

**Product screencasts** do not use this file as a second rubric. Their craft authority is `killer-demo-production-guide.md` plus the story-experience reviewer on the encoded file. Recast owns cursor, click ripple, and punch-in zoom. Do not invent another overlay stack. The annotation layer (`kit/screencast/render-overlay.mjs`: dim, box, arrow, label, flow diagram) is story markup for `technical-story.md`, directed per beat and composited over Recast's output; it is not an engagement rubric and not a second cursor system.

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
- Same visual archetype twice in a row with no reason
- Narrated PowerPoint: every beat is a type-on-dark-field slide
- Ken Burns / scale-pan on a product screenshot, or a slide stack mixed with frozen UI (`product-picture.md`)
- Feature tour / settings walkthrough posing as a demo
- Instant-perfect AI result with no human control

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
| SFX / silence window | Reveal, hero, match-cut | `sound.sfxCue`, `silenceOnReveal`, `transitionAudio` | Wall-to-wall bed with no accent or rest |
| Archetype change | Idea change | `visualArchetype` from `scene-archetypes.md` | Reusing the briefing slide for every beat |

## Defaults by kind (`intent: viewer-facing`)

| Kind | Default plates | Rhythm |
| --- | --- | --- |
| `briefing` | Bed + Remotion **archetype** kit (not one slide grammar) | Hook in 5–8s. Hold after the takeaway. Consecutive archetype repeats forbidden unless intentional. |
| `training` | Bed + one idea per card / checklist-build | Pattern interrupt between cards. Shorter than a briefing. |
| `explainer` | Bed + dramatic spine in `story-craft.md` + diagram **build** or screen | Question → stakes → wrong intuition → reveal. Show then tell. |
| `talking-head` | Bed + lipsync | Register change on the payoff line. Face stays visible. |
| `animation` | Motif and/or Remotion; bed unless the motion is the music | Do not regenerate motion to fit duration; trim or hold. |
| `audio-only` | Voice + bed unless the user asked for dry speech | Duck the bed. Silence on the key line. |
| `series-episode` | `story-series` owns drama; this studio still mixes bed and holds | Truth tags stay on every beat. |
| `webcast` | Bed + speaker/slide/lower-third/chapter archetypes | Broadcast feel. Chapters. Passive audience. |
| `webinar` | Same + Q&A chapter cards | Taught session, not a slide dump. |
| `keynote` | Talking-head coverage + slides | Change angle; do not lock one webcam. |
| `documentary` | B-roll + slower VO + silence for image | Picture leads. Do not narrate the frame. |
| `teaser` | One hook, one visual language | 15–45s. No intro, no denouement. |
| `product-screencast` | PDS path | Outcome-first (`program-forms.md`). Do not apply this table's plates. |

`intent: draft` (user asked for a scratch, proxy, or timing pass): TTS + stills/slides only. Record what was skipped.

## Writer owns

1. First sentence is payoff or pain — never "welcome" or an agenda.
2. One idea per scene. Tag `DRAMATIZED` / `COMPOSITE` when you heighten.
3. Set `hook`, `emotionalTarget`, `viewerPromise`. Per scene: `sceneRole`, `viewerQuestion`, `wiifm`, one `emphasis`, `pauseBeforeSeconds`, `holdAfterSeconds`. Structure from `story-craft.md`.
4. Do not narrate visible chrome ("click the blue button"). Name the result after it appears.
5. Kill repeated scenes and a long close after the takeaway.
6. Hand the locked screenplay to `media-storyboard`. Do not skip to director.

## Storyboard owns

1. Timed beats: eye direction, expected state, `shotPlan`, `visualArchetype`, `rhythm`, `sound`, `transition`.
2. Internally score 2–3 hook/visual approaches; write `chosenHook` and `rejectedHooks`. Do not present a menu.
3. Exactly one `protectedHeroBeatId`. No consecutive archetype repeats unless intentional.
4. Then `media-studio-visuals` (visual bible) and `media-director`.

## Director owns

1. The picture changes when the idea changes. Prefer the **simplest truthful visual that maintains attention**, not the cheapest still.
2. One emphasis per scene (color **or** zoom **or** callout, not all three unless the hold is the hero).
3. Set `sound.musicCue` / `sfxCue` / `silenceOnReveal`. Viewer-facing default is `bed` with `silence` on the hero hold.
4. Name the Sarosh register. Role voices may use `--instruction`.
5. Then `media-studio-generate`.

## Visuals owns

`visual-bible.json`: motif, lighting, type, composition, B-roll plan, motion treatment, continuity. Never synthesize product UI, metrics, or testimonials.

## Generate / compose / craft critic / QA own

- Generate: consume storyboard + visual bible + direction. TTS with per-beat register. Viewer-facing `musicCue: bed|sting` → `ai.ps1 music`; `silence` generates nothing. Bible B-roll via `ai.ps1 image`. Directed Motif/lipsync/portrait only. Score owner voice before compose.
- Compose: honor pause/hold; duck the bed; Remotion **archetypes** rather than one slide grammar; Recast for `screen`. Two-pass linear loudnorm only. Viewer-facing briefing/training/explainer/series-episode/webcast/webinar/keynote/documentary/teaser **requires Remotion** unless `intent: draft`.
- Craft critic: `media-story-experience-reviewer` on the encoded file. Score < 85 fails; revise `reviseSceneIds` and rerun.
- QA: identity, listen, captions, engagement diagnose, plus `Inspect-MediaVisualQuality.ps1`. Remit to the owner above. Non-screencast kinds do not claim PDS arbitration.
