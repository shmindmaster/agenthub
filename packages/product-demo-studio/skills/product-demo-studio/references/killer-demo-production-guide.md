# The Killer Demo Production Guide
### A self-contained, repo-agnostic guide to producing — or knowing when *not* to produce — compelling product demo videos

<!-- version: 1.0 | self-contained edition -->

This guide is standalone. It assumes **no** prompt framework, companion files, benchmark repo, or specific infrastructure — any team can implement everything here with the tools named in Part 6 and the config in Appendix C. It merges three things into one: what makes a demo worth watching (Parts 1–4), how to produce it and gate its quality (Part 5), and how to automate the whole thing (Part 6).

**Companion guides (optional — this one works alone).** [The Product Experience Audit & Remediation Guide](Product-Audit-Remediation-Guide.md) runs **before** this one and fixes the product so the demo-worthiness gate in 5.2 has little left to block on. [The Visual Communication & Asset Generation Guide](Visual-Asset-Guide.md) runs **alongside** it, and owns the image/voice asset system, the marketing-surface visual plan, and website video that isn't a product demo. It holds the authoritative model configuration — check it before a billed run.

**Do the config in Appendix C first** — an output location, a narration provider + credentials, a seedable demo environment, and your brand tokens. Everything else follows from that.

---

## The one principle, and the two outcomes

**A demo is not about your product — it's an argument that the viewer's life gets better.** Every technique in this guide serves the one question the viewer asks every five seconds: *why do I care — what's in it for me?*

A production run has **two legitimate successful endings, and one wrong one:**

- **KILLER VIDEO** — the episode clears correctness *and* craft *and* persuasion. Ship it.
- **PRODUCT-READINESS FEEDBACK, NO VIDEO** — the product can't yet carry a demo that meets the bar. Deliver a specific, fix-oriented feedback report to the product/UX/engineering team instead of a video. If nothing clears the bar, ship zero videos and only the report.
- **MEDIOCRE-BUT-ACCURATE VIDEO** — technically correct but boring, cluttered, feature-centered, or with no moment that makes anyone lean in. This is the defect this guide exists to prevent. **Do not ship it.** One killer video (or zero plus a clear reason) always beats a catalog of adequate ones.

Correctness answers *is it true?* Craft answers *is the product good enough today to make something worth watching?* Persuasion answers *does it make a viewer feel what's in it for them?* You need all three.

---

# PART 1 — STRATEGY

## 1.1 Pick the kind of demo

"Make a demo" isn't one thing. This one choice sets length, pacing, voice, personalization, and whether you automate.

| Type | Job | Length | Automate? |
|---|---|---|---|
| **Sizzle / hook** (top of funnel) | Earn 30 more seconds; sell the *outcome* | 60–90s | Fully — where personalized variants pay off |
| **Guided / discovery-support** | After a call, show *their* workflow solved | 2–4 min | Semi — templated capture, tailored narration |
| **Onboarding / enablement** | Get a user to first value | Chapters of 1–3 min | Fully — high volume, low variance |
| **Internal / handoff** | Spec, bug repro, feature walkthrough | As needed | Fully — cheapest win; build the pipeline here first |

Quality over quantity, always.

## 1.2 Audience and WIIFM focus

Same craft, different tone and framing by audience type:

- **Compliance-heavy audiences** (healthcare, financial services, legal, regulated ops) — calm, credible, authoritative. Slower voice, obviously careful data (no fake PII, visible audit trails), "additive to your system of record" framing. Lead with trust and risk reduction, then efficiency.
- **Operational audiences** (logistics, field ops, sales floors, SMB back-office) — ROI- and speed-forward. Punchier, friendlier, concrete numbers early.

Two principles that generalize:

1. **Discovery-led even in the demo.** The strongest format is often a guided demo sent *after* a conversation, showing the prospect's own multi-system reality getting a new layer — explicitly *additive, not rip-and-replace*. It should provoke "could it also do X?", not close a sale. A conversation-opener with a play button.
2. **Personalize the data to the audience.** The seeded environment should feel like the viewer's world — the right entities, jargon, believable volumes. Generic sample data is the tell that says "not built for you."

---

# PART 2 — THE PERSUASION LAYER

## 2.1 WIIFM laddering — the core move

Three rungs; most demos never climb past the first:

- **Feature** — what it is. *"Auto-reconciliation matches every line."*
- **Outcome** — what it gets them. *"Close the month in an afternoon, not a week."*
- **Identity / stakes** — who they become, or escape. *"You walk into Monday's review already done — nobody's chasing you for numbers."*

Feature-only is the default failure. **The great ones land on the top rung at least once**, at the payoff. Test: write the one-line WIIFM for every segment *before* the narration — if you can't, it's a feature tour; cut it or re-anchor it. Speak in the **viewer's units** — hours, dollars, headcount, risk, weekends — not "efficiency" or "10x." *"About four minutes instead of three days"* beats *"dramatically faster."*

## 2.2 Narrative architecture

