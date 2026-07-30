---
name: product-demo-studio
description: >
  Route autonomous, truthful product-video production and demo-readiness assessment in any
  repository: demo, training, trust, homepage-loop, sales, or marketing videos. Use when asked to
  make, generate, plan, capture, narrate, render, critique, or inventory product videos or a
  role-routed interactive product deep-dive, or to decide whether a workflow is demo-worthy.
  Enforce two valid outcomes per episode: a persuasive,
  fully gated video, or fix-oriented Product-Readiness Feedback with no mediocre video. Reuse existing video
  infrastructure and route Remotion, capture, narration, render, QA, and Descript work to the
  corresponding product-demo-studio subskills.
---

## This plugin is self-contained — it does not install anything into a repo on its own

This plugin lives entirely under its own plugin root. It is invoked *against* a target repository
path (`--repo <path>`); it never scaffolds its own config, skills, or dependencies into that repo.
The only things that land in a target repo are the video-production deliverables themselves
(a Remotion workspace, captures, manifests, rendered media) — exactly the kind of first-party
asset that repo would own anyway, in its own idiom. Never add plugin/skill/MCP machinery to a
target repo, and never assume or require a specific multi-repo workspace layout — every stage
below works against one repo in isolation.

## Resolve the shared plugin root on every coding-agent host

Before invoking a bundled script, resolve `PRODUCT_DEMO_STUDIO_ROOT` to a directory containing
`scripts/video-cli.mjs`. Prefer the host-provided plugin root when available. On a skill-only host,
read `registry/capabilities.json` from the configured Agent Capabilities registry and use the
`canonicalSource` for `product-demo-studio`. Do not copy scripts into a target product repo or
assume the Claude-only `CLAUDE_PLUGIN_ROOT` variable exists.

All command examples below use `${PRODUCT_DEMO_STUDIO_ROOT}` as the resolved path.

## Read the demo bar before selecting episodes

Read the complete [Killer Demo Production Guide](references/killer-demo-production-guide.md), then
use [the normalized adapter](references/killer-demo-playbook.md) for validator field names. The
standard has two valid outcomes: ship a killer video that clears every gate, or ship precise
product-readiness feedback for an episode the product
cannot yet carry. A mediocre-but-accurate video is a defect, not a deliverable.

For marketing/journey visuals, generated imagery, voice/model selection, or narration-provider
configuration, route to `product-demo-studio-visual-assets` and read the complete
[Visual Communication & Asset Generation Guide](references/Visual-Asset-Guide.md). That guide is
authoritative over the older narration model table. Never use generated imagery to depict product
UI, product data, or a result the real product did not produce.

## The pipeline

Every video goes through the same stages, in order. Adapt each stage's *mechanics* to the target
repository's real conventions; do not skip a stage, invent a competing video app, or jump straight
to a final render. The portable generation prompts are under `agents/`; product repositories keep
their own product-specific pipeline and data boundaries.

0. **Configure and discover** — resolve `<OUTPUT_ROOT>`, an in-repo `<WORK_DIR>`, the seed/reset
   path, brand tokens, approved voice profile, authorized product context, and intended platform.
   Inspect instructions, current commit/build, WIP, existing video infrastructure, source media,
   scripts, CI, GitHub, and supplied Notion/Linear requirements. Reconcile documentation against
   current behavior; newer documents are not automatically correct. Preserve active WIP.
1. **Architect the episode** — use `agents/episode-architect.md`. Consume the current Product
   Experience handoff, independently reassess capture readiness, and write the audience, problem,
   outcome, emotional target, workflow, duration, platform, felt before-state, one protected hero
   moment, visible payoff, trust/control moment, next step, truth sheet, and claim ledger. A missing,
   stale, revision-mismatched, `REMEDIABLE`, `DEFERRED`, or product-fix-required handoff stops
   production and yields precise Product-Readiness Feedback. Validate the normalized readiness
   sheet with `validate-demo-readiness.mjs`.
