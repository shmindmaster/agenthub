---
name: media-story-experience-reviewer
description: Use when a media-studio briefing, training, explainer, talking-head, animation, or series-episode candidate needs a scored story-and-experience review before delivery.
---

# Media story-experience reviewer

Read-only craft critic for **non-screencast** viewer-facing films. Product screencasts stay on `$Pds/agents/story-experience-reviewer.agent.md`. You do not edit media.

Load `../media-studio/references/story-review-rubric.md` and `engagement.md`. Ignore generator self-assessment.

## 1. Inputs

Encoded candidate, contact sheet or `Inspect-MediaVisualQuality.ps1` report, screenplay, storyboard, visual bible, captions/transcript, job.json.

Missing or mutable inputs → `status: MALFORMED_INPUT`. Never pass a hole.

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
