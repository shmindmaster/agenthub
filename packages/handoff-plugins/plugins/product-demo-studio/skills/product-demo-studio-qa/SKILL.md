---
name: product-demo-studio-qa
description: >
  Fail-closed QA for product-video captures and renders using deterministic technical checks and a
  five-reviewer critic loop. Use after proxy/final renders or to critique product truth, craft,
  persuasion, narration, framing, accessibility, occlusion, delivery formats, or reproducibility.
  Enforce one hero moment, shown before-state, segment WIIFM, emotional payoff, attention cadence,
  and the video-versus-UX-feedback boundary before final render or Descript handoff.
---

## Scope

Treat QA as a production stage, not a final glance. This skill covers technical validation,
frame-based visual inspection, a five-role critic loop, and reproducibility evidence. It does not
grant approval to publish or attest that footage contains no sensitive data — a named human
reviewer makes that call via `product-demo-studio-render`'s evidence gate.

Resolve `PRODUCT_DEMO_STUDIO_ROOT` through the router skill before invoking bundled scripts.

## Step 1 — deterministic technical checks

Run before any subjective review; a technically broken proxy isn't worth a human's or a critic
agent's time.

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/technical-checks.mjs" --video <path-to-proxy.mp4> --out <qa-output-dir>
```

Requires `ffmpeg`/`ffprobe` on PATH; the script fails with an explicit install instruction rather
than silently skipping checks if they're missing. It reports codec, resolution, frame rate,
duration, audio stream presence, black-frame and freeze-frame ranges, and loudness/silence, and
extracts frames at the opening, every scene transition, every focus/zoom moment, and the final hold
into `<qa-output-dir>/frames/` plus a contact sheet — the inputs the visual and technical reviewer
agents inspect in step 2.

## Step 2 — the five-role critic loop

Run these read-only reviewer prompts independently (they don't depend on each other), one per
finding category:

| Agent | Portable prompt | Validates |
|---|---|---|
| Product-truth reviewer | `agents/product-truth-reviewer.md` | Every claim against the product-claim ledger, readiness state, visible evidence, environment accuracy, synthetic-data safety. |
| Story reviewer | `agents/story-reviewer.md` | Audience fit, cold open, shown before-state, one hero moment, per-segment WIIFM, payoff ladder rung, emotional target, pacing/cadence, CTA, duration. |
| Visual reviewer | `agents/visual-reviewer.md` | Product readability, hero staging, progressive screens, zoom accuracy, cursor acting, attention resets, text/caption occlusion, aspect-ratio framing. |
| Audio reviewer | `agents/audio-reviewer.md` | Viewer-centered narration, naturalness, vocal dynamics, pronunciation, hero silence, emotional delivery, music balance, loudness/clipping, visual alignment. |
| Technical reviewer | `agents/technical-reviewer.md` | Resolution/frame-rate/codec correctness, missing/black/frozen frames, caption overflow, file integrity, checksums, reproduction commands. |

Resolve each file from `${PRODUCT_DEMO_STUDIO_ROOT}`. If the host exposes packaged
`product-demo-studio:<reviewer>` agents, invoke them. Otherwise create five independent read-only
reviewer/subagent passes from these Markdown prompts. On a host without subagents, run five
separate isolated review passes and record that limitation in the QA report. Missing named plugin
agents never permits skipping or collapsing the five reviews into one opinion.

Give each agent the same context bundle: the proxy video path, `<qa-output-dir>/frames/` +
contact sheet, the technical-checks.mjs report, the render manifest, the capture manifest(s), the
product-claim ledger, and the narration script/transcript. Each returns a verdict in this shape:

```json
{
  "accepted": false,
  "revisions": [
    {
      "scene": "workflow-result",
      "category": "visual",
      "issue": "The headline overlaps the result status.",
      "action": "Move the headline to the upper-left safe region and reduce it to one line."
    }
  ]
}
```

## Step 3 — apply, rerender, repeat

1. Review every reported revision; discard ones that are wrong or out of scope, but don't discard a
   revision just because it's inconvenient.
2. Apply justified revisions to the *source* composition, capture manifest, or claim ledger — never
   patch only the exported binary while the source stays wrong.
3. Re-render the proxy (`video-cli.mjs render-proxy`) and repeat from Step 1.
4. Use up to **three** normal iterations. Continue beyond three only if a serious product-truth,
   privacy, technical, or accessibility issue remains — note why in the QA report when you do.

For a full parallel run in one shot instead of driving five separate Agent calls by hand, use the
`video:qa` verb:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/video-cli.mjs" qa --repo <path-to-repo> --video <path-to-proxy.mp4>
```

