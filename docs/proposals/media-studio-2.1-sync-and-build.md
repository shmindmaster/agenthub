# Media Studio 2.1: word sync, building diagrams, emphasis tokens

Status: **proposed** (review only; no kit code, no deploy). Base: media-studio 2.0.4 (repo `packages/media-studio`,
runtime `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit` and `_shared\tools`, both reporting 2.0.4).
Target: 2.1.0. Owner of the capability: `packages/media-studio` (one registry owner; this proposal adds no new
capability, skill, MCP or plugin).

Aligned with the exam-prep "Sync Cards" proof that is being built now (`D:\ExamPrep\builds\REDO-PLAN-2026-10-21.md`,
job workspace `%LOCALAPPDATA%\AgentHub\media-studio\cca-f-sync-redo-20261021`). That job is the first consumer and the
reference sample. This proposal generalises its design into the kit so every film gets it. It does not duplicate
or replace that job's work, and nothing here asks it to change course before its sample is approved.

## 1. What changes for the viewer

1. **Words on screen move with the voice.** Text that is on screen because it is being spoken paints in, or
   highlights, on the frame its word starts, from word timings of the actual narration take.
2. **Diagrams build on the narration.** A node appears on the word that names it, the edge into it draws as it
   lands, and a focus ring sits on the node being talked about. No evenly spread reveals, no whole stills.
3. **Colour means something, the same thing, every time.** Question vs answer, claim vs evidence, key term, trap,
   risk and good are semantic roles resolved through the brand kit, never hex literals in components.

The three highest-value changes are, in order:

1. **One clock of record for words.** Forced alignment of the locked script against the accepted take
   (`ai.ps1 align`, new in Local-AI), written as `media-studio/word-timings/1` and consumed by the cue sheet,
   captions, word-synced text and diagram beats alike. Today the kit has three caption/word shapes, no aligner, and
   the default Local-AI ASR engine returns no timestamps at all.
2. **`<BuildDiagram>` driven by beat words**, replacing `revealAt`'s even spread for viewer-facing films.
3. **`validate-word-sync.mjs`**, a gate that can fail: it binds the render's own event receipt to the encoded
   candidate and probes pixels at every sampled event, and `validate-viewer-release.mjs` refuses a release without it.

## 2. Inventory: what 2.0.4 supports today

Paths relative to `packages/media-studio` unless marked. "Absent" means searched and not found in the files named.

### 2.1 Captions and word timing

| Fact | Where |
| --- | --- |
| Remotion family pinned at 4.0.517 (`remotion`, `@remotion/cli`, `@remotion/tailwind-v4`); React 19.2.3; Playwright 1.63.0; playwright-recast 0.21.0 | `kit/package.json:9-14` |
| `@remotion/captions` is **not** a declared dependency (present only transitively via `@remotion/studio`); never imported. `createTikTokStyleCaptions`, `Caption`, `parseSrt` absent from `kit/src`, `kit/marketing`, `kit/screencast` | `kit/package-lock.json:1829` |
| Own caption types: `CaptionWord {word,start,end}` (seconds), `CaptionChunk {startSec,endSec,words[],lines?,top?}` | `kit/src/MarketingAd.tsx:42-43` |
| The only word-highlight renderer: `KineticCaptions` (active word scale 1.03, ±0.04 s window, unspoken opacity 0.88, 6-frame fade), MarketingAd only | `kit/src/MarketingAd.tsx:108-110, 283-330` |
| `Briefing` has no caption layer and no word-level text; one `<Audio>` | `kit/src/Briefing.tsx:154` |
| The `Question` card spreads words evenly over 86% of the scene (`step = duration*0.86/words`), not on spoken times | `kit/src/Briefing.tsx:506-515` |
| Caption chunking (4-7 words, lead 0.05 s, hold 0.35 s, ≤18 cps) and SRT writer (42-char lines) | `kit/marketing/lib/captions.mjs:11, 67-113` |
| Caption gate: ≤7 words, ≥2 words, ≤2 lines × 42 chars, ≤20 cps | `kit/marketing/lib/gates.mjs:34-48` |
| Soft track (`mov_text`) only in the scaffold's `--burn-captions` path; no `.ass`/`.vtt` output anywhere | `scripts/scaffold-video-workspace.mjs:113-130` |
| Transcription for timing: `ai.ps1 transcribe --engine whisper --no-vad --json-out` (local) or OpenAI `whisper-1` word granularity (marketing only) | `kit/marketing/lib/providers/local.mjs:23-25`, `providers/openai.mjs:59-67` |
| ASR word shapes accepted: `{segments[].words[]}`, `{words[]}`, bare arrays → `{w,start,end}`, precision `word|segment|none` | `kit/screencast/sync-lib.mjs:43-70` |
| Cue sheet reads `voice/asr/<segId>.json`, then `story/narration-words.json`, else an even-spread `estimate` | `scripts/build-cue-sheet.mjs:11-17, 76-92` |
| Script-to-ASR alignment (interpolates missed words) exists only in the marketing pipeline | `kit/marketing/lib/timing.mjs:13-60` |
| Forced aligner: absent from the kit and from Local-AI. It exists only in a product repo's QA script (`Qwen3-ForcedAligner-0.6B`, product-owned weight cache) and in the exam job's `prep/align.py` | Local-AI `src/runtime/media/*` searched |
| Local-AI `ai.ps1 transcribe` defaults to Qwen3-ASR, which writes **plain text only**; `--engine whisper` (`media/stt.py`) writes `segments[].words[{start,end,word,probability}]` | `local-ai-platform/src/runtime/ai.ps1` (`'transcribe'` branch), `media/stt_qwen.py`, `media/stt.py:337-345` |
| Skills: capture says per-line `--engine whisper --json-out voice/asr/<id>.json`; compose says "Captions stay Recast/Remotion from the locked spoken words"; QA requires "captions from the spoken words" bound to the candidate | `skills/media-studio-capture/SKILL.md:35`, `skills/media-studio-compose/SKILL.md:68`, `skills/media-studio-qa/SKILL.md:41` |

