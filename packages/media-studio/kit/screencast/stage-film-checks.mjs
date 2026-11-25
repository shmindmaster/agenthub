// Screen stage: pure image checks on decoded film frames, shared by the encoded-film gate and the tests. No ffmpeg, no filesystem.
// They exist because core-v1 failed in ways the camera registration cannot see: a colour cast and a coil of copies during moves,
// a faded opening, and results out of frame. Each check is built to fail on those pictures. Contract: skills/studio/references/screen-stage.md.

/** Camera-warped bilinear sample of a gray raster `src` (EW x EH, stage/2 px) at screen px (u, v): stage point -> source. */
export function warpSample(src, EW, EH, W, H, c, u, v) {
  const sc = EW / W;
  const x = ((u / sc - W / 2) / c.z + c.cx) * sc, y = ((v / sc - H / 2) / c.z + c.cy) * sc;
  if (x < 0 || y < 0 || x >= EW - 1 || y >= EH - 1) return null;
  const x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0, i = y0 * EW + x0;
  return (src[i] * (1 - fx) + src[i + 1] * fx) * (1 - fy) + (src[i + EW] * (1 - fx) + src[i + EW + 1] * fx) * fy;
}

/** The ideal motion-blurred frame: the source warped at many times across the shutter and averaged (what a perfect blur gives). Raster ew x eh. */
export function idealBlur(src, EW, EH, W, H, cams, ew, eh) {
  const out = new Float32Array(ew * eh);
  for (let v = 0; v < eh; v++) for (let u = 0; u < ew; u++) {
    let s = 0, n = 0;
    for (const c of cams) { const a = warpSample(src, EW, EH, W, H, c, ((u + 0.5) * EW) / ew, ((v + 0.5) * EH) / eh); if (a !== null && Number.isFinite(a)) { s += a; n++; } }
    out[v * ew + u] = n ? s / n : NaN;
  }
  return out;
}

/** Squares of side `side` (px) in a gray raster whose standard deviation is under `maxStd`; returns centres, flattest first. */
export function flatBlocks(gray, w, h, side, maxStd = 1.5, step = 8) {
  const out = [];
  for (let y = 0; y + side <= h; y += step) for (let x = 0; x + side <= w; x += step) {
    let s = 0, ss = 0, n = 0;
    for (let j = 0; j < side; j += 2) for (let i = 0; i < side; i += 2) { const a = gray[(y + j) * w + x + i]; s += a; ss += a * a; n++; }
    const std = Math.sqrt(Math.max(0, ss / n - (s / n) ** 2));
    if (std <= maxStd) out.push({ cx: x + side / 2, cy: y + side / 2, std });
  }
  return out.sort((a, b) => a.std - b.std);
}

/** Pick up to n blocks at least `apart` px from each other. */
export function spread(blocks, n, apart) {
  const out = [];
  for (const b of blocks) if (out.length < n && out.every((o) => Math.hypot(o.cx - b.cx, o.cy - b.cy) >= apart)) out.push(b);
  return out;
}

/** Mean of an RGB raster (interleaved rgb24) in a (2r+1)^2 window around (cx, cy); null when the window leaves the raster. */
export function patchMean(rgb, w, h, cx, cy, r) {
  const m = [0, 0, 0]; let n = 0;
  for (let y = Math.round(cy) - r; y <= Math.round(cy) + r; y++) for (let x = Math.round(cx) - r; x <= Math.round(cx) + r; x++) {
    if (x < 0 || y < 0 || x >= w || y >= h) return null;
    const i = (y * w + x) * 3; m[0] += rgb[i]; m[1] += rgb[i + 1]; m[2] += rgb[i + 2]; n++;
  }
  return m.map((v) => v / n);
}

const median3 = (a, b, c) => [a, b, c].sort((x, y) => x - y)[1];

/** Worst per-channel difference (0-255 scale) of the median over three patches between a moving frame and the hold, or null when unmeasurable. */
export function colourShift(moving, hold) {
  const ok = moving.map((m, i) => (m && hold[i] ? i : -1)).filter((i) => i >= 0);
  if (ok.length < 3) return null;
  const d = [0, 1, 2].map((ch) => median3(...ok.slice(0, 3).map((i) => moving[i][ch] - hold[i][ch])));
  return Math.max(...d.map(Math.abs));
}

/** High-pass (value minus a 5x5 box mean) of a gray raster; the 2 px border is left at 0. */
export function highpass(g, w, h) {
  const out = new Float32Array(w * h);
  const r = 2;
  for (let y = r; y < h - r; y++) for (let x = r; x < w - r; x++) {
    let s = 0;
    for (let j = -r; j <= r; j++) for (let i = -r; i <= r; i++) s += g[(y + j) * w + x + i];
    out[y * w + x] = g[y * w + x] - s / ((2 * r + 1) ** 2);
  }
  return out;
}