This runs `technical-checks.mjs`, prints the exact five Agent-tool dispatch prompts pre-filled with
the context bundle above, and validates the resulting revision JSON — it does not spawn the agents
itself (only the calling Claude session can do that), it prepares everything needed to spawn them
in one pass.

## Craft and engagement gate

Review full playback plus representative frames. Fail unless all are true:

- the first frame carries pain, tension, or a result glimpse, and the problem/desired outcome lands
  within five to eight seconds without login, tour, logo, or "in this video" preamble;
- a three-to-five-second before-state makes the old-way cost felt;
- exactly one hero moment is named, staged with pre-silence/push-in/cue/hold, and uncontested;
- every segment has one WIIFM and one idea, and the payoff reaches the primary `outcome` or
  `identity` rung (the validator also accepts refined outcome/identity aliases);
- no uncut dead time remains and pace, visual, sound, zoom, text, or framing changes at least about
  every 10–15 seconds;
- results stay visible in deliberate near-silence long enough to register;
- the declared emotional target is supported by voice, motion, music, silence, and wording;
- voice is conversational, varied, correctly pronounced, and not wall-to-wall;
- final frames are stable, legible at delivery size, spatially coherent, and free of occlusion;
- the video ends quickly after payoff with exactly one takeaway/next step and a designed end frame.

If a proxy still fails after justified re-editing, classify the cause. Re-edit a capture-fixable
cause. Pull the episode and write demo-readiness feedback for a product-fix-required cause. Never
lower the bar or accept a mediocre master to meet an episode quota.

## Required checks (what "accepted" should mean across all five roles)

- The product state shown is real for the declared environment and uses synthetic or authorized
  demo data.
- Every claim has a source and readiness state; unverified or roadmap claims are excluded or
  disclosed.
- The intended outcome is legible at each target viewport. Vertical and square cuts are recomposed,
  not mechanically cropped from the wide master.
- Text stays within safe areas, has sufficient contrast, and never overlaps the focus region, an
  active control, a cursor destination, or a status/evidence region — cross-check against
  `compute-overlay-placement.mjs`'s output for that scene (see `product-demo-studio-remotion`).
- Cursor motion, zooms, transitions, and holds clarify the workflow rather than merely decorate it.
- The hard case and its complexity are legible without making the flow look chaotic; AI episodes
  show enough reasoning and adjacent human control to earn trust.
- Console errors, failed requests, and reset results from the capture manifest are clean or
  explained.
- Reduced-motion and poster/fallback assets exist for autoplaying homepage media.
- Output hashes, source commit, package command, manifests, and generated captions/transcripts are
  stored with the deliverable so the render is reproducible.

## Transcript check — the narration matches the approved script

Audio QA isn't only "does it sound good." Transcribe the *final rendered* audio and compare it to the
approved narration script with word-level timestamps. Flag: missing or added words, a wrong name or
number, a mispronunciation, an unexpected sound, and timing drift between a segment's spoken end and
where the next beat starts. Because captions are generated from the ground-truth narration text (see
`product-demo-studio-render`), this check also protects against a caption that has silently drifted
from the audio. Every visible on-screen value (name, date/timezone, number, calculation, status,
chart, table, notification, permission, AI result, workflow outcome) is checked against the episode's
demo **truth sheet** (see `product-demo-studio-render`), not just eyeballed.

## Human watch-through approval — the final gate

Technical + critic passes never substitute for a person watching the master. Before delivery, a named
human watches every final master **start to finish at normal speed**: once **with captions on**, once
**with captions off**, on the **intended delivery display size**. No video is delivered without a
recorded watch-and-listen approval. This is recorded in the evidence manifest's `watchThroughStatus`
and `reviewedBy` (see `product-demo-studio-render`) — you prepare everything for it, but you never
attest it on the reviewer's behalf.

## Report

Write a concise QA report beside the render manifest: files reviewed, source commit, target
formats, pass/fail per role, issues with timestamp/frame references, corrective action taken,
remaining limitations, and the human evidence-review status. A technically and critically passing
render remains `needs-human-review` until a real reviewer completes the release-evidence manifest
in `product-demo-studio-render`.
