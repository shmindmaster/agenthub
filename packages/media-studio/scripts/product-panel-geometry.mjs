// Editorial layout is not letterboxing. Judge the capture inside its declared panel,
// while retaining source identity/time evidence and all existing picture thresholds.
const finite = n => typeof n === 'number' && Number.isFinite(n);
const sha = value => /^[a-f0-9]{64}$/.test(value || '');

export function productPanelGeometry(rect, canvasWidth, canvasHeight, cropWidth, cropHeight, transform = null) {
  if (![canvasWidth, canvasHeight, cropWidth, cropHeight].every(n => finite(n) && n > 0)) throw new Error('panel canvas and source dimensions must be finite and positive');
  const explicit = rect != null;
  const panel = explicit ? { ...rect } : { x: 0, y: 0, width: canvasWidth, height: canvasHeight };
  // This declaration lives in the hash-bound compose map, not a best-match search.
  // Native FFmpeg composition retains its historical YUV scale/raster contract.
  const renderPipeline = panel.renderPipeline ?? 'ffmpeg-yuv';
  if (!['ffmpeg-yuv', 'browser-rgb'].includes(renderPipeline)) throw new Error('destinationRect renderPipeline must be ffmpeg-yuv or browser-rgb');
  if (!['x', 'y', 'width', 'height'].every(k => finite(panel[k])) || panel.x < 0 || panel.y < 0 || panel.width <= 0 || panel.height <= 0 || panel.x + panel.width > canvasWidth || panel.y + panel.height > canvasHeight) throw new Error('destinationRect must be finite, positive and inside the pre-caption canvas');
  const scale = Math.min(panel.width / cropWidth, panel.height / cropHeight);
  const fitted = { w: cropWidth * scale, h: cropHeight * scale };
  const bars = { left: (panel.width - fitted.w) / 2, right: (panel.width - fitted.w) / 2, top: (panel.height - fitted.h) / 2, bottom: (panel.height - fitted.h) / 2 };
  let sx = 1, sy = 1, px = 0, py = 0;
  if (transform) {
    sx = transform.scaleWidth / canvasWidth; sy = transform.scaleHeight / canvasHeight;
    px = transform.padX; py = transform.padY;
    if (![sx, sy, px, py].every(finite) || sx <= 0 || sy <= 0 || px < 0 || py < 0 || Math.abs(sx - sy) > 0.00001) throw new Error('panel mapping needs a valid aspect-preserving final encoder transform');
  }
  const encoded = { x: px + panel.x * sx, y: py + panel.y * sy, width: panel.width * sx, height: panel.height * sy };
  // Browser composition snaps the CSS box origin to the nearest device pixel
  // (151.5 -> 152). Keep authored coordinates for geometry/bounds measurements.
  const origin = renderPipeline === 'browser-rgb' ? Math.round : value => Math.ceil(value - 0.5);
  const raster = { x: origin(encoded.x), y: origin(encoded.y), width: Math.round(encoded.width), height: Math.round(encoded.height) };
  if (raster.width < 1 || raster.height < 1) throw new Error('destinationRect has no encoded pixels');
  return { explicit, panel, encoded, raster, scale, fitted, bars, renderPipeline };
}

export function panelSourceSample(binding, { candidateSha256, sourceSha256, groupStartSeconds, sampleSeconds, sourceDuration }) {
  if (!binding || !sha(binding.candidateSha256) || !sha(binding.sourceSha256) || binding.candidateSha256 !== candidateSha256 || binding.sourceSha256 !== sourceSha256) throw new Error('panel source binding must match the exact candidate and source SHA256');
  if (![binding.sourceStartSeconds, binding.playbackRate, groupStartSeconds, sampleSeconds, sourceDuration].every(finite) || binding.sourceStartSeconds < 0 || binding.playbackRate < 0 || sourceDuration <= 0 || sampleSeconds < groupStartSeconds) throw new Error('panel source clock must have finite nonnegative source time/rate and a valid sample');
  const sourceSeconds = binding.sourceStartSeconds + (sampleSeconds - groupStartSeconds) * binding.playbackRate;
  if (sourceSeconds >= sourceDuration) throw new Error('panel source sample exceeds the captured source duration');
  return sourceSeconds;
}

export function cropPanelGray(buffer, frameWidth, frameHeight, geometry) {
  const r = geometry.raster;
  if (!buffer || buffer.length !== frameWidth * frameHeight || r.x < 0 || r.y < 0 || r.x + r.width > frameWidth || r.y + r.height > frameHeight) throw new Error('encoded panel raster is outside decoded frame');
  const result = Buffer.alloc(r.width * r.height);
  for (let y = 0; y < r.height; y++) buffer.copy(result, y * r.width, (y + r.y) * frameWidth + r.x, (y + r.y) * frameWidth + r.x + r.width);
  return result;
}

export function panelReferenceFilter(crop, geometry) {
  if (!crop || !['x', 'y', 'w', 'h'].every(k => finite(crop[k])) || crop.x < 0 || crop.y < 0 || crop.w <= 0 || crop.h <= 0) throw new Error('panel source crop must be finite and positive');
  const { width, height } = geometry.raster;
  // Browser video frames are converted to RGB before CSS composition/resampling.
  // Resampling YUV and only then converting luma is a different reference image.
  const rgb = geometry.renderPipeline === 'browser-rgb' ? 'format=rgb24,' : '';
  return `crop=${crop.w}:${crop.h}:${crop.x}:${crop.y},${rgb}scale=${width}:${height}:force_original_aspect_ratio=decrease:flags=lanczos,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2,format=gray`;
}
