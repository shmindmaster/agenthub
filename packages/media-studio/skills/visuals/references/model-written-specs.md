# Model-written specs

Read this when a film needs diagrams, animated words, staged explainers or scene-setting pictures that are not a captured screen, and there are more of them than is sensible to write by hand, or they come from a large context such as a codebase, a transcript or a screen recording.

The lane is `claude-haiku-specs` in `policy/provider-routing.json`. It is optional. A handful of pictures is still quicker to write straight into the kit. The adapter is `scripts/generate_specs.py`, the resolver `scripts/model-specs-resolve.mjs` and the gate `scripts/validate-model-specs.mjs`.

## It adds to the recording; it never replaces it

A film about a product is built on the real thing: the captured screens (`../../capture/SKILL.md`), the actual narration, and the word clock and cue sheet that tie them together. Those are the product. Model-written visuals are added layers that make them easier to follow.

1. **The recording is the master timeline.** Every generated item is anchored to a timestamp in the real footage or audio and names the script line it supports. An item that matches neither is dropped. The recording is never retimed, trimmed, sped up or re-voiced to fit a visual; shorten or split the visual instead.
2. **Real footage stays visible.** Default to overlays (captions, callouts, zooms, lower-thirds, chapter cards) and side or picture-in-picture panels. A full-screen diagram is the exception, placed at a natural pause, with the real audio continuing underneath.
3. **Non-destructive.** Never write over a source file. Deliver each layer separately (caption sidecar, overlay data, overlay render) so it can be switched off or redone without touching the recording.
4. **Do not cover the thing being shown.** Overlays sit in free regions of the frame, never over the cursor, the active element or the next click target.
5. **Truthful to what happened.** An overlay may explain or label what is on screen and what was said. It may not show a feature, result or step the recording does not contain. Captions follow the words actually spoken, taken from the audio, not from the script when the two differ.
6. **Less is a valid answer.** Ask first where help is needed, and accept "nothing here". Most seconds of a good recording need no overlay.
7. **Script mismatches are reported, not hidden.** If the script and the recording disagree, flag it for a person. Never generate a visual that papers over the gap. If a capture is missing, the beat goes back to `capture`.

Layers, from the bottom up, all on the recording's clock:

1. Base video: the screen recording, untouched.
2. Base audio: the real narration, untouched. A governed voice is used only where no recorded take exists and never replaces one.
3. Captions: animated words timed from the actual audio.
4. Overlays: callouts, zoom crops, term cards, chapter cards. One explanatory overlay at a time besides captions.
5. Support: side-panel or picture-in-picture diagrams and charts; occasional full-screen inserts at pauses.

If generated visuals fill most of the frame most of the time, the film has stopped being a recording with support. `policy/product-video-policy.json` still governs how much of the picture the product occupies and how long a card may hold; this lane does not change those limits. A fully generated film, with no recording behind it, is a separate case: use it only where no real footage exists or is planned, and label it as such in the job.

## The one idea

A small text model never draws. It writes a description, and the kit draws it.

1. **The model writes:** diagram source, a staged scene spec, caption chunks, callout data.
2. **Code renders:** the Remotion kit, a layout engine, a browser, ffmpeg.

Text stays real text, so it is legible and checkable. A bad result is fixed by editing data. Photographs, illustrations and anything painterly are not this lane: use `still` or `broll` from the ladder.

## Who does what

| Job | Who | Why |
| --- | --- | --- |
| Visual style, templates, three to five worked examples | The producing agent, once, approved by the owner | Design quality is set here. A thin prompt with no examples gets generic pictures. |
| Filling those templates for many beats | Claude Haiku 5.5 | Cheap, fast, good at a pattern it has been shown. |
| Geometry, layout, frame maths | Kit code | Models are unreliable at arithmetic layout. |
| Word timing | The aligner (`../../review/references/word-clocks.md`) | The model cannot hear audio. It returns word indexes, never times. |
| Does it look right | A person on a sample, then the gates | Taste first, scale second. |

