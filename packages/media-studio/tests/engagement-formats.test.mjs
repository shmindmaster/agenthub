import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, cpSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { checkStory } from '../scripts/check-story.mjs';
import { COMMUNICATION_PROFILES, inspectCommunication, resolveFilmType } from '../kit/marketing/lib/story-profiles.mjs';
import { validate } from '../kit/marketing/lib/schema.mjs';

const pkg = join(dirname(fileURLToPath(import.meta.url)), '..');
const fixtureDir = join(pkg, 'tests', 'fixtures', 'engagement');
const load = (name) => JSON.parse(readFileSync(join(fixtureDir, `${name}.json`), 'utf8'));
const clone = (value) => JSON.parse(JSON.stringify(value));
const NEW = ['pitch', 'proposal', 'status-update', 'kickoff', 'final-readout', 'value-review'];
const OLD = ['consulting-demo', 'technical-walkthrough', 'product-update'];

const findings = (spec) => inspectCommunication(spec, { id: 'main', targetSeconds: spec.targetSeconds, beats: spec.beats }, (b) => b.minSeconds || 5);
const rules = (spec) => findings(spec).map((f) => f.rule);
const beatOf = (spec, section) => spec.beats.find((b) => b.section === section);
const without = (spec, section) => { const s = clone(spec); s.beats = s.beats.filter((b) => b.section !== section); return s; };
const claimOf = (b) => b.evidenceClaims[0];

// ---- the table ---------------------------------------------------------------------------------------------------

test('six engagement profiles map to existing film types with the declared ceilings and sections', () => {
  const expected = {
    pitch: ['founder-pitch', 180, ['recommendation', 'why-change', 'cost-of-inaction', 'new-way', 'why-us', 'options', 'ask']],
    proposal: ['explainer', 300, ['recommendation', 'understanding', 'approach', 'team', 'timeline', 'options', 'investment', 'next-step']],
    'status-update': ['internal-update', 120, ['status', 'done', 'next', 'risks', 'decisions', 'plan-vs-actual']],
    kickoff: ['explainer', 240, ['objectives', 'scope', 'governance', 'team', 'timeline', 'risks', 'first-30-days']],
    'final-readout': ['explainer', 480, ['recommendation', 'findings', 'roadmap', 'business-case', 'next-step']],
    'value-review': ['explainer', 180, ['baseline', 'realized', 'evidence', 'next-step']],
  };
  for (const [id, [filmType, ceiling, sections]] of Object.entries(expected)) {
    const p = COMMUNICATION_PROFILES[id];
    assert.ok(p, `${id} is declared`);
    assert.equal(p.filmType, filmType, id);
    assert.equal(p.ceilingSeconds, ceiling, id);
    assert.equal(p.proofMoments, 0, `${id} does not force a product UI proof`);
    assert.deepEqual(p.sections, sections, id);
    assert.equal(resolveFilmType({ communicationProfile: id }, {}, 'fictional-story').id, filmType, id);
  }
  assert.equal(COMMUNICATION_PROFILES['status-update'].cadences.weekly.ceilingSeconds, 90);
  assert.deepEqual(COMMUNICATION_PROFILES['status-update'].cadences.steering.sections, ['plan-vs-actual', 'risks', 'decisions', 'next']);
});

test('the three existing profiles are unchanged, and ignore the new section field', () => {
  assert.deepEqual(Object.fromEntries(OLD.map((id) => [id, COMMUNICATION_PROFILES[id]])), {
    'consulting-demo': { filmType: 'feature-demo', proofMoments: 3 },
    'technical-walkthrough': { filmType: 'tutorial', proofMoments: 1 },
    'product-update': { filmType: 'internal-update', proofMoments: 1 },
  });
  // Recorded from the code before this change: a deliberately broken brief with an invalid section on every beat.
  const beat = (id) => ({ id, storyRole: 'demonstration', kind: 'ui', minSeconds: 5, section: 'bogus', actionTitle: `Short ${id}`, evidenceClaims: [] });
  const base = ['brief.primaryAudience', 'brief.viewerDecision', 'brief.primaryTakeaway', 'problem-status', 'next-step', 'duration', 'captions', 'audio-direction', 'action-title', 'argument-proof', 'claim-scope', 'action-title', 'argument-proof', 'claim-scope', 'proof-moments', 'limitations'].map((r) => `communication.${r}`);
  for (const id of OLD) {
    const got = rules({ communicationProfile: id, maxDurationSeconds: 3, targetSeconds: 40, beats: [beat('a'), beat('b')] });
    assert.deepEqual(got, id === 'technical-walkthrough' ? [...base, 'communication.integration-flow', 'communication.integration-status'] : base, id);
  }
});

