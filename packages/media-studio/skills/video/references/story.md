# Story

Write the brief, thesis and script from the source in context, in this turn. Infer structure, tone and length. Do not generate TTS.

Contents: Brief and thesis · Spine · Writing for the ear · No fluff · Explainer path · Dramatised incidents · Technical story beat map · Diagnose first · Tools

## Brief and thesis

The thesis is one sentence: what the viewer can do or stop doing afterwards. It goes in `viewerPromise`. A second promise is a second film.

`story/screenplay.json` (`schemas/screenplay.schema.json`):

- Film: `hook`, `emotionalTarget`, `audience`, `viewerPromise`, `wpm` (default 150; slower for `documentary` and `ai-trust`).
- Scene: `id`, `narration`, `sceneRole`, `viewerQuestion`, `wiifm` (outcome or identity, never a feature name), one `emphasis`, `truth`, `pauseBeforeSeconds`, `holdAfterSeconds`, `musicCue`, and `story.beforeState`, `.tension`, `.openLoop`, `.payoff` as they apply.
- Exactly one `heroMoment: true`.
- `product-screencast`: default `visualMode: screen`, `uiProof` on every product claim, scenes as a causal chain.

`truth` defaults to `FACT` when the source is given; `DRAMATIZED` or `COMPOSITE` only where you heighten or merge. Omit unsourced numbers. Do not invent metrics, customer names or product behaviour. Pronunciation goes in a lexicon or SSML layer at synthesis; never respell the script. Run `scripts/check_script_terms.py` on the locked script before any speech spend: it blocks on any undecided acronym, brand or name.

Run in order:

1. Keep the draft as `story/screenplay.draft.json`, then cut.
2. Write `story/screenplay.json`, `story/narration.md` (one scene per heading) and `story/locked-script.txt` (the exact spoken text).
3. `node scripts/lock-facts.mjs <jobRoot>` writes `story/fact-lock.json`. `validate-picture-inputs.mjs` refuses narration whose numbers differ from it.
4. `node scripts/validate-narration.mjs <jobRoot>` writes `qa/narration-check.json`. It must pass.
5. With `story/storyboard.json` in place: `python scripts/write-story-review.py <jobRoot> --judgments qa/story-judgments.json` writes `qa/story-review.json`. Missing judgments give `MALFORMED_INPUT`.

## Spine

Hook, stakes, characters, tension, payoff:

```text
Question → Stakes → Wrong intuition → Complication → Reveal → Demonstration → Implication → Takeaway
```

A single-beat clip runs question → reveal → takeaway.

| `sceneRole` | Viewer job |
| --- | --- |
| `hook` | Open on the payoff or the tension. Match the title's promise. Open a loop. |
| `before` | Felt cost: the stakes. Name who wants what. |
| `tension` | The normal way breaks. |
| `reveal` | Picture first, name it after. |
| `proof` | One hard case, number or evidence. |
| `trust` | Human control, limit, what it does not do. |
| `hero` | The one protected moment. |
| `payoff` | Close the loop, then hold. |
| `cta` | One next step. |
| `bridge` | Only when the cut would otherwise confuse. |

- Cut the greeting, logo, agenda and nav tour, even for an internal audience.
- Goal → obstacle → escalation → complication → reversal → payoff. A stretch with no obstacle is a lecture: cut it or give it stakes.
- Turn around the midpoint: what the viewer believed stops being true.
- Joins: start the next scene's voice over the old picture (J-cut) or run the voice into the new picture (L-cut). Not on `screen` beats: `validate-sync.mjs` fails a screen more than 40 ms after the first content word.

`write-story-review.py` requires: first scene `hook`; a `before` scene ahead of the hero; hero outside the first 3 scenes, `holdAfterSeconds` ≥ 1.0, and `silenceOnReveal` or `musicCue` `silence` or `sting`; `trust` or `proof` within 3 scenes after it, or a recorded judgment.

## Writing for the ear

- One idea per scene, one thought per sentence, short sentences.
- Set pauses and holds; do not pad the speech.
- Do not narrate visible chrome. Name the result after it appears.
- If the voice names a config or integration, a scene shows it.
- A line names only what the cursor will move to: one target per beat.
- One voice per film or series, from the recipes in the `generate` skill. No Sarosh voice clone.
- Stakeholder Q&A: `speaker` `ryan`, `vivian` or `aiden` on a labeled question card. The host carries most lines.

## No fluff

Every line changes what the viewer knows or does, or it is cut. One idea is said once. `validate-narration.mjs` checks `story/narration-timeline.json` when it exists, else the screenplay. Each hit is an error.

