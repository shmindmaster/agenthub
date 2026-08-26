# The Visual Communication & Asset Generation Guide
### Fixing a text-heavy presence, and producing the images and narration that replace the words

<!-- version: 1.0 | self-contained edition -->
<!-- Guide 3 of 3. Bolts onto:
     1. Product-Audit-Remediation-Guide.md — fix the product
     2. Demo-Production-Guide.md — then demo it
     3. THIS GUIDE — and make the whole surface communicate visually -->

Guide 1 fixes the product. Guide 2 demos it. This guide covers everything in between and around: the **marketing and journey surfaces** a prospect meets before they ever see a demo, and the **image and voice assets** those surfaces and videos are built from.

It exists because of a specific, common failure: a company whose product, site, and demos are almost entirely **text**. That's not a cosmetic problem. It's a communication problem, a credibility problem, and — for anyone selling design, AI, or product capability — a self-refuting one.

**The one principle:** *an image earns its place by doing work text can't.* Not by filling space. The four jobs an image can do (§2.2) are the whole test; anything failing all four is decoration and should be cut, not commissioned.

---

## How this bolts on

| | [Guide 1](Product-Audit-Remediation-Guide.md) | [Guide 2](Demo-Production-Guide.md) | **This guide** |
|---|---|---|---|
| Question | Is the product good? | Is the demo compelling and true? | Does the surface communicate — and do we have the assets? |
| Scope | In-product workflows | Demo episodes | Marketing pages, journey surfaces, image + voice assets |
| Output | Working workflows + audit record | Killer video or readiness report | Visual plan, generated assets, corrected model config |

**Sequencing.** Run Guide 1 first (a beautiful page pointing at a broken product is worse than useless). Run the §3 survey any time — it's cheap and independent. Produce assets (§4–5) once the survey tells you *which* assets and *why*. Guide 2's videos consume the voice config in §5 and the brand/asset system in §4.

