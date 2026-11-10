# Model-written specs

Read this when a film needs diagrams, animated words, staged explainers or scene-setting pictures that are not a captured screen, and there are more of them than is sensible to write by hand, or they come from a large context such as a codebase, a transcript or a screen recording.

The lane is `claude-haiku-specs` in `policy/provider-routing.json`. It is optional. A handful of pictures is still quicker to write straight into the kit.

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

## Format by job

Pick the highest-level format that can say it. It costs fewer tokens and makes fewer errors.

| The beat needs | Have the model write | Kit visual |
| --- | --- | --- |
| Architecture, a flow, a sequence, states | Mermaid or D2 source, or node and edge lists | `flow`, `layers`, `sequence`, `map`, `svg` |
| A mechanism that builds step by step | A JSON scene spec with stages, one stage per narration beat | `svg` or `flow` with `at` pinned to the word |
| Animated words | Caption chunks and emphasis words by word index | the caption layer |
| A chart | Chart config only: type, series names, the one highlight | `chart`, `stat` (data goes to the renderer directly) |
| An annotated screen recording | Chapters, step captions, callouts, zoom regions | overlays on `screen-in-context` |
| A short loop | A scene spec whose last frame matches the first | `lottie` or a kit scene |

Do not ask for raw coordinates: give named slots or regions and let code place things. Do not ask for Lottie JSON. Do not run model-written render code unreviewed.

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

One retry with the validation error in the prompt, then a simpler kit visual written by hand. Never let a missing or invalid spec silently produce a different picture: log it and list it. A refusal is not resent unchanged.

## Keys and privacy

- Model calls use the key named in the lane (`ANTHROPIC_API_KEY_BACKUP`), passed explicitly; SDKs read `ANTHROPIC_API_KEY` by default.
- An Admin key (`ANTHROPIC_ADMIN_KEY`) is never used for generation. Its only use here is reporting what a run cost. Keep it off render workers.
- Workers that only render get no key: generate specs first, then ship specs.
- Frames may hold credentials or personal data. Send synthetic or redacted frames only. Batch requests are stored for up to 29 days.

## Cost

Per million tokens on prompts up to 100,000 tokens: input $0.10, output $0.50 (thinking included), half that in batch, cache reads $0.01. A 2,000-token spec is about a tenth of a cent. Rendering and review time cost more than the model. Record the actual spend in `qa/spend-ledger.jsonl`.

Prices and model limits were read from the Claude Platform documentation on 2026-11-10. Callout accuracy from screenshots and per-image token cost are not measured here: measure before a large run.
