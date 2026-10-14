// Scene functions for code and diagram shots, driven through the same record-lib helpers as a product take, so
// record-job.mjs records them headless as Playwright WebM, finishes them with Recast (pointer, click ring, punch-in)
// and writes the same capture receipt. The editor and diagram pages are served from disk through page.route on a
// private origin; nothing listens on a port and no window opens.
//
// Usage (written for you by build-stage.mjs into <job>/capture/code-stage/scenes.mjs):
//   import { stageScenes } from '<kit>/code-stage/driver.mjs';
//   export const { scenes, recast, order } = stageScenes('<job>/capture/code-stage');
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ORIGIN = 'http://code-stage.localhost'; // *.localhost is a secure context (crypto.subtle verifies the lines)
const here = path.dirname(fileURLToPath(import.meta.url));
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.ttf': 'font/ttf', '.svg': 'image/svg+xml' };

function inside(root, rel) {
  const p = path.resolve(root, rel);
  return p === root || p.startsWith(root + path.sep) ? p : null;
}

/** Serve editor/diagram pages, stage.json and (when local) Monaco from disk to this page's context. */
export async function installStage(page, stageDir, stage) {
  await page.context().route(ORIGIN + '/**', async (route) => {
    const u = new URL(route.request().url());
    const rel = decodeURIComponent(u.pathname).replace(/^\/+/, '');
    let file = null;
    if (rel === 'stage.json') file = path.join(stageDir, 'stage.json');
    else if (rel === 'editor.html' || rel === 'diagram.html') file = path.join(here, rel);
    else if (rel.startsWith('monaco/') && stage.monacoDir) file = inside(path.resolve(stage.monacoDir), rel.slice('monaco/'.length));
    if (!file || !fs.existsSync(file)) return route.fulfill({ status: 404, body: 'not found' });
    return route.fulfill({ status: 200, body: fs.readFileSync(file), headers: { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'max-age=3600' } });
  });
}

async function runCode(h, page, shot, events) {
  const ev = (fn, arg) => page.evaluate(fn, arg);
  const xr = (i) => shot.crossRefs[i];
  return {
    async reveal() { await ev(() => window.codeStage.reveal()); },
    async pointer(k) { const pt = shot.pointer[k]; const loc = page.locator(`#anchor-p${k}`); if (pt.click) await h.click(loc, { hold: 0, label: `line ${pt.line}` }); else await h.pointAt(loc, { hold: 0, label: `line ${pt.line}` }); },
    async highlight(i) {
      const [a, b] = shot.highlight[i];
      await ev((id) => window.codeStage.highlight(id), 'h' + i);
      await h.click(page.locator(`#anchor-h${i}`), { hold: 0, label: `highlight ${a}-${b}` });
      await h.expect(page.locator(`#band-h${i}.on`), `highlight ${a}-${b} shown`, { hold: 0 });
    },
    async callout() {
      await ev(() => window.codeStage.callout('main'));
      await h.expect(page.locator('#callout-main.on'), `callout "${shot.callout.text}"`, { hold: 0 });
    },
    async crossref(i) {
      const x = xr(i);
      await ev((k) => window.codeStage.prepareRef(k), i); // scroll the explorer like VS Code would, before the pointer moves
      await h.click(page.locator(`#tree .row[data-file="${x.file}"]`), { hold: 0, label: `open ${x.file}` });
      await ev((k) => window.codeStage.openRef(k), i);
      await h.expect(page.locator(`#tabs .tab.active[data-path="${x.file}"]`), `opened ${x.file}`, { hold: 0 });
    },
    async crossrefHighlight(i) {
      const x = xr(i);
      for (let k = 0; k < x.highlight.length; k++) await ev((id) => window.codeStage.highlight(id), `x${i}-${k}`);
      const [a, b] = x.highlight[0];
      await h.click(page.locator(`#anchor-x${i}-0`), { hold: 0, label: `highlight ${x.file} ${a}-${b}` });
      await h.expect(page.locator(`#band-x${i}-0.on`), `highlight ${x.file} ${a}-${b} shown`, { hold: 0 });
    },
    async crossrefCallout(i) {
      await ev((k) => window.codeStage.callout(String(k)), i);
      await h.expect(page.locator(`#callout-${i}.on`), `callout "${xr(i).callout.text}"`, { hold: 0 });
    },
  };
}