## Run the adapter

Quote first, then spend. Without `--run` nothing is sent and nothing is written.

```powershell
python scripts/generate_specs.py <jobRoot>                         # quote the default layer, moments
python scripts/generate_specs.py <jobRoot> --run                   # send it; review plan/model-specs/moments.json
python scripts/generate_specs.py <jobRoot> --layers overlays,captions,diagram                # quote the visual layers
python scripts/generate_specs.py <jobRoot> --layers overlays,captions,diagram --run --max-usd 0.50
node scripts/validate-model-specs.mjs <jobRoot>                    # the gate; writes qa/model-specs-report.json
node scripts/model-specs-resolve.mjs <jobRoot>                     # plan/model-specs/timed-graphics.json (see below)
```

- **Layers**, one request and one schema each (`schemas/model-specs/`): `moments` (where help is needed, with a reason; an empty list is a valid answer), `overlays` (callouts, step captions, term cards, zoom regions, chapter cards in a named region), `captions` (chunk boundaries and emphasis by word index, never times), `diagram` (Mermaid or D2 source as a string, a one-sentence caption and the beat range it supports).
- **Inputs** come from what the pipeline already records: `plan/cue-sheet.json` (each beat's spoken words with aligner times, labelled actions with program times, expected UI state) and, optionally, `story/model-specs-brief.json` with `{"style": "...", "examples": {"<layer>": [...]}}`, the house style and worked examples the producing agent wrote and the owner approved. Only text is sent; no frames.
- **Moments first.** The default layer is `moments`. A person reviews `plan/model-specs/moments.json` and sets `"approvedBy"` in it; from then on the overlays and diagram requests carry only the approved moments, and no later run overwrites the approved file. If the cue sheet or brief changes what the model would see, the run refuses to touch it and says so; if only timing changed, its recorded inputs are refreshed and the person's edits kept.
- **Request:** model `claude-haiku-5-5` (`--model`), effort `low` (`--effort medium` for messy source) in `output_config.effort`, structured outputs as `output_config.format` with the layer's schema, `max_tokens` four times the expected output because adaptive thinking is on by default and counts toward it, the reusable rules, style and examples first in a cached system block and the beat data last. No `temperature`, `top_p`, `top_k` or prefill. Thinking blocks before the text block are skipped. A prompt estimated above 90,000 tokens is refused.
- **Never pays twice:** the request hash covers model, system prefix, schema, beat data, effort and `max_tokens`. An answer is cached in `plan/model-specs/cache/<hash>.json`; an identical request is served from it, and the layer file's recorded inputs are refreshed when only the cue sheet's timing changed, so the gate does not call it stale. A request already listed in `fallback-needed.json` is not resent unless it changes or `--retry-fallbacks` is given.
- **Ledger:** one line per request in `qa/spend-ledger.jsonl` (`kind` `spec`, lane, layer, model, effort, attempt, stop reason and `stopDetails`, usage, dollars from the usage, request and prompt hashes, output file hash), written before the cache and the layer file so a crash never loses a paid result. A response that cannot be read still gets a line, with `usd` null because it may have been billed. `--max-usd` (default 0.50) refuses a run whose quote is over it, and every attempt, including each later layer's first, is checked against what has been spent so far.
- **One run at a time:** `--run` holds `qa/generate-specs.lock` (pid and start time inside) and refuses to start while another run holds it, saying whether that pid is still running. A lock it did not create is never deleted; remove a stale one by hand.
- **Stop reasons:** a refusal (HTTP 200, `stop_reason` `refusal` with `stop_details`; this model has no server-side refusal fallback) is recorded and never resent unchanged. Truncation at `max_tokens` is retried once with twice the room. An answer that fails the schema or the anchor, caption-word or length checks is retried once with the errors in the message. After that the layer goes into `plan/model-specs/fallback-needed.json` and the exit is non-zero: a person writes a simpler kit visual, then removes the entry. Never a silent fallback.
- **Key:** read by name from `ANTHROPIC_API_KEY_BACKUP` (`--key-env` names another variable) and sent in the request header. The tool refuses to start with `--key-env ANTHROPIC_ADMIN_KEY` or `ANTHROPIC_API_KEY` in any letter case (Windows reads environment names without regard to case). The value is never printed or stored.

## Anchors

Every generated item carries `beatId` from the cue sheet plus either an action label recorded in that beat (`anchor: "action"`, timed by its program `action_time`) or a range of that beat's word indexes (`anchor: "words"`, timed by the aligner's words). Captions are always a word range. A diagram also names `toBeatId`, the last beat it supports. The model never writes a time or a pixel.

