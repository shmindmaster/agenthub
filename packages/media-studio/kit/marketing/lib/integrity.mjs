// Picture integrity of every product shot, checked on each compose before anything renders. A product recording is
// shown whole, at no more than its recorded resolution, filling the frame: no stretch, no crop, no bars, no upscale.
// The one exception is a zoom the cue sheet declares (focus window `declaredZoom: true`) on a recording made at device
// scale, so the zoomed region still has at least one recorded pixel per output pixel.
const EPS = 0.01;

/**
 * @param {object} o
 * @param {{w:number,h:number}} o.band  frame area the recording occupies (output pixels)
 * @param {{width:number,height:number}} o.recorded  recorded video size (pixels)
 * @param {Array<{region:{x:number,y:number,width:number,height:number}, declaredZoom?:boolean, label?:string}>} o.windows
 * @returns {{ok:boolean, scaleX:number, scaleY:number, rows:object[], errors:string[]}}
 */
export function pictureIntegrity({ band, recorded, windows }) {
  const errors = [];
  const rows = [];
  const bandAspect = band.w / band.h;
  const srcAspect = recorded.width / recorded.height;
  if (Math.abs(bandAspect / srcAspect - 1) > EPS) errors.push(`recording ${recorded.width}x${recorded.height} (${srcAspect.toFixed(3)}) does not match the ${band.w}x${band.h} frame (${bandAspect.toFixed(3)}): capture at a viewport of this aspect`);
  for (const w of windows) {
    const r = w.region;
    const scaleX = band.w / (r.width * recorded.width);
    const scaleY = band.h / (r.height * recorded.height);
    const cropped = r.x > EPS || r.y > EPS || r.width < 1 - EPS || r.height < 1 - EPS;
    const row = { label: w.label || null, region: r, scaleX: +scaleX.toFixed(3), scaleY: +scaleY.toFixed(3), cropped, declaredZoom: !!w.declaredZoom };
    rows.push(row);
    if (Math.abs(scaleX / scaleY - 1) > EPS) errors.push(`${w.label || 'window'}: non-uniform scale ${row.scaleX} x ${row.scaleY} (stretch)`);
    if (scaleX > 1 + EPS) errors.push(`${w.label || 'window'}: upscales the recording ${row.scaleX}x (soft text); record at a larger viewport or device scale`);
    if (cropped && !w.declaredZoom) errors.push(`${w.label || 'window'}: crops the recording (region ${r.x},${r.y} ${r.width}x${r.height}) without a declared zoom`);
  }
  const worst = rows.reduce((m, r) => Math.max(m, r.scaleX), 0);
  return { ok: errors.length === 0, scaleX: +worst.toFixed(3), scaleY: +worst.toFixed(3), rows, errors };
}
