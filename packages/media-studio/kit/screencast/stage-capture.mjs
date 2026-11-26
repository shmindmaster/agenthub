// Screen stage capture: the real page as high-resolution frames with their real timestamps, through the Chrome DevTools screencast
// (Page.startScreencast). Frames arrive only when the page changes; the stage synthesises the cursor and the camera at 60 fps, so a
// still page costs no frames. No recordVideo: nothing here is a lossy WebM. Headless. Contract: skills/studio/references/screen-stage.md.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

/**
 * Start capturing `page`. `size` is the physical frame size (CSS viewport x deviceScaleFactor). Frame times are seconds since `t0`
 * (the recorder's clock origin); `arm()` marks the moment the product is ready, and the clip clock starts there, so the blank page
 * before the first navigation is never in the clip.
 */
export async function startStageCapture(context, page, { dir, size, t0, quality = 92 }) {
  fs.mkdirSync(dir, { recursive: true });
  const cdp = await context.newCDPSession(page);
  const frames = [];
  const writes = [];
  let n = 0, armedAt = null, stopped = false, dims = null;
  cdp.on('Page.screencastFrame', (ev) => {
    if (stopped) return;
    const t = ev.metadata?.timestamp ? ev.metadata.timestamp * 1000 - t0 : Date.now() - t0;
    const file = `f${String(++n).padStart(6, '0')}.jpg`;
    const buf = Buffer.from(ev.data, 'base64');
    if (!dims) dims = jpegSize(buf);
    frames.push({ t: t / 1000, file, bytes: buf.length, sha256: sha256(buf) });
    writes.push(fs.promises.writeFile(path.join(dir, file), buf));
    cdp.send('Page.screencastFrameAck', { sessionId: ev.sessionId }).catch(() => {});
  });
  await cdp.send('Page.startScreencast', { format: 'jpeg', quality, maxWidth: size.width, maxHeight: size.height, everyNthFrame: 1 });
  return {
    arm() { if (armedAt === null) armedAt = (Date.now() - t0) / 1000; },
    get origin() { return armedAt ?? 0; },
    /** Stop, flush, and return { origin, frames, endSeconds }: frame times and `endSeconds` on the clip clock (origin = arm time). */
    async stop() {
      stopped = true;
      try { await cdp.send('Page.stopScreencast'); } catch { /* page already closed */ }
      await Promise.all(writes);
      const origin = armedAt ?? 0;
      const endSeconds = (Date.now() - t0) / 1000 - origin;
      // The frame on screen at the origin is the first frame of the clip; earlier ones are the blank page and are dropped.
      let keepFrom = 0;
      frames.forEach((f, i) => { if (f.t <= origin + 1e-3) keepFrom = i; });
      const kept = frames.slice(keepFrom).map((f, i) => ({ ...f, t: i === 0 ? 0 : Number(Math.max(0, f.t - origin).toFixed(4)) }));
      for (const f of frames.slice(0, keepFrom)) fs.rmSync(path.join(dir, f.file), { force: true });
      return { origin, frames: kept, endSeconds: Number(endSeconds.toFixed(3)), frameSize: dims };
    },
  };
}

/** Width and height of a JPEG (its SOF marker). */
export function jpegSize(buf) {
  let i = 2;
  while (i + 9 < buf.length) {
    if (buf[i] !== 0xff) { i++; continue; }
    const m = buf[i + 1];
    if (m >= 0xc0 && m <= 0xc3) return { height: buf.readUInt16BE(i + 5), width: buf.readUInt16BE(i + 7) };
    i += 2 + buf.readUInt16BE(i + 2);
  }
  return null;
}

/** The per-take frames record written beside the frames: the receipt binds its hash. */
export function frameIndex({ id, size, deviceScaleFactor, viewport, stop }) {
  return { schema: 'media-studio/screen-stage-frames/1', clip: id, format: 'jpeg', width: size.width, height: size.height, viewport, deviceScaleFactor, origin: stop.origin, endSeconds: stop.endSeconds, frames: stop.frames };
}

/** Shift recorder-clock event times onto the clip clock (events before the origin clamp to 0). */
export function shiftEvents(events, expectations, beats, origin) {
  const s = (v) => (Number.isFinite(v) ? Number(Math.max(0, v - origin).toFixed(4)) : v);
  return {
    events: events.map((e) => ({ ...e, t: s(e.t), ...(e.tStart !== undefined ? { tStart: s(e.tStart) } : {}), ...(e.tEnd !== undefined ? { tEnd: s(e.tEnd) } : {}) })),
    expectations: expectations.map((e) => ({ ...e, at: s(e.at), observedAt: s(e.observedAt) })),
    beats: beats.map((b) => ({ ...b, approxStartSeconds: s(b.approxStartSeconds) })),
  };
}

/** The CSS cursor under a point, resolved the way the stage draws it: `auto` is an arrow except over an editable field. Runs in the page. */
export const readCursorInPage = ([x, y]) => {
  const el = document.elementFromPoint(x, y);
  if (!el) return 'default';
  const c = getComputedStyle(el).cursor;
  if (c !== 'auto') return c;
  const editable = el.closest('input:not([type=button]):not([type=submit]):not([type=checkbox]):not([type=radio]):not([type=range]):not([type=color]),textarea,[contenteditable=""],[contenteditable="true"]');
  return editable ? 'text' : 'default';
};