2. **Script and storyboard** — use `agents/script-storyboard-generator.md`. The timed source of
   truth includes narration, actions, expected states/values, scene timing, pauses, holds,
   annotations, explicit cursor/click/typing/scroll choreography, screen-space/framing treatment,
   captions, sound, and validation assertions. Each meaningful product beat must read as a real
   guided screencast: the pointer leads the eye, the real action occurs, the state changes, and
   only then does narration name the result. Enforce a five-to-
   eight-second hook, no login/generic introduction, one idea per beat, no feature tour, one
   protected hero moment, purposeful pauses/result holds, mobile-readable framing, no long
   inactive interval, and evidence-linked claims. Validate with `validate-storyboard.mjs` and
   `validate-claims.mjs`.
3. **Prepare and capture product state** — use `agents/capture-product-state-generator.md` and
   `product-demo-studio-capture`. Verify synthetic seed data, roles, dates, and visible values;
   establish a deterministic browser environment; validate the workflow once in a native browser
   when needed; then encode repository-owned Playwright coverage. Record browser playback,
   console/network/assertion, reset, redaction, selector, geometry, screen-space utilization,
   pointer/action/narration synchronization, and capture evidence. Prefer page-only capture or
   native-browser fullscreen, remove extraneous browser/OS chrome, collapse irrelevant navigation
   through real product controls, and plan a crop/push-in/recomposition whenever the active region
   would occupy less than half of the delivered frame. Fail on a
   broken, unstable, manually dependent, fabricated, unauthorized, or truth-sheet-inconsistent
   workflow.
4. **Generate narration and audio** — use `agents/narration-audio-generator.md` and
   `product-demo-studio-narration`. Produce exact narration, pronunciation rules, word timestamps,
   captions, loudness-normalized audio, ducking, disclosures, provider/voice provenance, and
   checksums. Fail on wording, names, numbers, pronunciation, timing, clipping, artifacts, or
   caption differences.
5. **Compose and render** — use `agents/composition-render-generator.md`. Prefer the repository's
   reproducible native pipeline. For Remotion, load current Remotion guidance before changes, use
   frame-driven APIs and Remotion media components, keep inputs source-controlled, and validate
   the final render rather than only Studio preview. Own framing, zooms, annotations, cursor,
   captions, pacing, sound, platform variants, still-frame validation, and full provenance.
   Interactive workflow beats must remain continuous screencast motion, not a slideshow of
   disconnected screenshots or a decorative cursor moving over a state that never changed.
6. **Preflight and evidence** — create a new immutable candidate and complete evidence package,
   then use `agents/automated-preflight.md` and `scripts/preflight.mjs`. Deterministic failures
   return to the responsible generator. Independent review cannot start until preflight passes.
7. **Review and arbitrate** — use `product-demo-studio-qa` to run the four isolated read-only
   reviewers, validate the shared finding schema, and run a separate read-only Release Arbiter.
   Valid decisions are `PASS`, `REMEDIATE`, `PRODUCT_BLOCKED`, or `PIPELINE_BLOCKED`.
8. **Remediate and repeat** — validated, least-privilege assignments route findings by independent
   subsystem. Any relevant product/data/source/media/configuration/environment change requires a
   new candidate, regenerated evidence, fresh affected-domain reviews, mandatory technical/sync/
   accuracy/privacy/compliance reruns, and a new arbiter decision.
9. **Mandatory final independent review and verification, then deliver and measure** — after
   arbiter `PASS`, dispatch `agents/final-verifier.md` as the mandatory terminal independent
   reviewer and verifier in a fresh read-only context. It rechecks the final bytes, reports,
   checksums, provenance, playback, and delivery contents. No candidate may be packaged,
   released without its schema-valid `PASS`. A machine-verified candidate may enter the private
   review-delivery lane below; only human-approved masters and requested cuts may enter final or
   publication folders. Failed candidates always receive a
   readiness report; zero videos is valid. External reuse still requires the named-human evidence
   gate. Descript is optional third-party editorial finishing and must not duplicate an
   already-connected session-level connector. Every edit creates a new candidate and forces new
   evidence, reviews, arbiter/final verification, and human attestation; publishing requires
   explicit authorization.

## The private review-delivery lane

