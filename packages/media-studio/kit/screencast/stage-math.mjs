// Screen stage geometry and motion: pure functions, no filesystem, no DOM. The renderer (kit/src/ScreenStage.tsx), the plan builder
// (stage-plan.mjs) and the encoded-film gate (scripts/validate-screen-stage.mjs) all read the camera, cursor and frame lookup
// from here, so the film and the gate cannot disagree about where the camera is.
// Contract: skills/studio/references/screen-stage.md.
//
// Space: the film frame is W x H (full bleed). A page of viewport vw x vh CSS px is shown edge to edge at "wide", so one CSS px is
// W / vw film px. The camera is { cx, cy, z } in wide-frame pixels: the view is the (W/z x H/z) rectangle centred on (cx, cy),
// scaled up by z. screen = (stage - c) * z + (W/2, H/2).
// Spring idea for the camera (critically damped, no overshoot) follows the measured owner reference; the target-grouping ideas
// (joint bounding box, typing as a target, two-keyframe pan inside one held zoom) follow connerkward/screenstudio-alt-skill (MIT).

export const STAGE = Object.freeze({
  fps: 60,
  viewport: Object.freeze({ width: 1280, height: 720 }),
  deviceScaleFactor: 3,
  zoom: Object.freeze({ min: 1.3, default: 1.5, max: 1.8 }),         // 16:9 and wider: the page is small at wide, so the camera works harder
  zoomPortrait: Object.freeze({ min: 1.15, default: 1.25, max: 1.35 }), // 9:16, 4:5, 1:1: phone UI is already large
  omega: 10.5,              // critically damped spring: peak speed ~0.095 s, ~90% at 0.37 s, ~99% at 0.63 s, no overshoot
  leadSeconds: 0.55,        // the camera starts this long before the press it serves
  fill: 0.78,               // a zoom region may fill at most this share of the view
  bias: Object.freeze({ x: 0.42, y: 0.38 }), // where a lone control sits in the view, leaving room for what it opens
  openWideSeconds: 0.4,     // the first move starts no sooner than this
  closeHoldSeconds: 0.9,    // the last press and its result stay in the zoomed view this long before the pull back
  closeWideSeconds: 1.3,    // the film ends on the full page for at least this long when the run allows
  settleSeconds: 0.7,       // a move is judged settled this long after it starts (99% at omega 10.5)
  contextGapSeconds: 3.0,   // a quiet gap this long between two targets pulls back to the full page
  clusterGapSeconds: 1.3,   // presses closer than this share one zoom region when their joint box fits
  clusterSpanSeconds: 3.2,
  mergeInset: 0.1,          // a target already inside the current view, inset by this share, needs no move
  cursorHeight: Object.freeze({ wide: 40, zoomed: 58 }),
  press: Object.freeze({ seconds: 0.2, scale: 0.84 }),
  hideFadeSeconds: 0.2,
  idleHideSeconds: 2.0,     // a still cursor fades after this long (never across a pointAt) and is back before the next move
  kindDebounceSeconds: 0.12,// a cursor-type change that lasts less than this is not drawn
  restSeconds: 0.5,         // the cursor stops moving this long before the run ends
  blur: Object.freeze({ shutterAngle: 300, samples: 10, cameraSpeed: 150, cursorSpeed: 900 }), // speeds in px/s on screen
});

/** Capture viewport per delivered ratio: each ratio is recorded at its own responsive viewport and fills its frame edge to edge. */
export const STAGE_CAPTURE = Object.freeze({
  '16:9': Object.freeze({ width: 1280, height: 720, deviceScaleFactor: 3 }),
  '9:16': Object.freeze({ width: 405, height: 720, deviceScaleFactor: 4, isMobile: true, hasTouch: true }),
  '4:5': Object.freeze({ width: 432, height: 540, deviceScaleFactor: 4 }),
  '1:1': Object.freeze({ width: 720, height: 720, deviceScaleFactor: 3 }),
});