test('every fixture is a complete brief that passes the existing story gate and the profile checks', () => {
  const files = readdirSync(fixtureDir).filter((f) => f.endsWith('.json')).map((f) => f.replace(/\.json$/, '')).sort();
  assert.deepEqual(files, [...NEW].sort());
  for (const id of NEW) {
    const spec = load(id);
    assert.equal(spec.communicationProfile, id);
    assert.deepEqual(findings(spec), [], id);
    const report = checkStory(spec);
    assert.equal(report.ok, true, `${id}: ${JSON.stringify(report.cuts[0].failures)}`);
    assert.equal(report.cuts[0].filmType, COMMUNICATION_PROFILES[id].filmType);
    assert.ok(Math.max(report.cuts[0].seconds, 0) <= spec.maxDurationSeconds, id);
  }
});

// ---- sections ----------------------------------------------------------------------------------------------------

test('a required section that is absent is named; an optional one may be omitted', () => {
  for (const id of NEW) {
    const spec = load(id);
    const profile = COMMUNICATION_PROFILES[id];
    for (const section of profile.sections.filter((s) => !(profile.optional || []).includes(s))) {
      const trimmed = without(spec, section);
      const hit = findings(trimmed).find((f) => f.rule === 'communication.section.missing' && f.message.includes(section));
      assert.ok(hit, `${id} without ${section}`);
    }
  }
  assert.ok(!rules(without(load('pitch'), 'options')).some((r) => r.startsWith('communication.section')), 'pitch options is optional');
  assert.ok(!rules(without(load('proposal'), 'options')).some((r) => r.startsWith('communication.section')), 'proposal options is optional');
});

test('sections must follow the profile order; a section may span consecutive beats but not return', () => {
  const spec = load('kickoff');
  const swapped = clone(spec);
  [swapped.beats[1].section, swapped.beats[2].section] = [swapped.beats[2].section, swapped.beats[1].section];
  assert.ok(rules(swapped).includes('communication.section.order'));
  const returning = clone(load('final-readout'));
  returning.beats.splice(4, 0, { ...clone(returning.beats[1]), id: 'again', actionTitle: 'A finding returns after the roadmap has begun.' });
  assert.ok(rules(returning).includes('communication.section.order'), 'findings after the roadmap started');
  assert.deepEqual(rules(load('final-readout')), [], 'two consecutive findings beats are fine');
});

test('an unknown section names the allowed values', () => {
  const spec = load('proposal');
  spec.beats[2].section = 'approch';
  const hit = findings(spec).find((f) => f.rule === 'communication.section.unknown');
  assert.ok(hit);
  assert.match(hit.message, /approch/);
  for (const allowed of COMMUNICATION_PROFILES.proposal.sections) assert.ok(hit.message.includes(allowed), allowed);
  assert.equal(hit.where, 'main/b3');
});

test('the opening beat declares the first section, so a final readout leads with its recommendation', () => {
  const spec = load('final-readout');
  spec.beats[0].section = 'findings';
  spec.beats[1].section = 'recommendation';
  spec.beats[2].section = 'recommendation';
  const got = rules(spec);
  assert.ok(got.includes('communication.section.first'), got.join(','));
  const preface = load('final-readout');
  delete preface.beats[0].section;
  assert.ok(rules(preface).includes('communication.section.first'));
});

