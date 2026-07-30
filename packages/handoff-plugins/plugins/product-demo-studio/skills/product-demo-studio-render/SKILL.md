---
name: product-demo-studio-render
description: >
  Plan and render reproducible, persuasive product-video deliverables; validate normalized
  readiness/storyboards; maintain truth sheets and product-claim ledgers; package evidence; and
  enforce human release review. Use for candidate episode plans, demo-worthiness verdicts,
  storyboards, formats, catalogs, proxy/final renders, derivative cuts, manifests, checksums, or UX
  feedback routing. Render only PASS/CONDITIONAL episodes and never ship a craft-gate failure.
---

## Adapt to the existing renderer

Before adding a package, inspect the target repo's media source and package scripts. Reuse its
composition catalog and render command when one exists. If there is no code-driven renderer,
propose the smallest development-only setup that fits its package manager and source layout — do
not add a rendering runtime to the production application bundle without a clear reason.

## Episode shape: short, single-purpose, five beats

Prefer several focused episodes over one long tour. Target **45–120 seconds; three minutes is the
hard maximum** unless a workflow genuinely can't be divided without losing meaning. Each episode
targets **one persona, one problem, one clear outcome, and one trust/safety/human-control
guardrail**, and stands alone as independently shareable. Reach the product value fast — minimal
intro/setup. Structure every episode as five beats: **Hook** (problem or desired outcome) →
**Action** (the essential workflow only) → **Payoff** (visible result + customer value) →
**Guardrail** (a control, verification, or human decision) → **Close** (concise takeaway/next
step). Avoid long tours, exhaustive feature lists, repeated navigation, and unnecessary setup.

Before writing a catalog entry, declare: a humanized persona; the shown three-to-five-second
before-state; one emotional target; exactly one hero moment; one-line WIIFM per segment; the
three-rung `feature` → `outcome` → `identity` ladder with the payoff at `outcome` or `identity`;
a cold open; attention
resets; and a designed end card. For
problem-solving or AI, include one brief taste of the hard case before the reveal. Validate a
normalized JSON export even when the repo keeps its native storyboard in TypeScript or another
shape:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-storyboard.mjs" <path-to-storyboard.json>
```

## Decide video versus feedback before production

Walk each candidate's real workflow and record every criterion from the router's demo-worthiness
rubric. Normalize the assessment to JSON and run:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-demo-readiness.mjs" <path-to-readiness.json>
```

The readiness sheet must carry the validated Product Experience handoff identity, assessed
revision, persona/permissions, deterministic seed/reset profile, hero moment, and `DEMO-READY`
upstream verdict. Validate it against the current revision before rendering.

- `PASS`: no failed criterion; proceed.
- `CONDITIONAL`: capture-fixable failures only, with exact treatments; proceed and verify them in QA.
- `FAIL`: one or more product-fix-required failures; do not create a master. Write one buildable
  Product-Readiness Feedback entry per defect under `<WORK_DIR>/feedback/`, including evidence, viewer impact, severity,
  suggested fix, and the shortest path to readiness.

Create external tracker tickets only when the current request authorizes tracker writes. A run in
which all candidates fail is complete when the feedback package is clear and reproducible.

## Catalog schema (recommended shape for a repo with no existing catalog)

Model a new catalog on a typed module, not a hand-maintained JSON or markdown file, so mistakes
(wrong duration math, invalid audience) are caught by the type checker and tests:

```ts
export const FPS = 30;

export const VIDEO_FORMATS = [
  { id: "wide", width: 1920, height: 1080, label: "16:9" },
  { id: "vertical", width: 1080, height: 1920, label: "9:16" },
  { id: "square", width: 1080, height: 1080, label: "1:1" },
] as const;

export type Audience =
  | "Hero" | "Pillar" | "Persona" | "Training" | "Trust" | "Marketing" | "Sales";

export type VideoScene = {
  durationSeconds: number;
  eyebrow: string;
  title: string;
  caption: string;
  motif: string;      // per-product enum, e.g. "capture" | "document-data" | "cta"
  asset?: string;      // path relative to public/, from an approved capture
  metric?: { label: string; value: string; detail: string };
  chart?: { label: string; value: number; margin?: string }[];
};

export type ProductVideo = {
  id: string;
  audience: Audience;
  title: string;
  subtitle: string;
  durationSeconds: number;
  durationInFrames: number;   // always durationSeconds * FPS -- never hand-compute
  cta: string;
  scenes: VideoScene[];
};
```

Use `scripts/new-video-catalog-entry.mjs` to append entries rather than hand-editing — it validates
the audience enum and computes `durationInFrames` for you, and it only ever writes to a catalog it
has confirmed matches this exact shape.

