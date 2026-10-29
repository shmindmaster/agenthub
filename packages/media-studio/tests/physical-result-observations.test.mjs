import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readPhysicalResultObservations, applyPhysicalResultObservations } from '../scripts/physical-result-observations.mjs';
import { receiptSemantics, declaredHold } from '../kit/screencast/sync-lib.mjs';

function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'physical-results-'));
  const put = (p, content) => { mkdirSync(join(root, p, '..'), { recursive: true }); writeFileSync(join(root, p), typeof content === 'string' ? content : JSON.stringify(content)); return { path: p, sha256: createHash('sha256').update(readFileSync(join(root, p))).digest('hex') }; };
  const source = put('capture/source.mp4', 'source identity');
  const receipt = { clips: { clip1: { file: 'source.mp4', sha256: source.sha256, expectations: [{ label: 'Approved', observed: true, observedAt: 2.3 }] } } };
  const inputs = { receipt: put('capture/receipt.json', receipt), composeMap: put('output/compose.json', { groups: ['retained'] }), cuePlan: put('story/cue-plan.json', { beats: ['S1'] }) };
  const doc = { schema: 'media-studio/physical-result-observations/1', producer: 'producer', reviewer: { identity: 'independent-reviewer', independent: true, method: 'Inspect exact decoded neighboring frames' }, candidate: put('output/final.mp4', 'candidate identity'), inputs: structuredClone(inputs), frameRate: { numerator: 30, denominator: 1 }, observations: [{ beat: 'S1', clip: 'clip1', receiptExpectationIndex: 0, label: 'Approved', previousFrame: 59, firstVisibleFrame: 60, region: { x: 10, y: 10, w: 90, h: 30 }, previousState: 'Approval pending', visibleState: 'Green Approved banner', previousEvidence: { ...put('qa/previous.png', 'prior pixels'), frame: 59 }, visibleEvidence: { ...put('qa/visible.png', 'result pixels'), frame: 60 } }] };
  const beats = [{ beat: 'S1', slot_start: 0, slot_end: 5, screen: { clip: 'clip1', visible_from: 0, visible_until: 5 }, actions: [{ action_time: 1 }], result: { label: 'Approved', receipt_expectation_index: 0, clip_time: 2.3, visible_at: 2.3 } }];
  const probe = { streams: [{ codec_type: 'video', avg_frame_rate: '30/1', r_frame_rate: '30/1', nb_frames: '150', width: 640, height: 360 }] };
  const path = join(root, 'qa/physical.json');
  // Unit tests inject deterministic decoded pixels; the separate encoded test uses real ffmpeg.
  const decode = (p, frame) => Buffer.alloc(90 * 30 * 4, frame === 59 || p.endsWith('previous.png') ? 1 : 2);
  return { root, path, doc, inputs, beats, probe, put, receipt, decode, read() { put('qa/physical.json', doc); return readPhysicalResultObservations(this); }, close() { rmSync(root, { recursive: true, force: true }); } };
}

test('exact frame overrides conservative poll without changing raw action/receipt clocks', () => {
  const f = fixture(); try {
    const proof = f.read(); applyPhysicalResultObservations(f.beats, proof);
    const b = f.beats[0]; assert.equal(b.result.visible_at, 2); assert.equal(b.result.poll_visible_at, 2.3);
    assert.equal(b.result.clip_time, 2.3); assert.equal(b.actions[0].action_time, 1);
    assert.equal(b.result.physical_observation.receipt_observed_at, 2.3);
    assert.equal(receiptSemantics(b, b.result, f.receipt, true), null);
    assert.equal(declaredHold(b, f.receipt).from, 2, 'physical onset stays a transition');
    applyPhysicalResultObservations(f.beats, proof, { verify: true });
    b.result.visible_at = 1.9; assert.throws(() => applyPhysicalResultObservations(f.beats, proof, { verify: true }), /differs/);
  } finally { f.close(); }
});

