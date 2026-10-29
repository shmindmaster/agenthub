// Run remotely: node --test tests/product-panel-{geometry,encoded}.test.mjs
// Real encoded pixel negative controls for the helper used by the picture gate.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { productPanelGeometry, cropPanelGray, panelReferenceFilter } from '../scripts/product-panel-geometry.mjs';
import { meanAbsoluteDifference } from '../scripts/final-encoder-transform.mjs';

const ff = args => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-threads', '2', '-filter_threads', '1', '-filter_complex_threads', '1', ...args], { windowsHide: true, timeout: 60000, maxBuffer: 8 << 20 });
const frame = (path, filter = 'format=gray') => ff(['-i', path, '-frames:v', '1', '-vf', filter, '-f', 'rawvideo', 'pipe:1']);

test('real encoded panel matches only the exact source, destination position and size', () => {
  const root = mkdtempSync(join(tmpdir(), 'panel-encoded-'));
  try {
    const source = join(root, 'source.mkv'), candidate = join(root, 'candidate.mkv');
    ff(['-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=1:duration=1', '-c:v', 'ffv1', source]);
    ff(['-i', source, '-vf', 'scale=256:144:flags=lanczos,pad=320:180:32:18:color=0x304050', '-c:v', 'libx264', '-crf', '18', '-preset', 'ultrafast', '-f', 'matroska', candidate]);
    const pixels = frame(candidate);
    const rect = { x: 32, y: 18, width: 256, height: 144 };
    const geometry = r => productPanelGeometry(r, 320, 180, 320, 180);
    const difference = (r, path = source) => {
      const g = geometry(r);
      return meanAbsoluteDifference(cropPanelGray(pixels, 320, 180, g), frame(path, panelReferenceFilter({ x: 0, y: 0, w: 320, h: 180 }, g)));
    };
    assert.ok(difference(rect) <= 4, 'correct encoded panel must match within unchanged mean-luma threshold');
    assert.ok(difference({ ...rect, x: 40 }) > 4, 'wrong offset must fail on encoded pixels');
    assert.ok(difference({ ...rect, width: 236 }) > 4, 'wrong size must fail on encoded pixels');
    const replacement = join(root, 'replacement.mkv');
    ff(['-i', source, '-vf', 'negate', '-c:v', 'ffv1', replacement]);
    assert.ok(difference(rect, replacement) > 4, 'replaced source must fail on encoded pixels');
    const stretched = join(root, 'stretched.mkv');
    ff(['-i', source, '-vf', 'scale=256:128:flags=lanczos,pad=320:180:32:18:color=black', '-c:v', 'ffv1', stretched]);
    const expected = frame(source, panelReferenceFilter({ x: 0, y: 0, w: 320, h: 180 }, geometry(rect)));
    assert.ok(meanAbsoluteDifference(cropPanelGray(frame(stretched), 320, 180, geometry(rect)), expected) > 4, 'stretch/internal bars must fail against the source fit');
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('declared browser RGB composition survives encode without relaxing source, offset or stretch checks', () => {
  const root = mkdtempSync(join(tmpdir(), 'panel-browser-rgb-'));
  try {
    const source = join(root, 'source.mkv'), candidate = join(root, 'candidate.mkv');
    ff(['-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=1:duration=1', '-c:v', 'ffv1', source]);
    // Known browser-equivalent pipeline: decoded RGB frame -> CSS-size RGB
    // composition at device-pixel-rounded origin -> final YUV420 H.264 encode.
    // This fixture is independent of panelReferenceFilter and its raster helper.
    ff(['-i', source, '-vf', 'format=rgb24,scale=256:144:flags=lanczos,pad=320:180:32:18:color=0x304050,format=yuv420p', '-c:v', 'libx264', '-crf', '18', '-preset', 'ultrafast', candidate]);
    const rect = { x: 31.5, y: 18, width: 256, height: 144, renderPipeline: 'browser-rgb' };
    const g = productPanelGeometry(rect, 320, 180, 320, 180);
    assert.equal(g.raster.x, 32);
    const pixels = frame(candidate);
    const expected = frame(source, panelReferenceFilter({ x: 0, y: 0, w: 320, h: 180 }, g));
    assert.ok(meanAbsoluteDifference(cropPanelGray(pixels, 320, 180, g), expected) <= 4, 'declared RGB reference must pass unchanged threshold');
    const wrongOffset = productPanelGeometry({ ...rect, x: 39.5 }, 320, 180, 320, 180);
    assert.ok(meanAbsoluteDifference(cropPanelGray(pixels, 320, 180, wrongOffset), expected) > 4, 'wrong browser origin must still fail');
    const replacement = join(root, 'replacement.mkv');
    ff(['-i', source, '-vf', 'negate', '-c:v', 'ffv1', replacement]);
    assert.ok(meanAbsoluteDifference(cropPanelGray(pixels, 320, 180, g), frame(replacement, panelReferenceFilter({ x: 0, y: 0, w: 320, h: 180 }, g))) > 4, 'wrong source must still fail');
    const stretched = join(root, 'stretched.mkv');
    ff(['-i', source, '-vf', 'format=rgb24,scale=256:128:flags=lanczos,pad=320:180:32:18:color=black,format=yuv420p', '-c:v', 'libx264', '-crf', '18', '-preset', 'ultrafast', stretched]);
    assert.ok(meanAbsoluteDifference(cropPanelGray(frame(stretched), 320, 180, g), expected) > 4, 'RGB pipeline does not excuse stretch or internal bars');
  } finally { rmSync(root, { recursive: true, force: true }); }
});
