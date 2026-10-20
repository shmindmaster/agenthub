# mvg: marketing video generator

One ad spec file in, gated 16:9 / 4:5 / 9:16 ads out. Source of truth: this folder. The runtime copy is
`%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit\marketing` (replaced, never merged, by
`scripts\Sync-MediaStudioKit.ps1`). Product-specific data (brand tokens, claim ledger, specs, job folders) lives in the
external media workspace, for ABACare `D:\Local-AI\data\artifacts\media-studio\abacare-marketing\`; product repositories are
read-only inputs.

```powershell
# from the deployed kit (or kit\marketing in a checkout); plain `node`, no windows, no npm install needed for lint/voice/assets
node mvg.mjs D:\...\abacare-marketing\specs\01-expired-authorization.json --stage lint
node mvg.mjs <spec> --dry-run                 # plan, planned spend, no provider call
node mvg.mjs <spec> --hosted-only             # lint, voice, timing, assets, capture check, compose PREPARE; no render, no local gates
node mvg.mjs <spec>                           # everything up to qa; deliver only when every required gate passed
node mvg.mjs <spec> --stage qa --local-gates  # adds local whisper + sync + Local-AI listen (GPU)
node mvg.mjs <spec> --only deliver
```

Exit 0 = ok, 1 = a stage failed closed (lint, budget, gate), 2 = usage. Every run writes `jobs\<spec id>\manifest.json`
(stage status, hashes, cost) and `cost-ledger.json`.

## Writing a spec (`ad.schema.json`)

| Field | Meaning |
| --- | --- |
| `id`, `title`, `product`, `audience`, `objective`, `concept` | Identity. `title` becomes the delivered file name. |
| `ratios`, `targetSeconds`, `beats` **or** `cuts[]` | One cut, or several cuts of the same ad with their own length and script (e.g. a 20 s `main` for 16x9 + 4x5 and a 12 s `vertical` for 9x16). A ratio belongs to exactly one cut. |
| `voice` | `provider` `elevenlabs` / `openai` / `local`, `voiceId`, `model`, `settings` (ElevenLabs `voice_settings` + `apply_text_normalization`; `eleven_v4` takes only `stability` and `similarity_boost`), `instructions` (OpenAI), `stitching` (previous_text / next_text), `pronunciationDictionaries`, `disclosure`. |
| `music` | `provider` `elevenlabs` / `none`, `prompt` (instrumental, never naming artists), `licenseBasis` (required), `bedDb` (default -24). |
| `beats[]` | `id`, `kind` `ui` / `broll` / `card` / `title`, `narration`, `onScreenText`, `emphasis[]`, `claims[]`, `minSeconds`, `ui {sourceJob, clipId, trimStart, trimEnd, focus[], actions[], freshness, record}`, `broll {provider, prompt}`, `sfx[] {cue, prompt, durationSeconds}`. A final `card` beat is the CTA end card. |
| `claims[]` | `id`, `text`, `phrases[]` (exact substrings of narration/on-screen text it substantiates), `kind`, `evidence`: `file:<path>[:line]`, `clip:<sourceJob>#<clipId>@<t0>-<t1>` (checked against the capture receipt) or `approved:<source>`. |
| `cta` | `text`, `url` (https), `displayUrl`, `claim`. |
| `labels` | Persistent on-screen label; must say SYNTHETIC and NO PHI. |
| `budget`, `qa` | Per-run caps; `qa.storyMin`, `qa.visionEverySeconds`, `qa.loudness`, `qa.required`. |

`ui.focus[]` gives explicit focus windows in clip seconds with the target's normalized position in the clip frame
(`x`, `y`), an optional `zoom` and `sourceZoom` (Recast punch-in already in the clip). It is required for any non-16:9 cut
when the clip has clicks, because Recast zooms around clicks and the pointer coordinates then no longer match the frame.
Clips without clicks may omit it: the pointer/point track drives the windows. `ui.actions[]` names the receipt actions the
spoken keywords land on (for the sync gate); `sfx[].cue` is `start`, `end`, `at:<seconds>` or `action:<receipt label>`.

The brand file (`brand.schema.json`) holds colors, fonts (files are loaded in the composition), safe zones per ratio,
`forbiddenNames` (prospects, customers, partners, competitors), extra `bannedPhrases`, cumulative and per-run `budgets`,
loudness targets, the vision and image models, the timing provider, the demo URL, the delivery folder and its
`reservedNumbers`.

## Stages (each cached by the hash of its inputs; `--force` ignores caches)

