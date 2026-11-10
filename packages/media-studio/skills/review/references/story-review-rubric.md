# Story-experience rubric

Score 0 to 100. **Below 85 is a fail** (job `craftScoreMin`, default 85). Revise the named scenes and rerun. Marketing cuts also need a passing marketing-readiness check.

Before capture: `validate-narration.mjs <jobRoot>`, then `python write-story-review.py <jobRoot>`. It writes `qa/story-review.json`, a lint, never a craft pass. A screenplay lint from `write-story-review.py` authorizes nothing after capture. On the encoded file the critic writes `qa/story-experience-review.json` (`schemas/story-experience-review.schema.json`), the only craft pass: `status: COMPLETE`, score at the minimum, no `block` finding. A check without evidence is `MALFORMED_INPUT`, never a pass.

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

Fail when the score is under `craftScoreMin` (default 85), on any `block` finding, or when the hook is missing, the hero count is not exactly one, the opening is a feature tour, the bed is unducked, the narration reads the slide, anything is said twice, or the cursor moves with nothing named. Marketing cuts also need `qa/marketing-readiness-check.json` PASS on this candidate.

## Context and software-orientation ship blockers

An engaging cold open is allowed; a context-free montage is not. On any
buyer-facing software film, review the actual picture and audio from 0:00
through the first solution and payoff. Record a timestamped `block` finding
and send it to `develop` / `video` when any of these occurs:

- The viewer never learns the persona, situation, triggering event or
  specific problem. The first shots simply cycle among unrelated screens.
- The product is not identified by name in its solution beat; the viewer
  cannot tell what software is solving the issue until the closing logo.
- There is no visible cause-and-effect: one screen is followed by another,
  without showing what was done, what the system returned and why that
  result addresses the original stakes.
- The film exits directly after a screen tour instead of revisiting the
  original problem, holding the result and supplying one relevant next step.

For >=25s marketing cuts, verify the `narrative`/ `storyRole` preflight
and then independently assess whether the **encoded footage** truly conveys
that outline. Metadata, scene-role tags and a passing `lint` report cannot
prove that the audience understands the story. A silent watch-through is
mandatory: the outcome must remain comprehensible without narration, aided
by screen evidence and available captions. Never manufacture a product
capability or an outcome to close a narrative gap.

## Creative experience check: evidence on the finished movie

On the encoded candidate, the reviewer must explicitly assess the following
with timestamps (do not accept `hookPlan`, `narrative` or `storyRole` labels
as proof that the movie actually works):

1. **Layered first seconds:** does the actual first frame say who this is for
   or what is at stake, and do the visible/native words and narration work
   together without contradicting or merely repeating one another?
   Does the opening earn attention *without* hiding essential context?
2. **Human relevance:** can a viewer recognize the actor's task, source of
   friction and plausible emotional cost? Is the emotional change credible
   and proportionate, not manufactured fear or a miracle claim?
3. **Progression:** does each middle beat introduce a genuine action, obstacle,
   insight, state change or result? Would swapping these beats change
   the logic? If not, the cut is likely an unconnected feature montage.
4. **Open-loop closure:** identify the first viewer question and cite where
   the film answers it. An unexplained cliffhanger or sudden exit is a
   failure, not a retention tactic.
5. **Value and evidence:** does the film deliver its original useful insight
   before asking for a click? Is the named product shown causing a
   source-verified response/result, with human review and limits for AI?
6. **Editing for meaning:** do transitions, text, music and silence follow
   meaning and preserve legibility? Do **not** fail an otherwise clear
   film for lacking arbitrary cuts or a surprise every three seconds.
7. **Audience/channel fit:** judge mobile legibility and muted viewing for
   feed cuts; demand a complete usable workflow for product demos. Avoid
   treating identical edits at different aspect ratios as automatically
   audience-appropriate.

A missing scenario, unexplained solution, unearned claim, incoherent
mechanism, missing payoff or missing viewer value is a **block** finding
even if the structural lint and numerical craft score pass. A pattern
interrupt is never mandatory; making the plot confusing in order to
increase curiosity is itself a defect. The reviewer should state what
a first-time viewer would actually understand by 0:03, 0:10, the
solution introduction and the payoff, citing frames.

## Judge the encoded file

The story-experience review reads the picture. Cite a timestamp or frame for every finding and ignore generator self-assessment. Required inputs: encoded candidate, contact sheet, screenplay, storyboard, visual bible, captions, `job.json`, `qa/narration-check.json`, and `qa/pointer-path.json` with screen beats. A `product-screencast` also needs a passing `validate-product-picture.mjs`. A missing or mutable input is `status: MALFORMED_INPUT`, never a pass.

`build-contact-sheet.mjs <jobRoot> <candidate.mp4>` writes `qa/contact-sheet.png`. Sample frames at cue boundaries and scene midpoints. Check word-clock drift with hosted ASR timestamps. Give the vision judge this rubric, randomise order, compare pairwise, use more than one run, and calibrate against human-labelled clips. Metrics are flags, not verdicts. Cite a timestamp per finding, then set `reviseSceneIds` and `findings[].owner`.
