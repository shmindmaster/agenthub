// Product-neutral Playwright recording library for media-studio screencasts.
// Contract: skills/media-studio/references/product-picture.md. Timing: PDS killer-demo production guide
// (eased pointer 400–600 ms, settle ≥250 ms, click pulse 300–400 ms via Recast, result hold ≥500 ms).
//
// Every pointer move, click, keystroke, wheel and expectation that a scene script performs through the
// helpers below is logged with a timestamp relative to the recording start. record-job.mjs writes that
// log into capture/receipt.json, hash-bound to the finished clip, and validate-product-picture.mjs
// refuses any screen beat whose clip has no receipt, no pointer motion, or an unobserved expectation.
// That is what makes a stills animation, a looped PNG, or a hand-typed manifest unable to pass as
// product footage: none of them can produce a receipt from a live browser session.
// playwright is loaded inside startRecording, so the helpers below (bindHelpers, EventLog, resolveDevice) import and unit-test without a browser install.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

export const TIMING = Object.freeze({
  pointerMoveMsMin: 400,
  pointerMoveMsMax: 600,
  clickSettleMs: 250,
  clickHoldMs: 500,
  typingDelayMs: 55,
  scrollStepDelayMs: 220,
  expectTimeoutMs: 15000,
});

const easeInOutCubic = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const describe = (locator) => { try { return String(locator).replace(/s+/g, ' ').slice(0, 120); } catch { return null; } };

export class BeatTracker {
  constructor(t0) { this.t0 = t0; this.marks = []; }
  now() { return Math.round(((Date.now() - this.t0) / 1000) * 100) / 100; }
  mark(label, extra = {}) {
    const at = this.now();
    this.marks.push({ label, approxStartSeconds: at, ...extra });
    console.log('  beat:', label, '@', at + 's');
    return at;
  }
  toJSON() { return this.marks; }
}

export class EventLog {
  constructor(t0) { this.t0 = t0; this.events = []; this.expectations = []; this.pointer = { x: null, y: null }; }
  now() { return Math.round(((Date.now() - this.t0) / 1000) * 1000) / 1000; }
  push(type, data = {}) { const ev = { t: this.now(), type, ...data }; this.events.push(ev); return ev; }
  summary() {
    const count = (type) => this.events.filter((e) => e.type === type).length;
    return {
      pointerMoves: count('move'),
      clicks: count('click'),
      taps: count('tap'),
      uploads: count('upload'),
      keystrokes: this.events.filter((e) => e.type === 'type').reduce((n, e) => n + (e.chars || 0), 0),
      scrolls: count('wheel'),
      navigations: count('goto'),
      expectations: this.expectations.length,
      expectationsObserved: this.expectations.filter((e) => e.observed).length,
      expectationsFailed: this.expectations.filter((e) => !e.observed).map((e) => e.label),
    };
  }
}

/**
 * The Playwright device descriptor named by opts.device (e.g. 'iPhone 13'), or null when none is named. A name Playwright does not
 * know is an error: a non-16:9 cut is captured at its own viewport with device emulation, never silently as a desktop page.
 */
export function resolveDevice(opts, devices) {
  if (!opts.device) return null;
  const d = devices?.[opts.device];
  if (!d) throw new Error('unknown Playwright device "' + opts.device + '" (options.viewports[...].device)');
  return d;
}

