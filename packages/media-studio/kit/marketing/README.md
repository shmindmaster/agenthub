# mvg: marketing video generator

One ad spec file in, gated 16:9 / 4:5 / 9:16 ads out. Source of truth: this folder. The runtime copy is
`%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit\marketing` (replaced, never merged, by
`scripts\Sync-MediaStudioKit.ps1`). Product-specific data (brand tokens, claim ledger, specs, job folders) lives in the
external media workspace under `MEDIA_STUDIO_ROOT` (default `D:\Media-Studio`), for ABACare `<MEDIA_STUDIO_ROOT>\abacare-marketing\`; product repositories are
read-only inputs.

```powershell
# from the deployed kit (or kit\marketing in a checkout); plain `node`, no windows, no npm install needed for lint/voice/assets
node mvg.mjs D:\...\abacare-marketing\specs\01-expired-authorization.json --stage lint
node mvg.mjs <spec> --dry-run                 # plan, planned spend, no provider call
node mvg.mjs <spec> --stage capture --hosted-only --whisper-timing # explicit hosted fallback; no render
node mvg.mjs <spec> --stage timing --whisper-timing # explicit fallback only when no forced aligner is available
node mvg.mjs <spec> --stage compose --candidate-id cut-01 --no-line-chips
node mvg.mjs <spec> --stage qa --candidate-id cut-01 # never composes
node mvg.mjs <spec> --stage deliver --candidate-id cut-01
```

Exit 0 = ok, 1 = a stage failed closed (lint, budget, gate), 2 = usage. Every run writes `jobs\<spec id>\manifest.json`
(stage status, hashes, cost) and `cost-ledger.json`, except external read-only QA, which writes only under `--qa-dir`.

For new OpenAI narration, pass `--narration-entity abacare|mahumtech|personal`
and `--narration-funding <file>` to any stage that generates voice. Use a single
dashboard evidence record with `entity`, `source: "dashboard"`, `observedAt`,
`availableUsd`, and `credentialSha256` from `narration-preflight.mjs fingerprint openai`.
The voice stage checks the exact model and the funding for all missing lines
before synthesis. It reserves funds in the shared local narration ledger. Retakes
using the same dashboard record subtract later charges and outstanding reservations.
Existing audio and dry runs can be used without evidence.

Compose reserves `compose/candidates/<id>` exclusively, even with `--force`. Recompose means a new ID.
QA and delivery require that ID and its compose receipt. To gate an existing file without writing source evidence:

```powershell
node mvg.mjs <spec> --stage qa --candidate-id retained-01 --candidate <ad.mp4> --candidate-sha256 <sha256> --compose-dir <original-build-dir> --ratio 9x16 --qa-dir <MEDIA_STUDIO_ROOT>\qa\qa-retained-01
```

Read-only external QA makes no paid call: paid vision is refused before a provider call because its cumulative spend
ledger would write the source workspace, so its vision gate stays pending. Explicit paid fallback remains available for
normal receipt-bound candidate QA. The QA directory must be outside the source job; alignment outputs stay inside it.
No copying to the delivery library occurs in QA.
`--no-line-chips`, `--no-captions`, or `render: { "lineChips": false }` disables burned caption chips, retaining the SRT.
Local AI is off (owner direction 2026-10-29): there is no local vision model, and the `local` vision default fails
closed (the gate stays pending). Vision QA uses paid OpenAI through `--vision-provider openai` or explicit
`brand.vision.provider: "openai"` and the normal budget ledger.

QA containment resolves symlinks/junctions, even for a new output directory. Its receipt binds the sidecar SRT hash
as well as the MP4; changed or missing subtitles block delivery. An unencoded prepared candidate writes pending gates.
Isolated compose/QA/delivery dry runs are rejected; use `--stage capture --dry-run` for lint and planned-spend checks.

Timing aligns each accepted narration take to its authored text with the forced-aligner provider. Local AI is off: the
local aligner is retired and the default refuses, naming the hosted route (`kit/cloud/cloud-ai.mjs align`, an
ASR-anchored report that clocks the picture only where `job.json` sets `clockPolicy.allowAsrAnchored: true`).
Take/script-bound reports already on disk under the existing `timing\<cut>\asr` receipt paths are reused and still drive
timelines, captions and action trims. `--whisper-timing` is the explicit hosted compatibility fallback (OpenAI
`gpt-transcribe`) for a job without an aligner, including an existing 2.0.4 or 2.0.5 timeline; compose otherwise refuses a
non-aligned clock. QA independently aligns the exact encoded candidate only when an aligner is provided; otherwise the
sync, word-sync and transcript gates stay pending. A transcript checks text and never supplies the default timing clock.
The 80 ms output grid is not a claim of 40 ms acoustic accuracy. This is not the proposed 2.1 pixel/render sync audit.

### Migrating a 2.0.4 runner or retained encode

Replace no-stage or `--stage all` runners with separate preparation (`--stage capture`), compose, QA and delivery
invocations. Give each new compose a fresh candidate ID; a prepared ID is reserved and cannot be composed again.
For an existing encode without `candidate.json`, use the external QA command above with its exact SHA-256, original
compose metadata and ratio. Keep the old job read-only. Old PASS receipts do not authorize release: rerun the required
gates, including `wordSync` and `transcript`, and obtain exact-candidate reviews. QA measures existing captions; it does
not retime them. The separate production timing-stage follow-up is not part of this repair.

## Choose creativeMode before writing the film

Media Studio is **not** a single-product proof-of-feature generator. The
`mvg` marketing-ad lane accepts `creativeMode`:
`verified-demo` (default for legacy ads), `hybrid`, `future-vision`,
`concept-film`, `fictional-story`, `explainer`, `documentary`,
`educational`, and `abstract`. It accepts optional beat
`truthStatus: verified|proposed|fictional|illustrative`.

A **verified demo** must support present-tense claims with real captured UI
evidence. Its pre-spend 25s+ story lint checks scenario, clear product
introduction, actual mechanism, outcome and CTA. A 10–24s verified teaser
can compress to hook → real UI proof → CTA. These are verified-demo
standards, **not a universal screenplay formula**.

All other forms are free to start at the climax, tell a fictional day in
the life, depict an imagined future, use an abstract rhythmic structure,
or follow a documentary's evidence trail. They do **not** require six
ordered beats, a genuine current product clip, a software name in the
opening, a mandatory conflict/hero at a fixed timestamp, or a generated
person's age to meet a particular rule. The final reviewer judges the
declared film's goals, story quality, truthfulness of real claims and
actual visible result.

### Realistic people, patients and synthetic interfaces

Fictional people, invented settings and imagined screens are valid
creative assets. Two things decide what a given film may show, and
neither is shared code:

- **The product's policy.** A brand file may set `generatedPeople` to
  `any` (default), `adults-only` or `none`. `product-profiles.json`
  holds the standing policy of a product that needs one.
- **Classification.** In a film about the current product, a generated
  person carries `truthStatus: fictional` or `illustrative` (or a
  `broll.actor.kind`), so nobody is shown an invented person as a real
  customer or patient. A captured product screen is always a statement
  about the product today and cannot be relabelled as fiction.

No blur, anonymization mask or ban on readable text is imposed on
synthetic media.
An actor may optionally have `broll.actor` metadata (role, ageGroup,
character continuity). Legacy `noPatientOrMinor` metadata is not an
active restriction.

A proposed interface in `future-vision` or `concept-film` may be
shown in full. In `hybrid`, identify it as `truthStatus: proposed`
(or `fictional|illustrative`) and mark `broll.depictsProductUI: true`
so it is not mistaken for current-functionality proof. Use
`conceptDisclosure` or a clear film-level phrase such as
"Concept visualization" or "Envisioning what's possible". **A film-level
disclosure need not be a permanent watermark, blurred scene, or an
audio interruption.** Keep the invented content visually excellent.

A fictional hospital/clinic encounter is not automatically a
testimonial, a real medical record or a currently shipped capability.
A verified factual claim, in contrast, still needs its source or
real product capture. Licensed real-person portrayals require ordinary
rights/consent. No real patient/customer data goes to an unapproved
provider.

**Example: future-world experience** — Show a clear, realistic synthetic
family entering a future clinic, a fully legible imagined planning
dashboard, an AI-supported interaction, then how the day changes for
the fictional characters. This can be the *entire film*. It is not a
working software demonstration unless separately backed by real
capture and truth-status evidence.

For a general documentary, education program, dramatic or abstract film
without a marketing CTA, use the wider `studio`/`video` development and
composition workflow rather than pretending `mvg`'s ad spec is a
universal film file format. See `skills/studio/references/creative-formats.md`.

### Production constraints are not creative constraints

The `mvg` b-roll asset stage currently supports configured OpenAI image
generation, accepted stock files and the historical ElevenLabs-video
stub. Public Runware models cannot be activated simply by changing an
environment variable; each must have a model-correct, priced, governed
adapter. That is an implementation gap, **not** a ban on synthetic
people, scenes or future product screens.

## Writing a spec (`ad.schema.json`)

| Field | Meaning |
| --- | --- |
| `id`, `title`, `product`, `audience`, `objective`, `concept` | Identity. `title` becomes the delivered file name. |
| `ratios`, `targetSeconds`, `beats` **or** `cuts[]` | One cut, or several cuts of the same ad with their own length and script (e.g. a 20 s `main` for 16x9 + 4x5 and a 12 s `vertical` for 9x16). A ratio belongs to exactly one cut. |
| `voice` | `provider` `elevenlabs` / `openai` / `import` (narration made elsewhere, see Imported narration below; `local` is retired: Local AI is off and it refuses), `voiceId`, `model`, `settings` (ElevenLabs `voice_settings` + `apply_text_normalization`; `eleven_v4` takes only `stability` and `similarity_boost`), `instructions` (OpenAI), `stitching` (previous_text / next_text), `pronunciationDictionaries`, `disclosure`. |
| `music` | `provider` `elevenlabs` / `none`, `prompt` (instrumental, never naming artists), `licenseBasis` (required), `bedDb` (default -24), `lengthSeconds` (optional, >= 3). By default the bed is the longest cut plus 2 s, so every job of a different length buys a new track; `lengthSeconds` fixes it, so jobs with the same prompt, model and length make an identical request and reuse one track in the governed adapter. It must be at least the longest cut plus 2 s (lint checks it against the target, the assets stage against the measured timeline); the mix trims the bed to the program (`atrim`) and fades it out inside it, so a longer bed never lengthens the film. |
| `beats[]` | `id`, `kind` `ui` / `broll` / `card` / `title`, `narration`, `onScreenText`, `emphasis[]`, `claims[]`, `minSeconds`, `ui {sourceJob, clipId, trimStart, trimEnd, focus[], actions[], freshness, record}`, `broll {provider, prompt}`, `sfx[] {cue, prompt, durationSeconds}`. A final `card` beat is the CTA end card. |
| `claims[]` | `id`, `text`, `phrases[]` (exact substrings of narration/on-screen text it substantiates), `kind`, `evidence`: `file:<path>[:line]`, `clip:<sourceJob>#<clipId>@<t0>-<t1>` (checked against the capture receipt) or `approved:<source>`. |
| `cta` | `text`, `url` (https), `displayUrl`, `claim`. Required unless the spec declares a `filmType` with no cta slot (not `product-marketing` or `founder-pitch`); an undeclared `filmType` still requires it, and a beat with the `cta` role always does. |
| `labels` | The film's disclosure line, shown on the end card. What it must contain is the product's rule: `brand.disclosure.mustInclude`, or the product's entry in `product-profiles.json` (ABACare: SYNTHETIC and NO PHI). A spec that sets `syntheticData` must say "synthetic". |
| `edit.beatGrid` | Optional `{ bpm, offsetSeconds }`: the music bed's tempo, so the marketing-readiness floor (>= 90% of cuts within 80 ms of the beat) can be met. The bed plays from program time 0, so beats fall at `offsetSeconds + n * 60/bpm` for any whole `n` (the offset is the bed's phase). After the voice-first timeline is built, every scene boundary except the program start is moved to the next beat at or after its natural end by lengthening that scene's tail hold only (never shortening, each extension under one beat); narration keeps its place inside its scene and everything after shifts with it (`startSeconds`, `lineStartSeconds`, word and caption times), so the film grows by the added holds. Each boundary is then moved to a whole frame (30 fps: the nearest frame to the beat, never earlier than the scene's natural end, so a cut sits within one frame of the beat), so the edit list, the captions and the gates name the frames the picture cuts on; MarketingAd lays consecutive beats out from one shared rounded boundary, so no frame belongs to no beat (no black frame at a cut). Keep it out of `music` (the bed's cache key is its prompt, length and model) and put the tempo in the music prompt yourself. It keys the `timing` stage (a change re-times with the cached ASR, no new spend), is written to `timeline.json` and to `compose-map.json` as `beatGrid`, and a UI beat's longer hold must still be covered by its clip (compose refuses a hold over the limit). |
| `budget`, `qa` | Per-run caps (`elevenlabsCredits`, `openaiUsd`, `assemblyaiUsd`, `deepgramUsd`, `runwareUsd`, `azureUsd`; brand `budgets` takes the same keys as cumulative caps, and a USD provider with no cap configured refuses new spend); `qa.storyMin`, `qa.visionEverySeconds`, `qa.loudness`, `qa.required`. |

`ui.focus[]` gives explicit focus windows in clip seconds with the target's normalized position in the clip frame
(`x`, `y`), an optional `zoom`, `sourceZoom` (Recast punch-in already in the clip) and `declaredZoom` (the cue sheet
declares this zoom). Without a declared zoom every window shows the whole native recording; the integrity check fails any
other crop. `ui.actions[]` names the receipt actions the
spoken keywords land on (for the sync gate); `sfx[].cue` is `start`, `end`, `at:<seconds>` or `action:<receipt label>`.

The brand file (`brand.schema.json`) holds colors, fonts (files are loaded in the composition), safe zones per ratio,
`forbiddenNames` (prospects, customers, partners, competitors), extra `bannedPhrases`, cumulative and per-run `budgets`,
loudness targets, the vision and image models, the timing provider, the demo URL, the delivery folder and its
`reservedNumbers`.

## Stages (each cached by the hash of its inputs; `--force` ignores caches)

| # | Stage | What it does | Spend |
| --- | --- | --- | --- |
| 1 | `lint` | Schema, claims and evidence, narration/on-screen coverage, figures, banned phrases, forbidden names, people/children b-roll, voice and music policy, label, clip validity, length estimate, planned spend vs caps. Fails closed before any paid call. | none |
| 2 | `voice` | One line per narrated beat. ElevenLabs REST through the governed adapter for an owner-authorized job (request stitching, versioned pronunciation dictionary, text normalization) or OpenAI Realtime with `instructions` and live narration preflight. Keyed by (text, voice, model, settings, neighbors). | ElevenLabs credits / OpenAI USD |
| 3 | `timing` | Forced alignment of each accepted take and authored line, the voice-first timeline (scene = narration span + 0.35 s lead + 0.45 s tail), 4-7 word caption chunks, an SRT; with `edit.beatGrid`, scene boundaries are then held to the bed's beats. No current hosted model returns word timestamps, so timing always uses the forced aligner. Fails if a cut runs more than 1.5 s over target. | aligner provider |
| 4 | `assets` | Sound effects and a music bed go through the governed adapter's `sfx` and `music` lanes for an owner-authorized job, and fail closed without its manifest. OpenAI `gpt-image` abstract stills, ElevenLabs video only if the API exposes it (it does not: recorded as skipped with the reason). Every generated asset is `aiGenerated: true` in `assets\manifest.json`. | credits / USD |
| 5 | `capture` | Reuses a receipt-bound clip (sha256 re-checked against its capture receipt) or records it with `record-job.mjs` (`ui.record` plus `--allow-capture`). | none |
| 6 | `compose` | Per ratio: layout, focus-follow camera, captions, compose map, FFmpeg mix plan, Remotion render of the `MarketingAd` composition (picture only), audio mix with the bed ducked under the voice, two-pass loudnorm (-14 LUFS social, -16 web) and the encode. `--prepare-only` writes `props.json`, `compose-map.json`, `mix-plan.json` and `render-command.json` and stops. | none (local CPU) |
| 7 | `qa` | Selects a named, hash-verified candidate without composing: picture, captions, loudness, sync, forced word-sync and independent transcript (only with a provided aligner and encoded transcript), listen (no runner: pending), vision, marketing, story and viewer-release. Missing checks stay pending. | explicit `--vision-provider openai` is paid |
| 8 | `deliver` | Verifies the named candidate and every required gate's SHA, then copies MP4/SRT and updates the library index. Candidate evidence is retained. | none |

The film number `NN` is computed at deliver time: one above every number used by a file, a README row or heading, or the
brand's `reservedNumbers`. It is claimed with an exclusive create, so a number is never reused.

## Truth rules (enforced, not advisory)

- In a `verified-demo` film, real captured UI carries every credibility-bearing second and a cut with no UI beat fails
  lint. A generated interface is never proof of current behaviour, and a captured interface is never fiction.
- A beat is **factual** when it is captured UI, is marked `verified`, belongs to a verified demo, or names the product in a
  form that states facts (explainer, documentary, educational, hybrid). Every factual sentence and on-screen text maps to
  a claim with checked evidence; any figure (digits or number words) must appear in a referenced claim. Declaring another
  `creativeMode` does not change this.
- Guarantees, superlatives, testimonials and unsubstantiated comparisons fail in factual beats for every product. Industry
  wording is a named policy the product opts into: `brand.claimPolicies: ["healthcare-payer"]` fails "submitted to a payer"
  and payer-outcome language unless negated ("nothing is sent to a payer").
- A film that shows proposed capability says so (`conceptDisclosure` or `labels`), in words that mean "not current": a
  product name or a slogan containing "vision" or "future" does not count.
- The disclosure line a product requires is checked in lint, in the narration gate and by the frame reviewer, in every
  creative mode.
- Marketing narration is never the owner clone unless `voice.ownerVoice` is true, that job's immutable owner manifest names the voice, and `voice.disclosure` states it. Never a celebrity sound-alike. OpenAI voices need a stated AI disclosure. The delivery note denies an owner voice only for OpenAI stock voices.
  Eleven Music needs a `licenseBasis` (its terms limit Creator to individual use and never name advertising; confirm in
  writing before paid media).
- Budgets: the per-run and the cumulative cap are checked before each paid call, and spend is recorded after it.
  ElevenLabs speech goes only through the governed adapter named by `MVG_ELEVENLABS_CLI`, with the job's owner manifest in `MVG_ELEVENLABS_AUTHORIZATION` (`skills/produce/references/content-controls.md`). The `sfx` and `music` lanes take their own manifests in `MVG_ELEVENLABS_SFX_AUTHORIZATION` and `MVG_ELEVENLABS_MUSIC_AUTHORIZATION` — each manifest's `kind` matches exactly one lane. Without both it fails closed. The job's ledger holds a reservation at about
  1.2x characters, receipts and no repeat purchase; run it with plain `python`, never `python -I`. Cumulative spend is in
  `_spend\ledger.jsonl`.

## Providers and costs (estimates round up; actuals are recorded when the provider returns them)

| Provider | Used for | Cost basis |
| --- | --- | --- |
| ElevenLabs `eleven_v4` (explicitly authorized) | Narration, request stitching works; `dialogue` lane for multi-voice scenes | Speech reserves 1.2x characters and checks the account's current rate and credits |
| ElevenLabs sound effects (`eleven_text_to_sound_v3`), ElevenLabs Music (`music_v2_5`, instrumental) | Owner-authorized jobs only through the governed adapter, each with its own manifest and epoch | 200 credits/generation; 900 credits/minute |
| OpenAI `gpt-transcribe` | Transcript check (text) | ~$0.27/hr |
| OpenAI `gpt-image-2.6-flare` (default; `gpt-image-2.6-sunburst` for hero and precise edits) | Abstract stills only (default quality medium) | ~$0.07 per 1536x1024 (padded estimate, unverified; token-priced) |
| OpenAI `gpt-6.1-terra` (brand `vision.model`) | Vision QA on sampled frames | $1 / $5 per 1M tokens |
| OpenAI `gpt-realtime-2.1-mini` (marin, cedar) through the Realtime API | Optional narration with `instructions` | ~$0.024/min |
| ElevenLabs video, OpenAI video | Not used: ElevenLabs video is not exposed by the governed REST adapter; there is no OpenAI video route | |

## Voice-first alignment

`ui.actions` names the receipt actions the voice talks about. The first one is cut onto its spoken keyword (digits and number
words match: "twelve" finds "12"), so `ui.trimStart` is only a fallback; the beat is lengthened so the result holds at least
1.6 s after the last narrated action. The compose map records the timeline word clock, timing receipt hash, trim source,
and matched action/word anchor; unmatched-action fallback warnings are also persisted. Every other receipt action inside the beat's window is written to the cue plan as
`narrated: false`. Caption cues are held or started earlier into the surrounding gaps so none exceeds 18 characters per second.
A capture expectation ("the product responded") stands as a beat's result only if it is visible inside the beat and holds >= 1.5 s; one up to 0.5 s short lengthens the beat, any other is left out of the cue plan (so it is never stamped after the beat). The per-line ASR copy in the gate workspace is shifted by the lead-in so keyword times match where each line is placed. Vision frames are sampled at least 0.25 s from a caption cue start or end. A reviewer may add `qa/<ratio>/vision-arbitration.json` `{candidateSha256, reviewer, items:[{frame, category, verdict:"false-positive", reason}]}`; it counts only when it names the current candidate hash, is recorded in `gates.json`, and is never written by mvg. The listen gate has no runner while Local AI is off, so it stays pending (see QA gates).
A focus window magnified by a Recast punch-in (`sourceZoom`) gets a wider crop so the total magnification stays at or under
3x; any magnification of recorded pixels then still fails the integrity check unless the recording was made at device scale.

## Composition and ratios

`kit/src/MarketingAd.tsx` (registered in `Root.tsx` as `MarketingAd`) renders the picture from props. Each ratio is its
own native capture at a viewport of that aspect (16:9 desktop web recorded at 1920x1080, 4:5 web at a tablet or
large-phone layout recorded at 1080x1350, 9:16 the mobile app or phone web at 1080x1920), so the product picture fills
the frame at scale 1.0: no UI band, no crop, no bars, no upscale. `lib/integrity.mjs` checks every product window on
each compose and stops it on a stretch, an aspect mismatch (bars), an upscale (soft text) or a crop the cue sheet did not
declare (`ui.focus[].declaredZoom`, allowed only on a device-scale recording so the zoomed region keeps one recorded pixel
per output pixel); the result is written to `compose-map.json` as `integrity`. Kinetic captions (burned in, 4-7 words,
balanced over explicit line breaks of at least two words, the spoken word bold as well as bright, emphasis words in amber)
sit on their own navy plate over the picture inside the platform-safe area (Reels/Shorts reserve the top 14% and bottom
35% of 9:16) and are hidden on title and card beats. A `title` beat is the hook: its headline lands word by word in big
type on brand colour. The `card` end card carries the logo lockup (`brand.logo`), the line the film ends on, the CTA (amber
pill, navy text) and, as one small line at its foot, the synthetic-data label and any AI-voice disclosure; that is the only
place the label appears. Layout math is plain JS (`lib/layout.mjs`, `lib/integrity.mjs`) so it is unit tested; the
composition only draws.

| Ratio | Frame | Product picture | Caption plate |
| --- | --- | --- | --- |
| 16x9 | 1920x1080 | full frame, native 1920x1080 recording | one line, x 96, y 924 |
| 4x5 | 1080x1350 | full frame, native 1080x1350 recording | up to two lines, y 1110 |
| 9x16 | 1080x1920 | full frame, native 1080x1920 recording | up to two lines, y 1030 (above the bottom 35%) |

The music bed sits about 12 dB below its mastered level with a light 3:1 duck under the voice, so it carries the pace;
narration that spends words on the demo data or on the film itself (`synthetic`, `in this video`, ...) fails lint.

## QA gates (`qa/<ratio>/gates.json`)

`integrity`, `pointer`, `frameIntegrity` and `marketing` are always required (a spec's `qa.required` cannot drop them), so `deliver` refuses a ratio unless all three passed on the current file.

| Gate | How | Needs |
| --- | --- | --- |
| `picture` | `lib/picture-gate.mjs`: UI band binds to the receipt-bound clip (dHash <= 12), no dead screen > 6 s, UI >= 70% of the cut, designed first/last frame | ffmpeg |
| `integrity` | `validate-picture-integrity.mjs <ws> <candidate> --compose-map <ws compose map> --out <ws>/qa/picture-integrity.json` (media-studio 2.0.0): every product clip at its native scale (no upscale, stretch, bars or undeclared crop or zoom), and a 4:5 / 9:16 cut recorded at its own frame. The ws `job.json` carries `deliveryProfile` and `captureViewports` (`4:5` 1080x1350, `9:16` 1080x1920; 16:9 is unconstrained); an authored `ui.focus[].declaredZoom` is declared in `story/cue-plan.json`, nothing else is. Pass or fail is the script's exit code and report | ffmpeg |
| `pointer` | `validate-pointer-path.mjs <ws> --out <ws>/qa/pointer-path.json` on the ws `capture/receipt.json`, which carries each used clip's full action log. When the sync gate ran, its freshly built mapped `plan/cue-sheet.json` is passed, so only the footage on screen is judged per beat; without it the whole clips are judged and the detail says so | none (more exact when the sync gate ran) |
| `frameIntegrity` | `validate-frame-integrity.mjs <ws> <candidate> --out <ws>/qa/frame-integrity.json`: no tiled frame (the picture repeated in two halves) and no luma jump that is not a declared cut. Declared cuts come from the mapped `plan/cue-sheet.json` that the sync gate builds, else from mvg's own compose map (the cuts the edit plans), so a hard cut from a light title to dark UI is declared and a flash anywhere else fails. `validate-viewer-release` reads the report from the workspace `qa/` | ffmpeg |
| `marketing` | `validate-marketing-readiness.mjs <ws> <candidate> --readiness <ws>/qa/marketing-readiness.json` (the ws `job.json` says `marketing: true`; `programForm` stays `outcome-workflow`). A reviewer writes `qa/<ratio>/marketing-readiness.json` (`skills/finish/references/marketing-readiness.md`, `candidate.sha256` and `bytes` of this exact `ad.mp4`); mvg never writes it, copies it into the ws only when it names this candidate, and reports `pending` (not fail) when it is absent or bound to another render. The floor includes the no-fluff rule, so mvg runs `validate-narration.mjs` on the ws first (`qa/narration-check.json`) | an agent review |
| `captions` | 4-7 words per cue, <= 2 lines of 42 characters, <= 20 characters per second, ordered | none |
| `loudness` | ffmpeg `loudnorm` on the exact file, within 1 LU of the target, true peak <= -1 dBTP | ffmpeg |
| `sync` | `build-cue-sheet.mjs` + `validate-sync.mjs` using aligned word timings, never transcript onsets | a provided aligner (hosted: `cloud-ai.mjs align` with the `clockPolicy` opt-in); pending otherwise |
| `wordSync` | Alignment bound to the exact encoded candidate and locked script, retaining the raw 80 ms grid and canonical 40 ms sync tolerance | a provided aligner; pending otherwise |
| `transcript` | Independent transcript text compared with the locked script; numeric values preserved, onsets discarded | a provided encoded transcript; pending otherwise |
| `listen` | Retired with Local AI (owner direction 2026-10-29). mvg has no hosted listen runner, so the gate stays `pending` and `deliver` refuses a ratio that requires it | no runner |
| `vision` | `vision-qa.mjs`: a frame every 1.5 s to the vision model, with a rubric (overlay typos, unreadable text at phone size, banned claims, prospect names, missing label, captions over the focal point, people/children, fabricated UI); any high finding or a missing label fails. Explicit paid OpenAI requires the governed ledger through `mvg --stage qa`; standalone paid CLI calls are refused. The `local` default fails closed (Local AI is off) | paid OpenAI, explicit opt-in |
| `story` | `review` skill story-experience review score >= `qa.storyMin` (85) recorded in `qa/<ratio>/reviews.json` `storyReview` with a reviewer and `cta: true` | an agent review |
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
5. **ElevenLabs sound effects and music** left with `packages/elevenlabs` (retired 2026-10-30). In 2.9.0 the governed
   adapter grew `sfx` and `music` lanes (`eleven_text_to_sound_v3`, `music_v2_5`), so `soundEffect` and `music` run
   owner-authorized jobs through the same manifest, reservation and receipt controls as speech.
6. **Focus windows are piecewise static with eased transitions** so the encoded-picture binding can compare a stable crop
   at each beat midpoint. Recast zoom is declared with `sourceZoom` because the clip is already magnified there.
7. **No chip over the product picture.** The synthetic-data label is one line on the end card, beside the logo and the
   CTA (owner direction, 2026-10-20); a persistent chip read as an internal explainer.
8. **Campaign contract not used.** `campaign-short` is 10-20 s and the concept ads run to 25 s; mvg jobs use
   `programForm: outcome-workflow` and carry their own gates.

## Known limits

- Clips are captured at 1600x1000. A 9:16 crop is magnified about 1.3-2x; recapture at a 1080-wide portrait viewport for the
  sharpest vertical cut.
- Vision models miss small text; the vision gate is evidence, not the final read. Watch and listen to every encoded file.
- ElevenLabs `eleven_v4` ignores style and speed, so pacing comes from punctuation, the script and `stitching`.
- Pronunciation: the ABACare dictionary (`ABACare` to "A B A Care") is attached; the transcript gate confirms it.

## Film types and the story gate

`lib/story-profiles.mjs` keys the story rules by `filmType`, so a film is judged by the parts its own form needs. Set
`filmType` on the spec or on one cut; without it the type follows `creativeMode` (a verified demo or hybrid is
`product-marketing`).

| `filmType` | Beats, in order | Brief (`narrative`) |
| --- | --- | --- |
| `product-marketing` | hook, context, problem, solution (product named), demonstration, payoff, cta | persona, situation, trigger, problem, stakes, solution, mechanism, payoff, emotionalBefore, emotionalAfter, viewerValue, plus `hookPlan` |
| `product-marketing` under 25 s | hook, demonstration, cta; product named in the first two beats | none |
| `feature-demo` | context, demonstration, payoff | persona, problem, payoff |
| `tutorial` | goal, step, payoff | goal |
| `explainer` | hook, explanation, takeaway | question, viewerValue |
| `social-cut` | hook, demonstration, then a payoff or a cta | none |
| `founder-pitch` | hook, problem, solution, proof, cta | problem, solution, ask |
| `internal-update` | context, demonstration, next-step | change |
| `story` | free order | persona, situation, emotionalBefore, emotionalAfter |
| `non-narrative` | free order | none; `organizingPrinciple` is required |

A cut under ten seconds keeps only the ordinary gates. Thresholds use the longer of `targetSeconds` and the estimate.

Role and field names accept the wording of a planning document: `problem and stakes`, `product introduction`,
`call to action`, `beforeState`, `afterState`, `firstVisual`, `spokenLine`.

**Waiving a rule.** Each finding has a rule id such as `story.cta-last`. A spec may waive story rules:

```json
"storyOverrides": [{ "rule": "story.cta-last", "reason": "Owner 2026-11-10: plays inside the product page, which carries the button." }]
```

The finding becomes a `story-override` warning that names the rule and the reason. Only `story.*` rules can be waived;
truth and evidence rules cannot. A spec written before the story gate either adds `storyRole` to its beats or waives
`story.*` with the reason.

**Before capture, for any product:**

```text
node scripts/check-story.mjs <brief.json> [--brand <brand.json>]   # exit 0 pass, 1 fail; contacts no provider
node scripts/check-story.mjs --types                               # what each film type needs
```

The brief may be a full spec or only `product`, `filmType`, `targetSeconds`, `narrative` and `beats`.

**Optional cta.** A film type with no cta slot may omit `cta` (the lint requires it only for `product-marketing`, `founder-pitch`, an undeclared `filmType`, or a beat with the `cta` role). Ratios are 16x9, 4x5 and 9x16; `voice.provider` is elevenlabs, openai or import (`local` is retired).

## Imported narration and stills

`voice.provider: "import"` reads narration that a governed script already made, so no provider is called and nothing is charged
here. `voice` carries `source` (`assemblyai`, `deepgram`, `azure`, `openai`, `elevenlabs` or `recording`), `manifest` (a path
relative to the spec folder) and, for every AI source, a `disclosure`. The manifest is `media-studio/narration-import/1`:
`{schema, source, entity, lines: [{beatId, cut?, textSha256, file, sha256, receipt: {provider, requestId, outputSha256, usdMicros|null, estimated}}]}`.
The voice stage checks that each file sits inside the manifest folder, the audio hash, that the receipt hash equals the audio hash
(AI sources), and that `textSha256` is the beat narration; any miss stops with one message naming the beat. The audio hash is part
of the line key, so swapped audio re-times. Each line is a zero-cost cached ledger row under the true source; a `recording` is not
AI-generated and needs no request id. An imported AssemblyAI owner clone (`ownerVoice: true`) also needs
`consent {subject, approvedBy, validUntil}` (unexpired) on the manifest or every line receipt, plus the disclosure.
`scripts/import-narration.mjs --spec --source assemblyai|deepgram --from --out [--entity] [--region]` builds the manifest from an
AssemblyAI `narration-manifest.json` (every batch must be one beat) or a folder of Deepgram CLI receipts, offline.

B-roll `provider: "import"` (`file`, `sha256`, `source`, `aiGenerated`, optional `receipt`) takes a still (png, jpg or webp) made by Runware,
Azure, OpenAI or licensed; a video fails the lint because compose is image-only. `elevenlabs-video` (no governed adapter) and `stock` without a
file fail the lint, and the assets stage throws before any paid call if a required b-roll cannot be produced. There is no skip.

Imports are capped by their own governed ledger (the script that made them), not here: their rows stay zero-cost in this ledger and record
`paidElsewhere {usdMicros, estimated}` (also summed in `summary().paidElsewhere`), with the entity in the row note. Rules applied by the lint
and again by the voice stage: each synthetic line receipt must carry the declared `voiceId` and `model`; an owner clone needs consent on the
manifest or on every narrated line (`subject` equal to `voice.name`, `approvedAt` or `recordedAt`, `validUntil` within 60 days of it; a date
alone ends that day in US Central, a date-time needs an offset); a receipt marked `clone: true` or `visibility: "private"` needs `ownerVoice`;
a `recording` needs `recordedBy` and no receipt provider; `brand.entity` and the manifest (or b-roll receipt) entity must agree unless
`voice.entityException` / `broll.entityException {reason, approvedBy}` is recorded. A cut with `voice.disclosure` or `brand.disclosure.required`
must end on a `card`, the only place the label and disclosure are drawn. Imported stills must lie inside the spec folder or workspace.
A planned provider with unknown cost fails the lint unless it is `local`. `finalHoldSeconds` counts toward the planned cut length.
