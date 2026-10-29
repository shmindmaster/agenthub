// Receipt-to-picture mapping only. This does not align speech or prove an encode.
// Preserve the real renderer anchors; never replace them with an average speed.
export function piecewiseCaptureClock(group, { sourceSha256, receiptSha256 } = {}) {
  const w = group.actualCaptureWindow;
  if (!Array.isArray(w?.piecewise_time_map)) throw Error('missing piecewise capture map');
  const a = w.piecewise_time_map;
  const n = w.output_frames, seconds = w.output_seconds;
  const fps = n / seconds;
  const near = (x, y) => Number.isFinite(x) && Number.isFinite(y) && Math.abs(x-y) <= 1e-6;
  if (!Number.isInteger(n) || n <= 0 || !Number.isFinite(seconds) || seconds <= 0 || !Number.isFinite(fps) || fps <= 0 || !Number.isInteger(w.output_start_frame) || w.output_start_frame < 0 || !near(group.startSeconds, w.output_start_frame / fps) || !near(group.needSeconds, seconds)) throw Error('piecewise output clock differs from compose group');
  if (!/^[a-f0-9]{64}$/.test(w.source_sha256 ?? '') || w.source_sha256 !== sourceSha256 || w.source_sha256 !== receiptSha256 || w.clipId !== group.clipId) throw Error('piecewise source/receipt identity differs');
  if (a.length < 2 || a.some((p,i) => !Number.isInteger(p.output_frame) || p.output_frame < 0 || !Number.isFinite(p.source_seconds) || p.source_seconds < 0 || (i && (p.output_frame <= a[i-1].output_frame || p.source_seconds <= a[i-1].source_seconds)))) throw Error('piecewise anchors must be finite and strictly increasing');
  const first = a[0], last = a.at(-1);
  if (last.output_frame-first.output_frame !== n || !near(first.source_seconds,w.source_start_seconds) || !near(last.source_seconds,w.source_end_seconds)) throw Error('piecewise anchors do not cover the complete declared source/output window');
  return {
    sourceToProgram(t) {
      if (!Number.isFinite(t) || t < first.source_seconds || t > last.source_seconds) return null;
      // Adjacent windows may share an endpoint. The caller owns beat selection.
      for (let i=1;i<a.length;i++) {
        const lo=a[i-1], hi=a[i];
        if (t <= hi.source_seconds) {
          const frame = lo.output_frame + (t-lo.source_seconds)*(hi.output_frame-lo.output_frame)/(hi.source_seconds-lo.source_seconds);
          return group.startSeconds + (frame-first.output_frame)/fps;
        }
      }
      return null;
    },
    evidence: { kind:'receipt-to-piecewise-picture', actualCaptureWindow:w, framesPerSecond:fps,
      limitations:['Renderer-declared picture transform, not new forced alignment or encoded correspondence proof','Capture receipt clock and source hash must match; speech uncertainty is unchanged'] },
  };
}