/** Start a fresh recording context. viewport is the delivery frame; DSF 2 is the PDS minimum. opts.device spreads a Playwright device descriptor first; explicit viewport / DSF / isMobile / hasTouch win. opts.videoSize (default: viewport) is the recorded pixel size; record-job passes viewport x DSF for a --ratio entry whose CSS viewport is smaller than its delivery frame. */
export async function startRecording(id, opts = {}) {
  const { chromium, devices } = await import('playwright');
  const device = resolveDevice(opts, devices);
  const viewport = opts.viewport || device?.viewport || { width: 1600, height: 1000 };
  const rawDir = path.resolve(opts.rawRoot || 'raw', id);
  fs.rmSync(rawDir, { recursive: true, force: true });
  fs.mkdirSync(rawDir, { recursive: true });
  const browser = await chromium.launch({ headless: opts.headless !== false, args: ['--hide-scrollbars=false'] });
  // Playwright records video at CSS-pixel size whatever the device scale, so a phone or tablet layout recorded the
  // ordinary way comes out at 360-540 px and has to be upscaled. opts.mobileLayout = { cssWidth, scale } instead opens a
  // mobile context the size of the delivery frame and sets the page's viewport meta to cssWidth at that page scale: the
  // app lays out at its phone/tablet breakpoint and is rasterised at `scale`, so the recording is the native layout at
  // one recorded pixel per output pixel. Runtime-only; the product's own markup is untouched.
  const mobile = opts.mobileLayout || null;
  const context = await browser.newContext({
    ...(device || {}),
    viewport,
    // mobileLayout (native-resolution phone/tablet layout) wins over device emulation: it rasterises at DSF 1 by design.
    deviceScaleFactor: mobile ? 1 : opts.deviceScaleFactor || device?.deviceScaleFactor || 2,
    ...(mobile ? { isMobile: true, hasTouch: true } : {}),
    ...(!mobile && opts.isMobile !== undefined ? { isMobile: opts.isMobile } : {}),
    ...(!mobile && opts.hasTouch !== undefined ? { hasTouch: opts.hasTouch } : {}),
    colorScheme: opts.colorScheme || 'light',
    locale: opts.locale || 'en-US',
    timezoneId: opts.timezoneId || 'America/Chicago',
    ...(opts.storageState ? { storageState: opts.storageState } : {}),
    ...(opts.extraHTTPHeaders ? { extraHTTPHeaders: opts.extraHTTPHeaders } : {}),
    recordVideo: { dir: rawDir, size: opts.videoSize || viewport },
  });
  if (mobile) {
    await context.addInitScript(([cssWidth, scale]) => {
      const set = () => {
        let m = document.querySelector('meta[name=viewport]');
        if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
        m.content = `width=${cssWidth}, initial-scale=${scale}, minimum-scale=${scale}, maximum-scale=${scale}, user-scalable=no`;
      };
      if (document.head) set(); else document.addEventListener('DOMContentLoaded', set);
      window.addEventListener('load', set);
      // A phone shows a touch, not a cursor: a soft dot where the finger lands (like the OS "show touches" option).
      document.addEventListener('pointerdown', (e) => {
        const d = document.createElement('div');
        d.style.cssText = `position:fixed;left:${e.clientX - 22}px;top:${e.clientY - 22}px;width:44px;height:44px;border-radius:50%;background:rgba(110,86,248,0.35);border:2px solid rgba(110,86,248,0.85);pointer-events:none;z-index:2147483647;transition:transform 420ms ease-out,opacity 420ms ease-out;transform:scale(0.6);opacity:1`;
        document.body.appendChild(d);
        requestAnimationFrame(() => { d.style.transform = 'scale(1.25)'; d.style.opacity = '0'; });
        setTimeout(() => d.remove(), 600);
      }, true);
    }, [mobile.cssWidth, mobile.scale]);
  }
  // Likewise a desktop frame is recorded at CSS-pixel size, so the app's 14 px text reads small in a 16:9 ad. An opt-in
  // opts.pageZoom (e.g. 1.5) magnifies the page itself: the document zoom is set before the app paints and again once it
  // has loaded, the layout reflows at viewport / pageZoom CSS px, and boundingBox / mouse coordinates stay in window pixels.
  if (opts.pageZoom && !mobile) {
    await context.addInitScript((z) => {
      const set = () => { if (document.documentElement) document.documentElement.style.zoom = String(z); };
      set();
      document.addEventListener('DOMContentLoaded', set);
      window.addEventListener('load', set);
    }, opts.pageZoom);
  }
  await context.tracing.start({ screenshots: true, snapshots: true, sources: false });
  // The recorded video starts when the page is created, so the action clock starts just before it: every event `t`
  // is then seconds into the raw WebM (the cue sheet and the sync gate map these through the edit decision list).
  const t0 = Date.now();
  const page = await context.newPage();
  const beats = new BeatTracker(t0);
  const log = new EventLog(t0);
  const h = bindHelpers(page, log, beats, { ...opts, hasTouch: opts.hasTouch ?? device?.hasTouch ?? false });
  return { id, browser, context, page, rawDir, beats, log, h, t0, viewport };
}