test('a steering status cut needs only plan-vs-actual, risks, decisions and next, in that order', () => {
  const full = load('status-update');
  const steering = clone(full);
  steering.cadence = 'steering';
  steering.beats = ['plan-vs-actual', 'risks', 'decisions', 'next'].map((s) => clone(beatOf(full, s)));
  steering.beats[3].storyRole = 'next-step';
  steering.beats[0].storyRole = 'context';
  steering.beats[1].storyRole = 'demonstration';
  assert.deepEqual(rules(steering), []);
  assert.equal(checkStory(steering).ok, true, JSON.stringify(checkStory(steering).cuts[0].failures));
  const full90 = clone(full);
  full90.cadence = 'weekly';
  assert.deepEqual(rules(full90), []);
  const outOfOrder = clone(steering);
  [outOfOrder.beats[1].section, outOfOrder.beats[2].section] = [outOfOrder.beats[2].section, outOfOrder.beats[1].section];
  assert.ok(rules(outOfOrder).includes('communication.section.order'));
  const dropped = clone(steering);
  dropped.beats = dropped.beats.filter((b) => b.section !== 'decisions');
  assert.ok(findings(dropped).some((f) => f.rule === 'communication.section.missing' && f.message.includes('decisions')));
  const extra = clone(steering);
  extra.beats[1].section = 'done';
  const hit = findings(extra).find((f) => f.rule === 'communication.section.unknown');
  assert.ok(hit && hit.message.includes('plan-vs-actual, risks, decisions, next'), 'the steering list is what is allowed');
  const full90Missing = without(full90, 'done');
  assert.ok(findings(full90Missing).some((f) => f.rule === 'communication.section.missing'), 'weekly keeps the full list');
  const odd = clone(full); odd.cadence = 'daily';
  assert.ok(rules(odd).includes('communication.cadence'));
});

// ---- status update -----------------------------------------------------------------------------------------------

test('status update declares an overall rag with its start date and the status date', () => {
  for (const rag of [undefined, 'orange']) {
    const spec = load('status-update');
    if (rag === undefined) delete spec.rag; else spec.rag = rag;
    assert.ok(rules(spec).includes('communication.status.rag'), String(rag));
  }
  for (const ragSince of [undefined, '2 Nov', '2026-13-45']) {
    const spec = load('status-update');
    if (ragSince === undefined) delete spec.ragSince; else spec.ragSince = ragSince;
    assert.ok(rules(spec).includes('communication.status.rag-since'), String(ragSince));
  }
  const spec = load('status-update');
  delete spec.statusDate;
  assert.ok(rules(spec).includes('communication.status.status-date'));
});

test('each risk has an owner, an impact and a mitigation', () => {
  for (const field of ['description', 'owner', 'impact', 'mitigation']) {
    const spec = load('status-update');
    delete spec.risks[0][field];
    assert.ok(rules(spec).includes('communication.status.risk-fields'), field);
  }
  const spec = load('status-update');
  delete spec.risks;
  assert.ok(rules(spec).includes('communication.status.risks'));
  const none = load('status-update');
  none.risks = [];
  assert.deepEqual(rules(none), [], 'an empty risk list is a statement, not an omission');
});

test('each decision has an owner and a due date, null only when none is agreed', () => {
  const owner = load('status-update'); delete owner.decisions[0].owner;
  assert.ok(rules(owner).includes('communication.status.decision-fields'));
  const missing = load('status-update'); delete missing.decisions[0].dueDate;
  assert.ok(rules(missing).includes('communication.status.decision-fields'));
  const none = load('status-update'); none.decisions[0].dueDate = null; delete none.decisions[0].sourceRefs;
  assert.deepEqual(rules(none), [], 'null is allowed when nothing is agreed');
  const badDate = load('status-update'); badDate.decisions[0].dueDate = 'Friday';
  assert.ok(rules(badDate).includes('communication.status.decision-date'));
  const unsourced = load('status-update'); delete unsourced.decisions[0].sourceRefs;
  assert.ok(rules(unsourced).includes('communication.status.decision-date'), 'an agreed date needs sourceRefs');
  const nodecisions = load('status-update'); delete nodecisions.decisions;
  assert.ok(rules(nodecisions).includes('communication.status.decisions'));
});

