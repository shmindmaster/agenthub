---
name: product-demo-studio
description: >
  Route autonomous, truthful product-video production and demo-readiness assessment in any
  repository: demo, training, trust, homepage-loop, sales, or marketing videos. Use when asked to
  make, generate, plan, capture, narrate, render, critique, or inventory product videos, or to
  decide whether a workflow is demo-worthy. Enforce two valid outcomes per episode: a persuasive,
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
to a final render.

0. **Configure the run** — resolve `<OUTPUT_ROOT>`, an in-repo `<WORK_DIR>`, the seed/reset path,
   brand tokens, approved voice profile, and optional issue tracker before production. Keep final
   masters flat under `<OUTPUT_ROOT>/<PRODUCT>/`, cuts under `cuts/`, and all working/evidence files
   inside `<WORK_DIR>`.
1. **Reconcile and propose candidates** — inspect the repo's instructions, README, routes, package manifests,
   git status, existing media/video work, tests, and seed/reset fixtures before changing anything.
   Pick `sizzle-hook`, `guided-discovery-support`, `onboarding-enablement`, or `internal-handoff`,
   and record whether audience framing is compliance-heavy or operational. Propose short candidates
   with one persona, problem, viewer-unit outcome, guardrail, emotional target, and protected hero
   moment. **Produce a
   WIP ledger** recording what in-progress work was completed, preserved, or removed and why:
   complete or merge work only when the request and repository policy authorize it; preserve
   active/blocked/unexplained work, and remove obsolete/duplicated work only after proving nothing
   unique is lost.
2. **Consume the Product Experience handoff, then independently assess demo-worthiness** — before
   capture, require `_product-experience/07-demo-readiness-handoff.md` and
   `_product-experience/demo-readiness.json` from the canonical `prepare-product-for-demo` skill.
   Product Experience Engineering owns product assessment and remediation; this plugin consumes
   that evidence and owns media production. Validate the handoff against the target repository's
   current revision and expected handoff path. Missing, stale, revision-mismatched, `REMEDIABLE`,
   `DEFERRED`, or product-fix-required evidence stops capture and routes back to
   `prepare-product-for-demo`. Never recreate or weaken that upstream assessment inside the video
   plugin. Once the handoff clears, walk each candidate's real workflow again and score all eleven
   rubric criteria, including whether a real in-product hero moment exists. This second gate catches
   capture-specific defects; it does not blindly trust upstream. Write a normalized readiness sheet
   and feedback under `<WORK_DIR>/feedback/` and run `validate-demo-readiness.mjs` with the current
   revision. `PASS` and capture-only `CONDITIONAL` proceed; `FAIL` stops master production and
   becomes fix-oriented product-readiness feedback. A short diagnostic capture is allowed when
   evidence is needed to distinguish capture-fixable from product-fix-required.
3. **Storyboard and narrate** — make one structured timed script the source of truth for capture,
   narration, annotations, captions, and render timing. For every proceeding episode, define one cold open,
   a shown three-to-five-second before state, exactly one hero moment, segment-level WIIFM, the
   primary three-rung ladder (`feature` → `outcome` → `identity`) with a payoff at `outcome` or
   `identity`, attention resets, no more than two simultaneous annotations, emotional target,
   and designed end card.
   Validate the normalized storyboard with `validate-storyboard.mjs`. Approve narration before
   final capture; measured audio durations drive the recording plan. Use
   `product-demo-studio-render` and `product-demo-studio-narration`.
4. **Capture** — record real product states (screenshots and/or short recordings) through
   deterministic browser automation, synthetic data only. Record selectors, bounding boxes,
   protected regions, cursor paths, console/failed-request evidence, and reset results. See
   `product-demo-studio-capture`. Use the Browser Quality Toolkit for live Chrome diagnostics and
   repository-owned deterministic automation for master capture; those are complementary layers,
   not competing capture systems.
5. **Compose** — build a reusable Remotion composition: scenes, camera/zoom, cursor motion, focus
   masks, callouts, captions, narration, and aspect-ratio-specific reframing. See
   `product-demo-studio-remotion` for authoring knowledge and its `overlay-placement` rule for
   text-vs-product occlusion.
