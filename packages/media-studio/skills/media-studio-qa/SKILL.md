---
name: media-studio-qa
description: Use when a media-studio candidate needs fail-closed screencast evidence, craft, local audio perception, an engagement pass, domain review, arbitration, or final verification.
---

# Media studio QA

Load `../media-studio/references/engagement.md` (Generate / compose / craft critic / QA own).

## 1. product-screencast

Fail-closed release.

Run `packages/media-studio/scripts/validate-product-picture.mjs` on the job root. Story, pacing, music, and zoom for this kind are that gate plus `media-story-experience-reviewer` on the **encoded** file — do not apply a second engagement rubric. Do **not** use `Inspect-MediaVisualQuality.ps1` as this kind's craft gate (that helper is Other kinds). A pre-capture `story-experience-review.json` scored from the screenplay is not a craft pass.

## 2. Other kinds

Briefings, training, explainers, talking-heads, animation, and audio-only do **not** run the four-domain screencast gate. For those:

1. Identity-score owner voice and `ai.ps1 listen` on the **exact encoded file**. Above 90 seconds, pass the canonical narration timeline with `--timeline <timeline.json>`; the Local-AI report must bind the original candidate and prove contiguous decoded-sample coverage across its scene-aligned reviews. Do not substitute separately exported clips.
2. Captions from the spoken words.
3. Require a current `story-experience-review.json` from `media-story-experience-reviewer` with `pass: true` (score ≥ `craftScoreMin`, default 85). If it is missing or failing, remit — do not treat identity/listen as a craft pass.
4. Engagement pass on the **encoded** file (not the screenplay): walk every scene and list stretches that are slow, repetitive, visually static, or emotionally flat per `engagement.md` Diagnose first. Missing hook, wall-to-wall static, rushed payoff, unducked bed, or narration that reads the slide is a fail — remit to writer, storyboard, director, generate, or compose.
5. Run `Inspect-MediaVisualQuality.ps1` on the encoded file. Suspects (static stretch, duplicate visual, undesigned first/last frame) go to the critic or director. Metrics flag; they do not replace judgment.

Do not ship a product-screencast that failed product-picture or encoded-file review.

## 3. Final check

- [ ] Encoded file, not a proxy clip
- [ ] Critic pass on viewer-facing jobs
- [ ] Visual-quality report present
- [ ] Diagnose-first list is empty or remitted
