# Story-experience rubric

Score 0 to 100. **Below 85 is a fail** (job `craftScoreMin`, default 85). Revise the named scenes and rerun. Marketing cuts also need a passing marketing-readiness check.

Before capture: `validate-narration.mjs <jobRoot>`, then `python write-story-review.py <jobRoot>`. It writes `qa/story-review.json`, a lint, never a craft pass. On the encoded file the critic writes `qa/story-experience-review.json` (`schemas/story-experience-review.schema.json`), the only craft pass: `status: COMPLETE`, score at the minimum, no `block` finding. A check without evidence is `MALFORMED_INPUT`, never a pass.

## Checks

`L`: the lint computes it. `J`: verdict and scene-cited evidence in `qa/story-judgments.json` (schema `media-studio/story-judgments/1`: `reviewer`, `judgments`, `deliberateRepeats`, `findings`). `E`: encoded file only. The critic judges every row on the picture.

| Id | By | Pass |
| --- | --- | --- |
| audience | J | Visible in hook, WIIFM, CTA |
| outcome | J | Promise shown, not only named |
| wiifm | J | Outcome or identity, not a feature tour |
| progressive | J | Complexity climbs |
| one-idea | J | One idea per scene |
| one-promise | J | Keeps the `programForm` job |
| studio-picture | J | Picture changes with the idea |
| ai-control | J | `ai-in-action`, `ai-trust`: shows review and limits |
| trust | L, J | Control or limit by the result; lint needs a `trust` scene, and trust or proof within 3 after the hero |
| hook | L | S01 `sceneRole: hook`, pain or payoff and promise in 5 s, no greeting |
| one-hero | L | One `heroMoment`, matching `heroSceneId` and `protectedHeroBeatId`, after scene 3 |
| silence-hero | L | `silenceOnReveal`, or `musicCue` silence, sting or duck |
| before-state | L | `before` or `problem` scene precedes the hero |
| archetype-diversity | L | No accidental repeat |
| designed-frames | L | Card or `cold-open` first, card last held 1.0 s |
| filler | L | `sceneRole`: hook before bridge tension reveal proof trust hero payoff mechanism explain problem close cta |
| narration-vs-type | L | Voice does not read the card |
| type-density | L | Cards under 8 rows and 60 words |
| no-fluff | L | `qa/narration-check.json` ok, bound to the script |
| platform | L | `deliveryProfile` set |
| mix | E | Voice on top, bed ducked |
| cursor-flow | E | `qa/pointer-path.json` PASS |
| marketing-floor | E | `qa/marketing-readiness-check.json` PASS |

## Scoring

Start at 100, floor at 0.

- 20: missing hook, hero count other than one, feature-tour opening
- 15: no before-state, wall-to-wall static, rushed payoff, a failed check with no rule here (trust, designed-frames, no-fluff, platform, failed judgment)
- 10: each filler beat or accidental repeat; once for narration reading type
- 5: each rhythm or type-density miss
- Judgment findings: `points`, else minor 5, major 15

## Fail at any score

Any `block` finding; missing or failing no-fluff, or `cursor-flow` with screen beats; spoken versions, revisions, what changed, how it was made, or synthetic data; a build or version chip in any frame; a marketing cut below the floor.

## Judge the encoded file

Sample frames at cue boundaries and scene midpoints. Check word-clock drift with hosted ASR timestamps. Give the vision judge this rubric, randomise order, compare pairwise, use more than one run, and calibrate against human-labelled clips. Metrics are flags, not verdicts. Cite a timestamp per finding, then set `reviseSceneIds` and `findings[].owner`.