The arc — Hook → Action → Payoff → Guardrail → Close — is the skeleton. What makes it dramatic:

- **Cold open / in medias res.** Start at the moment of pain or magic — never a login screen. The first frame carries tension.
- **Make the "before" felt, not stated.** Show the cost of the status quo viscerally for 3–5s. Relief needs something to be relieved *from*.
- **The hero moment.** Every great demo has exactly **one** reveal where the product does the almost-unfair thing. Build the whole video around protecting it. Three ways to kill it: burying it mid-feature-list, having three competing ones, or rushing past it. Stage it — a beat of near-silence before, a slow push-in, one sound cue, then hold on the result.
- **Open loops.** Tease early, pay off late. One or two per video.
- **Contrast, shown not told.** Value is legible only against an alternative — cut old-way → new-way, or split-screen. The gap between effort-in and result-out *is* the drama.
- **Denouement discipline.** After the hero moment, get out fast — one takeaway, one next step, end card.

## 2.3 Making "impressive" legible — the problem-solving demo

Impressive isn't "it works." It's *watching a genuinely hard thing handled cleanly* — and most demos get this backwards:

- **Demo the hard case, not the trivial one.** The messy 500-row file, the ambiguous request, the edge case that would eat a human's afternoon. A flawless happy-path on trivial input looks like a toy.
- **Show a *taste* of the work, then the result.** Hide all the mechanism and it looks trivial; show all of it and it looks slow. Flash the complexity for two seconds, *then* the clean result. The glimpse is what makes the result impressive.
- **"It just works" is the enemy of impressive.** Give just enough visible mechanism that the viewer knows a hard problem was solved.
- **For AI products specifically:** the wow is rarely raw speed — it's *it understood what I meant*, *it caught what a human would miss*, or *it handled ambiguity gracefully*. Show the reasoning transparently enough to earn trust, put the human-in-the-loop control right beside it (that's also your guardrail), and let it handle a genuinely hard input. Demos that only ever show perfect inputs make buyers *more* suspicious.

## 2.4 Emotional register

Flat is forgettable. Decide, before scripting, **the one feeling the viewer should have at the payoff** — relief, confidence, delight, "finally" — and engineer toward it with pace, music, silence, and word choice. Add **micro-delights** along the way (a status snapping to "Approved," a number resolving), and **humanize the persona** — a real person with a real Monday, not "User A."

---

# PART 3 — THE CRAFT LAYER

## 3.1 The cursor

The real OS cursor is the enemy — it jitters, it's tiny, it moves nervously. Synthesize it.

- **Eased motion,** ~400–600ms per deliberate move, decelerating into the target. Linear movement,
  jitter, unexplained teleporting, and decorative wandering fail the craft gate.
- **Settle before and hold after a click** — pause at least ~250ms on target, perform the real
  action, then hold at least ~500ms so cause and result both register.
- **Enlarge it** to 150–200% for mobile or embedded delivery. A click uses a restrained,
  semi-transparent brand-color radial pulse for ~300–400ms. Do not use a persistent yellow
  follow-the-pointer spotlight.
- **Differentiate interaction evidence:** click = radial pulse; drag = held state or short trail;
  hover = the product's native hover state with no extra overlay; shortcut-driven action = a
  reproducible keystroke overlay.
- **One move per idea;** never drift while narrating something stationary. **Hide it** during full-screen explanations and result reveals.
- **The cursor is an actor** — it can hover to indicate, hesitate to show a decision, trace a path (this flows into that).

## 3.2 Directing attention (in order of power)

1. **Snap to the region of action** — reframe over ~300–500ms, hold through the action, then pull
   back when context is needed. Use at most one zoom change per beat. Do not drift over UI like a
   Ken Burns treatment.
2. **Spotlight / dim** — 40–60% dark overlay everywhere except a cut-out.
3. **Animated bounding box** — rounded, brand accent, 2–3px, stroke drawing on, faint glow. Reveal synced to the narration beat; **remove it the instant you're done.**
4. **Callout + leader line** — ≤4 words, for naming not explaining.
5. **Motion arrows / underlines** — to trace a path the eye should follow.

Hard rules: **≤2 annotations at once**, **reveal progressively**, and hold text for at least
`word count / 2.5 + 0.5 seconds`.

## 3.3 On-screen storytelling

- **Seed data that tells a story** — not random rows, but *the overdue $12,400 invoice from the customer who always pays late*. Relatable specifics stick; random data reads as fake.
- **Build complex screens progressively** — animate a dashboard in panel-by-panel, synced to narration.
- **Speed ramps as punctuation** — real-time for the key interaction, fast-forward the boring middle, snap back for the payoff.
- **Kinetic type for the ONE number** — animate the single figure that matters (*"3 days → 4 minutes"*).
- **Spatial continuity** — move through the UI coherently; don't teleport.
- **Design the end card** — outcome restated, next step, logo, link/QR. The last frame is what they screenshot.

## 3.4 Framing