**A repo with a different existing format — do not force a migration.** Real, independently
observed shapes include: a JSON catalog plus a separate program/composition file; a markdown table
catalog; a richer, runtime-validated catalog where capture entries carry route/persona/expected-
access fields, scenes carry a `kind`/`tone` instead of a free-string `motif`, and every video has an
`externalAssets` AI-generation-request block; and repos with no central catalog file at all, where
scene data lives directly in a component driven by a small render-group script. Treat any of these
as a valid, working implementation — read its own README and types and extend it in its own idiom.
`scripts/new-video-catalog-entry.mjs` and `scripts/repo-registry.mjs` detect which shape a repo
actually has (by reading the real file, never by assuming from folder structure) and refuse with
specifics rather than guessing when it doesn't match the reference shape above.

## Silent hero micro-clips (a recurring, worth-reusing pattern)

Homepage-loop deliverables are usually short, silent, above-the-fold clips distinct from longer
product-tour/training videos — e.g. a 45s hero clip plus several 9:16 short social clips, or a set
of 8-12s silent hero clips (one per key workflow) that a homepage showcase can switch between.

- 8-12 seconds, silent (no voiceover track), one action and one outcome per clip.
- Real product states/captures, synthetic data only (see `product-demo-studio-capture`).
- Restrained cursor choreography — no meaningless movement.
- Ends on a clean hold frame so it can loop or crossfade without a jump cut.
- Ship a poster frame (for `prefers-reduced-motion` and pre-load), plus WebM and MP4.
- Record source commit, fixture/capture version, and a checksum in a sidecar next to the render so
  it is reproducible and auditable.
- This is a different deliverable from the longer overview/tour/training videos in the same
  catalog — a catalog can and should have both.

## Demo truth sheet — verify before you record

For every episode, write a truth sheet: the persona and permissions; the seeded entities and their
identifiers; the expected counts, statuses, dates, values, and calculated results; the expected
workflow outcome; and the claims demonstrated. **Verify the truth sheet against the database, APIs,
and the deployed app before recording** — not after. During QA (`product-demo-studio-qa`) every
visible value (name, date/timezone, number, calculation, status, chart, table, notification,
permission, AI result, workflow outcome) is checked against this sheet. Reject any take with stale
state, incorrect values, impossible domain states, placeholders, unexplained errors, or misleading
data.

## The product-claim ledger

Every spoken or visible claim in a video needs a source and a readiness state — this is what keeps
narration honest and keeps `product-demo-studio-qa`'s Screen, Accuracy, and Compliance reviewer from having to
reverse-engineer what was meant. Maintain it as a structured file (wherever the repo's own media
manifests live, e.g. `apps/videos/manifests/product-claims.yaml`; propose that path if none exists
yet) with one entry per claim:

```yaml
claims:
  - id: claim-approval-speed
    text: "Approve a batch in under two minutes."
    audience: Hero
    episode: hero-overview       # which video
    scene: workflow-result       # scene/segment the claim appears in
    workflow: batch-approval
    route: /approvals/batch
    source: apps/web/src/routes/approvals/batch.tsx#L40-L88   # evidence location
    visibleOnScreen: true        # is the claim actually shown on screen?
    environment: local
    readiness: live              # the six standard classes -- see below
    disclaimer: null
    verified: true               # false blocks release unless a verdict + correctionNotes is recorded
    verdict: null                # correction notes when a claim was checked and adjusted
```

**Readiness classes** (§12 of the Universal Demo Production Standard — `validate-claims.mjs` enforces
exactly these; the older longer enum is still accepted with a deprecation warning and auto-mapped):

| Class | Use for |
|---|---|
| `live` | Backed by the real, running product/API in the shown environment. |
| `synthetic` | True of the product, demonstrated on synthetic/authorized demo data. |
| `reference-recorded` | A pre-recorded reference of a real capability, not re-run live in this take. |
| `background` | Real behavior that isn't visible on screen; describe it as background, don't narrate it as seen. |
| `human-gated` | Real but gated behind a human approval/release step before it takes effect. |
| `not-published` | Documented but must NOT appear in a released video (blocks release if shown on screen). |

Validate it with:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-claims.mjs" <path-to-product-claims.yaml>
```

Do not let generated captions, voiceover scripts, or on-screen copy assert:

- guaranteed accuracy or completed compliance/audit status (SOC 2, HIPAA, etc.) unless a cited,
  reviewed source substantiates it,
- specific customer counts, revenue, savings, or recovery figures unless explicitly synthetic and
  labeled as such,
- external competitor/vendor scoring, rankings, or comparisons.

If a capability isn't visible in the product, either adjust the claim, improve the UI where that's
in scope, describe it accurately as background behavior, or exclude it — never narrate a capability
into existence because backend code appears to support it.

## Rendering

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/render-videos.mjs" --repo <path-to-repo> [--id <video-id>] [--format wide|vertical|square]
```

