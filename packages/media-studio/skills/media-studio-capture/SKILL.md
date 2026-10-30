---
name: media-studio-capture
description: Use when a live product workflow needs deterministic Playwright WebM capture and Recast pointer/click/zoom finishing for a media-studio screencast. Product screens in the encoded film are WebM + Recast, not Ken Burns PNGs. Diagnostic stills are posters only.
---

# Media studio capture

Engine: `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit\screencast\record-job.mjs` (adjacent `record-lib.mjs`). Contract: `../media-studio/references/product-picture.md`; cursor rules: `../media-studio/references/cursor-flow.md`. Native plugins contain package source; loose-skill hosts use the deployed runtime kit and `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools` for capture validators. PNG plates are diagnostic/posters only, never the picture of a `screen` beat. Do not copy product UI with diffusion.

The product repository is read-only. All Playwright scripts, traces, recordings, screenshots, manifests, auth state, and reset evidence go in the external job workspace. Never add a capture test, helper, or capture file to the product repo. A required product/seed change is readiness feedback for a separate engineering task.

## 1. Browser provider (host-neutral)

1. **Deterministic capture is Playwright CLI or Test** from the external job workspace. Load `use-playwright-cli` / `use-playwright-test` (browser-toolkit). This is the only path producing trace + high-res WebM.
2. **Exploratory looks** use the running surface's browser when `registry/fleet-profile.json` → `hostSurfaces` records `browser.isolated: true`; otherwise `browser-evidence` / `interactive-browser-testing` routers resolve fallback. `false` and `null` are different findings; neither is a provider. Exploration happens before the take, never inside it.
3. Never write a host-specific browser MCP or tool name into a storyboard, manifest, or script.

## 2. Procedure

1. Verify deployed commit, role, seed/reset, clean browser profile. Product-specific sign-in, navigation, seed/reset commands, and env overrides live in `references/` (`references/duckie-capture.md`, `references/abacare-local.md`); read the product note before first take.
2. Write `<jobRoot>/capture/scenes.mjs`: export `options = { baseUrl, storageState?, viewport?, deviceScaleFactor?, recast?: { S05: { autoZoom: false } } }`, `order = [...]`, one `async S05(h, ctx)` per screen beat. Drive product only through helpers `h.go`, `h.approach`, `h.click`, `h.typeText`, `h.uploadFile`, `h.fillValue`, `h.selectOption`, `h.pointAt`, `h.hoverHold`, `h.smoothScroll`, `h.expect`, `h.hold` (`kit/screencast/record-lib.mjs`). Every helper call logs into receipt; every interaction beat ends with `h.expect(locator, 'label')`. Timing per PDS guide (eased pointer 400–600 ms, settle ≥250 ms, hold ≥500 ms) is built into helpers; do not add `page.waitForTimeout` padding — re-pace or split the beat.
   When product ships `demo/harness.json` (demo-harness/v1), `scaffold-video-workspace.mjs` prefills from it. Start product with `node <tools>\demo-stack.mjs up --repo <product>` (windowless), `<tools>` = deployed `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools`.
3. **Pre-flight, then record.** `record-job.mjs` runs `validate-capture-preflight.mjs <jobRoot>` and refuses on failure (every id in `order` has a scene function, capture-plan interactions and cue-plan beats map to narration segments, keywords match lines, typing fits narration seconds). `--skip-preflight` is diagnostic only, leaves `recordings.preflight: skipped`, no gate accepts it. Record: `node <kit>\screencast\record-job.mjs <jobRoot> [S05 ...]`, `<kit>` = `%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit`. Records one take per beat (1600×1000 @2×, trace + WebM), finishes with Recast, writes `capture/clips/<id>.webm`, `capture/beats/<id>.json`, `capture/recordings.json`, hash-bound `capture/receipt.json`. SHORT/INVALID takes are re-recorded, never padded.
4. One beat per action (`product-picture.md`). `story/capture-plan.json` interactions need `action`, `expectedResult`, `startState` ≠ `resultState`, `provesClaim`, WebM `clip`. Same session (`carryState`) for config then runtime. Do not skip loading/submit/response. Re-record only beats failing mute test.
5. Validate with `validate-storyboard.mjs`, `validate-capture-manifest.mjs`, `validate-product-picture.mjs <jobRoot>`, and **`validate-pointer-path.mjs <jobRoot>`** from deployed shared tools. Old takes can be bound with `backfill-capture-receipt.mjs`; validator accepts with warning but takes without action log cannot pass pointer-path gate.
6. **Voice-first, purposeful cursor.** Lock narration before judging take. Use `ai.ps1 align <take.wav> --script <locked-line.txt> --output <qa/align/run-id/report.json>` (80 ms grid); Whisper is transcript-only. Keep raw report hashes. Align picture to voice, never stretch voice.
7. **Cursor moves with purpose** (`cursor-flow.md`). One direction per beat, one `h.approach` per named target. No flicking, no up-and-down, no parking, no circling, no move not followed by labelled click/point/typing. Scroll once with `h.smoothScroll` toward named element, stop there; never scroll past and return. `validate-pointer-path.mjs` counts direction reversals, travel vs straight path, scroll reversals, unnamed moves; fails over cue plan allowance (default: zero reversals, zero scroll returns, travel ≤ 1.35× direct path, zero unnamed moves). Loosening needs `beats[id].pointer: { ..., reason }` in `story/cue-plan.json`. Failing takes are re-recorded.
8. **Receipts carry action timestamps.** `record-job.mjs` writes `capture/receipt.json` `clips[id].actions` (move, wheel, click, type, point, expect with `tStart`, label, x, y) beside `expectations`. `scripts/build-cue-sheet.mjs <jobRoot>` joins with narration into `plan/cue-sheet.json`. Takes before 2026-10-15 have no `actions`; re-record — backfilled receipts cannot be sync-gated or pointer-gated.

