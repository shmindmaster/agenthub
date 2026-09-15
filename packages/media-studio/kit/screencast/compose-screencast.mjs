// Assemble the silent picture for a screencast-led video from captured clips, aligned to the locked narration timeline.
// Usage: node compose-screencast.mjs <jobRoot> <base>
// Inputs (all under <jobRoot>, the external job workspace — never a product repo):
//   story/narration-timeline.json  { durationSeconds, segments: [{ id, scene, text, startSeconds, durationSeconds }] }
//   capture/manifest.json          { clips: [{ id, file: "clips/x.webm|mp4|png", segments: ["S03","S04"], ...hints }] }
//   story/storyboard.json          optional; beats supply kicker/title/subtitle/footer for auto cards
//   job.json                       optional; `title` and `cardFooter` feed auto cards
// Per-clip hints (see README.md): trimStart, trimEnd, speed, skip, fit: cut|hold|fit|fitpad, overlay.
// A segment with no clip holds the previous clip's last frame. A png is a card, looped.
// Output: output/<base>-silent.mp4 (1600x1000, 30 fps, yuv420p). Prints a per-segment coverage table.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [jobRoot, base] = process.argv.slice(2);
if (!jobRoot || !base) { console.error('usage: node compose-screencast.mjs <jobRoot> <base>'); process.exit(2); }
const here = path.dirname(fileURLToPath(import.meta.url));
const W = 1600, H = 1000, FPS = 30;
const tl = JSON.parse(fs.readFileSync(path.join(jobRoot, 'story', 'narration-timeline.json'), 'utf8'));
const man = JSON.parse(fs.readFileSync(path.join(jobRoot, 'capture', 'manifest.json'), 'utf8'));
// Accept both shapes: { clips:[{id,file,segments}] } and the validator-shaped { captures:[{storyboardSegmentId, segments, clip?}] }.
// A job may pre-assemble one exact-length plate per scene (manifest.composeClips); it wins over the raw capture record.
const rawClips = man.composeClips || man.clips || man.entries || man.captures || [];
const clips = rawClips.map((c) => {
  const id = c.id || c.scenario || c.storyboardSegmentId;
  let file = c.file || c.clip || c.video || c.output;
  if (!file) for (const ext of ['webm', 'mp4', 'png']) { if (fs.existsSync(path.join(jobRoot, 'capture', 'clips', `${id}.${ext}`))) { file = `clips/${id}.${ext}`; break; } }
  return { ...c, id, file, segments: c.segments || [c.storyboardSegmentId] };
}).filter((c) => c.file);
// Map clips to timeline segments. A clip may name a segment id (S06a / S12), a scene id (S06) that
// spans several paragraph segments, or several of either. When several clips name one scene they
// are dealt to that scene's segments in order; leftovers attach to the last segment as extra sources.
const bySeg = new Map();
const segsByScene = new Map();
for (const seg of tl.segments) { if (!segsByScene.has(seg.scene)) segsByScene.set(seg.scene, []); segsByScene.get(seg.scene).push(seg.id); }
const sceneQueue = new Map();
for (const c of clips) {
  for (const key of c.segments || []) {
    if (!key) continue;
    if (tl.segments.some((s) => s.id === key)) { bySeg.set(key, c); continue; }
    const scene = key.replace(/[a-z]$/, '');
    const targets = segsByScene.get(scene) || segsByScene.get(key) || [];
    if (!targets.length) { console.error('clip', c.id, 'names unknown segment/scene', key); continue; }
    const q = sceneQueue.get(scene) || 0; sceneQueue.set(scene, q + 1);
    const target = targets[Math.min(q, targets.length - 1)];
    if (bySeg.has(target) && bySeg.get(target) !== c) { const prev = bySeg.get(target); prev.extras = [...(prev.extras || []), c]; }
    else bySeg.set(target, c);
  }
}
// Card-only segments: render a typeset card from the storyboard beat when no clip exists.
const sbPath = path.join(jobRoot, 'story', 'storyboard.json');
const sb = fs.existsSync(sbPath) ? JSON.parse(fs.readFileSync(sbPath, 'utf8')) : null;
const beats = sb ? (sb.beats || sb.scenes || []) : [];
const job = (() => { try { return JSON.parse(fs.readFileSync(path.join(jobRoot, 'job.json'), 'utf8')); } catch { return {}; } })();
const jobTitle = job.title || '';
for (const seg of tl.segments) {
  if (bySeg.has(seg.id)) continue;
  const png = path.join(jobRoot, 'capture', 'clips', `${seg.id}-card.png`);
  if (!fs.existsSync(png)) {
    const b = beats.find((x) => x.id === seg.id || (x.segments || []).includes(seg.id)) || {};
    const spec = { kicker: b.kicker || jobTitle, title: b.title || (seg.text.split(/[.!?]/)[0] || '').slice(0, 90), subtitle: b.subtitle || '', footer: b.footer || job.cardFooter || '' };
    execFileSync('node', [path.join(here, 'render-card.mjs'), png, JSON.stringify(spec)], { stdio: 'ignore' });
  }
  const card = { id: `${seg.id}-card`, file: `clips/${seg.id}-card.png`, segments: [seg.id], autoCard: true };
  clips.push(card); bySeg.set(seg.id, card);
}