export const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const lerp = (a, b, t) => a + (b - a) * t;

// ------------------------------------------------------------------------------------------------ geometry

/** Page CSS px -> stage px, and the stage frame. The viewport must have the frame's aspect: there are no bars. */
export function stageGeometry(frame, viewport) {
  const { width: W, height: H } = frame;
  const k = W / viewport.width;
  const aspectError = Math.abs(viewport.height * k - H) / H;
  if (aspectError > 0.01) throw new Error(`screen stage: the capture viewport ${viewport.width}x${viewport.height} does not match the ${W}x${H} frame (full bleed has no bars); capture at ${W}x${H} aspect, for example ${STAGE.viewport.width}x${STAGE.viewport.height}`);
  return { W, H, k, zoom: W / H > 1.2 ? STAGE.zoom : STAGE.zoomPortrait, unit: Math.min(W, H) / 1080 };
}

export const wideCamera = (g) => ({ cx: g.W / 2, cy: g.H / 2, z: 1 });

/** Keep the view inside the page: no empty border at any zoom. */
export function clampCamera(cam, g) {
  const z = clamp(cam.z, 1, g.zoom.max + 0.2);
  const hw = g.W / (2 * z), hh = g.H / (2 * z);
  return { cx: clamp(cam.cx, hw, g.W - hw), cy: clamp(cam.cy, hh, g.H - hh), z };
}

export function viewRect(cam, g) {
  const hw = g.W / (2 * cam.z), hh = g.H / (2 * cam.z);
  return { x: cam.cx - hw, y: cam.cy - hh, w: 2 * hw, h: 2 * hh };
}

export const projectPoint = (cam, g, p) => ({ x: (p.x - cam.cx) * cam.z + g.W / 2, y: (p.y - cam.cy) * cam.z + g.H / 2 });
export const projectBox = (cam, g, b) => {
  const a = projectPoint(cam, g, { x: b.x, y: b.y });
  return { x: a.x, y: a.y, w: b.w * cam.z, h: b.h * cam.z };
};
export const toStageBox = (g, cssBox) => ({ x: cssBox.x * g.k, y: cssBox.y * g.k, w: cssBox.w * g.k, h: cssBox.h * g.k });
export const unionBox = (boxes) => {
  const x0 = Math.min(...boxes.map((b) => b.x)), y0 = Math.min(...boxes.map((b) => b.y));
  const x1 = Math.max(...boxes.map((b) => b.x + b.w)), y1 = Math.max(...boxes.map((b) => b.y + b.h));
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
};
/** Is the box inside the camera's view, inset by `inset` of the view on every side? */
export function boxInView(cam, g, box, inset = 0) {
  const v = viewRect(cam, g);
  const mx = v.w * inset, my = v.h * inset;
  return box.x >= v.x + mx - 1e-6 && box.y >= v.y + my - 1e-6 && box.x + box.w <= v.x + v.w - mx + 1e-6 && box.y + box.h <= v.y + v.h - my + 1e-6;
}

/**
 * The zoom for a region: the largest zoom (up to the maximum) at which the region fills at most STAGE.fill of the view, never below
 * the minimum. A small control zooms more, a wide panel less. Returns 1 (stay on the full page) when even the minimum zoom would
 * not hold the region, so the target can never be pushed out of frame.
 */
export function zoomForBox(box, g) {
  const fit = Math.min((STAGE.fill * g.W) / Math.max(1, box.w), (STAGE.fill * g.H) / Math.max(1, box.h));
  if (fit < g.zoom.min) return 1;
  return Math.min(g.zoom.max, fit);
}

/** Camera that frames `box`. A lone control (`bias`) sits upper-left of centre so what it opens has room below and to the right. */
export function cameraForBox(box, g, { bias = false, zoom = null } = {}) {
  const z = zoom ?? zoomForBox(box, g);
  if (z <= 1) return wideCamera(g);
  const cx = box.x + box.w / 2 + (bias ? (0.5 - STAGE.bias.x) * (g.W / z) : 0);
  const cy = box.y + box.h / 2 + (bias ? (0.5 - STAGE.bias.y) * (g.H / z) : 0);
  return clampCamera({ cx, cy, z }, g);
}