Screencast engagement is `product-picture.md` plus story-experience review (`media-studio-qa`) on encoded file, not `engagement.md` and not a second overlay stack. Annotation markup is compositor's layer, applied after Recast.

## 3. Every ratio at its own viewport

Capture once per delivered aspect ratio at matching viewport with device emulation, own cue sheet and pointer/touch path. **Never derive vertical/square cut by zooming, cropping, or reframing desktop capture**; `validate-picture-integrity.mjs` fails 4:5/9:16 deliverables with desktop-viewport receipts, upscaled/stretched/cropped/barred footage.

`job.json` carries per-ratio table; capture at delivery frame or larger:
```json
"captureViewports": {
  "16:9": { "width": 1920, "height": 1080, "deviceScaleFactor": 2 },
  "4:5":  { "width": 820,  "height": 1025, "deviceScaleFactor": 2, "device": "iPad Mini" },
  "9:16": { "width": 390,  "height": 844,  "deviceScaleFactor": 3, "device": "iPhone 14" }
}
```
One job root per ratio; its `job.json` names that ratio's `deliveryProfile`; `capture/scenes.mjs` exports `options.viewports` with matching keys (`isMobile`, `hasTouch`, DSF). `record-job.mjs --ratio 9:16` records at that viewport with device emulation. Receipt records `viewport`, `deviceScaleFactor`, `ratio`, `device` per clip. Phone viewports use `h.tap(locator, { label })` instead of `h.click`; eye-path rules unchanged.

Punch-in zoom off by default. Passes only when DSF ≥ 2, cue plan declares `beats[id].zoom: true`, no named UI leaves frame (reviewer attests). Non-responsive products declare `"responsive": false, "responsiveException": { "reason": "...", "declaredBy": "..." }` in `job.json`; without it ratio gate fails closed. Even with this exception, the desktop capture stays unscaled, uncropped and without bars inside the product frame; the storyboard designs the surround.

## 4. Native mobile app lane

When `registry/mobile-scope.json` includes the product's native app, 9:16/phone-first flows record from real app on emulator via `mobile-device-lab` (Appium) with touch path, not web at phone viewport. `job.json` names picture per flow (`"picture": "native-app"` or `"responsive-web"`). Emulator recording lands in job workspace with receipt (`lane: "native-app"`, device, viewport, DSF, touch actions with `tStart`, label, x, y, expectations); `viewport` is the device's screen pixels; same gates apply. Web capture for a `native-app` flow fails picture-integrity. Mobile eligibility is `mobile-scope.json`'s call only.

## 5. Recast engine notes

- Recast writes `.recast-tmp` inside output clips directory. Concurrent renders into same directory collide with `EPERM`. Serialize per output directory.
- ffmpeg render can fail on long clips with many clicks (117 s, ~40 clicks). Fall back to render without `autoZoom` or split into shorter takes.
- Trace frames are metadata fallback only; final picture is source WebM.
- Punch-in needs subtitle cues: `autoZoom` only zooms inside a cue; empty-text cues are dropped. `renderRecast` writes `raw/<id>/zoom-cues.srt`; cue text never burned in. Check record log for `Zoom: zoompan` and contact sheet (`build-contact-sheet.mjs`).
- Recast warns on upscale for zoom. Record at 1600×1000+ when text must stay sharp in punch-in.
- Run with resolved `D:\Local-AI\data\artifacts\media-studio\...` path, not the `%LOCALAPPDATA%\AgentHub\media-studio` link: Node 26 `mkdirSync(..., { recursive: true })` fails ENOENT through that link.