| # | Stage | What it does | Spend |
| --- | --- | --- | --- |
| 1 | `lint` | Schema, claims and evidence, narration/on-screen coverage, figures, banned phrases, forbidden names, people/children b-roll, voice and music policy, label, clip validity, length estimate, planned spend vs caps. Fails closed before any paid call. | none |
| 2 | `voice` | One line per narrated beat. ElevenLabs REST through the governed adapter (request stitching, versioned pronunciation dictionary, text normalization), OpenAI `gpt-4o-mini-tts` with `instructions`, or local Qwen (`ai.ps1 voice qwen-role`). Keyed by (text, voice, model, settings, neighbors). | ElevenLabs credits / OpenAI USD |
| 3 | `timing` | Word timings per line (OpenAI `whisper-1` word timestamps, or local whisper), the authored script aligned onto them, the voice-first timeline (scene = narration span + 0.35 s lead + 0.45 s tail), 4-7 word caption chunks, an SRT. Fails if a cut runs more than 1.5 s over target. | whisper-1 ~$0.006/min |
| 4 | `assets` | ElevenLabs sound effects and one ducked music bed (governed ledger), OpenAI `gpt-image` abstract stills, ElevenLabs video only if the API exposes it (it does not: recorded as skipped with the reason). Every generated asset is `aiGenerated: true` in `assets\manifest.json`. | credits / USD |
| 5 | `capture` | Reuses a receipt-bound clip (sha256 re-checked against its capture receipt) or records it with `record-job.mjs` (`ui.record` plus `--allow-capture`). | none |
| 6 | `compose` | Per ratio: layout, focus-follow camera, captions, compose map, FFmpeg mix plan, Remotion render of the `MarketingAd` composition (picture only), audio mix with the bed ducked under the voice, two-pass loudnorm (-14 LUFS social, -16 web) and the encode. `--prepare-only` writes `props.json`, `compose-map.json`, `mix-plan.json` and `render-command.json` and stops. | none (local CPU) |
| 7 | `qa` | On the exact encoded file: picture, captions, loudness, sync and Local-AI listen (`--local-gates`), OpenAI vision QA, the story score, `validate-viewer-release`. Anything that did not run on this candidate is `pending`, never a pass. | vision ~$0.1-0.3/ratio |
| 8 | `deliver` | Only if every required gate passed on the current file: copies to the library as `NN - Title (ratio).mp4` + `.srt`, updates the folder README table and per-film section, sha256 every file, deletes reproducible intermediates. | none |

The film number `NN` is computed at deliver time: one above every number used by a file, a README row or heading, or the
brand's `reservedNumbers`. It is claimed with an exclusive create, so a number is never reused.

## Truth rules (enforced, not advisory)

- Real captured UI carries every credibility-bearing second; a cut with no UI beat fails lint. No fabricated UI, dashboards,
  metrics, customers or testimonials; no generated people or children (b-roll prompts naming either fail lint); synthetic
  data only; the label stays on screen in every frame (vision QA checks it).
