import test from 'node:test';
import assert from 'node:assert/strict';
import { productPanelGeometry, panelSourceSample, cropPanelGray, panelReferenceFilter } from '../scripts/product-panel-geometry.mjs';

const rect = { x: 151.5, y: 90, width: 1617, height: 910 };
const geometry = r => productPanelGeometry(r, 1920, 1080, 1920, 1080);
test('legacy whole-frame geometry is unchanged', () => {
  const g = geometry(null);
  assert.equal(g.explicit, false); assert.equal(g.scale, 1);
  assert.deepEqual(g.bars, { left: 0, right: 0, top: 0, bottom: 0 });
});
test('real fractional editorial panel preserves authored coordinates and fits only its interior', () => {
  const g = geometry(rect);
  assert.deepEqual(g.panel, rect); assert.equal(g.scale, 1617 / 1920);
  assert.equal(g.raster.x, 151); assert.equal(g.raster.width, 1617);
  assert.ok(g.bars.top < 1); assert.equal(g.bars.left, 0);
});
test('invalid, nonfinite and out-of-bounds rectangles fail closed', () => {
  for (const patch of [{ x: -1 }, { y: NaN }, { width: 0 }, { height: Infinity }, { width: 1920 }, { y: 200 }]) assert.throws(() => geometry({ ...rect, ...patch }), /destinationRect/);
});

test('declared browser RGB pipeline maps half-pixel CSS origins and converts before scaling', () => {
  const g = geometry({ ...rect, renderPipeline: 'browser-rgb' });
  assert.equal(g.raster.x, 152);
  assert.equal(g.panel.x, 151.5);
  assert.equal(g.renderPipeline, 'browser-rgb');
  const crop = { x: 0, y: 0, w: 1920, h: 1080 };
  assert.match(panelReferenceFilter(crop, g), /crop=1920:1080:0:0,format=rgb24,scale=1617:910/);
  assert.doesNotMatch(panelReferenceFilter(crop, geometry(rect)), /rgb24/);
  assert.throws(() => geometry({ ...rect, renderPipeline: 'auto-best-match' }), /renderPipeline/);
  const mapped = productPanelGeometry({ ...rect, renderPipeline: 'browser-rgb' }, 1920, 1080, 1920, 1080, { scaleWidth: 1536, scaleHeight: 864, padX: 192, padY: 0 });
  assert.equal(mapped.raster.x, 313);
  assert.equal(mapped.encoded.x, 313.2);
});
test('internal bars and upscale remain measurable, independent of editorial margins', () => {
  const bars = productPanelGeometry({ x: 20, y: 20, width: 1000, height: 900 }, 1920, 1080, 1920, 1080);
  assert.ok(bars.bars.top > 100);
  assert.equal(productPanelGeometry(rect, 1920, 1080, 800, 450).scale > 1.005, true);
});
test('final caption transform maps panel once while preserving its own coordinates', () => {
  const g = productPanelGeometry(rect, 1920, 1080, 1920, 1080, { scaleWidth: 1536, scaleHeight: 864, padX: 192, padY: 0 });
  assert.equal(g.encoded.x, 313.2); assert.equal(g.encoded.y, 72);
  assert.deepEqual(g.panel, rect);
  assert.throws(() => productPanelGeometry(rect, 1920, 1080, 1920, 1080, { scaleWidth: 1536, scaleHeight: 800, padX: 0, padY: 0 }), /aspect/);
});
const sample = { candidateSha256: 'a'.repeat(64), sourceSha256: 'b'.repeat(64), groupStartSeconds: 5, sampleSeconds: 6, sourceDuration: 20 };
const binding = { candidateSha256: sample.candidateSha256, sourceSha256: sample.sourceSha256, sourceStartSeconds: 10, playbackRate: 1 };
test('exact source identity and linear or held source clock are mandatory', () => {
  assert.equal(panelSourceSample(binding, sample), 11);
  assert.equal(panelSourceSample({ ...binding, playbackRate: 0 }, sample), 10);
  for (const patch of [{ sourceSha256: 'c'.repeat(64) }, { candidateSha256: 'c'.repeat(64) }, { sourceStartSeconds: -1 }, { playbackRate: NaN }, { sourceStartSeconds: 20 }]) assert.throws(() => panelSourceSample({ ...binding, ...patch }, sample));
});
test('panel raster extraction uses actual position and rejects a frame-size mismatch', () => {
  const g = productPanelGeometry({ x: 1.5, y: 1, width: 2, height: 2 }, 5, 4, 2, 2);
  const frame = Buffer.from(Array.from({ length: 20 }, (_, i) => i));
  assert.deepEqual([...cropPanelGray(frame, 5, 4, g)], [6, 7, 11, 12]);
  assert.throws(() => cropPanelGray(frame, 6, 4, g), /outside/);
  assert.match(panelReferenceFilter({ x: 0, y: 0, w: 2, h: 2 }, g), /scale=2:2:force_original_aspect_ratio=decrease/);
});