## 6. Final check

- [ ] Provider resolved from `hostSurfaces`; deterministic takes are Playwright from external workspace
- [ ] All artifacts outside product repo
- [ ] Pre-flight passed; nothing recorded with `--skip-preflight`
- [ ] Renders serialized per clips directory; long many-click clips split or without `autoZoom`
- [ ] Storyboard, capture manifest, product-picture, pointer-path validate; every clip has receipt entry
- [ ] Screen beats are WebM/MP4 + Recast, not PNGs; every interaction beat ends with `h.expect`
- [ ] Every named action labelled, ends in `h.expect`, receipt has `actions`; static beats use `h.pointAt`
- [ ] No reversal, no scroll return, no unnamed move (`qa/pointer-path.json` PASS)
- [ ] Each ratio at own viewport with device emulation; phone flows touch path; native-app from emulator; no vertical cut from desktop capture
- [ ] Capture at delivery frame or larger, DSF ≥ 2; punch-in only where cue plan declares
- [ ] Capture-plan interactions have startState ≠ resultState and provesClaim; setup/runtime same session

## File selection (including hidden dropzone inputs)

Use `await h.uploadFile(modal.locator('input[type=file]'), '/remote/path/source.csv', { label: 'Select synthetic September CSV', hold: 500 })`, then `await h.expect(preview, 'CSV Preview')` for the actual visible response. The path must exist on the recording runner. The locator must resolve to exactly one real file input; hidden inputs are supported without a bounding box or a fabricated click. A missing file, directory, ambiguous locator, wrong element or failed native selection aborts the scene.

The helper passes the exact locally read bytes to Playwright `locator.setInputFiles`; it does not inject DOM change events. Only after Playwright returns does it record `type: upload`, the real `tStart`/`tEnd` in recording seconds, label, locator target, method, and `file: { name, bytes, sha256, mimeType }`. The private source path and file contents are omitted. CSV defaults to `text/csv`; other files use `application/octet-stream` unless `mimeType` is supplied. The normal recording trace retains the native action; keep `trace.zip` with the take. Selection proves selection only: retain the separate observed preview/import outcome and never describe this event as a pointer click or a completed server import. It adds `summary.uploads` without changing the receipt schema version.

## Native single-select controls

Use `await h.selectOption(page.getByLabel('Viewing as', { exact: true }), 'reviewer', { label: 'Choose content reviewer' })`, then `h.expect` for the actual application response. Only a unique visible, enabled, single-select element and exactly one enabled matching option are accepted, including disabled optgroup checks. Use public or synthetic nonsecret values only. The helper approaches the control, saves before/after images under the recording raw directory, calls real Playwright `locator.selectOption`, and checks the returned value, input readback and selected option label. No DOM assignment, injected change event or invented pointer click is used.

The `select` receipt includes method, label, locator target, before/after value, option label, native action times, measured bounds, pointer position and relative image paths with SHA256. `summary.selections` counts only successful selections. A failed stage records `select-failed` with safe stage/timing and any image references already obtained, then aborts without a success event or beat. Keep the images and normal Playwright trace with the recording; selection alone does not prove the application processed it. The production recorder supplies `rawDir`; standalone callers must supply it to `bindHelpers` for image receipts.

## Controlled input values

Use `await h.fillValue(modal.getByLabel('Declared reporting month', { exact: true }), '2026-09', { label: 'Set reporting month', hold: 500 })` for a native month/date/text input that cannot be entered with keyboard typing. The unique visible input is approached with real pointer motion, filled with Playwright `locator.fill`, and read back through `inputValue`; a failed fill or mismatched readback aborts without a success event. Password, file, hidden and unsupported controls are rejected. Use only public or synthetic nonsecret values.

The receipt records `type: fill`, `method: locator.fill`, actual `inputType`, exact readback `value`, recording-clock `tStart`/`tEnd`, label, locator target and measured target bounds in recorded pixels. It adds `summary.fills`, never keystrokes or an invented click. Keep the native trace and follow with `h.expect` for the actual preview or result; a field value alone does not prove the application processed it. Do not substitute DOM assignment or synthetic change events.
