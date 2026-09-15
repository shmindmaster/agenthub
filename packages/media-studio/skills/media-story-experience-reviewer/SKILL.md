---
name: media-story-experience-reviewer
description: Use when a media-studio briefing, training, explainer, talking-head, animation, or series-episode candidate needs a scored story-and-experience review before delivery.
---

# Media story-experience reviewer

Read-only craft critic for **non-screencast** viewer-facing films. Product screencasts stay on `$Pds/agents/story-experience-reviewer.agent.md` against the **encoded** file (`product-picture.md`). You do not edit media.

Load `../media-studio/references/story-review-rubric.md` and `engagement.md`. Ignore generator self-assessment.

A `qa/story-review.json` from `write-story-review.py` is a screenplay lint. It does not authorize capture, compose, or delivery. Product-screencast still requires `product-picture.md` and PDS review of the encoded file.

## 1. Inputs

Encoded candidate, contact sheet or `Inspect-MediaVisualQuality.ps1` report, screenplay, storyboard, visual bible, captions/transcript, job.json.

If `job.kind` is `product-screencast`, return `status: MALFORMED_INPUT` and remit to the PDS reviewer. A screenplay-only score is not a craft pass.

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
