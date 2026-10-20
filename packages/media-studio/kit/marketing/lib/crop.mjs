// Ratio crop math and focus-follow windows. The compositor crops the receipt-bound UI clip to a region whose aspect
// equals the UI band of the delivery frame, centered on what the voice is talking about (the pointer / an explicit
// focus), so the UI stays readable in 4:5 and 9:16 instead of letterboxed.
import { clamp, round } from './util.mjs';

/**
 * Largest rectangle of the band's aspect inside the source, shrunk by `zoom`, centered on `focus` (normalized 0-1)
 * and clamped inside the source. Returns the normalized sourceRegion (campaign-contract shape) plus the px scale
 * the region is drawn at, so callers can reject unreadable crops.
 */
export function bandRegion({ srcW, srcH, band, focus = { x: 0.5, y: 0.5 }, zoom = 1 }) {
  if (!(srcW > 0 && srcH > 0 && band?.w > 0 && band?.h > 0)) throw new Error('bandRegion needs positive source and band sizes');
  if (!(zoom >= 1)) throw new Error('zoom must be >= 1');
  const aspect = band.w / band.h;
  let rw;
  let rh;
  if (aspect >= srcW / srcH) { rw = srcW; rh = srcW / aspect; } else { rh = srcH; rw = srcH * aspect; }
  rw /= zoom;
  rh /= zoom;
  const x0 = clamp(focus.x * srcW - rw / 2, 0, srcW - rw);
  const y0 = clamp(focus.y * srcH - rh / 2, 0, srcH - rh);
  const region = { x: round(x0 / srcW, 4), y: round(y0 / srcH, 4), width: round(rw / srcW, 4), height: round(rh / srcH, 4) };
  return { region, scale: round(band.w / rw, 3), regionPx: { x: Math.round(x0), y: Math.round(y0), w: Math.round(rw), h: Math.round(rh) } };
}

export const MAX_SCALE = 3;

/** The crop is only readable if source text is not magnified past 3x (soft) nor shrunk below 0.9x (tiny). */
export function readability(scale) {
  if (scale > MAX_SCALE) return { ok: false, reason: `crop magnifies the capture ${scale}x; recapture at a larger viewport` };
  if (scale < 0.9) return { ok: false, reason: `crop shrinks the capture to ${scale}x; text will not read on a phone` };
  return { ok: true };
}

const key = (a) => (a.type === 'point' || a.type === 'click' || a.type === 'type' ? 2 : a.type === 'move' ? 1 : 0);

/**
 * Pointer / click track from a capture receipt action log, in clip seconds (Recast trims the blank lead-in off the
 * head, so an event at t plays at t - headTrim), with positions normalized to the capture viewport.
 */
export function pointerTrack(actions, { headTrim = 0, viewport }) {
  const out = [];
  for (const a of actions || []) {
    if (!key(a) || !Number.isFinite(a.x) || !Number.isFinite(a.y)) continue;
    out.push({ t: round(a.t - headTrim, 3), x: clamp(a.x / viewport.width, 0, 1), y: clamp(a.y / viewport.height, 0, 1), strong: key(a) === 2, label: a.label || null });
  }
  return out.filter((p) => p.t >= -0.05).sort((p, q) => p.t - q.t);
}

/** Focus point at clip time `t`: the latest strong event within `hold` seconds, else the latest pointer move. */
export function focusAt(track, t, hold = 1.8) {
  let strong = null;
  let any = null;
  for (const p of track) {
    if (p.t > t + 1e-6) break;
    any = p;
    if (p.strong && t - p.t <= hold) strong = p;
  }
  const p = strong || any;
  return p ? { x: p.x, y: p.y } : { x: 0.5, y: 0.5 };
}

/**
 * Focus windows for one beat, in CLIP seconds over [clipStart, clipEnd]. Explicit `ui.focus` windows win (they tile the
 * span: gaps are absorbed by the neighbors). Otherwise the pointer track is sampled and consecutive samples whose focus
 * stays within `moveThreshold` merge; windows shorter than `minWindowSeconds` merge into the previous, and at most
 * `maxWindows` remain. The camera never cuts: the compositor eases between windows.
 */