After arbiter `PASS` and the mandatory final-verifier `PASS`, create the user's immutable review
package with `video-cli.mjs package-review`. Resolve the target repository through the configured
AgentHub `registry/product-video-delivery.json`; do not hard-code portfolio paths into this
repo-agnostic plugin. The managed mappings place review candidates under the corresponding private
OneDrive product folder at `Review/<candidateId>`.

The package includes the exact candidate, decision, final verification, requested captions,
transcript, contact sheet, and other review artifacts plus `review-package.json`. It is always
`classification: review-only`, `humanReview.status: pending`, and
`publicationApproved: false`. Candidate directories are immutable and never overwritten:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/video-cli.mjs" package-review \
  --repo <path-to-repo> \
  --delivery-registry <AgentHub-root>/registry/product-video-delivery.json \
  --decision <release-decision.json> \
  --final-verification <final-verification.json> \
  --artifact <caption-or-review-artifact>
```

This lane exists so the named human can watch the final bytes. It does not authorize public use,
promotion into the product folder root, Descript import, or publication. Those actions still
require the separately signed human evidence gate.

## Interactive product deep-dive derivative

When the request is a role-routed interactive walkthrough rather than only a video, read
[interactive-product-deep-dives.md](references/interactive-product-deep-dives.md) and produce a
schema-valid `interactive-deep-dive.json`. Product Demo Studio owns its verified media, scene
contract, claims, and evidence. Route page/frontend implementation to Product Experience
Engineering or the target repository's native frontend owner. Do not create another standalone
deep-dive runtime.

## The evidence-redaction rule (gates publication reuse, not internal iteration or private review)

Iterate freely inside the pipeline — captures, proxy renders, revisions, and QA loops all run
without waiting for human sign-off. The gate applies only at the boundary, before an asset is:

- promoted from its immutable `Review/<candidateId>` package into a repo's final video/marketing
  folder,
- imported into Descript,
- uploaded anywhere externally reachable, or
- referenced in docs, sales material, training content, or a live site.

Every such asset needs the signed release-evidence graph and named-human watch-through attestation
before it crosses that boundary. Use `scripts/check-evidence-gate.mjs` to verify the immutable
receipt and detached Ed25519 signature. **Never author or sign an approval receipt yourself** —
that is a human/operator trust action, not something to fill in on the user's behalf.

## Check what already exists before doing anything

Before scaffolding or authoring anything new in the target repo, run:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/repo-registry.mjs" --repo <path-to-repo>
```

This is the default, always-available invocation — no workspace or portfolio concept required. It
reports whether the repo already has video infrastructure and the actual shape of what's there,
e.g. (concrete cases seen in the wild, not an exhaustive list — always read what the tool reports
for *your* target repo rather than assuming one of these):

- An **`apps/videos/` workspace package** — a proper package-manager workspace package. **This
  structural match alone does not mean the catalog schema is the same as another repo's.** One
  observed repo used `src/content.ts` exporting `videos: ProductVideo[]`; another used
  `src/catalog.ts` exporting a materially richer, independently-evolved schema with runtime
  validation, capture manifests tied to auth personas and expected outcomes, `chapters`, and an
  `externalAssets` AI-generation request pipeline; a third had **no central catalog file at all** —
  scene data lived inside a component, driven by a small render-group script. Read the workspace's
  own README first (it usually states its own source of truth explicitly).
- A **`<Product>_Video_Program/_production/remotion/` + JSON catalog** pattern — mature but
  isolated from `apps/`/`packages/`.
- A **top-level `_production/remotion/` + markdown catalog** pattern — a partial scaffold.

If the target repo already has one of these, **extend it in place** — do not introduce a fourth
convention or migrate a working repo to a different one without being asked. Only use
`scripts/scaffold-video-workspace.mjs` for a repo genuinely reporting no video infrastructure.
Use [product-pipeline-compatibility.md](references/product-pipeline-compatibility.md) to map
repository-native artifacts into the canonical evidence/review contracts without moving product
code or media into AgentHub.
`scripts/new-video-catalog-entry.mjs` only knows how to safely insert into the
`content.ts`/`videos`/`ProductVideo` reference shape — it deliberately refuses (with specifics)
rather than force-fitting a different repo's catalog, since guessing wrong there means silently
corrupting a working file. When it refuses, read the named catalog file and README yourself and
add the entry by hand in that repo's own idiom.