`scripts/model-specs-resolve.mjs` places items deterministically. An action anchor runs from 0.2 s before the action to 2.5 s after it; a word anchor from the first word's start to the last word's end, at least 1.5 s; both ends are trimmed to the beat's screen slot when the anchor sits inside it (an anchor outside is left for the gate to report), and a diagram runs to the end of `toBeatId`. Regions are a fixed vocabulary on the delivery frame (`job.json` `deliveryProfile`, or `--frame`), inside a 4% margin: `top-left`, `top-right`, `bottom-left`, `bottom-right` (30% by 16%), `left-panel`, `right-panel` (32% wide), `lower-third`, and `fullscreen` for a diagram only. The output, `plan/model-specs/timed-graphics.json`, is overlays in `schemas/timed-graphics.schema.json`, the unchanged renderer contract. Anything it cannot place (an unknown beat or action, a word range outside the beat, an action with no program time) is rejected, never guessed, and without layer files it writes nothing.

What consumes it today: nothing automatically. `compose-screencast.mjs` reads `story/timed-graphics.json` and lays each entry's asset (an image listed in `job.json` `campaign.assets` under the same `assetId`) over the footage at that rectangle. So a person renders each item's asset with the kit and copies the entries into `story/timed-graphics.json`; the gate binds the resolver's file by hash so a hand edit is seen. Zooms are left out of the output on purpose: the compositor would paint an asset over the very footage a zoom is meant to magnify, and no crop renderer exists yet.

## The gate and the job convention

**A job has model-written layers when it has a `plan/model-specs/` directory.** `generate_specs.py --run` creates it. Then `validate-viewer-release.mjs` requires `qa/model-specs-report.json` as a PASS from `validate-model-specs.mjs`, bound to the cue sheet, every layer file and `timed-graphics.json` in that directory, and refuses while `fallback-needed.json` exists. A job without the directory releases exactly as before.

`validate-model-specs.mjs` lists each check as performed, or as not performed with the reason:

1. Layer files: from the adapter, valid against their schemas, generated from the current cue sheet, no pending fallback.
2. Anchors: every item names a beat in the cue sheet and an action label or word range of that beat.
3. Timing: resolved times sit inside the anchored beat (a diagram: from `beatId` to `toBeatId`).
4. Geometry: no overlay rectangle, padded by 24 px, covers the pointer, the active element or the next click target, read from `capture/receipt.json` for every clip in the item's span (`beatId` to `toBeatId`). It is reported `clear` only when every relevant action has geometry: `partial` when some action in the window has none, `not checked: no geometry in receipt` when none has, `not checked: Recast zoom not modelled` for a take with `recast` `full` (the default for desktop takes; the punch-in moves things far more than 24 px), `not checked: editorial crop not modelled` or `... panel not modelled` where the compose map gives that clip a `sourceRegion` or `destinationRect`, and `not checked: no recorded clip in this span` for a card. A zoom is reported as not rendered. A fullscreen insert must sit at a pause with no recorded action, and is not checked where there is no clip or an action has no program time.
5. One explanatory overlay at a time besides captions; a fullscreen insert takes the frame alone; one supporting diagram at a time, and no overlay whose rectangle meets a side-panel diagram's. There is no exception: two panels at once leave too little real footage.
6. Captions: the words equal the aligned transcript words by index (punctuation may change), each word once.
7. Sources: the recording equals the receipt's `sha256`, and each beat's audio equals the take hash in its aligner report.
8. Density: the share of runtime with any overlay and with a fullscreen insert, warned above half.

