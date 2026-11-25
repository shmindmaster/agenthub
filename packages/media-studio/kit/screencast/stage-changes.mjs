// Screen stage: what changed on the page after each press, measured from the captured frames (not guessed from the DOM).
// The plan frames the target box together with the pixels that changed within `windowSeconds` of the press, so a result that
// appears elsewhere (a menu, a total, a toast) is shown. Pure image work on small gray grids; no model, no network.
// Contract: skills/studio/references/screen-stage.md.
import { execFileSync } from 'node:child_process';

export const CHANGES = Object.freeze({ windowSeconds: 1.2, gridW: 320, gridH: 180, cellCss: 32, pixelDelta: 14, cellFill: 0.1, minCells: 2, samples: 7 });

/** Gray 320x180 raster of one frame file (JPEG) as a Uint8Array. */
export function grayGrid(file, w = CHANGES.gridW, h = CHANGES.gridH) {
  const buf = execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', file, '-vf', `scale=${w}:${h}:flags=area,format=gray`, '-frames:v', '1', '-f', 'rawvideo', '-'], { maxBuffer: 1 << 26 });
  if (buf.length !== w * h) throw new Error(`stage changes: ${file} decoded to ${buf.length} bytes, expected ${w * h}`);
  return new Uint8Array(buf.buffer, buf.byteOffset, buf.length);
}

/**
 * Boxes (CSS px) of the regions that differ between two gray grids. A cell is "changed" when enough of its pixels moved by more than
 * `pixelDelta`; changed cells join through their 8 neighbours; a component smaller than `minCells` (a caret, an antialiasing flicker) is dropped.
 */
export function changedBoxes(a, b, viewport, { gridW = CHANGES.gridW, gridH = CHANGES.gridH } = {}) {
  const sx = gridW / viewport.width, sy = gridH / viewport.height;
  const cw = Math.max(1, Math.round(CHANGES.cellCss * sx)), ch = Math.max(1, Math.round(CHANGES.cellCss * sy));
  const cols = Math.ceil(gridW / cw), rows = Math.ceil(gridH / ch);
  const hit = new Uint8Array(cols * rows);
  for (let cy = 0; cy < rows; cy++) for (let cx = 0; cx < cols; cx++) {
    let n = 0, tot = 0;
    for (let y = cy * ch; y < Math.min(gridH, (cy + 1) * ch); y++) for (let x = cx * cw; x < Math.min(gridW, (cx + 1) * cw); x++) { tot++; if (Math.abs(a[y * gridW + x] - b[y * gridW + x]) > CHANGES.pixelDelta) n++; }
    if (tot && n / tot >= CHANGES.cellFill) hit[cy * cols + cx] = 1;
  }
  const seen = new Uint8Array(cols * rows), boxes = [];
  for (let i = 0; i < hit.length; i++) {
    if (!hit[i] || seen[i]) continue;
    const stack = [i]; seen[i] = 1; let n = 0, x0 = cols, y0 = rows, x1 = -1, y1 = -1;
    while (stack.length) {
      const j = stack.pop(), x = j % cols, y = (j - x) / cols; n++;
      x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const nx = x + dx, ny = y + dy; if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
        const k = ny * cols + nx; if (hit[k] && !seen[k]) { seen[k] = 1; stack.push(k); }
      }
    }
    if (n < CHANGES.minCells) continue;
    // the last row or column of cells may run past the page: clamp to it
    const bx = x0 * cw / sx, by = y0 * ch / sy;
    boxes.push({ x: bx, y: by, w: Math.min(viewport.width, (x1 + 1) * cw / sx) - bx, h: Math.min(viewport.height, (y1 + 1) * ch / sy) - by });
  }
  return boxes;
}