Capture at a device scale factor of at least 2. Derive effective delivery density from the actual
viewport, delivered crop, and delivery dimensions; every delivered crop must retain at least 1×
pixel density so it is never upscaled. Keep the
action in the upper-center hot zone and validate at the smallest delivery size. Prefer 100% browser
zoom plus composition-level reframing; a fixed 110–125% browser profile is acceptable only when
documented, deterministic, and representative of normal product use.

## 3.5 Pacing and pauses

The unit is **setup → action → result → let it land → next.**

- **Let the result land** — hold 0.5–1.5s of near-silence after a payoff. The most common mistake is barreling past the exact moment you wanted felt.
- **Pause before the payoff too.**
- **Kill dead time ruthlessly** — cut bounded loading/waits or speed-ramp them 4–8×; render text
  entry as a chunk or at 3–4×. Preserve honest latency context, and never hide missing feedback or
  a product defect by editing.
- **Match motion to voice** — if the voice explains, the screen is still; if the screen acts, the voice steps back.

---

# PART 4 — NARRATION & VOICE

## 4.1 Writing for the ear

Second person, active voice, present tense. Short sentences, one clause each. **140–160 WPM.** **Say the value while the screen shows the mechanism** — never narrate what's already visible ("now I'm clicking the blue button" is the number-one sin).

## 4.2 Structure

Hook in the first 5–8s — lead with the outcome or tension, never "Hi, welcome to…". **The first sentence must carry the payoff or the pain.** Problem → tension → resolution. One idea per scene. Close on one clear next step.

## 4.3 Rhetoric and delivery

- **Rule of three:** *"No spreadsheets. No chasing. No Monday scramble."*
- **Antithesis:** *"Three days of work, done before your coffee's cold."*
- **Rhetorical question:** *"What if reconciliation just… did itself?"*
- **Concrete over abstract:** *"the $12,400 invoice,"* not *"the transaction."*
- **Vary pace and pitch** — slow down and drop pitch for the important line (gravitas).
- **Pause before the key word:** *"And it's… done."*
- **Round for the ear, precise on screen** — say *"about four minutes,"* show `4:12`.
- **Lead the eye for actions, lag it for results** — *"watch the total"* a half-beat before it changes; name a result a half-beat after it appears.
- **Scriptless moments** — let the hero moment play in near-silence with a single sound cue.
- **Center the viewer** — count your "we"s; if they outnumber your "you"s, rewrite.

## 4.4 Voice selection

Warm, credible, mid-energy — never the over-produced announcer. Match to audience (compliance-heavy = calmer, authoritative; operational = friendlier, quicker). **One voice across your library** builds brand. Audition at least three candidates on your real script; never approve a voice on its name or a vendor's general recommendation. Silence is a tool.

## 4.5 Sound design (the cheap secret weapon)

A quiet UI click on interactions, a soft whoosh on major transitions, a very low music bed (–24dB, felt not heard) ducked under narration. Almost nobody does it; it's the fastest way to look expensive.

## 4.6 The timed script (single source of truth)

The script is a structured, timed document — it's also what makes automation possible, since capture, voice, and edit all render from it.

```yaml
scene: 03_reconcile
narration: |
  Here's the part that used to take all morning. [pause:0.4]
  Watch — it matches *every* line automatically. [emphasis:every]
on_screen:
  action: click("#reconcile")
  wait_for: "#results-ready"
annotations:
  - type: spotlight, target: "#results-panel", at: "matches"
  - type: zoom, target: "#total", scale: 1.6, at: end
hold_after: 1.2        # let the result land
voice: { rate: 0.95, style: confident }
wiifm: "close the month without chasing anyone"   # every segment must have one
```

Mark pauses and emphasis explicitly (one stressed word per sentence, not whole phrases). `hold_after` and the `at:` cues are where engagement lives — they sync the eye to the ear. Front-load each scene's payoff in its first sentence.

## 4.7 Narration provider setup

<!-- canonical-model-config: Visual-Asset-Guide.md -->

### Choosing a provider (2026)

Provider choice is swappable; use a tier by job rather than one tool for everything:

- **Pre-rendered hero narration (quality ceiling):** ElevenLabs v3, or a licensed-voice enterprise tool where voice licensing matters.
- **Scaled / cost:** OpenAI Speech API, or Google Chirp 3 HD (has closed much of the quality gap cheaply).
- **Emotion-forward:** Hume Octave 2.
- **Real-time / interactive surfaces:** Cartesia Sonic 2 (~90ms).
- **On-prem / data can't leave your infra (compliance):** open-source Chatterbox or Fish Audio on your own GPU.

Pick a default, name it as *your* profile, and never switch providers silently. A common two-tier default: a premium voice for flagship hero demos, a cheaper API voice for the scaled/personalized long tail. The rest of this section is a fully worked reference implementation for one common choice (OpenAI Speech API); adapt the field names for whichever provider you standardize on.

### Reference implementation — OpenAI Speech API

