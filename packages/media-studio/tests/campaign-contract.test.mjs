import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CAMPAIGN_FORMS, frameFor, sourcePictureFilter, sourceRegionError, validateCampaign } from '../kit/screencast/campaign-contract.mjs';

const root = mkdtempSync(join(tmpdir(), 'campaign-contract-'));
const packageRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
test.after(() => rmSync(root, { recursive: true, force: true }));
const sha = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');
const file = (name, bytes) => { const path = join(root, name); writeFileSync(path, bytes); return { path: name, sha256: sha(path) }; };
mkdirSync(join(root, 'story'));
mkdirSync(join(root, 'evidence'));
mkdirSync(join(root, 'capture'));
const evidence = file('claim.json', '{"status":"synthetic-proof"}');
const ui = file('capture/screen.webm', 'receipt-bound-source-placeholder');
const graphicAsset = file('label.png', 'transparent-graphic-placeholder');
const parent = file('parent.mp4', 'locked-parent-placeholder');
const unlisted = file('capture/unlisted.webm', 'not in campaign asset list');
const timeline = { durationSeconds: 65, segments: [{ id: 'S01', startSeconds: 0, durationSeconds: 32.5 }, { id: 'S02', startSeconds: 32.5, durationSeconds: 32.5 }] };
writeFileSync(join(root, 'capture', 'manifest.json'), JSON.stringify({ clips: [{ id: 'ui', file: 'screen.webm', segments: ['S01', 'S02'] }, { id: 'unused', file: 'unlisted.webm', segments: ['S99'] }] }));
writeFileSync(join(root, 'story', 'storyboard.json'), JSON.stringify({ scenarioId: 'synthetic-01' }));
writeFileSync(join(root, 'evidence', 'demo-scenario-proof.json'), JSON.stringify({ scenarioId: 'synthetic-01', continuity: { entities: [{ type: 'client', id: 'record-01' }, { type: 'client', id: 'a' }, { type: 'client', id: 'b' }] } }));
const job = () => ({ kind: 'product-screencast', programForm: 'campaign-flagship', deliveryProfile: 'linkedin-4x5', campaign: {
  continuity: { mode: 'single-record', recordId: 'record-01', scenarioId: 'synthetic-01' },
  claims: [{ id: 'claim-01', text: 'A human approved the draft.', asOf: '2026-09-22', segmentIds: ['S02'], evidence: { ...evidence } }],
  assets: [{ id: 'ui', ...ui, origin: 'captured-ui', rights: 'synthetic test capture' }, { id: 'label', ...graphicAsset, origin: 'authored-graphic', rights: 'authored for this campaign' }],
  protectedRegions: [{ x: 600, y: 500, width: 300, height: 400 }],
  captionRegion: { x: 100, y: 920, width: 500, height: 100 },
} });
const graphic = () => [{ assetId: 'label', x: 100, y: 170, width: 300, height: 90, startSeconds: 2, endSeconds: 8 }];
const check = (j = job(), t = timeline, g = graphic()) => validateCampaign(root, j, t, g);
const fails = (mutate, pattern) => { const j = job(), t = structuredClone(timeline), g = graphic(); mutate(j, t, g); assert.match(check(j, t, g).join(' '), pattern); };

test('campaign contracts pass with one record, sourced claim, provenanced assets, safe timed graphics', () => {
  assert.deepEqual(check(), []);
  assert.deepEqual(Object.keys(CAMPAIGN_FORMS), ['campaign-flagship', 'campaign-comparison', 'campaign-short', 'campaign-outreach']);
  assert.deepEqual([frameFor(job()).width, frameFor(job()).height], [1080, 1350]);
  assert.deepEqual([frameFor({ deliveryProfile: 'youtube-16x9' }).width, frameFor({ deliveryProfile: 'youtube-16x9' }).height], [1920, 1080]);
  assert.deepEqual([frameFor({ deliveryProfile: 'vertical-9x16' }).width, frameFor({ deliveryProfile: 'vertical-9x16' }).height], [1080, 1920]);
  assert.deepEqual([frameFor({ deliveryProfile: 'linkedin' }).width, frameFor({ deliveryProfile: 'linkedin' }).height], [1920, 1080]);
});