test('green status with an unowned risk or an overdue decision is a finding; amber is not', () => {
  const green = load('status-update'); green.rag = 'green';
  assert.deepEqual(rules(green), [], 'owned risk and future decision under green is fine');
  const unowned = clone(green); unowned.risks[0].owner = '';
  const got = rules(unowned);
  assert.ok(got.includes('communication.status.green-with-open-issues'), got.join(','));
  const overdue = clone(green); overdue.decisions[0].dueDate = '2026-11-20';
  assert.ok(rules(overdue).includes('communication.status.green-with-open-issues'));
  for (const rag of ['amber', 'red']) {
    const spec = clone(overdue); spec.rag = rag; spec.risks[0].owner = '';
    assert.ok(!rules(spec).includes('communication.status.green-with-open-issues'), rag);
  }
  const today = clone(green); today.decisions[0].dueDate = '2026-11-23';
  assert.deepEqual(rules(today), [], 'due on the status date is not overdue');
});

// ---- pitch and proposal ------------------------------------------------------------------------------------------

test('an options section has two or three options with exactly one recommended', () => {
  for (const id of ['pitch', 'proposal']) {
    const base = load(id);
    const bad = (mutate) => { const s = clone(base); mutate(beatOf(s, 'options').options); return s; };
    assert.ok(rules(bad((o) => o.splice(1))).includes('communication.options.count'), `${id} one option`);
    assert.ok(rules(bad((o) => o.push({ label: 'Fourth', recommended: false }))).includes('communication.options.count'), `${id} four options`);
    assert.ok(rules(bad((o) => { o.forEach((x) => { x.recommended = false; }); })).includes('communication.options.recommended'), `${id} none recommended`);
    assert.ok(rules(bad((o) => { o.forEach((x) => { x.recommended = true; }); })).includes('communication.options.recommended'), `${id} all recommended`);
    assert.ok(rules(bad((o) => { o[0].label = ''; })).includes('communication.options.label'), `${id} unlabeled`);
    const noOptions = clone(base); delete beatOf(noOptions, 'options').options;
    assert.ok(rules(noOptions).includes('communication.options.count'), `${id} options section without options`);
    assert.deepEqual(rules(bad((o) => o.splice(0, 1))), [], `${id} two options is fine`);
  }
});

test('a proposal investment scene states assumptions and exclusions', () => {
  for (const field of ['assumptions', 'exclusions']) {
    const spec = load('proposal');
    delete beatOf(spec, 'investment')[field];
    const hit = findings(spec).find((f) => f.rule === 'communication.section-fields');
    assert.ok(hit && hit.message.includes(field), field);
    const empty = load('proposal');
    beatOf(empty, 'investment')[field] = [];
    assert.ok(rules(empty).includes('communication.section-fields'), `${field} empty`);
  }
});

