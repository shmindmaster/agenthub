#!/usr/bin/env node
// Record a screen take through the local capture runtime and keep a timed action log, so validate-pointer-path.mjs can judge the
// cursor. Each command runs the real browser action and logs it on the clip clock (seconds since recording started).
//
//   node browser-take.mjs <jobRoot> <clipId> start <video.webm> [url]
//   node browser-take.mjs <jobRoot> <clipId> move <x> <y> [--ms 600]
//   node browser-take.mjs <jobRoot> <clipId> click <x> <y> --label "<what the narration names>"
//   node browser-take.mjs <jobRoot> <clipId> point <x> <y> --label "<what the narration names>"
//   node browser-take.mjs <jobRoot> <clipId> type <text> --label "<field>"
//   node browser-take.mjs <jobRoot> <clipId> wheel <dy>
//   node browser-take.mjs <jobRoot> <clipId> stop
//
// `stop` writes capture/receipt.json clips[<clipId>] = { video, actions, actionClock: "clip", clipSeconds, segments }.
// Times are taken when each browser command returns, so they are real, not planned. Browser: $AH_BROWSE, else this
// package's own capture-browse.mjs wrapper, else agent-browser on PATH. The wrapper is local since 2026-11-26: the
// ah-browser package was removed because Playwright and Chrome DevTools are official plugins, and only the capture
// path media-studio needs was kept.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export function browserCommand() {
  const candidates = [process.env.AH_BROWSE, join(here, 'capture-browse.mjs')].filter(Boolean);
  const browse = candidates.find((path) => existsSync(path));
  return browse ? { command: process.execPath, prefix: [browse] } : { command: 'agent-browser', prefix: [] };
}
function browser(args) {
  const { command, prefix } = browserCommand();
  const run = spawnSync(command, [...prefix, ...args], { encoding: 'utf8', windowsHide: true, shell: false });
  if (run.status !== 0) throw new Error(`browser ${args.join(' ')} failed: ${(run.stderr || run.stdout || run.error?.message || '').trim()}`);
  return run.stdout;
}
const round = (n) => Math.round(n * 1000) / 1000;

/** Pure: append one action to a take log. `now` is ms since epoch. */
export function logAction(take, action, now) {
  const tStart = round((now - take.t0) / 1000);
  take.actions.push({ ...action, tStart });
  return take;
}
/** Pure: the receipt entry for a finished take. */
export function receiptClip(take, now) {
  return { video: take.video, actions: take.actions, actionClock: 'clip', clipSeconds: round((now - take.t0) / 1000), segments: [take.clipId], recordedWith: 'capture-browse.mjs record --cursor' };
}

const invoked = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invoked) {
  const argv = process.argv.slice(2);
  const flag = (name) => { const i = argv.indexOf(name); if (i < 0) return undefined; const v = argv[i + 1]; argv.splice(i, 2); return v; };
  const label = flag('--label');
  const ms = Number(flag('--ms') ?? 600);
  const [jobRoot, clipId, verb, ...rest] = argv;
  if (!jobRoot || !clipId || !verb) { console.error('Usage: node browser-take.mjs <jobRoot> <clipId> start|move|click|point|type|wheel|stop ...'); process.exit(1); }
  const root = resolve(jobRoot);
  const logPath = join(root, 'capture', 'takes', `${clipId}.take.json`);
  const load = () => JSON.parse(readFileSync(logPath, 'utf8'));
  const save = (take) => { mkdirSync(dirname(logPath), { recursive: true }); writeFileSync(logPath, `${JSON.stringify(take, null, 2)}\n`); };
  const xy = () => { const x = Number(rest[0]); const y = Number(rest[1]); if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error(`${verb} needs <x> <y>`); return { x, y }; };
  const named = () => { if (!label) throw new Error(`${verb} needs --label naming what the narration points at`); return label; };
  try {
    if (verb === 'start') {
      const video = resolve(root, rest[0] ?? `capture/${clipId}.webm`);
      mkdirSync(dirname(video), { recursive: true });
      browser(['record', 'start', video, ...(rest[1] ? [rest[1]] : []), '--cursor']);
      save({ clipId, video, t0: Date.now(), pointer: { x: 0, y: 0 }, actions: [] });
    } else if (verb === 'stop') {
      const take = load();
      browser(['record', 'stop']);
      const receiptPath = join(root, 'capture', 'receipt.json');
      const receiptLib = [join(here, 'receipt-lib.mjs'), join(here, '..', 'kit', 'screencast', 'receipt-lib.mjs')].find(existsSync);
      if (!receiptLib) throw new Error('receipt-lib.mjs not found beside this script or in ../kit/screencast');
      const { receiptProblem, saveReceipt } = await import(pathToFileURL(receiptLib).href);
      const receipt = existsSync(receiptPath) ? JSON.parse(readFileSync(receiptPath, 'utf8')) : { schema: 'media-studio/capture-receipt/1', clips: {} };
      const edited = receiptProblem(receipt, null);
      if (edited) throw new Error(edited);
      receipt.clips = { ...(receipt.clips || {}), [clipId]: receiptClip(take, Date.now()) };
      saveReceipt(receiptPath, receipt);
    } else {
      const take = load();
      if (verb === 'move' || verb === 'click' || verb === 'point') {
        const { x, y } = xy();
        // Log three points along the eased approach, the way record-lib.mjs does, then the named action.
        const from = take.pointer;
        browser(['mouse', 'move', String(x), String(y), '--duration', String(ms)]);
        const now = Date.now();
        for (const f of [1 / 3, 2 / 3, 1]) logAction(take, { type: 'move', x: round(from.x + (x - from.x) * f), y: round(from.y + (y - from.y) * f) }, now - ms * (1 - f));
        take.pointer = { x, y };
        if (verb === 'click') { browser(['mouse', 'down']); browser(['mouse', 'up']); logAction(take, { type: 'click', x, y, label: named() }, Date.now()); }
        if (verb === 'point') logAction(take, { type: 'point', x, y, label: named() }, Date.now());
      } else if (verb === 'type') {
        const text = rest.join(' ');
        const startedAt = Date.now();
        browser(['keyboard', 'type', text]);
        logAction(take, { type: 'type', x: take.pointer.x, y: take.pointer.y, label: named(), chars: text.length }, startedAt);
      } else if (verb === 'wheel') {
        const dy = Number(rest[0]);
        if (!Number.isFinite(dy)) throw new Error('wheel needs <dy>');
        browser(['mouse', 'wheel', String(dy)]);
        logAction(take, { type: 'wheel', dy }, Date.now());
      } else throw new Error(`unknown verb ${verb}`);
      save(take);
    }
    console.log(JSON.stringify({ ok: true, clip: clipId, verb }));
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
