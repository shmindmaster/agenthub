// Stage 6: compose, per ratio. Builds the MarketingAd props (layout, focus-follow camera, kinetic captions), the
// compose map the gates read, the FFmpeg mix plan, then renders the picture with Remotion and finishes audio and
// the loudness-normalized encode with FFmpeg. `--prepare-only` stops after the props, map and plans (no render).
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { MODULE_ROOT, recordStage } from '../context.mjs';
import { alignBeat } from '../align.mjs';
import { cameraKeyframes, focusWindows, pointerTrack, readability, windowAt } from '../crop.mjs';
import { FRAMES, layoutFor, safeZoneErrors } from '../layout.mjs';
import { pictureIntegrity } from '../integrity.mjs';
import { normalizeCuts } from '../lint.mjs';
import { buildMixArgs, encodeArgs, loudnessTarget, loudnormMeasureArgs, parseLoudnorm, run } from '../mix.mjs';
import { lineBreaks, toSrt } from '../captions.mjs';
import { resolveClip } from './capture.mjs';
import { sfxKey } from './assets.mjs';
import { fileSha, readJson, round, writeJson } from '../util.mjs';

export const HOLD_PAD_MAX = 2.0;

const recorded = new Map();
/** Pixel size of a recording (ffprobe), cached per file. */
export function recordedSize(file) {
  if (!recorded.has(file)) {
    const out = execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', file], { encoding: 'utf8' }).trim();
    const [width, height] = out.split(',').map(Number);
    if (!(width > 0 && height > 0)) throw new Error(`cannot probe the size of ${file}`);
    recorded.set(file, { width, height });
  }
  return recorded.get(file);
}

/** Program time (seconds) a sound-effect cue lands at, or throws when an `action:` label is not in the receipt. */
export function cueTime(cue, seg, { actions = [], headTrim = 0, trimStart = 0, duration = 1 }) {
  if (cue === 'start') return round(seg.startSeconds + 0.12);
  if (cue === 'end') return round(seg.startSeconds + seg.durationSeconds - duration);
  if (cue.startsWith('at:')) return round(seg.startSeconds + Number(cue.slice(3)));
  const label = cue.slice(7);
  const hit = actions.find((a) => a.label === label && (a.type === 'click' || a.type === 'point' || a.type === 'type'));
  if (!hit) throw new Error(`sfx cue action:${label} is not an action in the capture receipt`);
  return round(seg.startSeconds + (hit.t - headTrim - trimStart));
}

/** Structural check of the MarketingAd props before anything renders: a bad prop is cheaper to find here than mid-render. */
export function validateProps(props, publicDir) {
  const errors = [];
  const need = (cond, msg) => { if (!cond) errors.push(msg); };
  need(Number.isInteger(props.width) && Number.isInteger(props.height) && props.fps === 30, 'frame size / fps');
  need(props.beats.length > 0, 'no beats');
  let end = 0;
  for (const b of props.beats) {
    need(Math.abs(b.startSec - end) < 0.011, `beat ${b.id} does not start where the previous one ends (${b.startSec} vs ${end})`);
    end = b.startSec + b.durationSec;
    if (b.kind === 'ui') {
      const c = b.clip;
      need(!!c, `ui beat ${b.id} has no clip`);
      if (!c) continue;
      need(existsSync(join(publicDir, c.src)), `clip file missing for ${b.id}: ${c.src}`);
      const cam = c.camera;
      need(cam.times.length >= 2 && ['x', 'y', 'w', 'h'].every((k) => cam[k].length === cam.times.length), `camera arrays of ${b.id} differ in length`);
      need(cam.times.every((t, i) => i === 0 || t > cam.times[i - 1]), `camera times of ${b.id} are not strictly increasing`);
      need(['x', 'y'].every((k) => cam[k].every((v) => v >= 0 && v <= 1)) && ['w', 'h'].every((k) => cam[k].every((v) => v > 0 && v <= 1)), `camera region of ${b.id} leaves the source`);
      need(cam.x.every((x, i) => x + cam.w[i] <= 1.0001) && cam.y.every((y, i) => y + cam.h[i] <= 1.0001), `camera region of ${b.id} overflows the source`);
      need(c.playSec > 0 && c.playSec <= b.durationSec + 0.001, `play length of ${b.id}`);
    }
    if (b.kind === 'broll') need(b.image && existsSync(join(publicDir, b.image.src)), `b-roll image missing for ${b.id}`);
  }
  need(Math.abs(end - props.durationSec) < 0.02, `beats end at ${end}, props say ${props.durationSec}`);
  for (const f of props.brand.fontFiles) need(existsSync(join(publicDir, f.src)), `font file missing: ${f.src}`);
  for (const c of props.captions) {
    need(c.endSec > c.startSec && c.words.length > 0 && c.words.length <= 7, 'caption chunk');
    need(!c.lines || c.lines.reduce((a, b) => a + b, 0) === c.words.length, 'caption line breaks must cover every word');
    need(!c.lines || c.words.length < 4 || c.lines.every((n) => n >= 2), 'a caption line holds a single word');
  }
  return errors;
}

