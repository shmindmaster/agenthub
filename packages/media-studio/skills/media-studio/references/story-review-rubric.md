# Story-experience rubric (non-screencast)

Used by the story-experience review (`media-studio-qa` → "Story-experience review") on the encoded file, including product screencasts. Marketing cuts
are additionally held to the floor in `marketing-readiness.md`; below that floor is a fail whatever this score says.

Score 0–100. **Below 85 is a fail.** Remit deficient scenes and rerun. Do not deliver.

Judge the **encoded file** plus screenplay, storyboard, visual bible, and captions. A criterion without evidence is `MALFORMED_INPUT`, never pass.

`write-story-review.py` may lint the screenplay before capture. That score is not a craft pass. Product-screencast still requires `product-picture.md` (WebM + Recast) and this rubric's encoded-file reviewer.

## Before capture

The encoded critics cannot run before the master exists, so every kind first passes
`scripts/validate-narration.mjs <jobRoot>` (no fluff, hook and promise inside five seconds, synthetic disclosure
off the voice track; writes `qa/narration-check.json`) and then
`scripts/write-story-review.py <jobRoot>` on `story/screenplay.json` + `story/storyboard.json`. It computes
the mechanical checks below (hook, one-hero, silence-hero, before-state, archetype-diversity,
designed-frames, filler, no-fluff, narration-vs-type, type-density, platform) and reads audience, outcome, wiifm,
progressive, one-idea, one-promise, studio-picture (and trust when the scene labels cannot prove it)
from `qa/story-judgments.json`, a writer-recorded verdict with a scene-cited evidence line per check. No
judgments file means `MALFORMED_INPUT` and no score. The arithmetic below applies unchanged, plus one
rule of the tool's own, named in its `reason`: a failed check this rubric gives no arithmetic for (trust,
designed-frames, platform, no-fluff, a failed judgment) costs 15. Below 85 the scenes it names are revised and it
runs again before capture. It writes `qa/story-review.json`; the encoded critic later supersedes it with
`qa/story-experience-review.json`, which is the only craft pass.

## Checks

| Id | Pass |
| --- | --- |
| audience | Declared audience is visible in hook, WIIFM, and CTA |
| before-state | Viewer feels the current cost before the solution |
| outcome | ViewerPromise is shown, not only named |
| wiifm | Segment-level WIIFM is outcome or identity, not a feature tour |
| hook | Payoff or pain inside the first five seconds; the promise named in them; no greeting, logo reel, agenda |
| no-fluff | `qa/narration-check.json` is a PASS for this script: no banned class, nothing said twice, every line adds something, no spoken synthetic-data talk, no version or process talk |
| cursor-flow | Every screen beat's pointer moved only to what the line named, one direction, no scroll return (`qa/pointer-path.json` PASS); nothing on screen moved that the narration was not about |
| one-hero | Exactly one protected hero moment with anticipation, hold, visible payoff |
| trust | A control, limit, or hard-case glimpse sits next to the result |
| progressive | Complexity climbs; the hard case is not the first beat after the hook |
| one-idea | One idea per scene; picture changes when the idea changes |
| archetype-diversity | No accidental consecutive repeat of the same `visualArchetype` |
| designed-frames | First and last frames are intentional and stable; no build or version chip anywhere |
| filler | Every beat is hook, before, tension, reveal, proof, trust, hero, required transition, or CTA |
| narration-vs-type | Narration does not read the slide |
| silence-hero | Hero / reveal has silence or a ducked bed, not wall-to-wall music |
| platform | Delivery profile (title/thumbnail/opening, mute-safe, vertical safe area) holds |
| one-promise | The film keeps the declared `programForm` job; nav tours fail |
| studio-picture | Picture changes with the idea; not a slide stack (`studio-craft.md`) |
| mix | Voice on top, bed ducked, silence or sting on hero |
| ai-control | `ai-in-action` / `ai-trust` show review and limits, not instant magic |
| marketing-floor | Marketing cuts only: `qa/marketing-readiness-check.json` PASS (`marketing-readiness.md`) |

Empty findings only when the candidate is persuasive, coherent, polished, **and** score ≥ 85.

## Scoring

Start at 100. Subtract:

- 20 for a missing hook, missing hero, or feature-tour opening
- 15 for wall-to-wall static, rushed payoff, or no before-state
- 10 per filler beat or consecutive accidental archetype repeat
- 10 for narration that reads on-screen type
- 5 per minor rhythm or type-density miss

Floor at 0. Any `block` finding forces fail regardless of arithmetic. These are always `block`:

- a failed or missing `no-fluff` check on the locked script
- a failed or missing `cursor-flow` check on a film with screen beats
- any spoken mention of versions, revisions, what changed, how the film was made, or synthetic data
- a build or version chip visible in any frame
- a marketing cut below the floor in `marketing-readiness.md`

## Revision loop

`reviseSceneIds` + `findings[].owner` go back to that skill. The producer reruns only the deficient scenes, then this reviewer again, then `media-studio-qa`.