or via the unified dispatcher:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/video-cli.mjs" render-proxy --repo <path-to-repo> [--id <video-id>]
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/video-cli.mjs" render-candidate --repo <path-to-repo> [--id <video-id>] [--format wide|vertical|square]
```

Both inspect the target repo's actual `package.json` scripts rather than assuming fixed names —
some repos have `render:all`/`render:priority`/`render:still`, others have bespoke per-video
scripts. The wrapper finds and runs the closest match; it never invents a new script name in
someone else's `package.json`.

**Always render a proxy before an immutable candidate.** Inspect the proxy before investing in
high-resolution or multi-format renders. Then render the candidate exactly once, generate its
evidence package, and run preflight, independent review, arbitration, and final verification.
Never render or edit after evidence generation or approval; remediation starts a new candidate.

## Deliverables

Treat output as a versioned package, not a single MP4. Produce only the variants the story needs,
but typically: a master MP4, a web-optimized fallback where required, poster, thumbnail, the
caption/transcript set (see the explicit list under **Delivery package and manifest** below),
narration script, checksums, a render manifest, and a reproduction command. Recompose vertical and
square cuts — reframe scenes, focus, and text for each aspect ratio; don't mechanically crop a wide
master.

When requested, derive a focused family from the approved hero capture: roughly 90-second sales
master, 30-second social cut, 10–15-second teaser, silent GIF/loop, and 9:16 vertical cut with
captions. Do not create every variant by default, and do not let a derivative bypass the same truth,
craft, evidence, and human-review gates as its master.

The render manifest links output files to source commit, capture/fixture versions, the story and
claim manifests, render command, composition parameters, aspect ratio, duration, and the
`product-demo-studio-qa` four-domain review reports and Release Arbiter decision.

## Delivery package and manifest

Ship a portable package, not a lone MP4. Include: final masters; a **burned-caption master**;
**SRT, VTT, transcript TXT, and caption JSON**; poster/thumbnail and artwork; narration clips **and
their source script**; storyboards and timing maps; the demo truth sheets; the claim ledger;
capture and render manifests; QA reports and extracted frames; and checksums.

The **package manifest** records: a synthetic-data disclosure; the voice + model profile used; the
source and deployment commits; the QA status; and the human-approval status. Publish masters and
the full package to the repo's (or portfolio's) designated video folder for the product. **Remove a
stale, superseded master only after the new release package is confirmed complete and valid** —
never delete the old one first.

## The evidence gate — required before external use, not before internal iteration

A render is not "approved" just because it renders without error and passes technical QA. Before
it may be copied into a final video/marketing folder, handed to `product-demo-studio-descript`, or
uploaded anywhere external, run:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/check-evidence-gate.mjs" --manifest <path-to-manifest.json>
```

The manifest (schema and example shipped alongside the script) requires:

| Field | Required | Notes |
|---|---|---|
| `assetPath` | yes | path to the rendered file or capture being attested |
| `classification` | yes | `approved \| needs-redaction \| rejected` — **a human judgment call, never auto-filled** |
| `reviewedBy` | yes | a real person's name/handle — the script refuses a manifest without one |
| `reviewedAt` | yes | ISO date |
| `syntheticDataConfirmed` | yes | boolean — reviewer confirms no real customer/patient/financial data appears |
| `watchThroughStatus` | for `approved` | `completed` only after a named human watched the master start-to-finish (captions on, then off, at delivery size). Never auto-filled. |
| `redactionNotes` | no | what was redacted or why it's clean |

The script also runs a **best-effort, warning-only** regex scan for emails, phone/SSN-like
patterns, `$`-figures, and common secret/token shapes in the asset's accompanying text — a
first-pass assist, not a substitute for the human review fields, and it cannot itself set
`classification: approved`.

Never write `classification: approved` on the user's behalf. If asked to "approve" a render, either
ask the actual reviewer to attest it, or explicitly flag that you are not the appropriate reviewer
for this gate.

## Optional: publishing an approved master externally

Once a render is `approved`, publishing it (e.g. to the repo's own object storage bucket, so the
live app or marketing site can reference it) is guidance-only — no script in this plugin performs
an upload automatically, and it is never a required step before a render counts as approved. Follow
the target repo's own storage/publishing convention for this step.

## Next: QA, then Descript (optional)

Send every proxy through `product-demo-studio-qa` before a final render. Captions belong in the
render itself — generate them from the ground-truth narration text (perfect sync, no ASR error)
and burn them in, rather than outsourcing. Reach for `product-demo-studio-descript` only when you
specifically need a hosted shareable link/player or interactive human hand-tweaking — it is
optional and off the critical path, not a required finishing step. If the render is already final,
stop here.
