// A full-master caption canvas is distinct from cropping a captured product viewport.
// This contract never exempts bars or distortion inside that product rectangle.
export function validateFinalEncoderTransform(t, candidateSha, width, height) {
  if (!t || t.candidateSha256 !== candidateSha || !/^[a-f0-9]{64}$/.test(t.sourceSha256 || '')) throw new Error('transform must bind exact candidate and source SHA256');
  const keys = ['sourceWidth', 'sourceHeight', 'outputWidth', 'outputHeight', 'scaleWidth', 'scaleHeight', 'padX', 'padY'];
  if (keys.some(k => !Number.isInteger(t[k]) || t[k] < 0) || !t.sourceWidth || !t.sourceHeight || !t.scaleWidth || !t.scaleHeight) throw new Error('transform geometry must use positive integer dimensions');
  if (t.crop !== false || !t.sourceFile || t.purpose !== 'external-caption-band') throw new Error('only an uncropped full-master external caption band is supported');
  if (t.sourceWidth !== width || t.sourceHeight !== height || t.outputWidth !== width || t.outputHeight !== height) throw new Error('transform must retain master and output canvas dimensions');
  if (t.scaleWidth > width || t.scaleHeight > height || t.padX + t.scaleWidth > width || t.padY + t.scaleHeight > height) throw new Error('transform rectangle exceeds canvas');
  if (Math.abs(t.scaleWidth / t.sourceWidth - t.scaleHeight / t.sourceHeight) > 0.00001) throw new Error('transform must preserve aspect ratio');
  return t;
}

export function cropGray(buf, width, x, y, w, h) {
  const out = Buffer.alloc(w * h);
  for (let row = 0; row < h; row++) buf.copy(out, row * w, (y + row) * width + x, (y + row) * width + x + w);
  return out;
}

export function meanAbsoluteDifference(a, b) {
  if (!a || !b || a.length !== b.length || !a.length) return Infinity;
  let sum = 0;
  for (let i = 0; i < a.length; i++) sum += Math.abs(a[i] - b[i]);
  return sum / a.length;
}