const negatives = {
  'wrong candidate hash': f => { f.doc.candidate.sha256 = 'f'.repeat(64); },
  'stale receipt': f => { f.doc.inputs.receipt.sha256 = 'f'.repeat(64); },
  'stale EDL': f => { f.doc.inputs.composeMap.sha256 = 'f'.repeat(64); },
  'stale cue plan': f => { f.doc.inputs.cuePlan.sha256 = 'f'.repeat(64); },
  'wrong FPS': f => { f.doc.frameRate.numerator = 25; },
  'non CFR candidate': f => { f.probe.streams[0].r_frame_rate = '60/1'; },
  'missing probed FPS': f => { delete f.probe.streams[0].avg_frame_rate; },
  'invalid probed FPS': f => { f.probe.streams[0].r_frame_rate = '0/0'; },
  'unknown frame count': f => { delete f.probe.streams[0].nb_frames; },
  'out of program frame': f => { f.doc.observations[0].firstVisibleFrame = 150; },
  'fractional frame': f => { f.doc.observations[0].firstVisibleFrame = 60.1; },
  'missing adjacent frame': f => { f.doc.observations[0].previousFrame = 58; },
  'wrong evidence hash': f => { f.doc.observations[0].visibleEvidence.sha256 = 'f'.repeat(64); },
  'evidence wrong frame': f => { f.doc.observations[0].visibleEvidence.frame = 61; },
  'wrong event ID': f => { f.doc.observations[0].receiptExpectationIndex = 1; },
  'wrong result state': f => { f.doc.observations[0].label = 'Saving'; },
  'wrong clip': f => { f.doc.observations[0].clip = 'other'; },
  'wrong beat': f => { f.doc.observations[0].beat = 'other'; },
  'offscreen result': f => { f.doc.observations[0].region.y = -1265; },
  'region exceeds viewport': f => { f.doc.observations[0].region.w = 1000; },
  'empty observation set': f => { f.doc.observations = []; },
  'duplicate event': f => { f.doc.observations.push(structuredClone(f.doc.observations[0])); },
  'self review': f => { f.doc.reviewer.identity = f.doc.producer; },
  'unknown reviewer': f => { f.doc.reviewer.independent = false; },
  'indistinct states': f => { f.doc.observations[0].previousState = f.doc.observations[0].visibleState; },
  'result outside retained beat': f => { f.beats[0].slot_start = 2.1; },
  'missing viewport clock': f => { delete f.beats[0].screen.visible_from; },
  'changed source bytes': f => { f.put('capture/source.mp4', 'tampered'); },
  'path traversal': f => { f.doc.candidate.path = '../outside.mp4'; },
  'evidence pixels differ': f => { f.decode = (p) => Buffer.alloc(90 * 30 * 4, p.endsWith('.mp4') ? 1 : 2); },
  'no actual pixel transition': f => { f.decode = () => Buffer.alloc(90 * 30 * 4, 1); },
};
for (const [name, mutate] of Object.entries(negatives)) test(`fails closed: ${name}`, () => { const f = fixture(); try { mutate(f); assert.throws(() => f.read(), /physical result observations:/); } finally { f.close(); } });

test('undeclared override is refused and no-sidecar ordinary result remains unchanged', () => {
  const f = fixture(); try {
    applyPhysicalResultObservations(f.beats, null, { verify: true }); assert.equal(f.beats[0].result.visible_at, 2.3);
    f.beats[0].result.physical_observation = {}; assert.throws(() => applyPhysicalResultObservations(f.beats, null, { verify: true }), /unbound/);
  } finally { f.close(); }
});

test('real encoded candidate binds exact adjacent cropped pixels; another valid image fails', () => {
  const f = fixture(); const run = (args) => { const r = spawnSync('ffmpeg', ['-v', 'error', '-y', '-threads', '2', '-filter_threads', '1', ...args], { windowsHide: true, encoding: 'utf8' }); assert.equal(r.status, 0, r.stderr); };
  try {
    run(['-f', 'lavfi', '-i', 'color=red:s=640x360:r=30:d=2', '-f', 'lavfi', '-i', 'color=blue:s=640x360:r=30:d=3', '-filter_complex_threads', '1', '-filter_complex', '[0:v][1:v]concat=n=2:v=1:a=0[v]', '-map', '[v]', '-c:v', 'libx264', '-threads', '2', '-pix_fmt', 'yuv420p', join(f.root, 'output/final.mp4')]);
    const rehash = (ref) => { ref.sha256 = createHash('sha256').update(readFileSync(join(f.root, ref.path))).digest('hex'); };
    rehash(f.doc.candidate);
    const extract = (frame, name) => { run(['-i', join(f.root, 'output/final.mp4'), '-vf', `select=eq(n\\,${frame}),crop=90:30:10:10:exact=1,format=rgba`, '-frames:v', '1', join(f.root, name)]); };
    extract(59, 'qa/previous.png'); extract(60, 'qa/visible.png');
    rehash(f.doc.observations[0].previousEvidence); rehash(f.doc.observations[0].visibleEvidence);
    delete f.decode; delete f.probe;
    const proof = f.read(); assert.equal(proof.observations.get('S1').seconds, 2);
    extract(59, 'qa/visible.png'); rehash(f.doc.observations[0].visibleEvidence);
    assert.throws(() => f.read(), /evidence pixels differ/);
  } finally { f.close(); }
});