export function buildRatioPlan(ctx, cut, ratio, { timeline, captions, voice, assets, capture }) {
  const layout = layoutFor(ratio, ctx.brand);
  const layoutErrors = safeZoneErrors(layout);
  if (layoutErrors.length) throw new Error(`layout violates the platform-safe area: ${layoutErrors.join('; ')}`);
  const frame = FRAMES[ratio];
  const beats = [];
  const groups = [];
  const gateSegments = [];
  const media = new Map();
  const warnings = [];
  const addMedia = (file, ext) => {
    const name = `${fileSha(file).slice(0, 16)}.${ext}`;
    media.set(name, file);
    return `media/${name}`;
  };
  const sfxPlan = [];
  const integrityRows = [];
  const lastIndex = cut.beats.length - 1;
  cut.beats.forEach((beat, i) => {
    const seg = timeline.segments.find((s) => s.id === beat.id);
    const base = { id: beat.id, kind: beat.kind, startSec: seg.startSeconds, durationSec: seg.durationSeconds, headline: beat.onScreenText };
    if (beat.kind === 'ui') {
      const clip = capture.find((c) => c.beatId === beat.id);
      const { entry } = resolveClip(ctx, beat);
      // The first narrated pointer action is cut onto its spoken word; ui.trimStart is only the fallback.
      let trimStart = beat.ui.trimStart || 0;
      let aligned = false;
      if (beat.ui.actions?.length && beat.ui.align !== false) {
        const a = alignBeat({ actions: beat.ui.actions, receiptActions: entry.actions, headTrim: clip.headTrimSeconds, wordsRel: seg.words.map((w) => ({ word: w.word, start: w.start - seg.startSeconds })), fallbackTrim: trimStart });
        if (a.aligned) { trimStart = a.trimStart; aligned = true; }
        if (a.note) warnings.push(`${beat.id}: ${a.note}`);
      }
      // An authored trimEnd (it kept a Recast zoom or a click out of the beat) still applies when the beat can be covered with it.
      const authoredEnd = beat.ui.trimEnd && (!aligned || beat.ui.trimEnd - trimStart >= seg.durationSeconds - HOLD_PAD_MAX) ? beat.ui.trimEnd : clip.clipSeconds;
      const clipEnd = Math.min(authoredEnd, clip.clipSeconds);
      const available = clipEnd - trimStart;
      if (!(available > 0)) throw new Error(`${beat.id}: trim leaves no clip`);
      const playSec = Math.min(seg.durationSeconds, available);
      const hold = seg.durationSeconds - playSec;
      if (hold > HOLD_PAD_MAX) throw new Error(`${beat.id}: the clip covers ${playSec.toFixed(1)}s of the ${seg.durationSeconds.toFixed(1)}s beat (hold ${hold.toFixed(1)}s > ${HOLD_PAD_MAX}s); shorten the narration, adjust trims, or recapture`);
      const track = pointerTrack(entry.actions, { headTrim: clip.headTrimSeconds, viewport: clip.viewport });
      const windows = focusWindows({ explicit: beat.ui.focus, track, clipStart: trimStart, clipEnd: trimStart + playSec, srcW: clip.viewport.width, srcH: clip.viewport.height, band: layout.uiBand, zoom: layout.zoom, contentLeft: ctx.brand.capture?.contentLeft || 0, contentInsetPx: ctx.brand.capture?.contentInsetPx ?? 24 });
      for (const w of windows) { const r = readability(w.scale); if (!r.ok) throw new Error(`${beat.id} ${ratio}: ${r.reason}`); }
      // Each ratio is its own native capture: the recording fills the frame at scale <= 1, uncropped unless a zoom is declared.
      const integrity = pictureIntegrity({ band: layout.uiBand, recorded: recordedSize(clip.file), windows: windows.map((w) => ({ region: w.region, declaredZoom: w.declaredZoom, label: `${beat.id}${w.label ? ` (${w.label})` : ''}` })) });
      integrityRows.push({ beat: beat.id, clip: clip.file, recorded: recordedSize(clip.file), ...integrity });
      if (!integrity.ok) throw new Error(`${beat.id} ${ratio}: picture integrity: ${integrity.errors.join('; ')}`);
      const camera = cameraKeyframes(windows, { clipStart: trimStart, duration: seg.durationSeconds });
      const src = addMedia(clip.file, 'webm');
      beats.push({ ...base, clip: { src, trimBeforeSec: trimStart, playSec: round(playSec, 3), srcW: clip.viewport.width, srcH: clip.viewport.height, camera } });
      const mid = windowAt(windows, trimStart + playSec / 2);
      groups.push({ segments: [beat.id], startSeconds: seg.startSeconds, needSeconds: seg.durationSeconds, clipId: beat.id, file: `clips/${beat.id}.webm`, heldFromPrevious: false, sourceRegion: mid.region, srcSeconds: clip.clipSeconds, fit: 'hold', trimStart: 0, speed: 1, edit: { trimStart, trimEnd: clipEnd, speed: 1, skip: [], headHold: 0, srcSeconds: clipEnd }, extras: false, overlay: null, isImage: false, windows });
      gateSegments.push({ id: beat.id, kind: 'ui', startSeconds: seg.startSeconds, durationSeconds: seg.durationSeconds, clipFile: clip.file, sourceRegion: mid.region, sourceRegions: windows.map((w) => w.region), clipStart: trimStart });
      for (const s of beat.sfx || []) {
        const duration = s.durationSeconds || 1;
        const key = sfxKey(s.prompt, duration);
        const asset = assets.items.find((a) => a.kind === 'sfx' && a.key === key);
        if (!asset) throw new Error(`${beat.id}: sfx "${s.prompt}" was not generated (run the assets stage)`);
        sfxPlan.push({ beatId: beat.id, file: join(ctx.jobDir, asset.path), startSec: cueTime(s.cue, seg, { actions: entry.actions, headTrim: clip.headTrimSeconds, trimStart, duration }), gainDb: s.gainDb ?? -14 });
      }
    } else if (beat.kind === 'broll') {
      const asset = assets.items.find((a) => a.kind === 'broll' && a.beat === `${cut.id}/${beat.id}`);
      if (!asset) throw new Error(`${beat.id}: b-roll not generated (run the assets stage)`);
      const file = asset.provider === 'stock' ? asset.path : join(ctx.jobDir, asset.path);
      beats.push({ ...base, image: { src: addMedia(file, 'png') } });
      gateSegments.push({ id: beat.id, kind: 'broll', startSeconds: seg.startSeconds, durationSeconds: seg.durationSeconds });
      groups.push({ segments: [beat.id], startSeconds: seg.startSeconds, needSeconds: seg.durationSeconds, clipId: beat.id, file: asset.path, heldFromPrevious: false, sourceRegion: null, srcSeconds: 0, fit: 'hold', trimStart: 0, speed: 1, edit: null, extras: false, overlay: null, isImage: true });
      for (const s of beat.sfx || []) sfxPlan.push({ beatId: beat.id, file: join(ctx.jobDir, assets.items.find((a) => a.kind === 'sfx' && a.key === sfxKey(s.prompt, s.durationSeconds || 1)).path), startSec: cueTime(s.cue, seg, { duration: s.durationSeconds || 1 }), gainDb: s.gainDb ?? -14 });
    } else {
      beats.push({ ...base, isCta: beat.kind === 'card' && i === lastIndex });
      gateSegments.push({ id: beat.id, kind: beat.kind, startSeconds: seg.startSeconds, durationSeconds: seg.durationSeconds });
      groups.push({ segments: [beat.id], startSeconds: seg.startSeconds, needSeconds: seg.durationSeconds, clipId: beat.id, file: `cards/${beat.id}.png`, heldFromPrevious: false, sourceRegion: null, srcSeconds: 0, fit: 'hold', trimStart: 0, speed: 1, edit: null, extras: false, overlay: null, isImage: true });
      for (const s of beat.sfx || []) sfxPlan.push({ beatId: beat.id, file: join(ctx.jobDir, assets.items.find((a) => a.kind === 'sfx' && a.key === sfxKey(s.prompt, s.durationSeconds || 1)).path), startSec: cueTime(s.cue, seg, { duration: s.durationSeconds || 1 }), gainDb: s.gainDb ?? -14 });
    }
  });
  const fontFiles = (ctx.brand.fonts.files || []).map((f) => ({ family: f.family, src: addMedia(f.file, f.file.split('.').pop()), weight: f.weight || 400 }));
  const c = ctx.brand.colors;
  const props = {
    ratio, width: frame.width, height: frame.height, fps: 30, durationSec: timeline.durationSeconds,
    layout: { uiBand: layout.uiBand, captionBox: layout.captionBox, ctaBox: layout.ctaBox, ctaPillFont: layout.ctaPillFont },
    brand: { productName: ctx.brand.product, colors: { primary: c.primary, foreground: c.foreground, background: c.background, accent: c.accent, onPrimary: c.onPrimary || '#ffffff', ...(c.emphasis ? { emphasis: c.emphasis } : {}) }, fontDisplay: ctx.brand.fonts.display, fontBody: ctx.brand.fonts.body, fontFiles },
    // The synthetic-data label and the AI-voice disclosure are end-card lines, not a chip over the product picture.
    label: ctx.spec.labels, disclosure: ctx.spec.voice.disclosure || undefined,
    logo: ctx.brand.logo ? addMedia(ctx.brand.logo, ctx.brand.logo.split('.').pop()) : undefined,
    beats, captions: captions.map((k) => ({ startSec: k.startSec, endSec: k.endSec, words: k.words, lines: lineBreaks(k.words, { maxWidthPx: Math.min(layout.captionBox.w, Math.round(0.82 * frame.width)), fontSize: layout.captionBox.fontSize }) })),
    emphasis: [...new Set(cut.beats.flatMap((b) => b.emphasis || []))],
    cta: { text: ctx.spec.cta.text, displayUrl: ctx.spec.cta.displayUrl || ctx.spec.cta.url.replace(/^https?:\/\//, '') },
  };
  const lines = voice.lines.map((l) => ({ file: join(ctx.jobDir, l.file), startSec: timeline.segments.find((s) => s.id === l.beatId).lineStartSeconds }));
  const musicAsset = assets.items.find((a) => a.kind === 'music');
  const music = musicAsset ? { file: join(ctx.jobDir, musicAsset.path), bedDb: ctx.spec.music?.bedDb ?? -12 } : null;
  return { layout, props, groups, gateSegments, media, sfxPlan, lines, music, warnings, integrity: integrityRows };
}

export async function composeStage(ctx) {
  const summary = {};
  for (const cut of normalizeCuts(ctx.spec)) {
    const timeline = readJson(join(ctx.jobDir, 'timing', cut.id, 'timeline.json'));
    const captionsAll = readJson(join(ctx.jobDir, 'timing', cut.id, 'captions.json')).chunks;
    const voice = readJson(join(ctx.jobDir, 'voice', `${cut.id}.lines.json`));
    const assetsPath = join(ctx.jobDir, 'assets', 'manifest.json');
    const assets = existsSync(assetsPath) ? readJson(assetsPath) : { items: [] };
    const capture = existsSync(join(ctx.jobDir, 'capture', `${cut.id}.json`)) ? readJson(join(ctx.jobDir, 'capture', `${cut.id}.json`)).clips : [];
    for (const ratio of cut.ratios) {
      const dir = join(ctx.jobDir, 'compose', ratio);
      mkdirSync(join(dir, 'public', 'media'), { recursive: true });
      const plan = buildRatioPlan(ctx, cut, ratio, { timeline, captions: captionsAll, voice, assets, capture });
      for (const [name, file] of plan.media) if (!existsSync(join(dir, 'public', 'media', name))) copyFileSync(file, join(dir, 'public', 'media', name));
      const propErrors = validateProps(plan.props, join(dir, 'public'));
      if (propErrors.length) throw new Error(`MarketingAd props for ${ratio} are invalid: ${propErrors.slice(0, 4).join('; ')}`);
      writeJson(join(dir, 'props.json'), plan.props);
      writeJson(join(dir, 'compose-map.json'), { generator: 'media-studio/mvg-compose', base: ctx.spec.id, voiceFirst: true, deliveryProfile: FRAMES[ratio].profile, width: FRAMES[ratio].width, height: FRAMES[ratio].height, timelineSeconds: timeline.durationSeconds, pictureSeconds: timeline.durationSeconds, leadInSeconds: 0, timedGraphics: [], band: plan.layout.uiBand, groups: plan.groups, integrity: plan.integrity });
      writeJson(join(dir, 'gate-segments.json'), { band: plan.layout.uiBand, durationSeconds: timeline.durationSeconds, segments: plan.gateSegments });
      const target = loudnessTarget(ratio, ctx.spec, ctx.brand);
      const mixOut = join(dir, 'mix.wav');
      const mixArgs = buildMixArgs({ lines: plan.lines, sfx: plan.sfxPlan, music: plan.music, durationSec: timeline.durationSeconds, out: mixOut });
      writeJson(join(dir, 'mix-plan.json'), { target, lines: plan.lines, sfx: plan.sfxPlan, music: plan.music, ffmpegArgs: mixArgs });
      writeFileSync(join(dir, 'ad.srt'), toSrt(captionsAll), 'utf8');
      const kit = ctx.flags.kit || join(MODULE_ROOT, '..');
      const silent = join(dir, 'silent.mp4');
      const renderArgs = [join(kit, 'node_modules', '@remotion', 'cli', 'remotion-cli.js'), 'render', 'src/index.ts', 'MarketingAd', silent, `--props=${join(dir, 'props.json')}`, `--public-dir=${join(dir, 'public')}`, '--codec=h264', '--muted', '--crf=17', '--concurrency=2', '--log=error', '--timeout=180000'];
      writeJson(join(dir, 'render-command.json'), { cwd: kit, node: process.execPath, args: renderArgs });
      summary[ratio] = { dir, durationSeconds: timeline.durationSeconds, windows: plan.groups.filter((g) => g.windows).map((g) => ({ beat: g.segments[0], windows: g.windows.length })), sfx: plan.sfxPlan.length, music: !!plan.music, target };
      if (ctx.flags.prepareOnly || ctx.flags.dryRun) { ctx.log(`compose/${ratio}: prepared (no render)`); continue; }
      ctx.log(`compose/${ratio}: rendering picture`);
      const r1 = await run(process.execPath, renderArgs, { timeoutMs: 1800000 });
      if (r1.code !== 0 || !existsSync(silent)) throw new Error(`remotion render failed for ${ratio}: ${(r1.stderr || r1.stdout).trim().split('\n').slice(-3).join(' | ')}`);
      const r2 = await run('ffmpeg', mixArgs);
      if (r2.code !== 0) throw new Error(`audio mix failed for ${ratio}: ${r2.stderr.trim().split('\n').pop()}`);
      const measured = parseLoudnorm((await run('ffmpeg', loudnormMeasureArgs(mixOut, target))).stderr);
      const out = join(dir, 'ad.mp4');
      const r3 = await run('ffmpeg', encodeArgs({ silent, mixWav: mixOut, out, measured, target }));
      if (r3.code !== 0) throw new Error(`encode failed for ${ratio}: ${r3.stderr.trim().split('\n').pop()}`);
      summary[ratio].ad = { path: out, sha256: fileSha(out) };
    }
  }
  recordStage(ctx, 'compose', ctx.flags.prepareOnly || ctx.flags.dryRun ? 'prepared' : 'done', { ratios: summary });
  return summary;
}