export function focusWindows({ explicit, track, clipStart, clipEnd, srcW, srcH, band, zoom, minWindowSeconds = 1.2, maxWindows = 3, moveThreshold = 0.18, step = 0.25, maxScale = MAX_SCALE }) {
  const span = clipEnd - clipStart;
  if (!(span > 0)) throw new Error('focusWindows needs clipEnd > clipStart');
  let raw;
  if (explicit?.length) {
    // Windows written for another part of the clip (an aligned trim moved the beat) drop out; the neighbors absorb the gap.
    const sorted = [...explicit].filter((w) => w.endSec > clipStart + 1e-6 && w.startSec < clipEnd - 1e-6).sort((a, b) => a.startSec - b.startSec).map((w) => ({ ...w }));
    if (!sorted.length) {
      const nearest = [...explicit].sort((a, b) => Math.abs(a.startSec - clipStart) - Math.abs(b.startSec - clipStart))[0];
      sorted.push({ ...nearest, startSec: clipStart, endSec: clipEnd });
    }
    sorted[0].startSec = Math.min(sorted[0].startSec, clipStart);
    sorted[sorted.length - 1].endSec = Math.max(sorted[sorted.length - 1].endSec, clipEnd);
    for (let i = 1; i < sorted.length; i++) sorted[i - 1].endSec = sorted[i].startSec;
    raw = sorted.map((w) => ({ start: Math.max(w.startSec, clipStart), end: Math.min(w.endSec, clipEnd), x: w.x, y: w.y, zoom: w.zoom || zoom, sourceZoom: w.sourceZoom || 1, label: w.label || null }));
  } else {
    const samples = [];
    for (let t = clipStart; t < clipEnd - 1e-6; t += step) samples.push({ t, ...focusAt(track || [], t) });
    raw = [];
    for (const s of samples) {
      const last = raw[raw.length - 1];
      if (last && Math.hypot(last.x - s.x, last.y - s.y) <= moveThreshold) { last.end = s.t + step; last.xs.push(s.x); last.ys.push(s.y); }
      else raw.push({ start: s.t, end: s.t + step, x: s.x, y: s.y, xs: [s.x], ys: [s.y], zoom, sourceZoom: 1, label: null });
    }
    for (const w of raw) { w.x = w.xs.reduce((a, b) => a + b, 0) / w.xs.length; w.y = w.ys.reduce((a, b) => a + b, 0) / w.ys.length; delete w.xs; delete w.ys; }
    for (let i = 1; i < raw.length;) { if (raw[i].end - raw[i].start < minWindowSeconds) { raw[i - 1].end = raw[i].end; raw.splice(i, 1); } else i++; }
    if (raw.length > 1 && raw[0].end - raw[0].start < minWindowSeconds) { raw[1].start = raw[0].start; raw.shift(); }
    while (raw.length > maxWindows) {
      let shortest = 0;
      for (let i = 1; i < raw.length; i++) if (raw[i].end - raw[i].start < raw[shortest].end - raw[shortest].start) shortest = i;
      const into = shortest === 0 ? 1 : shortest - 1;
      raw[into].start = Math.min(raw[into].start, raw[shortest].start);
      raw[into].end = Math.max(raw[into].end, raw[shortest].end);
      raw.splice(shortest, 1);
    }
    if (raw.length) { raw[0].start = clipStart; raw[raw.length - 1].end = clipEnd; }
  }
  return raw.map((w) => {
    // A window that is already magnified by a Recast punch-in (sourceZoom) gets a wider crop, so the text is never
    // magnified past the readability cap; the crop never goes below zoom 1 (readability() fails if even that is too much).
    const base = bandRegion({ srcW, srcH, band, focus: { x: w.x, y: w.y }, zoom: 1 }).scale * w.sourceZoom;
    const effective = base * w.zoom > maxScale ? Math.max(1, Math.min(w.zoom, maxScale / base)) : w.zoom;
    const { region, scale } = bandRegion({ srcW, srcH, band, focus: { x: w.x, y: w.y }, zoom: effective });
    w.zoom = round(effective, 3);
    return { startSec: round(w.start, 3), endSec: round(w.end, 3), focus: { x: round(w.x, 4), y: round(w.y, 4) }, zoom: w.zoom, sourceZoom: w.sourceZoom, label: w.label, region, scale: round(scale * w.sourceZoom, 3) };
  });
}

/** The window active at clip time t (the one the picture gate samples at the beat midpoint). */
export function windowAt(windows, t) {
  return windows.find((w) => t >= w.startSec && t < w.endSec) || windows[windows.length - 1];
}

/**
 * Camera keyframes for the MarketingAd composition, in seconds from the beat start. Each window holds its region;
 * the camera eases to the next window's region across `ease` seconds centered on the boundary, so it never cuts.
 * Windows are in clip seconds; `clipStart` is the clip time that plays at the beat start.
 */
export function cameraKeyframes(windows, { clipStart = 0, duration, ease = 0.5 }) {
  if (!windows.length) throw new Error('cameraKeyframes needs at least one window');
  const times = [];
  const x = [];
  const y = [];
  const w = [];
  const h = [];
  const push = (t, r) => {
    let tt = round(Math.min(Math.max(t, 0), duration), 3);
    if (times.length && tt <= times[times.length - 1]) tt = round(times[times.length - 1] + 0.001, 3);
    times.push(tt); x.push(r.x); y.push(r.y); w.push(r.width); h.push(r.height);
  };
  windows.forEach((win, i) => {
    const start = win.startSec - clipStart;
    const end = win.endSec - clipStart;
    const last = i === windows.length - 1;
    push(i === 0 ? 0 : start + ease / 2, win.region);
    push(last ? duration : Math.max(start + ease / 2 + 0.002, end - ease / 2), win.region);
  });
  return { times, x, y, w, h };
}
