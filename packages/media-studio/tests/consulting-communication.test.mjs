import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, cpSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { checkStory } from '../scripts/check-story.mjs';
import { inspectCommunication, resolveFilmType } from '../kit/marketing/lib/story-profiles.mjs';
import { inspectNarrativeArc } from '../kit/marketing/lib/narrative.mjs';
import { validate } from '../kit/marketing/lib/schema.mjs';

const profile = (communicationProfile = 'consulting-demo') => ({
  product: 'Casework', communicationProfile, targetSeconds: 40, maxDurationSeconds: 120,
  primaryAudience: 'operations evaluator', viewerDecision: 'whether to discuss one handoff',
  primaryTakeaway: 'The reviewer resolves the conflict before approval.',
  audienceContext: { problemStatus: 'hypothesis', sourceRefs: [] },
  nextStep: { action: 'discuss one representative handoff', owner: 'presenter', agreedDate: null },
  captionPolicy: { mode: 'sidecar', deliverySurface: 'web player' },
  audioDirection: { narratorIdentity: 'approved narrator', pronunciationRefs: [], delivery: 'calm and precise', emphasis: [], pauses: 'hold the visible result', musicTreatment: 'none' },
  limitations: ['Synthetic case; customer benefit has not been measured.'],
  narrative: { persona: 'operations reviewer', problem: 'two sources disagree', payoff: 'the supported decision is recorded', goal: 'resolve the case', change: 'source conflicts now block approval' },
});
const beat = (id, storyRole = 'demonstration') => ({
  id, storyRole, kind: 'ui', narration: `Casework records the supported decision for case ${id}.`, minSeconds: 5,
  actionTitle: `The reviewer records the supported decision for ${id}.`,
  supportingArgument: 'The decision retains its source.', proofRefs: [`capture/${id}.receipt.json`],
  uiProof: { actor: 'case reviewer', object: 'conflicting assignment', action: 'select supported date', systemResponse: 'records chosen date', result: 'handoff approval enabled', significance: 'unsupported dates cannot pass' },
  evidenceClaims: [{ text: 'The supported date is recorded.', scope: 'product-behavior', sourceRefs: [`capture/${id}.receipt.json`], implementationState: 'implemented', dataType: 'synthetic', aiExecutionMode: 'recorded', businessValidation: 'unvalidated' }],
});
const cut = (beats = [beat('a'), beat('b'), beat('c')]) => ({ id: 'main', beats });
const findings = (spec, c = cut()) => inspectCommunication(spec, c, (b) => b.minSeconds || 5);

test('profiles reuse existing film types, without creative-mode bypass', () => {
  for (const [id, type] of [['consulting-demo', 'feature-demo'], ['technical-walkthrough', 'tutorial'], ['product-update', 'internal-update']]) {
    assert.equal(resolveFilmType(profile(id), {}, 'fictional-story').id, type);
  }
  assert.deepEqual(findings(profile()), []);
  assert.deepEqual(findings(profile('product-update'), cut([beat('a')])), []);
  assert.ok(findings(profile(), cut([beat('a')])).some((f) => f.rule === 'communication.proof-moments'));
});

test('titles-only output preserves conclusions and proof contracts through normalization', () => {
  const spec = { ...profile(), beats: [beat('a', 'context'), beat('b'), beat('c'), beat('d', 'payoff')] };
  const report = checkStory(spec);
  assert.equal(report.ok, true, JSON.stringify(report));
  assert.equal(report.cuts[0].titlesOnly.length, 4);
  assert.equal(report.cuts[0].titlesOnly[0].actionTitle, spec.beats[0].actionTitle);
  spec.beats[0].actionTitle = 'Integrations';
  assert.ok(checkStory(spec).cuts[0].failures.some((f) => f.rule === 'communication.action-title'));
});