function runDiagram(h, page, shot) {
  return {
    async node(id) {
      await page.evaluate((n) => window.diagram.reveal(n), id);
      await h.expect(page.locator(`#node-${id}.on`), `node ${id} shown`, { hold: 0 });
    },
    async lit() {
      await page.evaluate(() => window.diagram.lit());
      await h.click(page.locator(`#node-${shot.lit}`), { hold: 0, label: `gate ${shot.lit}` });
      await h.expect(page.locator(`#node-${shot.lit}.lit`), `node ${shot.lit} lit`, { hold: 0 });
    },
  };
}

/** Play one shot: load the page, verify the rendered code, then fire each event on its cue time. */
export async function playShot(h, ctx, stageDir, stage, shot) {
  const page = ctx.page;
  await installStage(page, stageDir, stage);
  await h.go(`${ORIGIN}/${shot.kind === 'code' ? 'editor' : 'diagram'}.html?shot=${encodeURIComponent(shot.id)}`, { readySelector: '#cs-ready', readyTimeout: 60000, settle: 400 });
  if (await page.locator('#cs-error').count()) throw new Error('stage page error: ' + (await page.locator('#cs-error').textContent()).split('\n')[0]);
  if (shot.kind === 'code') {
    await h.expect(page.locator('#verified[data-ok="1"]'), 'rendered lines match the receipt hashes', { state: 'attached', hold: 0 });
    // Pointer starts parked over the editor, so the first approach reads as a hand moving to the code.
    await h.pointAt(page.locator('#ed'), { hold: 0 });
  } else {
    await h.pointAt(page.locator('#board'), { hold: 0 });
  }
  const t0 = Date.now();
  h.mark('stage-t0');
  const run = shot.kind === 'code' ? await runCode(h, page, shot) : runDiagram(h, page, shot);
  const fired = [];
  for (const e of shot.events) {
    // Opening a cross-ref is click-driven: start the pointer travel early so the file opens on the word.
    const lead = /^crossref:\d+$/.test(e.event) ? 900 : 0;
    const due = t0 + e.t * 1000 - lead - Date.now();
    if (due > 0) await h.wait(due);
    const late = Math.max(0, -due) / 1000;
    const started = Math.round((Date.now() - t0) / 10) / 100; // the visual change is applied first, then the pointer follows
    const [kind, a, b] = e.event.split(':');
    if (kind === 'reveal') await run.reveal();
    else if (kind === 'pointer') await run.pointer(+a);
    else if (kind === 'highlight') await run.highlight(+a);
    else if (kind === 'callout') await run.callout();
    else if (kind === 'crossref' && !b) await run.crossref(+a);
    else if (kind === 'crossref' && b === 'highlight') await run.crossrefHighlight(+a);
    else if (kind === 'crossref' && b === 'callout') await run.crossrefCallout(+a);
    else if (kind === 'node') await run.node(a);
    else if (kind === 'lit') await run.lit();
    fired.push({ event: e.event, plannedSeconds: e.t, startedSeconds: started, doneSeconds: Math.round((Date.now() - t0) / 10) / 100, lateSeconds: Math.round(late * 100) / 100 });
  }
  const end = t0 + Math.max(shot.durationSeconds, (shot.events.at(-1)?.t || 0) + shot.holdSeconds) * 1000 - Date.now();
  if (end > 0) await h.wait(end);
  fs.writeFileSync(path.join(stageDir, `played-${shot.id}.json`), JSON.stringify({ id: shot.id, fired, verification: shot.kind === 'code' ? await page.evaluate(() => window.codeStage.verification) : null }, null, 2));
}

/** Scenes, Recast options and order for every shot in <stageDir>/stage.json. */
export function stageScenes(stageDir) {
  const dir = path.resolve(stageDir);
  const stage = JSON.parse(fs.readFileSync(path.join(dir, 'stage.json'), 'utf8'));
  const scenes = {}; const recast = {};
  for (const shot of stage.shots) {
    scenes[shot.id] = (h, ctx) => playShot(h, ctx, dir, stage, shot);
    const z = shot.zoom || 1.35;
    recast[shot.id] = { zoom: { clickLevel: z, inputLevel: z }, ...(stage.fps ? { fps: stage.fps } : {}) };
  }
  return { scenes, recast, order: stage.shots.map((s) => s.id), stage };
}
