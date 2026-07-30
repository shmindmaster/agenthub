---
name: product-demo-studio-narration
description: >
  Generate and maintain voiceover narration for a product video: provider-agnostic text-to-speech,
  segment-level regeneration, timing metadata, and narration style. Use when the user asks to "add
  narration", "generate voiceover", "record the script", or when a Remotion composition needs an
  audio track. This is the narration step of product-demo-studio, running after the script is
  final (product-demo-studio-render's validated persuasion/storyboard plan) and before final
  capture, render, and QA. Enforce viewer-centered WIIFM, one protected hero moment, emotional
  pacing, deliberate silence, pronunciation, and measured segment timing.
---

## Generating narration

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/generate-narration.mjs" --script <path-to-script.yaml> --out <audio-output-dir> \
  [--provider elevenlabs|openai] [--voice <id>] [--voice-profile <path>] [--preset natural-warm|expressive|calm] [--no-context]
```

Resolve `PRODUCT_DEMO_STUDIO_ROOT` through the router skill before invoking bundled scripts. TTS is
a billed external action: generate auditions or narration only when the current request authorizes
that spend. Never auto-clone a voice.

Pass the provider and the live-verified model explicitly for a billed production run. The script
can infer a provider only when the environment makes the choice unambiguous; never let the
availability of a key silently change an approved voice profile. It never hardcodes or prints a
key. If credentials are absent, it fails with the environment-variable reference to resolve — it
does not fall back to a lower-quality path, solicit a raw secret, or fabricate audio.

## Preflight before every billed run

Provider model IDs, deprecation state, voice rosters, quotas, and prices drift. Before generation:

1. Resolve the current speech model against the provider's model and deprecation information.
2. Verify credentials with a non-generating authentication check; keep keys in environment refs.
3. Verify the approved voice still exists and the current transcription model can return word-level
   timestamps for caption and Audio QA alignment.
4. Recheck pricing and live quota, then estimate cost from measured narration duration.
5. Record provider, model, voice, per-segment instructions/speed, response formats, and the check
   timestamp in the episode manifest.

Treat provider/model/price examples in the complete guide as a dated comparison snapshot, never as
permission to skip this preflight. HTTP 429 stops the run; do not rotate across keys to repeat a
successful request.

It applies the **Voice quality standard** below by default, sends each ElevenLabs segment with the
previous/next segment text as continuity context (so adjacent clips share prosody — disable with
`--no-context`), and hashes the full resolved voice profile into each segment's cache key so a
settings change correctly regenerates instead of serving a stale take at the old voice. Pass an
immutable `--voice-profile <path>` (JSON with `voiceId` + a `settings` block) to pin the exact voice
for a whole catalog.

Input is a segment-level script file:

```yaml
segments:
  - id: opening
    text: "Approvals used to take a full day. Now they take two minutes."
    voice: default
  - id: workflow-result
    text: "Every step is logged, so nothing gets approved twice."
```

Output per segment: an audio file, plus a sidecar with provider, model, voice, voice settings,
duration (measured from the actual generated audio, never estimated from word count), a checksum,
and the exact text used. A top-level manifest lists all segments with their combined duration.

## Regenerate only what changed

The script hashes each segment's `text` + `voice` + provider/model. On a re-run it only regenerates
segments whose hash changed, and leaves the rest untouched — so a one-line copy edit doesn't
re-spend the whole video's narration budget or introduce a subtly different voice take on lines
that didn't change. When a segment changes:

1. Regenerate that segment's audio.
2. Recompute its exact duration from the new audio.
3. Retime the composition beats and captions that depend on that segment's duration.
4. Recheck total duration against the target.

Never hand-maintain a timing value that should be derived from the generated audio file.

## Write narration for speech, not prose

TTS reads what you write, literally. Narration that reads well on a page often *sounds* like an
announcer reading an essay. Write for the ear:

- **One idea per sentence.** Most segments are one or two short sentences. Keep most sentences under
  ~18 words. Break a dense explanation into separate spoken beats instead of one long sentence.
- **Contractions and plain wording.** "It's logged" not "It is logged". Conversational, not formal.
- **Write numbers, symbols, and acronyms the way they're spoken** when the default reading is wrong:
  "twenty-one days", "ninety-two percent", "B-C-B-A" (or "the B.C.B.A."), "H-I-P-A-A". Verify the
  provider says names, dates, dollar figures, and clinical terms correctly and fix the ones it
  doesn't (see Pronunciation).
- **Punctuation is your pacing tool** — periods are full stops, commas are short pauses, an em dash —
  is emphasis, an ellipsis is intentional hesitation only, and a separate paragraph is a distinct
  spoken beat. Don't overuse punctuation or insert pauses that sound artificial.
- **Pause before a result and after a key statement.** Give the important number or outcome its own
  short sentence so it lands.
- **Don't narrate every click.** Describe the outcome, not the mechanics ("The claim is validated and
  ready to release" — not "Now I click the Validate button"). Allow quiet moments where the viewer
  needs to read or absorb a result; silence is allowed.
- Avoid announcer/newsreader/sales/essay delivery. Direct, credible, calm, outcome-oriented.

## Write to persuade without overclaiming

Use the validated storyboard's WIIFM and emotional target before writing any segment:

- Put pain, tension, or payoff in the first sentence. Ban "Welcome to", "In this video", login
  narration, company history, and dashboard-tour openings.
- Center "you" and the viewer's units — time, money, headcount, effort, or risk — rather than "we",
  product internals, vague efficiency claims, or feature names alone.
- Give every segment one explicit WIIFM. Cut or re-anchor any line that cannot explain why the
  viewer cares. Use the guide's three primary rungs (`feature`, `outcome`, `identity`) and make the
  payoff reach `outcome` or `identity`. Richer existing schemas may retain the validator-supported
  aliases, but `functional-benefit` cannot satisfy the payoff gate.
- Prefer concrete, source-backed specifics and useful contrast. The rule of three, antithesis, and
  an occasional rhetorical question are tools, not a house style.
- Lead the eye just before an action; name a result just after it appears. Round numbers for the ear
  while the verified exact value remains visible on screen.
- Protect the single hero moment: slow down, lower intensity, pause before the key word, then leave
  enough near-silence for the viewer to discover and absorb the result.
- Cut the first draft aggressively. Wall-to-wall narration, vendor-centered copy, and narration
  that repeats a headline fail the craft gate.

## Narration style

Direct, credible, calm, product-specific, outcome-oriented. Understandable without product
expertise. Avoid empty hype: *revolutionary, game-changing, AI-powered transformation, seamless
innovation, next-generation platform, one-stop solution, unlocking possibilities, redefining the
future*. Only describe AI behavior when it's tied to something visible in the capture — narration
claims are still claims and belong in the product-claim ledger (`product-demo-studio-render`).

Keep three content types distinct and don't let one substitute for another:

1. **Spoken narration** — what the voiceover says.
2. **Closed captions** — a timed transcript of the narration (see
   `product-demo-studio-remotion`'s captions rules for on-screen rendering).
3. **Visual headline/callout** — on-screen text for muted viewing. Should add value on its own,
   not just repeat the narration verbatim, and must never obscure the product state being shown
   (see `compute-overlay-placement.mjs` in `product-demo-studio-remotion`).

## Pronunciation and consistency

If the product name, an acronym, or a technical term is mispronounced by the provider's default
voice, add a pronunciation override (provider-specific: an ElevenLabs pronunciation dictionary, or
inline phonetic respelling for OpenAI TTS) and record it in the manifest so future regenerations
stay consistent. Reuse the same voice/settings across a whole video and, unless a persona-specific
video calls for a different voice, across a repo's whole catalog.

## Voice quality profile

Use the repo's auditioned, human-approved profile as the source of truth. The bundled ElevenLabs
values below are a reproducible legacy starting preset for repos already using that provider, not
a current provider recommendation. Verify the model and voice live, audition at least three current
candidates when no profile exists, and never switch a catalog's provider or voice silently.

| Setting | Default | Notes |
|---|---|---|
| Model | `eleven_multilingual_v2` | Legacy starting value only; replace with the live-verified approved model before a new billed run. |
| Stability | `0.42` | |
| Similarity boost | `0.75` | |
| Speed | `0.92` | Slightly slower than default reads calmer and more credible. |
| Style | `0.00` | Try `0.05` then `0.10` only after pacing and stability are already good, and only if quality clearly improves. |
| Speaker boost | on | |
| Text normalization | on (`auto`) | Normalizes numbers/dates/acronyms. |

Presets (in `--preset`): **natural-warm** `0.42 / 0.75 / 0.92 / 0.00` · **expressive** `0.35 / 0.72 /
0.90 / 0.00` · **calm** `0.50 / 0.78 / 0.90 / 0.00` (stability / similarity / speed / style).

Before committing a voice for a catalog, render a small A/B set on a representative 10–20 second
segment containing the product name, an acronym, a number/date, the result, and the guardrail.
Audition at least three suitable current built-in candidates when the repo has no approved profile,
keep the scoring/decision record, and require named human voice approval before the first master.
An existing repo voice profile is the source-of-truth candidate to verify, not permission to replace
or clone it. If quota blocks the audition, record `BLOCKED_ON_QUOTA` rather than choosing from a
label or one short clip. Generate narration in short
semantic segments (not one giant request) and keep continuity context on. For v2, use SSML breaks
sparingly — prefer punctuation and segment boundaries. For v3, don't use SSML breaks. **Never use
aggressive latency optimization for prerecorded narration** — it trades away quality for speed you
don't need here (the script never sets it).

## Timing: narrate first, then capture to the measured durations

Narration is approved *before* final capture, and its measured per-segment durations drive the
recording plan — not the other way around. When aligning audio and video:

- The screen state must appear *before* the narration describes it; don't announce an action
  substantially before it happens.
- Treat each interactive beat as a guided screencast sequence: pointer lead → real action →
  visible state change → spoken result. Use the capture manifest's measured
  `interaction.narrationSync` offsets; do not align by intuition after rendering.
- Narration may lead the viewer's eye toward the target, but it may not claim the result before
  `resultVisibleAtSeconds`. A click label is not the story—the resulting outcome is.
- Give each action enough time to complete, and keep an important result on screen long enough to
  read after its narration ends. Pause narration during dense reading or a complex transition.
- Don't accelerate cursor movement or a workflow just to fit the audio, and don't stretch or compress
  narration enough to damage the voice — adjust the script instead.
- Mux from the measured per-segment timeline offsets, never by eyeballing. See
  `product-demo-studio-render` for the pre-mux checks and `product-demo-studio-remotion`'s
  `calculateMetadata` for sizing scenes from real audio duration.

## Wiring generated audio into the composition

Once audio files exist, use `product-demo-studio-remotion`'s
[rules/voiceover.md](../product-demo-studio-remotion/rules/voiceover.md) to wire them into the
composition and size scenes dynamically from the real audio duration via `calculateMetadata`. This
skill only covers generating and maintaining the audio itself; the Remotion-side wiring stays in
`product-demo-studio-remotion`.

## Audio mastering handoff

Silence trimming, segment crossfades, music selection/ducking, and loudness normalization are
FFmpeg-level mastering steps — see `product-demo-studio-qa`'s `technical-checks.mjs` for validating
the result (loudness, clipping, silence) once narration is mixed into a render. Music is optional
and should support pacing, not be added by default "to sound premium."
