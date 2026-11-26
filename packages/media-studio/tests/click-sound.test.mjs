// Click and tap sounds, the effects stem and the effects-mix gate: pure synthesis, no ffmpeg. Run: node --test tests/click-sound.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const kit = pathToFileURL(join(pkg, 'kit', 'screencast')).href;
const C = await import(`${kit}/click-sound.mjs`);
const E = await import(`${kit}/stage-effects.mjs`);
const SR = C.SAMPLE_RATE;
const peakDb = (x) => { let p = 0; for (const v of x) p = Math.max(p, Math.abs(v)); return 20 * Math.log10(p); };
const node = (script, args) => spawnSync(process.execPath, [join(pkg, script), ...args], { encoding: 'utf8' });

test('same seed gives identical bytes, a different seed differs, for both kinds', () => {
  for (const kind of ['mouse', 'tap']) {
    const a = C.synthClick({ kind, seed: 42 }), b = C.synthClick({ kind, seed: 42 }), c = C.synthClick({ kind, seed: 43 });
    assert.ok(Buffer.from(a.buffer).equals(Buffer.from(b.buffer)), `${kind} repeat`);
    assert.ok(!Buffer.from(a.buffer).equals(Buffer.from(c.buffer)), `${kind} other seed`);
  }
  assert.equal(C.seedFor(1.5, 'Save'), C.seedFor(1.5, 'Save'));
  assert.notEqual(C.seedFor(1.5, 'Save'), C.seedFor(1.5, 'Open'));
});

test('variation stays within +-1 dB and +-2% and actually varies', () => {
  const gains = new Set(), pitches = new Set();
  for (let seed = 1; seed <= 500; seed++) {
    const { gainDb, pitch } = C.drawVariation(C.mulberry32(seed));
    assert.ok(Math.abs(gainDb) <= 1 && Math.abs(pitch - 1) <= 0.02, `seed ${seed}: ${gainDb} dB, ${pitch}`);
    gains.add(gainDb.toFixed(3)); pitches.add(pitch.toFixed(4));
    const peak = peakDb(C.synthClick({ kind: 'mouse', seed })); // the press transient peaks at 0 dB before the seed's gain
    assert.ok(Math.abs(peak - gainDb) < 0.01, `peak ${peak} vs gain ${gainDb}`);
  }
  assert.ok(gains.size > 400 && pitches.size > 200);
});

test('shape: a mouse click is a press and a softer release 70 ms later, each transient 6-25 ms; a tap is one shorter, softer transient', () => {
  const m = C.synthClick({ kind: 'mouse', seed: 5 }), t = C.synthClick({ kind: 'tap', seed: 5 });
  const win = (x, a, b) => peakDb(x.subarray(Math.round(a * SR / 1000), Math.round(b * SR / 1000)));
  assert.ok(win(m, 68, 72) < win(m, 0, 3) - 3, 'release under the press');
  assert.ok(win(m, 68, 95) > -40, 'a release is there');
  assert.ok(m.length / SR * 1000 <= 96 && t.length / SR * 1000 <= 25, `lengths ${m.length / 48} ms, ${t.length / 48} ms`);
  for (let seed = 1; seed <= 100; seed++) assert.ok(peakDb(C.synthClick({ kind: 'tap', seed })) < peakDb(C.synthClick({ kind: 'mouse', seed })) - 3, `seed ${seed}`);
});

test('stem: a click starts within one 60 fps frame of its press and the stem has the film length', () => {
  const presses = [{ t: 1.2345, kind: 'mouse', label: 'A' }, { t: 3.0, kind: 'tap', label: 'B' }, { t: 7.777, kind: 'mouse', label: null }];
  const { samples, kept } = E.buildEffectsStem({ presses, durationSeconds: 10 });
  assert.equal(samples.length, 10 * SR);
  assert.equal(kept.length, 3);
  let peak = 0;
  for (const v of samples) peak = Math.max(peak, Math.abs(v));
  for (const p of presses) {
    let i = Math.round(p.t * SR) - Math.round(0.02 * SR);
    while (Math.abs(samples[i]) < peak * 0.01) i++;
    assert.ok(Math.abs(i / SR - p.t) < 1 / 60, `onset ${i / SR} vs press ${p.t}`);
  }
  for (let i = 0; i < Math.round(1.2 * SR); i++) assert.equal(samples[i], 0, 'silent before the first press');
});

