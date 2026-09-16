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
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

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
  push(type, data = {}) { this.events.push({ t: this.now(), type, ...data }); }
  summary() {
    const count = (type) => this.events.filter((e) => e.type === type).length;
    return {
      pointerMoves: count('move'),
      clicks: count('click'),
      keystrokes: this.events.filter((e) => e.type === 'type').reduce((n, e) => n + (e.chars || 0), 0),
      scrolls: count('wheel'),
      navigations: count('goto'),
      expectations: this.expectations.length,
      expectationsObserved: this.expectations.filter((e) => e.observed).length,
      expectationsFailed: this.expectations.filter((e) => !e.observed).map((e) => e.label),
    };
  }
}

/** Start a fresh recording context. viewport is the delivery frame; DSF 2 is the PDS minimum. */
export async function startRecording(id, opts = {}) {
  const viewport = opts.viewport || { width: 1600, height: 1000 };
  const rawDir = path.resolve(opts.rawRoot || 'raw', id);
  fs.rmSync(rawDir, { recursive: true, force: true });
  fs.mkdirSync(rawDir, { recursive: true });
  const browser = await chromium.launch({ headless: opts.headless !== false, args: ['--hide-scrollbars=false'] });
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: opts.deviceScaleFactor || 2,
    colorScheme: opts.colorScheme || 'light',
    locale: opts.locale || 'en-US',
    timezoneId: opts.timezoneId || 'America/Chicago',
    ...(opts.storageState ? { storageState: opts.storageState } : {}),
    ...(opts.extraHTTPHeaders ? { extraHTTPHeaders: opts.extraHTTPHeaders } : {}),
    recordVideo: { dir: rawDir, size: viewport },
  });
  await context.tracing.start({ screenshots: true, snapshots: true, sources: false });
  const page = await context.newPage();
  const t0 = Date.now();
  const beats = new BeatTracker(t0);
  const log = new EventLog(t0);
  const h = bindHelpers(page, log, beats, opts);
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

/** Recast finishing: cursor approach, click ripple, punch-in zoom. Requires playwright-recast in the kit. */
export async function renderRecast(rawDir, outFile, opts = {}) {
  const { Recast } = await import('playwright-recast');
  let r = Recast.from(rawDir).parse().subtitles(() => '')
    .cursorOverlay({ approachMs: 500, postArrivalHoldMs: 300, ...(opts.cursor || {}) })
    .clickEffect({ radius: 28, duration: 350, opacity: 0.55, ...(opts.click || {}) });
  if (opts.autoZoom !== false) {
    r = r.autoZoom({ clickLevel: 1.35, inputLevel: 1.4, idleLevel: 1.0, centerBias: 0.25, ...(opts.zoom || {}) });
  }
  const size = opts.resolution || { width: 1600, height: 1000 };
  await r.render({ format: 'webm', resolution: size, fps: 30 }).toFile(outFile);
  return outFile;
}

/** Helpers bound to one page. Every helper logs to the receipt. */
export function bindHelpers(page, log, beats, opts = {}) {
  const base = opts.baseUrl || '';
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
    const steps = o.steps || Math.max(8, Math.round(ms / 33));
    const per = ms / steps;
    for (let i = 1; i <= steps; i++) {
      const e = easeInOutCubic(i / steps);
      const x = sx + (tx - sx) * e, y = sy + (ty - sy) * e;
      await page.mouse.move(x, y);
      log.push('move', { x: Math.round(x), y: Math.round(y) });
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
    await page.mouse.down(); await wait(60); await page.mouse.up();
    log.push('click', { x: Math.round(x), y: Math.round(y), label: o.label || null });
    if (o.label) beats.mark(o.label, { box: { x: Math.round(box.x), y: Math.round(box.y), w: Math.round(box.width), h: Math.round(box.height) } });
    await wait(o.hold ?? TIMING.clickHoldMs);
  }

  /** Readable accelerated typing (never real-time entry). Clicks the field first. */
  async function typeText(locator, text, o = {}) {
    await click(locator, { ...o, hold: 250 });
    if (o.clear) { await page.keyboard.press('Control+A'); await page.keyboard.press('Backspace'); }
    await page.keyboard.type(text, { delay: o.delay ?? TIMING.typingDelayMs });
    log.push('type', { chars: text.length, label: o.label || null });
    await wait(o.hold ?? 600);
  }

  /** Pointer lead without a click, for a read beat. */
  async function pointAt(locator, o = {}) {
    const r = await approach(locator, o);
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
    try {
      if (o.text) await locator.filter({ hasText: o.text }).first().waitFor({ state: 'visible', timeout: o.timeout ?? TIMING.expectTimeoutMs });
      else await locator.first().waitFor({ state: o.state || 'visible', timeout: o.timeout ?? TIMING.expectTimeoutMs });
      observed = true;
    } catch (e) {
      observed = false;
      log.push('expect-failed', { label, error: String(e.message).split('\n')[0] });
    }
    log.expectations.push({ label, observed, at: t, observedAt: observed ? log.now() : null });
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

  return { approach, click, typeText, pointAt, hoverHold, smoothScroll, expect, go, hold, wait, mark: (l, x) => beats.mark(l, x), page };
}
