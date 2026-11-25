// write-scenario-proof.mjs with the browser replaced by a small page model and everything else real, including the scenario gate.
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, cpSync, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { IDENTITY, readJson, sha, write } from './fixtures/capture-job.mjs';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const scratch = mkdtempSync(join(tmpdir(), 'scenario-proof-'));
after(() => rmSync(scratch, { recursive: true, force: true }));
const kit = join(scratch, 'kit');
cpSync(join(pkg, 'kit', 'screencast'), join(kit, 'screencast'), { recursive: true });
copyFileSync(join(pkg, 'scripts', 'validate-demo-scenario.mjs'), join(kit, 'screencast', 'validate-demo-scenario.mjs'));
write(join(kit, 'node_modules', 'playwright', 'package.json'), { name: 'playwright', version: '0.0.0', type: 'module', exports: './index.js' });
write(join(kit, 'node_modules', 'playwright', 'index.js'), `
const world = JSON.parse(process.env.WORLD);
const locator = (page, what) => ({ first() { return this; }, waitFor: async () => { if (!page.visible.has(what)) throw new Error('timeout'); }, click: async () => { page.visible.add(world.results[what]); } });
export const chromium = { launch: async () => ({ close: async () => {}, newContext: async (o) => ({ newPage: async () => {
  const page = { visible: new Set(), signedIn: Boolean(o.storageState), reads: 0, on() {}, url: () => page.at,
    goto: async (u) => { page.at = world.landsOn || u; if (page.signedIn || world.openToAll) page.visible.add('guarded'); return { status: () => world.status || 200 }; },
    get: (what) => locator(page, what), identity: () => ({ persona: world.persona, servedRevision: world.revisions[Math.min(page.reads++, world.revisions.length - 1)] }) };
  return page; } }) }) };
`);
const WORLD = { persona: 'parent', revisions: ['f1c30ee967'], results: { Save: 'thanks' } };
const PROVE = "await act('Save', () => page.get('Save').click()); await check('thanks', page.get('thanks'));";

let n = 0;
function run({ world = {}, prove = PROVE, scenario = {}, root = join(scratch, `job-${n++}`), signIn = 'export const signIn = async (page) => { page.signedIn = true; };' } = {}) {
  write(join(root, 'job.json'), { kind: 'product-screencast', intent: 'viewer-facing', repositoryWritePolicy: 'read-only' });
  write(join(root, 'story', 'storyboard.json'), { scenarioId: 'weeknight', cta: 'Open the portal', beats: [{ id: 'S02' }] });
  write(join(root, 'capture', 'scenes.mjs'), `export const options = { baseUrl: '${IDENTITY.baseUrl}', provenance: { sourceRevision: 'f1c30ee967' } };\nexport const identity = async (page) => page.identity();`);
  write(join(root, 'capture', 'scenario.mjs'), `export const scenario = ${JSON.stringify({ scenarioId: 'weeknight', synthetic: true, persona: 'Parent, synthetic clinic', personaId: 'parent', problem: 'p', start: '/parent',
    hero: { segmentId: 'S02', beforeState: 'a', action: 'b', visibleResult: 'c' }, outcome: { statement: 's', evidence: 'e' }, continuity: { entities: [{ type: 'clinic', id: 'demo' }] }, ...scenario })};
export const guarded = (page) => page.get('guarded');
${signIn}
export const prove = async ({ page, act, check }) => { ${prove} };`);
  const r = spawnSync(process.execPath, [join(kit, 'screencast', 'write-scenario-proof.mjs'), root], { encoding: 'utf8', windowsHide: true, env: { ...process.env, WORLD: JSON.stringify({ ...WORLD, ...world }) } });
  const ev = (f) => { const p = join(root, 'evidence', f); return existsSync(p) ? readJson(p) : null; };
  return { root, code: r.status, out: `${r.stdout}${r.stderr}`, proof: ev('demo-scenario-proof.json'), handoff: ev('readiness-handoff.json'), outcome: ev('runtime-outcome.json') };
}
const gate = (root) => spawnSync(process.execPath, [join(pkg, 'scripts', 'validate-demo-scenario.mjs'), root], { encoding: 'utf8', windowsHide: true }).status;

test('a live run that passes writes a proof the gate accepts, bound by hash', () => {
  const r = run();
  assert.equal(r.code, 0, r.out);
  assert.equal(gate(r.root), 0);
  for (const [field, value] of Object.entries({ personaId: 'parent', scenarioId: 'weeknight', sourceRevision: 'f1c30ee967', servedRevision: 'f1c30ee967', baseUrl: IDENTITY.baseUrl })) assert.equal(r.proof[field], value);
  assert.equal(r.proof.source.sha256, sha(join(r.root, 'evidence', 'readiness-handoff.json')));
  assert.equal(r.handoff.runtimeOutcome.sha256, sha(join(r.root, 'evidence', 'runtime-outcome.json')));
  assert.deepEqual(r.handoff.workflow, { authenticated: true, actionResultObserved: true });
});
for (const [name, over, why] of [
  ['a page anyone can open', { world: { openToAll: true } }, /signed-out browser is refused/],
  ['a server that fails the signed-out request', { world: { status: 503 } }, /answered the signed-out request/],
  ['a sign-in that does not reach the page', { signIn: 'export const signIn = async () => {};' }, /guarded page is shown/],
  ['another origin', { world: { landsOn: 'https://other.example/parent' } }, /served from baseUrl/],
  ['the wrong persona', { world: { persona: 'owner' } }, /names persona parent/],
  ['no served revision', { world: { revisions: [''] } }, /served revision/],
  ['a deploy in the middle of the run', { world: { revisions: ['f1c30ee967', 'other'] } }, /after the workflow: the page names its served revision/],
  ['a result that never appears', { world: { results: { Save: 'nothing' } } }, /not observed: thanks/],
  ['a workflow that acts and checks nothing after', { prove: "await act('Save', () => page.get('Save').click());" }, /last act has an observed result/],
  ['a workflow that never acts', { prove: "await check('guarded', page.get('guarded'));" }, /last act has an observed result/],
]) test(`${name} writes NOT-READY and no proof`, () => {
  const r = run(over);
  assert.equal(r.code, 1, r.out); assert.match(r.out, why);
  assert.equal(r.proof, null); assert.equal(r.handoff.status, 'NOT-READY'); assert.equal(r.outcome.status, 'FAIL');
});
test('a failed rerun invalidates the earlier proof', () => {
  const { root } = run();
  assert.equal(run({ root, world: { persona: 'owner' } }).code, 1);
  assert.equal(gate(root), 1);
});
test('undeclared facts are refused before a browser opens', () => {
  for (const scenario of [{ synthetic: false }, { personaId: '' }, { scenarioId: undefined }, { start: undefined }]) { const r = run({ scenario }); assert.equal(r.code, 2, JSON.stringify(scenario)); assert.equal(r.outcome, null); }
  const r = run({ signIn: '' }); assert.equal(r.code, 2); assert.match(r.out, /signIn/);
});
test('a proof that does not fit the storyboard fails the gate it runs', () => {
  const r = run({ scenario: { hero: { segmentId: 'S99', beforeState: 'a', action: 'b', visibleResult: 'c' } } });
  assert.equal(r.code, 1); assert.match(r.out, /S99/);
});