// ------------------------------------------------------------------------------------------------ the camera spring

/** One axis of a critically damped spring toward `to`, from position x0 and speed v0, tau seconds after the move starts. */
export function springAxis(x0, v0, to, tau, omega = STAGE.omega) {
  if (tau <= 0) return { x: x0, v: v0 };
  const A = x0 - to, B = v0 + omega * A, e = Math.exp(-omega * tau);
  return { x: to + (A + B * tau) * e, v: (B - omega * (A + B * tau)) * e };
}

/**
 * Camera track: { initial, segments: [{ t0, to: { cx, cy, z } }] } with segments sorted by t0. A later segment retargets the spring
 * from the position and speed the earlier one has reached, so the motion stays continuous. Pure and deterministic.
 */
export function cameraAt(track, t, g) {
  let s = { cx: track.initial.cx, cy: track.initial.cy, z: track.initial.z, vx: 0, vy: 0, vz: 0 };
  const segs = track.segments || [];
  for (let i = 0; i < segs.length; i++) {
    const seg = segs[i];
    if (t < seg.t0) break;
    const end = i + 1 < segs.length ? Math.min(t, segs[i + 1].t0) : t;
    const tau = end - seg.t0;
    const x = springAxis(s.cx, s.vx, seg.to.cx, tau), y = springAxis(s.cy, s.vy, seg.to.cy, tau), z = springAxis(s.z, s.vz, seg.to.z, tau);
    s = { cx: x.x, cy: y.x, z: z.x, vx: x.v, vy: y.v, vz: z.v };
    if (end >= t) break;
  }
  const cam = clampCamera(s, g);
  return { ...cam, vx: s.vx, vy: s.vy, vz: s.vz };
}

/** On-screen speed of the view centre, in film px per second: what the motion blur keys on. */
export function cameraSpeed(cam) {
  return Math.hypot(cam.vx * cam.z, cam.vy * cam.z, cam.vz * 300);
}

// ------------------------------------------------------------------------------------------------ the cursor

// Cursor shapes as polygons in their own units, hotspot at the origin of `hot`. Black fill, white outline, soft shadow.
// The renderer draws them as SVG; the gate rasterises the same polygons to find the cursor in an encoded frame.
export const CURSOR_SHAPES = Object.freeze({
  arrow: { height: 19, hot: [0, 0], points: [[0, 0], [0, 16], [4.2, 12.3], [7, 19], [9.6, 17.9], [6.9, 11.4], [12, 11.4]] },
  hand: { height: 20, hot: [7, 0], points: [[7, 0], [8.4, 0.3], [9, 1.6], [9, 8], [10, 7.6], [11.4, 7.6], [12.5, 8.4], [13.4, 8.1], [14.8, 8.2], [15.7, 9], [16.6, 8.9], [17.8, 9.4], [18, 10.6], [18, 15], [17.2, 17.6], [15.4, 19.6], [13, 20], [9.4, 20], [7.4, 19.2], [6, 17.6], [1.8, 12.2], [1.4, 11], [2.4, 10.2], [3.6, 10.4], [6, 12.4], [5, 1.8], [5.6, 0.4]] },
  ibeam: { height: 16, hot: [6, 8], points: [[3, 0], [9, 0], [9, 1.6], [7, 1.6], [7, 14.4], [9, 14.4], [9, 16], [3, 16], [3, 14.4], [5, 14.4], [5, 1.6], [3, 1.6]] },
});

/** CSS `cursor` value -> the shape the stage draws. `auto` is an arrow except over an editable field (the capture resolves that). */
export function cursorKind(css) {
  const c = String(css || '').toLowerCase().split(',')[0].trim();
  if (c === 'pointer' || c === 'grab' || c === 'grabbing') return 'hand';
  if (c === 'text' || c === 'vertical-text') return 'ibeam';
  return 'arrow';
}