**This guide supersedes [Guide 2's §4.7 model table](Demo-Production-Guide.md).** Corrections are in §5.1. Apply them before your next billed run.

---

# PART 0 — MODEL CURRENCY: what actually changed

Read this first. Several things retired, one contradiction needs resolving, and one whole category is going away.

## 0.1 The TTS "deprecation" — resolved

<!-- canonical-model-config: Visual-Asset-Guide.md -->

The model catalog and the TTS guide contradict each other. The **deprecations page is authoritative**, and it settles it:

- **`gpt-4o-mini-tts` (the family) is NOT deprecated.** It remains the recommended speech-generation model, and it's the only one supporting `instructions` (delivery steering).
- **`gpt-4o-mini-tts-2025-03-20` (one snapshot) shut down 2026-07-23.** Replacement: **`gpt-4o-mini-tts-2025-12-15`**. If any pipeline you own pins that March snapshot, **it is already broken.** This is the single most urgent item here.
- **`tts-1` / `tts-1-hd` are NOT deprecated** — the catalog even shows tts-1 as "Default" — but they are **legacy**: no `instructions`, smaller voice roster, no `marin`/`cedar`, and billed per *character* (~$15 and ~$30 per 1M characters). Fine to run, wrong to build on.

**The distinction that explains the confusion:** *deprecated* = has a shutdown date and will die on it. *Legacy* = no longer updated, signals platform direction, expect eventual deprecation. A "Deprecated" badge in a model catalog usually flags **one snapshot**, not the family. **Always resolve against the deprecations page, never the catalog. All other guides in this repo defer to this file for TTS, image, and generative-video model status.**

## 0.2 Image models — one survivor

| Model | Status |
|---|---|
| **`gpt-image-2`** | **Current. The only image model with a future.** Default for all new work. |
| `gpt-image-1.5`, `gpt-image-1-mini`, `chatgpt-image-latest` | Shut down **2026-12-01** → `gpt-image-2` |
| `gpt-image-1` | Shuts down **2026-10-23** → `gpt-image-2` |
| `dall-e-2`, `dall-e-3` | **Already shut down** (2026-05-12) |

Standardize on `gpt-image-2` now; there is no migration decision to make.

## 0.3 Generative video — going away entirely

**The Videos API and every Sora 2 model shut down 2026-09-24 with _no recommended replacement_.** Do not architect website video around text-to-video generation.

This is strategically clarifying rather than limiting: Guide 2's **deterministic screen-capture pipeline is the durable path**, and it was always the only one that could satisfy the accuracy gates. A *generated* video of your product is a fabricated claim about software that doesn't exist. Real capture, real narration, programmatic assembly.

## 0.4 Notice periods (plan around these)

- **Generally available models:** ≥6 months notice.
- **Specialized variants** (chat/codex/deep-research variants): ≥3 months.
- **Preview models** (`preview` in the name): as little as **2 weeks** — never use for business-critical production unless you can migrate on days' notice.

Anything pinned to a `preview` model in a production asset pipeline is a standing outage risk.

**See Appendix D** for the dated migration calendar — what has already retired, what's coming, and which dates touch this pipeline.

---

# PART 1 — IS "TEXT-HEAVY" ACTUALLY A PROBLEM?

Yes — but not for the reason most people assume, and the usual fix makes it worse.

## 1.1 What's actually wrong

- **Scanning, not reading.** Visitors scan first and commit to reading only after something earns it. A wall of text has nothing to scan — no entry point, no hierarchy the eye can grab.
- **Some concepts are structural.** Architectures, workflows, integrations, before/after states are *spatial*. Rendering them as prose forces every reader to rebuild the diagram in their head — and most won't. You've outsourced your explanation to their working memory.
- **Undifferentiated.** Every competitor's text-only B2B page makes the same claims in the same words: production-ready, measurable ROI, compliance-first. Text can't distinguish you because the vocabulary is shared. Showing the actual thing can.
- **Unproven.** "We deliver X" is a claim. A screenshot of X is evidence. Text-heavy pages are claim-dense and evidence-poor, which reads as *can't show it* — especially damaging when the buyer is evaluating whether you can build things.
- **Self-refuting for design and product firms.** If you sell design thinking, UX capability, or product craft, an all-text surface is a live counter-argument. The medium contradicts the message. This is the sharpest version of the problem and it applies directly to anyone whose pitch includes "we make software people can actually use."

## 1.2 The failure mode that's worse than text

**Decorative stock imagery.** Generic handshakes, abstract blue networks, glowing brains, robot hands, "AI sparkle" motifs. These are worse than plain text because they add load without adding information, and they actively signal *generic vendor*. A text-only page reads as austere; a stock-photo page reads as fake.

So the fix is not "add images." The fix is **add images that do work** — and cut the rest.

## 1.3 The test

An image earns its place only if it does at least one of four jobs (§2.2). If you can't name which job, don't make it. This is the visual analogue of Guide 1's "does this feature deserve to exist" and Guide 2's "is this worth watching."

---

# PART 2 — THE FRAMEWORK

## 2.1 Read the surface as a journey, not a set of pages

Before scoring anything, map the surfaces a prospect actually crosses: entry (ads, search, referral) → landing/home → capability or service pages → proof (case studies, insights) → evaluation (pricing, FAQ, security/compliance) → conversion (contact, booking) → post-conversion (onboarding, docs). Visual deficits matter most at the points where **belief has to form** — proof and evaluation — and where **attention is won or lost** — entry and landing.

## 2.2 The four jobs an image can do

| Job | What it shows | Right medium | Never |
|---|---|---|---|
| **1. Show the thing** | The product, the artifact, the actual output | **Real screenshots / real captures**, lightly framed | Never *generate* your product's UI |
| **2. Show the structure** | Architecture, workflow, integration, sequence, before/after | Diagrams, flows, system maps | Never a diagram whose labels you can't defend |
| **3. Show the proof** | Data, results, comparisons, timelines | Charts, infographics, annotated screenshots | Never a chart with invented numbers |
| **4. Show the people / context** | Who this is for, where they work, the real-world environment | Photorealistic environmental imagery; **real** team photos | Never a *generated* photo of a real person |

**Anything that fails all four is decoration. Cut it.**

Note that jobs 1–3 are mostly **not** generative-image work — they're screenshots, diagrams, and charts built from real data. **Generative imagery's honest home is job 4** (and abstract/textural support). That single distinction prevents the most common and most damaging misuse.

## 2.3 The integrity rules (non-negotiable)

These carry over from Guide 2's claim ledger and apply to every asset:

1. **Never generate product UI.** Screenshots of real features only. A generated interface is a claim about software that doesn't exist — the visual equivalent of a fabricated benchmark.
2. **Never generate photorealistic images of real, identifiable people** — team, clients, testimonial subjects. Use real photography with consent.
3. **Never generate data.** Charts and infographics render numbers you can source. If the number isn't in a truth sheet, it doesn't get drawn.
4. **Never imply capability through imagery.** No robot hands, no glowing brains, no sparkle motifs standing in for a capability you haven't shown.
5. **Disclose AI-generated media** where a reasonable viewer would assume it's a photograph, and **always disclose synthetic voice** (§5.4 — this one is a policy requirement, not a preference).
6. **No trademarks, no watermarks, no third-party logos** in generated output — state this as an explicit constraint in every prompt.

---

# PART 3 — THE SURVEY METHOD

*This is the part the executor runs. Do not skip to generating images.*

The goal is a prioritized, evidence-backed list of **specific images for specific sections with specific jobs** — not a vague "add visuals" mandate.

## 3.1 Inventory

Crawl or manually walk every public surface. For each **page**, record: URL, page type, its job in the journey, primary audience, primary conversion action, and traffic/engagement data if available (sessions, scroll depth, bounce, time on page, conversion rate).

Then decompose each page into **sections** — hero, value prop, capability block, process, proof, objection handling, CTA, etc. Sections are the unit of work, not pages.

## 3.2 Score each section

For every section, record:

| Field | Question |
|---|---|
| Section job | What must the reader believe or do after this section? |
| Current content | Word count; existing media (type, real vs generated, quality) |
| Text density | Words per screen at desktop and mobile widths |
| Scannability | Is there a heading, a hierarchy, an entry point for the eye? |
| Concept type | Is the idea **structural** (spatial/sequential), **evidentiary** (data/proof), **experiential** (what it's like), or **declarative** (a simple claim)? |
| Job needed | Which of the four jobs (§2.2), or none |
| Deficit | Does the section fail to communicate without an image? |
| Evidence | Analytics, scroll drop-off, user quotes, sales objections |
| Priority | Now / Next / Later / No image |

**The concept-type field does most of the work.** Structural → diagram. Evidentiary → chart or annotated screenshot. Experiential → photorealistic or product capture. Declarative → usually *no image* (a claim doesn't become truer with a picture next to it).

## 3.3 Prioritize

Rank by: **journey position** (entry and proof surfaces first) × **deficit severity** × **traffic** × **effort**. Then apply two overrides:

- Any section where a **screenshot of the real product** would replace a paragraph of description → do it first. Highest credibility per unit of effort, zero generative risk.
- Any section making a **quantified claim** with no evidence shown → chart or annotated capture, sourced from a truth sheet.

## 3.4 Output

A **visual plan**: one row per approved image, carrying section, job, medium, spec (size, orientation, format), source (generated / screenshot / diagram / photography), prompt or build notes, and acceptance criteria. This is what §4 executes against. Sections that get **no image** stay in the plan with that decision recorded, so nobody re-litigates them.

## 3.5 Section-by-section defaults

Starting points for a B2B software/AI services surface. Adapt; don't apply blindly.

| Section | Typical job | Recommended medium | Notes |
|---|---|---|---|
| **Hero** | 4 (context) or 1 (the thing) | Real product capture, or photorealistic environmental | The single highest-stakes image. Avoid abstract. If the product is presentable, show it. |
| **Value prop / positioning** | Usually none | — | Declarative. Strong typography beats a picture. |
| **Capability / service cards** | 1 or 2 | Small real captures, or restrained iconography | Resist stock illustration; a tiny real screenshot outperforms a metaphor. |
| **How it works / process** | 2 (structure) | Diagram or flow | The clearest win in most audits. Structural concepts trapped in prose. |
| **Architecture / integration** | 2 | System map | Show what connects to what. Additive-layer stories need this most. |
| **Proof / case study** | 3 (proof) | Before/after, annotated capture, outcome chart | Numbers must be sourced. This is where belief forms. |
| **Industry / vertical pages** | 4 (context) | Photorealistic environmental, per vertical | The strongest use of generative imagery — show the reader's world. |
| **Team / about** | 4 (people) | **Real photography only** | Never generated. |
| **Testimonials** | 4 | Real photo, or none | Never generate a face. |
| **Pricing / packaging** | 2 | Comparison table, tier diagram | Structure, not decoration. |
| **FAQ / objections** | Usually none | — | Occasionally a small diagram for a structural objection. |
| **Security / compliance** | 2 or 3 | Control-flow diagram, certification marks | Concrete artifacts beat shield icons. |
| **Blog / insights index** | 4 or abstract | Consistent generated header system | Highest-volume generative use; needs a locked style system (§4.5). |
| **Article headers** | Varies by article | Generated header, or a diagram from the article | Reuse the article's own best diagram where one exists. |
| **CTA / contact** | Usually none | — | Reduce friction; don't add visual noise. |
| **Social / OG cards** | Varies | Templated generated or composed | Systematize — these are produced constantly. |

---

# PART 4 — IMAGE PRODUCTION

Model: **`gpt-image-2`** (§0.2). Requires **API organization verification** before use.

## 4.1 Which API

- **Image API** (`/v1/images/generations`, `/v1/images/edits`) — one prompt, one image. Use for batch/templated production.
- **Responses API** with the `image_generation` tool — multi-turn iterative editing, accepts file IDs, and the mainline model auto-revises your prompt (inspect `revised_prompt`). Use for art direction and refinement.

Both support quality/size/format customization and streaming (`partial_images` 0–3, each partial costs +100 output tokens).

## 4.2 Prompting fundamentals

- **Structure and state the goal.** Consistent order — background/scene → subject → key details → constraints — and name the intended use ("website hero," "blog header"), which sets the mode and polish level. Use short labeled segments or line breaks over one long paragraph.
- **Be specific about materials, textures, and medium** (photo, 3D render, watercolor). Add "quality levers" (film grain, macro detail) only when needed.
- **Control composition explicitly:** framing (close-up, wide, top-down), angle (eye-level, low), lighting and mood (soft diffuse, golden hour), and placement when layout matters ("subject centered with negative space on left" — essential when text overlays the image).
- **State exclusions and invariants:** "no watermark, no extra text, no logos or trademarks." For edits: "change only X" + "keep everything else the same," and **repeat the preserve list on every iteration** to prevent drift.
- **Iterate with small single changes** rather than one overloaded prompt. Debugging a long prompt is far harder than refining a clean base.
- **Multi-image inputs:** reference each by **index and description** ("Image 1: product photo… Image 2: style reference…") and describe how they interact.

## 4.3 Photorealism recipe

For job-4 imagery — the honest home of generative work.

- **Include the word "photorealistic" directly.** It strongly engages the model's photorealistic mode. Related cues that help: "real photograph," "taken on a real camera," "professional photography," "iPhone photo."
- **Prompt as if a real photo is being captured in the moment.** Use photography language — lens, lighting, framing.
- **Explicitly request real texture and imperfection:** pores, wrinkles, fabric wear, scuffs, everyday clutter.
- **Avoid words implying studio polish or staging.** Say "honest and unposed," "no glamorization, no heavy retouching."
- Detailed camera specs are interpreted loosely — use them for **look and composition**, not exact physical simulation.
- Use `quality: "high"` when detail matters; wide, low-light, or atmospheric scenes need extra detail about scale and atmosphere or the model trades mood for surface realism.

**Template:**

```
Create a photorealistic candid photograph of {subject} in {specific real environment}.
{Concrete physical detail: what they're doing, what they're touching, where they're looking.}
Shot like a 35mm film photograph, {framing} at {angle}, using a {focal length} lens.
{Lighting}, shallow depth of field, subtle film grain, natural color balance.
The image should feel honest and unposed, with real texture, worn materials, and
everyday detail. No glamorization, no heavy retouching.
Constraints: no watermark, no extra text, no logos or trademarks, no identifiable
real individuals.
```

For an industry/vertical page, replace `{subject}` and `{environment}` with the reader's actual world — a service advisor at a dealership counter mid-morning, a clinic's front desk during intake, a dispatcher's desk with three screens. Specificity is what separates "this was made for me" from stock.

## 4.4 Text inside images

The model renders text far better than earlier generations, but it still needs constraints:

- Put literal copy in **quotes** or **ALL CAPS**, and demand verbatim rendering with no extra characters.
- Specify typography as constraints: font style, size, color, placement.
- **Spell tricky words letter-by-letter** — brand names especially. `Pendoah` → "P-E-N-D-O-A-H".
- Use **`medium` or `high` quality** for small text, dense information panels, and multi-font layouts.
- Say "ensure text appears once and is perfectly legible."
- Still verify every character by eye. **Text rendering remains a known limitation** — never ship in-image text unread.

For anything with heavy or precision-critical typography (pricing, legal, long headlines), **compose text in HTML/CSS or a design tool over a generated background** instead of asking the model to render it. Cheaper, editable, localizable, and always correct.

## 4.5 The brand consistency problem

**This is the biggest risk for a systematic image program**, and it's a stated model limitation: consistency for **recurring characters or brand elements across multiple generations** is not guaranteed. Ten blog headers generated independently will not look like a set.

Mitigations, in order of strength:

1. **Style anchor + edit workflow.** Generate one approved reference image, then produce variants via the **edits** endpoint using that anchor as an input image, with an explicit preserve list. This is the same "character anchor" pattern used for illustrated series, applied to brand.
2. **A locked style block.** Maintain one canonical paragraph of style language — palette, medium, lighting, grain, treatment — pasted verbatim into every prompt in the family. Version it.
3. **Multi-image style reference.** Pass the anchor as "Image 1: style reference" and instruct "apply Image 1's style to the new subject."
4. **Batch in one sitting** with identical parameters — drift is lower within a run.
5. **Human review against the anchor** before publish. Reject off-family output rather than shipping "close enough."

Also: **`gpt-image-2` does not support transparent backgrounds.** For logos, cutouts, or overlay assets, generate on an opaque background and run a downstream background-removal step. Plan that step into the pipeline — don't discover it at publish time.

## 4.6 Sizes, formats, cost

**Size constraints:** max edge ≤ 3840px · **both edges multiples of 16** · long:short ratio ≤ 3:1 · total pixels between 655,360 and 8,294,400. Above 2560×1440 (2K) is **experimental** and more variable. (Docs disagree on whether the max edge is `<` or `≤` 3840 — if 3840×2160 is rejected, use **3824×2144**.)

Useful valid sizes:

| Use | Size | Notes |
|---|---|---|
| Hero / wide banner | `1536x1024`, `2048x1152` | Square is fastest to generate |
| 2K hero | `2560x1440` | Upper reliability boundary |
| Blog header | `1536x1024` | Crop downstream to exact ratio |
| Square / social | `1024x1024` | General-purpose default |
| Portrait / mobile | `1024x1536` | |
| Vertical 9:16 | `1088x1920` | 1080 is **not** a multiple of 16 |
| OG card (1200×630) | Generate `1536x1024`, crop | 630 is not a multiple of 16 |

**Rule: generate at a valid size, then crop or resize downstream to exact platform specs.** Don't fight the multiple-of-16 constraint.

**Formats:** `png` default; `jpeg` and `webp` support `output_compression` (0–100). **JPEG is faster than PNG** — prefer it when latency matters.

**Cost (`gpt-image-2`), per image:**

| Quality | 1024×1024 | 1024×1536 / 1536×1024 |
|---|---|---|
| Low | $0.006 | $0.005 |
| Medium | $0.053 | $0.041 |
| High | $0.211 | $0.165 |

**Use `low` for drafts, thumbnails, and exploration** — it's genuinely strong and dramatically cheaper. Move to `medium`/`high` only for finals, small text, dense infographics, and close-up photorealism. A 40-image exploration at low quality costs about a quarter; the same at high costs about eight dollars. Explore cheap, finish expensive.

**Latency:** complex prompts can take up to **2 minutes**. Build async; never block a page render or a user-facing request on generation.

## 4.7 Known limitations to design around

- **Text placement and clarity** — improved but imperfect. Verify every character.
- **Consistency across generations** — see §4.5.
- **Composition control** — the model may struggle to place elements precisely in layout-sensitive compositions. If exact placement matters, compose the layout yourself and generate only the imagery.
- **Latency** — up to 2 min.
- **No transparent backgrounds** on `gpt-image-2`.

## 4.8 Moderation and error handling

Set `moderation` to `auto` (default) or `low`. Handle failures as normal API errors, but note that some are **user-correctable** and return `error.type = "image_generation_user_error"` — **do not blind-retry these**; the prompt or inputs must change. Branch on `error.code` as the stable discriminator; `moderation_blocked` may carry an optional `moderation_details` object with `moderation_stage` (`input` / `output` / `unknown`) and coarse `categories`. Use those for developer logs and remediation hints, keep the end-user message generic, and always log the request ID. Retry normally on transient `429`/`5xx`.

## 4.9 Acceptance criteria for every generated image

Before publish:

- [ ] Names its job (§2.2); is not decoration
- [ ] No fabricated product UI, data, or real people
- [ ] Every character of in-image text verified letter-by-letter
- [ ] On-family against the style anchor
- [ ] No watermarks, trademarks, or third-party logos
- [ ] Legible and correctly cropped at mobile width
- [ ] Alt text written — describing the **information**, not the picture
- [ ] File size and format optimized; no layout shift on load (dimensions reserved)
- [ ] Contrast sufficient behind any overlaid text
- [ ] AI-generation disclosed where a viewer would assume photography
- [ ] Provenance recorded (§7.1)

---

# PART 5 — NARRATION & VOICE

Supersedes Guide 2 §4.7's model table.

## 5.1 Corrected model configuration

**Use `gpt-4o-mini-tts`, pinned to `gpt-4o-mini-tts-2025-12-15`.**

- The **family is not deprecated**; only the `2025-03-20` snapshot, which **shut down 2026-07-23**. Migrate off it immediately if pinned.
- The 2025-12-15 snapshot brings roughly **35% lower word error rate** and better custom-voice performance.
- **`tts-1` / `tts-1-hd` are alive but legacy** — no `instructions`, smaller voice set, per-character pricing. Not suitable for narration: without `instructions` you get a flat read with no emphasis, pacing, or emotional control.
- **Resolve status against the deprecations page before every billed run.** The model catalog conflates families and snapshots.

## 5.2 Voices

Thirteen built-in voices: `alloy`, `ash`, `ballad`, `coral`, `echo`, `fable`, `nova`, `onyx`, `sage`, `shimmer`, `verse`, `marin`, `cedar`. **`marin` and `cedar` are recommended for best quality — start auditions there.** Voices are optimized for English. Query the live roster at runtime; it changes.

Audition ≥3 candidates on your real script (with product name, an acronym, a number, a date, a result, and the guardrail line) before approving one. Never approve on a voice's name or a vendor's general recommendation.

## 5.3 Delivery control via `instructions`

The `instructions` parameter is where Guide 2's vocal-dynamics and emotional-target work becomes real. It can steer **accent, emotional range, intonation, impressions, speed, tone, and whispering**. Keep it under ~35 words.

```
{Register}. {Pace}. Emphasize the one key word per line; slow and lower the pitch
on the payoff line; a deliberate pause before the result. Never announcer-flat or salesy.
```

Per-audience presets (starting points — audition, don't assume):

| Audience | Emotional target | Preset |
|---|---|---|
| Healthcare / care | Calm relief, trust | "Calm, warm, reassuring. Unhurried. Land results gently. Emphasize one key word per line; pause before the result. Never bright or sentimental." |
| Finance / audit | Confident precision | "Precise and composed. Clear on figures. Confident, not robotic. Emphasize numbers and outcomes; slow slightly on the payoff. No hype." |
| Legal | Senior, exact | "Measured and senior. Exact terminology. Deliberate pace. Trustworthy, never theatrical. Emphasize the key term; pause before the conclusion." |
| Ops / dealer / field | Practical momentum | "Grounded and practical. Peer-to-peer confidence. Direct, no hype. Momentum into the payoff; emphasize the outcome, not the feature." |
| Logistics / SMB | Approachable competence | "Plainspoken and approachable. Easygoing but competent. Conversational pace. Emphasize the result; keep it human, never corporate." |

Set `speed` **per segment** (0.25–4.0; start ~0.97, 0.94 for dense/number-heavy beats, up to 1.0 for light setup). Record the resolved `instructions` and `speed` per segment in the episode manifest — delivery is part of the reproducible configuration.

## 5.4 ⚠️ AI-voice disclosure is required

**Provider usage policies require a clear disclosure to end users that the voice they're hearing is AI-generated and not human.** This is a policy obligation, not a stylistic choice, and a generic site-wide AI disclaimer doesn't satisfy it for a specific narrated asset.

Satisfy it with an on-screen credit, an end-card line, or a description/caption note on every narrated video — and put it on the delivery checklist in Guide 2 §5.7 so it can't ship without one.

## 5.5 Output formats

`mp3` (default, general use) · `opus` (streaming, low latency) · **`aac` (preferred for YouTube, Android, iOS delivery)** · `flac` (lossless archival) · `wav` (uncompressed, low latency) · `pcm` (raw 24kHz 16-bit signed LE). For fastest response use `wav` or `pcm`; for reproducible prerecorded masters use a complete file response, not streaming.

## 5.6 Custom voices

Available to **eligible organizations only** (contact sales). Requires two recordings: a **consent recording** in which the voice actor reads one of the exact prescribed consent phrases — any divergence fails — and a **sample recording** from the same voice.

Constraints: ≤20 voices per organization; samples ≤30 seconds; formats `mpeg`, `wav`, `ogg`, `aac`, `flac`, `webm`, `mp4`.

Quality tips: record in a quiet room with minimal echo; professional XLR mic; 7–8 inches with a pop filter at consistent distance; **the model copies exactly what you give it — tone, cadence, energy, pauses, habits** — so record the exact voice you want and stay consistent in energy, style, and accent. Try several samples.

**Never auto-clone a voice.** Owner consent is mandatory and the consent recording is the mechanism.

This does not restrict the **owner's own local voice profile**, which is a
consented, purpose-recorded capability rather than a clone of a third party. It
is not produced here at all — see §5.8.

## 5.8 The owner's voice is local, not a provider choice

When the narration is the owner's own voice, no cloud provider is correct. They
cannot produce that voice; they return a different speaker who merely sounds
professional. The owner's speech also never leaves the machine.

```powershell
D:\Local-AI\ai.ps1 voice qwen-clone --voice sarosh --text "..." --out <segment.wav>
```

From Node, use `scripts/generate-narration.mjs --provider local`, which selects
this route automatically when the Local-AI control plane is present and handles
the PowerShell invocation correctly (`ai.ps1` must be called with the call
operator, not `pwsh -File`).

Every owner-voice segment is scored against an enrolled speaker profile before
it ships — `ai.ps1 voice score --voice sarosh <file>` — on two independent
embedders, against a floor derived from the owner's own recordings. Retro-scoring
148 already-delivered segments found 6 below that floor, one at less than half
of it.

Do not fix a mispronounced name by respelling it. Of five orthography variants
measured on this speaker, phonetic respelling was the **only** one to fail the
identity floor on both backends: changing the spelling to change the vowel
changes the speaker. Pronunciation belongs in a dictionary layer applied at
render time.

Everything else in Part 5 — voice selection, `instructions` steering, the pinned
`gpt-4o-mini-tts-2025-12-15` snapshot — continues to apply to every non-owner
voice.

## 5.7 Multilingual

The TTS model broadly follows Whisper's language coverage (50+ languages) though voices are English-optimized. With the same capture and burned-caption pipeline, **localization is nearly free** — regenerate narration per language against the same master. Worth doing for any international footprint.

---

# PART 6 — WEBSITE VIDEO THAT ISN'T A PRODUCT DEMO

Guide 2 covers product demos: sizzle, guided, onboarding, internal. But most video on a marketing site isn't a demo — and with generative video retiring (§0.3), the question "what do we build it from?" has a real answer that isn't obvious.

## 6.1 The source-material problem

You have exactly five honest sources. Everything shippable is a composition of these:

| Source | What it's for | Constraint |
|---|---|---|
| **Real screen capture** | Anything showing the product | Guide 2's deterministic pipeline |
| **Real filmed footage** | People, places, physical operations | Requires a shoot and releases |
| **Motion graphics** | Concepts, structure, process, systems | Built from your diagram system (§2.2 job 2) |
| **Stills in motion** | Atmosphere, context, transitions | Generated (§4) or photographed; slow push/parallax |
| **Kinetic typography & data** | Claims, numbers, outcomes | Numbers must be sourced |

**Generative video is not on this list and won't be.** If a video can't be built from those five, it shouldn't exist.

## 6.2 The types, and what each is made of

| Type | Length | Built from | Product capture needed? |
|---|---|---|---|
| **Explainer** — how the approach/concept works | 60–90s | Motion graphics + narration | No |
| **Hero loop** — ambient background on a landing page | 6–12s, silent | Capture or stills in motion | Optional |
| **Case study** — a customer outcome | 60–120s | Real customer footage/audio + capture + outcome charts | Usually |
| **Brand / company** — who we are | 60–90s | Filmed footage + stills | No |
| **Founder POV / thought leadership** | 60–180s | Talking head | No |
| **Data story** — a market or outcome argument | 30–60s | Kinetic data + narration | No |

## 6.3 The explainer is the highest-value one — and it's nearly free

**Your diagrams are already the storyboard.** The structural diagrams §3 tells you to build for the how-it-works, architecture, and process sections are exactly the frames an explainer needs. Build them once as layered vector assets and you get two outputs: static images for the page, and animated builds for the video.

That reframes the economics. An explainer isn't a separate production — it's a second render of the asset system you're already committed to. And it's the direct antidote to the §1 diagnosis, because the prose that was hardest to read (the structural, multi-system, sequential explanation) becomes the thing motion handles best.

Build order: diagram → progressive-build animation → narration over the build → captions. Same Remotion-style composition and the same script schema as Guide 2 §4.6.

## 6.4 Craft — what carries over, what changes

**Carries over from Guide 2:** hook in the first 5–8 seconds, one idea per beat, kill dead time, let results land, pattern interrupt every ~10–15s, one clear close, 140–160 WPM narration, sound design, and the whole persuasion layer (WIIFM, felt before-state, emotional target).

**What changes:**

- **The hero moment becomes the "click."** A demo's hero moment is the product doing something almost unfair. An explainer's is the instant the concept snaps into place — usually a diagram completing, a comparison resolving, or a number landing. Name it, stage it, hold it, same as Guide 2.
- **Silent by default.** Most website video autoplays muted and many viewers never enable sound. **The video must fully work with no audio.** Captions always on, and key points also carried by on-screen text or the visual itself — not narration alone. This is a harder constraint than demos face.
- **Autoplay hygiene.** Hero loops: silent, short, seamlessly looping, no hard cuts, low motion (respect `prefers-reduced-motion`), and never carrying information the page needs — they're atmosphere, and atmosphere must be skippable.
- **Poster frame is a real design decision.** It's what most visitors see. Design it; don't accept frame 0.
- **Performance is a UX gate.** Video is the heaviest thing on a marketing page. Lazy-load below the fold, reserve dimensions to prevent layout shift, cap hero-loop file size hard, and serve modern codecs with fallbacks. A video that hurts LCP has negative value regardless of how good it is — this is Guide 1's Lens 7 applied to your own marketing surface.

## 6.5 Integrity rules for non-demo video

The §2.3 rules apply, plus:

1. **Never synthesize a customer.** Testimonials are real people saying things they actually said, with written permission. No synthetic voice reading a "quote," no generated face, no actor implied to be a client.
2. **Never synthesize a colleague.** Founder and team video is filmed.
3. **Explainers may be fully synthetic** — motion graphics plus TTS narration — because nothing is being impersonated. **This is the honest home of synthetic narration.** Disclose the voice (§5.4).
4. **Every claim still enters the claim ledger.** A number in kinetic type is a claim exactly as much as a number spoken in a demo.
5. **Stock footage is subject to the §1.2 test.** Generic drone-over-city and time-lapse-office footage is the video form of decorative stock imagery — it fails all four jobs.

## 6.6 Delivery

Master per Guide 2's format standards (H.264 High, MP4 Fast Start, AAC-LC 48 kHz, −16 LKFS, BT.709, burned captions where used). Additionally, for web:

- **Hero loops:** muted, `playsinline`, `loop`, `autoplay`, poster frame set, no audio track at all.
- **Cut-downs:** the same produce-once-cut-many family from Guide 2 §6.4 — 9:16 vertical with captions always on, a short social cut, a silent GIF or looping clip.
- **Accessibility:** captions on everything with speech; a transcript on the page for anything over ~60s; no autoplay with sound, ever.
- **Disclosure:** synthetic narration disclosed on every asset, per §5.4.

---

# PART 7 — GOVERNANCE

## 7.1 Asset provenance

Maintain an **asset register** alongside Guide 2's claim ledger. Per asset: ID, job, surface/section, source (generated / screenshot / diagram / photography), model and snapshot, exact prompt and parameters, seed/reference anchors, generation date, reviewer, approval date, disclosure status, license/consent for any real people, and the checksum of the published file.

Rationale: when a model retires or a brand refresh lands, you can regenerate the family instead of archaeology. And when someone asks "is this real," you can answer in seconds.

## 7.2 Disclosure policy

Write it once, apply everywhere:

- **Synthetic voice:** always disclosed (§5.4 — policy requirement).
- **Generated photorealistic imagery:** disclosed where a viewer would reasonably assume photography.
- **Generated illustration / abstract / textural:** disclosure optional.
- **Diagrams and charts:** no disclosure needed, but **sources cited**.
- **Product screenshots:** never generated, so nothing to disclose — but note the version/build if the UI has changed.

## 7.3 Consistency governance

One owner for the style anchor. Version it. Re-review the whole family when the anchor changes. Reject off-family assets rather than shipping "close enough" — the value of a system is that it *reads* as a system.

## 7.4 Measurement

Track per surface: scroll depth, time on section, bounce, and conversion — **before and after**. The claim being tested is that the image did work text couldn't. If a section performs identically with and without the image, the image was decoration; cut it and update the defaults in §3.5. Feed the result back the same way Guide 2 feeds drop-off data back into scripts.

---

# APPENDICES

## Appendix A — Runnable agent prompt

```
Improve the visual communication of <SURFACE> for <ORG>, and produce the approved assets.
Write the survey, visual plan, and asset register to <WORK_DIR>/.

Principle: an image earns its place only by doing work text can't. Four jobs — show the
thing, show the structure, show the proof, show the people/context. Anything failing all
four is decoration; cut it, don't commission it. Decorative stock-style imagery (abstract
networks, glowing brains, robot hands, sparkle motifs) is worse than plain text.

Integrity rules, non-negotiable: never generate product UI (real screenshots only); never
generate photorealistic images of real identifiable people; never generate data; never
imply capability through imagery; disclose AI-generated media and always disclose synthetic
voice; no trademarks, watermarks, or third-party logos in generated output.

PHASE 1 — SURVEY. Inventory every public surface and decompose into sections. Per section
record: job, current content and word count, text density at desktop and mobile, scanna-
bility, concept type (structural / evidentiary / experiential / declarative), which of the
four jobs is needed, deficit, evidence, priority. Map sections onto the journey; weight
entry and proof surfaces highest.

PHASE 2 — PLAN. Produce a visual plan: one row per approved image with section, job,
medium, spec, source, prompt or build notes, and acceptance criteria. Record no-image
decisions explicitly. Prioritize (a) sections where a real screenshot replaces a paragraph
and (b) quantified claims with no evidence shown.

PHASE 3 — PRODUCE. Use gpt-image-2 (only image model with a future; requires org
verification). Explore at quality=low, finish at medium/high. Generate at a valid size
(edges multiples of 16, ratio ≤3:1, 655,360–8,294,400 px) and crop downstream to exact
specs. Lock a style anchor and produce family variants via the edits endpoint with an
explicit preserve list, restated every iteration. Verify in-image text letter-by-letter;
prefer HTML/CSS overlay for precision typography. No transparent background support —
plan a downstream background-removal step for cutouts.

PHASE 4 — NARRATION (if producing video). gpt-4o-mini-tts pinned to
gpt-4o-mini-tts-2025-12-15. The 2025-03-20 snapshot shut down 2026-07-23 — migrate off it.
Audition >=3 voices starting with marin and cedar. Steer delivery via instructions (<=35
words) and per-segment speed. Disclose the synthetic voice on every narrated asset.

PHASE 5 — VIDEO (if the plan calls for it). Build only from the five honest sources: real
screen capture, real filmed footage, motion graphics, stills in motion, kinetic type/data.
Generative video is unavailable and retiring — never plan around it. Prefer explainers built
from the diagram assets already produced in Phase 3 (one asset system, two outputs). The
video must work fully with sound off: captions always on, key points carried visually.
Never synthesize a customer or colleague; testimonials and team video are real people with
permission. Design the poster frame. Lazy-load, reserve dimensions, cap hero-loop weight.

PHASE 6 — GOVERN. Record every asset in the register with model, snapshot, prompt,
parameters, reviewer, approval, and disclosure status. Set a measurement baseline.

Return: the survey with per-section scores; the visual plan including no-image decisions;
assets produced with their acceptance-check results; any video produced and its sources;
the asset register location; model and snapshot configuration used; disclosure status per
asset; measurement baseline; limitations and anything deferred.
```

## Appendix B — Config checklist

- **`<WORK_DIR>`** — survey, visual plan, asset register, prompts, evidence
- **Asset output location** and naming convention
- **API organization verification** completed (required for GPT Image models)
- **Style anchor** — approved reference image plus the canonical style block, versioned
- **Brand tokens** — palette, type, logo files, spacing
- **Screenshot pipeline** — the same seeded fixture and reset command from Guides 1 and 2
- **Background-removal step** for cutout assets
- **Voice profile** — approved voice, per-audience `instructions` presets, pinned snapshot
- **Disclosure copy** — the exact wording used for AI imagery and synthetic voice
- **Analytics baseline** captured before changes

## Appendix C — Pre-run validation

1. Resolve current image and speech model status **against the deprecations page**, not the catalog.
2. Confirm `gpt-image-2` availability and that org verification is complete.
3. Confirm the speech snapshot is `gpt-4o-mini-tts-2025-12-15` (or newer) and **not** `2025-03-20`.
4. Verify the live voice roster; confirm the approved voice still exists.
5. Verify credentials with a non-generating auth check.
6. Re-check pricing; produce a pre-run cost estimate (image count × quality × size, plus narration duration).
7. Confirm quota headroom.
8. Record the resolved configuration in the asset register.

## Appendix D — Migration calendar

Sourced from the provider's **deprecations page** — the only authoritative status source (the model catalog conflates families with snapshots). Re-check before every billed run; this is a snapshot, not a subscription.

**Already gone**

| Date | Retired | Replacement |
|---|---|---|
| 2026-05-12 | `dall-e-2`, `dall-e-3` | `gpt-image-2` |
| 2026-05-12 | Realtime API Beta (`OpenAI-Beta: realtime=v1`) | Realtime API GA |
| 2026-07-23 | **`gpt-4o-mini-tts-2025-03-20`** | **`gpt-4o-mini-tts-2025-12-15`** |
| 2026-07-23 | `gpt-audio-mini-2025-10-06` | `gpt-audio-1.5` |
| 2026-07-23 | `gpt-realtime-mini-2025-10-06` | `gpt-realtime-mini` |
| 2026-07-23 | `computer-use-preview` (+ snapshot) | `gpt-5.4-mini` |
| 2026-07-23 | `gpt-4o-search-preview`, `gpt-4o-mini-search-preview` snapshots | `gpt-5.4-mini` |
| 2026-07-23 | `gpt-5-chat-latest`, `gpt-5-codex`, `gpt-5.1-chat-latest`, `gpt-5.1-codex`, `gpt-5.1-codex-max`, `gpt-5.2-codex` | `gpt-5.5` |
| 2026-07-23 | `gpt-5.1-codex-mini` | `gpt-5.4-mini` |
| 2026-07-23 | `o3-deep-research`, `o4-mini-deep-research` | `gpt-5.5-pro` |

**Coming**

| Date | Retiring | Replacement | Relevance here |
|---|---|---|---|
| 2026-08-10 | `gpt-5.2-chat-latest`, `gpt-5.3-chat-latest` | `gpt-5.5` | Script/QA models |
| 2026-08-26 | Assistants API | Responses + Conversations API | Any legacy agent scaffolding |
| **2026-09-24** | **Videos API, `sora-2`, `sora-2-pro` + all snapshots** | **none** | **No generative-video path. Capture pipeline only.** |
| 2026-09-28 | `gpt-3.5-turbo-instruct`, `babbage-002`, `davinci-002`, `gpt-3.5-turbo-1106` | `gpt-5.4-mini` / `gpt-5-mini` | Legacy scripting |
| 2026-10-23 | **`gpt-image-1`** | `gpt-image-2` | Image production |
| 2026-10-23 | `gpt-3.5-turbo`, `gpt-4`, `gpt-4-turbo`, `gpt-4.1-nano`, `gpt-4o-2024-05-13`, `o1`, `o1-pro`, `o3-mini`, `o4-mini` (+ fine-tunes) | `gpt-5.x` line | Script/QA models |
| 2026-10-31 | Existing evals become read-only | — | QA tooling |
| **2026-11-30** | **`v1/prompts` + reusable prompt objects** | **Move prompt content into application code** | **Prompt library — file-based storage is the destination** |
| 2026-11-30 | Evals dashboard and API | — | QA tooling |
| 2026-11-30 | Agent Builder (ChatKit stays) | Agents SDK / Workspace Agents | Agent scaffolding |
| **2026-12-01** | **`gpt-image-1.5`, `gpt-image-1-mini`, `chatgpt-image-latest`** | `gpt-image-2` | Image production |
| 2026-12-11 | `gpt-5-2025-08-07`, `-mini`, `-nano`, `gpt-5-pro-2025-10-06`, `o3`, `o3-pro` snapshots | `gpt-5.5` / `gpt-5.4-mini` / `gpt-5.4-nano` / `gpt-5.5-pro` | Script/QA models |
| 2027-01-06 | New fine-tuning job creation (active customers) | — | Only if fine-tuning |

**Reading it:** by December 2026 every image model except `gpt-image-2` is gone, generative video is gone with no successor, and prompt objects are gone. The configuration this guide specifies — `gpt-image-2`, `gpt-4o-mini-tts-2025-12-15`, file-based prompts, capture-based video — is the one that survives all of it.

## Appendix E — The three guides together

| Stage | Guide | Question | Gate |
|---|---|---|---|
| 1 | Product Experience Audit & Remediation | Is the product good? | Demo-readiness verdict |
| 2 | Killer Demo Production | Is the demo compelling and true? | Craft & persuasion gate |
| 3 | **Visual Communication & Asset Generation** | **Does the surface communicate — and are the assets real?** | **Four-jobs test + integrity rules** |

Shared spine across all three: **a seeded, resettable environment producing real captures**; **a claim/asset ledger** proving everything shown is true; and **a fail-closed gate** that prefers shipping nothing to shipping something hollow.

---

## The one line

A text-heavy surface isn't ugly — it's **unproven**. Fix it by showing the thing, the structure, the proof, and the people, using real captures wherever the subject is real and generated imagery only where it honestly belongs. Everything else is decoration, and decoration is what made the page feel generic in the first place.