**Runtime verification is load-bearing, not precautionary.** Model IDs, status, voice rosters, and pricing drift, and provider docs routinely contradict each other. **Resolve status against the deprecations page, not the model catalog** — the catalog conflates model families with snapshots, and a "Deprecated" badge there usually means *one snapshot* is retiring, not the family. Check before every billed run; never start on a sunset snapshot.

**Models and voices (verify each run).** This guide does not maintain its own TTS model table. The authoritative model configuration for TTS, image, and generative video lives in [Visual-Asset-Guide.md](Visual-Asset-Guide.md):

- **TTS deprecations and the `gpt-4o-mini-tts` family** — see §0.1
- **Image model status** — see §0.2
- **Generative video shutdown** — see §0.3
- **Corrected narration model and provider rules** — see §5.1
- **Voice roster and audition rules** — see §5.2

Resolve every model and voice status against that guide before a billed run.

**Voices:** built-in roster changes (observed 11–13). Query the current list at runtime. Known at last check: `alloy`, `ash`, `ballad`, `coral`, `echo`, `fable`, `nova`, `onyx`, `sage`, `shimmer`, `verse`, `marin`, `cedar` — with **`marin` and `cedar` recommended for best quality**, so start auditions there. Voices are optimized for English. Custom voices: discover eligibility at runtime; never auto-clone; requires a consent recording plus a sample recording, and is limited to eligible organizations.

**⚠️ Disclosure requirement:** provider usage policies require a **clear disclosure to end users that a synthetic voice is AI-generated**. Any narrated video shipped to customers or the public needs that disclosure — an on-screen credit, end-card line, or description note. Add it to the delivery checklist; it is not optional and it is not covered by a generic AI disclaimer elsewhere on the site.

**Request fields:**
- `model` — resolve live.
- `voice` — built-in name or eligible custom voice.
- `input` — text. Current limit ~2,000 input tokens (was ~4,096 chars; verify). Demo segments are short, so this rarely binds; if a segment approaches it, it's too long for one beat — split it.
- `instructions` — concise voice/style/delivery, ≤~35 words (see presets below).
- `response_format` — `pcm` (post-processing), `flac`/`opus` (archival), `aac` (YouTube/Apple delivery), `mp3` (preview).
- `speed` — 0.25–4.0, **set per segment**. Start ~0.97; 0.94 for dense/number-heavy beats, up to 1.0 for light setup. This operationalizes 140–160 WPM and "vary the pace."

**Instruction / delivery presets** — where vocal dynamics and the episode's emotional target get realized. Pattern:

> *"{register}. {pace}. Emphasize the one key word per line; slow and lower the pitch on the payoff line; a deliberate pause before the result. Never announcer-flat or salesy."*

Example presets by audience (starting points to audition, not fixed assignments):

| Audience type | Emotional target | Instruction preset (≤35 words) |
|---|---|---|
| Healthcare / care | Calm relief, trust | "Calm, warm, reassuring. Unhurried. Land results gently. Emphasize one key word per line; pause before the result. Never bright, salesy, or sentimental." |
| Finance / audit | Confident precision | "Precise and composed. Clear on figures. Confident, not robotic. Emphasize numbers and outcomes; slow slightly on the payoff. No hype." |
| Legal | Senior, exact | "Measured and senior. Exact terminology. Deliberate pace. Trustworthy, never theatrical. Emphasize the key term per line; pause before the conclusion." |
| Ops / dealer / field | Practical momentum | "Grounded and practical. Peer-to-peer confidence. Direct, no hype. A touch of momentum into the payoff; emphasize the outcome, not the feature." |
| Logistics / SMB | Approachable competence | "Plainspoken and approachable. Easygoing but competent. Conversational pace. Emphasize the result; keep it human, never corporate." |

Record the resolved `instructions` and `speed` per segment in the episode manifest — delivery is part of the reproducible config.

**ASR / transcription (the Audio QA gate depends on it).** The speech endpoint returns audio only. Word-level timestamps — needed to compare final narration against the validated script and to build caption files — come from a transcription model (e.g. current `gpt-4o-mini-transcribe`). Don't hand-align captions or QA when timestamps are available.

**Caching.** Cache audio by a hash of provider, model, voice, input, instructions, speed, format, and pronunciation map; reuse exact hits; never duplicate a successful request across API keys. (Because `instructions` is in the hash, changing delivery correctly busts the cache.)

**Credentials.** Resolve keys from the environment at runtime; probe with a non-generating auth check before use; never send one provider's key to another; HTTP 429 stops the run.

**Pricing.** Re-check at runtime; don't hardcode. As of mid-2026, `gpt-4o-mini-tts` was ~$0.60 / M text-input tokens and ~$12 / M audio-output tokens, while the legacy tts-1 line bills per *character* (~$15 / 1M for tts-1, ~$30 / 1M for tts-1-hd) — different units, so don't compare the numbers directly. Batch text endpoints (for script/QA, *not* TTS) run ~50% cheaper. Estimate audio-output tokens from measured narration duration during the audition step so a billed run has a cost estimate first.