test('unsupported claims cannot be waived or converted into customer benefit by creative mode', () => {
  for (const creativeMode of ['verified-demo', 'fictional-story', 'future-vision']) {
    const spec = { ...profile(), creativeMode, storyOverrides: [{ rule: 'story.*', reason: 'Owner accepts this alternate scene structure.' }] };
    const c = cut();
    Object.assign(c.beats[0].evidenceClaims[0], { scope: 'measured-benefit', businessValidation: 'measured', measurement: { baseline: 'ten minutes', comparison: 'five minutes', population: 'ten cases', method: 'paired observations', timeWindow: 'one month' } });
    const result = inspectNarrativeArc(spec, c, () => 5);
    assert.ok(result.some((f) => f.rule === 'communication.measurement' && !f.waived));
  }
});

test('discovery, commitments, source scope, action/result and duration fail independently', () => {
  const spec = profile();
  spec.audienceContext.problemStatus = 'confirmed-discovery';
  spec.nextStep.agreedDate = '2026-12-01';
  spec.maxDurationSeconds = 10;
  const c = cut();
  delete c.beats[0].uiProof.result;
  c.beats[1].evidenceClaims[0].scope = 'proposed-interface';
  const rules = findings(spec, c).map((f) => f.rule);
  for (const rule of ['discovery-source', 'commitment-source', 'duration', 'action-result', 'visible-label']) assert.ok(rules.includes(`communication.${rule}`), rule);
});

test('technical flow distinguishes supported ingestion from a proposed connection', () => {
  const spec = { ...profile('technical-walkthrough'), scenarioRecord: 'case A-17', integrationStatus: 'file-import', integrationFlow: ['source', 'intake', 'transformation', 'rules-ai', 'human-decision', 'output', 'acknowledgment-or-exception'] };
  assert.deepEqual(findings(spec, cut([beat('a')])), []);
  spec.integrationStatus = 'live-sync';
  assert.ok(findings(spec).some((f) => f.rule === 'communication.integration-status'));
});

test('derived update inherits limitations and proof but uses its own one-moment profile', () => {
  const spec = profile();
  const update = { ...cut([beat('a')]), communicationProfile: 'product-update', targetSeconds: 25, maxDurationSeconds: 45 };
  assert.deepEqual(findings(spec, update), []);
  update.limitations = [];
  assert.ok(findings(spec, update).some((f) => f.rule === 'communication.limitations'));
});

test('screenplay and marketing schemas accept scoped scene evidence and reject invalid dimensions', () => {
  const ad = JSON.parse(readFileSync(new URL('../kit/marketing/ad.schema.json', import.meta.url), 'utf8'));
  const b = beat('a');
  assert.deepEqual(validate(ad.definitions.beat, b, ad), []);
  b.evidenceClaims[0].dataType = 'successful-demo';
  assert.ok(validate(ad.definitions.beat, b, ad).length);
  const screenplay = JSON.parse(readFileSync(new URL('../schemas/screenplay.schema.json', import.meta.url), 'utf8'));
  assert.ok(screenplay.properties.communicationProfile);
  assert.ok(screenplay.$defs.scene.properties.evidenceClaims);
  const job = JSON.parse(readFileSync(new URL('../schemas/job.schema.json', import.meta.url), 'utf8'));
  const { product, targetSeconds, narrative, ...decisionBrief } = profile();
  assert.deepEqual(validate(job, { ...decisionBrief, kind: 'product-screencast', title: 'Resolve one case', workspace: '/tmp/job', repositoryWritePolicy: 'read-only' }), []);
});

