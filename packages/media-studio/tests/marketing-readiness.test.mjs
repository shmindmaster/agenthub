// Marketing-readiness floor: the reviewer's rubric file is held to the floor on the exact encoded candidate.
// Run: node --test packages/media-studio/tests/marketing-readiness.test.mjs   (needs ffmpeg/ffprobe for the candidate)
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync, existsSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const gate = join(pkg, 'scripts', 'validate-marketing-readiness.mjs');
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const run = (args) => { const r = spawnSync(process.execPath, [gate, ...args], { encoding: 'utf8', windowsHide: true }); return { code: r.status, out: `${r.stdout}${r.stderr}` }; };
const hasFfmpeg = (() => { try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore', windowsHide: true }); execFileSync('ffprobe', ['-version'], { stdio: 'ignore', windowsHide: true }); return true; } catch { return false; } })();
const scratch = mkdtempSync(join(tmpdir(), 'mkt-ready-'));
test.after(async () => { await new Promise((d) => setTimeout(d, 1000)); rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); });
const writeJson = (p, v) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, JSON.stringify(v, null, 2)); };

test('managed runtime gate list ships the speech helper beside both validator copies', () => {
  const sync = readFileSync(join(pkg, 'scripts/Sync-MediaStudioKit.ps1'), 'utf8');
  const block = sync.match(/\$gateScripts\s*=\s*@\(([\s\S]*?)\)\s*\$sharedTools/);
  assert.ok(block, 'native managed gate list must be discoverable');
  const names = [...block[1].matchAll(/'([^']+\.mjs)'/g)].map(m => m[1]);
  for (const name of ['validate-marketing-readiness.mjs', 'speech-only-readiness.mjs']) assert.ok(names.includes(name), `${name} must travel through the native gate-copy loop`);
  // Exercise adjacent resolution in both deployment layouts. The PowerShell deployment suite separately runs the actual sync and checks destination hashes.
  for (const target of ['briefing-kit/screencast', '_shared/tools']) {
    const destination = join(scratch, 'packaged', target); mkdirSync(destination, { recursive: true });
    for (const name of names.filter(n => ['validate-marketing-readiness.mjs', 'speech-only-readiness.mjs'].includes(n))) copyFileSync(join(pkg, 'scripts', name), join(destination, name));
    const deployedGate = join(destination, 'validate-marketing-readiness.mjs');
    let result = spawnSync(process.execPath, [deployedGate], { encoding: 'utf8', windowsHide: true });
    assert.equal(result.status, 1); assert.match(result.stderr, /Usage: node validate-marketing-readiness/); assert.doesNotMatch(result.stderr, /ERR_MODULE_NOT_FOUND/);
    rmSync(join(destination, 'speech-only-readiness.mjs'));
    result = spawnSync(process.execPath, [deployedGate], { encoding: 'utf8', windowsHide: true });
    assert.notEqual(result.status, 0); assert.match(result.stderr, /ERR_MODULE_NOT_FOUND/, 'negative control must reproduce the original missing-helper failure');
  }
});

let sharedCandidate = null;
function candidateFor(root) {
  mkdirSync(join(root, 'output'), { recursive: true });
  const out = join(root, 'output', 'cut.mp4');
  if (!sharedCandidate) {
    sharedCandidate = join(scratch, 'shared-10s.mp4');
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', '-f', 'lavfi', '-i', 'testsrc2=size=320x200:rate=10:duration=10', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', sharedCandidate], { windowsHide: true, timeout: 60000 });
  }
  writeFileSync(out, readFileSync(sharedCandidate));
  return out;
}