test('form range and explicit delivery profile can fail', () => {
  fails((j, t) => { t.durationSeconds = 55; }, /60–70 seconds/);
  fails((j) => { delete j.deliveryProfile; }, /explicit deliveryProfile/);
  for (const [form, range] of Object.entries(CAMPAIGN_FORMS)) {
    const j = job(), t = structuredClone(timeline); j.programForm = form; t.durationSeconds = range[0]; assert.deepEqual(check(j, t), []);
    t.durationSeconds = range[1] + 1; assert.match(check(j, t).join(' '), /timeline must be/);
  }
});

test('single-record and labeled-vignette continuity can fail', () => {
  fails((j) => { j.campaign.continuity.scenarioId = 'other'; }, /differs from the storyboard/);
  fails((j) => { delete j.campaign.continuity.recordId; }, /recordId and scenarioId/);
  const j = job(); j.campaign.continuity = { mode: 'labeled-vignettes', vignettes: [
    { id: 'one', label: 'Clinic A', recordId: 'a', segmentIds: ['S01'] },
    { id: 'two', label: 'Clinic B', recordId: 'b', segmentIds: ['S02'] },
  ] };
  const g = [
    { ...graphic()[0], startSeconds: 0, vignetteId: 'one', visibleLabel: 'Clinic A' },
    { ...graphic()[0], startSeconds: 32.5, endSeconds: 40, vignetteId: 'two', visibleLabel: 'Clinic B' },
  ];
  assert.deepEqual(check(j, timeline, g), []);
  g[1].startSeconds = 10; g[1].endSeconds = 16; assert.match(check(j, timeline, g).join(' '), /must cover the opening/); assert.match(check(j, timeline, g).join(' '), /overlaps another vignette label/);
  g[1].startSeconds = 32.5; g[1].endSeconds = 40;
  g[1].visibleLabel = 'Wrong'; assert.match(check(j, timeline, g).join(' '), /needs a timed, visible label/);
  g[1].visibleLabel = 'Clinic B'; j.campaign.continuity.vignettes[1].segmentIds = ['S01']; assert.match(check(j, timeline, g).join(' '), /missing or duplicated/);
  j.campaign.continuity.vignettes[1].segmentIds = ['S02']; j.campaign.continuity.vignettes[1].recordId = 'a'; assert.match(check(j, timeline, g).join(' '), /distinct records/);
});

test('dated claims and file hashes can fail', () => {
  fails((j) => { j.campaign.claims[0].asOf = '2999-01-01'; }, /nonfuture asOf/);
  fails((j) => { j.campaign.claims[0].segmentIds = ['S99']; }, /segmentIds/);
  fails((j) => { j.campaign.claims[0].evidence.sha256 = '0'.repeat(64); }, /claim claim-01 evidence SHA-256/);
  fails((j) => { j.campaign.claims[0].evidence.path = '../escape.json'; }, /escapes the external job workspace/);
});

test('asset provenance and derivative lineage can fail', () => {
  fails((j) => { delete j.campaign.assets[0].rights; }, /origin and rights/);
  fails((j) => { j.campaign.assets[0].sha256 = 'f'.repeat(64); }, /asset ui SHA-256/);
  const j = job(); j.sourceJobId = 'parent-01'; j.campaign.derivative = { parentJobId: 'parent-01', parentCandidate: { ...parent }, sourceAssets: [{ ...ui }] };
  assert.deepEqual(check(j), []);
  j.campaign.derivative.parentJobId = 'wrong'; assert.match(check(j).join(' '), /must match sourceJobId/);
  j.campaign.derivative.parentJobId = 'parent-01'; j.campaign.derivative.parentCandidate.sha256 = '0'.repeat(64); assert.match(check(j).join(' '), /parent candidate SHA-256/);
  j.campaign.derivative.parentCandidate.sha256 = parent.sha256; j.campaign.derivative.sourceAssets = [{ ...unlisted }]; assert.match(check(j).join(' '), /not recorded in campaign asset provenance/);
});