6. **Render and QA** — render proxies first, run correctness, technical, accessibility, craft, and
   persuasion review, then revise. If editing cannot clear the craft gate because of product UX,
   pull the episode and route it to feedback. Render finals only after acceptance, with captions,
   transcripts, posters, checksums, and reproduction commands. See `product-demo-studio-render`
   and `product-demo-studio-qa`.
7. **Ship, report, measure, and editorial finish** — deliver only approved masters and explicitly requested
   derivative cuts. Always deliver the Product-Readiness Feedback Report for failed candidates; if all fail, deliver zero
   videos. The pipeline produces a complete, captioned, narrated MP4
   with no mandatory external editor. When a user requests transcription cleanup, speaker
   isolation, filler-word removal, editorial trim cuts, or alternate social clips, hand off to
   `product-demo-studio-descript` for final-stage finishing. Captions that are already grounded in
   known narration text should remain source-of-truth captions unless a user explicitly asks for
   Descript-managed captions. Record completion/watch percentage, drop-off, CTA/reply, and the
   demo-type-specific downstream outcome when distribution is in scope; use it to revise the timed
   script. If Descript is used, it is always the *last* stage, never the first
   — never import raw, unredacted, or unapproved footage into it.

## The evidence-redaction rule (gates external reuse, not internal iteration)

Iterate freely inside the pipeline — captures, proxy renders, revisions, and QA loops all run
without waiting for human sign-off. The gate applies only at the boundary, before an asset is:

- copied into a repo's final video/marketing folders,
- imported into Descript,
- uploaded anywhere externally reachable, or
- referenced in docs, sales material, training content, or a live site.

Every such asset needs a release-evidence manifest — `classification` of
`approved | needs-redaction | rejected` plus a named human reviewer — before it crosses that
boundary. Use `scripts/check-evidence-gate.mjs` to enforce it. **Never mark something `approved`
yourself** — that field is a human attestation, not something to fill in on the user's behalf.

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
(`render-proxy`, `qa`, `render-final`); run `video-cli.mjs` with no verb for the full list.

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

Treat the work as complete only when: valuable WIP is completed/merged when authorized or explicitly
preserved; every candidate has an evidence-backed `PASS`, `CONDITIONAL`, or `FAIL`; every proceeding
storyboard passes the hero-moment, before-state, WIIFM, emotional-target, and cadence contract; every
demo uses real production functionality on synthetic data; every visible value is verified against
the truth sheet; every workflow succeeds on the verified deployment; narration is natural,
segmented, correctly pronounced, and paced; audio/video/captions/actions are synchronized; craft,
screen, data, audio, sync, technical, evidence, and named-human gates pass; every failed episode has
buildable feedback and a shortest path to readiness; claims, provenance, manifests, and package
integrity are verified; final videos and sources are organized in the product folder; and temporary
artifacts are cleaned without losing active work. **Never claim completion without verified
evidence. Zero approved videos plus complete feedback is a valid completed outcome.**

When reporting back, lead with `videos delivered`, `feedback-only`, or `mixed`; cover WIP handled;
candidate episodes and verdicts; deciding defects; demo-data and accuracy verification; voice and
narration QA; craft/screen/audio/sync/technical results; final filenames and delivery-folder
integrity; feedback path, severity counts, and shortest path to readiness; package location;
merge/deployment/cleanup results; and remaining blockers, preserved work, or limitations.

## Safety boundaries

Operate in local, preview, staging, or explicitly authorized synthetic hosted environments only.
Never expose production data, secrets, personal data, live third-party portals, or trigger a real
external action. Stop and ask for explicit authority before: irreversible deletion, production
secret/database mutation, billed TTS, tracker ticket creation, paid external work, public
publishing, or any other consequential
real-world action. Everything else in the pipeline — capture, compose, narrate, proxy-render,
revise, QA — runs autonomously without waiting for a checkpoint.
