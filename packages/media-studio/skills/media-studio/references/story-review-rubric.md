# Story-experience rubric (non-screencast)

Used by `media-story-experience-reviewer`. Product screencasts stay on `$Pds/agents/story-experience-reviewer.agent.md`.

Score 0–100. **Below 85 is a fail.** Remit deficient scenes and rerun. Do not deliver.

Judge the **encoded file** plus screenplay, storyboard, visual bible, and captions. A criterion without evidence is `MALFORMED_INPUT`, never pass.

## Checks

| Id | Pass |
| --- | --- |
| audience | Declared audience is visible in hook, WIIFM, and CTA |
| before-state | Viewer feels the current cost before the solution |
| outcome | ViewerPromise is shown, not only named |
| wiifm | Segment-level WIIFM is outcome or identity, not a feature tour |
| hook | Payoff or pain in 5–8s; no greeting, logo reel, agenda |
| one-hero | Exactly one protected hero moment with anticipation, hold, visible payoff |
| trust | A control, limit, or hard-case glimpse sits next to the result |
| progressive | Complexity climbs; the hard case is not the first beat after the hook |
| one-idea | One idea per scene; picture changes when the idea changes |
| archetype-diversity | No accidental consecutive repeat of the same `visualArchetype` |
| designed-frames | First and last frames are intentional and stable |
| filler | Every beat is hook, before, tension, reveal, proof, trust, hero, required transition, or CTA |
| narration-vs-type | Narration does not read the slide |
| silence-hero | Hero / reveal has silence or a ducked bed, not wall-to-wall music |
| platform | Delivery profile (title/thumbnail/opening, mute-safe, vertical safe area) holds |
| one-promise | The film keeps the declared `programForm` job; nav tours fail |
| studio-picture | Picture changes with the idea; not a slide stack (`studio-craft.md`) |
| mix | Voice on top, bed ducked, silence or sting on hero |
| ai-control | `ai-in-action` / `ai-trust` show review and limits, not instant magic |

Empty findings only when the candidate is persuasive, coherent, polished, **and** score ≥ 85.

## Scoring

Start at 100. Subtract:

- 20 for a missing hook, missing hero, or feature-tour opening
- 15 for wall-to-wall static, rushed payoff, or no before-state
- 10 per filler beat or consecutive accidental archetype repeat
- 10 for narration that reads on-screen type
- 5 per minor rhythm or type-density miss

Floor at 0. Any `block` finding forces fail regardless of arithmetic.

## Revision loop

`reviseSceneIds` + `findings[].owner` go back to that skill. The producer reruns only the deficient scenes, then this reviewer again, then `media-studio-qa`.