test('numbers in cost-of-inaction and value-review sections must be measured, sourced claims', () => {
  const targets = [['pitch', 'cost-of-inaction'], ['value-review', 'baseline'], ['value-review', 'realized']];
  for (const [id, section] of targets) {
    const spec = load(id);
    claimOf(beatOf(spec, section)).scope = 'illustrative-scenario';
    Object.assign(claimOf(beatOf(spec, section)), { visibleLabel: 'Illustrative example', businessValidation: 'unvalidated', dataType: 'synthetic' });
    delete claimOf(beatOf(spec, section)).measurement;
    const got = findings(spec).filter((f) => f.rule === 'communication.measured-number');
    assert.equal(got.length, 1, `${id}/${section}`);
    assert.ok(got[0].message.includes(section));
    assert.equal(got[0].where, `main/${beatOf(spec, section).id}`);
  }
  // The existing measured-benefit rules still bite: an unsourced or synthetic number is rejected, never invented.
  const unsourced = load('pitch'); claimOf(beatOf(unsourced, 'cost-of-inaction')).sourceRefs = [];
  assert.ok(rules(unsourced).includes('communication.claim-source'));
  const synthetic = load('value-review'); claimOf(beatOf(synthetic, 'realized')).dataType = 'synthetic';
  assert.ok(rules(synthetic).includes('communication.measurement'));
  const thin = load('value-review'); delete claimOf(beatOf(thin, 'baseline')).measurement.timeWindow;
  assert.ok(rules(thin).includes('communication.measurement'));
  // A pitch may state the cost in words. With no number there is nothing to measure; a spelled-out number still counts.
  const worded = load('pitch');
  Object.assign(beatOf(worded, 'cost-of-inaction'), { narration: 'Every late close keeps reviewers from their own work.', actionTitle: 'A late close keeps reviewers from their own work.', supportingArgument: 'The cost grows while the close stays manual.' });
  Object.assign(claimOf(beatOf(worded, 'cost-of-inaction')), { scope: 'illustrative-scenario', visibleLabel: 'Illustrative example', businessValidation: 'unvalidated', dataType: 'synthetic' });
  delete claimOf(beatOf(worded, 'cost-of-inaction')).measurement;
  assert.ok(!rules(worded).includes('communication.measured-number'));
  for (const line of ['It costs twice the time.', 'It costs 12 hours.']) {
    beatOf(worded, 'cost-of-inaction').narration = line;
    assert.ok(rules(worded).includes('communication.measured-number'), line);
  }
  // Other sections keep their ordinary scopes.
  assert.deepEqual(rules(load('pitch')), []);
});

test('one ask per video for pitch, proposal, final readout and value review', () => {
  const second = (id, role) => {
    const spec = load(id);
    spec.beats.push({ id: 'extra', section: spec.beats.at(-1).section, storyRole: role, kind: 'card', minSeconds: 5, narration: 'Please also book a second meeting.' });
    return spec;
  };
  for (const id of ['pitch', 'proposal', 'final-readout', 'value-review']) {
    for (const role of ['cta', 'next-step']) assert.ok(rules(second(id, role)).includes('communication.one-ask'), `${id} + ${role}`);
  }
  const mixed = load('pitch'); mixed.beats.at(-2).storyRole = 'next-step';
  assert.ok(rules(mixed).includes('communication.one-ask'), 'cta and next-step together are two asks');
  for (const id of ['status-update', 'kickoff']) {
    const spec = load(id);
    spec.beats.push({ id: 'extra', section: spec.beats.at(-1).section, storyRole: 'cta', kind: 'card', minSeconds: 5, narration: 'Confirm your date.' });
    assert.ok(!rules(spec).includes('communication.one-ask'), `${id} is not limited to one ask`);
  }
});

test('ceilings are advisory: a brief above the recommended ceiling is not a finding, the approved ceiling governs', () => {
  for (const id of NEW) {
    const spec = load(id);
    spec.maxDurationSeconds = COMMUNICATION_PROFILES[id].ceilingSeconds * 2;
    assert.deepEqual(rules(spec), [], id);
  }
  const spec = load('pitch');
  spec.maxDurationSeconds = 20;
  assert.ok(rules(spec).includes('communication.duration'), 'the brief maxDurationSeconds still governs');
});

// ---- schemas, narration list, deploy layouts, docs ---------------------------------------------------------------

test('every schema enum lists every profile, in the table order', () => {
  const all = Object.keys(COMMUNICATION_PROFILES);
  assert.deepEqual(all.slice(0, 3), OLD, 'existing profiles keep their place');
  const ad = JSON.parse(readFileSync(join(pkg, 'kit/marketing/ad.schema.json'), 'utf8'));
  const job = JSON.parse(readFileSync(join(pkg, 'schemas/job.schema.json'), 'utf8'));
  const screenplay = JSON.parse(readFileSync(join(pkg, 'schemas/screenplay.schema.json'), 'utf8'));
  const storyboard = JSON.parse(readFileSync(join(pkg, 'schemas/storyboard.schema.json'), 'utf8'));
  for (const [name, schema] of Object.entries({ 'ad spec': ad.properties.communicationProfile, 'ad cut': ad.properties.cuts.items.properties.communicationProfile, job: job.properties.communicationProfile, screenplay: screenplay.properties.communicationProfile, storyboard: storyboard.properties.communicationProfile })) {
    assert.deepEqual(schema.enum, all, name);
  }
});

