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

1. Verify deployed commit, role, seed/reset, clean browser profile. Product-specific sign-in routes, navigation tricks, and environment overrides live in this skill's `references/` (for example `references/duckie-prod-sim.md`); read the product's note before the first take.
2. Playwright CLI or Playwright Test from the external workspace. Preserve trace + high-resolution WebM outside the product repo.
3. Recast (`playwright-recast`) is required on pointer beats: cursor approach, click ripple, punch-in zoom. Source WebM without Recast is only the fallback when Recast's ffmpeg render fails (see §3). Screencast engagement is product-picture plus encoded-file review, not `engagement.md` and not a second overlay stack. Annotation markup for a technical story (dim, box, arrow, label, flow) is the compositor's layer (`media-studio-compose`), applied after Recast.
4. One beat per action: start → locator → pointer lead → action → visible result hold. Write that into `story/capture-plan.json` (`schemas/capture-plan.schema.json`). An `interaction` row needs `action`, `expectedResult`, and a WebM/MP4 `clip` — not `plateName: *.png` alone.
5. Validate with `packages/media-studio/scripts/validate-storyboard.mjs`, `validate-capture-manifest.mjs`, and `validate-product-picture.mjs`.

## 3. Recast engine notes (measured)

- Recast writes a `.recast-tmp` folder **inside the output clips directory**. Two renders into the same directory at once collide with `EPERM`. Render **sequentially per output directory**, or give each concurrent render its own directory.
- Recast's ffmpeg render can fail on long clips with many clicks (a 117 s clip with ~40 clicks failed). Fall back to a render **without `autoZoom`**, or split the recording into shorter takes and let the compositor join them.
- Trace frames are metadata fallback only; the final picture is the source WebM.

## 4. Final check

- [ ] Provider resolved from `hostSurfaces`; deterministic takes are Playwright CLI/Test from the external workspace
- [ ] Trace, WebM, storage state, manifest all outside the product repo
- [ ] Renders serialized per clips directory; long many-click clips split or rendered without `autoZoom`
- [ ] Storyboard, capture manifest, and product-picture validate
- [ ] Screen beats are WebM/MP4 + Recast, not PNG stills
