---
name: media-studio-qa
description: Use when a media-studio candidate needs fail-closed screencast evidence, craft, a scored story-and-experience review, local audio perception, an engagement pass, domain review, arbitration, or final verification.
---

# Media studio QA

Load `../media-studio/references/engagement.md` (Generate / compose / craft critic / QA own), `story-craft.md` → "No fluff", `cursor-flow.md`, and `marketing-readiness.md` when the job is a marketing cut.

Four rules hold for every kind and no gate below outranks them: no fluff (every line earns its seconds; nothing spoken about synthetic data, versions, revisions or how the film was made); the feed test for customer-facing cuts (wins the viewer against the references in the first five seconds, not "accurate and complete"); nothing redundant (one idea said once, no build or version chips); the cursor moves with purpose (only to the next thing named, one direction per beat, nothing moves that the narration is not about).

## 1. product-screencast

Fail-closed release. Gates run on source artifacts and the exact encoded candidate; a numeric craft score never overrides them. Native plugins resolve `scripts/` inside their installed package. Loose-skill hosts use `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools`; its `RELEASE-EVIDENCE.md` defines the evidence contract. Missing executables block release.

0. `scripts/validate-demo-scenario.mjs <jobRoot>` **before recording** — source-hashed synthetic scenario proof: persona, pain, hero action, visible outcome, coherent generic entity continuity, and CTA. Do not record a hard-coded or unverified authenticated path. A readiness handoff must prove the product resolves the intended workflow.
0b. `scripts/validate-narration.mjs <jobRoot>` **before recording** — the no-fluff check on the locked script: every banned class (greeting, meta, recap, process, version, synthetic-data talk, jargon, filler), redundancy, lines that add nothing, hook and promise inside five seconds, synthetic disclosure as caption or end card. Writes `qa/narration-check.json` with fluff per minute and the words-cut report. Any hit → back to the writer (`../media-studio/references/writer.md`); `write-story-review.py` and the viewer-release gate both require this PASS.
0c. Capture pre-flight runs inside `record-job.mjs` (`validate-capture-preflight.mjs`): scene ids across `scenes.mjs`, the narration timeline, storyboard, capture plan and cue plan agree, every cue-plan keyword is in its line, typing fits the beat. `qa/capture-preflight.json` must be a PASS; `recordings.preflight: skipped` is not.
1. `scripts/validate-product-picture.mjs <jobRoot>` — plan and clips: receipt-bound live captures, pointer motion, observed responses, Recast, no hidden freeze, ≥70% screen.
1b. **Pointer-path gate:** `scripts/validate-pointer-path.mjs <jobRoot>` — the receipt's move, wheel, click, point and type events per beat against the cue sheet: direction reversals (flicking, up-and-down, going back), total travel against the straight path through the named targets, scroll reversals and scroll-past-and-return, moves not followed by a named action. Defaults are zero reversals, zero scroll returns, travel ≤ 1.35× direct, zero unnamed moves; a cue-plan `pointer` allowance needs a reason. Writes `qa/pointer-path.json` bound to the receipt. FAIL → re-record those beats; nothing else fixes a wandering cursor.
2. `scripts/validate-encoded-picture.mjs <jobRoot> <candidate.mp4>` — the file a viewer will watch: every screen segment binds to its captured clip (dHash), no dead screen > 6 s in a screen beat, cards ≤ 8 s, designed first/last frames. Writes `qa/encoded-picture.json` bound to the candidate SHA-256 and byte count. The viewer-release gate reads that exact PASS report and rejects lax static/source-binding thresholds; missing or failing → do not ship.
2b. **Sync gate:** `node <tools>/validate-sync.mjs <jobRoot> <candidate.mp4>` on the same exact file, after `build-cue-sheet.mjs` has been rerun against the final compose map. For the exact 40 ms A/V check run ASR on the encoded audio first: `ai.ps1 transcribe <candidate.mp4> --engine whisper --json-out <jobRoot>/qa/encoded-asr.json` (the gate picks it up; without it drift is estimated from speech onsets). It checks screen up by the first content word, each narrated action within ±300 ms of its spoken verb or object, result held ≥1.5 s after it is shown and named, no result named before it appears, A/V drift ≤40 ms, dropped frames, and stalled pictures. A freeze is a stalled picture **where the cue sheet expects change** (a screen change, an action, a result, an edit-list cut); a still picture inside a declared hold (from the result or last action to the end of the beat) passes and is listed as a `declared-hold` finding, however long it is. Never add scroll jiggles or cursor wobble to defeat the freeze check: that is what the pointer-path gate fails. It writes `qa/sync.json` bound to the candidate SHA-256 with per-beat findings and the checks it did **not** perform (text clipping needs tesseract; cursor continuity across cuts is never machine-checked; action times come from the capture receipt through the edit list, not from pixels). On FAIL, re-time, re-capture or re-render only the failing beats, then rerun every gate on the new encode. Word-level ASR is required; `--allow-degraded` is diagnostic and cannot release.
2c. **Frame integrity:** `scripts/validate-frame-integrity.mjs <jobRoot> <candidate.mp4>` — samples the encoded picture for tiled frames (a half-frame repeated, the concurrent-render defect) and luma jumps that are not at an edit-list cut. Writes `qa/frame-integrity.json` bound to the candidate. FAIL → re-render (serialize the render if it tiled).
2f. **Picture integrity** (the "morphed and cropped" gate): `scripts/validate-picture-integrity.mjs <jobRoot> <candidate.mp4>` — for every product clip in the compose map, the capture's native pixel size and aspect against the frame it occupies in the output: non-uniform scaling (stretch), any upscale past the capture's native pixels, a `sourceRegion` crop that removes UI edges (unless the cue plan declares it with a reason), pillarbox or letterbox bars inside the product frame, and a Recast punch-in that the cue plan did not declare or that was captured below device scale factor 2. It also holds the ratio rule: a 4:5 or 9:16 deliverable whose receipt shows a desktop viewport fails unless `job.json` declares `responsive: false` with a `responsiveException`. Per clip it records scale x/y, the crop box, bars and a verdict in `qa/picture-integrity.json` bound to the candidate. "No named UI leaves the frame" on a declared zoom is not machine-checked; the reviewer attests it. FAIL → re-capture at the delivery frame or at the ratio's own viewport; never fix it in compose.
2d. **Contact sheet:** `scripts/build-contact-sheet.mjs <jobRoot> <candidate.mp4>` — stills at every screen-on, action and result time from the cue sheet, tiled into `qa/contact-sheet.png` with `qa/contact-sheet.json` as the index. It is the reviewer's map for the human watch-through below; it does not replace it.
2e. **Marketing floor** (marketing cuts only): the reviewer writes `qa/marketing-readiness.json` (`marketing-readiness.md`) and `scripts/validate-marketing-readiness.mjs <jobRoot> <candidate.mp4>` holds it to the floor: hook on screen inside two seconds, one promise, designed motion and type, music bed and sound design carrying the pace, brand kit end card with one CTA inside the last eight seconds, ≥ 90% of cuts on the bed's grid, three cited reference ads, and the feed verdict "wins the viewer next to the references". Writes `qa/marketing-readiness-check.json` bound to the candidate. Below the floor the cut does not ship; no story score rescues it.
3. Voice: `qa/pronunciation-risk.json` (from `ai.ps1 voice pronunciation-risk`, written by `Generate-OwnerVoice.ps1`) with `coverage.status` PASS or REVIEW, and `qa/pronunciation-listen.json` with `finalStatus: PASS` (per-scene `ai.ps1 listen` grounded in transcript + risk slice). Then identity-score and `ai.ps1 listen` on the **encoded** candidate with `--transcript` and `--pronunciation-manifest qa/pronunciation-risk.json` (and `--timeline` above 90 s); the report must say `releaseEligible: true`. An ungrounded listen report is diagnostic only.
4. Story and craft on the encoded file: hook in the first five seconds, one promise, one hero moment, conversational narration that adds meaning the screen does not already show, pointer visible where an action happens and nowhere else, result on screen before or as it is spoken, no feature-tour opening, no long title cards, no build or version chip in any frame. Record the review as `qa/story-experience-review.json` (score, per-scene notes, `reviseSceneIds`). Score < 85 or any visual/pronunciation failure above → revise **those scenes only** and remux; do not restart writer → capture → TTS. The score cannot rescue a failed gate.
5. `scripts/validate-viewer-release.mjs <jobRoot> <candidate.mp4>` after **every** recut — it requires, bound to the exact candidate, the encoded-picture, sync, frame-integrity and picture-integrity reports, the pointer-path report bound to the receipt, the narration check, the marketing-readiness check on marketing cuts, captions, loudness, authored-script pronunciation, visual/title/action-result reviews, CTA and, when applicable, series evidence.