test('schemas accept the section field, the status fields and the options and investment fields', () => {
  const ad = JSON.parse(readFileSync(join(pkg, 'kit/marketing/ad.schema.json'), 'utf8'));
  const screenplay = JSON.parse(readFileSync(join(pkg, 'schemas/screenplay.schema.json'), 'utf8'));
  const storyboard = JSON.parse(readFileSync(join(pkg, 'schemas/storyboard.schema.json'), 'utf8'));
  const job = JSON.parse(readFileSync(join(pkg, 'schemas/job.schema.json'), 'utf8'));
  const proposal = load('proposal');
  const { id, kind, storyRole, minSeconds, narration, ...rest } = beatOf(proposal, 'investment');
  assert.deepEqual(validate(ad.definitions.beat, beatOf(proposal, 'investment'), ad), []);
  assert.deepEqual(validate(ad.definitions.beat, beatOf(proposal, 'options'), ad), []);
  assert.ok(validate(ad.definitions.beat, { ...beatOf(proposal, 'options'), options: [{ label: 'x', recommended: 'yes' }] }, ad).length);
  const scene = { id: 's1', narration, ...rest };
  assert.deepEqual(validate(screenplay.$defs.scene, scene, screenplay), []);
  const board = storyboard.properties.beats.items;
  assert.ok(board.properties.section && board.properties.options && board.properties.assumptions && board.properties.exclusions);
  const status = load('status-update');
  const brief = { kind: 'explainer', title: 'Weekly status', workspace: '/tmp/job', repositoryWritePolicy: 'read-only' };
  for (const key of ['communicationProfile', 'primaryAudience', 'viewerDecision', 'primaryTakeaway', 'audienceContext', 'nextStep', 'maxDurationSeconds', 'captionPolicy', 'limitations', 'audioDirection', 'rag', 'ragSince', 'statusDate', 'cadence', 'risks', 'decisions']) brief[key] = status[key];
  assert.deepEqual(validate(job, brief), []);
  assert.ok(validate(job, { ...brief, rag: 'orange' }).length, 'rag is red, amber or green');
  assert.ok(validate(job, { ...brief, cadence: 'daily' }).length);
  const adSpecProps = ad.properties;
  for (const key of ['rag', 'ragSince', 'statusDate', 'cadence', 'risks', 'decisions']) {
    assert.ok(adSpecProps[key] && ad.properties.cuts.items.properties[key], `ad ${key}`);
    assert.ok(screenplay.properties[key], `screenplay ${key}`);
  }
});

const narrationReport = (root, profile) => {
  const jobRoot = join(root, `job-${profile}`);
  mkdirSync(join(jobRoot, 'story'), { recursive: true });
  mkdirSync(join(jobRoot, 'qa'), { recursive: true });
  writeFileSync(join(jobRoot, 'job.json'), JSON.stringify({ kind: 'explainer', communicationProfile: profile }));
  writeFileSync(join(jobRoot, 'story/screenplay.json'), JSON.stringify({ title: 'Check', primaryTakeaway: 'Move the close to one ledger.', scenes: [{ id: 'S1', narration: 'Move the close to one ledger. Teams post once and reviewers see one version.' }] }));
  return jobRoot;
};
const runNarration = (script, jobRoot) => {
  const r = spawnSync(process.execPath, [script, jobRoot], { encoding: 'utf8', windowsHide: true });
  const reportPath = join(jobRoot, 'qa/narration-check.json');
  return { status: r.status, output: `${r.stdout}${r.stderr}`, report: existsSync(reportPath) ? JSON.parse(readFileSync(reportPath, 'utf8')) : null };
};