- Every narration sentence and on-screen text maps to a claim with checked evidence; any figure (digits or number words) must
  appear in a referenced claim. "Submitted to a payer" and payer-outcome language fail unless negated ("nothing is sent to a
  payer"). Ready to Bill is local readiness.
- Marketing narration is never the owner clone and never a celebrity sound-alike. OpenAI voices need a stated AI disclosure.
  Eleven Music needs a `licenseBasis` (its terms limit Creator to individual use and never name advertising; confirm in
  writing before paid media).
- Budgets: the per-run and the cumulative cap are checked before each paid call, and spend is recorded after it.
  ElevenLabs goes only through `packages/elevenlabs/scripts/elevenlabs_cli.py` (shared content ledger, reservation at about
  1.2x characters, receipts, no repeat purchase); run it with plain `python`, never `python -I`. Cumulative spend is in
  `_spend\ledger.jsonl`.

## Providers and costs (estimates round up; actuals are recorded when the provider returns them)

| Provider | Used for | Cost basis |
| --- | --- | --- |
| ElevenLabs `eleven_v4` (default) | Narration, request stitching works | 1 credit/char, reserved at 1.2x |
| ElevenLabs sound effects | UI ticks, chimes | reserved max(200, 40/s) credits |
| ElevenLabs Music `music_v2_5` | One instrumental bed per spec | 900 credits/min + 15% margin |
| OpenAI `whisper-1` | Word timings (hosted fallback to local whisper) | $0.006/min |
| OpenAI `gpt-image-2` | Abstract stills only (default quality medium) | ~$0.05 per 1536x1024 |
| OpenAI `gpt-5.6-sol` (brand `vision.model`) | Vision QA on sampled frames | $4 / $20 per 1M tokens |
| OpenAI `gpt-4o-mini-tts` | Optional narration with `instructions` | ~$0.02/min |
| ElevenLabs video, OpenAI video | Not used: ElevenLabs video is not exposed by the governed REST adapter; the Sora Videos API was shut down 2026-09-24 | |

## Composition and ratios

`kit/src/MarketingAd.tsx` (registered in `Root.tsx` as `MarketingAd`) renders the picture from props. The UI sits in a "UI
band" inside the platform-safe area (Reels/Shorts reserve the top 14% and bottom 35% of 9:16) cropped by a focus-follow
camera; kinetic captions (burned in, 4-7 words, the spoken word underlined, emphasis words in the accent color), the
persistent label and the CTA end card sit beside it, never over the focal point. Layout and crop math are plain JS
(`lib/layout.mjs`, `lib/crop.mjs`) so they are unit tested; the composition only draws.

| Ratio | Frame | UI band | Base zoom |
| --- | --- | --- | --- |
| 16x9 | 1920x1080 | 1920x944 at top, caption bar below | 1.15 |
| 4x5 | 1080x1350 | 1080x760, label above, captions below | 1.7 |
| 9x16 | 1080x1920 | 1080x610 inside the safe band (y 330-940), captions to y 1238 | 2.4 |

## QA gates (`qa/<ratio>/gates.json`)

| Gate | How | Needs |
| --- | --- | --- |
| `picture` | `lib/picture-gate.mjs`: UI band binds to the receipt-bound clip (dHash <= 12), no dead screen > 6 s, UI >= 70% of the cut, designed first/last frame | ffmpeg |
| `captions` | 4-7 words per cue, <= 2 lines of 42 characters, <= 20 characters per second, ordered | none |
| `loudness` | ffmpeg `loudnorm` on the exact file, within 1 LU of the target, true peak <= -1 dBTP | ffmpeg |
| `sync` | `build-cue-sheet.mjs` + `validate-sync.mjs` after local whisper on the encoded file | `--local-gates` (GPU) |
| `listen` | `ai.ps1 listen` Local-AI gate | `--local-gates` (GPU) |
| `vision` | `vision-qa.mjs`: a frame every 1.5 s to an OpenAI vision model with a rubric (overlay typos, unreadable text at phone size, banned claims, prospect names, missing label, captions over the focal point, people/children, fabricated UI); any high finding or a missing label fails | OpenAI |
| `story` | `media-story-experience-reviewer` score >= `qa.storyMin` (85) recorded in `qa/<ratio>/reviews.json` `storyReview` with a reviewer and `cta: true` | an agent review |
| `viewerRelease` | `validate-viewer-release.mjs` on the gate workspace in `qa/<ratio>/ws`, from `reviews.json` PASS entries (`encodedVisualReview`, `titleReview`, `actionResultReview`, `storyReview`, `pronunciation`) bound to the candidate | the reviews above |

## Deviations from the design brief (with reasons)

1. **Cuts.** One spec may carry several cuts because concept ads have different lengths per ratio. Top-level `ratios` /
   `targetSeconds` / `beats` still work for a single cut.
2. **Own picture gate.** `validate-encoded-picture.mjs` compares whole frames; an ad composites the UI into a band beside
   captions, so `lib/picture-gate.mjs` applies the same source-binding, dead-screen and first/last-frame tests to the band.
   `validate-viewer-release.mjs` accepts that report only for jobs whose `job.json` says `generator: media-studio/mvg`.
3. **Loudness.** The viewer-release gate hard-coded -16 +/- 1.5 LUFS; the social target is -14. `job.json` may now carry
   `loudnessTargetLufs` (mvg sets it per ratio); the default is unchanged.
4. **Audio outside Remotion.** The composition renders the picture only. Voice placement, sound effects, ducking
   (`sidechaincompress`), the two-pass loudness normalization and the mux are FFmpeg (`lib/mix.mjs`).
5. **ElevenLabs sound effects and music** were added to the governed adapter (`governed_audio.py`, `sfx` and `music`
   subcommands) so they use the same ledger, reservation and receipt rules as speech.
6. **Focus windows are piecewise static with eased transitions** so the encoded-picture binding can compare a stable crop
   at each beat midpoint. Recast zoom is declared with `sourceZoom` because the clip is already magnified there.
7. **No separate wordmark chip.** The persistent label is on screen in every frame, the product UI carries its own mark in
   16:9 crops and the end card names the product; a moving corner mark would sit on the UI.
8. **Campaign contract not used.** `campaign-short` is 10-20 s and the concept ads run to 25 s; mvg jobs use
   `programForm: outcome-workflow` and carry their own gates.

## Known limits

- Clips are captured at 1600x1000. A 9:16 crop is magnified about 1.3-2x; recapture at a 1080-wide portrait viewport for the
  sharpest vertical cut.
- Vision models miss small text; the vision gate is evidence, not the final read. Watch and listen to every encoded file.
- ElevenLabs `eleven_v4` ignores style and speed, so pacing comes from punctuation, the script and `stitching`.
- Pronunciation: the ABACare dictionary (`ABACare` to "A B A Care") is attached; the listen gate confirms it.
