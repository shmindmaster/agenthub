---
name: media-studio-capture
description: Use when a live product workflow needs deterministic Playwright WebM capture and Recast pointer/click/zoom finishing for a media-studio screencast. Product screens in the encoded film are WebM + Recast, not Ken Burns PNGs. Diagnostic stills are posters only.
---

# Media studio capture

Capture the real product. This is the screencast lane of media-studio (Playwright + Recast).

Engine: `packages/media-studio/kit/screencast/record-job.mjs` (and `record-lib.mjs`). Contract: `../media-studio/references/product-picture.md`. Do not copy product UI with diffusion. PNG plates are diagnostic or posters; they are not the picture of a `screen` beat.

The product repository is read-only. Put Playwright scripts/specs, traces,
recordings, screenshots, manifests, authentication state, and reset evidence in
the external job workspace. Never add a capture test, fixture, config, helper,
dependency, or generated file to the product repo. A required product or seed
change is readiness feedback for a separate engineering task.

## 1. Browser provider (host-neutral)

Hosts do not share one browser tool. Resolve the provider, never a tool name:

1. **Deterministic capture is Playwright CLI or Playwright Test, run from the external job workspace.** This lane is identical on every host and is the only path that produces the trace plus the high-resolution WebM the compositor needs. Load `use-playwright-cli` / `use-playwright-test` (browser-toolkit).
2. **Exploratory looks** (finding a locator, checking a state before a take) use the running surface's own browser when `registry/fleet-profile.json` → `hostSurfaces` records `browser.isolated: true` for that surface; otherwise the `browser-evidence` / `interactive-browser-testing` routers resolve the fallback. `false` and `null` are different findings; neither is a provider.
3. Do not write a host-specific browser MCP or in-app browser tool name into a storyboard, manifest, or script. A take that only one host can reproduce is not deterministic.

## 2. Procedure

1. Verify deployed commit, role, seed/reset, clean browser profile. Product-specific sign-in routes, navigation tricks, seed/reset commands, and environment overrides live in this skill's `references/` (`references/duckie-prod-sim.md`, `references/abacare-local.md`); read the product's note before the first take.
2. Write `<jobRoot>/capture/scenes.mjs`: `export const options = { baseUrl, storageState?, viewport?, deviceScaleFactor?, recast?: { S05: { autoZoom: false } } }`, `export const order = [...]`, and one `async S05(h, ctx)` per screen beat. Drive the product only through the helpers `h.go`, `h.approach`, `h.click`, `h.typeText`, `h.pointAt`, `h.hoverHold`, `h.smoothScroll`, `h.expect`, `h.hold` (`kit/screencast/record-lib.mjs`). Every helper call is logged into the receipt; `h.expect(locator, 'label')` is the recorded proof that the product responded, so every interaction beat ends with one. Timing is the PDS production guide (eased pointer 400–600 ms, settle ≥250 ms, hold ≥500 ms) and is built into the helpers; do not add `page.waitForTimeout` padding to reach a narration length — re-pace the beat or split it.
3. Record: `node <kit>/screencast/record-job.mjs <jobRoot> [S05 ...]` where `<kit>` is `packages/media-studio/kit` (repo) or `%LOCALAPPDATA%\AgentHub\media-studioriefing-kit` (synced). It records one Playwright take per beat (1600×1000 @2×, trace + WebM), finishes it with Recast (cursor approach, click ripple, punch-in), and writes `capture/clips/<id>.webm`, `capture/beats/<id>.json`, `capture/recordings.json`, and the hash-bound `capture/receipt.json`. A take flagged `SHORT` or `INVALID` is re-recorded, never padded.
4. One beat per action: start → locator → pointer lead → action → visible result hold. Mirror that in `story/capture-plan.json` (`schemas/capture-plan.schema.json`): an `interaction` row needs `action`, `expectedResult`, and a WebM `clip` — not `plateName: *.png` alone.
5. Validate with `scripts/validate-storyboard.mjs`, `scripts/validate-capture-manifest.mjs`, and `scripts/validate-product-picture.mjs <jobRoot>` (clip on disk, receipt-bound, pointer motion, Recast status, no hidden freeze). Takes from an older recorder can be bound with `scripts/backfill-capture-receipt.mjs` from their Playwright trace; the validator accepts those with a warning.

## 3. Recast engine notes (measured)

- Recast writes a `.recast-tmp` folder **inside the output clips directory**. Two renders into the same directory at once collide with `EPERM`. Render **sequentially per output directory**, or give each concurrent render its own directory.
- Recast's ffmpeg render can fail on long clips with many clicks (a 117 s clip with ~40 clicks failed). Fall back to a render **without `autoZoom`**, or split the recording into shorter takes and let the compositor join them.
- Trace frames are metadata fallback only; the final picture is the source WebM.

## 4. Final check

- [ ] Provider resolved from `hostSurfaces`; deterministic takes are Playwright CLI/Test from the external workspace
- [ ] Trace, WebM, storage state, manifest all outside the product repo
- [ ] Renders serialized per clips directory; long many-click clips split or rendered without `autoZoom`
- [ ] Storyboard, capture manifest, and product-picture validate; every screen clip has a receipt entry
- [ ] Screen beats are WebM/MP4 + Recast, not PNG stills; every interaction beat ends with `h.expect`