If you're deliberately operating across several sibling repos in one workspace, `--root
<workspace-root>` reports on all of them at once (optionally backed by a
`portfolio-wiki/registry/repositories.yaml`-style file if one exists) — but this is a convenience,
never a requirement.

## The `video:*` command surface

`scripts/video-cli.mjs` provides one consistent verb-based entry point for the whole pipeline,
always invoked from the plugin, never installed into the target repo:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/video-cli.mjs" <verb> --repo <path-to-repo> [options]
```

See `product-demo-studio-render` and `product-demo-studio-qa` for the verbs that matter most
(`render-proxy`, `render-candidate`, `qa`, `package`); run `video-cli.mjs` with no verb for the
full list. Candidate rendering precedes evidence generation; no render or edit is allowed after
review, arbitration, final verification, or approval.

## What this skill set does NOT cover

This plugin owns video/media production only: consume validated product handoff → plan → capture →
compose → narrate → render → QA → finish. Product Experience Engineering owns making the real
workflow useful, coherent, polished, and `DEMO-READY`; route missing or failed prerequisites to its
`prepare-product-for-demo` skill. A request that also asks for landing-page information architecture,
hero/component frontend engineering, product positioning and copy strategy, analytics event
implementation, live-app accessibility or performance engineering outside the video pipeline
itself, or the repo's own branch/PR workflow is asking for several other specialties at once.
Handle the video/media portion with these skills; for the rest, use the repo's own frontend,
accessibility, and design skills (or a human product/design lead). If a single large request
bundles both, say so explicitly and scope the video/media slice out rather than attempting the
whole thing under this plugin's authority.

## Audience taxonomy

Use this enum consistently in any catalog this plugin creates or extends:

| Audience | Use for |
|---|---|
| `Hero` | The single flagship overview video for the product. |
| `Pillar` | A deeper video on one major workflow/feature. |
| `Persona` | A video aimed at one specific user role (owner, admin, reviewer, etc.). |
| `Training` | Onboarding / how-to-use-the-product walkthroughs. |
| `Trust` | Security, compliance, access-control, data-handling videos. |
| `Marketing` | Short social cuts derived from Hero/Pillar masters. |
| `Sales` | Design-partner or investor-facing pitch cuts. |

## Completion criteria and final response

Treat the work as complete only when valuable WIP is preserved or handled under repository policy;
every episode has an evidence-backed readiness result; generation and preflight use current source,
build, product behavior, truth, claims, and synthetic data; the four independent schema-valid
reviews finish; the Release Arbiter returns `PASS`; no blocker/critical finding remains; Story and
Experience is at least 85; Audio/Captions/Synchronization is at least 95; accuracy, claims, privacy,
compliance, browser playback, technical integrity, checksums, and provenance pass completely; the
render is reproducible; delivery contains only approved outputs; and the mandatory terminal
independent reviewer/verifier confirms the same immutable candidate. An external-release claim
additionally requires the
named-human evidence/watch-through attestation. **Never claim completion without verified evidence.
Zero approved videos plus complete feedback is a valid completed outcome.**

When reporting back, lead with `videos delivered`, `feedback-only`, or `mixed`; cover cleanup and
migration, canonical locations, retained/merged/replaced/deleted items, supported integrations and
parity, drift enforcement, candidate and arbiter decision, reviewer scores, defects remediated,
validation commands/results, final video/evidence paths, commit/build/config/render provenance,
authorized Linear changes, remaining limitations, and the exact reason for any blocked result.

## Safety boundaries

Operate in local, preview, staging, or explicitly authorized synthetic hosted environments only.
Never expose production data, secrets, personal data, live third-party portals, or trigger a real
external action. Stop and ask for explicit authority before: irreversible deletion, production
secret/database mutation, billed TTS, tracker ticket creation, paid external work, public
publishing, or any other consequential
real-world action. Everything else in the pipeline — capture, compose, narrate, proxy-render,
revise, QA — runs autonomously without waiting for a checkpoint.
