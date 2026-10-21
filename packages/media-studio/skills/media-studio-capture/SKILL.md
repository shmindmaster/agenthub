---
name: media-studio-capture
description: Use when a live product workflow needs deterministic Playwright WebM capture and Recast pointer/click/zoom finishing for a media-studio screencast. Product screens in the encoded film are WebM + Recast, not Ken Burns PNGs. Diagnostic stills are posters only.
---

# Media studio capture

Capture the real product. This is the screencast lane of media-studio (Playwright + Recast).

Engine: `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit\screencast\record-job.mjs` (and its adjacent `record-lib.mjs`). Contract: `../media-studio/references/product-picture.md`; cursor rules: `../media-studio/references/cursor-flow.md`. Native plugins also contain the package source; loose-skill hosts use the deployed runtime kit and `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools` for capture validators. Do not copy product UI with diffusion. PNG plates are diagnostic or posters; they are not the picture of a `screen` beat.

The product repository is read-only. Put Playwright scripts/specs, traces,
recordings, screenshots, manifests, authentication state, and reset evidence in
the external job workspace. Never add a capture test, fixture, config, helper,
dependency, or generated file to the product repo. A required product or seed
change is readiness feedback for a separate engineering task.

## 1. Browser provider (host-neutral)

Hosts do not share one browser tool. Resolve the provider, never a tool name:

1. **Deterministic capture is Playwright CLI or Playwright Test, run from the external job workspace.** This lane is identical on every host and is the only path that produces the trace plus the high-resolution WebM the compositor needs. Load `use-playwright-cli` / `use-playwright-test` (browser-toolkit).
2. **Exploratory looks** (finding a locator, checking a state before a take) use the running surface's own browser when `registry/fleet-profile.json` → `hostSurfaces` records `browser.isolated: true` for that surface; otherwise the `browser-evidence` / `interactive-browser-testing` routers resolve the fallback. `false` and `null` are different findings; neither is a provider. Exploration happens before the take, never inside it: a recorded take contains no looking around.
3. Do not write a host-specific browser MCP or in-app browser tool name into a storyboard, manifest, or script. A take that only one host can reproduce is not deterministic.

## 2. Procedure