/** Normalised autocorrelation of a raster along unit direction (dx, dy) at integer lag L (nearest-pixel shift). */
export function autocorr(a, w, h, dx, dy, L) {
  const ox = Math.round(dx * L), oy = Math.round(dy * L);
  let n = 0, sab = 0, saa = 0, sbb = 0;
  for (let y = 4; y < h - 4; y++) for (let x = 4; x < w - 4; x++) {
    const x2 = x + ox, y2 = y + oy;
    if (x2 < 4 || y2 < 4 || x2 >= w - 4 || y2 >= h - 4) continue;
    const p = a[y * w + x], q = a[y2 * w + x2];
    sab += p * q; saa += p * p; sbb += q * q; n++;
  }
  return n && saa > 0 && sbb > 0 ? sab / Math.sqrt(saa * sbb) : 0;
}

/**
 * How much more repeated structure the film frame has along the motion direction than the ideal blur: the largest autocorrelation
 * excess over lags 2..maxLag. Discrete copies of the page (a coil of ghosts) repeat at the copy spacing; a true blur does not.
 * `film` and `ideal` are gray rasters of the same size. Returns { excess, lag }.
 */
export function ghostExcess(film, ideal, w, h, dir, maxLag) {
  const fh = highpass(film, w, h), ih = highpass(ideal, w, h);
  const n = Math.hypot(dir.x, dir.y) || 1, dx = dir.x / n, dy = dir.y / n;
  let best = { excess: -1, lag: 0 };
  for (let L = 2; L <= maxLag; L++) {
    const e = autocorr(fh, w, h, dx, dy, L) - autocorr(ih, w, h, dx, dy, L);
    if (e > best.excess) best = { excess: e, lag: L };
  }
  return best;
}

/** Mean luma of a gray raster. */
export const meanLuma = (g) => { let s = 0; for (let i = 0; i < g.length; i++) s += g[i]; return s / g.length; };

/** Runs of consecutive frames with (almost) no pixel change: [{ from, to }] frame indices. A frame "changes" when more than `minPx` pixels differ by over `delta`. */
export function stillRuns(frames, delta = 8, minPx = 6) {
  const runs = []; let start = null;
  for (let i = 1; i < frames.length; i++) {
    let n = 0; const a = frames[i - 1], b = frames[i];
    for (let k = 0; k < a.length; k++) if (Math.abs(a[k] - b[k]) > delta && ++n > minPx) break;
    if (n <= minPx) { if (start === null) start = i - 1; } else if (start !== null) { runs.push({ from: start, to: i - 1 }); start = null; }
  }
  if (start !== null) runs.push({ from: start, to: frames.length - 1 });
  return runs;
}

/** Frame rate of a capture's animation bursts: consecutive frames closer than `burstGapMs` belong to one burst; the median gap is the unique fps, the 95th percentile the floor. */
export function captureRate(times, burstGapMs = 50) {
  const gaps = [];
  for (let i = 1; i < times.length; i++) { const g = (times[i] - times[i - 1]) * 1000; if (g <= burstGapMs) gaps.push(g); }
  gaps.sort((a, b) => a - b);
  const pick = (q) => (gaps.length ? gaps[Math.min(gaps.length - 1, Math.floor(q * gaps.length))] : NaN);
  return { frames: times.length, burstGaps: gaps.length, medianGapMs: pick(0.5), p95GapMs: pick(0.95), uniqueFps: gaps.length ? 1000 / pick(0.5) : NaN, floorFps: gaps.length ? 1000 / pick(0.95) : NaN };
}

/** The ideal blur of a crop at full stage resolution: crop (x0, y0, w, h) in stage px; `src` is the source in stage space at W x H. */
export function idealBlurCrop(src, W, H, cams, x0, y0, w, h) {
  const out = new Float32Array(w * h);
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    let s = 0, n = 0;
    for (const c of cams) { const a = warpSample(src, W, H, W, H, c, x0 + i + 0.5, y0 + j + 0.5); if (a !== null && Number.isFinite(a)) { s += a; n++; } }
    out[j * w + i] = n ? s / n : NaN;
  }
  return out;
}

/** The w x h window of a gray raster (W wide) with the most high-pass energy on a coarse grid: where text is. Returns { x0, y0 }. */
export function busiestWindow(gray, W, H, w, h, step = 60) {
  const hp = highpass(Float32Array.from(gray), W, H);
  let best = { e: -1, x0: 0, y0: 0 };
  for (let y0 = 8; y0 + h <= H - 8; y0 += step) for (let x0 = 8; x0 + w <= W - 8; x0 += step) {
    let e = 0;
    for (let j = 0; j < h; j += 3) for (let i = 0; i < w; i += 3) e += hp[(y0 + j) * W + x0 + i] ** 2;
    if (e > best.e) best = { e, x0, y0 };
  }
  return best;
}