function readiness(candidate, over = {}) {
  return {
    schema: 'media-studio/marketing-readiness/1', reviewer: 'fixture reviewer',
    candidate: { path: 'output/cut.mp4', sha256: sha(candidate), bytes: statSync(candidate).size },
    hook: { atSeconds: 0.8, what: 'the held-claim count fills the frame before any logo', verdict: 'pass' },
    promise: { text: 'See why a claim is held before the payer does.', count: 1, verdict: 'pass', evidence: 'M01 names it, M06 shows the held reason, M08 CTA repeats it' },
    motion: { verdict: 'pass', evidence: 'type builds at 0:00.4 and 0:03.1; the table rows wipe in at 0:05; no hold over 2 s' },
    sound: { bed: true, designCues: 3, verdict: 'pass', evidence: 'riser into the reveal at 0:04, hit on the 0:06 cut, sting under the end card' },
    brand: { kit: 'fixture-brand-2026', endCardAtSeconds: 8.5, cta: 'Book a 20-minute walkthrough', verdict: 'pass' },
    cutsOnBeat: { bpm: 120, offsetSeconds: 0, toleranceMs: 80, verdict: 'pass', evidence: 'cuts at 2.0, 4.0, 6.5 on the 120 bpm grid' },
    references: [
      { title: 'Linear launch film', source: 'linear.app, 2025', whyItWins: 'one claim per cut, product motion is the hook' },
      { title: 'Notion AI 30s', source: 'youtube ad library', whyItWins: 'pain in the first second, promise in the first five' },
      { title: 'Stripe Sessions teaser', source: 'stripe.com', whyItWins: 'type and cuts on the bed, end card inside three seconds' },
    ],
    attentionCompetition: { winsAgainstReferences: true, evidence: 'the held-claim number lands at 0.8 s; the three references take 1.5-3 s to state a pain' },
    ...over,
  };
}

function job(root, over = {}) {
  const candidate = candidateFor(root);
  writeJson(join(root, 'job.json'), { kind: 'product-screencast', title: 'fixture', workspace: root, repositoryWritePolicy: 'read-only', programForm: 'marketing-cutdown', intent: 'viewer-facing', ...over });
  writeJson(join(root, 'plan', 'cue-sheet.json'), { generator: 'media-studio/build-cue-sheet', mode: 'mapped', durationSeconds: 10, edl: [{ segments: ['M01'], startSeconds: 0 }, { segments: ['M02'], startSeconds: 2.0 }, { segments: ['M03'], startSeconds: 4.0 }, { segments: ['M04'], startSeconds: 6.5 }], beats: [] });
  writeJson(join(root, 'qa', 'narration-check.json'), { generator: 'media-studio/validate-narration', ok: true, thresholds: { hookSeconds: 5, redundantOverlap: 0.7, redundantMinContentWords: 3, noNewInformationMinContentWords: 4 }, errors: [], fluff: { perMinute: 0, count: 0 } });
  writeJson(join(root, 'qa', 'marketing-readiness.json'), readiness(candidate));
  return candidate;
}

test('a non-marketing job is not held to the marketing floor', { skip: !hasFfmpeg }, () => {
  const root = join(scratch, 'explainer'); const candidate = job(root, { programForm: 'technical-story' });
  const r = run([root, candidate]); assert.equal(r.code, 0, r.out);
  const report = JSON.parse(readFileSync(join(root, 'qa', 'marketing-readiness-check.json'), 'utf8'));
  assert.equal(report.applies, false); assert.equal(report.ok, true);
});

test('marketing floor passes with a complete, candidate-bound rubric and cuts on the grid', { skip: !hasFfmpeg }, () => {
  const root = join(scratch, 'pass'); const candidate = job(root);
  const r = run([root, candidate]); assert.equal(r.code, 0, r.out);
  const report = JSON.parse(readFileSync(join(root, 'qa', 'marketing-readiness-check.json'), 'utf8'));
  assert.equal(report.ok, true); assert.equal(report.applies, true);
  assert.equal(report.candidate.sha256, sha(candidate));
  assert.equal(report.cutsOnBeat.onBeat, 3);
  assert.equal(report.cutsOnBeat.subdivision, 1);
  assert.equal(report.cutsOnBeat.gridPeriodSeconds, 0.5);
  for (const c of ['hook-2s', 'one-promise', 'designed-motion', 'sound-design', 'brand-end-card', 'cuts-on-beat', 'references', 'feed-test', 'no-fluff', 'candidate-binding']) assert.equal(report.checks[c], 'pass', c);
});