test('campaign asset provenance covers used capture-manifest clips but ignores unused takes', () => {
  assert.deepEqual(check(), []);
  fails((j) => { j.campaign.assets = j.campaign.assets.filter((asset) => asset.id !== 'ui'); }, /used capture clip ui.*missing from campaign asset provenance/);
  fails((j) => { j.campaign.assets[0].origin = 'licensed'; }, /screen capture clip ui must have captured-ui asset provenance/);
  const manifestPath = join(root, 'capture', 'manifest.json');
  const original = readFileSync(manifestPath, 'utf8');
  try {
    writeFileSync(manifestPath, JSON.stringify({ composeClips: [{ id: 'new', file: 'unlisted.webm', segments: ['S02'] }], clips: [{ id: 'ui', file: 'screen.webm', segments: ['S01', 'S02'] }] }));
    assert.match(check().join(' '), /used capture clip new.*missing from campaign asset provenance/);
  } finally { writeFileSync(manifestPath, original); }
});

test('timed graphics protect frame safety and product controls', () => {
  fails((j, t, g) => { g[0].x = 0; }, /safe area/);
  fails((j, t, g) => { g[0].x = 620; g[0].y = 600; }, /covers a declared product control/);
  fails((j, t, g) => { g[0].endSeconds = 100; }, /invalid size or timing/);
  fails((j, t, g) => { g[0].assetId = 'missing'; }, /no provenanced asset/);
  fails((j) => { j.campaign.protectedRegions = []; }, /require protectedRegions/);
  fails((j) => { j.campaign.protectedRegions[0].width = -1; }, /valid rectangle/);
  fails((j) => { delete j.campaign.captionRegion; }, /requires captionRegion/);
  fails((j) => { j.campaign.captionRegion.y = 1250; }, /captionRegion crosses/);
  fails((j) => { j.campaign.captionRegion.x = 500; j.campaign.captionRegion.y = 600; }, /captionRegion covers a declared product control/);
  fails((j, t, g) => { g[0].y = 930; }, /covers the captionRegion/);
});

test('legacy jobs remain outside the campaign contract', () => {
  assert.deepEqual(check({ kind: 'product-screencast', programForm: 'role-demo' }), []);
});

test('campaign findings are exact and ordered for valid and invalid campaigns', () => {
  assert.deepEqual(check(), []);

  assert.deepEqual(
    validateCampaign(root, { kind: 'other', programForm: 'campaign-flagship' }, timeline),
    ['campaign-flagship requires kind product-screencast.', 'campaign contract is required.'],
  );

  const j = job();
  const t = structuredClone(timeline);
  const g = graphic();
  j.kind = 'other';
  delete j.deliveryProfile;
  t.durationSeconds = 55;
  j.campaign.continuity.scenarioId = 'other';
  j.campaign.claims[0].segmentIds = ['S99'];
  j.campaign.assets[0].origin = 'licensed';
  g[0].x = 0;
  assert.deepEqual(check(j, t, g), [
    'campaign-flagship requires kind product-screencast.',
    'campaign requires an explicit deliveryProfile.',
    'campaign-flagship timeline must be 60–70 seconds.',
    'single-record continuity differs from the proven scenario or record.',
    'single-record scenarioId differs from the storyboard.',
    'claim claim-01 must cite campaign segmentIds.',
    'screen capture clip ui must have captured-ui asset provenance.',
    'captionRegion crosses the delivery-profile safe area.',
    'timed graphic 1 crosses the briefing-board safe area.',
  ]);
});

test('source crop is bounded and has one shared FFmpeg transform', () => {
  const region = { x: .275, y: 0, width: .45, height: 1 };
  assert.equal(sourceRegionError(region), null);
  assert.match(sourcePictureFilter(region, frameFor(job())), /crop=iw\*0\.45:ih\*1:iw\*0\.275:ih\*0,scale=1080:1350/);
  assert.match(sourceRegionError({ ...region, width: .8 }), /bounded normalized rectangle/);
  assert.match(sourceRegionError({ ...region, height: .05 }), /bounded normalized rectangle/);
});

test('native manifests and runtime kit advertise one Media Studio release version', () => {
  const read = (path) => JSON.parse(readFileSync(join(packageRoot, path), 'utf8'));
  const version = read('plugin.json').version;
  assert.equal(read('.claude-plugin/plugin.json').version, version);
  assert.equal(read('.codex-plugin/plugin.json').version, version);
  assert.equal(read('.cursor-plugin/plugin.json').version, version);
  assert.equal(read('kit/package.json').version, version);
  assert.equal(read('kit/package-lock.json').version, version);
  assert.equal(read('kit/package-lock.json').packages[''].version, version);
  assert.equal(read('kit/scene-archetypes.json').version, version);
});
