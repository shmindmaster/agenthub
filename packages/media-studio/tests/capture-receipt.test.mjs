// CORE-122: the capture receipt is sealed and says who and what was recorded, the gates check it, and a failed take fails the run.
// Run: node --test packages/media-studio/tests/capture-receipt.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leadSeconds, sealReceipt, receiptIntegrity, RECEIPT_SCHEMA, videoLeadProblems } from '../kit/screencast/receipt-lib.mjs';
import { IDENTITY, ff, hasFfmpeg, putReceipt, readJson, sha, write, writeCaptureJob, writeProof } from './fixtures/capture-job.mjs';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const scripts = join(pkg, 'scripts');
const skip = !hasFfmpeg();
const scratch = mkdtempSync(join(tmpdir(), 'capture-receipt-'));
test.after(() => rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }));
const run = (script, args) => { const r = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', windowsHide: true }); return { code: r.status, out: `${r.stdout}${r.stderr}` }; };
const gate = (name, root) => run(join(scripts, name), [root]);
let source = null;
const job = (name, over) => { const root = join(scratch, name); source ||= writeCaptureJob(join(scratch, '_source')); writeCaptureJob(root, { clip: source, ...over }); return root; };
const receiptOf = (root) => join(root, 'capture', 'receipt.json');
const edit = (root, fn) => { const r = readJson(receiptOf(root)); fn(r); write(receiptOf(root), r); };

test('a seal covers the whole receipt and does not depend on key order', () => {
  const sealed = sealReceipt({ clips: { S01: { sha256: 'a', actions: [{ t: 1.25 }] } }, baseUrl: 'x' });
  assert.equal(sealed.schemaVersion, RECEIPT_SCHEMA);
  const { contentSha256, ...rest } = sealed;
  assert.equal(receiptIntegrity({ contentSha256, ...Object.fromEntries(Object.entries(rest).reverse()) }).state, 'sealed');
  for (const change of [(r) => { r.clips.S01.actions[0].t = 1; }, (r) => { r.baseUrl = 'y'; }, (r) => { r.clips.S02 = {}; }]) {
    const copy = structuredClone(sealed); change(copy);
    assert.equal(receiptIntegrity(copy).state, 'edited');
  }
  assert.equal(receiptIntegrity({ schemaVersion: '9.9.9', clips: {} }).state, 'unknown-schema');
  assert.equal(receiptIntegrity({ clips: {} }).state, 'unknown-schema');
  assert.equal(receiptIntegrity({ schemaVersion: RECEIPT_SCHEMA, clips: {} }).state, 'edited');
  assert.equal(receiptIntegrity({ schemaVersion: '1.0.0', clips: {} }).state, 'unsealed');
});

test('a sealed receipt of the proven persona and build passes the gate', { skip }, () => {
  const r = gate('validate-product-picture.mjs', job('ok'));
  assert.equal(r.code, 0, r.out);
});

for (const [name, change, message] of [
  ['an unknown schema', (r) => { r.schemaVersion = '9.9.9'; }, /unknown receipt schemaVersion "9\.9\.9"/],
  ['a changed baseUrl', (r) => { r.baseUrl = 'https://elsewhere.test'; }, /edited after it was written/],
  ['a moved action time', (r) => { r.clips.S02.actions[1].t = 0.6; }, /edited after it was written/],
  ['a stripped seal', (r) => { delete r.contentSha256; r.schemaVersion = '1.0.0'; }, /not sealed/],
]) test(`product picture refuses ${name}`, { skip }, () => {
  const root = job(name.replace(/\W/g, '-')); edit(root, change);
  const r = gate('validate-product-picture.mjs', root);
  assert.equal(r.code, 1, r.out); assert.match(r.out, message);
});

test('pointer path and cue sheet refuse an edited receipt', { skip }, () => {
  const root = job('edited'); edit(root, (r) => { r.clips.S02.actions[1].tStart = 0.6; });
  for (const name of ['validate-pointer-path.mjs', 'build-cue-sheet.mjs']) { const r = gate(name, root); assert.equal(r.code, 1, name); assert.match(r.out, /edited after it was written/, name); }
});

test('a stripped seal is refused by every reader, unless the job gives a reason', { skip }, () => {
  const root = job('stripped'); edit(root, (r) => { delete r.contentSha256; r.schemaVersion = '1.0.0'; });
  for (const name of ['validate-pointer-path.mjs', 'build-cue-sheet.mjs']) { const r = gate(name, root); assert.equal(r.code, 1, name); assert.match(r.out, /not sealed/, name); }
  edit(root, (r) => { delete r.schemaVersion; });
  for (const name of ['validate-pointer-path.mjs', 'build-cue-sheet.mjs']) assert.match(gate(name, root).out, /unknown receipt schemaVersion/, name);
  edit(root, (r) => { r.schemaVersion = '1.0.0'; });
  write(join(root, 'job.json'), { ...readJson(join(root, 'job.json')), legacyReceiptAllowed: 'recorded on 4.2.0' });
  for (const name of ['validate-pointer-path.mjs', 'build-cue-sheet.mjs']) assert.doesNotMatch(gate(name, root).out, /not sealed/, name);
});

test('encoded picture refuses an edited receipt', { skip }, () => {
  const root = job('edited-encoded'); edit(root, (r) => { r.baseUrl = 'x'; });
  const candidate = join(root, 'out', 'film.mp4'); mkdirSync(dirname(candidate), { recursive: true });
  ff(['-i', source, '-t', '1', '-c:v', 'libx264', '-preset', 'ultrafast', candidate]);
  const r = run(join(scripts, 'validate-encoded-picture.mjs'), [root, candidate]);
  assert.notEqual(r.code, 0); assert.match(r.out, /edited after it was written/);
});

for (const [field, value] of [['persona', 'owner'], ['scenarioId', 'other'], ['sourceRevision', 'old'], ['servedRevision', 'old'], ['baseUrl', 'http://127.0.0.1:1']]) {
  test(`product picture refuses a take with the wrong ${field}`, { skip }, () => {
    const root = job(`wrong-${field}`);
    const r0 = readJson(receiptOf(root)); delete r0.clips.S02.provenance;
    putReceipt(root, r0, { ...IDENTITY, [field]: value });
    const r = gate('validate-product-picture.mjs', root);
    assert.equal(r.code, 1, r.out); assert.match(r.out, new RegExp(`${field} .* is not the proven`));
  });
}
for (const field of ['persona', 'scenarioId', 'sourceRevision', 'servedRevision', 'baseUrl', 'kitVersion']) {
  test(`product picture refuses a take with no ${field}`, { skip }, () => {
    const root = job(`no-${field}`);
    const r0 = readJson(receiptOf(root)); delete r0.clips.S02.provenance;
    putReceipt(root, r0, { ...IDENTITY, [field]: null });
    const r = gate('validate-product-picture.mjs', root);
    assert.equal(r.code, 1, r.out); assert.match(r.out, new RegExp(`records no ${field}`));
  });
}

for (const field of ['personaId', 'sourceRevision', 'servedRevision', 'baseUrl']) test(`a proof that names no ${field} cannot vouch for a take`, { skip }, () => {
  const root = job(`proof-no-${field}`); const p = join(root, 'evidence', 'demo-scenario-proof.json');
  const proof = readJson(p); delete proof[field]; write(p, proof);
  const r = gate('validate-product-picture.mjs', root);
  assert.equal(r.code, 1, r.out); assert.match(r.out, new RegExp(`proof names no ${field}`));
  rmSync(receiptOf(root));
  const rec = record(root, SCENES());
  assert.notEqual(rec.code, 0); assert.match(rec.out, new RegExp(`proof names no ${field}`)); assert.equal(rec.receipt, null);
});

test('a take recorded with --skip-preflight is refused on a viewer-facing job', { skip }, () => {
  const root = fresh('skipped-preflight');
  assert.equal(record(root, SCENES(), ['--skip-preflight']).code, 0);
  const r = gate('validate-product-picture.mjs', root);
  assert.equal(r.code, 1); assert.match(r.out, /--skip-preflight/);
});

test('the served revision is read off the page, not declared', { skip }, () => {
  const scenes = SCENES('', "export const identity = async () => ({ persona: 'parent' });").replace("provenance: {", "provenance: { servedRevision: 'f1c30ee967',");
  const r = record(fresh('declared-served'), scenes);
  assert.equal(r.code, 1, r.out); assert.match(r.receipt.clips.S02.error, /no servedRevision/);
});

test('a BOM in job.json does not fail the pre-flight', { skip }, () => {
  const root = fresh('bom'); const p = join(root, 'job.json');
  writeFileSync(p, `\uFEFF${JSON.stringify(readJson(p))}`);
  const r = record(root, SCENES());
  assert.equal(r.code, 0, r.out);
});

test('the kit version is known when the recorder runs from _shared/tools', { skip }, () => {
  const tools = join(scratch, '_shared', 'tools');
  cpSync(join(recorder(), 'screencast'), tools, { recursive: true });
  copyFileSync(join(pkg, 'plugin.json'), join(tools, 'plugin.json'));
  const root = fresh('shared-tools'); write(join(root, 'capture', 'scenes.mjs'), SCENES());
  const r = spawnSync(process.execPath, [join(tools, 'record-job.mjs'), root, '--recast', '--no-recast'], { encoding: 'utf8', windowsHide: true, env: { ...process.env, FAKE_RAW: source } });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.equal(readJson(receiptOf(root)).clips.S02.provenance.kitVersion, readJson(join(pkg, 'plugin.json')).version);
});

test('a viewer-facing job without a scenario proof is refused, a draft is not', { skip }, () => {
  const root = job('no-proof'); rmSync(join(root, 'evidence'), { recursive: true });
  const r = gate('validate-product-picture.mjs', root);
  assert.equal(r.code, 1); assert.match(r.out, /demo-scenario-proof\.json/);
  const draft = job('draft', { job: { intent: 'draft' } }); rmSync(join(draft, 'evidence'), { recursive: true });
  const d = gate('validate-product-picture.mjs', draft);
  assert.equal(d.code, 0, d.out);
});

test('an unsealed receipt passes only with a written reason, and says so', { skip }, () => {
  const root = job('legacy', { job: { legacyReceiptAllowed: 'recorded on 4.2.0 before receipts were sealed' } });
  edit(root, (r) => { delete r.contentSha256; r.schemaVersion = '1.0.0'; delete r.clips.S02.provenance; });
  const r = gate('validate-product-picture.mjs', root);
  assert.equal(r.code, 0, r.out); assert.match(r.out, /recorded on 4\.2\.0/);
  write(join(root, 'job.json'), { ...readJson(join(root, 'job.json')), legacyReceiptAllowed: true });
  assert.equal(gate('validate-product-picture.mjs', root).code, 1);
});

test('product picture refuses a manifest that names a file which is not there', { skip }, () => {
  const root = job('overlay');
  write(join(root, 'capture', 'manifest.json'), { clips: [{ id: 'S02', file: 'clips/S02.webm', segments: ['S02'], overlay: 'overlays/S02.png' }, { id: 'card', file: 'clips/card.png', segments: ['S03'] }] });
  const r = gate('validate-product-picture.mjs', root);
  assert.equal(r.code, 1); assert.match(r.out, /overlays\/S02\.png/); assert.match(r.out, /clips\/card\.png/);
});

test('product picture leaves a report bound to the receipt and the manifest', { skip }, () => {
  const root = job('report');
  assert.equal(gate('validate-product-picture.mjs', root).code, 0);
  const rep = readJson(join(root, 'qa', 'product-picture.json'));
  assert.equal(rep.ok, true);
  assert.equal(rep.inputs.receipt.sha256, sha(receiptOf(root)));
  assert.equal(rep.inputs.manifest.sha256, sha(join(root, 'capture', 'manifest.json')));
  edit(root, (r) => { r.baseUrl = 'x'; });
  assert.equal(gate('validate-product-picture.mjs', root).code, 1);
  assert.equal(readJson(join(root, 'qa', 'product-picture.json')).ok, false);
});

// ---- the videoLead need is met in the manifest, not the receipt
const manifestWith = (root, videoLead) => write(join(root, 'capture', 'manifest.json'), { clips: [{ id: 'S02', file: 'clips/S02.webm', segments: ['S02'], videoLead }] });
const clickTime = (root) => {
  const r = gate('build-cue-sheet.mjs', root);
  const p = join(root, 'plan', 'cue-sheet.json');
  assert.ok(existsSync(p), r.out);
  return readJson(p).beats[0].actions.find((a) => a.kind === 'click').clip_time;
};
test('a manifest videoLead moves the named action and leaves the receipt alone', { skip }, () => {
  const root = job('lead');
  write(join(root, 'story', 'cue-plan.json'), { beats: { S02: { actions: [{ label: 'Save', keywords: ['save'] }] } } });
  const before = sha(receiptOf(root));
  const plain = clickTime(root);
  manifestWith(root, [{ label: 'Save', seconds: 0.26, reason: 'the press paints 0.26 s before the logged click' }]);
  const led = clickTime(root);
  assert.ok(Math.abs(plain - led - 0.26) < 0.0011, `${plain} ${led}`);
  assert.equal(sha(receiptOf(root)), before);
  assert.equal(gate('validate-product-picture.mjs', root).code, 0);
});
for (const [name, lead] of [['no reason', [{ label: 'Save', seconds: 0.2 }]], ['too long a lead', [{ label: 'Save', seconds: 0.6, reason: 'r' }]], ['an unknown label', [{ label: 'Nope', seconds: 0.2, reason: 'r' }]], ['a bare number', 0.2]]) {
  test(`product picture refuses a videoLead with ${name}`, { skip }, () => {
    const root = job(`lead-${name.replace(/\W/g, '')}`); manifestWith(root, lead);
    const r = gate('validate-product-picture.mjs', root);
    assert.equal(r.code, 1); assert.match(r.out, /videoLead/);
  });
}
test('a videoLead corrects a press and never a pointer arrival', () => {
  const lead = [{ label: 'Save', seconds: 0.2, reason: 'r' }];
  const point = { type: 'point', label: 'Save', t: 1 };
  const press = { type: 'click', label: 'Save', t: 2 };
  assert.match(videoLeadProblems('S02', lead, [point]).join(), /videoLead label "Save" is not a recorded press/);
  // A pointer arrival that shares the press's label keeps its recorded time: receiptSemantics matches on it.
  assert.deepEqual(videoLeadProblems('S02', lead, [point, press]), []);
  assert.equal(leadSeconds(lead, point), 0);
  assert.equal(leadSeconds(lead, press), 0.2);
});

// ---- recorder, with the browser replaced and everything else real
const GOOD_IDENTITY = "export const identity = async () => ({ persona: 'parent', servedRevision: 'f1c30ee967' });";
const SCENES = (body = '', identity = GOOD_IDENTITY) => `
export const order = ['S02'];
export const options = { baseUrl: '${IDENTITY.baseUrl}', provenance: { sourceRevision: 'f1c30ee967' } };
${identity}
export const scenes = { async S02(h) { ${body} } };
`;
const FAKE_LIB = `
import fs from 'node:fs'; import path from 'node:path';
export async function startRecording(id) { const rawDir = path.resolve('raw', id); fs.mkdirSync(rawDir, { recursive: true }); return { h: {}, page: { screenshot: async () => {} }, beats: {}, rawDir, viewport: { width: 640, height: 360 } }; }
export async function finishRecording(rec) { const webm = path.join(rec.rawDir, 'page.webm'); fs.copyFileSync(process.env.FAKE_RAW, webm); const tracePath = path.join(rec.rawDir, 'trace.zip'); fs.writeFileSync(tracePath, 'trace');
  return { tracePath, webm, rawDir: rec.rawDir, beats: [], events: [{ type: 'click', t: 1, label: 'Save' }], expectations: [], summary: { pointerMoves: 3, clicks: 1, taps: 0, keystrokes: 0, scrolls: 0, expectations: 1, expectationsObserved: 1, expectationsFailed: [] } }; }
export async function renderRecast(rawDir, out) { fs.copyFileSync(path.join(rawDir, 'page.webm'), out); fs.appendFileSync(out, 'recast'); }
`;
let kit = null;
function recorder() {
  if (kit) return kit;
  kit = join(scratch, '_kit');
  cpSync(join(pkg, 'kit', 'screencast'), join(kit, 'screencast'), { recursive: true });
  copyFileSync(join(pkg, 'kit', 'package.json'), join(kit, 'package.json'));
  for (const f of readdirSync(scripts).filter((x) => x.endsWith('.mjs'))) if (!existsSync(join(kit, 'screencast', f))) copyFileSync(join(scripts, f), join(kit, 'screencast', f));
  writeFileSync(join(kit, 'screencast', 'record-lib.mjs'), FAKE_LIB);
  return kit;
}
function record(root, scenes, args = ['--no-recast']) {
  write(join(root, 'capture', 'scenes.mjs'), scenes);
  const r = spawnSync(process.execPath, [join(recorder(), 'screencast', 'record-job.mjs'), root, '--recast', ...args], { encoding: 'utf8', windowsHide: true, env: { ...process.env, FAKE_RAW: source } });
  return { code: r.status, out: `${r.stdout}${r.stderr}`, receipt: existsSync(receiptOf(root)) ? readJson(receiptOf(root)) : null };
}
const fresh = (name, over) => { const root = job(name, over); rmSync(receiptOf(root)); return root; };

test('a good take exits 0 with a sealed receipt that names who, what and which kit', { skip }, () => {
  const r = record(fresh('rec-ok'), SCENES());
  assert.equal(r.code, 0, r.out);
  assert.equal(receiptIntegrity(r.receipt).state, 'sealed');
  const { kitVersion, ...p } = r.receipt.clips.S02.provenance;
  assert.deepEqual(p, { persona: 'parent', scenarioId: 'weeknight', sourceRevision: 'f1c30ee967', servedRevision: 'f1c30ee967', baseUrl: IDENTITY.baseUrl });
  assert.equal(kitVersion, readJson(join(pkg, 'kit', 'package.json')).version);
});
test('a failed scene exits nonzero and still records the failure', { skip }, () => {
  const r = record(fresh('rec-fail'), SCENES("throw new Error('no button');"));
  assert.equal(r.code, 1, r.out); assert.equal(r.receipt.clips.S02.valid, false); assert.match(r.out, /FAILED.*S02/);
});
test('a scene id with no scene function exits nonzero', { skip }, () => {
  const r = record(fresh('rec-missing'), SCENES(), ['S09', '--no-recast', '--skip-preflight']);
  assert.equal(r.code, 1); assert.match(r.out, /FAILED.*S09/);
});
test('the wrong persona on the live page makes the take invalid and exits nonzero', { skip }, () => {
  const r = record(fresh('rec-persona'), SCENES('', "export const identity = async () => ({ persona: 'owner', servedRevision: 'f1c30ee967' });"));
  assert.equal(r.code, 1, r.out); assert.equal(r.receipt.clips.S02.valid, false); assert.match(r.receipt.clips.S02.error, /persona/);
});
test('a viewer-facing job without identity() is refused before recording, a draft is not', { skip }, () => {
  const r = record(fresh('rec-noid'), SCENES('', ''));
  assert.notEqual(r.code, 0); assert.match(r.out, /identity/); assert.equal(r.receipt, null);
  const d = record(fresh('rec-draft', { job: { intent: 'draft' } }), SCENES('', ''));
  assert.equal(d.code, 0, d.out);
});
test('the pre-flight refuses a viewer-facing recording without a passing scenario proof', { skip }, () => {
  const root = fresh('rec-noproof'); rmSync(join(root, 'evidence'), { recursive: true });
  const r = record(root, SCENES());
  assert.notEqual(r.code, 0); assert.match(r.out, /demo-scenario-proof\.json/); assert.equal(r.receipt, null);
  const bad = fresh('rec-badproof'); write(join(bad, 'evidence', 'runtime-outcome.json'), { status: 'FAIL' });
  const b = record(bad, SCENES());
  assert.notEqual(b.code, 0); assert.equal(b.receipt, null);
});
test('the recorder will not add a take to an edited receipt', { skip }, () => {
  const root = fresh('rec-launder'); assert.equal(record(root, SCENES()).code, 0);
  edit(root, (r) => { r.clips.S02.actions[0].t = 0.2; });
  const r = record(root, SCENES());
  assert.notEqual(r.code, 0); assert.match(r.out, /edited after it was written/);
});

test('--recast-only finishes a take recorded elsewhere, reseals it and opens no browser', { skip }, () => {
  const root = fresh('recast-only'); assert.equal(record(root, SCENES()).code, 0);
  const before = readJson(receiptOf(root)).clips.S02;
  assert.equal(gate('validate-product-picture.mjs', root).code, 1);
  const r = record(root, SCENES("throw new Error('a browser was opened');"), ['--recast-only']);
  assert.equal(r.code, 0, r.out);
  const after = r.receipt.clips.S02;
  assert.equal(receiptIntegrity(r.receipt).state, 'sealed');
  assert.equal(after.sha256, sha(join(root, 'capture', 'clips', 'S02.webm'))); assert.notEqual(after.sha256, before.sha256);
  assert.match(after.recast, /^(full|noZoom)$/); assert.deepEqual(after.provenance, before.provenance); assert.deepEqual(after.actions, before.actions);
});
test('--recast-only refuses a raw take that is not the recorded one', { skip }, () => {
  const root = fresh('recast-raw'); assert.equal(record(root, SCENES()).code, 0);
  writeFileSync(join(root, 'capture', 'raw', 'S02', 'page.webm'), 'other');
  const r = record(root, SCENES(), ['--recast-only']);
  assert.notEqual(r.code, 0); assert.match(r.out, /does not match the receipt/);
});

test('the backfill tools keep a sealed receipt sealed and refuse an edited one', { skip }, () => {
  const root = job('backfill'); mkdirSync(join(root, 'capture', 'raw'), { recursive: true });
  assert.equal(run(join(scripts, 'backfill-capture-receipt.mjs'), [root]).code, 0);
  assert.equal(receiptIntegrity(readJson(receiptOf(root))).state, 'sealed');
  edit(root, (r) => { r.baseUrl = 'x'; });
  const r = run(join(scripts, 'backfill-capture-receipt.mjs'), [root]);
  assert.notEqual(r.code, 0); assert.match(r.out, /edited after it was written/);
});
test('the marketing generator refuses a clip from an edited receipt', { skip }, async () => {
  const { resolveClip } = await import('../kit/marketing/lib/stages/capture.mjs');
  const root = job('mvg-source');
  const beat = { id: 'B1', ui: { sourceJob: root, clipId: 'S02' } };
  assert.equal(resolveClip({ specDir: root }, beat).entry.file, 'clips/S02.webm');
  edit(root, (r) => { r.clips.S02.actions[1].tStart = 0.6; });
  assert.throws(() => resolveClip({ specDir: root }, beat), /edited after it was written/);
});
test('the proof fixture satisfies the scenario gate', () => {
  const root = join(scratch, 'proof'); write(join(root, 'job.json'), { kind: 'product-screencast', intent: 'viewer-facing' });
  write(join(root, 'story', 'storyboard.json'), { scenarioId: 'weeknight', cta: 'c', beats: [{ id: 'S02' }] }); writeProof(root);
  assert.equal(gate('validate-demo-scenario.mjs', root).code, 0);
});