/** Stop tracing and video; return paths. */
export async function finishRecording(rec, opts = {}) {
  const tracePath = path.join(rec.rawDir, 'trace.zip');
  await rec.context.tracing.stop({ path: tracePath });
  const video = rec.page.video();
  // Multi-take product flows keep per-device state (a capture tally, a persona, a draft) in web storage; saving it
  // lets the next take continue exactly where this one ended, which is what a viewer sees as one session.
  if (opts.saveStatePath) { try { await rec.context.storageState({ path: opts.saveStatePath }); } catch (e) { console.log('  storageState not saved:', String(e.message).split(/\r?\n/)[0]); } }
  await rec.context.close();
  await rec.browser.close();
  let webm = null;
  try { webm = await video.path(); } catch { /* fall through to directory scan */ }
  if (!webm || !fs.existsSync(webm)) {
    const files = fs.readdirSync(rec.rawDir).filter((f) => f.endsWith('.webm'));
    if (!files.length) throw new Error('no webm recorded in ' + rec.rawDir);
    webm = path.join(rec.rawDir, files[0]);
  }
  fs.writeFileSync(path.join(rec.rawDir, 'beats.json'), JSON.stringify(rec.beats.toJSON(), null, 2));
  fs.writeFileSync(path.join(rec.rawDir, 'events.json'), JSON.stringify({ events: rec.log.events, expectations: rec.log.expectations }, null, 2));
  return { tracePath, webm, rawDir: rec.rawDir, beats: rec.beats.toJSON(), events: rec.log.events, expectations: rec.log.expectations, summary: rec.log.summary() };
}

/**
 * Zoom windows for Recast autoZoom, one per click, written as an SRT beside the raw take.
 * Recast's autoZoom only zooms inside a subtitle cue (zoom end = min(next user action, cue end)), and
 * generateSubtitles drops every action whose text is empty, so `.subtitles(() => '')` produced zero cues and
 * no punch-in on any take (measured 2026-10-14: subtitlesCount 0, frames unzoomed through both clicks). A cue
 * runs from just before each click (typeText clicks the field first, so typing is covered) to the next click
 * or `holdSeconds` later. Cue text is never burned in (burnSubtitles stays off).
 */