What the receipt holds today: `click` and `tap` events carry the pointer position (`x`, `y`) but no element box; `point`, `fill` and `select` events carry `targetBox`; `type` events carry neither; observed expectations carry the result element's `targetBox`. Coordinates are recorded-video pixels, mapped to the frame by uniform fit and padded by 24 px for rounding and cursor size. That padding does not cover Recast's punch-in zoom or an editorial crop; those takes are reported not checked instead. For geometry the gate can check, record with `recast` `noZoom`.

## Format by job

Pick the highest-level format that can say it. It costs fewer tokens and makes fewer errors.

| The beat needs | Have the model write | Kit visual |
| --- | --- | --- |
| Architecture, a flow, a sequence, states | Mermaid or D2 source, or node and edge lists | `flow`, `layers`, `sequence`, `map`, `svg` |
| A mechanism that builds step by step | A JSON scene spec with stages, one stage per narration beat | `svg` or `flow` with `at` pinned to the word |
| Animated words | Caption chunks and emphasis words by word index | the caption layer |
| A chart | Chart config only: type, series names, the one highlight | `chart`, `stat` (data goes to the renderer directly) |
| An annotated screen recording | Chapters, step captions, callouts, zoom regions | overlays on `screen-in-context` |
| A short loop | A kit scene spec whose last frame matches the first | a kit scene; an existing Lottie mark may be placed by name |

Do not ask for raw coordinates: give named slots or regions and let code place things. Do not run model-written render code unreviewed.

This lane never writes Lottie JSON. A short loop from it is a kit scene spec. Lottie marks come only from the lottie lane's own tooling (`lottie.md`) and may be placed by name, for example `lottie/check.json`.

## Budgets to state in the prompt

- One question per diagram. About 7 to 12 nodes. Labels of a few words.
- One idea per stage. At most about four new elements per stage.
- A one-sentence caption with every picture. It doubles as alt text.
- For words: maximum characters per line, lines on screen, minimum hold per chunk.
- Show the wrong path, then the correction, where the beat teaches.

These sit under the rules in `visual-bible.md`; they do not replace them.

## Prompt and request

- Examples are the spec. Put renderer facts in the prompt: canvas, safe margins, frame rate, primitives, tones, fonts, limits.
- Reusable material first, in the system prompt. The beat's data last, in the user message.
- Structured outputs with a JSON schema for anything a renderer parses. Every property required, `additionalProperties: false`, shallow nesting, ranges enforced in code. Mermaid or D2 can be a string field.
- Effort `low` for templated fills, `medium` for messy source or long context. `max_tokens` several times the expected output, because hidden thinking counts toward it.
- Do not send `temperature`, `top_p`, `top_k` or a prefill; this model rejects them. Vary takes with a variant number or layout hint in the data.
- Ask for a caption or note field, never a reasoning field.
- Keep prompts under 100,000 tokens; above that every rate is five times higher. For a codebase, build a compact map with code and send only the files the question needs.
- Caching pays only with a shared prefix of at least 512 tokens reused many times. Send one request, let it start, then the rest. Batch what is not needed in the next few minutes: half price, results in any order, check each one.

## Annotating a screen recording

The model cannot watch video. Give it deduplicated, downscaled frames with timestamps in text, the transcript, and the recorder's event log when there is one.

