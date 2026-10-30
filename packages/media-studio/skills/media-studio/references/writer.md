# Writer (screenplay, narration, shot list)

Step 1 of the crew in `SKILL.md`. From the concept or outline already in context, produce a locked screenplay in this turn. Do not ask for act structure, tone, or shot count; infer them. Do not generate TTS. The next step is `storyboard.md`.

Read with this step: `engagement.md`, `story-craft.md`, `studio-craft.md`, and `program-forms.md`, unless kind is `product-screencast` (outcome-first rules in `program-forms.md` + `product-picture.md`; `story-craft.md` → "No fluff" still applies). When `programForm` is `technical-story` (a product or engineering change told as a 5–8 minute story), also read `technical-story.md` for the beat order and the what → why → consequence rule, whatever the kind. Marketing cuts (`marketing-readiness.md`) are written to win a feed: the hook is on screen inside two seconds.

## 1. Output

- `story/screenplay.json` matching `../../../schemas/screenplay.schema.json` — `hook`, `emotionalTarget`, `viewerPromise`; per scene `sceneRole`, `viewerQuestion`, `wiifm`, `story`, `emphasis`, `pauseBeforeSeconds`, `holdAfterSeconds`, `musicCue`; `syntheticDisclosure` when the data is synthetic
- `narration.md` — canonical spoken text, one scene per heading, no phonetic respelling
- `story/screenplay.draft.json` — the draft before the cut, so the check can report what was cut
- `qa/narration-check.json` — from `scripts/validate-narration.mjs <jobRoot>` (deployed in `_shared\tools`), a PASS

## 2. The no-fluff rule (hard check)

Every line earns its seconds: it changes what the viewer knows or does. If it does not, cut it. One idea is said once.

Never spoken, ever: greetings; "in this video", "let me show you", "as you can see"; recaps; how the film was made; **versions, revisions, what changed since last time**; synthetic or demo data; jargon; filler adverbs. The full banned list and the redundancy rule are in `story-craft.md` → "No fluff". `validate-narration.mjs` fails on any hit, reports **fluff per minute**, and, with the draft beside the locked script, the **words-cut report** (runtime before and after, lines removed). A product word on the banned list ("the Version history panel") goes in `narrationAllowlist` with a reason; nothing else gets through.

Synthetic data is a caption or end card: set `syntheticDisclosure: { mode: "caption" | "end-card", text }`. Narrating it is a fail.

## 3. Rules

1. One idea per scene. One promise per film (`program-forms.md`). Spoken sentences stay short (~150 wpm; slower for documentary / ai-trust).
2. **Hook and result in the first five seconds.** The first sentence fits five seconds (≤ 12 words at 150 wpm), says the payoff or the pain, and the promise is named inside those five seconds. No greeting, logo recap, agenda, or nav tour.
3. Dramatic spine from `story-craft.md`. Exactly one `heroMoment: true`. Outcome-workflow / AI forms: pain → task → system acts → human reviews → result.
4. Default truth `FACT` when the source is given; tag `DRAMATIZED` / `COMPOSITE` only when you heighten or merge.
5. Owner-voice scripts stay canonical. Pronunciation is a lexicon/SSML layer in the synthesis input at render time — never respell the script.
6. Do not invent metrics, customer names, or product behavior. Unsourced numbers are omitted, not guessed.
7. On `product-screencast`, default `visualMode: screen` (`product-picture.md`). Write the causal chain as scenes; fill `uiProof` on every product claim. Do not jump start → payoff.
8. Do not narrate chrome. Name the result after it appears. If VO names a config or integration, a scene must show it. The voice speaks this locked text. A line names only what the cursor will move to (`cursor-flow.md`): one target per beat.
9. Technical stories: the hook is the problem, not the UI. Every code, log, or diagram beat says what happened, why, and the consequence — then the human consequence (a customer waiting, a bill, an agent who cannot act). Code beats follow product behavior → question → code → explanation → product result. The story is what the change does for the user, never a changelog.

Prefer:

`sceneRole: before` / `wiifm: "I don't spend Monday hunting the bad row."`

Avoid:

`Welcome back.` / `Since the last cut, the import now…` / `This is demo data, but…` / five consecutive scenes with no `sceneRole`.

## 4. Final check

- [ ] Hook in the first sentence, inside five seconds, promise named with it
- [ ] `validate-narration.mjs` PASS: zero hits, fluff per minute 0, words-cut report recorded
- [ ] No version, revision, process or synthetic-data talk; disclosure is a caption or end card
- [ ] Every viewer-facing scene has role, WIIFM, viewerQuestion
- [ ] One hero
- [ ] Schema validates
- [ ] Next step is `storyboard.md`

## 5. Dramatize a real incident (series and comic episodes)

When the brief is a real technical incident to be told as a comic or dramatic episode (a `series-episode`, or any film that heightens a real failure), transform the incident into a premise before writing scenes:

```text
REAL INCIDENT
     ↓
comic/dramatic premise
     ↓
character objective
     ↓
conflict
     ↓
escalation
     ↓
technical complication
     ↓
reversal
     ↓
payoff
```

Comedy craft belongs inside dramatization; it is not a separate step. Keep comedy inside the telling:

1. Establish the earnest goal.
2. Add a small, plausible obstacle.
3. Escalate with a technical misunderstanding (permissions, env, "it works on my machine").
4. Reverse: the "fix" reveals the real system rule.
5. Payoff teaches the takeaway without humiliating real people.

Tag every beat `FACT` / `DRAMATIZED` / `COMPOSITE`. Fictionalize before any external share (the `sarosh-writing` fictionalization reference; `series.md`). Series methodology, truth ledger and continuity are in `series.md`.