/** Screen height of the cursor for a camera zoom: 40 px on the full page, 58 px at the maximum zoom. */
export const cursorHeightFor = (z, g = { zoom: STAGE.zoom, unit: 1 }) => g.unit * lerp(STAGE.cursorHeight.wide, STAGE.cursorHeight.zoomed, clamp((z - 1) / (g.zoom.max - 1), 0, 1));

// Monotone cubic (Fritsch-Carlson) through the samples: it passes exactly through every recorded point, never overshoots between
// them, and has zero speed on a dwell. That is the "smoothed path through the recorded pointer positions".
function pchipSlopes(ts, vs) {
  const n = ts.length;
  const d = [], m = new Array(n).fill(0);
  for (let i = 0; i < n - 1; i++) d.push((vs[i + 1] - vs[i]) / (ts[i + 1] - ts[i]));
  if (n === 2) { m[0] = m[1] = d[0]; return m; }
  for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (2 * d[i - 1] * d[i]) / (d[i - 1] + d[i]);
  const end = (h0, h1, d0, d1) => { let v = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1); if (Math.sign(v) !== Math.sign(d0)) v = 0; else if (Math.sign(d0) !== Math.sign(d1) && Math.abs(v) > 3 * Math.abs(d0)) v = 3 * d0; return v; };
  m[0] = end(ts[1] - ts[0], ts[2] - ts[1], d[0], d[1]);
  m[n - 1] = end(ts[n - 1] - ts[n - 2], ts[n - 2] - ts[n - 3], d[n - 2], d[n - 3]);
  return m;
}

/** Cursor track from samples [{ t, x, y, kind }] (film seconds, stage px). Same-time samples keep the last. */
export function buildCursorTrack(samples) {
  const s = [];
  for (const p of [...samples].sort((a, b) => a.t - b.t)) {
    if (s.length && p.t - s[s.length - 1].t < 1e-4) s[s.length - 1] = p; else s.push(p);
  }
  const ts = s.map((p) => p.t);
  return { samples: s, ts, mx: s.length > 1 ? pchipSlopes(ts, s.map((p) => p.x)) : [0], my: s.length > 1 ? pchipSlopes(ts, s.map((p) => p.y)) : [0] };
}

function hermite(t0, t1, p0, p1, m0, m1, t) {
  const h = t1 - t0, u = (t - t0) / h, u2 = u * u, u3 = u2 * u;
  return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * h * m0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * h * m1;
}

/** How hidden the cursor is at t (0 shown, 1 hidden) given hide ranges [[from, to], ...]: a 0.2 s fade at each end. */
export function hideAlpha(ranges, t) {
  let a = 0;
  for (const [from, to] of ranges || []) {
    if (t < from - STAGE.hideFadeSeconds || t > to + STAGE.hideFadeSeconds) continue;
    a = Math.max(a, clamp(Math.min((t - (from - STAGE.hideFadeSeconds)) / STAGE.hideFadeSeconds, ((to + STAGE.hideFadeSeconds) - t) / STAGE.hideFadeSeconds), 0, 1));
  }
  return a;
}

/** Cursor position, shape and visibility at time t. Hidden before the first recorded pointer sample: nothing is invented. */
export function cursorAt(track, t, hidden = []) {
  const s = track.samples;
  if (!s.length) return null;
  const hide = hideAlpha(hidden, t);
  if (t < s[0].t) return { visible: 0, hidden: hide, x: s[0].x, y: s[0].y, kind: s[0].kind, vx: 0, vy: 0 };
  const visible = clamp((t - s[0].t) / 0.12, 0, 1);
  if (t >= s[s.length - 1].t) { const l = s[s.length - 1]; return { visible, hidden: hide, x: l.x, y: l.y, kind: l.kind, vx: 0, vy: 0 }; }
  let lo = 0, hi = s.length - 1;
  while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (s[mid].t <= t) lo = mid; else hi = mid; }
  const a = s[lo], b = s[hi];
  const x = hermite(a.t, b.t, a.x, b.x, track.mx[lo], track.mx[hi], t);
  const y = hermite(a.t, b.t, a.y, b.y, track.my[lo], track.my[hi], t);
  const e = 1e-3;
  const x2 = hermite(a.t, b.t, a.x, b.x, track.mx[lo], track.mx[hi], Math.min(b.t, t + e));
  const y2 = hermite(a.t, b.t, a.y, b.y, track.my[lo], track.my[hi], Math.min(b.t, t + e));
  return { visible, hidden: hide, x, y, kind: a.kind, vx: (x2 - x) / e, vy: (y2 - y) / e };
}