test('stem: a press within 60 ms of the last kept one is dropped and listed', () => {
  const presses = [1.0, 1.03, 1.059, 1.06, 2.0, 2.0].map((t, i) => ({ t, kind: 'mouse', label: `p${i}` }));
  const { kept, dropped } = E.buildEffectsStem({ presses, durationSeconds: 4 });
  assert.deepEqual(kept.map((p) => p.t), [1, 1.06, 2]);
  assert.deepEqual(dropped.map((p) => p.t), [1.03, 1.059, 2]);
  assert.ok(dropped.every((p) => /within-60ms/.test(p.reason)));
  const outside = E.buildEffectsStem({ presses: [{ t: 9, kind: 'mouse' }], durationSeconds: 4 });
  assert.equal(outside.dropped[0].reason, 'outside-film');
});

test('stem: peaks at -20 dBFS alone and -26 dBFS under speech, and a tap stays softer than a mouse click in the same stem', () => {
  assert.equal(E.ALONE_PEAK_DBFS, -20);
  assert.equal(E.UNDER_SPEECH_PEAK_DBFS, -26);
  const presses = [{ t: 1, kind: 'mouse', label: 'm' }, { t: 3, kind: 'tap', label: 't' }];
  const alone = E.buildEffectsStem({ presses, durationSeconds: 5 });
  const under = E.buildEffectsStem({ presses, durationSeconds: 5, peakDbfs: E.UNDER_SPEECH_PEAK_DBFS });
  assert.ok(Math.abs(peakDb(alone.samples) + 20) < 0.001, `alone ${peakDb(alone.samples)}`);
  assert.ok(Math.abs(peakDb(under.samples) + 26) < 0.001, `under ${peakDb(under.samples)}`);
  assert.ok(peakDb(alone.samples.subarray(2.5 * SR, 4 * SR)) < peakDb(alone.samples.subarray(0.5 * SR, 2 * SR)) - 3);
  assert.equal(peakDb(E.buildEffectsStem({ presses: [], durationSeconds: 1 }).samples), -Infinity);
});

// ---- a hand-built job: two stage runs, the second a touch run
function makeJob(root, { clickSound } = {}) {
  mkdirSync(join(root, 'output'), { recursive: true });
  if (clickSound) writeFileSync(join(root, 'job.json'), JSON.stringify({ clickSound }));
  const plan = (mode, clicks, start) => ({ schema: 'media-studio/screen-stage-plan/1', film: { startSeconds: start }, cursor: { mode, samples: [], clicks, hidden: [] } });
  writeFileSync(join(root, 'output', 'demo-stage-plan-0.json'), JSON.stringify(plan('pointer', [{ t: 1.0, x: 10, y: 10, label: 'Open' }, { t: 3.0, x: 20, y: 20, label: 'Save' }, { t: 3.03, x: 20, y: 20, label: 'Save again' }], 2)));
  writeFileSync(join(root, 'output', 'demo-stage-plan-1.json'), JSON.stringify(plan('touch', [{ t: 0.5, x: 5, y: 5, label: 'Tap' }], 8)));
  writeFileSync(join(root, 'output', 'demo-compose-map.json'), JSON.stringify({ base: 'demo', pictureSeconds: 12, stagePlans: [
    { run: 0, file: 'output/demo-stage-plan-0.json', startSeconds: 2, durationSeconds: 5 },
    { run: 1, file: 'output/demo-stage-plan-1.json', startSeconds: 8, durationSeconds: 3 },
  ] }));
}
const withTemp = (fn) => { const root = mkdtempSync(join(tmpdir(), 'click-sound-')); try { return fn(root); } finally { rmSync(root, { recursive: true, force: true }); } };

test('pressesFromComposeMap: absolute film time is the run start plus the click time; touch runs give taps; clickSound off gives none', () => withTemp((root) => {
  makeJob(root);
  assert.deepEqual(E.pressesFromComposeMap(root, 'demo'), [
    { t: 3, kind: 'mouse', label: 'Open' }, { t: 5, kind: 'mouse', label: 'Save' }, { t: 5.03, kind: 'mouse', label: 'Save again' }, { t: 8.5, kind: 'tap', label: 'Tap' },
  ]);
  assert.equal(E.pressesFromComposeMap(root).length, 4, 'finds the only compose map when no base is given');
  writeFileSync(join(root, 'job.json'), JSON.stringify({ clickSound: 'off' }));
  assert.deepEqual(E.pressesFromComposeMap(root, 'demo'), []);
}));

