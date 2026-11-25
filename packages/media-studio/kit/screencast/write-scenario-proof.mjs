// Prove the workflow a viewer-facing product job is about to film, on the running product, and write the scenario proof (gate 5).
//
// Usage: node write-scenario-proof.mjs <jobRoot> [--headed]
// Reads  <jobRoot>/capture/scenes.mjs    options (baseUrl, provenance.sourceRevision, storageState, viewport ...) and identity(page), as record-job.mjs does
//        <jobRoot>/capture/scenario.mjs  (its storyboard must carry the same scenarioId):
//   export const scenario = { scenarioId, synthetic: true, persona, personaId, problem, start: '/path',
//     hero: { segmentId, beforeState, action, visibleResult }, outcome: { statement, evidence }, continuity: { entities: [{ type, id }] } };
//   export const guarded = (page) => locator;               // shown at scenario.start only to the signed-in persona
//   export const signIn = async (page) => {};               // optional; options.storageState works too
//   export const prove = async ({ page, act, check }) => {  // the filmed workflow, read back at the end (reload, then check)
//     await act('Save', () => page.getByRole('button', { name: 'Save' }).click()); await check('the thank you', page.getByText('Thank you')); };
// Writes <jobRoot>/evidence/runtime-outcome.json, readiness-handoff.json and, on PASS only, demo-scenario-proof.json; then runs
// validate-demo-scenario.mjs. A failed run leaves NOT-READY, so an earlier proof no longer validates. Exit 0 only on a passing proof.
// Nothing here is typed in by hand: PASS needs `guarded` refused to a signed-out browser and shown to the signed-in one, identity()
// naming the persona before and after with one served revision, and a check observed after the last act.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from 'playwright';
import { proofProblems } from './receipt-lib.mjs';