test('marketing floor fails closed on each criterion', { skip: !hasFfmpeg }, () => {
  const root = join(scratch, 'fail'); const candidate = job(root);
  const rp = join(root, 'qa', 'marketing-readiness.json');
  const expectFail = (over, pattern, label) => {
    writeJson(rp, readiness(candidate, over));
    const r = run([root, candidate]); assert.notEqual(r.code, 0, `${label} should fail`); assert.match(r.out, pattern, label);
  };
  expectFail({ hook: { atSeconds: 3.2, what: 'logo then the number', verdict: 'pass' } }, /hook lands at 3.2s; the floor is 2s/, 'late hook');
  expectFail({ hook: { atSeconds: null, what: 'the held-claim count fills the frame before any logo', verdict: 'pass' } }, /hook.atSeconds must be the measured time/, 'null hook time is not zero');
  expectFail({ hook: { atSeconds: '', what: 'the held-claim count fills the frame before any logo', verdict: 'pass' } }, /hook.atSeconds must be the measured time/, 'empty-string hook time is not zero');
  expectFail({ promise: { text: 'two things', count: 2, verdict: 'pass', evidence: 'M01 and M05 promise different outcomes' } }, /promise.count must be 1/, 'two promises');
  expectFail({ motion: { verdict: 'fail', evidence: 'static dashboard held 6 s at 0:03' } }, /motion needs verdict pass/, 'static motion');
  expectFail({ sound: { bed: false, designCues: 0, verdict: 'pass', evidence: 'voice only' } }, /sound.bed must be true/, 'no bed');
  expectFail({ brand: { kit: 'fixture-brand-2026', endCardAtSeconds: 1.0, cta: 'Book', verdict: 'pass' } }, /end card at 1s is not inside the last 8s/, 'early end card');
  expectFail({ brand: { kit: 'fixture-brand-2026', endCardAtSeconds: 8.5, cta: '', verdict: 'pass' } }, /brand.cta is required/, 'no CTA');
  expectFail({ references: readiness(candidate).references.slice(0, 2) }, /exactly 3 reference ads are required \(got 2\)/, 'two references');
  expectFail({ attentionCompetition: { winsAgainstReferences: false, evidence: 'the references open faster' } }, /does not win the viewer in a feed/, 'loses the feed');
  expectFail({ candidate: { path: 'output/cut.mp4', sha256: '0'.repeat(64), bytes: 1 } }, /not bound to this exact candidate/, 'stale candidate');
  expectFail({ reviewer: '' }, /reviewer is required/, 'unsigned');
  // cuts off the grid: 120 bpm = 0.5 s period; 2.17 / 4.33 / 6.61 are 170 / 170 / 110 ms off
  writeJson(rp, readiness(candidate));
  writeJson(join(root, 'plan', 'cue-sheet.json'), { generator: 'media-studio/build-cue-sheet', mode: 'mapped', durationSeconds: 10, edl: [{ startSeconds: 0 }, { startSeconds: 2.17 }, { startSeconds: 4.33 }, { startSeconds: 6.61 }], beats: [] });
  let r = run([root, candidate]); assert.notEqual(r.code, 0); assert.match(r.out, /0\/3 cuts land within 80 ms of the 120 bpm grid/);
  rmSync(join(root, 'plan', 'cue-sheet.json'));
  r = run([root, candidate]); assert.notEqual(r.code, 0); assert.match(r.out, /no edit decision list/);
  writeJson(join(root, 'plan', 'cue-sheet.json'), { generator: 'media-studio/build-cue-sheet', mode: 'mapped', durationSeconds: 10, edl: [{ startSeconds: 0 }, { startSeconds: 2.0 }, { startSeconds: 4.0 }, { startSeconds: 6.5 }], beats: [] });
  // no fluff is part of the floor
  writeJson(join(root, 'qa', 'narration-check.json'), { generator: 'media-studio/validate-narration', ok: false, errors: ['S02: version: "since last time"'], fluff: { perMinute: 2.4, count: 2 } });
  r = run([root, candidate]); assert.notEqual(r.code, 0); assert.match(r.out, /narration check failed \(1 error\(s\), 2.4 fluff\/min\)/);
  rmSync(join(root, 'qa', 'narration-check.json'));
  r = run([root, candidate]); assert.notEqual(r.code, 0); assert.match(r.out, /missing qa\/narration-check.json/);
  // missing review altogether
  rmSync(rp);
  r = run([root, candidate]); assert.notEqual(r.code, 0); assert.match(r.out, /Silence is not readiness/);
  assert.equal(existsSync(join(root, 'qa', 'marketing-readiness-check.json')), true);
});