/** Press squash factor: 1 at rest, dips to STAGE.press.scale at the press and eases back. */
export function pressScale(clicks, t) {
  let scale = 1;
  for (const c of clicks) {
    const u = (t - c.t) / STAGE.press.seconds;
    if (u < 0 || u > 1) continue;
    const dip = u < 0.35 ? u / 0.35 : 1 - (u - 0.35) / 0.65;
    scale = Math.min(scale, 1 - (1 - STAGE.press.scale) * clamp(dip, 0, 1) ** 1.2);
  }
  return scale;
}

// ------------------------------------------------------------------------------------------------ film time <-> source time

/** Source seconds shown at `local` seconds into a slot (inverse of sync-lib clipToSlot). Freezes on the first frame during headHold and on the last after the edit ends. */
export function slotToSource(edit, local) {
  const sp = Number(edit.speed || 1);
  const t0 = Number(edit.trimStart || 0), t1 = Number(edit.trimEnd || edit.srcSeconds || 0);
  const keep = [];
  let cur = t0;
  for (const [a, b] of (edit.skip || []).slice().sort((x, y) => x[0] - y[0])) { if (a > cur) keep.push([cur, Math.min(a, t1)]); cur = Math.max(cur, b); }
  if (cur < t1) keep.push([cur, t1]);
  if (!keep.length) return t0;
  let rest = local - Number(edit.headHold || 0);
  if (rest <= 0) return keep[0][0];
  for (const [a, b] of keep) {
    const len = (b - a) / sp;
    if (rest <= len) return a + rest * sp;
    rest -= len;
  }
  return keep[keep.length - 1][1];
}

/** The slot a film time falls in (the last slot for any time past the end). */
export function slotAt(slots, t) {
  for (let i = slots.length - 1; i >= 0; i--) if (t >= slots[i].startSeconds - 1e-9) return slots[i];
  return slots[0];
}

/** Index of the last frame at or before source time ts (frames arrive only on change; the page looks the same until the next one). */
export function frameIndexAt(times, ts) {
  if (!times.length) return -1;
  let lo = 0, hi = times.length - 1;
  if (ts <= times[0]) return 0;
  while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (times[mid] <= ts + 1e-9) lo = mid; else hi = mid - 1; }
  return lo;
}

const tracks = new WeakMap();
const trackOf = (plan) => { let tr = tracks.get(plan.cursor); if (!tr) { tr = buildCursorTrack(plan.cursor.samples); tracks.set(plan.cursor, tr); } return tr; };

/** Everything the renderer and the gate need at film time t: slot, source time, source frame, camera, cursor, press scale. */
export function stateAt(plan, t) {
  const g = plan.geometry;
  const slot = slotAt(plan.slots, t);
  const srcT = slotToSource(slot.edit, t - slot.startSeconds);
  const f = plan.frames[slot.clipId];
  const frame = f ? f.files[frameIndexAt(f.times, srcT)] : null;
  const camera = cameraAt(plan.camera, t, g);
  const cursor = plan.cursor.samples.length ? cursorAt(trackOf(plan), t, plan.cursor.hidden) : null;
  return { t, slot, srcT, frame, camera, cursor, press: pressScale(plan.cursor.clicks, t) };
}
