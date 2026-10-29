import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

test('canonical picture gate validates explicit panels and fails closed on false bindings or geometry', () => {
  const root = mkdtempSync(join(tmpdir(), 'panel-gate-'));
  const ff = args => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-threads', '2', '-filter_threads', '1', '-y', ...args], { windowsHide: true, timeout: 60000, stdio: 'pipe' });
  const json = (file, value) => writeFileSync(join(root, file), JSON.stringify(value));
  const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
  try {
    for (const folder of ['capture', 'output', 'qa']) mkdirSync(join(root, folder));
    const source = join(root, 'capture/source.mp4'), candidate = join(root, 'output/candidate.mp4');
    ff(['-f', 'lavfi', '-i', 'testsrc2=size=960x600:rate=4:duration=2', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18', source]);
    ff(['-i', source, '-vf', 'scale=800:500:flags=lanczos,pad=1600:1000:400:200:color=0x304050', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18', candidate]);
    json('job.json', { deliveryProfile: 'briefing-board' });
    json('capture/receipt.json', { clips: { proof: { file: 'source.mp4', viewport: { width: 960, height: 600 }, deviceScaleFactor: 1, recast: 'noZoom' } } });
    const group = { clipId: 'proof', file: 'source.mp4', segments: ['proof'], startSeconds: 0, needSeconds: 2, destinationRect: { x: 400, y: 200, width: 800, height: 500 }, sourceBinding: { candidateSha256: hash(candidate), sourceSha256: hash(source), sourceStartSeconds: 0, playbackRate: 1 } };
    let selectedCandidate = candidate, finalEncoderTransform;
    const run = patch => {
      json('output/film-compose-map.json', { width: 1600, height: 1000, finalEncoderTransform, groups: [{ ...group, ...patch }] });
      const result = spawnSync(process.execPath, [join(dirname(fileURLToPath(import.meta.url)), '../scripts/validate-picture-integrity.mjs'), root, selectedCandidate], { windowsHide: true, encoding: 'utf8', timeout: 60000 });
      return { result, report: JSON.parse(readFileSync(join(root, 'qa/picture-integrity.json'), 'utf8')) };
    };
    const clean = run({});
    assert.equal(clean.result.status, 0, clean.result.stdout + clean.result.stderr);
    assert.ok(clean.report.clips[0].findings.some(f => f.check === 'panel-source' && f.status === 'pass'));
    assert.ok(clean.report.inputs['panelSource:proof']);
    for (const patch of [
      { destinationRect: { ...group.destinationRect, x: 420 } },
      { destinationRect: { ...group.destinationRect, width: 740 } },
      { destinationRect: { ...group.destinationRect, x: -1 } },
      { sourceBinding: undefined },
      { sourceBinding: { ...group.sourceBinding, sourceSha256: '0'.repeat(64) } },
      { sourceBinding: { ...group.sourceBinding, sourceStartSeconds: 1 } },
    ]) assert.notEqual(run(patch).result.status, 0, `false panel must fail: ${JSON.stringify(patch)}`);
    selectedCandidate = join(root, 'output/captioned.mp4');
    ff(['-i', candidate, '-vf', 'scale=1280:800:flags=lanczos,pad=1600:1000:160:0:color=0x101524', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18', selectedCandidate]);
    finalEncoderTransform = { candidateSha256: hash(selectedCandidate), sourceSha256: hash(candidate), sourceFile: 'output/candidate.mp4', sourceWidth: 1600, sourceHeight: 1000, outputWidth: 1600, outputHeight: 1000, scaleWidth: 1280, scaleHeight: 800, padX: 160, padY: 0, crop: false, purpose: 'external-caption-band' };
    const captioned = run({ sourceBinding: { ...group.sourceBinding, candidateSha256: hash(selectedCandidate) } });
    assert.equal(captioned.result.status, 0, captioned.result.stdout + captioned.result.stderr);
    assert.equal(captioned.report.clips[0].destinationRect.encoded.x, 480);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