test('explicit eighth-note grid preserves bed tempo, and still rejects off-grid cuts', { skip: !hasFfmpeg }, () => {
  const root = join(scratch, 'eighth'); const candidate = job(root);
  const rp = join(root, 'qa', 'marketing-readiness.json');
  const grid = { bpm: 112.5, subdivision: 2, offsetSeconds: 0, verdict: 'pass' };
  writeJson(rp, readiness(candidate, { cutsOnBeat: grid }));
  const cuts = [0, 0.8, 1.6, 2.4, 4.533333, 6.4];
  const cue = (times) => writeJson(join(root, 'plan', 'cue-sheet.json'), { mode: 'mapped', edl: times.map((startSeconds) => ({ startSeconds })), beats: [] });
  cue(cuts); let r = run([root, candidate]); assert.equal(r.code, 0, r.out);
  let report = JSON.parse(readFileSync(join(root, 'qa', 'marketing-readiness-check.json'), 'utf8'));
  assert.equal(report.cutsOnBeat.bpm, 112.5); assert.equal(report.cutsOnBeat.subdivision, 2);
  assert.equal(report.cutsOnBeat.gridPeriodSeconds, 60 / 225); assert.equal(report.cutsOnBeat.onBeat, 5);
  assert.equal(report.thresholds.beatToleranceMs, 80); assert.equal(report.thresholds.beatHitRatio, 0.9);
  cue([0, 0.8 + 0.12, 1.6 + 0.12, 2.4 + 0.12]);
  r = run([root, candidate]); assert.notEqual(r.code, 0); assert.match(r.out, /0\/3 cuts land within 80 ms/);
  cue(cuts);
  for (const subdivision of [0, 3, 8, 1.5, null, '2', 'NaN']) {
    writeJson(rp, readiness(candidate, { cutsOnBeat: { ...grid, subdivision } }));
    r = run([root, candidate]); assert.notEqual(r.code, 0, String(subdivision)); assert.match(r.out, /subdivision must be the integer 1, 2 or 4/);
  }
});


test('rhythmic grids must remain discriminating at the fixed tolerance', { skip: !hasFfmpeg }, () => {
  const root = join(scratch, 'dense-grid'); const candidate = job(root);
  for (const grid of [{ bpm: 112.5, subdivision: 4 }, { bpm: 220, subdivision: 2 }]) {
    writeJson(join(root, 'qa', 'marketing-readiness.json'), readiness(candidate, { cutsOnBeat: { ...grid, offsetSeconds: 0, verdict: 'pass' } }));
    const period = 60 / (grid.bpm * grid.subdivision);
    writeJson(join(root, 'plan', 'cue-sheet.json'), { mode: 'mapped', edl: [0, period * 5, period * 10].map((startSeconds) => ({ startSeconds })), beats: [] });
    const r = run([root, candidate]); assert.notEqual(r.code, 0); assert.match(r.out, /too dense for the fixed tolerance/);
  }
});
function speechJob(root) {
  const candidate = job(root, { soundMode: 'speech-only', producer: 'fixture editor' });
  const file = (name, value, raw = false) => { const path = join(root, name); if (raw) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, value); } else writeJson(path, value); return { path: name, sha256: sha(path) }; };
  const script = file('story/locked.txt', 'First phrase. Second phrase. Third phrase.', true);
  const creativeSource = file('originals/creative.txt', 'Owner creative brief: speech only, deliberate pauses.', true);
  const authorization = file('originals/speech-authorization.json', { schema: 'media-studio/speech-only-authorization/1', soundMode: 'speech-only', authorizedBy: 'fixture owner', reason: 'Deliberate speech-only creative intent from original brief.', creativeSource });
  const source = file('originals/alignment.json', { method: 'fixture measured alignment', phraseTimes: [[0,3],[3.2,6],[6.2,9.5]] });
  const clock = file('qa/speech-clock.json', { schema: 'media-studio/speech-edit-clock/1', candidateSha256: sha(candidate), method: 'measured accepted phrase alignment', uncertaintyMs: null, source, script, phrases: [{ startSeconds: 0, endSeconds: 3, text: 'First phrase.' }, { startSeconds: 3.2, endSeconds: 6, text: 'Second phrase.' }, { startSeconds: 6.2, endSeconds: 9.5, text: 'Third phrase.' }] });
  const observation = { verdict: 'pass', evidence: '0–10s whole file reviewed; deliberate speech remains clear and the transition does not mask words.' };
  const review = file('qa/speech-review.json', { schema: 'media-studio/speech-only-review/1', reviewer: 'independent fixture critic', independentOf: 'fixture editor', authorization, clock, candidate: { sha256: sha(candidate), bytes: statSync(candidate).size }, wholeFileSoundReviewed: true, wholeFileEditRhythmReviewed: true, coverage: [{ startSeconds: 0, endSeconds: 10 }], uncertainties: ['Phrase clock precision is unknown; no universal beat tolerance is asserted.'], clarity: observation, pauses: observation, pacing: observation, transitions: observation, edl: { path: 'plan/cue-sheet.json', sha256: sha(join(root, 'plan/cue-sheet.json')) }, cuts: [2, 4, 6.5].map((atSeconds, i) => ({ atSeconds, verdict: 'pass', relationship: 'continuous-speech', phraseIndices: [i], reason: 'Intentional visual progression within this continuing spoken phrase.', observedEffect: 'The exact cut preserves the thought and makes its next visual relationship readable.' })) });
  const r = readiness(candidate, { sound: { mode: 'speech-only', bed: false, designCues: 0, authorization, clock, review } }); delete r.cutsOnBeat;
  writeJson(join(root, 'qa/marketing-readiness.json'), r);
  return { candidate, r };
}

