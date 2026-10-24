---
name: media-studio-qa
description: Use when a media-studio candidate needs fail-closed screencast evidence, craft, a scored story-and-experience review, local audio perception, an engagement pass, domain review, arbitration, or final verification.
---

# Media studio QA

Load `../media-studio/references/engagement.md`, `story-craft.md` → "No fluff", `cursor-flow.md`, and `marketing-readiness.md` when the job is a marketing cut.

Four rules hold for every kind and no gate below outranks them: no fluff (every line earns its seconds; nothing spoken about synthetic data, versions, revisions or how the film was made); the feed test for customer-facing cuts (wins the viewer against references in the first five seconds); nothing redundant (one idea said once, no build or version chips); the cursor moves with purpose (only to the next thing named, one direction per beat, nothing moves that the narration is not about).

## 1. product-screencast

Fail-closed release. Gates run on source artifacts and the exact encoded candidate; a numeric craft score never overrides them. Native plugins resolve `scripts/` inside their installed package. Loose-skill hosts use `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools`; its `RELEASE-EVIDENCE.md` defines the evidence contract. Missing executables block release.

0. `scripts/validate-demo-scenario.mjs <jobRoot>` **before recording** — source-hashed synthetic scenario proof: persona, pain, hero action, visible outcome, coherent generic entity continuity, and CTA. Do not record a hard-coded or unverified authenticated path. A readiness handoff must prove the product resolves the intended workflow.
0b. `scripts/validate-narration.mjs <jobRoot>` **before recording** — no-fluff check on the locked script: every banned class (greeting, meta, recap, process, version, synthetic-data talk, jargon, filler), redundancy, lines that add nothing, hook and promise inside five seconds, synthetic disclosure as caption or end card. Writes `qa/narration-check.json` with fluff per minute and words-cut report. Any hit → back to the writer (`../media-studio/references/writer.md`); `write-story-review.py` and the viewer-release gate both require this PASS.
0c. Capture pre-flight inside `record-job.mjs` (`validate-capture-preflight.mjs`): scene ids across `scenes.mjs`, narration timeline, storyboard, capture plan and cue plan agree, every cue-plan keyword is in its line, typing fits the beat. `qa/capture-preflight.json` must be PASS; `recordings.preflight: skipped` is not.
1. `scripts/validate-product-picture.mjs <jobRoot>` — receipt-bound live captures, pointer motion, observed responses, Recast, no hidden freeze, ≥70% screen.
1b. `scripts/validate-pointer-path.mjs <jobRoot>` — receipt's move, wheel, click, point and type events per beat against the cue sheet: direction reversals, total travel against straight path through named targets, scroll reversals and scroll-past-and-return, moves not followed by a named action. Defaults: zero reversals, zero scroll returns, travel ≤ 1.35× direct, zero unnamed moves; a cue-plan `pointer` allowance needs a reason. Writes `qa/pointer-path.json` bound to the receipt. FAIL → re-record those beats.
2. `scripts/validate-encoded-picture.mjs <jobRoot> <candidate.mp4>` — every screen segment binds to its captured clip (dHash), no dead screen > 6 s in a screen beat, cards ≤ 8 s, designed first/last frames. Writes `qa/encoded-picture.json` bound to candidate SHA-256 and byte count. The viewer-release gate rejects lax static/source-binding thresholds and reads that exact PASS report; missing or failing → do not ship.
2b. **Forced word clock:** align each accepted take and the exact encoded candidate against their locked UTF-8 scripts with `ai.ps1 align <file> --script <script.txt> --output <qa/align/run-id/report.json>`. Keep raw `local-ai/forced-alignment/1` reports and their take/script hashes. Use reports to build cue words; put the encoded report at `qa/encoded-alignment.json`. Run `validate-word-sync.mjs <jobRoot> <candidate.mp4>` and `validate-sync.mjs` after `build-cue-sheet.mjs`. Whisper checks transcript text only; its onsets never set the clock. The aligner's 80 ms grid is reported honestly; canonical 40 ms offset/drift limits remain unchanged. Missing, stale or invalid alignment fails closed. This checks word onsets, not the proposed 2.1 rendered-pixel audit. Screen/action/result checks retain existing receipt-based limits. Declared holds are not blanket freeze waivers: watch the encoded file, report checks not performed.
2c. `scripts/validate-frame-integrity.mjs <jobRoot> <candidate.mp4>` — samples for tiled frames (half-frame repeated, concurrent-render defect) and luma jumps not at an edit-list cut. Writes `qa/frame-integrity.json` bound to candidate. FAIL → re-render (serialize if tiled).
2f. `scripts/validate-picture-integrity.mjs <jobRoot> <candidate.mp4>` — for every product clip in the compose map: non-uniform scaling, any upscale past native pixels, `sourceRegion` crop removing UI edges (unless cue plan declares with reason), pillarbox/letterbox bars inside product frame, Recast punch-in not declared or captured below device scale factor 2. Ratio rule: a 4:5 or 9:16 deliverable whose receipt shows a desktop viewport fails unless `job.json` declares `responsive: false` with `responsiveException`. Records scale x/y, crop box, bars and verdict in `qa/picture-integrity.json` bound to candidate. "No named UI leaves the frame" on declared zoom is not machine-checked; reviewer attests it. FAIL → re-capture at delivery frame or ratio's own viewport; never fix in compose.
2d. `scripts/build-contact-sheet.mjs <jobRoot> <candidate.mp4>` — stills at every screen-on, action and result time from cue sheet, tiled into `qa/contact-sheet.png` with `qa/contact-sheet.json` index. Reviewer's map for the human watch-through; does not replace it.
2e. **Marketing floor** (marketing cuts only): reviewer writes `qa/marketing-readiness.json` (`marketing-readiness.md`); `scripts/validate-marketing-readiness.mjs <jobRoot> <candidate.mp4>` holds to the floor: hook on screen inside two seconds, one promise, designed motion and type, music bed and sound design carrying pace, brand kit end card with one CTA inside last eight seconds, ≥ 90% of cuts on bed's grid, three cited reference ads, feed verdict "wins the viewer next to the references". Writes `qa/marketing-readiness-check.json` bound to candidate. Below the floor the cut does not ship; no story score rescues it.
3. Voice: `qa/pronunciation-risk.json` (from `ai.ps1 voice pronunciation-risk`, written by `Generate-OwnerVoice.ps1`) with `coverage.status` PASS or REVIEW, and `qa/pronunciation-listen.json` with `finalStatus: PASS` (per-scene `ai.ps1 listen` grounded in transcript + risk slice). Then identity-score and `ai.ps1 listen` on the **encoded** candidate with `--transcript` and `--pronunciation-manifest qa/pronunciation-risk.json` (and `--timeline` above 90 s); report must say `releaseEligible: true`. An ungrounded listen report is diagnostic only.
4. Story and craft on the encoded file: hook in first five seconds, one promise, one hero moment, conversational narration adding meaning the screen does not already show, pointer visible where an action happens and nowhere else, result on screen before or as spoken, no feature-tour opening, no long title cards, no build or version chip. Record as `qa/story-experience-review.json` (score, per-scene notes, `reviseSceneIds`). Score < 85 or any visual/pronunciation failure → revise **those scenes only** and remux; do not restart writer → capture → TTS. Score cannot rescue a failed gate.
5. `scripts/validate-viewer-release.mjs <jobRoot> <candidate.mp4>` after **every** recut — requires, bound to exact candidate: encoded-picture, sync, frame-integrity, picture-integrity reports, pointer-path bound to receipt, narration check, marketing-readiness check on marketing cuts, captions, loudness, authored-script pronunciation, visual/title/action-result reviews, CTA and, when applicable, series evidence.

