# Screen stage

The default finisher for product-screen beats (since 4.6.0). It replaces Recast. A screen beat is the real page, captured as high-resolution frames, shown edge to edge with a camera that springs toward the next action, a large cursor drawn from the real pointer positions, and real motion blur only while something moves. Recast stays selectable (`job.screenStage: false`, `--recast`, and always for `options.mobileLayout`) so old jobs re-render unchanged.

Look: the owner's reference film `hero-recording.mp4` (style reference only; it is never committed). Truth rule: the film never shows a pointer position or a click the recording does not contain.

## Capture

- CDP `Page.startScreencast` at the browser's own device scale, real frame timestamps, no `recordVideo`. Headless, on Daytona.
- Viewport by delivered ratio, at its own responsive layout, filling its frame edge to edge: `16:9` 1280x720 @2.5 (3200x1800 frames), `9:16` 405x720 @4 (touch), `4:5` 432x540 @4, `1:1` 720x720 @3. Zoom default 1.5 (range 1.3 to 1.8; portrait and square 1.15 to 1.35).
- 2.5x is the 16:9 default because the browser then delivers 60 unique frames a second while the page animates; 3x manages 37 to 50. The gate fails a capture under 50 unique fps (median) or under a 30 fps floor.
- The pointer is driven in the recorder with a gentle arc and a minimum-jerk speed curve (400 to 800 ms by length). Every move logs the real CSS cursor under it; every press logs the target element's box.

## Plan (a pure function of the receipt)

`stage-plan.mjs` turns receipt events and the compose edit list into the camera, cursor, highlight and cue times. The same input always gives the same plan; the gate rebuilds it and refuses a plan that differs.

- Presses cluster by joint bounding box (gap 1.3 s, span 3.2 s, must fit at zoom above 1). Typing is a target and holds the field in frame to the end of the burst. A far target pans at the held zoom; a quiet gap of 3 s or more pulls back to the full page.
- The region is the target box plus the pixels that changed within 1.2 s of the press (`stage-changes.mjs`, measured from the captured frames). If the result lies elsewhere it joins the region when both fit, otherwise the camera goes to it within 0.25 s of the press.
- Zoom is 1.5. 1.8 only for a tiny target with a tiny result in the same view. Never past the page edges; the film opens and closes on the full page, clean, held 0.35 to 0.6 s before the first move.
- The camera starts 0.1 s before the pointer starts to move, so the two are never at peak speed together. Camera: critically damped spring, peak 0.1 s, about 90 percent at 0.35 s, settled by 0.6 s, no overshoot.
- Cursor: arrow, hand or I-beam from the real CSS cursor (type changes under 120 ms are not drawn), a PCHIP path through the recorded samples, press response 0.9 and back over 0.15 s, still for the last 0.5 s. Idle-hide (default): a still cursor fades after 2 s, never during a `pointAt`. Hide per beat or span with `screenStage.hideCursor`. Touch captures draw a touch circle and a tap ripple instead.
- No dead time without a reason. Idle (no input and frozen pixels) may be cut; anything else needs a declared `speedReason`. Typing plays at 2x (`screenStage.typingSpeed`, cap 3x) with 0.15 s ramps; the last 0.4 s, autocomplete lists and spinners play at real speed. The speed ramps are part of the edit, so the camera, cursor, highlight, click sounds and cue times all sit on the same time map before the narration is aligned.

## Options (`job.json` `screenStage`)

| Key | Meaning |
| --- | --- |
| `zoom.mode` | `auto` (default), `manual` (declared `regions`), `off` (full page) |
| `zoom.level` | 1.3 to 1.8; the default for auto regions |
| `zoom.regions[]` | `{ target: <action label> or box, from, to, level, instant }`; `instant` is a declared jump cut |
| `highlights[]` | `{ action: <label>, start, hold, dim }`: one at a time, the cutout is the recorded element box, 0.25 s ease, default dim 0.45, thin outline. There is no blur-mask: sensitive data is fixed in the data and the take re-recorded |
| `idleHide` | `false` turns idle-hide off |
| `hideCursor[]` | `{ beat }` or `{ from, to }` |
| `typingSpeed` | number 1 to 3, or `false` |
| `background` | for a phone or native screen inside a wider frame only: a generated gradient (from the page's own colour) behind the centred screen. Every other film is full bleed: no wallpaper, presenter, window chrome, corners or shadow |
| `clickSound` | `'off'` to omit the effects stem |

No burned-in captions. Subtitles stay a sidecar `.srt` (`treatments.md`).

## Render

One Remotion composition (`ScreenStage`), one WebGL2 pass per frame, 60 fps in every ratio. The page frame is an sRGB texture; each output pixel averages 32 to 64 jittered samples across a 170 degree shutter in float, in linear light, and converts to sRGB once. The cursor is blurred separately, on its own on-screen path. A still view is a fixed 4x4 anti-aliasing filter, so a hold is the same picture every frame. Colour is tagged BT.709. Renders run on Daytona (`render-lanes.md`); on a box with no GPU use `--gl=swangle` (the default there).

## Sound

`stage-effects.mjs` writes `<base>-effects.wav`: one synthesised click (or tap) per drawn press, placed through the same time map, about -26 dBFS under speech and -20 dBFS alone, never ducked. `Finish-Media.ps1 -Effects` mixes it after loudness normalisation. Music bed rule: in the 2 to 5 kHz band, within 30 ms of every press, the effects stem is at least 6 dB above the bed (`validate-effects-mix.mjs`); lower the bed or pick another.

## Gates

`validate-screen-stage.mjs` measures the encoded film against the plan, on decoded frames. Each rule below fails the core-v1 picture and has a negative control run in the proof:

1. 60 fps stream and a regular timestamp grid; the plan equals the plan its inputs give; the speed ramps equal the typing and declared spans.
2. The film opens and closes on the full page, same framing; at every press the target is inside the measured view; each move follows the planned spring and is settled in time; nothing drifts during a hold; no duplicated frame inside a move.
3. Colour: a flat patch keeps its colour within 2/255 of the hold during a move.
4. No repeated copies along the motion (autocorrelation compared with an ideal blur).
5. No fade in: the opening is full brightness from the first frame and held still.
6. The result of a press is inside the measured view within 1 s; no unchanged view is held over 1 s without narration.
7. Zoom above 1.5 only for a tiny target and result; the camera leads the pointer; a result elsewhere is reached within 0.25 s.
8. The cursor is drawn on the click point; it presses to about 0.9 of its size and returns.
9. The capture delivered 50 or more unique frames a second while the page animated.

`validate-encoded-picture.mjs` defers every stage segment to `qa/screen-stage.json` for the same candidate sha256.