test('explicit authorized speech-only uses independent whole-file cut adjudication, not BPM', { skip: !hasFfmpeg }, () => {
  const root = join(scratch, 'speech-pass'); const { candidate } = speechJob(root);
  const r = run([root, candidate]); assert.equal(r.code, 0, r.out);
  const report = JSON.parse(readFileSync(join(root, 'qa/marketing-readiness-check.json')));
  assert.equal(report.cutsOnBeat, null); assert.equal(report.checks['cuts-on-beat'], undefined);
  assert.equal(report.checks['speech-edit-rhythm'], 'pass'); assert.equal(report.speechOnly.uncertaintyMs, null);
});

test('speech-only fails closed on authorization, provenance, coverage, clocks and cut adjudication', { skip: !hasFfmpeg }, () => {
  const mutations = [
    ['no-job-mode', (r, root) => { const j = JSON.parse(readFileSync(join(root, 'job.json'))); delete j.soundMode; writeJson(join(root, 'job.json'), j); }],
    ['no-authority', r => { delete r.sound.authorization; }],
    ['stale-authority', r => { r.sound.authorization.sha256 = '0'.repeat(64); }],
    ['stale-creative', (r, root) => { writeFileSync(join(root, 'originals/creative.txt'), 'changed'); }],
    ['stale-candidate', (r, root, v) => { v.candidate.sha256 = '0'.repeat(64); }],
    ['self-review', (r, root, v) => { v.reviewer = 'fixture editor'; }],
    ['partial-coverage', (r, root, v) => { v.coverage[0].endSeconds = 9; }],
    ['not-whole-rhythm', (r, root, v) => { v.wholeFileEditRhythmReviewed = false; }],
    ['hidden-uncertainty', (r, root, v) => { v.uncertainties = []; }],
    ['missing-cut', (r, root, v) => { v.cuts.pop(); }],
    ['wrong-cut', (r, root, v) => { v.cuts[0].atSeconds = 2.1; }],
    ['bad-phrase', (r, root, v) => { v.cuts[0].phraseIndices = [99]; }],
    ['failed-effect', (r, root, v) => { v.cuts[0].verdict = 'fail'; }],
    ['no-reason', (r, root, v) => { v.cuts[0].reason = ''; }],
    ['stale-clock', r => { r.sound.clock.sha256 = '0'.repeat(64); }],
    ['stale-edl', (r, root, v) => { v.edl.sha256 = '0'.repeat(64); }],
    ['missing-edl', (r, root) => { rmSync(join(root, 'plan/cue-sheet.json')); }],
    ['bad-clock', (r, root, v) => { const p = join(root, 'qa/speech-clock.json'); const c = JSON.parse(readFileSync(p)); c.phrases[1].startSeconds = -1; writeJson(p, c); r.sound.clock.sha256 = sha(p); v.clock = { ...r.sound.clock }; }],
    ['no-cta', r => { r.brand.cta = ''; }],
    ['lost-feed', r => { r.attentionCompetition.winsAgainstReferences = false; }],
    ['two-refs', r => { r.references.pop(); }],
    ['failed-narration', (r, root) => { writeJson(join(root, 'qa/narration-check.json'), { ok: false }); }],
    ['unknown-mode', r => { r.sound.mode = 'silent-waiver'; }],
  ];
  for (const [name, mutate] of mutations) {
    const root = join(scratch, `speech-${name}`); const { candidate, r } = speechJob(root);
    const p = join(root, 'qa/speech-review.json'), v = JSON.parse(readFileSync(p));
    mutate(r, root, v); writeJson(p, v); r.sound.review.sha256 = sha(p); writeJson(join(root, 'qa/marketing-readiness.json'), r);
    const result = run([root, candidate]); assert.notEqual(result.code, 0, `${name} must reject: ${result.out}`);
    const report = JSON.parse(readFileSync(join(root, 'qa/marketing-readiness-check.json')));
    const expected = { 'no-cta': 'brand-end-card', 'lost-feed': 'feed-test', 'two-refs': 'references', 'failed-narration': 'no-fluff', 'unknown-mode': 'sound-mode' }[name] ?? 'speech-edit-rhythm';
    assert.equal(report.checks[expected], 'fail', `${name} must fail its intended gate`);
    if (name === 'bad-clock') assert.match(report.errors.join('\n'), /invalid or overlapping phrase clocks/);
  }
});