test('the narration gate knows every profile from the one list, in every deploy layout', () => {
  const root = mkdtempSync(join(tmpdir(), 'engagement-layout-'));
  try {
    const scripts = ['validate-narration.mjs', 'marketing-cut.mjs'].map((f) => join(pkg, 'scripts', f)).concat(join(pkg, 'kit/screencast/sync-lib.mjs'));
    const lib = join(pkg, 'kit/marketing/lib');
    const layouts = {
      package: join(pkg, 'scripts'),
      // Sync-MediaStudioKit.ps1 copies the gate into <runtime kit>/screencast and into _shared/tools, with the kit at <runtime kit>/marketing/lib.
      'runtime kit': join(root, 'runtime/briefing-kit/screencast'),
      'shared tools': join(root, 'runtime/_shared/tools'),
    };
    mkdirSync(layouts['runtime kit'], { recursive: true });
    mkdirSync(layouts['shared tools'], { recursive: true });
    cpSync(lib, join(root, 'runtime/briefing-kit/marketing/lib'), { recursive: true });
    for (const dir of [layouts['runtime kit'], layouts['shared tools']]) for (const file of scripts) cpSync(file, join(dir, file.split(/[\\/]/).pop()));
    for (const [name, dir] of Object.entries(layouts)) {
      const script = join(dir, 'validate-narration.mjs');
      for (const profile of ['consulting-demo', ...NEW]) {
        const run = runNarration(script, narrationReport(join(root, name.replace(' ', '-')), profile));
        assert.ok(run.report, `${name}/${profile}: ${run.output}`);
        assert.ok(!run.report.errors.some((e) => e.startsWith('unknown communicationProfile')), `${name}/${profile}: ${JSON.stringify(run.report.errors)}`);
      }
      const bad = runNarration(script, narrationReport(join(root, name.replace(' ', '-')), 'workshop'));
      assert.ok(bad.report.errors.some((e) => e === 'unknown communicationProfile: workshop'), name);
    }
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('the engagement guide lists every profile with its sections and ceiling, and points at a fixture that exists', () => {
  const guide = readFileSync(join(pkg, 'skills/studio/references/engagement-formats.md'), 'utf8');
  const hub = readFileSync(join(pkg, 'skills/studio/references/consulting-communication.md'), 'utf8');
  assert.ok(hub.includes('engagement-formats.md'), 'the consulting guide links the engagement guide');
  assert.ok(!/remain future work/.test(hub), 'the future-work line is gone');
  assert.ok(hub.split('\n').length <= 150, 'the consulting guide stays short');
  for (const id of NEW) {
    const p = COMMUNICATION_PROFILES[id];
    const row = guide.split('\n').find((line) => line.startsWith(`| ${id} |`));
    assert.ok(row, `${id} row`);
    assert.ok(row.includes(`${p.ceilingSeconds} s`), `${id} ceiling`);
    assert.ok(row.includes(p.filmType), `${id} film type`);
    assert.ok(row.includes(p.sections.map((s) => s + ((p.optional || []).includes(s) ? '?' : '')).join(' > ')), `${id} sections`);
    assert.ok(guide.includes(`tests/fixtures/engagement/${id}.json`), `${id} fixture link`);
    assert.ok(hub.includes(`| ${id} |`), `${id} appears in the profile table`);
  }
  assert.match(guide, /weekly[^\n]*90 s/);
  assert.match(guide, /steering/);
});

test('request wording for each format reaches its profile through the routing docs', () => {
  const read = (p) => readFileSync(join(pkg, p), 'utf8');
  const studio = read('skills/studio/SKILL.md');
  const intake = read('skills/studio/references/creative-intake.md');
  const formats = read('skills/studio/references/creative-formats.md');
  const forms = read('skills/studio/references/forms.md');
  const treatments = read('skills/studio/references/treatments.md');
  assert.match(studio, /engagement-formats\.md/);
  for (const phrase of ['steering committee update', 'proposal video', 'pitch video', 'kickoff video', 'final readout', 'value review']) {
    assert.ok([intake, formats, forms].some((t) => t.toLowerCase().includes(phrase)), phrase);
  }
  for (const id of NEW) assert.match(treatments, new RegExp(`^- ${id}:`, 'm'), `${id} treatment`);
});