**A note on generative video.** Do not plan any part of this pipeline around text-to-video generation. OpenAI's Videos API and the entire Sora 2 model line are scheduled to shut down **2026-09-24 with no recommended replacement**. Deterministic screen capture (Part 6) is the durable architecture, and it's the only one that can satisfy this guide's accuracy gates anyway — a generated video of your product is a fabricated claim about software that doesn't exist.

### Delivery format standards

- **Video:** H.264 High / progressive / 4:2:0 / native fps, MP4 Fast Start.
- **Audio:** AAC-LC 48 kHz stereo, target −16 ±1 LKFS, true peak ≤ −1 dBFS (ITU-R BS.1770-5).
- **Color:** BT.709.
- **Captions:** W3C prerecorded captions, **burned into the master**; keep SRT/VTT/transcript in the working folder for QA/accessibility, not the delivery folder. DCMP caption-rate standards.
- **Cut-downs:** the social/teaser/GIF/vertical family re-uses the master's audio; the 9:16 vertical keeps captions always on (most social is watched muted).

---

# PART 5 — THE PRODUCTION PROCESS & QUALITY GATES

This is the operational process. It runs the same whether a human follows it or an LLM agent does (Appendix B is a runnable version). It gates correctness, craft, and persuasion, and it can end in either outcome.

## 5.1 The process, step by step

**0. Know your repo state and pick real, working functionality.** Choose a workflow that actually works end-to-end in a real (deployed or local) environment against synthetic data. If the feature is half-built, finish it or pick another — never demo mocked screens, hard-coded results, recording-only logic, or edited-over broken behavior.

**1. Design candidate episodes.** Prefer several focused videos over one tour; prefer one killer video over several adequate ones. Default 45–120s, three minutes max. Each candidate targets one persona and one problem, demonstrates one clear outcome, includes one trust/safety/human-control guardrail, stands alone, and reaches value fast. Declare up front, per candidate: the **hero moment** (exactly one), the **before-state** it will *show*, the **WIIFM at payoff** (outcome/identity, not feature), the **emotional target**, and the **cold open**. Structure: Cold open → Hook (5–8s) → Before-state (felt) → Action → Hero moment (staged) → Payoff (held) → Guardrail → Close.

**2. Demo-worthiness assessment (this decides video vs feedback).** Before committing any episode, walk its real workflow in the live product and score it against the **Demo-Worthiness Rubric (5.2)**. For each failure, classify it:
- *Capture-fixable* — resolvable at capture/edit with no product change (small UI → zoom; slow step → cut/speed; busy screen → spotlight). Does **not** block.
- *Product-fix-required* — a UX property no editing can hide. **Blocks**; becomes a feedback item.

Per-episode verdict: **PASS** (no product-fix-required defects), **CONDITIONAL** (only capture-fixable — proceed, recording the exact techniques), or **FAIL** (product-fix-required defects make a killer demo impossible today — do not produce; route to the feedback report). Also confirm a real in-product hero moment exists. Produce only PASS/CONDITIONAL episodes; if all FAIL, ship zero videos and only the report. **Never downgrade the bar to ship something.**

**3. Truth sheet + accuracy.** For each surviving episode, write a truth sheet: persona/permissions, seeded entities/identifiers, expected counts/statuses/dates/values/calculations, expected outcome, claims shown. Verify it against the database/APIs/app before recording. During QA, confirm every visible value matches source and real behavior; reject any take with stale state, wrong values, impossible states, placeholders, or unexplained errors.

**4. Storyboard.** One narration segment = one visible beat. Per segment: ID, on-screen action, expected state, spoken text, pronunciation notes, emphasis, pauses, expected audio duration, timeline position, and a one-line WIIFM. Encode the craft/persuasion beats: cold-open and hook placement, where the before-state is shown, the hero moment's exact placement and staging, hold-for-result moments, dead-time cuts, speed-ramp points, kinetic-type callouts, and the eye-direction cue (≤2 at once, progressive, removed when done). Enforce a **pattern-interrupt cadence:** no stretch longer than ~15s without a change in pace, visual, or sound.

**5. Narration.** Write and automatically validate narration (Part 4) *before* final capture; drive the recording plan from measured durations. Screen state appears before it's described; lead the eye for actions, lag it for results; never speed the workflow just to fit audio — fix the script first.

**6. Capture.** Drive the take from repository-owned Playwright coverage so it can be regenerated
when UI changes. Use fresh synthetic seeded data, a dedicated demo identity, clean profile,
deterministic locale/timezone, fixed resolution/scaling/zoom, hidden notifications/personal
accounts/bookmarks/unrelated tabs, and a shot list with exact controls before recording. Record in
bounded takes rather than one long session. Execute the storyboard's craft beats (synthesized
cursor, enlarged cursor + interaction-specific feedback, declared snap-to-region/speed treatment,
progressive screen build). Never let generated imagery invent product UI/text/numbers. Capture
**clean and un-annotated** — zoom/dim/boxes/captions are added at render, driven by the script, so
everything stays re-renderable. Each take produces a capture manifest (identity, timeline,
environment, console/page errors, failed requests, pass/fail). Any material fault blocks rendering.