/** Union of box lists, merging boxes that touch or overlap, so one result is one box. */
export function mergeBoxes(list, gap = 24) {
  const out = list.map((b) => ({ ...b }));
  for (let again = true; again;) {
    again = false;
    for (let i = 0; i < out.length && !again; i++) for (let j = i + 1; j < out.length && !again; j++) {
      const a = out[i], b = out[j];
      if (a.x <= b.x + b.w + gap && b.x <= a.x + a.w + gap && a.y <= b.y + b.h + gap && b.y <= a.y + a.h + gap) {
        const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
        out[i] = { x, y, w: Math.max(a.x + a.w, b.x + b.w) - x, h: Math.max(a.y + a.h, b.y + b.h) - y };
        out.splice(j, 1); again = true;
      }
    }
  }
  return out.map((b) => ({ x: Math.round(b.x * 10) / 10, y: Math.round(b.y * 10) / 10, w: Math.round(b.w * 10) / 10, h: Math.round(b.h * 10) / 10 }));
}

/**
 * For each press time (clip clock) the boxes that changed between the frame on screen at the press and the frames up to
 * `windowSeconds` later. `frames` is { times, files } with absolute file paths. Returns [{ t, boxes }].
 */
export function measureChanges({ presses, frames, viewport, grid = grayGrid }) {
  const cache = new Map();
  const get = (i) => { if (!cache.has(i)) cache.set(i, grid(frames.files[i])); return cache.get(i); };
  const indexAt = (t) => { let k = 0; for (let i = 0; i < frames.times.length; i++) { if (frames.times[i] <= t + 1e-6) k = i; else break; } return k; };
  const order = [...presses].sort((a, b) => a - b);
  return presses.map((t) => {
    // the window ends where the next press begins: what the next press does is its own result
    const next = order.find((x) => x > t + 0.05);
    const end = next === undefined ? t + CHANGES.windowSeconds : Math.max(t + 0.15, Math.min(t + CHANGES.windowSeconds, next - 0.05));
    const i0 = indexAt(t), i1 = indexAt(end);
    if (i1 <= i0) return { t, boxes: [] };
    const picks = new Set([i1]);
    for (let s = 1; s < CHANGES.samples; s++) picks.add(Math.round(i0 + ((i1 - i0) * s) / CHANGES.samples));
    picks.delete(i0);
    const base = get(i0), all = [];
    for (const i of picks) all.push(...changedBoxes(base, get(i), viewport));
    return { t, boxes: mergeBoxes(all) };
  });
}

/**
 * Typing at 2x: for each typing burst of at least `minSeconds`, the span that may play faster. It runs from the start of the burst to
 * 0.4 s before its end (the last words land at real speed), and stops early at the first change outside the typed field
 * (an autocomplete list, a spinner, a validation message): those play at real speed. Spans keep the 0.15 s ramps of sync-lib.
 * `frames` is { times, files } (absolute files); `actions` the receipt events on the clip clock.
 */
export function typingSpans({ actions, frames, viewport, speed = 2, minSeconds = 1.0, tailSeconds = 0.4, grid = grayGrid }) {
  const out = [];
  const S = Math.min(3, Math.max(1, Number(speed) || 1));
  if (S <= 1) return out;
  for (const a of actions || []) {
    if (a.type !== 'type' && a.type !== 'fill') continue;
    const t0 = a.tStart ?? a.t, t1 = a.tEnd;
    if (!Number.isFinite(t0) || !Number.isFinite(t1) || t1 - t0 < minSeconds) continue;
    let end = t1 - tailSeconds;
    const field = a.targetBox ? { x: a.targetBox.x - 24, y: a.targetBox.y - 24, w: a.targetBox.w + 48, h: a.targetBox.h + 48 } : null;
    const idx = (t) => { let k = 0; for (let i = 0; i < frames.times.length; i++) { if (frames.times[i] <= t + 1e-6) k = i; else break; } return k; };
    let prev = grid(frames.files[idx(t0)]);
    for (let t = t0 + 0.1; t <= t1 + 1e-6 && field; t += 0.1) {
      const cur = grid(frames.files[idx(t)]);
      const outside = changedBoxes(prev, cur, viewport).filter((b) => b.x < field.x || b.y < field.y || b.x + b.w > field.x + field.w || b.y + b.h > field.y + field.h);
      if (outside.length) { end = Math.min(end, t - 0.2); break; }
      prev = cur;
    }
    if (end - t0 >= 0.4) out.push({ from: Math.round(t0 * 1000) / 1000, to: Math.round(end * 1000) / 1000, speed: S, reason: 'typing' });
  }
  return out;
}