Two measured facts shape the design:

- **Aligner resolution is 80 ms.** In the exam sample (`voice/align-raw.json`, 10 lines, 212 words) every word start
  lies on an 80 ms grid and 3 words have zero duration. A 40 ms tolerance measured *against the aligner* is a
  tolerance on rendering, not on speech; accuracy against speech needs an independent cross-check (§6).
- **Whisper folds a file-initial fragment into its first word** (measured 2026-09-05 on 297 clips in the product QA
  script's own notes: word 0 at 0.00 s with probability 0.13-0.58). Whisper is a good second opinion and a poor
  clock for line-initial words.

### 2.2 Timing and sync gates (unchanged numbers, reused)

`kit/screencast/sync-lib.mjs:6-20` `SYNC_DEFAULTS`: action ±300 ms, screen 40 ms, result hold ≥1.5 s, drift ≤40 ms,
onset offset ≤120 ms, screen lead 0.3 s, head hold ≤1.5 s, freeze 4 s, hold 6.5 s, dropped frames ≤3.
`scripts/validate-sync.mjs:117-123, 239-274` requires word-level timing (or `--allow-degraded`, diagnostic only) and
uses `qa/encoded-asr.json` for the exact 40 ms A/V check. `scripts/validate-viewer-release.mjs:59` pins those
canonical thresholds; `:166-173` requires a candidate-bound captions file with readable cues. Storyboard timing
(`scripts/validate-storyboard.mjs:184-424`) and annotation hold `words/2.5+0.5` (`:363`). None of these measure
text-to-word or diagram-to-word sync.

### 2.3 Diagrams

- `kit/src/Visuals.tsx` visuals `flow`, `layers`, `sequence`, `timeline`, `map`, `checklist`, `code` carry an
  optional `at` (seconds from scene start). **Nothing populates `at` from timings**; the `atSeconds` builder promised
  in the `Briefing.tsx:20-28` comment is absent. Without `at`, `revealAt`/`phase` (`Visuals.tsx:1137-1162`) spread
  reveals evenly from 0.45 s across 88% of the scene. `revealFrom` carries a diagram across scenes.
- Flow edges are not drawn separately; a node's caption lands a stagger after the node (`Visuals.tsx:172-182, 225`).
- The only word-cued diagram is the code stage: `kit/code-stage/shotlist.mjs:8-12, 37-52, 146-185` resolves
  `{event, word, occurrence?, lead?}` cues; `kit/code-stage/diagram.html:7-8, 80-89` reveals node + inbound edge
  (`stroke-dashoffset`) and a lit gate. It is a single horizontal row of 2-8 nodes recorded through Playwright.
- `kit/screencast/render-card.mjs`, `render-html.mjs`, `render-overlay.mjs` each render one PNG; no timing.
  `schemas/timed-graphics.schema.json` is a rectangle plus a time window.
- Archetypes `diagram-build` (→ `flow`/`layers`/`map`) and `process-flow` (→ `flow`/`sequence`) exist
  (`kit/scene-archetypes.json:17-35`).

### 2.4 Emphasis and colour

- Tone palette duplicated as literals: `MARK` in `kit/src/Visuals.tsx:26-31` and `TONE` in `kit/src/Briefing.tsx:124-131`
  (default `#E8E4D9`, good `#3DDC84`, risk `#E85D5D`, emphasis `#F5C518`). No central theme object; `kit/src/index.css`
  is one Tailwind import.
- Question vs answer is typographic only: the `Question` card is off-white on `#070707` with no accent
  (`Briefing.tsx:495-560`); answers use a per-scene `accent`.
- Claim vs evidence is typographic only: `ProofCard` (`Visuals.tsx:855-877`).
- Key-term emphasis exists only in `MarketingAd` (`EMPHASIS_COLOR #ffd166`, hand-authored per-beat `emphasis[]`,
  `MarketingAd.tsx:112, 279, 295-320`; `kit/marketing/ad.schema.json:152`).
- Brand tokens: `kit/marketing/brand.schema.json:15-39` (`primary`, `foreground`, `background`, `accent`, optional
  `surface`, `muted`, `onPrimary`, `emphasis`; fonts). Screencast cards, overlays and `diagram.html` use their own
  hard-coded dark palettes.
- `screenplay.schema.json:149-155` and `storyboard.schema.json:206` carry `emphasis`/`highlight` strings that drive
  nothing in the `Briefing` composition.

### 2.5 Runtime drift found during inventory

- The deployed kit's `package-lock.json` still says **1.5.4** (no playwright-recast) while its `package.json` says
  2.0.4. `Sync-MediaStudioKit.ps1` copies sources but does not refuse a stale lock.
- The deployed kit's `screencast\` additionally holds validator copies that the repo kit's `screencast\` does not;
  `_shared\tools` is the documented home. Worth a parity check in the same release.

## 3. Where the techniques belong in the references

| Reference | Today | Add |
| --- | --- | --- |
| `references/story-craft.md` | Spine roles, no-fluff, explainer block; nothing on text on screen | New section **"Words on screen"**: when spoken text appears it is the exact locked words (`textMode: spoken`) and paints in on the word; callouts stay ≤4 words. Map spine roles to emphasis roles (question/stakes → `question`; reveal/takeaway → `answer`; proof → `claim` + `evidence`; misconception → `trap`). Resolves the conflict with `storyboard.md` rule 7 ("`onScreen` ≤ 4 words, do not duplicate narration"), which stays true for callouts and is explicitly not violated by `textMode: spoken` on training, explainer and exam forms. |
| `references/cursor-flow.md` | Eye path start/move/rest; static beats get `h.pointAt` | On a diagram or text beat **the build is the eye path**: the newly built node is the `move`, the focus ring is the `rest`. Word paint-in is narration-driven motion and is allowed; a cursor and a building diagram never both move in one beat (one emphasis per beat). |
| `references/product-picture.md` | Flow/diagram = overlay or ≤8 s cutaway | The ≤8 s diagram cutaway must build on beat words (`BuildDiagram`); an optional caption band with word highlight lives inside the campaign safe area, never over declared controls. Screen beats are unchanged: the product is the picture. |
| `references/marketing-readiness.md` | `designed-motion` criterion; kinetic captions exist in `mvg` | Muted autoplay: captions mandatory on every marketing cut, word-synced, measured by the word-sync gate (not by eye). Key terms take the brand `term` role. |
| `references/visuals.md` | Bible: motif, typography, motionTreatment... | Required `emphasisSystem` in `visual-bible.json`: role → token mapping for this film, ≤3 hue families plus neutral. |
| `references/direction.md` §6 | "A diagram that does not build is a still" | Each diagram beat names `build[]` (node, beat word, occurrence) and `focus[]`; each text beat names `textMode`. |
| `references/engagement.md` | Text callout row: "color emphasis" | Colour emphasis means a role token, never a literal. |
| `references/storyboard.md` | Rule 7 (≤4 words), rule 9 (markup) | Beat fields `textMode`, `build[]`, `emphasisRole`; rule 7 scoped to callouts. |

## 4. Changes per file

### 4.1 Skills (text)

- `skills/media-studio/SKILL.md`
  - Owner-standard "Voice first, word-level sync" bullet: word timings come from forced alignment of the locked
    script on the accepted take (`voice/timings/<lineId>.json`); add "text on screen paints on its word; diagrams
    build on their beat words; colour is a role token".
  - Crew table: Generate outputs add `voice/timings/*.json`; Compose validators add `validate-word-sync.mjs`.
  - §1 step 7 and §4 Stop: a viewer-facing training/explainer/briefing created on 2.1 with `wordSync: required` and no
    timings stops, it does not fall back to even spread.
- `skills/media-studio-generate/SKILL.md`: after a take is accepted, run `ai.ps1 align` on it with the authored script
  (never the pronunciation-respelled render text; respelling is a render-time dictionary layer, the aligner gets the
  words the viewer reads), then the whisper cross-check. Qwen3-ASR stays the identity/wording gate; it is not a clock.
- `skills/media-studio-compose/SKILL.md`: new section "Word-synced text and building diagrams" (components in §5,
  `build-sync-plan.mjs`, `render-with-receipt.mjs`). Replace line 68's single sentence with: this helper does not burn
  captions; burned word-synced text (burned by the render, not the finish helper) and the soft subtitle track
  (`mov_text` for MP4) are both generated from `story/word-timings.json`; neither is typed
  by hand. Update the hard-coded `2.0.4` version checks to `2.1.0`. Final check gains "sync plan built from timings;
  receipt collected".
- `skills/media-studio-qa/SKILL.md`: new step **2g Word-sync gate** (product screencast with captions, and every other
  kind with `wordSync` not `off`); "Other kinds" step 2 "Captions from the spoken words" becomes "word-sync PASS bound
  to the candidate". Human watch-through adds: "the highlighted word is the word you hear; the node lands as it is
  named; the same role is the same colour in every scene".
- `skills/media-studio-capture/SKILL.md:35`: per-line timings come from `voice/timings/` (aligner), with
  `voice/asr/` kept as the cross-check output.
- Third-party `remotion-*` skills are owner-installed and not vendored here (compose skill, line 102). No edits. The
  compose skill names `remotion-captions` (display-captions, `createTikTokStyleCaptions`) and `remotion-markup`
  (`text-highlights.md`, `timing.md`) as the ones to load for these components.
- `sarosh-audio-voice` lives in the private overlay; its matching one-line change (align against the authored script
  on the accepted take; identity gate unchanged) is made there, outside this public PR.
- `browser-toolkit` `desktop-evidence`: optional preflight for native-window recordings, see §8.3. `browser-evidence`:
  no change.

### 4.2 Kit sources

| File | Change |
| --- | --- |
| `kit/package.json` | Move the whole Remotion family to one exact version (4.0.537 at time of writing; all `@remotion/*` equal). Add `@remotion/captions`, `@remotion/paths`, `@remotion/layout-utils`, `@remotion/renderer`. Optional, behind a scene flag: `@remotion/motion-blur`, `@remotion/effects`. Evaluate Playwright 1.63.0 → 1.64.x and playwright-recast 0.21.0 → 0.23.x separately (§8.1). Bump to 2.1.0. |
| `kit/src/theme/tokens.ts` (new) | Role tokens (§5.3) resolved from the brand kit; replaces `MARK`, `TONE`, `FALLBACK_ACCENT`, `EMPHASIS_COLOR` and the screencast/diagram palettes. |
| `kit/src/sync/timeline.ts` (new, pure) | Seconds→frames (`Math.round(start*fps)`), minimum dwell, beat resolution (`{word, occurrence?, lead?}` against a line's words, the grammar already used by `code-stage/shotlist.mjs`), key-term matching. Shared by components and Node scripts; no React. |
| `kit/src/sync/WordSyncText.tsx` (new) | §5.1. |
| `kit/src/sync/BuildDiagram.tsx` (new) | §5.2. |
| `kit/src/Briefing.tsx` | Scene props gain `lines: string[]` (line ids), `textMode: "spoken" \| "callout" \| "none"`, `captionMode: "band" \| "off"`. The `Question` card renders `WordSyncText` with role `question`; answer scenes use role `answer`. Bullets' `atSeconds` is filled from beats, not by hand. Literals → tokens. |
| `kit/src/Visuals.tsx` | Every `at` can be given as `beat` (resolved through `timeline.ts`); `flow`/`sequence`/`layers` render through `BuildDiagram`; `revealAt`'s even spread is kept only for `intent: draft` and is recorded as `precision: estimate` in the sync plan. `ProofCard` uses `claim`/`evidence` roles. |
| `kit/src/MarketingAd.tsx` | `KineticCaptions` becomes a `WordSyncText` preset (`band`, scale 1.03). One implementation of word highlight in the kit. |
| `kit/sync/word-timings.mjs` (new) | Normalise, merge to program time, convert: `fromAligner`, `fromWhisper` (`stt.py` shape), `fromMarketingCaptions` (`{word,start,end}`), `toRemotionCaptions` (§6.3), `toSrt`/`toVtt`. |
| `kit/sync/build-sync-plan.mjs` (new) | Reads scenes + `story/word-timings.json`, writes `output/<base>-sync-plan.json`: every text paint, highlight, node, edge and focus event with its frame, source word and precision. The components import the same pure functions, so plan and picture cannot disagree by construction. |
| `kit/sync/render-with-receipt.mjs` (new) | Renders via `@remotion/renderer` `renderMedia` and collects each event's on-screen bounding box from component log lines (`onBrowserLog`) into `output/<base>-sync-receipt.json`, bound to the output SHA-256. Verify that the log callback is delivered per frame under concurrency during implementation; fall back to a `renderStill` probe per event if not. |
| `kit/scene-archetypes.json` | `diagram-build` and `process-flow` map to `BuildDiagram`; add `qa-reveal` (question → think gap → answer, the exam card shape) and `spoken-statement` (one sentence painted in, no callout). |
| `kit/code-stage/shotlist.mjs` | Import the beat grammar from `timeline.ts` instead of its private copy; behaviour unchanged. |
| `kit/screencast/sync-lib.mjs` | `parseAsrWords` also accepts `media-studio/word-timings/1` (precision `aligned`); export `WORD_SYNC_DEFAULTS` (§7). `SYNC_DEFAULTS` unchanged. |
| `kit/marketing/brand.schema.json` | Add `roles` (§5.3). Existing colour keys stay and seed the defaults. |
| `kit/marketing/lib/stages/timing.mjs` | Prefer `ai.ps1 align` on the governed narration take; hosted word timing stays the approved marketing fallback. |

### 4.3 Scripts and schemas

| File | Change |
| --- | --- |
| `scripts/validate-word-sync.mjs` (new) | §7. Writes `qa/word-sync.json` bound to the candidate. |
| `tests/word-sync.test.mjs` (new) | Synthetic fixtures only: a clean pass; a 3-frame late highlight (fails); an early paint (fails); a node with no beat word (fails); a plan/receipt mismatch (fails); a pixel probe that sees no change (fails); a draft with estimates (warns). Proves the gate can fail. |
| `scripts/build-cue-sheet.mjs` | Source order `voice/timings/` → `voice/asr/` → `story/narration-words.json` → estimate; record `precision: aligned \| word \| segment \| estimate` per line. |
| `scripts/validate-viewer-release.mjs` | When `job.wordSync` is `required`, require `qa/word-sync.json` PASS bound to the candidate with the canonical thresholds (same `canonical()` pattern as `:59`, `:100`). |
| `scripts/validate-storyboard.mjs` | Every `build[].word` occurs in its line's locked text; `textMode: spoken` beats have `onScreen` equal to the line, not a paraphrase. These checks run only on beats that declare `textMode`/`build[]` (or when `wordSync` is not `off`), so pre-2.1 jobs re-cut under 2.1 tooling are unaffected unless they opt in (§9). |
| `scripts/validate-narration.mjs` | Every `keyTerms[]` entry is spoken at least once (a term painted but never said is a fail). |
| `scripts/scaffold-video-workspace.mjs` | Create `voice/timings/`; stamp `mediaStudioVersion: "2.1.0"` on new jobs. |
| `scripts/Sync-MediaStudioKit.ps1` | Deploy `kit/sync/*`, `kit/src/sync/*`, `kit/src/theme/*`, and `validate-word-sync.mjs` to `_shared\tools`; refuse when the runtime lock's version differs from `package.json` (fixes §2.5). The deployed lock is stale today, so the first post-2.1 sync will refuse: the operator regenerates `package-lock.json` in the repo kit and re-runs the sync (remediation in §9). |
| `schemas/word-timings.schema.json` (new) | §6.2. |
| `schemas/sync-plan.schema.json` (new) | Plan and receipt events. |
| `schemas/storyboard.schema.json` | Beat `textMode`, `build[] {target, word, occurrence?, lead?}`, `focus[]`, `emphasisRole`. |
| `schemas/screenplay.schema.json` | Film-level `keyTerms[]`; scene `emphasis` gains a `role`. |
| `schemas/visual-bible.schema.json` | Required `emphasisSystem`. |
| `schemas/job.schema.json` | `wordSync: required \| optional \| off`; `mediaStudioVersion` (written by `scaffold-video-workspace.mjs` at job creation; absent on pre-2.1 jobs). |
| `schemas/timed-graphics.schema.json` | Optional `beat` on an overlay so a timed graphic can start on a word. |
| Manifests | `plugin.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json` → 2.1.0; recompute `scripts/RegistryContentHash.ps1`; `Validate-AgentHub.ps1` and the package tests pass. |

## 5. Remotion components

### 5.1 `<WordSyncText>`

Props: `words: Caption[]` (scene-relative ms, §6.3), `role`, `mode: "paint" | "highlight" | "band"`, `keyTerms`,
`maxLines`, `fontSize` (≥48 px body / ≥40 px options at 1080p; scaled by frame height for other profiles).

- `paint`: unspoken words are not drawn (or drawn at 0.15 opacity for layout stability); a word fades in over
  ≤4 frames starting on its own start frame. Used for full-screen spoken text (questions, answers, statements).
- `highlight`: all words visible; past words at role colour, the current word brightened with a pill behind it,
  upcoming words dimmed to the role's `muted`. The exam design.
- `band`: paged captions via `createTikTokStyleCaptions` (page pacing from the existing caption gates: ≤2 lines ×
  42 chars, ≤20 cps), current word highlighted. Replaces `KineticCaptions`.
- Key terms take the `term` role on their **spoken** occurrence: colour plus weight plus an underline that draws in on
  the word, so the role survives colour-vision deficiency and greyscale.
- Layout from `@remotion/layout-utils` (`fitTextOnNLines`, `measureText`) so word boxes are known; each word logs
  its box once for the receipt. Zero-duration words get a minimum dwell of 2 frames.
- Built with `Interactive` (already imported in `Briefing.tsx`) so the Studio caption editor and timeline can
  inspect and adjust it; edits flow back to the timings file, never to a hand-typed copy.

### 5.2 `<BuildDiagram>`

Props: `nodes[] {id, label, kind, rect?}`, `edges[] {from, to, label?}`, `build[] {target, word, occurrence?,
lead?}`, `focus[] {target, word}`, `layout: "row" | "grid" | "layered" | "given"`, `roles`.

- A node becomes visible on its beat word's start frame (scale 0.96→1, opacity 0→1, ≤8 frames ease-out).
- The edge into that node draws from source to target starting on the same frame, 300-600 ms, with
  `evolvePath` from `@remotion/paths`; `interpolatePaths` (4.0.529) for a node that changes shape on a later beat.
- One focus ring at a time, on the node named most recently; nodes already built stay at full contrast, the rest of
  the frame does not move.
- The diagram must be complete at least 1.5 s before the scene ends (the existing result-hold rule).
- `layout: given` accepts precomputed geometry, which is how the exam job's `plan/diagram.json` (nodes, `focusPath`,
  `highlightIds`, rects from `source.layout.json`) maps in without re-layout. `focusPath` order becomes `build[]`.
- Replaces the code stage's single-row `diagram.html` only for Remotion scenes; the code stage keeps its Playwright
  capture until a later release.

### 5.3 Emphasis role tokens

`kit/src/theme/tokens.ts` resolves `brand.roles` (new, optional) with defaults derived from existing brand colours:

| Role | Use | Default (dark learning theme, from the exam design) |
| --- | --- | --- |
| `question` | Question, stakes, wrong intuition | indigo: accent `#818CF8`, active `#C7D2FE` |
| `answer` | Reveal, answer, takeaway, `good` outcomes | emerald: accent `#34D399`, active `#A7F3D0` |
| `claim` | The assertion on a proof beat | foreground, bold |
| `evidence` | The source line under a claim | `muted` foreground, mono |
| `term` | Key terms on their spoken word | amber `#FBBF24`, bold + underline |
| `trap` | Misconception, exam trap, `risk` | rose `#FB7185` |
| `hook` | Memory hook card | amber surface |
| `muted` | Upcoming or non-current text | 55% foreground |

Rules: one role never changes colour within a job (checked from the receipt); ≤3 hue families plus neutral in one
frame; text roles ≥4.5:1 contrast on their background and non-text roles (rings, edges) ≥3:1 (WCAG 2.2); every role
also differs by weight, underline or a labelled chip. Brand kits that set `roles` override the defaults.

## 6. Local-AI word timings

### 6.1 What Local-AI provides today and what is missing

- `ai.ps1 transcribe --engine whisper` returns word timestamps; the default Qwen3-ASR engine returns text only.
- No `align` verb. The Qwen3 forced aligner is used only from a product repository's QA script and the exam job's
  prep script, with weights in a product-owned cache.

Proposed Local-AI change (separate, authorised engineering task in `local-ai-platform`, patched at
`src/runtime/**` and deployed through the release workflow, never edited under `D:\Local-AI`):

```text
ai.ps1 align <audio> --text-file <script.txt> --json-out <out.json> [--language English] [--cross-check whisper]
ai.ps1 align --batch <manifest.json>          # local-ai/align-batch/1 rows {source, text, out}
```

Weights in Local-AI's own model store; warm-worker reuse like the TTS/ASR workers; a receipt beside each output with
the audio SHA-256, script SHA-256, model and revision, so a stale timing file is never served against a re-rendered
take (the failure `stt_qwen.py` already guards against for transcripts). Until it lands, the kit accepts whisper word
timings as `clock.source: "asr"` and marks them lower precision; the exam job's `align.py` output converts directly.

### 6.2 `media-studio/word-timings/1`

One file per narration line at `voice/timings/<lineId>.json`; times in seconds from the start of that line's audio.
`kit/sync/word-timings.mjs merge` writes the program-absolute `story/word-timings.json` from the narration timeline.

```json
{
  "schema": "media-studio/word-timings/1",
  "lineId": "s03-l2",
  "audio": { "path": "voice/takes/s03-l2.wav", "sha256": "<hex>", "durationSeconds": 7.42 },
  "script": { "text": "<locked authored line>", "sha256": "<hex>" },
  "clock": { "source": "forced-align", "engine": "qwen3-forced-aligner", "model": "Qwen3-ForcedAligner-0.6B",
             "revision": "<hash>", "resolutionMs": 80, "runtime": "local-ai" },
  "crossCheck": { "engine": "faster-whisper", "model": "<name>", "comparedWords": 41,
                  "medianAbsDeltaMs": 31, "p95AbsDeltaMs": 92, "excluded": ["line-initial word"] },
  "words": [
    { "i": 0, "text": "Scenario:", "norm": "scenario", "start": 0.40, "end": 1.20,
      "scriptIndex": 0, "source": "aligned", "confidence": null }
  ],
  "unaligned": [],
  "coverage": 1.0
}
```

- `text` is the authored token including punctuation (what the viewer reads); `norm` is the match key.
- `source: "interpolated"` marks a word the aligner skipped and the converter placed between neighbours.
- `coverage` = aligned script tokens / script tokens.

### 6.3 Remotion `Caption` conversion

`toRemotionCaptions(words, offsetMs)` → `Caption[]` with `text` carrying a **leading space** for every word after the
first (what `createTikTokStyleCaptions` expects to join tokens), `startMs`/`endMs` rounded to integers,
`timestampMs = startMs`, `confidence` passed through or `null`. Units are the source of most caption bugs here: the
kit's own types are seconds, Remotion's are milliseconds; conversion happens in exactly one function.

## 7. The word-sync gate

`node <tools>/validate-word-sync.mjs <jobRoot> <candidate.mp4>` → `qa/word-sync.json`, bound to the candidate SHA-256
and byte count, the sync plan and the receipt.

| Check | Pass | Why this number |
| --- | --- | --- |
| Timings bound to take | Per line, `word-timings.audio.sha256` equals the SHA-256 of the take the cue sheet renders | Deterministic stale/swapped-take detection; the whisper cross-check is only probabilistic |
| Coverage | ≥98% of script tokens aligned per line; **every** key term and every `build[].word` aligned | The exam plan's 2% unmatched limit; a missing beat word is a missing build |
| Highlight/paint on time | Event frame − `round(start × fps)` ∈ [−1, +1] frames for every event; median 0 | ≤33 ms at 30 fps; the 40 ms owner tolerance expressed in frames |
| No early paint | No event visible before its frame − 1 (pixel probe) | Text that runs ahead of the voice reads as a teleprompter |
| Clock accuracy (cross-check) | Aligner start vs whisper word start on the encoded audio: median \|Δ\| ≤40 ms, p95 ≤120 ms, line-initial words excluded; any word >250 ms is a finding | Aligner grid is 80 ms; whisper folds line-initial fragments (§2.1) |
| Build beats | Node visible within [−1, +2] frames of its beat word; edge draw 300-600 ms; consecutive builds ≥400 ms apart (else merge into one beat); diagram complete ≥1.5 s before scene end | Lands with the word; readable pace; reuses the 1.5 s result hold |
| No unsourced reveal | Viewer-facing: zero events with `precision: estimate`. Draft: allowed, listed | Even spread is what made scenes freeze |
| Focus | One ring at a time; ring moves only on a `focus[]` or `build[]` word | One emphasis per beat |
| Plan = receipt = pixels | Every plan event appears in the receipt at the same frame; a probe of ≥30 sampled events (all if fewer) sees a luma change ≥8 levels in the event's box between frames f−2 and f+2 and none between f−4 and f−2 | This is what lets the gate fail on a broken render, not only on bad props |
| Emphasis | Role colours constant per job; contrast floors met; key term in `term` role on its spoken occurrence | §5.3 |
| Readability | Band: existing caption gates (≤2×42 chars, ≤20 cps); spoken text ≥48 px body at 1080p | Phone in landscape |
| A/V | Reuses `validate-sync.mjs` drift ≤40 ms on the same candidate | No second implementation |

Defaults live in `WORD_SYNC_DEFAULTS` (`sync-lib.mjs`); `validate-viewer-release.mjs` pins them canonically, so a
loosened run cannot release. Text clipping is still not machine-checked without OCR; the report says so.

## 8. Tooling from the last three months the kit does not use yet

Checked 2026-10-21 against npm release dates, the Remotion GitHub releases, the PowerToys GitHub releases and the
`local-ai-platform` commit log. Items are proposals; each is verified in its implementation PR before adoption.

### 8.1 Remotion 4.0.517 → 4.0.537 (kit pins 4.0.517, 2026-08-25)

| Adopt | What | Released |
| --- | --- | --- |
| Yes | `@remotion/captions` as a direct dependency; `parseSrt` precision and robustness fixes; `parseVtt()` | 4.0.526, 4.0.528, 4.0.537 |
| Yes | Caption Elements (Basic Captions, Rounded Captions) and `Interactive.captionsSchema`, `Interactive.withSchema`/`Interactive.create()` as the pattern for editable caption components | 4.0.528-4.0.536 |
| Yes | Studio caption editor (import SRT, split captions, follow active caption) and the new timeline / `<Track>` for review | 4.0.530-4.0.536 |
| Yes | `@remotion/paths` `interpolatePaths()` alongside `evolvePath` for edges and node morphs | 4.0.529 |
| Yes | `Config.setSequenceActivityLimit()` / `defaultPremountInSeconds` to keep hundreds of word sequences cheap | 4.0.535-4.0.536 |
| Optional | `@remotion/motion-blur` (HTML-in-canvas) on build-in motion; `@remotion/effects` (`lensBlur` to de-emphasise non-current regions, `lut` for a film look) | 4.0.526-4.0.537 |
| No | `@remotion/whisper-webgpu` Node transcription: Local-AI is the local route; `@remotion/whisper-web` stops publishing at v5 | 4.0.528, 4.0.537 |
| Evaluate | `@remotion/canvas-capture-extension` `setup_shot` agentic framing; product capture stays Playwright + Recast | 4.0.536 |

Nested HTML-in-canvas requires Chrome 157+ (4.0.533); effects are opt-in until the render host is confirmed.

### 8.2 Capture: Playwright and Recast

playwright-recast 0.22.0-0.23.0 (2026-09-29 to 2026-10-04) after the pinned 0.21.0. Its current README lists click
markers with a held cursor approach (`click()`/`markClick()`, `approachMs`), `waitForNarration()`, multi-page
(popup/tab) recordings, soft subtitle tracks (`mov_text`/WebVTT) and an OCR-driven "Jev" director. Confirm which
arrived after 0.21.0 when bumping. Adopt click markers and multi-page; feed `embedSubtitles` from
`story/word-timings.json`. Do **not** adopt "voiceover-driven freezes" (holding a frame until audio ends): it is the
frozen-screen defect `product-picture.md` and the sync gate forbid. Playwright 1.64.1 is current (kit 1.63.0).

### 8.3 PowerToys (0.101-0.102, 2026-09-30 to 2026-10-21)

- **CursorHide** (0.102): hide the OS cursor during a `desktop-evidence` recording when a drawn cursor is added in
  finishing.
- **Light Switch CLI** with JSON output (0.102.2814): set and record light/dark theme deterministically before a
  native-window capture; record the JSON in the receipt.
- **ZoomIt** recording (16:9-locked region, webcam overlay, clip append, snip dictation 0.102.2883): useful for an
  owner-performed live demo. It stays outside the autonomous path, as `desktop-evidence` already states; nothing in
  the kit drives it.

### 8.4 Local-AI voice (commits since 2026-07-21)

Already available and worth using in this release: warm TTS and ASR workers (059aa0c) so a per-line align and
cross-check pass is cheap; grounded pronunciation-risk and listen (8646231, e1dbddf); durable file-bound batch
rendering (f712b29); the audio.cpp expressive voice roster (8a00ed9, d23a8d2) as candidate built-in voices for a
second non-owner voice, which gives an audible question/answer split on top of the colour split (owner narration
rules unchanged; no clones of real people). Missing: `ai.ps1 align` (§6.1).

## 9. Migration for existing jobs

- **Nothing re-renders automatically.** Delivered masters and locked jobs are untouched.
- Jobs without `mediaStudioVersion` (everything made on ≤2.0.4) read as `wordSync: off`; the 2.1 validators do
  not require `qa/word-sync.json` for them, and every 2.0.4 gate keeps its numbers.
- New viewer-facing `training`, `explainer`, `briefing`, `series-episode` jobs default to `wordSync: required`;
  `product-screencast` defaults to `optional` (captions band only); marketing cuts default to `required`.
- A recut (`sourceJobId`) can opt in without new TTS: align the accepted takes (reuse before regenerate), author
  `build[]` and `keyTerms`, recompose the affected scenes, rerun every gate.
- Existing `voice/asr/<id>.json` (whisper) imports as `clock.source: "asr"`; scenes with `at`/`atSeconds` keep
  working, `beat` wins when both exist; `MarketingAd` `captions.json` converts through `word-timings.mjs`.
- Runtime: `Sync-MediaStudioKit.ps1` replaces the kit and refuses a stale lock; local extra files in the runtime kit
  (`.bak-*`, job-specific scene JSON, `out/`, `public/`) are not touched. The deployed lock is already stale (§2.5),
  so the first post-2.1 sync refuses: regenerate `package-lock.json` in the repo kit (so it matches the 2.1.0
  `package.json`), then re-run `Sync-MediaStudioKit.ps1` to deploy.
- The exam job's shapes map one to one: `voice/timings/` (same folder name), `plan/diagram.json` → `BuildDiagram`
  `layout: given`, script `keyTerms` → screenplay `keyTerms`, its colour families → the default learning roles. Its
  card-level 40 ms gates match §7 in frames; the one difference is the explicit cross-check against the 80 ms
  aligner grid.

## 10. Delivery plan (after approval)

1. Schemas, `word-timings.mjs`, `timeline.ts`, unit tests (synthetic fixtures). No rendering.
2. Components (`WordSyncText`, `BuildDiagram`, tokens) and `build-sync-plan.mjs`, Studio-previewed on a synthetic job
   in an external workspace.
3. `render-with-receipt.mjs`, `validate-word-sync.mjs`, viewer-release wiring, tests proving each check can fail.
4. Skill and reference text (§3, §4.1); manifests to 2.1.0; content hash; `Validate-AgentHub.ps1`; package tests.
5. Separate repo, separate authorisation: Local-AI `ai.ps1 align`.
6. Deploy with `Sync-MediaStudioKit.ps1`, then one synthetic film through every gate, watched and heard in full.

Each step reports its rung (merged → in main → deployed → production-verified) separately.

## 11. Open questions

1. Owner default for spoken text: `paint` (words appear as spoken) or `highlight` (all visible, current word lit)?
   The exam sample will answer this for learning films.
2. Should `product-screencast` captions default to `required` for customer-facing cuts (muted autoplay), not only
   marketing forms?
3. Is a second non-owner voice for questions acceptable outside exam prep, or only there?