const [jobRootArg] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
if (!jobRootArg) { console.error('usage: node write-scenario-proof.mjs <jobRoot> [--headed]'); process.exit(2); }
const root = path.resolve(jobRootArg);
const cap = path.join(root, 'capture');
const load = (name) => import(pathToFileURL(path.join(cap, name)).href);
const { options = {}, identity } = await load('scenes.mjs');
const { scenario, guarded, signIn, prove } = await load('scenario.mjs');
const sha = (file) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const write = (rel, data) => { const file = path.join(root, rel); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n'); return sha(file); };

const declared = { personaId: scenario?.personaId, sourceRevision: options.provenance?.sourceRevision, baseUrl: options.baseUrl };
const problems = proofProblems({ ...declared, scenarioId: scenario?.scenarioId, servedRevision: 'read live' });
for (const [name, fn] of Object.entries({ identity, guarded, prove })) if (typeof fn !== 'function') problems.push(`${name === 'identity' ? 'scenes' : 'scenario'}.mjs must export ${name}`);
if (scenario?.synthetic !== true) problems.push('scenario.synthetic must be true');
if (!scenario?.start) problems.push('scenario.start must be the path of the guarded page');
if (!signIn && !options.storageState) problems.push('scenario.mjs must export signIn, or scenes.mjs options.storageState');
if (problems.length) { console.error(problems.join('\n')); process.exit(2); }

const observations = [], apiWrites = [];
let servedRevision = null, error = null;
const start = new URL(scenario.start, options.baseUrl).href;
const see = (kind, step, observed) => { observations.push({ kind, step, observed, at: new Date().toISOString() }); if (!observed) throw new Error(`not observed: ${step}`); };
const shown = (locator, timeout) => locator.first().waitFor({ state: 'visible', timeout }).then(() => true, () => false);
const act = async (step, fn) => { await fn(); see('act', step, true); };
const check = async (step, locator, { timeout = 15000 } = {}) => see('check', step, await shown(locator, timeout));
const context = { viewport: options.viewport, deviceScaleFactor: options.deviceScaleFactor, colorScheme: options.colorScheme, timezoneId: options.timezoneId, extraHTTPHeaders: options.extraHTTPHeaders };
const who = async (page, when) => {
  const seen = (await identity(page)) || {};
  see('identity', `${when}: the page names persona ${scenario.personaId}`, seen.persona === scenario.personaId);
  see('identity', `${when}: the page names its served revision`, typeof seen.servedRevision === 'string' && seen.servedRevision.trim() !== '' && (servedRevision ?? seen.servedRevision) === seen.servedRevision);
  servedRevision = seen.servedRevision;
};

const browser = await chromium.launch({ headless: !process.argv.includes('--headed') });
try {
  const out = await (await browser.newContext({ ...context, extraHTTPHeaders: undefined })).newPage();
  const response = await out.goto(start);
  // An unreachable or failing server also hides the page; that is not a refusal.
  see('signed-out', 'the product answered the signed-out request', response !== null && response.status() < 500);
  see('signed-out', 'a signed-out browser is refused the guarded page', !(await shown(guarded(out), 5000)));

  const page = await (await browser.newContext({ ...context, storageState: options.storageState ? path.resolve(cap, options.storageState) : undefined })).newPage();
  page.on('response', (r) => { if (r.request().method() !== 'GET') apiWrites.push({ method: r.request().method(), path: new URL(r.url()).pathname.replace(/[^/]{16,}/g, '<id>'), status: r.status() }); });
  if (signIn) await signIn(page);
  await page.goto(start);
  await check('signed in: the guarded page is shown', guarded(page), { timeout: 30000 });
  see('signed-in', 'the page is served from baseUrl', new URL(page.url()).origin === new URL(options.baseUrl).origin);
  await who(page, 'before the workflow');
  const from = observations.length;
  await prove({ page, act, check });
  const kinds = observations.slice(from).map((o) => o.kind);
  see('workflow', 'the last act has an observed result', kinds.includes('act') && kinds.lastIndexOf('check') > kinds.lastIndexOf('act'));
  await who(page, 'after the workflow');
} catch (e) { error = String(e.message).split('\n')[0].slice(0, 300); } finally { await browser.close(); }

const pass = error === null, verifiedAt = new Date().toISOString();
const facts = { scenarioId: scenario.scenarioId, personaId: scenario.personaId, sourceRevision: declared.sourceRevision, servedRevision, baseUrl: options.baseUrl };
const outcome = write('evidence/runtime-outcome.json', { status: pass ? 'PASS' : 'FAIL', error, ...facts, scenarioFileSha256: sha(path.join(cap, 'scenario.mjs')), observations, apiWrites, verifiedAt });
const observed = (kind) => observations.some((o) => o.kind === kind) && observations.filter((o) => o.kind === kind).every((o) => o.observed);
const handoff = write('evidence/readiness-handoff.json', { status: pass ? 'DEMO-READY' : 'NOT-READY', ...facts, generator: 'media-studio/write-scenario-proof',
  workflow: { authenticated: observed('signed-out') && observed('signed-in') && observed('identity'), actionResultObserved: observed('workflow') },
  runtimeOutcome: { path: 'evidence/runtime-outcome.json', sha256: outcome, status: pass ? 'PASS' : 'FAIL' },
  limits: 'Written by the film job from one live run. Covers this workflow at this base URL and revision, not other environments.', verifiedAt });
if (!pass) { console.log(`FAIL ${error}`); process.exit(1); }
const { scenarioId, synthetic, persona, personaId, problem, hero, outcome: result, continuity } = scenario;
write('evidence/demo-scenario-proof.json', { scenarioId, synthetic, persona, personaId, problem, sourceRevision: declared.sourceRevision, servedRevision, baseUrl: options.baseUrl, hero, outcome: result, continuity,
  source: { kind: 'product-readiness-handoff', status: 'DEMO-READY', path: 'evidence/readiness-handoff.json', sha256: handoff, verifiedAt } });
const here = path.dirname(fileURLToPath(import.meta.url));
const gate = [path.join(here, 'validate-demo-scenario.mjs'), path.join(here, '..', '..', 'scripts', 'validate-demo-scenario.mjs')].find((f) => fs.existsSync(f));
if (!gate) { console.error('validate-demo-scenario.mjs not found (deploy list)'); process.exit(1); }
process.exit(spawnSync(process.execPath, [gate, root], { stdio: 'inherit', windowsHide: true }).status ?? 1);