**7. Render.** Assemble capture + zoom/pan + annotations + captions + audio from the script. Burn captions into the master; also produce SRT/VTT/transcript for QA/accessibility (kept in the working folder). Add sound design where the storyboard calls for it.

**8. Gates (5.3–5.4), then deliver (5.5).**

## 5.2 Demo-Worthiness Rubric

An episode is demo-worthy when its real workflow, as the product exists today, passes all of these. A failure is **product-fix-required** unless the pipeline can fully resolve it at capture/edit time.

1. **Single clear outcome** — one visible, valuable result in ≤3 min. *No crisp outcome flow → product-fix-required.*
2. **Fast to value** — minimal navigation/setup; no long mandatory preamble.
3. **Clean, believable states** — empty/loading/success/error states presentable; realistic data seeds cleanly; no placeholder/broken states on the happy path.
4. **Visual stability** — no layout shift, overflow, clipping, or broken responsive on the happy path.
5. **Legibility** — key UI/text readable at demo resolution or with reasonable zoom.
6. **Bounded, feedback-ed waits** — any wait is fast, cuttable, or shows progress. *A multi-second wait with no feedback on a core step → product-fix-required (missing loading state).*
7. **Discoverable primary action** — findable without tribal knowledge; no dead-ends.
8. **Deterministic and resettable** — reseeds and reproduces identically.
9. **A guardrail is visible** — a trust/safety/human-control moment exists to show.
10. **A hero moment exists** — one real in-product reveal worth building around. *None → the product may be useful but isn't demo-worthy yet.*
11. **Polish baseline** — consistent theming; nothing visibly unfinished on the happy path.

## 5.3 The Craft & Persuasion gate (fail closed)

Beyond correctness QA, the rendered master must clear the bar, reviewed on representative frames and full playback:

- **Cold open + hook** land in the first 5–8s; no preamble/tour/login opening.
- **Before-state felt** before the payoff.
- **Hero moment:** exactly one, staged and held — not buried, competing, or rushed.
- **WIIFM at payoff** lands on the outcome/identity rung, not the feature rung.
- **Emotional target hit** by pace/music/silence/word-choice.
- **No dead time;** results held in near-silence long enough to register.
- **One idea per beat;** the eye is directed every moment.
- **Pattern interrupt:** no >~15s stretch without change.
- **Voice** natural, paced, emphasized, with deliberate silence — not announcer-flat, not wall-to-wall.
- **Visual integrity:** no jank/shift/clipping/unreadable density; legible at mobile scale.
- **Close:** one clear takeaway; get out fast after the payoff.

If a master can't clear this even after re-edit: if the cause is capture/edit, re-edit; if it's a product-fix-required defect surfaced late, pull the episode to the feedback report. **Never ship a master that fails this gate to satisfy a quota.**

## 5.4 Correctness / QA gates

- **Screen QA:** data accuracy, readability, layout defects, cursor placement, correct role/permissions, no stray loading/error states, no sensitive info, branding consistency, no unsupported claims.
- **Audio QA:** pacing, pauses, emphasis, pronunciation, voice consistency, no monotony/clipping/noise/silence-dropouts, consistent volume, music ducking. Transcribe the final narration and compare to the validated script with **word-level timestamps** (flag missing/added words, wrong names/numbers, drift).
- **Sync QA:** each segment matches its beat; actions and speech in correct order; pauses align with transitions/reading; results stay visible after their narration; burned captions align with final audio.
- **Technical QA (fail closed):** valid checksum; expected codec/resolution/frame rate; valid audio stream; black-frame, freeze, silence-dropout, and clipping detection; representative frames extracted; complete manifests.
- **Compliance QA (fail closed):** if the narration is synthetic, the master carries a **clear AI-voice disclosure** (on-screen credit, end-card line, or description note) — this is a provider policy requirement, not a preference, and a site-wide AI disclaimer elsewhere does not satisfy it. Also verify: no real customer/patient/personal data visible; no third-party logos or trademarks the product isn't licensed to show; any generated imagery disclosed where a viewer would assume photography.

## 5.5 The two-outcome model + the feedback report

**Outcome A (video):** deliver finished master(s) for every PASS/CONDITIONAL episode that cleared 5.3–5.4, plus the cut-down family (Part 6.4). **Outcome B (feedback):** for every FAIL episode, deliver no video and write a **Product-Readiness Feedback Report** for the product/UX/engineering team. Produce the report whenever *any* candidate had product-fix-required defects, even if the run also ships videos.

The report is a build spec, not a critique. Header: product, assessed episodes and verdicts, the one-line reason it is or isn't demo-ready today. One entry per defect:
- ID + affected episode/flow.
- **Craft principle violated** (name it: fast-to-value, zero-dead-time, results-land, legibility, clean-states, visual-stability, single-outcome, guardrail-visible, hero-moment-exists).
- **Observed behavior** with evidence (frame/console/trace/timing reference).
- **Why it blocks a killer demo** — the concrete effect on a viewer.
- **Classification:** product-fix-required (blocks) / capture-fixable (for context).
- **Severity:** blocks / degrades / minor.
- **Suggested fix** — concrete and buildable, not "make it nicer."

