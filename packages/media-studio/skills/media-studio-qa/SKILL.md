---
name: media-studio-qa
description: Use when a media-studio candidate needs fail-closed screencast evidence, craft, local audio perception, an engagement pass, domain review, arbitration, or final verification.
---

# Media studio QA

Load `../media-studio/references/engagement.md` (Generate / compose / craft critic / QA own).

## 1. product-screencast

Fail-closed release. Gates run on source artifacts and the exact encoded candidate; a numeric craft score never overrides them. Native plugins resolve `scripts/` inside their installed package. Loose-skill hosts use `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools`; its `RELEASE-EVIDENCE.md` defines the evidence contract. Missing executables block release.

0. `scripts/validate-demo-scenario.mjs <jobRoot>` **before recording** — source-hashed synthetic scenario proof: persona, pain, hero action, visible outcome, coherent generic entity continuity, and CTA. Do not record a hard-coded or unverified authenticated path. A readiness handoff must prove the product resolves the intended workflow.
1. `scripts/validate-product-picture.mjs <jobRoot>` — plan and clips: receipt-bound live captures, pointer motion, observed responses, Recast, no hidden freeze, ≥70% screen.
2. `scripts/validate-encoded-picture.mjs <jobRoot> <candidate.mp4>` — the file a viewer will watch: every screen segment binds to its captured clip (dHash), no dead screen > 6 s in a screen beat, cards ≤ 8 s, designed first/last frames. Writes `qa/encoded-picture.json` bound to the candidate SHA-256 and byte count. The viewer-release gate reads that exact PASS report and rejects lax static/source-binding thresholds; missing or failing → do not ship.
2b. **Sync gate:** `node <tools>/validate-sync.mjs <jobRoot> <candidate.mp4>` on the same exact file, after `build-cue-sheet.mjs` has been rerun against the final compose map. For the exact 40 ms A/V check run ASR on the encoded audio first: `ai.ps1 transcribe <candidate.mp4> --engine whisper --json-out <jobRoot>/qa/encoded-asr.json` (the gate picks it up; without it drift is estimated from speech onsets). It checks screen up by the first content word, each narrated action within ±300 ms of its spoken verb or object, result held ≥1.5 s after it is shown and named, no result named before it appears, A/V drift ≤40 ms, dropped frames, and exact-frame freezes. It writes `qa/sync.json` bound to the candidate SHA-256 with per-beat findings and the checks it did **not** perform (text clipping needs tesseract; cursor lead and cursor continuity across cuts are never machine-checked; action times come from the capture receipt through the edit list, not from pixels). On FAIL, re-time, re-capture or re-render only the failing beats, then rerun every gate on the new encode. Word-level ASR is required; `--allow-degraded` is diagnostic and cannot release.
3. Voice: `qa/pronunciation-risk.json` (from `ai.ps1 voice pronunciation-risk`, written by `Generate-OwnerVoice.ps1`) with `coverage.status` PASS or REVIEW, and `qa/pronunciation-listen.json` with `finalStatus: PASS` (per-scene `ai.ps1 listen` grounded in transcript + risk slice). Then identity-score and `ai.ps1 listen` on the **encoded** candidate with `--transcript` and `--pronunciation-manifest qa/pronunciation-risk.json` (and `--timeline` above 90 s); the report must say `releaseEligible: true`. An ungrounded listen report is diagnostic only.
4. Story and craft on the encoded file: hook in the first 10 s, one promise, one hero moment, conversational narration that adds meaning the screen does not already show, pointer visible where an action happens, result on screen before or as it is spoken, no feature-tour opening, no long title cards. Record the review as `qa/story-experience-review.json` (score, per-scene notes, `reviseSceneIds`). Score < 85 or any visual/pronunciation failure above → revise **those scenes only** and remux; do not restart writer → capture → TTS. The score cannot rescue a failed gate.

Final human-grade review, never skipped: watch and listen to the whole exact encoded file and check the representative frames and every critical interaction against the cue-sheet timeline (screen already up at the line's first content word, cursor on the control as it is named, result readable after). The sync gate does not replace this. **Never say sync or visual quality is verified unless you inspected the rendered file and its audio; a successful render or a PASS report alone is not verification.** State limitations plainly in the handoff (e.g. "the architecture beat uses a guided highlight, not live UI"; "text clipping not machine-checked, no OCR").

Screen accuracy: every spoken product claim is visible in that beat's frames (`qa/screen-accuracy.json`). Mute test: `product-picture.md`. Do **not** use `Inspect-MediaVisualQuality.ps1` or `media-story-experience-reviewer` for this kind.

## 2. Other kinds

Briefings, training, explainers, talking-heads, animation, and audio-only do **not** run the four-domain screencast gate. For those:

1. Identity-score owner voice and `ai.ps1 listen` on the **exact encoded file**. Above 90 seconds, pass the canonical narration timeline with `--timeline <timeline.json>`; the Local-AI report must bind the original candidate and prove contiguous decoded-sample coverage across its scene-aligned reviews. Do not substitute separately exported clips.
2. Captions from the spoken words.
3. Require a current `story-experience-review.json` from `media-story-experience-reviewer` with `pass: true` (score ≥ `craftScoreMin`, default 85). If it is missing or failing, remit — do not treat identity/listen as a craft pass.
4. Engagement pass on the **encoded** file (not the screenplay): walk every scene and list stretches that are slow, repetitive, visually static, or emotionally flat per `engagement.md` Diagnose first. Missing hook, wall-to-wall static, rushed payoff, unducked bed, or narration that reads the slide is a fail — remit to writer, storyboard, director, generate, or compose.
5. Run `Inspect-MediaVisualQuality.ps1` on the encoded file. Suspects (static stretch, duplicate visual, undesigned first/last frame) go to the critic or director. Metrics flag; they do not replace judgment.

5. `scripts/validate-viewer-release.mjs <jobRoot> <candidate.mp4>` after **every** recut — it requires the exact candidate SHA on captions, loudness, authored-script pronunciation, visual/title/action-result reviews, and CTA and, when applicable, series evidence. Captions must be readable rather than paragraph blocks; ASR cannot be its own pronunciation reference.

Do not ship a product-screencast that failed scenario, product-picture, exact-candidate, or encoded-file review.

## 3. Final check

- [ ] Encoded file, not a proxy clip; `qa/encoded-picture.json` and `qa/sync.json` present and ok for screencasts, both bound to this SHA-256
- [ ] Watched and listened to the exact file; limitations and not-performed checks reported
- [ ] Critic pass on viewer-facing jobs
- [ ] Product-screencast mute test and screen-accuracy pass; configuration claims have on-screen proof
- [ ] Visual-quality report present
- [ ] Diagnose-first list is empty or remitted