const probe = (f) => { try { return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString()); } catch { return 0; } };
const tmp = path.join(jobRoot, 'output', '_parts'); fs.mkdirSync(tmp, { recursive: true });

// Group consecutive segments that share a clip so a long clip plays continuously across them.
const groups = [];
for (const seg of tl.segments) {
  const clip = bySeg.get(seg.id) || null;
  const last = groups[groups.length - 1];
  if (last && last.clip === clip && clip) { last.segments.push(seg); last.duration += seg.durationSeconds; }
  else groups.push({ clip, segments: [seg], duration: seg.durationSeconds, start: seg.startSeconds });
}

const parts = [];
const rows = [];
let prevFile = null;
groups.forEach((g, i) => {
  const out = path.join(tmp, `part-${String(i).padStart(3, '0')}.mp4`);
  const dur = g.duration.toFixed(3);
  let src = g.clip ? path.join(jobRoot, 'capture', g.clip.file) : prevFile;
  if (!src) throw new Error(`segment ${g.segments[0].id} has no clip and nothing precedes it`);
  if (g.clip && g.clip.extras && g.clip.extras.length) {
    // pre-concatenate the clip and its extras into one source so the slot plays them in order
    const srcs = [g.clip, ...g.clip.extras].map((c) => path.join(jobRoot, 'capture', c.file));
    const listP = path.join(tmp, `extras-${i}.txt`);
    const normed = srcs.map((f, k) => { const o = path.join(tmp, `extras-${i}-${k}.mp4`); execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', f, '-vf', `scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2,fps=${FPS},format=yuv420p`, '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', o]); return o; });
    fs.writeFileSync(listP, normed.map((p) => `file '${p.replace(/\\/g, '/')}'`).join('\n'));
    src = path.join(tmp, `extras-${i}.mp4`);
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', listP, '-c', 'copy', src]);
  }
  const isImage = /\.(png|jpg)$/i.test(src);
  // Per-clip edit hints from the manifest: trimStart (s), trimEnd (s), speed (>1 = faster, applied to the
  // whole clip; use for real wait time such as a production query), skip: [[a,b],...] (seconds to drop).
  const hints = g.clip || {};
  if (!isImage && ((hints.skip && hints.skip.length) || hints.trimStart || hints.trimEnd || hints.speed)) {
    const t0 = Number(hints.trimStart || 0), t1 = hints.trimEnd ? Number(hints.trimEnd) : probe(src);
    const keep = [];
    let cur = t0;
    for (const [a, b] of (hints.skip || []).slice().sort((x, y) => x[0] - y[0])) { if (a > cur) keep.push([cur, Math.min(a, t1)]); cur = Math.max(cur, b); }
    if (cur < t1) keep.push([cur, t1]);
    const sp = Number(hints.speed || 1);
    const fc = keep.map(([a, b], k) => `[0:v]trim=start=${a}:end=${b},setpts=(PTS-STARTPTS)/${sp}[k${k}]`).join(';') + ';' + keep.map((_, k) => `[k${k}]`).join('') + `concat=n=${keep.length}:v=1:a=0[ed]`;
    const edited = path.join(tmp, `edited-${i}.mp4`);
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', src, '-filter_complex', fc, '-map', '[ed]', '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', '-r', String(FPS), edited]);
    src = edited;
  }
  const srcDur = isImage ? 0 : probe(src);
  const fit = g.clip?.fit || (srcDur > g.duration ? 'cut' : 'hold');
  let vf = `scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2,fps=${FPS},format=yuv420p`;
  let args;
  if (isImage) args = ['-loop', '1', '-t', dur, '-i', src, '-vf', vf];
  else if (!g.clip) args = ['-sseof', '-0.1', '-i', src, '-vf', `${vf},tpad=stop_mode=clone:stop_duration=${dur}`, '-t', dur]; // hold previous last frame
  else if ((fit === 'fitpad' || fit === 'hold') && srcDur < g.duration) args = ['-i', src, '-vf', `${vf},tpad=stop_mode=clone:stop_duration=${(g.duration - srcDur + 0.5).toFixed(3)}`, '-t', dur];
  else if (fit === 'fit' && srcDur > 0) args = ['-i', src, '-vf', `setpts=PTS*${(g.duration / srcDur).toFixed(4)},${vf}`, '-t', dur]; // fit: retime the clip to the narration
  else args = ['-i', src, '-vf', vf, '-t', dur]; // cut: play from the start, stop at the narration end
  if (g.clip && g.clip.overlay) {
    // annotation overlay (transparent PNG, 1600x1000, from render-overlay.mjs): apply after scaling so the boxes align with the frame
    const ov = path.join(jobRoot, 'capture', g.clip.overlay);
    if (!fs.existsSync(ov)) throw new Error(`clip ${g.clip.id} names overlay ${g.clip.overlay} which does not exist`);
    const vfIdx = args.indexOf('-vf'); const baseVf = args[vfIdx + 1]; args.splice(vfIdx, 2);
    const inIdx = args.indexOf('-i'); args.splice(inIdx + 2, 0, '-i', ov);
    args.push('-filter_complex', `[0:v]${baseVf}[b];[b][1:v]overlay=0:0:format=auto,format=yuv420p[v]`, '-map', '[v]');
  }
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args, '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', '-r', String(FPS), out]);
  parts.push(out); prevFile = src;
  rows.push(`${g.segments.map((s) => s.id).join('+').padEnd(16)} ${(g.clip ? g.clip.id : '(hold prev)').padEnd(28)} need=${g.duration.toFixed(1).padStart(6)}s clip=${srcDur.toFixed(1).padStart(6)}s ${fit}${g.clip && g.clip.overlay ? ' +overlay' : ''}`);
});
const list = path.join(tmp, 'concat.txt');
fs.writeFileSync(list, parts.map((p) => `file '${p.replace(/\\/g, '/')}'`).join('\n'));
const outFile = path.join(jobRoot, 'output', `${base}-silent.mp4`);
execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-vf', `fade=t=in:st=0:d=0.5,fade=t=out:st=${(tl.durationSeconds - 0.8).toFixed(2)}:d=0.8,format=yuv420p`, '-c:v', 'libx264', '-preset', 'medium', '-crf', '17', '-r', String(FPS), '-movflags', '+faststart', outFile]);
const finalDur = probe(outFile);
console.log(rows.join('\n'));
console.log(JSON.stringify({ ok: true, out: outFile, pictureSeconds: finalDur, timelineSeconds: tl.durationSeconds, delta: +(finalDur - tl.durationSeconds).toFixed(2) }));
