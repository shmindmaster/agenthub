# Story craft (viewer-facing films)

Load this with `engagement.md` for every **viewer-facing** media-studio job that is not a product screencast. Product screencasts stay on the PDS story-experience gate. Series episodes use `series.md` for bible/continuity; this file is the reusable tension craft those episodes and every other film share.

A scene is a designed viewer experience, not narration with a slide attached.

## No fluff (hard check, every kind)

Only the most useful information in the least time. **Every narration line earns its seconds: it changes what
the viewer knows or does.** A line that does neither is cut, whatever kind of film it is. `scripts/validate-narration.mjs <jobRoot>`
measures this on the locked script and writes `qa/narration-check.json`; `write-story-review.py` fails `no-fluff`
without it, and the viewer-release gate will not ship without it.

Banned from narration (each hit is an error, not a style note):

| Class | Examples |
| --- | --- |
| greeting | hello, hi there, welcome, welcome back, thanks for watching, my name is |
| meta | in this video, today we'll, let me show you, let's take a look, as you can see, now we, next we, without further ado |
| recap | to recap, in summary, to sum up, as we saw, as mentioned, so that's |
| process | we built this, this was recorded, this scene / take / cut, the narration, voice-over, footage, how this film was made |
| version | version, v2, revision, revised, what changed, since last time, what's new, previously, changelog, release notes, iteration, latest build |
| synthetic | synthetic, demo data, sample data, test data, fake, dummy, placeholder, fictional, not real |
| jargon | leverage, seamless, robust, cutting-edge, best-in-class, game-changer, holistic, streamline, empower, unlock, powerful, intuitive, end-to-end |
| filler | just, really, very, actually, basically, simply, easily, kind of, sort of, you know, obviously, literally |
| redundant | a line that says ≥ 70 % of an earlier line again; a line that adds no new content word |

One idea is said once. Never any talk of versions, revision history, what changed since last time, or how the
film was made. No build or version chips on screen (`storyboard.md` owns the on-screen half of that rule).

**Synthetic data is disclosed on screen, never spoken.** When the job runs on synthetic data (`job.dataClass`
contains "synthetic" or `syntheticData: true`), the screenplay carries
`syntheticDisclosure: { mode: "caption" | "end-card", text }` and the narration never mentions it.

A word on the banned list that the product genuinely needs ("the Version history panel") goes in
`narrationAllowlist: [{ phrase, reason }]`. The reason is required; the allowlist is the only override.

The check also reports the **fluff per minute** score and, when `story/screenplay.draft.json` holds the draft
before the cut, a **words-cut report**: runtime before and after, lines removed. Keep the draft so the cut is
visible.

## Hook and result in the first five seconds

The first sentence fits in five seconds at the script's words-per-minute (≤ 12 words at 150 wpm) and says the
payoff or the pain. The viewer's promise (`viewerPromise`, or the hook scene's `wiifm`) is named inside those
five seconds. A film that opens on a logo, a title, a greeting, an agenda or a nav tour has already lost the
viewer; a marketing cut loses the feed (`marketing-readiness.md`: hook on screen inside two seconds).

## Dramatic spine

Use this order unless the brief is a single-beat clip (then: question → reveal → takeaway):

```text
Question → Stakes → Wrong intuition → Complication → Reveal → Demonstration → Implication → Takeaway
```

Map onto scenes with `sceneRole`:

| Role | Viewer job |
| --- | --- |
| `hook` | Payoff or pain in the first five seconds. No greeting, logo, agenda. |
| `before` | Felt current cost. The viewer recognizes Monday. |
| `tension` | The normal process breaks. Open a loop. |
| `reveal` | Show the change. Picture first, name it after. |
| `proof` | Hard case, number, or evidence. One claim. |
| `trust` | Human control, limit, or what it does not do. |
| `hero` | Exactly one protected hero moment per film. |
| `payoff` | Close the loop. Hold. |
| `cta` | One next step. Designed last frame. |
| `bridge` | Only when the cut would otherwise confuse. |

Conflict logic (same machinery as `series.md`, without becoming an episode):

```text
goal → obstacle → escalation → complication → reversal → payoff
```

If a stretch has no obstacle or reversal, it is a lecture. Cut it or give it stakes.

## Scene contract (writer + storyboard)

Every viewer-facing scene sets:

- `sceneRole`
- `viewerQuestion`
- `wiifm` (outcome or identity, not a feature name)
- `story.beforeState` / `story.tension` / `story.openLoop` / `story.payoff` as they apply
- exactly one `emphasis`
- `truth`

The film has:

- one `hook`
- one `emotionalTarget`
- one `viewerPromise`
- **exactly one** `heroMoment: true`
- `syntheticDisclosure` when the data is synthetic (caption or end card)

Prefer:

`Can it actually handle the messy case?` / `I don't spend Monday fixing this by hand.`

Avoid:

`Welcome to the fleet briefing.` / `Next we will cover architecture.` / `Since the last version, the import now…`

## Explainer path

Comprehension comes first: convert a technical question, failure, design choice or incident into this structure (`../../../schemas/explanation.schema.json`: `core_idea`, `plain_explanation`, `takeaway` required; `analogy`, `real_example`, `misconception`, `visual_plan`, `truth` optional):

```text
CORE IDEA          one sentence
PLAIN EXPLANATION  2–4 sentences
ANALOGY            memorable comparison
REAL EXAMPLE       what actually happened (FACT-tagged)
MISCONCEPTION      what people commonly get wrong
VISUAL PLAN        diagram / screen / animation intent
TAKEAWAY           what the viewer should remember
```

For a **film**, wrap that block in the dramatic spine above:

```text
Question → Stakes → Wrong intuition → Complication → Reveal → Demonstration → Implication → Takeaway
```

Do not ship the comprehension block as sequential slides. The film still needs tension and a reveal.

Rules:

1. Name the concept in one sentence the viewer can reuse at work.
2. Prefer show-then-tell: point to a visual plan before dense prose.
3. Define jargon once; then use it consistently.
4. Separate FACT (observed) from DRAMATIZED / COMPOSITE (storytelling).
5. Do not invent product behavior; if evidence is missing, say so.

Outputs: the explanation block (markdown); optional `visual_plan` notes for `direction.md` §6 (which visual); optional companion bullets for docs / learning cards. After the visual plan exists, compose the film through this studio (kind `explainer`, viewer-facing engagement). Do not load retired `product-demo*` skills.

Not in scope here: series continuity and privacy fictionalization (`series.md`), and Remotion implementation (request capability `video.programmatic-composition` when animation is needed; resolve Remotion through thirdPartyExtensions, do not vendor it).

## Filler test

A beat that is not hook, before-state, tension, reveal, proof, trust, hero, required transition, or CTA is filler. Kill it. A line inside a kept beat that does not change what the viewer knows or does is also filler; the narration check finds it.
