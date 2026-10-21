// Marketing-readiness floor: the reviewer's rubric file is held to the floor on the exact encoded candidate.
// Run: node --test packages/media-studio/tests/marketing-readiness.test.mjs   (needs ffmpeg/ffprobe for the candidate)
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync, existsSync } from 'node:fs';
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
  writeJson(join(root, 'qa', 'narration-check.json'), { generator: 'media-studio/validate-narration', ok: true, errors: [], fluff: { perMinute: 0, count: 0 } });
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