test('speech-only rejects non-object roots in every mandatory evidence document', { skip: !hasFfmpeg }, () => {
  for (const document of ['authorization', 'clock', 'review']) for (const [kind, value] of [['null', null], ['false', false], ['zero', 0], ['array', []], ['string', '']]) {
    const root = join(scratch, `speech-root-${document}-${kind}`); const { candidate, r } = speechJob(root);
    const path = join(root, r.sound[document].path); writeJson(path, value); r.sound[document].sha256 = sha(path);
    if (document !== 'review') {
      const reviewPath = join(root, r.sound.review.path), review = JSON.parse(readFileSync(reviewPath));
      review[document] = { ...r.sound[document] }; writeJson(reviewPath, review); r.sound.review.sha256 = sha(reviewPath);
    }
    writeJson(join(root, 'qa/marketing-readiness.json'), r);
    const result = run([root, candidate]); assert.notEqual(result.code, 0, `${document}/${kind} must reject`);
    const report = JSON.parse(readFileSync(join(root, 'qa/marketing-readiness-check.json')));
    assert.match(report.errors.join('\n'), /evidence must be a JSON object/);
    assert.equal(report.checks['speech-edit-rhythm'], 'fail');
  }
});

test('speech-only rejects empty original direction, timing evidence and script', { skip: !hasFfmpeg }, () => {
  for (const document of ['creativeSource', 'source', 'script']) for (const [kind, value] of [['empty', ''], ['whitespace', ' \n\t']]) {
    const root = join(scratch, `speech-empty-${document}-${kind}`); const { candidate, r } = speechJob(root);
    const parent = document === 'creativeSource' ? 'authorization' : 'clock';
    const parentPath = join(root, r.sound[parent].path), evidence = JSON.parse(readFileSync(parentPath));
    const sourcePath = join(root, evidence[document].path); writeFileSync(sourcePath, value); evidence[document].sha256 = sha(sourcePath);
    writeJson(parentPath, evidence); r.sound[parent].sha256 = sha(parentPath);
    const reviewPath = join(root, r.sound.review.path), review = JSON.parse(readFileSync(reviewPath));
    review[parent] = { ...r.sound[parent] }; writeJson(reviewPath, review); r.sound.review.sha256 = sha(reviewPath);
    writeJson(join(root, 'qa/marketing-readiness.json'), r);
    const result = run([root, candidate]); assert.notEqual(result.code, 0, `${document}/${kind} must reject`);
    const report = JSON.parse(readFileSync(join(root, 'qa/marketing-readiness-check.json')));
    assert.match(report.errors.join('\n'), /original evidence must not be empty/);
    assert.equal(report.checks['speech-edit-rhythm'], 'fail');
  }
});
