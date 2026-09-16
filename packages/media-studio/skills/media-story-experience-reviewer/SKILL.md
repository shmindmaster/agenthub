---
name: media-story-experience-reviewer
description: Use when a media-studio briefing, training, explainer, talking-head, animation, or series-episode candidate needs a scored story-and-experience review before delivery.
---

# Media story-experience reviewer

Read-only craft critic for viewer-facing films against the **encoded** file. Product screencasts also require `product-picture.md`. You do not edit media.

Load `../media-studio/references/story-review-rubric.md` and `engagement.md`. Ignore generator self-assessment.

A `qa/story-review.json` from `write-story-review.py` is a screenplay lint. It does not authorize capture, compose, or delivery. Product-screencast still requires `product-picture.md` and this review of the encoded file.

## 0. Before capture

This skill cannot run before capture: it judges the encoded file. The writer's
pre-capture gate for **every** kind, product screencasts included, is the plugin's
`scripts/write-story-review.py` (the media-studio kit keeps its working copy at
`%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools\`):

```text
python write-story-review.py <jobRoot> [--min 85] [--print]
```

It computes the mechanical rubric checks from `story/screenplay.json` + `story/storyboard.json` (hook,
hero, silence, before-state, repeats, designed frames, filler vocabulary, narration reading the card,
type density) and reads the judgment checks (audience, outcome, wiifm, progressive, one-idea,
one-promise, studio-picture, trust when the labels cannot prove it) from `qa/story-judgments.json`,
which the writer records with a scene-cited evidence line per check. A missing judgments file is
`MALFORMED_INPUT`, never a pass. It writes `qa/story-review.json` (this skill's schema) and a provenance
sidecar; nobody hand-writes a score. The rubric arithmetic is unchanged; the tool adds one rule of its
own, named in `reason`: a failed check the rubric gives no arithmetic for costs 15. Below 85 the writer
revises the scenes it names and reruns it before any capture starts. When the master exists, the encoded
critic runs on the file and supersedes
`qa/story-review.json` with `qa/story-experience-review.json`; that review, not the gate, is the craft pass.

## 1. Inputs

Encoded candidate, contact sheet or `Inspect-MediaVisualQuality.ps1` report, screenplay, storyboard, visual bible, captions/transcript, job.json.

If `job.kind` is `product-screencast`, also require a passing `validate-product-picture.mjs` result. A screenplay-only score is not a craft pass.

Missing or mutable inputs → `status: MALFORMED_INPUT`. Never pass a hole. The encoded candidate is required.

## 2. Judge

Walk the rubric checks against the **picture**, not the screenplay. Cite timestamp or frame for every finding.

Fail closed when:

- score < 85 (job `craftScoreMin`, default 85)
- any `block` finding
- missing hook, missing hero, feature-tour opening, wall-to-wall static, unducked bed, narration that reads the slide

Prefer:

`score: 78, pass: false, reviseSceneIds: ["s4","s7"], findings[0].owner: media-storyboard`

Avoid:

`Looks pretty good.` / shipping because QA identity passed.

## 3. Output

`story-experience-review.json` matching `../../schemas/story-experience-review.schema.json`.

`pass` is true only when `status` is `COMPLETE` and `score >= craftScoreMin`.

## 4. Revision

If fail: producer reruns `findings[].owner` on `reviseSceneIds` only, re-encodes, then this skill again. Do not skip to release.

## 5. Final check

- [ ] Encoded file inspected, not inferred
- [ ] Every finding has location, evidence, fix, owner
- [ ] Score arithmetic matches the rubric
- [ ] Fail below 85 even if identity/listen passed