Final human-grade review, never skipped: watch and listen to the whole exact encoded file; check contact sheet and every critical interaction against cue-sheet timeline (screen already up at line's first content word, cursor on control as named, result readable after, eye never asked to go back). Sync gate does not replace this. **Never say sync or visual quality is verified unless you inspected the rendered file and its audio; a successful render or PASS report alone is not verification.** State limitations plainly in handoff.

Screen accuracy: every spoken product claim visible in that beat's frames (`qa/screen-accuracy.json`). Mute test: `product-picture.md`. Do **not** use `Inspect-MediaVisualQuality.ps1` or a screenplay-only story score for this kind.

## 2. Other kinds

Hosted exact-file forced alignment may use the explicit verified
[hosted encoded alignment contract](references/hosted-alignment-clock.md).
Its provider uncertainty remains unknown; it does not claim the native80ms grid.

Briefings, training, explainers, talking-heads, animation, audio-only do **not** run the four-domain screencast gate. They inherit no-fluff and cursor rules unchanged.

0. `scripts/validate-narration.mjs <jobRoot>` on locked script before voice is rendered; a hit is a block.
1. Identity-score owner voice and `ai.ps1 listen` on the **exact encoded file**. Above 90 s, pass canonical narration timeline with `--timeline <timeline.json>`; Local-AI report must bind original candidate and prove contiguous decoded-sample coverage across scene-aligned reviews. Do not substitute separately exported clips.
2. Captions from spoken words.
3. Require current `story-experience-review.json` with `pass: true` (score ≥ `craftScoreMin`, default 85). Missing or failing → remit. A technical story or explainer with screen beats also needs pointer-path PASS (1b) and frame-integrity PASS (2c); a marketing cut needs the marketing floor (2e).
4. Engagement pass on the **encoded** file: walk every scene, list stretches that are slow, repetitive, visually static, or emotionally flat per `engagement.md`. Diagnose first. Missing hook, wall-to-wall static, rushed payoff, unducked bed, narration reading the slide, anything said twice, or cursor/highlight moving while nothing is named → remit to writer, storyboard, direction, generate, or compose.
5. Run `Inspect-MediaVisualQuality.ps1` on encoded file (`-ContactSheet` builds cue-sheet contact sheet when one exists). Suspects go to critic or director. Metrics flag; they do not replace judgment.
6. `scripts/validate-viewer-release.mjs <jobRoot> <candidate.mp4>` after every recut — requires exact candidate SHA on captions, loudness, authored-script pronunciation, visual/title/action-result reviews, narration check, frame integrity, CTA and, when applicable, series evidence. Captions must be readable rather than paragraph blocks; ASR cannot be its own pronunciation reference.

Do not ship a product-screencast that failed scenario, narration, pre-flight, product-picture, pointer-path, exact-candidate, frame-integrity, picture-integrity, marketing-floor or encoded-file review.

## 3. Story-experience review

Read-only craft critic for viewer-facing films against the **encoded** file. Product screencasts also require `product-picture.md`. You do not edit media.

Read: `../media-studio/references/story-review-rubric.md` and `engagement.md`; `marketing-readiness.md` for marketing cuts; `story-craft.md` → "No fluff" and `cursor-flow.md` always. Ignore generator self-assessment.

A `qa/story-review.json` from `write-story-review.py` is a screenplay lint. It does not authorize capture, compose, or delivery.

### 0. Before capture

This review cannot run before capture. The writer's pre-capture gate for **every** kind is `scripts/validate-narration.mjs` followed by `scripts/write-story-review.py` (working copies at `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools\`):

```text
node validate-narration.mjs <jobRoot>
python write-story-review.py <jobRoot> [--min 85] [--print]
```

It computes mechanical rubric checks from `story/screenplay.json` + `story/storyboard.json` (hook, hero, silence, before-state, repeats, designed frames, filler vocabulary, no-fluff, narration reading the card, type density) and reads judgment checks (audience, outcome, wiifm, progressive, one-idea, one-promise, studio-picture, trust) from `qa/story-judgments.json`, which the writer records with scene-cited evidence per check. Missing judgments file → `MALFORMED_INPUT`, never a pass. Writes `qa/story-review.json` and provenance sidecar; nobody hand-writes a score. A failed check the rubric gives no arithmetic for costs 15. Below 85 the writer revises named scenes and reruns before capture. When the master exists, the encoded critic supersedes with `qa/story-experience-review.json`; that review, not the gate, is the craft pass.

### 1. Inputs

Encoded candidate, contact sheet or `Inspect-MediaVisualQuality.ps1` report, screenplay, storyboard, visual bible, captions/transcript, job.json, `qa/narration-check.json`, and `qa/pointer-path.json` when the film has screen beats. If `job.kind` is `product-screencast`, also require passing `validate-product-picture.mjs`. Missing or mutable inputs → `status: MALFORMED_INPUT`. Never pass a hole. Encoded candidate is required.

### 2. Judge

Walk rubric checks against the **picture**, not screenplay. Cite timestamp or frame for every finding. Judge first five seconds as a stranger scrolling past.

Fail closed when: score < 85 (job `craftScoreMin`, default 85); any `block` finding; missing hook, missing hero, feature-tour opening, wall-to-wall static, unducked bed, narration reading the slide; `qa/narration-check.json` missing or failing; any spoken line about versions, revisions, what changed, how the film was made, or synthetic data; anything said twice; a card repeating the voice; a build/version/environment/revision chip in any frame; `qa/pointer-path.json` missing or failing on a film with screen beats; cursor or highlight moving while nothing is named, going back, or scrolling past and returning; `qa/picture-integrity.json` missing or failing on product footage (soft/upscaled, stretched, cropped at UI edge, barred, vertical cut plainly a desktop capture); on every declared punch-in, attest no named UI leaves the frame; marketing cut below the floor.

Prefer: `score: 78, pass: false, reviseSceneIds: ["s4","s7"], findings[0].owner: media-storyboard`. Avoid: `Looks pretty good.` / shipping because QA identity passed.

### 3. Marketing cuts: the feed test

When `job.json` is a marketing cut (`programForm` campaign-*, `marketing-cutdown`, `social-clip`, `hero`; `kind: teaser`; or `marketing: true`), the question is **"would this win the viewer in a feed next to the references?"** Write `qa/marketing-readiness.json` (schema `media-studio/marketing-readiness/1`, shape in `marketing-readiness.md`), bound to exact candidate, with timestamped verdict per criterion: hook on screen inside two seconds; one promise kept; designed motion and type; music bed and sound design carrying pace; brand kit end card with one CTA inside last eight seconds; cuts on beat; three cited reference ads; feed verdict `attentionCompetition.winsAgainstReferences` with evidence from first five seconds. Then run `scripts/validate-marketing-readiness.mjs`; below the floor is `pass: false` with `block` finding. An honest `winsAgainstReferences: false` names the reference that beat it and sends the cut back to writer/storyboard. Explainers and technical stories are not judged against reference ads.

### 4. Output

`story-experience-review.json` matching `../../schemas/story-experience-review.schema.json`. `pass` is true only when `status` is `COMPLETE`, `score >= craftScoreMin`, no `block` finding, and for marketing cuts `qa/marketing-readiness-check.json` is PASS on this candidate.

### 5. Revision

If fail: producer reruns `findings[].owner` on `reviseSceneIds` only, re-encodes, then this review again. Do not skip to release. Owner values: `media-writer` = `writer.md`, `media-storyboard` = `storyboard.md`, `media-director` = `direction.md`, `media-studio-visuals` = `visuals.md`; `media-studio-generate`, `media-studio-compose` and `media-studio` / `media-studio-qa` are skills. Schema enum keeps older values for existing files.

### 6. Final check

- [ ] Encoded file inspected, not inferred; contact sheet used
- [ ] Every finding has location, evidence, fix, owner
- [ ] Score arithmetic matches rubric; no-fluff, redundancy and cursor blocks applied
- [ ] Marketing cut: readiness file written and check is PASS, or review fails
- [ ] Fail below 85 even if identity/listen passed

## 4. Final check

For a deterministic edit of an already aligned film, see
[verified edit maps](references/edit-map-clock.md). This preserves the source
clock's uncertainty and requires exact final-file signal correspondence;
it never claims a new forced alignment.

- [ ] Encoded file, not proxy; `qa/encoded-picture.json`, `qa/sync.json`, `qa/frame-integrity.json`, `qa/picture-integrity.json` present and bound to this SHA-256
- [ ] Every product clip unscaled, uncropped, unstretched, without bars; every ratio from its own viewport; declared zooms only, captured at DSF ≥ 2, named UI stays in frame (attested)
- [ ] `qa/narration-check.json` PASS; `qa/pointer-path.json` PASS bound to receipt; `qa/capture-preflight.json` PASS
- [ ] Marketing cut: `qa/marketing-readiness-check.json` PASS on this candidate
- [ ] Watched and listened to exact file with contact sheet; limitations and not-performed checks reported
- [ ] Critic pass on viewer-facing jobs
- [ ] Product-screencast mute test and screen-accuracy pass; configuration claims have on-screen proof
- [ ] Visual-quality report present
- [ ] Diagnose-first list is empty or remitted