Final human-grade review, never skipped: watch and listen to the whole exact encoded file and check the contact sheet and every critical interaction against the cue-sheet timeline (screen already up at the line's first content word, cursor on the control as it is named, result readable after, the eye never asked to go back). The sync gate does not replace this. **Never say sync or visual quality is verified unless you inspected the rendered file and its audio; a successful render or a PASS report alone is not verification.** State limitations plainly in the handoff (e.g. "the architecture beat uses a guided highlight, not live UI"; "text clipping not machine-checked, no OCR").

Screen accuracy: every spoken product claim is visible in that beat's frames (`qa/screen-accuracy.json`). Mute test: `product-picture.md`. Do **not** use `Inspect-MediaVisualQuality.ps1` or a screenplay-only story score for this kind; the story-experience review below runs on the encoded file.

## 2. Other kinds

Briefings, training, explainers, talking-heads, animation, and audio-only do **not** run the four-domain screencast gate. They inherit the no-fluff and cursor rules unchanged. For those:

0. `scripts/validate-narration.mjs <jobRoot>` on the locked script (as 0b above) before any voice is rendered; a hit is a block.
1. Identity-score owner voice and `ai.ps1 listen` on the **exact encoded file**. Above 90 seconds, pass the canonical narration timeline with `--timeline <timeline.json>`; the Local-AI report must bind the original candidate and prove contiguous decoded-sample coverage across its scene-aligned reviews. Do not substitute separately exported clips.
2. Captions from the spoken words.
3. Require a current `story-experience-review.json` from the story-experience review below with `pass: true` (score ≥ `craftScoreMin`, default 85). If it is missing or failing, remit — do not treat identity/listen as a craft pass. A technical story or explainer with screen beats also needs the pointer-path PASS (1b) and the frame-integrity PASS (2c); a marketing cut of any kind needs the marketing floor (2e).
4. Engagement pass on the **encoded** file (not the screenplay): walk every scene and list stretches that are slow, repetitive, visually static, or emotionally flat per `engagement.md` Diagnose first. Missing hook, wall-to-wall static, rushed payoff, unducked bed, narration that reads the slide, anything said twice, or a cursor or highlight that moves while nothing is named is a fail — remit to the writer, storyboard, direction (`../media-studio/references/writer.md`, `storyboard.md`, `direction.md`), generate, or compose.
5. Run `Inspect-MediaVisualQuality.ps1` on the encoded file (`-ContactSheet` builds the cue-sheet contact sheet when a cue sheet exists). Suspects (static stretch, duplicate visual, undesigned first/last frame) go to the critic or director. Metrics flag; they do not replace judgment.

6. `scripts/validate-viewer-release.mjs <jobRoot> <candidate.mp4>` after **every** recut — it requires the exact candidate SHA on captions, loudness, authored-script pronunciation, visual/title/action-result reviews, the narration check, frame integrity, CTA and, when applicable, series evidence. Captions must be readable rather than paragraph blocks; ASR cannot be its own pronunciation reference.

Do not ship a product-screencast that failed scenario, narration, pre-flight, product-picture, pointer-path, exact-candidate, frame-integrity, picture-integrity, marketing-floor or encoded-file review.

## Story-experience review

Read-only craft critic for viewer-facing films against the **encoded** file. Product screencasts also require `product-picture.md`. You do not edit media.

Read: `../media-studio/references/story-review-rubric.md` and `engagement.md`; `marketing-readiness.md` when the job is a marketing cut; `story-craft.md` → "No fluff" and `cursor-flow.md` always. Ignore generator self-assessment.

A `qa/story-review.json` from `write-story-review.py` is a screenplay lint. It does not authorize capture, compose, or delivery. Product-screencast still requires `product-picture.md` and this review of the encoded file.

### 0. Before capture

This review cannot run before capture: it judges the encoded file. The writer's
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
`MALFORMED_INPUT`, never a pass. It writes `qa/story-review.json` (this review's schema) and a provenance
sidecar; nobody hand-writes a score. The rubric arithmetic is unchanged; the tool adds one rule of its
own, named in `reason`: a failed check the rubric gives no arithmetic for costs 15. Below 85 the writer
revises the scenes it names and reruns it before any capture starts. When the master exists, the encoded
critic runs on the file and supersedes
`qa/story-review.json` with `qa/story-experience-review.json`; that review, not the gate, is the craft pass.

### 1. Inputs

Encoded candidate, contact sheet (`qa/contact-sheet.png` + index from `build-contact-sheet.mjs`) or `Inspect-MediaVisualQuality.ps1` report, screenplay, storyboard, visual bible, captions/transcript, job.json, `qa/narration-check.json`, and `qa/pointer-path.json` when the film has screen beats.

If `job.kind` is `product-screencast`, also require a passing `validate-product-picture.mjs` result. A screenplay-only score is not a craft pass.

Missing or mutable inputs → `status: MALFORMED_INPUT`. Never pass a hole. The encoded candidate is required.

### 2. Judge

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

### 3. Marketing cuts: the feed test

When `job.json` is a marketing cut (`programForm` campaign-*, `marketing-cutdown`, `social-clip`, `hero`; `kind: teaser`; or `marketing: true`), the question is not "is it accurate and complete" but **"would this win the viewer in a feed next to the references?"** Write `qa/marketing-readiness.json` (schema `media-studio/marketing-readiness/1`, shape in `marketing-readiness.md`), bound to the exact candidate, with a timestamped verdict per criterion:

1. hook on screen inside two seconds (`hook.atSeconds`, what is on screen)
2. one promise, kept (`promise.text`, `count: 1`, evidence)
3. designed motion and type (evidence with timestamps)
4. music bed and sound design carrying the pace (`sound.bed`, `designCues`)
5. brand kit end card with one CTA inside the last eight seconds
6. cuts on the beat (`cutsOnBeat.bpm`, `offsetSeconds`)
7. three cited reference ads this cut competes against (title, source, why it wins)
8. the feed verdict: `attentionCompetition.winsAgainstReferences` with evidence from the first five seconds

Then run `scripts/validate-marketing-readiness.mjs <jobRoot> <candidate.mp4>`; it measures what it can (hook time, end-card window, cuts against the grid from the edit list, the narration check) and writes `qa/marketing-readiness-check.json`. Below the floor is `pass: false` with a `block` finding, whatever the story score. An honest `winsAgainstReferences: false` names the reference that beat it in `evidence` and sends the cut back to the writer / storyboard (`../media-studio/references/writer.md`, `storyboard.md`).

Explainers and technical stories are not judged against reference ads; they keep this rubric and inherit the no-fluff and cursor blocks above.

### 4. Output

`story-experience-review.json` matching `../../schemas/story-experience-review.schema.json`.

`pass` is true only when `status` is `COMPLETE`, `score >= craftScoreMin`, no `block` finding, and, for a marketing cut, `qa/marketing-readiness-check.json` is a PASS on this candidate.

### 5. Revision

If fail: producer reruns `findings[].owner` on `reviseSceneIds` only, re-encodes, then this review again. Do not skip to release. The `owner` values name the step guides: `media-writer` = `writer.md`, `media-storyboard` = `storyboard.md`, `media-director` = `direction.md`, `media-studio-visuals` = `visuals.md`; `media-studio-generate`, `media-studio-compose` and `media-studio` / `media-studio-qa` are skills. The schema enum keeps the older values for existing review files.

### 6. Final check

- [ ] Encoded file inspected, not inferred; contact sheet used for the walk-through
- [ ] Every finding has location, evidence, fix, owner
- [ ] Score arithmetic matches the rubric; no-fluff, redundancy and cursor blocks applied
- [ ] Marketing cut: readiness file written and its check is a PASS, or the review fails
- [ ] Fail below 85 even if identity/listen passed

## 3. Final check

- [ ] Encoded file, not a proxy clip; `qa/encoded-picture.json`, `qa/sync.json`, `qa/frame-integrity.json` and `qa/picture-integrity.json` present and ok for screencasts, all bound to this SHA-256
- [ ] Every product clip unscaled, uncropped, unstretched, without bars; every ratio from its own viewport; declared zooms only, captured at DSF ≥ 2, named UI stays in frame (attested)
- [ ] `qa/narration-check.json` PASS for the locked script; `qa/pointer-path.json` PASS bound to the receipt; `qa/capture-preflight.json` PASS
- [ ] Marketing cut: `qa/marketing-readiness-check.json` PASS on this candidate
- [ ] Watched and listened to the exact file with the contact sheet; limitations and not-performed checks reported
- [ ] Critic pass on viewer-facing jobs
- [ ] Product-screencast mute test and screen-accuracy pass; configuration claims have on-screen proof
- [ ] Visual-quality report present
- [ ] Diagnose-first list is empty or remitted