| Class | Examples |
| --- | --- |
| greeting | hello, hi, welcome, thanks for watching, my name is |
| meta | in this video, today we'll, let me show you, as you can see, now we, next we |
| recap | to recap, in summary, as we saw, as mentioned, so that's, that was |
| process | we built this, this scene / take / cut, the narration, voice-over, footage |
| version | version, v2, revision, what changed, since last time, what's new, previously, changelog |
| synthetic | synthetic, demo data, sample data, test data, fake, placeholder, not real |
| jargon | leverage, seamless, robust, cutting-edge, streamline, empower, unlock, powerful, end-to-end |
| filler | just, really, very, actually, basically, simply, easily, kind of, you know, of course |
| redundant | 70% of a line's content words repeat one earlier line |
| no-new-information | every content word was already spoken |

- Hook: the first sentence fits 5 seconds, at most 12 words at 150 wpm.
- Promise: a content word of `viewerPromise` (or the first scene's `wiifm`) is spoken inside those words.
- Marketing cuts: pain or payoff on screen inside 2 seconds (`review` skill).
- Synthetic data is never spoken, even to be honest about it. Set `syntheticDisclosure: { mode: "caption" | "end-card", text }`.
- Product words: `narrationAllowlist: [{ phrase, reason }]` covers jargon, filler and version hits only.

## Explainer path

Build the block (`schemas/explanation.schema.json`), then wrap it in the spine. Do not ship it as sequential slides.

- Required: `core_idea` (the core idea in one sentence a viewer can reuse at work), `plain_explanation` (2 to 4 sentences), `takeaway`.
- Optional: `analogy`, `real_example` (`FACT`), `misconception` (feeds Wrong intuition), `visual_plan` (for the storyboard).

Show, then tell. Define jargon once.

## Dramatised incidents

```text
real incident → premise → character objective → conflict → escalation → technical complication → reversal → payoff
```

Comedy stays inside the telling: earnest goal, small plausible obstacle, escalation through a technical misunderstanding, the "fix" reveals the real system rule, the payoff teaches without humiliating real people. Tag every beat. Fictionalize before any external share.

## Technical story beat map

`programForm: technical-story`. One change, 5 to 8 minutes, a mini technical documentary. Evidence serves the story.

> Show me what happened. Explain why it happened. Show me where it happens. Tell me why I should care.

| Target | Beat |
| --- | --- |
| 0:00 | Hook, 10 to 20 s: the problem, not the UI |
| 0:20 | Real product scenario, synthetic data |
| 1:00 | The weird behaviour |
| 1:45 | What is actually happening: small flow diagram |
| 2:30 | Code reveal, 5 to 20 lines: product behaviour → question → code → explanation → product result |
| 4:00 | The fix: before/after, one beat with two states |
| 5:00 | Replay the product |
| 6:00 | What this means: implications, edge cases, uncertainty |

A shorter film compresses every beat and drops none.

- Every code or log beat says what, why and consequence, then the human consequence: a dropped webhook is a customer waiting.
- `truth: FACT` on every code and log claim.
- Name each beat's markup. `kit/screencast/render-overlay.mjs` does dim, box, arrow, label and note. One highlight at a time.
- `render-code.mjs`: real excerpt, real line numbers, commit on the card. Never a full-file scroll.
- Change the picture because the story moved, never on a timer.
- Never record real user data (`PIPELINE_BLOCKED`).
- Never make an addendum video, even for one wrong section. Re-record it and re-cut the master.

## Diagnose first

Fix the failing stretch. Do not sprinkle effects on a cut that lands.

| Retention shape | Failing part |
| --- | --- |
| First-30-second cliff | Hook |
| Steady slide | Pacing |
| Late drop | Payoff |

| Failure mode | Fix |
| --- | --- |
| Wall-to-wall speech, no pause around the point | Pause, hold, `musicCue: silence` |
| One visual held across more than one idea | New scene or archetype |
| Narration repeats words on screen | Cut one |
| No contrast (old/new, cost/relief) | Add `before` or `tension` |
| Payoff rushed, or a long close after it | Hold it; cut the close |
| Same rhythm every scene | Vary pause, hold, energy |
| Opening is a greeting, logo reel or agenda | Rewrite the hook |
| Same archetype twice with no reason | Change the archetype |
| Every beat a type-on-dark slide | Use the archetype kit |
| Ken Burns on a screenshot, or frozen UI | Real captured WebM |
| Feature tour posing as a demo | Rebuild on one outcome |
| Instant-perfect AI result | Show the human control |

Screencasts: Recast owns cursor, clicks and zoom. Do not invent another overlay stack. `render-overlay.mjs` is markup over Recast's output, not a second cursor.

## Tools

| Technique | Provider | Refuse |
| --- | --- | --- |
| Music bed | Accepted, licensed bed asset, then `Finish-Media.ps1 -Speech -Music` | Bed under a screencast hero; one-pass loudnorm |
| Silence | `musicCue: silence`, pause, hold | Music in every gap |
| Register | Azure style per line (`generate` skill) | Styles outside the voice's catalog |
| Text callout | `onScreen`, up to 4 words | Repeating the voice |
| B-roll | Accepted plates, `gpt-image-2.5-flare` stills | Synthesized UI, metrics, testimonials |
| Accent | `sfxCue`, `silenceOnReveal`, `transitionAudio` | Wall-to-wall bed |