test('fresh copied package resolves the existing story gate without installed-host state', () => {
  const root = mkdtempSync(join(tmpdir(), 'consulting-host-'));
  try {
    mkdirSync(join(root, 'scripts'));
    cpSync(new URL('../scripts/check-story.mjs', import.meta.url), join(root, 'scripts/check-story.mjs'));
    cpSync(new URL('../kit/marketing/lib/', import.meta.url), join(root, 'kit/marketing/lib'), { recursive: true });
    cpSync(new URL('../kit/marketing/product-profiles.json', import.meta.url), join(root, 'kit/marketing/product-profiles.json'));
    writeFileSync(join(root, 'brief.json'), JSON.stringify({ ...profile(), beats: [beat('a', 'context'), beat('b'), beat('c'), beat('d', 'payoff')] }));
    const run = spawnSync(process.execPath, [join(root, 'scripts/check-story.mjs'), join(root, 'brief.json'), '--json'], { encoding: 'utf8', windowsHide: true });
    assert.equal(run.status, 0, run.stderr + run.stdout);
    assert.equal(JSON.parse(run.stdout).cuts[0].filmType, 'feature-demo');
    const titles = spawnSync(process.execPath, [join(root, 'scripts/check-story.mjs'), join(root, 'brief.json'), '--titles'], { encoding: 'utf8', windowsHide: true });
    assert.equal(titles.status, 0, titles.stderr);
    assert.match(titles.stdout, /1\. The reviewer records/);
    assert.ok(!titles.stdout.includes('Casework records'), 'ghost storyboard contains no narration');
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('Pink reviews an update without a dramatic hero, while enforcing current proof, narration and reviewer evidence', () => {
  const root = mkdtempSync(join(tmpdir(), 'consulting-review-'));
  const scripts = fileURLToPath(new URL('../scripts/', import.meta.url));
  const write = (name, value) => writeFileSync(join(root, name), JSON.stringify(value));
  const hash = (name) => createHash('sha256').update(readFileSync(join(root, name))).digest('hex');
  try {
    mkdirSync(join(root, 'story')); mkdirSync(join(root, 'qa'));
    const { targetSeconds, narrative, product, ...job } = profile('product-update');
    job.primaryTakeaway = 'Source conflicts now block approval.';
    write('job.json', { ...job, kind: 'product-screencast' });
    const lines = [job.primaryTakeaway, 'Select the supported date to record the decision.', 'Open the case review page.'];
    const scenes = ['context', 'demonstration', 'next-step'].map((sceneRole, i) => {
      const { kind, minSeconds, storyRole, ...scene } = beat(`s${i}`);
      return { ...scene, sceneRole, visualMode: 'screen', narration: lines[i] };
    });
    write('story/screenplay.json', { title: 'Resolve one case', product, narrative, communicationProfile: job.communicationProfile, primaryTakeaway: job.primaryTakeaway, scenes });
    write('story/storyboard.json', { title: 'Resolve one case', beats: [] });
    const narration = spawnSync(process.execPath, [join(scripts, 'validate-narration.mjs'), root], { encoding: 'utf8', windowsHide: true });
    assert.equal(narration.status, 0, narration.stderr + narration.stdout);
    const verdicts = { inputs: { screenplay: { sha256: hash('story/screenplay.json') }, storyboard: { sha256: hash('story/storyboard.json') } }, judgments: Object.fromEntries(['audience', 'form-fit', 'visual-story', 'representation', 'ghost-storyboard', 'proof-scope', 'answer-first'].map((name) => [name, { verdict: 'pass', evidence: 's0 through s2 show the case and its recorded result.' }])) };
    write('qa/story-judgments.json', verdicts);
    const review = () => spawnSync('python', [join(scripts, 'write-story-review.py'), root], { encoding: 'utf8', windowsHide: true });
    let run = review();
    assert.equal(run.status, 0, run.stderr + run.stdout);
    assert.equal(JSON.parse(readFileSync(join(root, 'qa/story-review.json'))).reviewStage, 'Pink');
    verdicts.judgments['proof-scope'].verdict = 'fail'; write('qa/story-judgments.json', verdicts);
    assert.equal(review().status, 1, 'one failed proof judgment blocks regardless of average score');
    verdicts.judgments['proof-scope'].verdict = 'pass'; write('qa/story-judgments.json', verdicts);
    scenes[1].evidenceClaims[0].scope = 'measured-benefit';
    write('story/screenplay.json', { title: 'Resolve one case', product, narrative, communicationProfile: job.communicationProfile, primaryTakeaway: job.primaryTakeaway, scenes });
    run = review();
    assert.equal(run.status, 1);
    const result = JSON.parse(readFileSync(join(root, 'qa/story-review.json')));
    assert.ok(result.missingEvidence.some((e) => e.includes('measurement')));
    assert.ok(result.missingEvidence.some((e) => e.includes('current screenplay')));
  } finally { rmSync(root, { recursive: true, force: true }); }
});