Close with the **shortest path to demo-readiness:** the minimal set of product fixes that move each FAIL episode to PASS, ordered by leverage. Route the report to your team's issue tracker (one ticket per product-fix-required item) where possible — not into the video delivery folder.

## 5.6 Provenance & integrity (lightweight, portable)

Keep an evidence trail in a working folder in the repo (not the delivery folder): per-master production provenance (source commit, recorder commit, clean/dirty worktree, deployment identity), the truth/seed manifest, a **claim ledger** (every spoken or displayed claim: exact wording, episode/segment, evidence location, visible-on-screen, verdict), checksums, and tool versions. Scan for placeholders and PII, and run OCR/ASR critical-term checks against the truth sheet before publishing. Optionally embed C2PA / Content Credentials on exported masters as one provenance signal among several (check the current spec version before relying on it). Unsupported, inaccurate, or overstated claims block release.

## 5.7 Completion criteria

Complete only when: real, working functionality was used with story-shaped synthetic data; every candidate has a demo-worthiness verdict with evidence; every shipped episode has every visible value verified against its truth sheet, clears the craft/persuasion gate and the correctness gates, and has provenance recorded; **every master with synthetic narration carries its AI-voice disclosure**; every FAIL episode has a complete feedback entry with a suggested fix; narration is natural, paced, and correctly pronounced; audio/video/captions/actions are synchronized; requested cut-downs are produced and checked **and carry the same disclosure**; the delivery folder holds only correctly named final videos (or is untouched if zero passed). **Do not ship a video that fails the craft/persuasion gate. Zero videos plus a clear feedback report is a complete, successful run.**

---

# PART 6 — AUTOMATION PIPELINE

The whole process above can run as a code-driven pipeline that also emits **hundreds of personalized variants** from one template.

## 6.1 The six stages

1. **Script as source of truth** — the structured, timed script (Part 4.6). An LLM can draft the script, capture code, and composition from a feature description + walkthrough; deterministic checks and an isolated reviewer validate the script without an intermediate human gate. This is the real "automate with code" leverage.
2. **Deterministic capture** — drive the *real* app with **Playwright** (the 2026 default; Puppeteer if Chrome-only) against a **seeded demo environment** so runs are identical. Record via Playwright video / CDP screencast; trace-to-video tools can hide login/setup noise. Capture clean and un-annotated.
3. **Voice synthesis** — TTS from the narration field (Part 4.7), requesting **word-level timestamps** for sync + captions.
4. **Composite & edit** — **Remotion** (React, data-driven, version-controlled; renders through headless Chromium so any web styling reproduces) assembles capture + zoom/pan + annotations + captions + audio, parameterized by the script. Motion Canvas / Revideo are generator-style alternatives.
5. **Render** — local for one-offs; cloud/serverless fan-out (e.g. Remotion Lambda) for many variants (budget for memory-hungry headless Chrome).
6. **Distribute & measure** — host where you get per-viewer analytics (completion %, drop-off timestamps, CTA clicks); wrap personalized demos in per-prospect pages; feed drop-off back into stage 1.

## 6.2 Tools (mid-2026)

Capture: **Playwright** (+ seeded env). Composite/render: **Remotion** (on serverless for batch). Voice: per Part 4.7 (ElevenLabs v3 / OpenAI / Chirp 3 HD / Cartesia / Hume / open-source). Script + codegen: an LLM generating script, capture, and composition, independently machine-reviewed.

## 6.3 Personalization at scale

Because stages 1 and 4 are data-driven, one template emits N variants — each with the prospect's name, logo, seeded data that looks like *their* world, and audience-specific narration. A 75-second clip showing *their* month-end, generated the night after a discovery call, is the highest-ROI thing this pipeline unlocks.

## 6.4 Produce once, cut many

One clean capture → a family: **90s sales cut** → **30s social cut** (hero + payoff) → **10–15s teaser** (hero only) → **silent GIF loop** (the single most satisfying beat) → **vertical 9:16, captions always on**. Cut-downs re-use the approved master's capture and audio — no new claims, no new capture — so integrity and provenance carry through. Localization is nearly free with TTS.

## 6.5 Automate intermediate acceptance

Do not add human checkpoints during generation, review, or remediation. Use deterministic validation plus isolated reviewers, rerender and re-review until every acceptance criterion passes or evidence proves a genuine blocker, then present the final result to the human. Consider a real human voice for flagship heroes and TTS for the scaled long tail.

---

# PART 7 — METRICS: what "worth it" means

Track per demo: **completion rate / average watch %**, **drop-off timestamps** (rewrite that scene), **CTA click / reply rate**, and **meetings booked** (sales) or **time-to-first-value** and **ticket deflection** (onboarding). The reason to build this as a code pipeline is that fixes compound — fix the hook once, re-render the whole library.