- **Ask where help is needed before asking for any visual.** Have it return moments with a reason: a fast run of clicks, a term used without explanation, a small or low-contrast target, something important off screen, a long wait. Review the list, then generate only for the approved moments.
- Each item carries the source timestamp it attaches to: chapter titles, step captions shown while the action happens, callouts, zoom regions (a zoom is a crop of the real footage, so it stays truthful by construction), term cards when jargon is first spoken, and a supporting diagram with the timestamp range it belongs to.
- Give it the free regions of each frame and require overlays to sit inside one. Reject in code any overlay that intersects the cursor, the active element or the next click target from the event log.
- Overlays enter and leave on the recording's own beats: a click, a page change, a sentence boundary. Long enough to read, short enough not to linger over the next action.
- If an explanation needs more time than the footage allows, use a side panel that persists across the segment. Holding or slowing the footage changes the recording and needs the owner's approval each time.
- The model may fix caption punctuation and line breaks. It may not reword what was said.
- Take callout coordinates from the event log or page structure. From vision alone, ask for a bounding box, pad it and check a sample by eye.

## Validate, then render

Model output is untrusted input to the renderer.

1. Schema check.
2. Semantic check in code: inside the canvas, times inside the scene, labels within length, referenced ids exist, diagram source compiles.
3. Render check: a file of plausible size and duration.
4. The gates in `SKILL.md`, then the contact sheet, looked at.
5. Augmentation check: the source recording and audio are byte-identical to the originals, every generated item carries a source timestamp, and turning every generated layer off still leaves a complete, watchable film.

`validate-model-specs.mjs` does step 1, step 2 except compiling the diagram source, and the hash and anchor parts of step 5; the render, the diagram compile, the contact sheet and the layers-off viewing stay with the kit and a person. One retry with the validation error in the prompt, then a simpler kit visual written by hand. Never let a missing or invalid spec silently produce a different picture: log it and list it. A refusal is not resent unchanged.

## Explaining a codebase

The compact code map comes from RepoWise at a pinned commit, never from a working tree or from the model's memory: the files, symbols and call paths the question needs, and nothing else. The diagram is written from that map. When the film shows the code itself, the code stage (`kit/code-stage/README.md`) records it: files are read from git objects at the resolved commit, and `capture/code-stage/receipt.json` holds the commit, each file's sha256 and blob id and a hash per shown line, re-checked later by `verify-receipt.mjs`. That receipt keeps the diagram truthful: every node and edge names something at the same commit, and a diagram that names code the receipt does not hold goes back for review. This is guidance only; nothing in this lane reads a repository.

## Prompts and examples in this package

Product-specific prompts, house styles and worked examples do not go in this public package. They live in the gitignored personal overlay with the product's other material. This package ships only neutral synthetic examples, such as the fixtures in `tests/fixtures/model-specs/`.

## Keys and privacy

- Model calls use the key named in the lane (`ANTHROPIC_API_KEY_BACKUP`), passed explicitly; SDKs read `ANTHROPIC_API_KEY` by default, so `generate_specs.py` refuses that name.
- An Admin key (`ANTHROPIC_ADMIN_KEY`) is never used for generation. Its only use here is reporting what a run cost. Keep it off render workers.
- Workers that only render get no key: generate specs first, then ship specs.
- Frames may hold credentials or personal data. Send synthetic or redacted frames only. Batch requests are stored for up to 29 days.

## Cost

Per million tokens on prompts of 100,000 tokens or fewer: input $0.10, output $0.50 (thinking included); above 100,000 tokens, $0.50 and $2.50. A 5-minute cache write costs about 1.25 times input and a cache read about 0.1 times; batch is half price. A 2,000-token spec is about a tenth of a cent. Rendering and review time cost more than the model. `generate_specs.py` records the actual spend from each response's usage in `qa/spend-ledger.jsonl`, at the long-context rates when the prompt was over 100,000 tokens. Its quote prices the cached system prefix at the cache-write rate, the beat data and the schema at the input rate and every allowed output token at the output rate. The token counts are estimated from characters, so the quote is meant to sit above the real cost but is not a strict bound.

Prices, model limits and the request shape were confirmed against the Claude API reference on 2026-11-10. Callout accuracy from screenshots and per-image token cost are not measured here: measure before a large run.