1. Verify deployed commit, role, seed/reset, clean browser profile. Product-specific sign-in routes, navigation tricks, seed/reset commands, and environment overrides live in this skill's `references/` (`references/duckie-capture.md`, `references/abacare-local.md`); read the product's note before the first take.
2. Write `<jobRoot>/capture/scenes.mjs`: `export const options = { baseUrl, storageState?, viewport?, deviceScaleFactor?, recast?: { S05: { autoZoom: false } } }`, `export const order = [...]`, and one `async S05(h, ctx)` per screen beat. Drive the product only through the helpers `h.go`, `h.approach`, `h.click`, `h.typeText`, `h.pointAt`, `h.hoverHold`, `h.smoothScroll`, `h.expect`, `h.hold` (`kit/screencast/record-lib.mjs`). Every helper call is logged into the receipt; `h.expect(locator, 'label')` is the recorded proof that the product responded, so every interaction beat ends with one. Timing is the PDS production guide (eased pointer 400–600 ms, settle ≥250 ms, hold ≥500 ms) and is built into the helpers; do not add `page.waitForTimeout` padding to reach a narration length — re-pace the beat or split it.
   When the product ships `demo/harness.json` (demo-harness/v1, product-experience-engineering `kits/demo-harness`), `scaffold-video-workspace.mjs` prefills this file from it: `baseUrl`, the reset command, the deployed-SHA endpoints to record in `job.json`, and an S01 that asserts the synthetic-data label. The harness is read-only input; start the product with `node <tools>\demo-stack.mjs up --repo <product>` (windowless) before recording, where `<tools>` is the deployed `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools` (`scaffold-video-workspace.mjs` and `Inspect-MediaVisualQuality.ps1` are deployed there too; the canonical `demo-stack.mjs` is product-experience-engineering's `scripts/demo-stack.mjs`).
3. **Pre-flight, then record.** `record-job.mjs` runs `validate-capture-preflight.mjs <jobRoot>` before the first take and refuses to record when it fails: every id in `order` has a scene function, every capture-plan interaction and cue-plan beat maps to a narration segment, every cue-plan keyword is in its line, and each scene's literal typing fits its narration seconds. Fix the ids, keywords or typing before recording; `--skip-preflight` is diagnostic and leaves `recordings.preflight: skipped`, which no gate accepts. Then: `node <kit>\screencast\record-job.mjs <jobRoot> [S05 ...]` where `<kit>` is the deployed `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`. It records one Playwright take per beat (1600×1000 @2×, trace + WebM), finishes it with Recast (cursor approach, click ripple, punch-in), and writes `capture/clips/<id>.webm`, `capture/beats/<id>.json`, `capture/recordings.json`, and the hash-bound `capture/receipt.json`. A take flagged `SHORT` or `INVALID` is re-recorded, never padded.
4. One beat per action (`product-picture.md`). `story/capture-plan.json` interaction rows need `action`, `expectedResult`, `startState` ≠ `resultState`, `provesClaim`, and a WebM `clip`. Same session (`carryState`) for config then runtime. Do not skip loading/submit/response. Re-record only beats that fail mute test; keep the rest.
5. Validate with `validate-storyboard.mjs`, `validate-capture-manifest.mjs`, `validate-product-picture.mjs <jobRoot>` and **`validate-pointer-path.mjs <jobRoot>`** from the deployed shared tools (or the native plugin's `scripts/`) (clip on disk, receipt-bound, pointer motion, Recast status, no hidden freeze, purposeful cursor). Takes from an older recorder can be bound with the adjacent `backfill-capture-receipt.mjs` from their Playwright trace; the validator accepts those with a warning, but a take without an action log cannot pass the pointer-path gate and is re-recorded.

6. **Voice-first, purposeful cursor.** The narration is locked and ASR-timed before the take is judged (`../media-studio/SKILL.md`; word timestamps per line with `ai.ps1 transcribe <take.wav> --engine whisper --json-out voice/asr/<id>.json`). The pointer travels to the control in one eased move (no teleporting, no wandering), clicks, and the real UI responds; typing runs at a human cadence; scrolling is smooth. Label every action a line names (`h.click(loc, { label: 'Approve' })`, `h.typeText`, `h.pointAt(loc, { label })`) and end it with `h.expect(loc, 'Plan approved')`. Static scenes (dashboards, diagrams, architecture) use `h.pointAt` on the exact element as it is named, never a held frame. Leave about a second of lead-in before the first action and hold the result at least 2 s: compose aligns the click to the spoken word by holding the first frame (max 1.5 s) or trimming the head, and stops if the clip is too short.
7. **The cursor moves with purpose** (`cursor-flow.md`). It goes only to the next thing being named, one direction per beat, one `h.approach` per named target from wherever it already is. No flicking, no up-and-down, no parking the pointer off to the side, no circling a control, no move that is not followed by a labelled click, point or typing. Scroll once with `h.smoothScroll` toward the named element and stop there; never scroll past and return (a take that scrolls down six steps and back up six fails). Nothing moves that the narration is not about. `validate-pointer-path.mjs` reads the receipt's move, wheel, click, point and type events per beat against the cue sheet, counts direction reversals, total travel against the straight path through the named targets, scroll reversals and unnamed moves, and fails the take over the cue plan's allowance (default: zero reversals, zero scroll returns, travel ≤ 1.35× the direct path, zero unnamed moves). Loosening it needs `beats[id].pointer: { ..., reason }` in `story/cue-plan.json`. A failing take is re-recorded, not excused.
8. **Receipts carry action timestamps.** `record-job.mjs` writes `capture/receipt.json` `clips[id].actions` (move, wheel, click, type, point, expect with `tStart`, label, x, y; seconds into the take) beside `expectations`. `scripts/build-cue-sheet.mjs <jobRoot>` joins them with the narration words into `plan/cue-sheet.json`. Takes recorded before 2026-10-15 have no `actions`; re-record the beat, a backfilled receipt cannot be sync-gated or pointer-gated.

Screencast engagement is `product-picture.md` plus the story-experience review (`media-studio-qa`) on the encoded file, not `engagement.md` and not a second overlay stack. Annotation markup (dim, box, arrow, label, flow) is the compositor's layer, applied after Recast.

## 2b. Every ratio at its own viewport

A responsive product is captured once per delivered aspect ratio, each at a viewport that matches the ratio, with device emulation, with its own cue sheet and its own pointer or touch path. **Never derive a vertical or square cut by zooming, cropping or reframing a desktop capture**; `validate-picture-integrity.mjs` fails a 4:5 or 9:16 deliverable whose receipt shows a desktop viewport, and fails any product footage that was upscaled past its native pixels, stretched, cropped at a UI edge, or padded with bars.

- `job.json` carries the per-ratio table and the capture is at the delivery frame or larger (a 1920×1080 deliverable is recorded at 1920×1080, not 1600×1000 upscaled):

  ```json
  "captureViewports": {
    "16:9": { "width": 1920, "height": 1080, "deviceScaleFactor": 2 },
    "4:5":  { "width": 820,  "height": 1025, "deviceScaleFactor": 2, "device": "iPad Mini" },
    "9:16": { "width": 390,  "height": 844,  "deviceScaleFactor": 3, "device": "iPhone 14" }
  }
  ```
- One job root per ratio (its `job.json` names that ratio's `deliveryProfile`); `capture/scenes.mjs` exports `options.viewports` with the same keys and `record-job.mjs --ratio 9:16` records every take at that viewport with Playwright device emulation (`isMobile`, `hasTouch`, DSF). The receipt records `viewport`, `deviceScaleFactor`, `ratio` and `device` per clip; the gate reads them.
- Phone viewports are driven with a touch path: `h.tap(locator, { label })` instead of `h.click`; the eye-path rules of `cursor-flow.md` apply unchanged (one target per beat, scroll once toward it, nothing moves that the line is not about).
- Punch-in zoom on product footage is off by default. A Recast punch-in passes only when the take was captured at device scale factor 2 or higher (so the zoomed region stays at native resolution), the cue plan declares the beat (`beats[id].zoom: true`), and no UI the narration names leaves the frame; the reviewer attests the last point.
- A product that is not responsive declares it: `"responsive": false, "responsiveException": { "reason": "...", "declaredBy": "..." }` in `job.json`. Without that declaration the ratio gate fails closed. With it, the desktop capture may be used, but still unscaled, uncropped and without bars inside the product frame; the designed canvas around it is the storyboard's job.

## 2c. Native mobile app lane

When the product has a native mobile app that `registry/mobile-scope.json` includes (for example ABACare `apps/mobile`), 9:16 and phone-first flows are recorded from the real app on the emulator through `mobile-device-lab` (Appium), with a touch path, not from the web app at a phone viewport. `job.json` names the picture per flow:

```json
"flows": { "intake": { "picture": "native-app", "device": "Pixel 8" }, "billing": { "picture": "responsive-web", "ratio": "9:16" } }
```

The emulator recording lands in the external job workspace like any take, with a `capture/receipt.json` clip entry (`lane: "native-app"`, `device`, `viewport` = the device's screen pixels, `deviceScaleFactor`, the touch `actions` with `tStart`, label, x, y, and `expectations`); the same gates (pointer-path, picture-integrity, sync) read it. A flow the job marks `native-app` that was captured from the web fails the picture-integrity ratio check. Mobile eligibility is `mobile-scope.json`'s call, never inferred from a running emulator.

## 3. Recast engine notes (measured)

- Recast writes a `.recast-tmp` folder **inside the output clips directory**. Two renders into the same directory at once collide with `EPERM`. Render **sequentially per output directory**, or give each concurrent render its own directory.
- Recast's ffmpeg render can fail on long clips with many clicks (a 117 s clip with ~40 clicks failed). Fall back to a render **without `autoZoom`**, or split the recording into shorter takes and let the compositor join them.
- Trace frames are metadata fallback only; the final picture is the source WebM.
- Punch-in zoom needs subtitle cues: Recast `autoZoom` only zooms inside a cue, and empty-text cues are dropped. `renderRecast` writes `raw/<id>/zoom-cues.srt` (one cue per click, to the next click or 2.5 s) and feeds it to `subtitlesFromSrt`; cue text is never burned in. Before 2026-10-14 every take rendered with zero cues and no punch-in. Check the record log for `Zoom: zoompan` and the contact sheet (`build-contact-sheet.mjs`) for the punch-in.
- Recast warns when it upscales for zoom (`Source 1280x800 is upscaled 1.40x`). Record at the 1600x1000 default or larger when text must stay sharp inside a punch-in.
- Run `record-job.mjs` with the resolved `D:\Local-AI\data\artifacts\media-studio\...` job path, not the `%LOCALAPPDATA%\AgentHub\media-studio` link: Node 26 `mkdirSync(..., { recursive: true })` fails with ENOENT through that link (measured 2026-10-14).

## 4. Final check

- [ ] Provider resolved from `hostSurfaces`; deterministic takes are Playwright CLI/Test from the external workspace
- [ ] Trace, WebM, storage state, manifest all outside the product repo
- [ ] Pre-flight passed before the first take (`qa/capture-preflight.json`); nothing recorded with `--skip-preflight`
- [ ] Renders serialized per clips directory; long many-click clips split or rendered without `autoZoom`
- [ ] Storyboard, capture manifest, product-picture and pointer-path validate; every screen clip has a receipt entry
- [ ] Screen beats are WebM/MP4 + Recast, not PNG stills; every interaction beat ends with `h.expect`
- [ ] Every action a line names is labelled, ends in `h.expect`, and the receipt has `actions`; static beats use `h.pointAt`
- [ ] No reversal, no scroll return, no unnamed move in any take (`qa/pointer-path.json` PASS)
- [ ] Each ratio captured at its own viewport with device emulation (`captureViewports`, `--ratio`, receipt `ratio`/`device`); phone flows on a touch path; native-app flows from the emulator; no vertical cut derived from a desktop capture
- [ ] Capture at the delivery frame or larger at DSF ≥ 2; punch-in only where the cue plan declares it
- [ ] Capture-plan interactions have startState ≠ resultState and provesClaim; setup and runtime are the same session