test('CLI: writes the stem and its report; clickSound off writes nothing', () => withTemp((root) => {
  makeJob(root);
  const run = node('kit/screencast/stage-effects.mjs', [root, 'demo']);
  assert.equal(run.status, 0, run.stderr);
  const wav = readFileSync(join(root, 'output', 'demo-effects.wav')), report = JSON.parse(readFileSync(join(root, 'output', 'demo-effects.json'), 'utf8'));
  assert.equal(wav.length, 44 + 12 * SR * 2);
  assert.equal(wav.readUInt32LE(24), 48000);
  assert.deepEqual(report.presses.map((p) => p.t), [3, 5, 8.5]);
  assert.deepEqual(report.dropped.map((p) => p.t), [5.03]);
  assert.ok(Math.abs(report.peakDbfs + 20) < 0.01, `peak ${report.peakDbfs}`);
  assert.match(report.sha256, /^[0-9a-f]{64}$/);
  const under = node('kit/screencast/stage-effects.mjs', [root, 'demo', '--under-speech']);
  assert.equal(under.status, 0, under.stderr);
  assert.ok(Math.abs(JSON.parse(readFileSync(join(root, 'output', 'demo-effects.json'), 'utf8')).peakDbfs + 26) < 0.01);
  const off = mkdtempSync(join(tmpdir(), 'click-sound-off-'));
  try {
    makeJob(off, { clickSound: 'off' });
    assert.equal(node('kit/screencast/stage-effects.mjs', [off, 'demo']).status, 0);
    assert.throws(() => readFileSync(join(off, 'output', 'demo-effects.wav')));
  } finally { rmSync(off, { recursive: true, force: true }); }
}));

test('mix gate: a pad bed passes, a bright bed fails and names the press; the report is bound to both wavs', () => withTemp((root) => {
  makeJob(root);
  assert.equal(node('kit/screencast/stage-effects.mjs', [root, 'demo']).status, 0);
  const pad = join(root, 'pad.wav'), bright = join(root, 'pad-bright.wav'), fx = join(root, 'output', 'demo-effects.wav');
  const fixture = 'tests/fixtures/screen-stage/pad.mjs';
  assert.equal(node(fixture, [pad, '12']).status, 0);
  assert.equal(node(fixture, [bright, '12', '--bright']).status, 0);
  const again = join(root, 'pad2.wav');
  node(fixture, [again, '12']);
  assert.ok(readFileSync(pad).equals(readFileSync(again)), 'the pad is deterministic');

  const good = node('scripts/validate-effects-mix.mjs', [root, fx, pad]);
  assert.equal(good.status, 0, good.stdout + good.stderr);
  const report = JSON.parse(readFileSync(join(root, 'qa', 'effects-mix.json'), 'utf8'));
  assert.equal(report.ok, true);
  assert.equal(report.presses.length, 3);
  assert.ok(report.presses.every((p) => p.marginDb >= 6), JSON.stringify(report.presses));
  assert.match(report.effects.sha256, /^[0-9a-f]{64}$/);
  assert.notEqual(report.effects.sha256, report.bed.sha256);

  const bad = node('scripts/validate-effects-mix.mjs', [root, fx, bright, '--out', 'qa/bad.json']);
  assert.equal(bad.status, 1, bad.stdout);
  const badReport = JSON.parse(readFileSync(join(root, 'qa', 'bad.json'), 'utf8'));
  assert.equal(badReport.ok, false);
  assert.match(badReport.failures[0], /press at 3 s \("Open"\).*lower or duck the bed, or drop the clicks/);
  assert.notEqual(badReport.bed.sha256, report.bed.sha256);
}));

test('mix gate: presses under 60 ms apart and a stem above -20 dBFS fail', () => withTemp((root) => {
  makeJob(root);
  assert.equal(node('kit/screencast/stage-effects.mjs', [root, 'demo']).status, 0);
  const fx = join(root, 'output', 'demo-effects.wav'), pad = join(root, 'pad.wav');
  node('tests/fixtures/screen-stage/pad.mjs', [pad, '12']);
  const meta = JSON.parse(readFileSync(join(root, 'output', 'demo-effects.json'), 'utf8'));
  writeFileSync(join(root, 'output', 'demo-effects.json'), JSON.stringify({ ...meta, presses: [...meta.presses, { t: 5.03, kind: 'mouse', label: 'Save again' }] }));
  const close = node('scripts/validate-effects-mix.mjs', [root, fx, pad]);
  assert.equal(close.status, 1);
  assert.match(close.stdout, /under 60 ms apart/);

  const loud = E.buildEffectsStem({ presses: [{ t: 3, kind: 'mouse' }], durationSeconds: 12, peakDbfs: -12 });
  const loudWav = C.encodeWav16(loud.samples);
  writeFileSync(fx, loudWav);
  writeFileSync(join(root, 'output', 'demo-effects.json'), JSON.stringify({ ...meta, sha256: createHash('sha256').update(loudWav).digest('hex') }));
  const hot = node('scripts/validate-effects-mix.mjs', [root, fx, pad]);
  assert.equal(hot.status, 1);
  assert.match(hot.stdout, /above -20 dBFS/);
}));
