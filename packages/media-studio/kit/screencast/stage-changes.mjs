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
    boxes.push({ x: x0 * cw / sx, y: y0 * ch / sy, w: (x1 - x0 + 1) * cw / sx, h: (y1 - y0 + 1) * ch / sy });
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
  return presses.map((t) => {
    const i0 = indexAt(t), i1 = indexAt(t + CHANGES.windowSeconds);
    if (i1 <= i0) return { t, boxes: [] };
    const picks = new Set([i1]);
    for (let s = 1; s < CHANGES.samples; s++) picks.add(Math.round(i0 + ((i1 - i0) * s) / CHANGES.samples));
    picks.delete(i0);
    const base = get(i0), all = [];
    for (const i of picks) all.push(...changedBoxes(base, get(i), viewport));
    return { t, boxes: mergeBoxes(all) };
  });
}