---

# APPENDICES

## Appendix A — Recommended stack & first move

- **Capture:** Playwright + seeded env → video/trace
- **Voice:** a premium voice for heroes, a cheaper API voice for scaled variants, an open-source model where data can't leave your infra
- **Composite/render:** Remotion, on serverless for batch personalization
- **Script/codegen:** LLM-generated script + capture + composition, independently machine-reviewed
- **Distribute:** analytics-enabled host with per-prospect pages

**First move:** don't start with the flagship. Build the capture → voice → render loop end-to-end on the cheapest format (an internal walkthrough or onboarding chapter), then point the same machine at personalized demos.

## Appendix B — Optional runnable agent prompt

For teams using an LLM/agent to run the process. Fill the bracketed values.

```
Produce demo video(s) for <PRODUCT> from its repository at <REPO_PATH>, OR — if the product
cannot yet carry a demo meeting the craft and persuasion bar — produce a Product-Readiness
Feedback Report instead, and no video. Final videos go to <OUTPUT_ROOT>/<PRODUCT>/ (flat,
final masters only; cut-downs in a cuts/ subfolder). Working package (scripts, narration,
captions, truth sheets, manifests, QA evidence, claim ledger, checksums) stays in
<REPO_PATH>/<WORK_DIR>/. Feedback goes to <REPO_PATH>/<WORK_DIR>/feedback/ and, where a tracker
exists, one ticket per product-fix-required item.

Two outcomes are acceptable: a killer video for every episode that clears the bar, or a
feedback report for every episode that does not. A mediocre-but-accurate video is not.

Follow this guide's process (Part 5): 0) pick real working functionality; 1) design candidate
episodes, each declaring its hero moment, before-state, WIIFM-at-payoff, emotional target, and
cold open; 2) run the Demo-Worthiness Assessment against the live product, classify each gap as
capture-fixable or product-fix-required, and verdict each episode PASS/CONDITIONAL/FAIL —
produce only PASS/CONDITIONAL, route FAIL to the feedback report, and if all FAIL ship zero
videos; 3) truth sheet + accuracy verification; 4) storyboard with one-beat-per-segment and the
encoded craft/persuasion cues; 5) write and automatically validate narration before capture; 6) capture clean,
deterministic, un-annotated takes with a capture manifest; 7) render with burned captions and
sound design; 8) pass the Craft & Persuasion gate (5.3) and the correctness/QA gates (5.4); then
deliver per 5.5 and record provenance per 5.6. Do not claim completion without verified evidence,
and never ship a video that fails the craft/persuasion gate.

Return: the run outcome (video / feedback-only / mixed); each episode's verdict with the
deciding defects; for delivered videos — accuracy, voice/narration QA, craft-gate result,
screen/audio/sync/technical QA, cut-downs, and final filenames; for blocked episodes — the
feedback report location, count/severity of product-fix-required items, and the shortest path to
demo-readiness; working-package location; remaining blockers or limitations.
```

## Appendix C — Config checklist (set these per repo before running)

- **`<OUTPUT_ROOT>`** — where final videos land (a shared drive/bucket). Masters are flat and named `<Product>-<NN>-<Episode-Title>-Demo-<Platform>.mp4` (`NN` zero-padded, sequence-aware — continue the folder's existing numbering; `Platform` = Desktop default, Mobile only for responsive episodes). Cut-downs go in `<OUTPUT_ROOT>/<PRODUCT>/cuts/`.
- **`<WORK_DIR>`** — a folder inside the repo for the working package (never in the delivery folder).
- **Narration provider + credentials** — the provider you standardized on (Part 4.7) and its keys resolved from the environment at runtime.
- **Seedable demo environment** — a real deployed/local app with a reset-and-reseed path and story-shaped synthetic data (no real PII).
- **Brand tokens** — accent color for annotations, logo, end-card, and the music bed/sound-design assets.
- **Voice profile** — the auditioned, approved voice(s) and per-audience instruction presets.
- **Issue tracker (optional)** — where product-fix-required feedback items become tickets.

## Appendix D — Pre-run validation checklist (before any billed run)

1. Resolve the current recommended speech-generation model and its status via the provider's models **and** deprecations endpoints — don't start on a sunset model.
2. Verify credentials with a non-generating auth check.
3. Verify current pricing; produce a pre-run cost estimate from measured narration duration.
4. Verify the current voice roster; confirm the approved voice is still available.
5. Verify the transcription model for Audio QA / caption timestamps.
6. Verify C2PA spec version if embedding credentials.
7. Confirm quota headroom with a live observation.
8. Record the resolved configuration (provider, model, voice, per-segment `instructions` and `speed`, formats) in the episode manifest.

---

## The one line

Every technique here reduces to one move: **stop showing what the product does, and start showing what the viewer's life becomes** — built around one protected hero moment, a felt before-and-after, and a payoff that lands where the viewer sees *themselves* winning. And if the product can't yet carry that, say so precisely — a clear product-readiness report is a better deliverable than a forgettable video.
