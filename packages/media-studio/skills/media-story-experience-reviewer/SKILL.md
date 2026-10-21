---
name: media-story-experience-reviewer
description: Use when a media-studio briefing, training, explainer, talking-head, animation, or series-episode candidate needs a scored story-and-experience review before delivery.
---

# Media story-experience reviewer

Read-only craft critic for viewer-facing films against the **encoded** file. Product screencasts also require `product-picture.md`. You do not edit media.

Load `../media-studio/references/story-review-rubric.md` and `engagement.md`; `marketing-readiness.md` when the job is a marketing cut; `story-craft.md` → "No fluff" and `cursor-flow.md` always. Ignore generator self-assessment.

A `qa/story-review.json` from `write-story-review.py` is a screenplay lint. It does not authorize capture, compose, or delivery. Product-screencast still requires `product-picture.md` and this review of the encoded file.

## 0. Before capture

This skill cannot run before capture: it judges the encoded file. The writer's
pre-capture gate for **every** kind, product screencasts included, is the plugin's
`scripts/validate-narration.mjs` (no fluff; `qa/narration-check.json`) followed by
`scripts/write-story-review.py` (the media-studio kit keeps its working copies at
`%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools\`):

```text
node validate-narration.mjs <jobRoot>
python write-story-review.py <jobRoot> [--min 85] [--print]
```

It computes the mechanical rubric checks from `story/screenplay.json` + `story/storyboard.json` (hook,
hero, silence, before-state, repeats, designed frames, filler vocabulary, no-fluff from the narration check,
narration reading the card, type density) and reads the judgment checks (audience, outcome, wiifm, progressive,
one-idea, one-promise, studio-picture, trust when the labels cannot prove it) from `qa/story-judgments.json`,
which the writer records with a scene-cited evidence line per check. A missing judgments file is
`MALFORMED_INPUT`, never a pass. It writes `qa/story-review.json` (this skill's schema) and a provenance
sidecar; nobody hand-writes a score. The rubric arithmetic is unchanged; the tool adds one rule of its
own, named in `reason`: a failed check the rubric gives no arithmetic for costs 15. Below 85 the writer
revises the scenes it names and reruns it before any capture starts. When the master exists, the encoded
critic runs on the file and supersedes
`qa/story-review.json` with `qa/story-experience-review.json`; that review, not the gate, is the craft pass.

## 1. Inputs

Encoded candidate, contact sheet (`qa/contact-sheet.png` + index from `build-contact-sheet.mjs`) or `Inspect-MediaVisualQuality.ps1` report, screenplay, storyboard, visual bible, captions/transcript, job.json, `qa/narration-check.json`, and `qa/pointer-path.json` when the film has screen beats.

If `job.kind` is `product-screencast`, also require a passing `validate-product-picture.mjs` result. A screenplay-only score is not a craft pass.

Missing or mutable inputs → `status: MALFORMED_INPUT`. Never pass a hole. The encoded candidate is required.

## 2. Judge

Walk the rubric checks against the **picture**, not the screenplay. Cite timestamp or frame for every finding. The viewer is not in a review room; judge the first five seconds as a stranger scrolling past.

Fail closed when:

- score < 85 (job `craftScoreMin`, default 85)
- any `block` finding
- missing hook, missing hero, feature-tour opening, wall-to-wall static, unducked bed, narration that reads the slide
- `qa/narration-check.json` missing or failing; any spoken line about versions, revisions, what changed, how the film was made, or synthetic data (block)
- anything said twice; a card that repeats the voice; a build, version, environment or revision chip in any frame (block)
- `qa/pointer-path.json` missing or failing on a film with screen beats; a cursor or highlight that moves while nothing is named, goes back, or scrolls past and returns (block)
- `qa/picture-integrity.json` missing or failing on a film with product footage; a product frame that looks soft (upscaled), stretched, cropped at a UI edge, barred, or a vertical cut that is plainly a desktop capture (block). On every declared punch-in, attest in the review that no UI the line names leaves the frame; that is the one integrity check the gate cannot make
- a marketing cut below the floor (section 3)

Prefer:

`score: 78, pass: false, reviseSceneIds: ["s4","s7"], findings[0].owner: media-storyboard`

Avoid:

`Looks pretty good.` / shipping because QA identity passed.

## 3. Marketing cuts: the feed test

When `job.json` is a marketing cut (`programForm` campaign-*, `marketing-cutdown`, `social-clip`, `hero`; `kind: teaser`; or `marketing: true`), the question is not "is it accurate and complete" but **"would this win the viewer in a feed next to the references?"** Write `qa/marketing-readiness.json` (schema `media-studio/marketing-readiness/1`, shape in `marketing-readiness.md`), bound to the exact candidate, with a timestamped verdict per criterion:

1. hook on screen inside two seconds (`hook.atSeconds`, what is on screen)
2. one promise, kept (`promise.text`, `count: 1`, evidence)
3. designed motion and type (evidence with timestamps)
4. music bed and sound design carrying the pace (`sound.bed`, `designCues`)
5. brand kit end card with one CTA inside the last eight seconds
6. cuts on the beat (`cutsOnBeat.bpm`, `offsetSeconds`)
7. three cited reference ads this cut competes against (title, source, why it wins)
8. the feed verdict: `attentionCompetition.winsAgainstReferences` with evidence from the first five seconds

Then run `scripts/validate-marketing-readiness.mjs <jobRoot> <candidate.mp4>`; it measures what it can (hook time, end-card window, cuts against the grid from the edit list, the narration check) and writes `qa/marketing-readiness-check.json`. Below the floor is `pass: false` with a `block` finding, whatever the story score. An honest `winsAgainstReferences: false` names the reference that beat it in `evidence` and sends the cut to `media-writer` / `media-storyboard`.

Explainers and technical stories are not judged against reference ads; they keep this rubric and inherit the no-fluff and cursor blocks above.

## 4. Output

`story-experience-review.json` matching `../../schemas/story-experience-review.schema.json`.

`pass` is true only when `status` is `COMPLETE`, `score >= craftScoreMin`, no `block` finding, and, for a marketing cut, `qa/marketing-readiness-check.json` is a PASS on this candidate.

## 5. Revision

If fail: producer reruns `findings[].owner` on `reviseSceneIds` only, re-encodes, then this skill again. Do not skip to release.

## 6. Final check

- [ ] Encoded file inspected, not inferred; contact sheet used for the walk-through
- [ ] Every finding has location, evidence, fix, owner
- [ ] Score arithmetic matches the rubric; no-fluff, redundancy and cursor blocks applied
- [ ] Marketing cut: readiness file written and its check is a PASS, or the review fails
- [ ] Fail below 85 even if identity/listen passed
