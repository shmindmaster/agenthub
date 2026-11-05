# Recording

## Scenes module

`capture/scenes.mjs` exports `options = { baseUrl, storageState?, viewport?, deviceScaleFactor?, recast?: { S05: { autoZoom: false } } }`, `order = [...]`, and one `async S05(h, ctx)` per screen beat. Drive the product only through `h.go`, `h.approach`, `h.click`, `h.typeText`, `h.uploadFile`, `h.fillValue`, `h.selectOption`, `h.pointAt`, `h.hoverHold`, `h.smoothScroll`, `h.expect`, `h.hold`. End every interaction beat with `h.expect(locator, 'label')`. Pacing is built into the helpers, so never add `page.waitForTimeout`; re-pace or split the beat.

## Every ratio at its own viewport

One job root per delivered ratio, with its own cue sheet and pointer or touch path. Never zoom, crop or reframe desktop capture into a vertical or square cut.

| Ratio | Viewport | DSF | `device` |
| --- | --- | --- | --- |
| 16:9 | 1920×1080 | 2 | |
| 4:5 | 820×1025 | 2 | iPad Mini |
| 9:16 | 390×844 | 3 | iPhone 14 |

- `job.json` `captureViewports` holds the table; `scenes.mjs` `options.viewports` uses the same keys, plus `isMobile`, `hasTouch`.
- `record-job.mjs <jobRoot> --ratio 9:16` records that entry. `capture/receipt.json` stores `viewport`, `deviceScaleFactor`, `ratio`, `device`.
- Phone viewports use `h.tap(locator, { label })`, not `h.click`.
- Punch-in passes only at DSF ≥ 2 with `beats[id].zoom: true` in `story/cue-plan.json`. No named UI may leave the frame.
- Responsive exception: `"responsive": false, "responsiveException": { reason, declaredBy }` in `job.json`. Footage stays unscaled, uncropped, unbarred.

## Native mobile app lane

If `registry/mobile-scope.json` includes the native app, record phone flows on an emulator through `mobile-device-lab` (Appium). `job.json` `flows.<id>.picture` is `native-app` or `responsive-web`. Its `capture/receipt.json` entry: `lane: "native-app"`, device, `viewport` (screen pixels), DSF, touch actions (`tStart`, label, x, y), expectations.

## Recast limits

- `.recast-tmp` sits in the clips directory: one render at a time per directory, or `EPERM`.
- `autoZoom` works only inside a cue; `raw/<id>/zoom-cues.srt` supplies them. Check the log for `Zoom: zoompan`.
- Long many-click clips can fail: `record-job.mjs` retries without `autoZoom`, then records `recast: fallback`, which fails unless `job.json` sets `recastFallbackAllowed`. Split the take.
- Run from the resolved real path under `MEDIA_STUDIO_ROOT`, not the `%LOCALAPPDATA%` link (`mkdirSync` ENOENT).

## Native input helpers

All need `{ label }` and synthetic values, abort on failure, and prove input only: follow with `h.expect`. Each records into `capture/receipt.json`; keep `trace.zip` with the take.

- `h.uploadFile(input, path, { label })`: one `input[type=file]`, hidden allowed. Records `type: upload`, `tStart`, `tEnd`, target, `file: { name, bytes, sha256, mimeType }`, `events.uploads`. Never the source path.
- `h.selectOption(select, value, { label })`: one visible enabled single select. Records `type: select`, `value`, `beforeValue`, `optionLabel`, `targetBox`, hashed before/after images, `events.selections`; `select-failed` on error.
- `h.fillValue(field, value, { label })`: text, number, date-type or textarea; never password, file, hidden. Records `type: fill`, `method: locator.fill`, `inputType`, read-back `value`, `targetBox`, `events.fills`. `validate-pointer-path.mjs` does not name `fill`: `h.pointAt` the field first and set `beats[id].pointer: { maxUnnamedMoves: 3, reason }`.