export function writeZoomCues(rawDir, holdSeconds = 2.5) {
  const eventsPath = path.join(rawDir, 'events.json');
  if (!fs.existsSync(eventsPath)) return null;
  const clicks = JSON.parse(fs.readFileSync(eventsPath, 'utf8')).events.filter((e) => e.type === 'click').map((e) => e.t);
  const cues = [];
  let prevEnd = 0;
  clicks.forEach((t, i) => {
    const start = Math.max(prevEnd, t - 0.3, 0);
    const end = Math.min(clicks[i + 1] ?? Infinity, t + holdSeconds);
    if (end - start >= 0.6) { cues.push([start, end]); prevEnd = end; }
  });
  if (!cues.length) return null;
  const ts = (x) => { const ms = Math.round(x * 1000); const p = (n, w = 2) => String(n).padStart(w, '0'); return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(Math.floor(ms / 1000) % 60)},${p(ms % 1000, 3)}`; };
  const srt = cues.map(([a, b], i) => `${i + 1}\n${ts(a)} --> ${ts(b)}\nzoom\n`).join('\n');
  const out = path.join(rawDir, 'zoom-cues.srt');
  fs.writeFileSync(out, srt);
  return out;
}

/** Recast finishing: cursor approach, click ripple, punch-in zoom. Requires playwright-recast in the kit. */
export async function renderRecast(rawDir, outFile, opts = {}) {
  const { Recast } = await import('playwright-recast');
  const cues = opts.autoZoom !== false ? writeZoomCues(rawDir, opts.zoomHoldSeconds) : null;
  let r = Recast.from(rawDir).parse();
  r = cues ? r.subtitlesFromSrt(cues) : r.subtitles(() => '');
  // cursor: false (mobile layouts) draws no desktop cursor or click ripple: the page shows its own touch indicator.
  if (opts.cursor !== false) {
    r = r
      .cursorOverlay({ approachMs: 500, postArrivalHoldMs: 300, ...(opts.cursor || {}) })
      .clickEffect({ radius: 28, duration: 350, opacity: 0.55, ...(opts.click || {}) });
  }
  if (opts.autoZoom !== false) {
    r = r.autoZoom({ clickLevel: 1.35, inputLevel: 1.4, idleLevel: 1.0, centerBias: 0.25, ...(opts.zoom || {}) });
  }
  const size = opts.resolution || { width: 1600, height: 1000 };
  await r.render({ format: 'webm', resolution: size, fps: opts.fps || 30 }).toFile(outFile);
  return outFile;
}

/** Helpers bound to one page. Every helper logs to the receipt. */
export function bindHelpers(page, log, beats, opts = {}) {
  const base = opts.baseUrl || '';
  // Input runs in CSS layout pixels; the receipt logs recorded-video pixels, which differ by the mobile page scale, or by
  // the DSF when record-job records a --ratio take at viewport x DSF (opts.videoSize).
  const k = opts.mobileLayout ? opts.mobileLayout.scale : (opts.videoSize && opts.viewport?.width ? opts.videoSize.width / opts.viewport.width : 1);
  const wait = (ms) => page.waitForTimeout(ms);

  const center = async (locator) => {
    await locator.first().scrollIntoViewIfNeeded().catch(() => {});
    const b = await locator.first().boundingBox();
    if (!b) throw new Error('locator has no bounding box: ' + String(locator));
    return { x: b.x + b.width / 2, y: b.y + b.height / 2, box: b };
  };

  /** Eased pointer travel to a locator (400–600 ms), then a short settle. Logs every step. */
  async function approach(locator, o = {}) {
    const { x: tx, y: ty, box } = await center(locator);
    const sx = log.pointer.x ?? clamp(tx - 260, 8, page.viewportSize().width - 8);
    const sy = log.pointer.y ?? clamp(ty - 160, 8, page.viewportSize().height - 8);
    const dist = Math.hypot(tx - sx, ty - sy);
    const ms = o.ms || clamp(TIMING.pointerMoveMsMin + (dist / 900) * (TIMING.pointerMoveMsMax - TIMING.pointerMoveMsMin), TIMING.pointerMoveMsMin, TIMING.pointerMoveMsMax);
    // Three real pointer positions per approach: Recast interpolates the eased path between trace keyframes, and every
    // mouse.move becomes a keyframe in its ffmpeg expression (a 100-move take overflowed the Windows command line).
    const steps = o.steps || 3;
    const per = ms / steps;
    for (let i = 1; i <= steps; i++) {
      const e = easeInOutCubic(i / steps);
      const x = sx + (tx - sx) * e, y = sy + (ty - sy) * e;
      await page.mouse.move(x, y);
      log.push('move', { x: Math.round(x * k), y: Math.round(y * k) });
      await wait(per);
    }
    log.pointer = { x: tx, y: ty };
    await wait(o.settle ?? TIMING.clickSettleMs);
    return { x: tx, y: ty, box };
  }

  /** Approach, optional hover dwell (native hover state on camera), click, result hold. */
  async function click(locator, o = {}) {
    const { x, y, box } = await approach(locator, o);
    if (o.hoverDwell) await wait(o.hoverDwell);
    // A locator click, not page.mouse.click: Recast's click ripple, held cursor approach and auto-zoom all key on trace
    // actions whose method is 'click' with a recorded point. mouse.click is method 'mouse.click' and none of the three see
    // it (the take then carries a cursor from the move keyframes but no ripple and no punch-in). The pointer is already
    // on the element centre, so the click lands where the approach ended; force skips a second actionability wait.
    // tStart is the moment the click is issued (the narration word it must land on); t is when Playwright returned.
    const tStart = log.now();
    await locator.first().click({ delay: 60, force: true, position: { x: box.width / 2, y: box.height / 2 }, timeout: 8000 });
    log.push('click', { x: Math.round(x * k), y: Math.round(y * k), label: o.label || null, target: o.target || o.label || describe(locator), tStart });
    if (o.label) beats.mark(o.label, { box: { x: Math.round(box.x), y: Math.round(box.y), w: Math.round(box.width), h: Math.round(box.height) } });
    await wait(o.hold ?? TIMING.clickHoldMs);
  }

  /**
   * A finger tap on a touch context: no pointer travel, so no 'move' events; the log carries only the tap, which the pointer-path
   * gate reads as a named action. Without touch (opts.hasTouch falsy) it falls back to the desktop click (eased approach, then
   * click) and still logs type 'tap'. Pass the same { label } the cue plan names.
   */
  async function tap(locator, o = {}) {
    const touch = !!opts.hasTouch;
    const { x, y, box } = touch ? await center(locator) : await approach(locator, o);
    const position = { x: box.width / 2, y: box.height / 2 };
    const tStart = log.now();
    if (touch) await locator.first().tap({ force: true, position, timeout: 8000 });
    else await locator.first().click({ delay: 60, force: true, position, timeout: 8000 });
    log.push('tap', { x: Math.round(x), y: Math.round(y), label: o.label || null, target: o.target || o.label || describe(locator), tStart });
    log.pointer = { x, y };
    if (o.label) beats.mark(o.label, { box: { x: Math.round(box.x), y: Math.round(box.y), w: Math.round(box.width), h: Math.round(box.height) } });
    await wait(o.hold ?? TIMING.clickHoldMs);
  }

  /** Readable accelerated typing (never real-time entry). Clicks the field first. */
  async function typeText(locator, text, o = {}) {
    await click(locator, { ...o, hold: 250 });
    if (o.clear) { await page.keyboard.press('Control+A'); await page.keyboard.press('Backspace'); }
    const tStart = log.now();
    await page.keyboard.type(text, { delay: o.delay ?? TIMING.typingDelayMs });
    log.push('type', { chars: text.length, label: o.label || null, target: o.target || o.label || describe(locator), tStart });
    await wait(o.hold ?? 600);
  }

  /** Select one local file through a real file input, including hidden dropzone inputs. No synthetic click. */
  async function uploadFile(locator, filePath, o = {}) {
    if (typeof o.label !== 'string' || !o.label.trim()) throw new Error('uploadFile requires a nonempty action label');
    if (typeof filePath !== 'string' || !filePath.trim()) throw new Error('uploadFile requires a local file path');
    if (!locator || typeof locator.count !== 'function' || typeof locator.setInputFiles !== 'function') throw new Error('uploadFile requires a file-input locator');
    if (await locator.count() !== 1) throw new Error('uploadFile locator must resolve to exactly one file input');
    const isFileInput = await locator.evaluate((el) => el.tagName === 'INPUT' && el.type === 'file');
    if (!isFileInput) throw new Error('uploadFile locator must target input[type=file]');
    // Read once, then pass those exact bytes to Playwright: later disk changes cannot invalidate the receipt hash.
    const resolved = path.resolve(filePath);
    if (!fs.statSync(resolved).isFile()) throw new Error('uploadFile source must be a regular file');
    const buffer = fs.readFileSync(resolved);
    const name = path.basename(resolved);
    const mimeType = o.mimeType ?? (path.extname(name).toLowerCase() === '.csv' ? 'text/csv' : 'application/octet-stream');
    if (typeof mimeType !== 'string' || !mimeType.trim()) throw new Error('uploadFile mimeType must be nonempty');
    const file = { name, bytes: buffer.length, sha256: createHash('sha256').update(buffer).digest('hex'), mimeType };
    const tStart = log.now();
    await locator.setInputFiles({ name, mimeType, buffer }, { timeout: o.timeout ?? 15000 });
    const tEnd = log.now();
    const event = log.push('upload', { label: o.label, target: o.target || describe(locator), method: 'locator.setInputFiles', file, tStart, tEnd });
    beats.mark(o.label);
    await wait(o.hold ?? TIMING.clickHoldMs);
    return event;
  }

  /** Pointer lead without a click, for a read beat. */
  async function pointAt(locator, o = {}) {
    const r = await approach(locator, o);
    // A cursor-led highlight for a read beat (dashboards, diagrams): the arrival is the action the narration names.
    log.push('point', { x: Math.round(r.x * k), y: Math.round(r.y * k), targetBox: { x: r.box.x * k, y: r.box.y * k, w: r.box.width * k, h: r.box.height * k }, label: o.label || null, target: o.target || o.label || describe(locator), tStart: log.now() });
    if (o.label) beats.mark(o.label, { box: { x: Math.round(r.box.x), y: Math.round(r.box.y), w: Math.round(r.box.width), h: Math.round(r.box.height) } });
    await wait(o.hold ?? 900);
    return r;
  }

  /** Hover and hold so the native hover state is on camera. */
  async function hoverHold(locator, ms = 1000) {
    await approach(locator, { settle: 0 });
    await locator.first().hover().catch(() => {});
    await wait(ms);
  }

  /** Multi-step wheel scroll so motion stays legible. */
  async function smoothScroll(px, o = {}) {
    const steps = o.steps || 6;
    const per = Math.round(px / steps);
    if (o.over) await approach(o.over, { settle: 0 });
    for (let i = 0; i < steps; i++) {
      await page.mouse.wheel(0, per);
      log.push('wheel', { dy: per });
      await wait(o.delay ?? TIMING.scrollStepDelayMs);
    }
    await wait(o.hold ?? 500);
  }

  /** Wait for the visible product response that proves the action. Logged as an expectation. */
  async function expect(locator, label, o = {}) {
    const t = log.now();
    let observed = false;
    const target = o.text ? locator.filter({ hasText: o.text }).first() : locator.first();
    const state = o.text ? 'visible' : o.state || 'visible';
    const alreadyVisible = state === 'visible' ? await target.isVisible().catch(() => false) : false;
    let targetBox = null;
    try {
      if (o.text) await locator.filter({ hasText: o.text }).first().waitFor({ state: 'visible', timeout: o.timeout ?? TIMING.expectTimeoutMs });
      else await locator.first().waitFor({ state: o.state || 'visible', timeout: o.timeout ?? TIMING.expectTimeoutMs });
      observed = true;
      if (state === 'visible') {
        const b = await target.boundingBox();
        if (b) targetBox = { x: b.x * k, y: b.y * k, w: b.width * k, h: b.height * k };
      }
    } catch (e) {
      observed = false;
      log.push('expect-failed', { label, error: String(e.message).split('\n')[0] });
    }
    log.expectations.push({ label, observed, at: t, observedAt: observed ? log.now() : null, state, alreadyVisible, targetBox });
    if (observed) log.push('expect', { label });
    if (observed) beats.mark('result: ' + label);
    if (!observed && !o.soft) throw new Error('expected product response not observed: ' + label);
    await wait(o.hold ?? TIMING.clickHoldMs);
    return observed;
  }

  /** Navigate and settle. */
  async function go(route, o = {}) {
    const url = /^https?:/.test(route) ? route : base + route;
    await page.goto(url, { waitUntil: o.waitUntil || 'domcontentloaded', timeout: o.timeout ?? 60000 });
    log.push('goto', { url });
    if (o.readySelector) await page.locator(o.readySelector).first().waitFor({ state: 'visible', timeout: o.readyTimeout ?? 30000 });
    await wait(o.settle ?? 1500);
  }

  /** Result hold (≥500 ms; longer when the viewer must read). */
  const hold = (ms = 1500) => wait(ms);

  return { approach, click, tap, typeText, uploadFile, pointAt, hoverHold, smoothScroll, expect, go, hold, wait, mark: (l, x) => beats.mark(l, x), page };
}
