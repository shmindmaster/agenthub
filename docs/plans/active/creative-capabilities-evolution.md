# Plan: Creative / learning capabilities evolution

## Purpose / outcome

Extend AgentHub (without redesign) with portable creative and learning
capabilities, after fixing distribution defects. Architecture stays:
canonical packages under `packages/`, host exposure in the registry, runtime
artifacts outside the repo, Local-AI outside AgentHub.

## Verified state at start

- AgentHub already has packages, host projections, content hashes, drift
  detection, capability routing, and third-party Superpowers tracking.
- `packages/browser-toolkit` launches `@playwright/mcp@0.0.79` but
  `use-playwright-mcp` still documents Chrome DevTools MCP tool names.
- `packages/startup-series` exists (workflow-only). User intent is a generic
  `story-series-studio` plus shared `technical-storytelling`, not a
  Duckie-specific plugin.
- No `learning-studio`, `technical-storytelling`, or `story-series-studio`
  packages yet. No `registry/bundles.json`. No capability
  `requires`/`recommends`/`provides` metadata.
- Root `plugin.json` files are minimal name/description markers, not Agent
  Plugins 1.0.0 portable manifests.
- Product Demo Studio is intentionally left alone (not a filmmaking engine).

## Implementation order

1. **P0 — browser-toolkit** ✅ (landed on main): Microsoft Playwright MCP vocabulary +
   profile semantics; add `use-playwright-cli` and `use-playwright-test`
   provider references; router lane selection (CLI vs MCP vs Test); tests.
2. **P1 — portable plugin floor** ✅: root `plugin.json` as Agent Plugins 1.0.0
   portable core; host projections remain; version authority + projection
   checks.
3. **P1 — third-party + deps + bundles** ✅: generalize `thirdPartyPlugins` →
   extensions; track Remotion; optional Creative Writing; capability
   dependency metadata; `registry/bundles.json`.
4. **P2 — local-ai progressive disclosure** ✅: keep `ai.ps1` / one control plane;
   split agent knowledge into router + specialists (or reference packs).
5. **P2 — technical-storytelling + story-series-studio** ✅: schemas for episode /
   receipt / scene / continuity; FACT/DRAMATIZED/COMPOSITE; `startup-series`
   evolved to Receipts overlay (no private story bible in AgentHub).
6. **P2 — learning-studio** ✅: single `engaging-exam-coach` + schemas; attention-
   friendly loop; no CCAF-specific logic; Remotion optional.
7. **P3 — maturity/provenance/freshness**: registry metadata; replace misleading
   global `generatedAt` semantics; ChatGPT as distinct Codex distribution
   surface (deferred packaging OK).

## Non-goals

- Do not convert Product Demo Studio into a series engine.
- Do not vendor Remotion or Creative Writing into AgentHub.
- Do not put private series media, show bible, or credentials in this repo.
- Do not create eight CCAF skills or a standalone comedy-writer package skill
  beyond dramatization references.

## Validation

Each phase: package validators (if any) + `Validate-AgentHub.ps1` + affected
`tests/Test-*.ps1`. Recompute `contentHash` after package edits. Never claim
green without running checks.

## Decision log

- 2026-08-21: Proceed from owner review; P0 browser-toolkit is blocking before
  series capture workflows rely on it.
- 2026-08-21: Keep Product Demo Studio architecture; extract
  `media-production-core` only if duplication appears after series lands.
- 2026-08-25: Duplication appeared (briefings/training/explainers were hitting
  the demo pipeline). Added `media-studio` rather than renaming PDS. Rapid
  orchestration is the default; PDS gates stay fail-closed for live-product
  screencasts.

- 2026-08-21: P0 browser-toolkit landed on main (`b93c6a1`).
- 2026-08-21: P1 portable root version authority landed on main (`77bae75`).
- 2026-08-21: P1 thirdPartyExtensions + Remotion/CW tracking + bundles.json landed.
- 2026-08-21: P2 local-ai progressive disclosure landed.
- 2026-08-21: P2 technical-storytelling, story-series-studio, learning-studio
  registered; startup-series slimmed to Receipts-only skills.
- 2026-08-25: P3 `media-studio` landed as the parent local creative studio
  (rapid concept → video). Product Demo Studio is not renamed; it remains the
  product-screencast engine and bounces other kinds here. Remotion stays
  third-party (`npx skills add remotion-dev/skills`).
- 2026-08-26: Viewer-facing media-studio jobs apply
  `packages/media-studio/skills/media-studio/references/engagement.md`. Rapid
  still infers-and-runs; it no longer skips music/pacing/visual change for
  viewer-facing non-screencast kinds. Product-screencast craft stays in the PDS
  killer-demo guide. `intent: draft` remains the GPU skip.
- 2026-09-02: Media Studio 1.4.0 adds `media-storyboard` and
  `media-story-experience-reviewer`, richer screenplay/storyboard schemas, a
  Remotion scene-archetype kit, visual-bible art direction, fail-closed craft
  score (85), and `Inspect-MediaVisualQuality.ps1`. Remotion is required for
  viewer-facing briefing/training/explainer/series-episode unless draft.
